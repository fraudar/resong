// language: Dart, file: lib/state/library.dart, target: mobile-first + desktop, runtime: resong app
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api.dart';
import '../core/audio_tags.dart';
import '../core/local_image.dart';
import '../core/models.dart';
import '../core/palette.dart';
import 'local_downloads_platform.dart';
import 'playlist_cover_store.dart';
import 'providers.dart';
import 'settings.dart';

final apiProvider = Provider<Api>((ref) => Api.instance);

// ------------------------------------------------------------------ home

final homeProvider = FutureProvider<HomeFeed>((ref) => Api.instance.home());

// ----------------------------------------------------------------- busca

class SearchState {
  const SearchState({this.query = '', this.results, this.suggestions = const [], this.loading = false});
  final String query;
  final SearchResults? results;
  final List<String> suggestions;
  final bool loading;

  SearchState copyWith({String? query, SearchResults? results, List<String>? suggestions, bool? loading}) => SearchState(
        query: query ?? this.query,
        results: results ?? this.results,
        suggestions: suggestions ?? this.suggestions,
        loading: loading ?? this.loading,
      );
}

class SearchController extends StateNotifier<SearchState> {
  SearchController() : super(const SearchState());
  Timer? _debounce;
  int _epoch = 0;

  void changed(String raw) {
    final q = raw.trim();
    state = state.copyWith(query: raw, loading: q.isNotEmpty);
    _debounce?.cancel();
    if (q.isEmpty) {
      state = const SearchState();
      return;
    }
    final token = ++_epoch;
    _debounce = Timer(const Duration(milliseconds: 320), () => _run(q, token));
  }

  Future<void> _run(String q, int token) async {
    try {
      final data = await Future.wait([
        Api.instance.search(q),
        Api.instance.suggest(q),
      ]);
      if (token != _epoch) return;
      state = state.copyWith(
        results: data[0] as SearchResults,
        suggestions: (data[1] as List<String>),
        loading: false,
      );
    } catch (_) {
      if (token != _epoch) return;
      state = state.copyWith(loading: false);
    }
  }

  void clear() {
    _debounce?.cancel();
    _epoch++;
    state = const SearchState();
  }
}

final searchProvider = StateNotifierProvider<SearchController, SearchState>((ref) => SearchController());

// ------------------------------------------------------------ biblioteca

class FavoritesController extends StateNotifier<List<Track>> {
  FavoritesController() : super(const []);

  Future<void> load() async {
    try {
      state = await Api.instance.favorites();
    } catch (_) {}
  }

  Future<bool> contains(String id) async {
    if (state.any((t) => t.id == id)) return true;
    await load();
    return state.any((t) => t.id == id);
  }

  Future<void> toggle(Track track) async {
    if (state.any((t) => t.id == track.id)) {
      state = state.where((t) => t.id != track.id).toList();
      await Api.instance.removeFavorite(track.id);
    } else {
      state = [track, ...state];
      await Api.instance.addFavorite(track);
    }
  }

  Future<void> clear() async {
    final current = List<Track>.from(state);
    state = const [];
    for (final t in current) {
      try {
        await Api.instance.removeFavorite(t.id);
      } catch (_) {}
    }
  }
}

final favoritesProvider = StateNotifierProvider<FavoritesController, List<Track>>((ref) {
  final c = FavoritesController()..load();
  return c;
});

class RecentController extends StateNotifier<List<Track>> {
  RecentController() : super(const []);

  Future<void> load() async {
    try {
      state = await Api.instance.recent();
    } catch (_) {}
  }

  Future<void> push(Track track) async {
    state = [track, ...state.where((t) => t.id != track.id)].take(40).toList();
    await Api.instance.addRecent(track);
  }

  Future<void> clear() async {
    state = const [];
    try {
      await Api.instance.clearRecent();
    } catch (_) {}
  }
}

final recentProvider = StateNotifierProvider<RecentController, List<Track>>((ref) {
  final c = RecentController()..load();
  return c;
});

class PlaylistsController extends StateNotifier<List<PlaylistRecord>> {
  PlaylistsController() : super(const []);

  Future<void> load() async {
    try {
      state = await Api.instance.playlists();
      await onPlaylistsLoaded?.call(state);
    } catch (_) {}
  }

  Future<void> Function(List<PlaylistRecord> playlists)? onPlaylistsLoaded;

  Future<PlaylistRecord> create(String name, {String description = ''}) async {
    final p = await Api.instance.createPlaylist(name, description: description);
    state = [p, ...state];
    return p;
  }

  Future<void> rename(String id, String name) async {
    await Api.instance.renamePlaylist(id, name: name);
    await load();
  }

  Future<void> remove(String id) async {
    state = state.where((p) => p.id != id).toList();
    await deleteLocalPlaylistCover(id);
    onCoverRemoved?.call(id);
    await Api.instance.deletePlaylist(id);
  }

  void Function(String id)? onCoverRemoved;

  Future<void> addTrack(String playlistId, Track track) async {
    await Api.instance.addToPlaylist(playlistId, track);
    await load();
  }

  Future<void> removeTrack(String playlistId, String trackId) async {
    await Api.instance.removeFromPlaylist(playlistId, trackId);
    await load();
  }

  Future<void> reorder(String playlistId, List<String> order) async {
    await Api.instance.reorderPlaylist(playlistId, order);
    await load();
  }
}

class PlaylistCoversController extends StateNotifier<Map<String, Uint8List>> {
  PlaylistCoversController() : super(const {});

  final Set<String> _loadedIds = {};

  Future<void> ensureLoaded(Iterable<String> playlistIds) async {
    final next = Map<String, Uint8List>.from(state);
    var changed = false;
    for (final id in playlistIds) {
      if (_loadedIds.contains(id)) continue;
      _loadedIds.add(id);
      final bytes = await readLocalPlaylistCover(id);
      if (bytes != null && bytes.isNotEmpty) {
        next[id] = bytes;
        changed = true;
      }
    }
    if (changed && mounted) {
      state = next;
    }
  }

  /// Salva capa personalizada localmente (arquivo no mobile/desktop ou IndexedDB no Web) sem passar pela VPS.
  Future<bool> setCover(String playlistId, Uint8List rawBytes) async {
    final compact = await compressLocalCoverBytes(rawBytes, targetWidth: 320);
    if (compact == null || compact.isEmpty) return false;
    await writeLocalPlaylistCover(playlistId, compact);
    _loadedIds.add(playlistId);
    if (mounted) {
      state = {...state, playlistId: compact};
    }
    return true;
  }

  Future<void> removeCover(String playlistId) async {
    await deleteLocalPlaylistCover(playlistId);
    _loadedIds.add(playlistId);
    if (mounted && state.containsKey(playlistId)) {
      final next = Map<String, Uint8List>.from(state)..remove(playlistId);
      state = next;
    }
  }

  void forgetInMemory(String playlistId) {
    if (mounted && state.containsKey(playlistId)) {
      final next = Map<String, Uint8List>.from(state)..remove(playlistId);
      state = next;
    }
  }
}

final playlistCoversProvider = StateNotifierProvider<PlaylistCoversController, Map<String, Uint8List>>(
  (ref) => PlaylistCoversController(),
);

final playlistsProvider = StateNotifierProvider<PlaylistsController, List<PlaylistRecord>>((ref) {
  final c = PlaylistsController();
  c.onPlaylistsLoaded = (list) => ref.read(playlistCoversProvider.notifier).ensureLoaded([
        for (final p in list) p.id,
      ]);
  c.onCoverRemoved = (id) => ref.read(playlistCoversProvider.notifier).forgetInMemory(id);
  c.load();
  return c;
});

// --------------------------------------------------------------- downloads locais

/// URL de reprodução para uma faixa: arquivo local salvo se existente, senão stream do backend.
String resolvePlaybackUrl(Track track, List<DownloadRecord> downloads) {
  for (final d in downloads) {
    if (d.trackId == track.id && d.hasPlayableLocal) {
      final localUri = playableUriForLocal(d.localPath);
      if (localUri != null) return localUri;
    }
  }
  return Api.instance.streamUrl(track);
}

class DownloadsController extends StateNotifier<List<DownloadRecord>> {
  DownloadsController(this._ref) : super(const []);

  final Ref _ref;
  static const _prefsKey = 'resong_local_downloads_v1';
  static const _maxConcurrent = 2;

  final List<String> _pending = [];
  final Set<String> _active = {};
  final Map<String, CancelToken> _tokens = {};
  final Set<String> _cancelledIds = {};
  bool _loaded = false;
  Future<void>? _loadInflight;

  Future<void> load() => _loadInflight ??= _doLoad().whenComplete(() => _loadInflight = null);

  Future<void> _doLoad() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) {
        _loaded = true;
        return;
      }
      final list = (jsonDecode(raw) as List?)?.whereType<Map>().map((m) {
            return DownloadRecord.fromJson(m.cast<String, dynamic>());
          }).toList() ??
          const <DownloadRecord>[];

      final verified = <DownloadRecord>[];
      var dirty = false;
      for (final d in list) {
        if (d.status == 'queued' || d.status == 'downloading') {
          verified.add(d.copyWith(status: 'error', progress: 0, error: 'Interrompido ao fechar o app'));
          dirty = true;
        } else if (d.isDone && (d.localPath ?? '').isNotEmpty) {
          final exists = await localFileExists(d.localPath);
          if (exists) {
            verified.add(d);
          } else {
            dirty = true;
          }
        } else {
          verified.add(d);
        }
      }
      state = verified;
      _loaded = true;
      if (dirty) await _persist();
    } catch (_) {
      _loaded = true;
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode([for (final d in state) d.toJson()]));
    } catch (_) {}
  }

  Future<void> request(Track track) async {
    if (!_loaded) await load();
    final existing = forTrack(track.id);
    if (existing != null &&
        (existing.status == 'queued' ||
            existing.status == 'downloading' ||
            (existing.isDone && (existing.hasPlayableLocal || isWebDownloadPlatform)))) {
      return;
    }

    _cancelledIds.remove(track.id);
    final record = DownloadRecord(
      trackId: track.id,
      track: track,
      status: 'queued',
      progress: 0,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    _upsert(record);
    await _persist();
    if (!_pending.contains(track.id) && !_active.contains(track.id)) {
      _pending.add(track.id);
    }
    _pump();
  }

  Future<void> retry(String trackId) async {
    final existing = forTrack(trackId);
    if (existing == null) return;
    _cancelledIds.remove(trackId);
    _upsert(existing.copyWith(status: 'queued', progress: 0, clearError: true));
    await _persist();
    if (!_pending.contains(trackId) && !_active.contains(trackId)) {
      _pending.add(trackId);
    }
    _pump();
  }

  Future<void> cancel(String trackId) async {
    _cancelledIds.add(trackId);
    _pending.remove(trackId);
    _tokens[trackId]?.cancel('cancelado');
    _tokens.remove(trackId);
    final existing = forTrack(trackId);
    if (existing != null && !existing.isDone) {
      _upsert(existing.copyWith(status: 'error', progress: 0, error: 'Cancelado'));
      await _persist();
    }
  }

  Future<void> remove(String trackId) async {
    await cancel(trackId);
    final existing = forTrack(trackId);
    if (existing?.localPath != null) {
      await deleteLocalFile(existing!.localPath);
    }
    state = state.where((d) => d.trackId != trackId).toList();
    await _persist();
  }

  DownloadRecord? forTrack(String trackId) {
    for (final d in state) {
      if (d.trackId == trackId) return d;
    }
    return null;
  }

  String playbackUrlFor(Track track) => resolvePlaybackUrl(track, state);

  @visibleForTesting
  void debugSetRecords(List<DownloadRecord> records) {
    state = records;
  }

  void _upsert(DownloadRecord record) {
    final idx = state.indexWhere((d) => d.trackId == record.trackId);
    if (idx >= 0) {
      final copy = List<DownloadRecord>.from(state);
      copy[idx] = record;
      state = copy;
    } else {
      state = [record, ...state];
    }
  }

  void _update(String trackId, DownloadRecord Function(DownloadRecord cur) transform) {
    final idx = state.indexWhere((d) => d.trackId == trackId);
    if (idx < 0) return;
    final copy = List<DownloadRecord>.from(state);
    copy[idx] = transform(copy[idx]);
    state = copy;
  }

  void _pump() {
    while (_active.length < _maxConcurrent && _pending.isNotEmpty) {
      final id = _pending.removeAt(0);
      final rec = forTrack(id);
      if (rec == null) continue;
      _active.add(id);
      unawaited(
        _runJob(rec).whenComplete(() {
          _active.remove(id);
          _tokens.remove(id);
          _pump();
        }),
      );
    }
  }

  Future<void> _runJob(DownloadRecord job) async {
    final token = CancelToken();
    _tokens[job.trackId] = token;
    _update(job.trackId, (c) => c.copyWith(status: 'downloading', progress: 0.02, clearError: true));

    try {
      final detailed = await Api.instance.trackDetail(job.trackId);
      if (_cancelledIds.contains(job.trackId) || token.isCancelled) return;
      final track = _mergeTrack(job.track, detailed);
      _update(job.trackId, (c) => c.copyWith(track: track));

      if (isWebDownloadPlatform) {
        final url = Api.instance.transientWebDownloadUrl(track);
        final bytes = await _downloadWithRetry(
          [url],
          cancelToken: token,
          onProgress: (p) => _update(job.trackId, (c) => c.copyWith(progress: (p * 0.96).clamp(0.02, 0.96))),
        );
        if (_cancelledIds.contains(job.trackId) || token.isCancelled) return;
        final fileName = '${_sanitizeFilename(_displayName(track))}.m4a';
        final saved = await saveTaggedAudioToDevice(
          bytes: bytes,
          fileName: fileName,
          mimeType: 'audio/mp4',
          customFolder: '',
        );
        _update(
          job.trackId,
          (c) => c.copyWith(
            status: 'done',
            progress: 1.0,
            localPath: saved.uriOrPath,
            displayPath: saved.displayPath,
            fileSize: saved.size,
            clearError: true,
          ),
        );
        await _persist();
        return;
      }

      // Fluxo nativo (Android/iOS/Desktop): resolve stream progressivo, baixa na pasta local e embute tags em Dart puro
      final resolved = await Api.instance.resolveProgressiveDownload(track);
      if (_cancelledIds.contains(job.trackId) || token.isCancelled) return;

      final proxyUrl = Api.instance.progressiveStreamUrl(track);
      final rawBytes = await _downloadWithRetry(
        [resolved.url, proxyUrl],
        cancelToken: token,
        onProgress: (p) => _update(job.trackId, (c) => c.copyWith(progress: (p * 0.88).clamp(0.02, 0.88))),
      );
      if (_cancelledIds.contains(job.trackId) || token.isCancelled) return;
      if (rawBytes.length < 1024) {
        throw Exception('Arquivo de áudio vazio');
      }

      _update(job.trackId, (c) => c.copyWith(progress: 0.92));
      Uint8List? coverBytes;
      if ((track.artwork ?? '').isNotEmpty) {
        try {
          coverBytes = await Api.instance.downloadBytes(
            track.artwork!,
            cancelToken: token,
            timeout: const Duration(seconds: 15),
          );
        } catch (_) {
          // Capa é opcional para concluir o download offline
        }
      }
      if (_cancelledIds.contains(job.trackId) || token.isCancelled) return;

      final ext = _normalizeExt(resolved.ext, rawBytes);
      final taggedBytes = AudioTags.write(
        audioBytes: rawBytes,
        ext: ext,
        track: track,
        coverBytes: coverBytes,
      );
      _update(job.trackId, (c) => c.copyWith(progress: 0.97));

      final folder = _ref.read(settingsProvider).downloadFolder;
      final fileName = '${_sanitizeFilename(_displayName(track))}.$ext';
      final saved = await saveTaggedAudioToDevice(
        bytes: taggedBytes,
        fileName: fileName,
        mimeType: ext == 'mp3' ? 'audio/mpeg' : 'audio/mp4',
        customFolder: folder,
      );

      _update(
        job.trackId,
        (c) => c.copyWith(
          status: 'done',
          progress: 1.0,
          localPath: saved.uriOrPath,
          displayPath: saved.displayPath,
          fileSize: saved.size,
          clearError: true,
        ),
      );
      await _persist();
    } on DioException catch (e) {
      if (CancelToken.isCancel(e) || _cancelledIds.contains(job.trackId)) return;
      _update(
        job.trackId,
        (c) => c.copyWith(
          status: 'error',
          progress: 0,
          error: e.message ?? 'Falha na rede ao baixar',
        ),
      );
      await _persist();
    } catch (e) {
      if (_cancelledIds.contains(job.trackId)) return;
      _update(
        job.trackId,
        (c) => c.copyWith(
          status: 'error',
          progress: 0,
          error: e.toString().replaceFirst('Exception: ', ''),
        ),
      );
      await _persist();
    }
  }

  Future<Uint8List> _downloadWithRetry(
    List<String> candidateUrls, {
    required CancelToken cancelToken,
    required void Function(double progress) onProgress,
  }) async {
    Object? lastErr;
    for (var attempt = 0; attempt < 3; attempt++) {
      final url = candidateUrls[attempt < candidateUrls.length ? attempt : candidateUrls.length - 1];
      try {
        return await Api.instance.downloadBytes(
          url,
          cancelToken: cancelToken,
          onProgress: (received, total) {
            if (total > 0) onProgress(received / total);
          },
        );
      } on DioException catch (e) {
        if (CancelToken.isCancel(e)) rethrow;
        lastErr = e;
      } catch (e) {
        lastErr = e;
      }
      if (attempt < 2 && !cancelToken.isCancelled) {
        await Future<void>.delayed(Duration(milliseconds: 600 * (attempt + 1)));
      }
    }
    throw lastErr ?? Exception('Falha ao baixar faixa');
  }

  static Track _mergeTrack(Track base, Track? enriched) {
    if (enriched == null) return base;
    return Track(
      id: base.id,
      source: base.source,
      title: enriched.title.isNotEmpty ? enriched.title : base.title,
      artists: enriched.artists.isNotEmpty ? enriched.artists : base.artists,
      album: (enriched.album ?? '').isNotEmpty ? enriched.album : base.album,
      artwork: (enriched.artwork ?? '').isNotEmpty ? enriched.artwork : base.artwork,
      durationMs: enriched.durationMs ?? base.durationMs,
      explicit: enriched.explicit,
      extra: {...enriched.extra, ...base.extra},
    );
  }

  static String _displayName(Track t) =>
      t.artists.isNotEmpty ? '${t.artists.first} - ${t.title}' : t.title;

  static String _sanitizeFilename(String raw) {
    final cleaned = raw
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[. ]+$'), '')
        .trim();
    if (cleaned.isEmpty) return 'resong';
    return cleaned.length > 120 ? cleaned.substring(0, 120) : cleaned;
  }

  static String _normalizeExt(String hintedExt, Uint8List bytes) {
    if (bytes.length >= 8 && bytes[4] == 0x66 && bytes[5] == 0x74 && bytes[6] == 0x79 && bytes[7] == 0x70) {
      return 'm4a';
    }
    if (bytes.length >= 3 && bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33) {
      return 'mp3';
    }
    final clean = hintedExt.toLowerCase().trim();
    if (clean == 'mp3' || clean == 'm4a' || clean == 'flac' || clean == 'webm') return clean;
    return 'm4a';
  }
}

final downloadsProvider = StateNotifierProvider<DownloadsController, List<DownloadRecord>>((ref) {
  final c = DownloadsController(ref)..load();
  return c;
});

final shellTabProvider = StateProvider<int>((ref) => 0);
final libraryTabProvider = StateProvider<int>((ref) => 0);

/// Abre diretamente Biblioteca > aba Downloads de qualquer rota do app.
void openDownloadsTab(BuildContext context, WidgetRef ref) {
  ref.read(libraryTabProvider.notifier).state = 2;
  ref.read(shellTabProvider.notifier).state = 2;
  Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
  final nav = Navigator.maybeOf(context);
  if (nav != null && nav != Navigator.of(context, rootNavigator: true)) {
    nav.popUntil((route) => route.isFirst);
  }
}

// ------------------------------------------------- cor dominante da capa + tema

class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController() : super(ThemeMode.dark) {
    _load();
  }

  static const _prefKey = 'resong_theme_mode';

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey);
      if (saved == 'light') {
        state = ThemeMode.light;
      } else if (saved == 'black') {
        state = ThemeMode.dark;
      }
    } catch (_) {}
  }

  Future<void> setMode(ThemeMode mode) async {
    if (state == mode) return;
    state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, mode == ThemeMode.light ? 'light' : 'black');
    } catch (_) {}
  }

  Future<void> toggle() => setMode(state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
}

final themeModeProvider = StateNotifierProvider<ThemeModeController, ThemeMode>((ref) => ThemeModeController());

class CurrentPaletteController extends StateNotifier<ArtworkPalette> {
  CurrentPaletteController() : super(ArtworkPalette.fallback);
  String? _lastUrl;

  Future<void> syncForUrl(String? url) async {
    final normalized = (url ?? '').trim();
    if (normalized == (_lastUrl ?? '')) return;
    _lastUrl = normalized;

    if (normalized.isEmpty) {
      state = ArtworkPalette.fallback;
      return;
    }

    final cached = cachedPaletteForArtwork(normalized);
    if (cached != null) {
      state = cached;
      return;
    }

    final palette = await paletteFromArtwork(normalized);
    if (_lastUrl == normalized) {
      state = palette;
    }
  }
}

final currentPaletteProvider = StateNotifierProvider<CurrentPaletteController, ArtworkPalette>(
  (ref) => CurrentPaletteController(),
);

final artworkPaletteProvider = FutureProvider.family<ArtworkPalette, String?>((ref, url) => paletteFromArtwork(url));

ArtworkPalette watchCollectionPalette(WidgetRef ref, String? artworkUrl) {
  final current = ref.watch(currentPaletteProvider);
  final async = ref.watch(artworkPaletteProvider(artworkUrl));
  return async.valueOrNull ?? cachedPaletteForArtwork(artworkUrl) ?? current;
}

final accentProvider = Provider<Color>((ref) {
  final palette = ref.watch(currentPaletteProvider);
  final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
  return palette.accentFor(isDark);
});

/// Auxiliar para disparar extração de paleta sempre que a faixa atual mudar.
final paletteSyncProvider = Provider<void>((ref) {
  final track = ref.watch(currentTrackProvider);
  final url = track?.artwork;
  Future.microtask(() => ref.read(currentPaletteProvider.notifier).syncForUrl(url));
});
