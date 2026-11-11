// language: Dart, file: lib/state/player.dart, target: Android/iOS/desktop, runtime: resong app
// fila + playback via just_audio, notificação/lockscreen via audio_service
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../core/api.dart';
import '../core/models.dart';
import 'audio_fx.dart';
import 'audio_fx_bridge_stub.dart' if (dart.library.js_interop) 'audio_fx_bridge_web.dart';

enum RepeatMode { off, all, one }

enum ShuffleMode { off, normal, smart }

class ResongHandler extends BaseAudioHandler {
  ResongHandler() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        _androidEq = AndroidEqualizer();
        _androidLoudness = AndroidLoudnessEnhancer();
        player = AudioPlayer(
          audioPipeline: AudioPipeline(
            androidAudioEffects: [_androidEq!, _androidLoudness!],
          ),
        );
      } catch (_) {
        _androidEq = null;
        _androidLoudness = null;
        player = AudioPlayer();
      }
    } else {
      player = AudioPlayer();
    }
    _bindPlayerStreams();
  }

  AndroidEqualizer? _androidEq;
  AndroidLoudnessEnhancer? _androidLoudness;
  late final AudioPlayer player;
  final List<Track> tracks = [];
  final math.Random _rng = math.Random();

  final _tracksController = StreamController<List<Track>>.broadcast();
  Stream<List<Track>> get tracksStream => _tracksController.stream;

  final _currentTrackController = StreamController<Track?>.broadcast();
  Stream<Track?> get currentTrackStream => _currentTrackController.stream;

  ShuffleMode shuffleMode = ShuffleMode.off;
  bool get shuffle => shuffleMode != ShuffleMode.off;
  RepeatMode repeatMode = RepeatMode.off;

  final _modeController = StreamController<void>.broadcast();
  Stream<void> get modeStream => _modeController.stream;

  final _sleepController = StreamController<void>.broadcast();
  Stream<void> get sleepStream => _sleepController.stream;

  /// Callback disparado quando a faixa atinge a regra de scrobble (50% ou 4 min).
  void Function(Track track)? onScrobbleEligible;

  /// Callback quando uma nova faixa fica ativa (para UI / playing_now).
  void Function(Track track)? onTrackChanged;

  /// Callback para fila infinita / smart shuffle ao precisar de mais faixas.
  Future<List<Track>> Function(Track seedTrack, Set<String> existingIds)? onNeedMoreTracks;
  bool infiniteQueue = true;
  bool autoSkipEnabled = true;
  bool gaplessEnabled = true;
  bool normalizationEnabled = true;
  int crossfadeSeconds = 0;

  bool _fetchingMore = false;
  bool _retriedCurrentError = false;
  int _activeIndex = 0;
  int _loadGeneration = 0;
  int _completedGen = -1;
  int _loadedSourceGen = -1;
  int _consecutiveLoadFailures = 0;
  bool _loadingQueue = false;
  bool _reloadingCurrent = false;
  bool _explicitSelection = true;
  String? _lastAttemptedUrl;
  String? _loadedSourceTrackId;
  Track? _currentTrack;
  final Set<String> _prewarmedIds = {};

  double _volume = 1.0;
  bool _muted = false;
  double _preMuteVolume = 1.0;
  final _volumeController = StreamController<double>.broadcast();

  double get volume => _muted ? 0.0 : _volume;
  double get unmutedVolume => _volume;
  bool get isMuted => _muted || _volume <= 0.001;
  Stream<double> get volumeStream => _volumeController.stream;
  String? get loadedSourceTrackId => _loadedSourceTrackId;

  Future<void> setVolume(double value) async {
    final clamped = value.clamp(0.0, 1.0).toDouble();
    if (clamped <= 0.001) {
      if (_volume > 0.02) _preMuteVolume = _volume;
      _volume = 0.0;
      _muted = true;
    } else {
      _volume = clamped;
      _preMuteVolume = clamped;
      _muted = false;
    }
    _volumeController.add(volume);
    unawaited(player.setVolume(volume).catchError((Object _) {}));
  }

  Future<void> toggleMute() async {
    if (isMuted) {
      final restored = _preMuteVolume > 0.02 ? _preMuteVolume : 0.7;
      await setVolume(restored);
    } else {
      _preMuteVolume = _volume > 0.02 ? _volume : 0.7;
      _muted = true;
      _volumeController.add(0.0);
      unawaited(player.setVolume(0.0).catchError((Object _) {}));
    }
  }

  // Fisher-Yates shuffle state
  List<int> _shuffleOrder = [];
  int _shuffleCursor = 0;

  // Regra de scrobble real (Achado #2)
  String? _trackedScrobbleId;
  bool _scrobbleSent = false;
  int _accumulatedPlayMs = 0;
  int _lastPositionMs = 0;

  // Auto-skip & Sleep timer
  Timer? _autoSkipTimer;
  Timer? _sleepTimer;
  Timer? _fadeTimer;
  DateTime? _sleepUntil;
  bool _sleepEndOfTrack = false;

  Duration? get sleepRemaining {
    if (_sleepUntil == null) return null;
    final diff = _sleepUntil!.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  bool get sleepAtTrackEnd => _sleepEndOfTrack;
  bool get hasSleepTimer => _sleepUntil != null || _sleepEndOfTrack;

  int get currentIndex => _activeIndex;
  Track? get currentTrack => _currentTrack ?? (tracks.isEmpty ? null : tracks[currentIndex.clamp(0, tracks.length - 1)]);

  /// Fonte do áudio: arquivo baixado (mais rápido, offline) senão o proxy do backend.
  String Function(Track track)? urlOf;

  void _resetScrobbleTracker(Track track) {
    if (_trackedScrobbleId == track.id) return;
    _trackedScrobbleId = track.id;
    _scrobbleSent = false;
    _accumulatedPlayMs = 0;
    _lastPositionMs = 0;
  }

  void _checkScrobbleProgress(Duration pos) {
    final track = _currentTrack;
    if (track == null || _scrobbleSent) return;
    if (_trackedScrobbleId != track.id) _resetScrobbleTracker(track);

    final posMs = pos.inMilliseconds;
    final delta = posMs - _lastPositionMs;
    _lastPositionMs = posMs;
    // Ignora saltos grandes de seek manual; conta só avanço contínuo real.
    if (delta > 0 && delta <= 2500 && player.playing) {
      _accumulatedPlayMs += delta;
    }

    final durMs = track.durationMs ?? player.duration?.inMilliseconds;
    final thresholdMs = durMs != null && durMs > 0
        ? math.min((durMs * 0.5).round(), 240000)
        : 30000;
    if (_accumulatedPlayMs >= math.max(thresholdMs, 10000)) {
      _scrobbleSent = true;
      onScrobbleEligible?.call(track);
    }
  }

  void _setActiveTrack(int index, {bool notifyChange = false}) {
    if (tracks.isEmpty) return;
    _activeIndex = index.clamp(0, tracks.length - 1);
    final track = tracks[_activeIndex];
    final changed = _currentTrack?.id != track.id;
    _currentTrack = track;
    if (changed) {
      _retriedCurrentError = false;
      _resetScrobbleTracker(track);
    }
    _currentTrackController.add(track);
    mediaItem.add(_mediaItemFor(track, _activeIndex));
    if (notifyChange || changed) {
      onTrackChanged?.call(track);
    }
  }

  Future<void> _bindPlayerStreams() async {
    player.playbackEventStream.listen(
      _onPlaybackEvent,
      onError: (Object e, StackTrace _) {
        if (_loadingQueue || _reloadingCurrent || e is PlayerInterruptedException) return;
        unawaited(_retryCurrentTrackSource());
      },
    );
    player.positionStream.listen((pos) {
      if (pos.inMilliseconds > 300) {
        _autoSkipTimer?.cancel();
      }
      _checkScrobbleProgress(pos);
      _checkGaplessPrewarm(pos);
      final state = playbackState.value;
      playbackState.add(state.copyWith(updatePosition: pos));
    });
    player.currentIndexStream.listen((_) => _pushState());
    player.processingStateStream.listen((s) {
      if (s == ProcessingState.ready) {
        _autoSkipTimer?.cancel();
      }
      if (s == ProcessingState.completed) {
        final loadedTag = player.sequenceState.currentSource?.tag;
        final matchesActive = loadedTag == null || loadedTag == _currentTrack?.id;
        if (!_loadingQueue && !_reloadingCurrent && _completedGen != _loadGeneration && matchesActive) {
          _completedGen = _loadGeneration;
          unawaited(onComplete());
        }
      } else {
        _pushState();
      }
    });
    player.playerStateStream.listen((_) => _pushState());
  }

  String _cacheBustUrl(String url) {
    final uri = Uri.parse(url);
    final qp = Map<String, String>.from(uri.queryParameters);
    qp['_r'] = '${DateTime.now().millisecondsSinceEpoch}_$_loadGeneration';
    return uri.replace(queryParameters: qp).toString();
  }

  Future<void> _retryCurrentTrackSource() async {
    if (_retriedCurrentError || _loadingQueue || _reloadingCurrent || tracks.isEmpty) return;
    final gen = _loadGeneration;
    final track = _currentTrack;
    if (track == null) return;
    _retriedCurrentError = true;
    _reloadingCurrent = true;
    _loadedSourceTrackId = null;
    try {
      final freshUrl = _cacheBustUrl(_resolveTrackUrl(track));
      await player.stop().catchError((Object _) {});
      if (gen != _loadGeneration || _currentTrack?.id != track.id) return;
      _lastAttemptedUrl = freshUrl;
      await player.setAudioSource(AudioSource.uri(Uri.parse(freshUrl), tag: track.id));
      if (gen != _loadGeneration || _currentTrack?.id != track.id) return;
      _loadedSourceTrackId = track.id;
      _loadedSourceGen = gen;
      _startPlayback(expectedGen: gen);
    } catch (e) {
      if (e is PlayerInterruptedException || gen != _loadGeneration) return;
      await player.stop().catchError((Object _) {});
      _loadedSourceTrackId = null;
      if (autoSkipEnabled && !_explicitSelection && tracks.length > 1) {
        unawaited(_advance(1, fromCompletion: true));
      }
    } finally {
      _reloadingCurrent = false;
    }
  }

  void _armAutoSkipWatchdog(int expectedGen) {
    _autoSkipTimer?.cancel();
    if (!autoSkipEnabled || _explicitSelection || tracks.length <= 1) return;
    final startTrackId = _currentTrack?.id;
    _autoSkipTimer = Timer(const Duration(seconds: 18), () {
      if (expectedGen != _loadGeneration || _loadingQueue || _reloadingCurrent) return;
      if (_currentTrack?.id != startTrackId) return;
      final stuck = player.position.inMilliseconds < 400 &&
          (player.processingState == ProcessingState.loading ||
              player.processingState == ProcessingState.buffering ||
              player.processingState == ProcessingState.idle);
      if (stuck && player.playing) {
        unawaited(_advance(1, fromCompletion: true));
      }
    });
  }

  void _applyFadeIn() {
    _fadeTimer?.cancel();
    final targetVol = volume;
    if (crossfadeSeconds <= 0 || targetVol <= 0.01) {
      unawaited(player.setVolume(targetVol).catchError((Object _) {}));
      return;
    }
    const steps = 12;
    final stepMs = math.max(50, (crossfadeSeconds * 1000) ~/ steps);
    var step = 1;
    unawaited(player.setVolume(targetVol * 0.08).catchError((Object _) {}));
    _fadeTimer = Timer.periodic(Duration(milliseconds: stepMs), (timer) {
      final liveTarget = volume;
      step++;
      final vol = (liveTarget * (step / steps)).clamp(0.0, 1.0);
      unawaited(player.setVolume(vol).catchError((Object _) {}));
      if (step >= steps) {
        timer.cancel();
      }
    });
  }

  void _onPlaybackEvent(PlaybackEvent event) => _pushState();

  void _pushState() {
    final playing = player.playing;
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: switch (player.processingState) {
          ProcessingState.idle => AudioProcessingState.idle,
          ProcessingState.loading => AudioProcessingState.loading,
          ProcessingState.buffering => AudioProcessingState.buffering,
          ProcessingState.ready => AudioProcessingState.ready,
          ProcessingState.completed => AudioProcessingState.completed,
        },
        playing: playing,
        speed: player.speed,
        updatePosition: player.position,
        queueIndex: tracks.isEmpty ? null : currentIndex,
      ),
    );
  }

  MediaItem _mediaItemFor(Track track, int index) => MediaItem(
        id: track.id,
        title: track.title,
        artist: track.artistLine,
        album: track.album,
        artUri: track.artwork == null ? null : Uri.parse(track.artwork!),
        duration: track.durationMs == null ? null : Duration(milliseconds: track.durationMs!),
        extras: {'index': index, 'track': jsonEncode(track.toJson())},
      );

  bool _isLoadedSourceValidFor(Track target, {int? expectedGen}) {
    if (_loadedSourceTrackId != target.id) return false;
    if (expectedGen != null && _loadedSourceGen != expectedGen) return false;
    final tag = player.sequenceState.currentSource?.tag;
    if (tag != null && tag != target.id) return false;
    return true;
  }

  void _startPlayback({int? expectedGen}) {
    final gen = expectedGen ?? _loadGeneration;
    if (gen != _loadGeneration) return;
    final target = _currentTrack;
    if (target == null) return;
    // Garante que jamais toque um buffer antigo de outra faixa após falha/troca.
    if (!_isLoadedSourceValidFor(target, expectedGen: gen)) {
      if (!_loadingQueue) {
        unawaited(_loadSingleSource(target, gen: gen, autoplay: true));
      }
      return;
    }
    _applyFadeIn();
    _armAutoSkipWatchdog(gen);
    // AudioPlayer.play() no just_audio só completa quando a faixa termina ou pausa.
    unawaited(player.play().catchError((Object _) {}));
    _pushState();
  }

  void _rebuildShuffleOrder(int anchorIndex) {
    if (tracks.isEmpty) {
      _shuffleOrder = [];
      _shuffleCursor = 0;
      return;
    }
    final rest = <int>[
      for (var i = 0; i < tracks.length; i++)
        if (i != anchorIndex) i,
    ];
    // Fisher-Yates shuffle completo sem repetições até zerar a fila.
    for (var i = rest.length - 1; i > 0; i--) {
      final j = _rng.nextInt(i + 1);
      final tmp = rest[i];
      rest[i] = rest[j];
      rest[j] = tmp;
    }
    _shuffleOrder = [anchorIndex, ...rest];
    _shuffleCursor = 0;
  }

  // ---------------------------------------------------------------- fila

  String _resolveTrackUrl(Track track) => urlOf?.call(track) ?? Api.instance.streamUrl(track);

  Future<void> _loadSingleSource(
    Track target, {
    required int gen,
    bool autoplay = true,
    Duration initialPosition = Duration.zero,
    bool fromAutoAdvance = false,
  }) async {
    var primaryUrl = _resolveTrackUrl(target);
    if (primaryUrl == _lastAttemptedUrl) {
      primaryUrl = _cacheBustUrl(primaryUrl);
    }
    _lastAttemptedUrl = primaryUrl;

    _loadingQueue = true;
    _loadedSourceTrackId = null;
    _loadedSourceGen = -1;
    var loaded = false;
    try {
      try {
        await player.setAudioSource(
          AudioSource.uri(Uri.parse(primaryUrl), tag: target.id),
          initialPosition: initialPosition,
        );
        loaded = true;
      } on PlayerInterruptedException {
        return;
      } catch (_) {
        if (gen != _loadGeneration || _currentTrack?.id != target.id) return;
        await player.stop().catchError((Object _) {});
        final fallbackUrl = _cacheBustUrl(Api.instance.streamUrl(target));
        _lastAttemptedUrl = fallbackUrl;
        try {
          await player.setAudioSource(
            AudioSource.uri(Uri.parse(fallbackUrl), tag: target.id),
            initialPosition: initialPosition,
          );
          loaded = true;
        } on PlayerInterruptedException {
          return;
        } catch (_) {
          // Garante áudio antigo completamente morto se a nova faixa falhou ao carregar.
          await player.stop().catchError((Object _) {});
        }
      }
    } on PlayerInterruptedException {
      return;
    } finally {
      if (gen == _loadGeneration) {
        _loadingQueue = false;
      }
    }

    if (gen != _loadGeneration || _currentTrack?.id != target.id) return;

    if (!loaded || (player.sequenceState.currentSource?.tag != null && player.sequenceState.currentSource?.tag != target.id)) {
      _loadedSourceTrackId = null;
      _loadedSourceGen = -1;
      _consecutiveLoadFailures++;
      _pushState();
      if ((fromAutoAdvance || (autoSkipEnabled && !_explicitSelection)) &&
          tracks.length > 1 &&
          _consecutiveLoadFailures < math.min(tracks.length, 4)) {
        unawaited(_advance(1, fromCompletion: true));
      }
      return;
    }

    _consecutiveLoadFailures = 0;
    _loadedSourceTrackId = target.id;
    _loadedSourceGen = gen;

    final idx = tracks.indexWhere((t) => t.id == target.id);
    if (idx >= 0 && _activeIndex != idx) {
      _setActiveTrack(idx);
    }
    _pushState();
    if (autoplay) {
      _startPlayback(expectedGen: gen);
    }
  }

  /// Carrega a lista inteira e toca a faixa `start`.
  Future<void> load(
    List<Track> list, {
    int start = 0,
    bool autoplay = true,
    String Function(Track track)? urlFor,
  }) async {
    if (list.isEmpty) return;
    if (urlFor != null) urlOf = urlFor;

    final gen = ++_loadGeneration;
    _explicitSelection = true;
    _consecutiveLoadFailures = 0;
    _autoSkipTimer?.cancel();
    _fadeTimer?.cancel();
    _retriedCurrentError = false;
    _loadingQueue = true;
    _loadedSourceTrackId = null;
    _loadedSourceGen = -1;

    tracks
      ..clear()
      ..addAll(list);
    final safeStart = start.clamp(0, tracks.length - 1);
    _rebuildShuffleOrder(safeStart);
    _tracksController.add(List.unmodifiable(tracks));
    _setActiveTrack(safeStart, notifyChange: true);
    _pushState();

    // Para imediatamente o áudio anterior (evita HTMLAudio continuar reproduzindo faixa antiga).
    try {
      await player.stop();
    } catch (_) {}
    if (gen != _loadGeneration || tracks.isEmpty) return;

    await _loadSingleSource(tracks[safeStart], gen: gen, autoplay: autoplay);
  }

  Future<void> playTrack(List<Track> list, int index) => load(list, start: index);

  Future<void> replaceUrl(Track track) async {
    if (_currentTrack?.id != track.id || urlOf == null) return;
    final gen = _loadGeneration;
    final pos = player.position;
    final wasPlaying = player.playing;
    await _loadSingleSource(
      track,
      gen: gen,
      autoplay: wasPlaying,
      initialPosition: pos,
    );
  }

  /// Reordena a fila preservando a faixa ativa e o áudio em curso sem interrupção.
  Future<void> reorderQueue(int oldIndex, int targetIndex) async {
    if (oldIndex < 0 || oldIndex >= tracks.length) return;
    final adjustedNew = targetIndex.clamp(0, tracks.length - 1);
    if (adjustedNew == oldIndex) return;

    final oldActive = _activeIndex;
    final moved = tracks.removeAt(oldIndex);
    tracks.insert(adjustedNew, moved);

    var nextActive = oldActive;
    if (oldActive == oldIndex) {
      nextActive = adjustedNew;
    } else if (oldIndex < oldActive && adjustedNew >= oldActive) {
      nextActive = oldActive - 1;
    } else if (oldIndex > oldActive && adjustedNew <= oldActive) {
      nextActive = oldActive + 1;
    }

    _activeIndex = nextActive.clamp(0, tracks.length - 1);
    _rebuildShuffleOrder(_activeIndex);
    _tracksController.add(List.unmodifiable(tracks));
    _setActiveTrack(_activeIndex);
    _pushState();
  }

  /// Remove uma faixa específica da fila.
  Future<void> removeFromQueue(int index) async {
    if (index < 0 || index >= tracks.length) return;
    if (tracks.length == 1) {
      tracks.clear();
      _currentTrack = null;
      _activeIndex = 0;
      _tracksController.add(const []);
      _currentTrackController.add(null);
      await stop();
      return;
    }

    final wasPlaying = player.playing;
    final oldActive = _activeIndex;
    final removedCurrent = index == oldActive;

    tracks.removeAt(index);
    var nextActive = oldActive;
    if (index < oldActive) {
      nextActive = oldActive - 1;
    } else if (removedCurrent) {
      nextActive = oldActive.clamp(0, tracks.length - 1);
    }

    _activeIndex = nextActive;
    _rebuildShuffleOrder(_activeIndex);
    _tracksController.add(List.unmodifiable(tracks));
    _setActiveTrack(_activeIndex, notifyChange: removedCurrent);
    _pushState();

    if (removedCurrent) {
      final gen = ++_loadGeneration;
      _explicitSelection = true;
      _consecutiveLoadFailures = 0;
      _loadingQueue = true;
      _loadedSourceTrackId = null;
      _loadedSourceGen = -1;
      try {
        await player.stop();
      } catch (_) {}
      if (gen != _loadGeneration || _activeIndex >= tracks.length) return;
      await _loadSingleSource(tracks[_activeIndex], gen: gen, autoplay: wasPlaying);
    }
  }

  // ------------------------------------------------------- sleep timer

  void setSleepTimer(Duration? duration, {bool atTrackEnd = false}) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepUntil = null;
    _sleepEndOfTrack = atTrackEnd;

    if (duration != null && !atTrackEnd) {
      _sleepUntil = DateTime.now().add(duration);
      _sleepTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (_sleepUntil == null) {
          t.cancel();
          return;
        }
        if (DateTime.now().isAfter(_sleepUntil!)) {
          t.cancel();
          _sleepTimer = null;
          _sleepUntil = null;
          unawaited(pause());
        }
        _sleepController.add(null);
      });
    }
    _sleepController.add(null);
  }

  void cancelSleepTimer() => setSleepTimer(null);

  // ------------------------------------------------------- controles

  @override
  Future<void> play() async {
    final active = _currentTrack;
    if (active == null) return;
    if (_loadingQueue) return;
    if (!_isLoadedSourceValidFor(active, expectedGen: _loadGeneration)) {
      await _loadSingleSource(active, gen: _loadGeneration, autoplay: true);
      return;
    }
    _startPlayback(expectedGen: _loadGeneration);
  }

  @override
  Future<void> pause() async {
    _autoSkipTimer?.cancel();
    await player.pause();
    _pushState();
  }

  @override
  Future<void> stop() async {
    ++_loadGeneration;
    _loadingQueue = false;
    _loadedSourceTrackId = null;
    _loadedSourceGen = -1;
    _autoSkipTimer?.cancel();
    _fadeTimer?.cancel();
    await player.stop();
    _pushState();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    _lastPositionMs = position.inMilliseconds;
    await player.seek(position);
  }

  @override
  Future<void> skipToNext() => _advance(1);

  @override
  Future<void> skipToPrevious() async {
    if (player.position.inSeconds > 3) {
      await seek(Duration.zero);
      return;
    }
    await _advance(-1);
  }

  Future<void> _advance(int step, {bool fromCompletion = false}) async {
    if (tracks.isEmpty) return;
    if (repeatMode == RepeatMode.one && step > 0) {
      await seek(Duration.zero);
      _startPlayback();
      return;
    }

    final gen = ++_loadGeneration;
    _explicitSelection = !fromCompletion;
    if (!fromCompletion) {
      _consecutiveLoadFailures = 0;
    }
    _autoSkipTimer?.cancel();
    _fadeTimer?.cancel();
    final wasPlaying = player.playing;

    int target;
    if (shuffle && tracks.length > 1) {
      if (_shuffleOrder.length != tracks.length) {
        _rebuildShuffleOrder(currentIndex);
      }
      final nextCursor = _shuffleCursor + step;
      if (nextCursor >= _shuffleOrder.length) {
        if (repeatMode == RepeatMode.all) {
          _rebuildShuffleOrder(currentIndex);
          _shuffleCursor = _shuffleOrder.length > 1 ? 1 : 0;
        } else if ((infiniteQueue || shuffleMode == ShuffleMode.smart) && await _appendRelatedTracks()) {
          _shuffleCursor = nextCursor.clamp(0, _shuffleOrder.length - 1);
        } else {
          await seek(Duration.zero);
          await pause();
          return;
        }
      } else if (nextCursor < 0) {
        _shuffleCursor = repeatMode == RepeatMode.all ? _shuffleOrder.length - 1 : 0;
      } else {
        _shuffleCursor = nextCursor;
      }
      if (gen != _loadGeneration || tracks.isEmpty) return;
      target = _shuffleOrder[_shuffleCursor];
    } else {
      target = currentIndex + step;
      if (target >= tracks.length) {
        if (repeatMode == RepeatMode.all) {
          target = 0;
        } else if (infiniteQueue && await _appendRelatedTracks()) {
          target = currentIndex + 1;
        } else {
          await seek(Duration.zero);
          await pause();
          return;
        }
      }
      if (gen != _loadGeneration || tracks.isEmpty) return;
      if (target < 0) target = repeatMode == RepeatMode.all ? tracks.length - 1 : 0;
    }

    _loadingQueue = true;
    _loadedSourceTrackId = null;
    _loadedSourceGen = -1;
    _setActiveTrack(target, notifyChange: true);
    _pushState();
    // Sempre encerra o source anterior para nunca deixar HTMLAudio reproduzindo faixa antiga.
    try {
      await player.stop();
    } catch (_) {}
    if (gen != _loadGeneration || target >= tracks.length) return;
    await _loadSingleSource(
      tracks[target],
      gen: gen,
      autoplay: fromCompletion || wasPlaying || step != 0,
      fromAutoAdvance: fromCompletion,
    );
  }

  int? _peekNextIndex() {
    if (tracks.length <= 1 || repeatMode == RepeatMode.one) return null;
    if (shuffle) {
      if (_shuffleOrder.length != tracks.length) return null;
      final nextCursor = _shuffleCursor + 1;
      if (nextCursor < _shuffleOrder.length) return _shuffleOrder[nextCursor];
      return repeatMode == RepeatMode.all && _shuffleOrder.isNotEmpty ? _shuffleOrder.first : null;
    }
    final next = currentIndex + 1;
    if (next < tracks.length) return next;
    return repeatMode == RepeatMode.all ? 0 : null;
  }

  void _checkGaplessPrewarm(Duration pos) {
    if (!gaplessEnabled || tracks.length <= 1) return;
    final dur = player.duration ?? (_currentTrack?.durationMs != null ? Duration(milliseconds: _currentTrack!.durationMs!) : null);
    if (dur == null || dur.inSeconds < 15) return;
    final remaining = dur - pos;
    if (remaining > const Duration(seconds: 22) && pos.inMilliseconds < dur.inMilliseconds * 0.65) {
      return;
    }
    final nextIdx = _peekNextIndex();
    if (nextIdx == null || nextIdx < 0 || nextIdx >= tracks.length) return;
    final nextTrack = tracks[nextIdx];
    final key = '${nextTrack.id}@$_activeIndex';
    if (_prewarmedIds.contains(key)) return;
    if (_prewarmedIds.length > 40) _prewarmedIds.clear();
    _prewarmedIds.add(key);

    final resolvedUrl = _resolveTrackUrl(nextTrack);
    if (resolvedUrl.startsWith('http')) {
      unawaited(Api.instance.prewarmStream(nextTrack));
      prewarmWebAudioUrl(resolvedUrl);
    }
  }

  Future<void> applyAudioEffects(AudioFxState fx) async {
    gaplessEnabled = fx.gapless;
    normalizationEnabled = fx.normalization;
    if ((player.speed - fx.speed).abs() > 0.001) {
      unawaited(player.setSpeed(fx.speed).catchError((Object _) {}));
    }

    final eq = _androidEq;
    if (eq != null) {
      try {
        await eq.setEnabled(fx.enabled);
        final params = await eq.parameters;
        const targets = [60.0, 230.0, 910.0, 3600.0, 14000.0];
        for (final band in params.bands) {
          final freq = band.centerFrequency;
          var bestIdx = 0;
          var bestDist = 999999.0;
          for (var i = 0; i < targets.length; i++) {
            final d = (freq - targets[i]).abs();
            if (d < bestDist) {
              bestDist = d;
              bestIdx = i;
            }
          }
          var gain = fx.bands[bestIdx];
          if (bestIdx == 0 && fx.bassBoost > 0) {
            gain += fx.bassBoost * 4.5;
          }
          await band.setGain(gain.clamp(params.minDecibels, params.maxDecibels));
        }
      } catch (_) {}
    }

    final loud = _androidLoudness;
    if (loud != null) {
      try {
        await loud.setEnabled(fx.normalization);
        await loud.setTargetGain(fx.normalization ? 0.35 : 0.0);
      } catch (_) {}
    }
  }

  Future<bool> _appendRelatedTracks() async {
    if (_fetchingMore || tracks.isEmpty) return false;
    _fetchingMore = true;
    try {
      final seed = tracks.last;
      final existing = {for (final t in tracks) t.id};
      final List<Track> candidates;
      if (onNeedMoreTracks != null) {
        candidates = await onNeedMoreTracks!(seed, existing);
      } else {
        final query = seed.artists.isNotEmpty ? seed.artists.first : seed.title;
        final res = await Api.instance.search(query, limit: 12);
        candidates = res.tracks.where((t) => !existing.contains(t.id)).take(5).toList();
      }
      if (candidates.isEmpty) return false;
      final prevLen = tracks.length;
      tracks.addAll(candidates);
      for (var i = prevLen; i < tracks.length; i++) {
        _shuffleOrder.add(i);
      }
      _tracksController.add(List.unmodifiable(tracks));
      return true;
    } catch (_) {
      return false;
    } finally {
      _fetchingMore = false;
    }
  }

  Future<void> onComplete() async {
    if (_sleepEndOfTrack) {
      _sleepEndOfTrack = false;
      _sleepController.add(null);
      await seek(Duration.zero);
      await pause();
      return;
    }
    if (repeatMode == RepeatMode.one) {
      await seek(Duration.zero);
      _startPlayback();
      return;
    }
    await _advance(1, fromCompletion: true);
  }

  void toggleShuffle() {
    shuffleMode = shuffleMode == ShuffleMode.off ? ShuffleMode.normal : ShuffleMode.off;
    if (shuffle) _rebuildShuffleOrder(currentIndex);
    _modeController.add(null);
  }

  /// Mantém alternância simples Ligado/Desligado sem terceiro modo extra.
  void cycleShuffle() => toggleShuffle();

  void cycleRepeat() {
    repeatMode = switch (repeatMode) {
      RepeatMode.off => RepeatMode.all,
      RepeatMode.all => RepeatMode.one,
      RepeatMode.one => RepeatMode.off,
    };
    _modeController.add(null);
  }

  Future<void> jumpTo(int index) async {
    if (index < 0 || index >= tracks.length) return;
    final gen = ++_loadGeneration;
    _explicitSelection = true;
    _consecutiveLoadFailures = 0;
    _loadingQueue = true;
    _loadedSourceTrackId = null;
    _loadedSourceGen = -1;
    _autoSkipTimer?.cancel();
    _fadeTimer?.cancel();
    _setActiveTrack(index, notifyChange: true);
    if (shuffle) {
      final pos = _shuffleOrder.indexOf(index);
      if (pos >= 0) _shuffleCursor = pos;
    }
    _pushState();
    try {
      await player.stop();
    } catch (_) {}
    if (gen != _loadGeneration || index >= tracks.length) return;
    await _loadSingleSource(tracks[index], gen: gen, autoplay: true);
  }

  @override
  Future<void> onTaskRemoved() async {
    _autoSkipTimer?.cancel();
    _sleepTimer?.cancel();
    _fadeTimer?.cancel();
    await player.stop();
    await super.onTaskRemoved();
  }
}
