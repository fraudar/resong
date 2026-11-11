// language: Dart, file: lib/state/providers.dart, target: mobile-first + desktop, runtime: resong app
import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models.dart';
import 'player.dart';

ResongHandler? _handler;

/// Única instância do handler — a mesma usada pelo audio_service e pela UI.
ResongHandler handlerInstance() => _handler ??= ResongHandler();

final handlerProvider = Provider<ResongHandler>((ref) => handlerInstance());

/// Streams reativos do player para manter mini-player, listas, capas e ondas em tempo real.
final mediaItemProvider = StreamProvider<MediaItem?>((ref) => ref.watch(handlerProvider).mediaItem);

final _currentTrackStreamProvider = StreamProvider<Track?>((ref) => ref.watch(handlerProvider).currentTrackStream);

final playbackStateProvider = StreamProvider<PlaybackState>((ref) => ref.watch(handlerProvider).playbackState);

final queueTracksProvider = StreamProvider<List<Track>>((ref) => ref.watch(handlerProvider).tracksStream);

final playerModeProvider = StreamProvider<void>((ref) => ref.watch(handlerProvider).modeStream);

final sleepTimerProvider = StreamProvider<void>((ref) => ref.watch(handlerProvider).sleepStream);

final currentTrackProvider = Provider<Track?>((ref) {
  final streamed = ref.watch(_currentTrackStreamProvider).valueOrNull;
  ref.watch(mediaItemProvider);
  return streamed ?? ref.watch(handlerProvider).currentTrack;
});

final isPlayingProvider = Provider<bool>((ref) {
  final pb = ref.watch(playbackStateProvider).valueOrNull;
  return pb?.playing ?? ref.watch(handlerProvider).playbackState.value.playing;
});
