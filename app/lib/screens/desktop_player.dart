// language: Dart, file: lib/screens/desktop_player.dart, target: desktop + web, runtime: resong app
import 'dart:math' as math;

import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:solar_icons_flutter/solar_icons_flutter.dart';

import '../core/format.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../state/audio_fx.dart';
import '../state/library.dart';
import '../state/player.dart';
import '../state/providers.dart';
import '../widgets/artist_link.dart';
import '../widgets/artwork.dart';
import '../widgets/lyrics_panel.dart';
import '../widgets/volume_control.dart';
import 'audio_fx_sheet.dart';
import 'detail_screen.dart';
import 'settings_screen.dart';

enum DesktopSidePanel { none, fx, lyrics, queue }

/// Modo Player Desktop minimalista inspirado no Sonora:
/// centro puro quando recolhido, ou tela dividida com Letras, Fila ou Equalizador.
class DesktopPlayerView extends ConsumerStatefulWidget {
  const DesktopPlayerView({
    super.key,
    this.track,
    this.initialPanel = DesktopSidePanel.none,
  });

  final Track? track;
  final DesktopSidePanel initialPanel;

  @override
  ConsumerState<DesktopPlayerView> createState() => _DesktopPlayerViewState();
}

class _DesktopPlayerViewState extends ConsumerState<DesktopPlayerView> {
  late DesktopSidePanel _panel = widget.initialPanel;

  void _togglePanel(DesktopSidePanel target) {
    setState(() {
      _panel = _panel == target ? DesktopSidePanel.none : target;
    });
  }

  Future<void> _openExtrasMenu(BuildContext btnCtx, Track track) async {
    final handler = ref.read(handlerProvider);
    final box = btnCtx.findRenderObject() as RenderBox?;
    final overlay = Navigator.of(btnCtx).overlay?.context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final pos = RelativeRect.fromRect(
      topLeft & box.size,
      Offset.zero & overlay.size,
    );

    final action = await showMenu<String>(
      context: btnCtx,
      position: pos,
      items: [
        const PopupMenuItem(value: 'download', child: Text('Baixar faixa')),
        PopupMenuItem(
          value: 'sleep',
          child: Text(handler.hasSleepTimer ? 'Timer de sono (ativo)' : 'Timer de sono'),
        ),
      ],
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'download':
        await ref.read(downloadsProvider.notifier).request(track);
        break;
      case 'sleep':
        await showSleepTimerSheet(context, ref);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final palette = ref.watch(currentPaletteProvider);
    final handler = ref.watch(handlerProvider);
    final track = ref.watch(currentTrackProvider) ?? widget.track;
    final playing = ref.watch(isPlayingProvider);
    ref.watch(playerModeProvider);

    if (track == null) {
      return Scaffold(
        backgroundColor: colors.bg,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(SolarIconsLinear.musicNote, size: 42, color: colors.textTertiary),
              const SizedBox(height: 12),
              Text('Nenhuma faixa tocando', style: TextStyle(color: colors.textSecondary)),
              const SizedBox(height: 14),
              TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Voltar'),
              ),
            ],
          ),
        ),
      );
    }

    final isDark = colors.isDark;
    final accent = palette.accentFor(isDark);
    final backdrop = palette.backdropFor(isDark);
    final isFav = ref.watch(favoritesProvider.select((favs) => favs.any((t) => t.id == track.id)));
    final fxActive = ref.watch(audioFxProvider.select((f) => f.hasActiveEffects));
    final splitOpen = _panel != DesktopSidePanel.none;

    // Fundo calmo e fosco com leve nuance da capa, sem animações pesadas
    final bgTop = isDark
        ? Color.lerp(const Color(0xFF0A0D0E), backdrop, 0.36)!
        : Color.lerp(const Color(0xFFF6F7F9), backdrop, 0.14)!;
    final bgBottom = isDark
        ? Color.lerp(const Color(0xFF060708), backdrop, 0.14)!
        : Color.lerp(const Color(0xFFECEDF1), backdrop, 0.08)!;

    final panelPill = _SonoraPanelPill(
      active: _panel,
      fxActive: fxActive,
      accent: accent,
      onToggle: _togglePanel,
    );

    return Scaffold(
      backgroundColor: bgBottom,
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop(),
          const SingleActivator(LogicalKeyboardKey.space): () =>
              playing ? handler.pause() : handler.play(),
        },
        child: Focus(
          autofocus: true,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: splitOpen ? const Alignment(-0.55, -0.35) : const Alignment(0, -0.35),
                radius: 1.35,
                colors: [bgTop, bgBottom],
              ),
            ),
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final artSize = (constraints.maxHeight * 0.37).clamp(200.0, 290.0);

                  final leftColumn = _PlayerCenterColumn(
                    track: track,
                    artSize: artSize,
                    isFav: isFav,
                    accent: accent,
                    playing: playing,
                    handler: handler,
                    centerPill: splitOpen ? null : panelPill,
                    onToggleFav: () => ref.read(favoritesProvider.notifier).toggle(track),
                  );

                  return Stack(
                    children: [
                      if (!splitOpen)
                        Center(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                            child: leftColumn,
                          ),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.fromLTRB(56, 28, 48, 28),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 42,
                                child: Center(
                                  child: SingleChildScrollView(child: leftColumn),
                                ),
                              ),
                              const SizedBox(width: 48),
                              Expanded(
                                flex: 58,
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 180),
                                  child: KeyedSubtree(
                                    key: ValueKey('${_panel.name}:${track.id}'),
                                    child: switch (_panel) {
                                      DesktopSidePanel.lyrics => Padding(
                                          padding: const EdgeInsets.only(bottom: 52),
                                          child: LyricsPanel(
                                            track: track,
                                            accent: accent,
                                            desktopStyle: true,
                                          ),
                                        ),
                                      DesktopSidePanel.queue => _SonoraQueuePanel(
                                          accent: accent,
                                          bottomPadding: 64,
                                        ),
                                      DesktopSidePanel.fx => AudioFxBody(
                                          showHeader: true,
                                          translucent: true,
                                          padding: const EdgeInsets.fromLTRB(4, 10, 8, 72),
                                        ),
                                      DesktopSidePanel.none => const SizedBox.shrink(),
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Canto inferior direito: pílula (quando painel aberto), menu discreto e botão v
                      Positioned(
                        right: 22,
                        bottom: 18,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (splitOpen) ...[
                              panelPill,
                              const SizedBox(width: 10),
                            ],
                            Builder(
                              builder: (btnCtx) => IconButton(
                                tooltip: 'Mais ações',
                                iconSize: 18,
                                visualDensity: VisualDensity.compact,
                                icon: Icon(
                                  SolarIconsLinear.menuDots,
                                  color: colors.textSecondary.withValues(alpha: 0.72),
                                ),
                                onPressed: () => _openExtrasMenu(btnCtx, track),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Minimizar player',
                              iconSize: 20,
                              visualDensity: VisualDensity.compact,
                              icon: Icon(
                                SolarIconsLinear.altArrowDown,
                                color: colors.textSecondary.withValues(alpha: 0.8),
                              ),
                              onPressed: () => Navigator.of(context).maybePop(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayerCenterColumn extends StatelessWidget {
  const _PlayerCenterColumn({
    required this.track,
    required this.artSize,
    required this.isFav,
    required this.accent,
    required this.playing,
    required this.handler,
    required this.onToggleFav,
    this.centerPill,
  });

  final Track track;
  final double artSize;
  final bool isFav;
  final Color accent;
  final bool playing;
  final ResongHandler handler;
  final VoidCallback onToggleFav;
  final Widget? centerPill;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 410),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: colors.isDark ? 0.48 : 0.16),
                  blurRadius: 34,
                  spreadRadius: -4,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: Artwork(
              url: track.artwork,
              size: artSize,
              radius: 12,
              tone: accent,
              icon: SolarIconsBold.musicNote,
            ),
          ),
          const SizedBox(height: 22),

          // Título + coração fino inline
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.35,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: onToggleFav,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    isFav ? SolarIconsBold.heart : SolarIconsLinear.heart,
                    size: 16,
                    color: isFav ? accent : colors.textSecondary.withValues(alpha: 0.72),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          ArtistTextLink(
            track: track,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13.5,
              fontWeight: FontWeight.w400,
              color: colors.textSecondary,
            ),
            onOpenArtist: (name) => DetailScreen.openArtistForTrack(
              context,
              track,
              artistName: name,
            ),
          ),

          if (centerPill != null) ...[
            const SizedBox(height: 24),
            centerPill!,
            const SizedBox(height: 16),
          ] else
            const SizedBox(height: 22),

          // Timeline linear fina (estilo Sonora)
          _SonoraTimelineSlider(handler: handler, track: track),
          const SizedBox(height: 12),

          // Linha de transporte minimalista + volume com ajuste no hover e mute no clique
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: handler.shuffle ? 'Aleatório ligado' : 'Aleatório',
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                icon: Icon(
                  SolarIconsLinear.shuffle,
                  color: handler.shuffle ? accent : colors.textSecondary,
                ),
                onPressed: handler.toggleShuffle,
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Anterior',
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                icon: Icon(SolarIconsLinear.skipPrevious, color: colors.textPrimary),
                onPressed: handler.skipToPrevious,
              ),
              const SizedBox(width: 10),
              IconButton(
                tooltip: playing ? 'Pausar' : 'Tocar',
                visualDensity: VisualDensity.compact,
                iconSize: 22,
                icon: Icon(
                  playing ? SolarIconsBold.pause : SolarIconsBold.play,
                  color: colors.textPrimary,
                ),
                onPressed: playing ? handler.pause : handler.play,
              ),
              const SizedBox(width: 10),
              IconButton(
                tooltip: 'Próxima',
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                icon: Icon(SolarIconsLinear.skipNext, color: colors.textPrimary),
                onPressed: handler.skipToNext,
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Repetir',
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                icon: Icon(
                  handler.repeatMode == RepeatMode.one
                      ? SolarIconsBold.repeatOne
                      : SolarIconsLinear.repeat,
                  color: handler.repeatMode != RepeatMode.off ? accent : colors.textSecondary,
                ),
                onPressed: handler.cycleRepeat,
              ),
              const SizedBox(width: 10),
              HoverVolumeControl(
                placement: VolumeSliderPlacement.floatingRight,
                iconSize: 17,
                iconColor: colors.textSecondary,
                mutedColor: colors.textTertiary,
                trackColor: colors.isDark ? Colors.white : colors.textPrimary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SonoraPanelPill extends StatelessWidget {
  const _SonoraPanelPill({
    required this.active,
    required this.fxActive,
    required this.accent,
    required this.onToggle,
  });

  final DesktopSidePanel active;
  final bool fxActive;
  final Color accent;
  final ValueChanged<DesktopSidePanel> onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bg = colors.isDark
        ? Colors.white.withValues(alpha: 0.055)
        : Colors.black.withValues(alpha: 0.05);
    final border = colors.isDark
        ? Colors.white.withValues(alpha: 0.11)
        : Colors.black.withValues(alpha: 0.10);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PillButton(
            icon: SolarIconsLinear.tuning2,
            tooltip: 'Equalizador & 8D',
            selected: active == DesktopSidePanel.fx,
            badge: fxActive && active != DesktopSidePanel.fx,
            accent: accent,
            onTap: () => onToggle(DesktopSidePanel.fx),
          ),
          const SizedBox(width: 2),
          _PillButton(
            icon: SolarIconsLinear.microphone,
            tooltip: 'Letras',
            selected: active == DesktopSidePanel.lyrics,
            accent: accent,
            onTap: () => onToggle(DesktopSidePanel.lyrics),
          ),
          const SizedBox(width: 2),
          _PillButton(
            icon: SolarIconsLinear.playlist2,
            tooltip: 'Fila',
            selected: active == DesktopSidePanel.queue,
            accent: accent,
            onTap: () => onToggle(DesktopSidePanel.queue),
          ),
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.accent,
    required this.onTap,
    this.badge = false,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final bool badge;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final selectedBg = colors.isDark
        ? Colors.white.withValues(alpha: 0.14)
        : Colors.black.withValues(alpha: 0.10);

    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? selectedBg : Colors.transparent,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: selected ? colors.textPrimary : colors.textSecondary,
              ),
              if (badge)
                Positioned(
                  right: 5,
                  top: 5,
                  child: Container(
                    width: 4.5,
                    height: 4.5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SonoraTimelineSlider extends StatefulWidget {
  const _SonoraTimelineSlider({
    required this.handler,
    required this.track,
  });

  final ResongHandler handler;
  final Track track;

  @override
  State<_SonoraTimelineSlider> createState() => _SonoraTimelineSliderState();
}

class _SonoraTimelineSliderState extends State<_SonoraTimelineSlider> {
  double? _dragMs;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fg = colors.isDark ? Colors.white : colors.textPrimary;
    final trackBg = colors.isDark
        ? Colors.white.withValues(alpha: 0.18)
        : Colors.black.withValues(alpha: 0.16);

    return StreamBuilder<Duration>(
      stream: widget.handler.player.positionStream,
      initialData: widget.handler.player.position,
      builder: (context, posSnap) {
        return StreamBuilder<Duration?>(
          stream: widget.handler.player.durationStream,
          initialData: widget.handler.player.duration,
          builder: (context, durSnap) {
            final pos = posSnap.data ?? Duration.zero;
            final rawDur = durSnap.data ??
                (widget.track.durationMs != null
                    ? Duration(milliseconds: widget.track.durationMs!)
                    : Duration.zero);
            final maxMs = math.max(1.0, rawDur.inMilliseconds.toDouble());
            final shownMs = (_dragMs ?? pos.inMilliseconds.toDouble()).clamp(0.0, maxMs);

            return Row(
              children: [
                Text(
                  formatDuration(shownMs.round()),
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.textTertiary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 20,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2.0,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4.5),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                        activeTrackColor: fg,
                        inactiveTrackColor: trackBg,
                        thumbColor: fg,
                        overlayColor: fg.withValues(alpha: 0.12),
                      ),
                      child: Slider(
                        min: 0,
                        max: maxMs,
                        value: shownMs,
                        onChangeStart: (v) => setState(() => _dragMs = v),
                        onChanged: (v) => setState(() => _dragMs = v),
                        onChangeEnd: (v) {
                          setState(() => _dragMs = null);
                          widget.handler.seek(Duration(milliseconds: v.round()));
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  rawDur > Duration.zero ? formatDuration(rawDur.inMilliseconds) : '--:--',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.textTertiary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _SonoraQueuePanel extends ConsumerWidget {
  const _SonoraQueuePanel({
    required this.accent,
    required this.bottomPadding,
  });

  final Color accent;
  final double bottomPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final handler = ref.watch(handlerProvider);
    final queue = ref.watch(queueTracksProvider).valueOrNull ?? handler.tracks;
    final activeTrack = ref.watch(currentTrackProvider);
    final safeIdx = queue.isEmpty ? -1 : handler.currentIndex.clamp(0, queue.length - 1);
    final recentAll = ref.watch(recentProvider);
    final queueIds = {for (final t in queue) t.id};
    final historyTracks = recentAll
        .where((t) => t.id != activeTrack?.id && !queueIds.contains(t.id))
        .take(5)
        .toList();

    return ListView(
      padding: EdgeInsets.fromLTRB(4, 8, 8, bottomPadding),
      children: [
        if (historyTracks.isNotEmpty) ...[
          _QueueSectionLabel('HISTÓRICO', colors.textTertiary),
          const SizedBox(height: 6),
          for (final hTrack in historyTracks)
            _SonoraQueueRow(
              track: hTrack,
              accent: accent,
              isActive: false,
              onTap: () => handler.load([hTrack], start: 0),
            ),
          const SizedBox(height: 18),
        ],
        if (safeIdx >= 0 && safeIdx < queue.length) ...[
          _QueueSectionLabel('TOCANDO AGORA', colors.textTertiary),
          const SizedBox(height: 6),
          _SonoraQueueRow(
            track: queue[safeIdx],
            accent: accent,
            isActive: true,
            onTap: () {},
          ),
          const SizedBox(height: 18),
        ],
        if (safeIdx + 1 < queue.length) ...[
          _QueueSectionLabel('A SEGUIR', colors.textTertiary),
          const SizedBox(height: 6),
          for (var i = safeIdx + 1; i < queue.length; i++)
            _SonoraQueueRow(
              track: queue[i],
              accent: accent,
              isActive: false,
              onTap: () => handler.jumpTo(i),
              onRemove: () => handler.removeFromQueue(i),
            ),
        ],
      ],
    );
  }
}

class _QueueSectionLabel extends StatelessWidget {
  const _QueueSectionLabel(this.label, this.color);

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 10),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.0,
          color: color,
        ),
      ),
    );
  }
}

class _SonoraQueueRow extends StatefulWidget {
  const _SonoraQueueRow({
    required this.track,
    required this.accent,
    required this.isActive,
    required this.onTap,
    this.onRemove,
  });

  final Track track;
  final Color accent;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  @override
  State<_SonoraQueueRow> createState() => _SonoraQueueRowState();
}

class _SonoraQueueRowState extends State<_SonoraQueueRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hoverBg = colors.isDark
        ? Colors.white.withValues(alpha: 0.065)
        : Colors.black.withValues(alpha: 0.05);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: _hovered ? hoverBg : Colors.transparent,
          ),
          child: Row(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  Artwork(
                    url: widget.track.artwork,
                    size: 36,
                    radius: 7,
                    tone: widget.accent,
                    icon: SolarIconsBold.musicNote,
                  ),
                  if (_hovered && !widget.isActive)
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(7),
                        color: Colors.black.withValues(alpha: 0.52),
                      ),
                      child: const Icon(SolarIconsBold.play, size: 14, color: Colors.white),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 13.5,
                        fontWeight: widget.isActive ? FontWeight.w600 : FontWeight.w500,
                        color: widget.isActive ? widget.accent : colors.textPrimary,
                      ),
                    ),
                    Text(
                      widget.track.artistLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: colors.textTertiary),
                    ),
                  ],
                ),
              ),
              if (widget.onRemove != null && _hovered)
                IconButton(
                  tooltip: 'Remover da fila',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  icon: Icon(Icons.close_rounded, size: 16, color: colors.textSecondary),
                  onPressed: widget.onRemove,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
