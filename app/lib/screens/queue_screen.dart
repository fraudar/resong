// language: Dart, file: lib/screens/queue_screen.dart, target: mobile-first + desktop, runtime: resong app
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons_flutter/solar_icons_flutter.dart';

import '../core/format.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../state/library.dart';
import '../state/providers.dart';
import '../state/settings.dart';
import '../widgets/artwork.dart';
import '../widgets/flight.dart';
import '../widgets/glass.dart';
import '../widgets/liquid_wave_backdrop.dart';

/// Tela cheia de fila com arrasto para reordenar, remoção e contador `tocando i/N`.
class QueueScreen extends ConsumerWidget {
  const QueueScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(builder: (_) => const QueueScreen()),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final handler = ref.watch(handlerProvider);
    final currentTrack = ref.watch(currentTrackProvider);
    final tracks = ref.watch(queueTracksProvider).valueOrNull ?? List<Track>.unmodifiable(handler.tracks);
    final palette = ref.watch(currentPaletteProvider);
    final accent = palette.accentFor(colors.isDark);
    final playing = ref.watch(isPlayingProvider);
    final waveEnabled = ref.watch(settingsProvider.select((s) => s.waveEffectsEnabled));

    final activeIdx = tracks.isEmpty ? 0 : handler.currentIndex.clamp(0, tracks.length - 1);
    final counterText = tracks.isEmpty ? 'Fila vazia' : 'Fila · tocando ${activeIdx + 1}/${tracks.length}';

    return Scaffold(
      backgroundColor: colors.bg,
      body: LiquidWaveBackdrop(
        palette: palette,
        intense: false,
        isPlaying: playing,
        animateAmbient: waveEnabled,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    child: Row(
                      children: [
                        GlassCircleButton(
                          icon: SolarIconsBold.altArrowLeft,
                          size: 40,
                          iconSize: 20,
                          tooltip: 'Voltar',
                          onTap: () => Navigator.maybePop(context),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                counterText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              if (currentTrack != null)
                                Text(
                                  '${currentTrack.title} • ${currentTrack.artistLine}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 12.5, color: colors.textSecondary),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: tracks.isEmpty
                        ? Center(
                            child: Text(
                              'Nenhuma faixa na fila',
                              style: TextStyle(fontSize: 14, color: colors.textSecondary),
                            ),
                          )
                        : ReorderableListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 32),
                            buildDefaultDragHandles: false,
                            itemCount: tracks.length,
                            onReorderItem: (oldIndex, newIndex) => handler.reorderQueue(oldIndex, newIndex),
                            proxyDecorator: (child, index, animation) => Material(
                              color: colors.bgElevated.withValues(alpha: 0.92),
                              elevation: 8,
                              borderRadius: BorderRadius.circular(16),
                              child: child,
                            ),
                            itemBuilder: (context, i) {
                              final t = tracks[i];
                              final occurrence = tracks.take(i).where((x) => x.id == t.id).length;
                              final isCurrent = i == activeIdx && currentTrack?.id == t.id;
                              return Dismissible(
                                key: ValueKey('queue:${t.id}#$occurrence'),
                                direction: DismissDirection.endToStart,
                                background: Container(
                                  margin: const EdgeInsets.symmetric(vertical: 2),
                                  padding: const EdgeInsets.only(right: 22),
                                  alignment: Alignment.centerRight,
                                  decoration: BoxDecoration(
                                    color: colors.danger.withValues(alpha: 0.22),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Icon(SolarIconsBold.trashBinMinimalistic, color: colors.danger),
                                ),
                                onDismissed: (_) => handler.removeFromQueue(i),
                                child: Container(
                                  margin: const EdgeInsets.symmetric(vertical: 2),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    color: isCurrent
                                        ? accent.withValues(alpha: colors.isDark ? 0.16 : 0.12)
                                        : Colors.transparent,
                                    border: isCurrent
                                        ? Border.all(color: accent.withValues(alpha: 0.32), width: 0.9)
                                        : null,
                                  ),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: () => handler.jumpTo(i),
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                                      child: Row(
                                        children: [
                                          SizedBox(
                                            width: 24,
                                            child: isCurrent
                                                ? Icon(SolarIconsBold.soundwave, size: 16, color: accent)
                                                : Text(
                                                    '${i + 1}',
                                                    textAlign: TextAlign.center,
                                                    style: TextStyle(
                                                      fontSize: 12.5,
                                                      color: colors.textTertiary,
                                                      fontFeatures: const [FontFeature.tabularFigures()],
                                                    ),
                                                  ),
                                          ),
                                          const SizedBox(width: 8),
                                          if (isCurrent)
                                            FlightElement(
                                              tag: 'artwork:${t.id}',
                                              borderRadius: BorderRadius.circular(10),
                                              enabled: waveEnabled,
                                              child: Artwork(url: t.artwork, size: 42, radius: 10, tone: accent),
                                            )
                                          else
                                            Artwork(url: t.artwork, size: 42, radius: 10, tone: accent),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  t.title,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w600,
                                                    color: isCurrent ? accent : colors.textPrimary,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  t.artistLine,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (t.durationMs != null) ...[
                                            const SizedBox(width: 6),
                                            Text(
                                              formatDuration(t.durationMs),
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                color: colors.textTertiary,
                                                fontFeatures: const [FontFeature.tabularFigures()],
                                              ),
                                            ),
                                          ],
                                          IconButton(
                                            visualDensity: VisualDensity.compact,
                                            iconSize: 18,
                                            tooltip: 'Remover da fila',
                                            icon: Icon(SolarIconsBold.close, color: colors.textTertiary),
                                            onPressed: () => handler.removeFromQueue(i),
                                          ),
                                          ReorderableDragStartListener(
                                            index: i,
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                                              child: Icon(SolarIconsBold.hamburgerMenu, size: 18, color: colors.textTertiary),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
