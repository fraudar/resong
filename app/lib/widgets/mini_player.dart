// language: Dart, file: lib/widgets/mini_player.dart, target: mobile-first + desktop, runtime: resong app
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons_flutter/solar_icons_flutter.dart';

import '../core/format.dart';
import '../core/theme.dart';
import '../screens/player_screen.dart';
import '../state/library.dart';
import '../state/player.dart';
import '../state/providers.dart';
import '../state/settings.dart';
import 'artwork.dart';
import 'flight.dart';
import 'glass.dart';

/// Barra compacta flutuante em vidro fosco acima da nav:
/// capa, título, artista, play/pause, próxima e fio de progresso no topo.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.watch(handlerProvider);
    final track = ref.watch(currentTrackProvider);
    if (track == null) return const SizedBox.shrink();

    final colors = context.colors;
    final palette = ref.watch(currentPaletteProvider);
    final accent = palette.accentFor(colors.isDark);
    final playing = ref.watch(isPlayingProvider);
    final waveEnabled = ref.watch(settingsProvider.select((s) => s.waveEffectsEnabled));

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        final vx = details.primaryVelocity ?? 0;
        if (vx < -280) {
          handler.skipToNext();
        } else if (vx > 280) {
          handler.skipToPrevious();
        }
      },
      child: GlassSurface(
        borderRadius: BorderRadius.circular(22),
        blur: 26,
        tint: palette.backdropFor(colors.isDark),
        tintStrength: 0.42,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => PlayerScreen.open(context, ref, initialTrack: track),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _TopProgressLine(handler: handler, accent: accent, isDark: colors.isDark),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 7, 8, 7),
                child: Row(
                  children: [
                    FlightElement(
                      tag: 'artwork:${track.id}',
                      borderRadius: BorderRadius.circular(11),
                      enabled: waveEnabled,
                      child: Artwork(url: track.artwork, size: 38, radius: 11, tone: accent),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: colors.textPrimary,
                              letterSpacing: -0.1,
                            ),
                          ),
                          Text(
                            track.artistLine,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                      iconSize: 20,
                      tooltip: playing ? 'Pausar' : 'Tocar',
                      icon: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: Icon(
                          playing ? SolarIconsBold.pause : SolarIconsBold.play,
                          key: ValueKey(playing),
                          color: colors.textPrimary,
                        ),
                      ),
                      onPressed: playing ? handler.pause : handler.play,
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                      iconSize: 20,
                      tooltip: 'Próxima',
                      icon: Icon(SolarIconsBold.forward, color: colors.textPrimary),
                      onPressed: handler.skipToNext,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopProgressLine extends StatelessWidget {
  const _TopProgressLine({
    required this.handler,
    required this.accent,
    required this.isDark,
  });

  final ResongHandler handler;
  final Color accent;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: handler.player.positionStream,
      initialData: handler.player.position,
      builder: (context, snapshot) {
        final total = handler.player.duration;
        final position = snapshot.data ?? Duration.zero;
        final value = total == null || total.inMilliseconds == 0
            ? 0.0
            : (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
        final active = isDark
            ? Color.lerp(accent, Colors.white, 0.48)!
            : accent;
        return SizedBox(
          height: 2.2,
          child: LinearProgressIndicator(
            value: value,
            minHeight: 2.2,
            backgroundColor: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
            valueColor: AlwaysStoppedAnimation<Color>(active),
          ),
        );
      },
    );
  }
}

String formatPosition(Duration d) => formatDuration(d.inMilliseconds);
