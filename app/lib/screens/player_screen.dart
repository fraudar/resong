// language: Dart, file: lib/screens/player_screen.dart, target: mobile-first + desktop, runtime: resong app
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/physics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:solar_icons_flutter/solar_icons_flutter.dart';

import '../core/format.dart';
import '../core/models.dart';
import '../core/palette.dart';
import '../core/theme.dart';
import '../state/audio_fx.dart';
import '../state/library.dart';
import '../state/lyrics_cache.dart';
import '../state/player.dart';
import '../state/providers.dart';
import '../state/settings.dart';
import '../widgets/artwork.dart';
import '../widgets/flight.dart';
import '../widgets/glass.dart';
import '../widgets/liquid_wave_backdrop.dart';
import '../widgets/lyrics_panel.dart';
import '../widgets/wave_seek_bar.dart';
import 'audio_fx_sheet.dart';
import 'desktop_player.dart';
import 'detail_screen.dart';
import 'queue_screen.dart';
import 'settings_screen.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({
    super.key,
    this.initialTrack,
    this.initialDesktopPanel = DesktopSidePanel.none,
  });

  final Track? initialTrack;
  final DesktopSidePanel initialDesktopPanel;

  static Future<void> open(
    BuildContext context,
    WidgetRef ref, {
    Track? initialTrack,
    DesktopSidePanel desktopPanel = DesktopSidePanel.none,
  }) {
    return Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 240),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, __, ___) => PlayerScreen(
          initialTrack: initialTrack,
          initialDesktopPanel: desktopPanel,
        ),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          child: child,
        ),
      ),
    );
  }

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final handler = ref.watch(handlerProvider);
    final track = ref.watch(currentTrackProvider) ?? widget.initialTrack;

    if (track == null) {
      return Scaffold(
        backgroundColor: colors.bg,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(SolarIconsBold.altArrowDown),
            onPressed: () => Navigator.maybePop(context),
          ),
        ),
        body: Center(
          child: Text('Nenhuma faixa em reprodução', style: TextStyle(color: colors.textSecondary)),
        ),
      );
    }

    if (MediaQuery.sizeOf(context).width >= 860) {
      return DesktopPlayerView(
        track: track,
        initialPanel: widget.initialDesktopPanel,
      );
    }

    final palette = ref.watch(currentPaletteProvider);
    final accent = palette.accentFor(colors.isDark);
    final glowColor = palette.highlightFor(colors.isDark);
    final backdropTint = palette.backdropFor(colors.isDark);
    final secondaryTint = palette.secondaryFor(colors.isDark);
    final playing = ref.watch(isPlayingProvider);
    final waveEnabled = ref.watch(settingsProvider.select((s) => s.waveEffectsEnabled));
    ref.watch(playerModeProvider);
    ref.watch(sleepTimerProvider);

    final isFav = ref.watch(favoritesProvider.select((favs) => favs.any((t) => t.id == track.id)));
    final downloadRec = ref.watch(
      downloadsProvider.select((list) {
        for (final d in list) {
          if (d.trackId == track.id) return d;
        }
        return null;
      }),
    );
    final isDownloading = downloadRec != null &&
        (downloadRec.status == 'queued' || downloadRec.status == 'downloading');
    final hasDownload = downloadRec?.hasPlayableLocal ?? false;
    final fxActive = ref.watch(audioFxProvider.select((f) => f.hasActiveEffects));
    final topPad = MediaQuery.paddingOf(context).top;
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    // Paleta harmônica dos botões principais (Husn + SQUARE)
    final playBtnBg = colors.isDark
        ? Color.lerp(accent, Colors.white, 0.70)!
        : Color.lerp(colors.heroPillBg, accent, 0.14)!;
    final playBtnFg = colors.isDark
        ? Color.lerp(backdropTint, Colors.black, 0.72)!
        : Colors.white;
    final waveActiveColor = colors.isDark
        ? Color.lerp(accent, Colors.white, 0.42)!
        : accent;
    final waveInactiveColor = colors.isDark
        ? Colors.white.withValues(alpha: 0.22)
        : colors.textPrimary.withValues(alpha: 0.14);

    return Scaffold(
      backgroundColor: colors.bg,
      body: LiquidWaveBackdrop(
        palette: palette,
        intense: true,
        isPlaying: playing,
        animateAmbient: waveEnabled,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final availableH = math.max(320.0, constraints.maxHeight - topPad - bottomPad - 20);
            final compact = availableH < 640;
            final maxCoverW = math.min(constraints.maxWidth - 48, 336.0);
            final maxCoverH = math.max(150.0, availableH - (compact ? 355 : 405));
            final coverSize = math.min(maxCoverW, maxCoverH).clamp(150.0, 336.0);

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(24, topPad + 10, 24, bottomPad + 16),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Barra superior limpa (Minimizar — Tocando agora — Fila)
                          Row(
                            children: [
                              GlassCircleButton(
                                icon: SolarIconsBold.altArrowDown,
                                size: 40,
                                iconSize: 20,
                                tint: backdropTint,
                                tooltip: 'Minimizar',
                                onTap: () => Navigator.maybePop(context),
                              ),
                              Expanded(
                                child: Text(
                                  'Tocando agora',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.sora(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: -0.1,
                                    color: colors.textPrimary.withValues(alpha: 0.88),
                                  ),
                                ),
                              ),
                              GlassCircleButton(
                                icon: SolarIconsBold.playlist2,
                                size: 40,
                                iconSize: 19,
                                tint: backdropTint,
                                tooltip: 'Fila',
                                onTap: () => QueueScreen.open(context),
                              ),
                            ],
                          ),
                          SizedBox(height: compact ? 12 : 18),

                          // Capa 1:1 com cantos bem arredondados e brilho ambiente suave
                          GestureDetector(
                            onHorizontalDragEnd: (details) {
                              final vx = details.primaryVelocity ?? 0;
                              if (vx < -320) {
                                handler.skipToNext();
                              } else if (vx > 320) {
                                handler.skipToPrevious();
                              }
                            },
                            child: AnimatedScale(
                              scale: playing ? 1.0 : 0.965,
                              duration: const Duration(milliseconds: 320),
                              curve: Curves.easeOutCubic,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 420),
                                curve: Curves.easeOutCubic,
                                width: coverSize,
                                height: coverSize,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(26),
                                  boxShadow: [
                                    BoxShadow(
                                      color: glowColor.withValues(alpha: colors.isDark ? 0.34 : 0.22),
                                      blurRadius: 46,
                                      spreadRadius: -4,
                                      offset: const Offset(0, 18),
                                    ),
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: colors.isDark ? 0.44 : 0.16),
                                      blurRadius: 28,
                                      offset: const Offset(0, 12),
                                    ),
                                  ],
                                ),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    FlightElement(
                                      tag: 'artwork:${track.id}',
                                      borderRadius: BorderRadius.circular(26),
                                      enabled: waveEnabled,
                                      child: AnimatedSwitcher(
                                        duration: const Duration(milliseconds: 380),
                                        switchInCurve: Curves.easeOutCubic,
                                        switchOutCurve: Curves.easeInCubic,
                                        child: Artwork(
                                          key: ValueKey(track.id),
                                          url: track.artwork,
                                          size: coverSize,
                                          radius: 26,
                                          tone: accent,
                                          icon: SolarIconsBold.musicNote,
                                        ),
                                      ),
                                    ),
                                    IgnorePointer(
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(26),
                                          border: Border.all(
                                            color: Colors.white.withValues(alpha: colors.isDark ? 0.16 : 0.45),
                                            width: 1.0,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          SizedBox(height: compact ? 14 : 20),

                          // Bloco de metadados, letra ao vivo, seekbar em onda, transporte e dock vidro
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Título + Artista à esquerda e Favorito à direita (estilo Husn / SQUARE)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: DetailScreen.artistIdForTrack(track) != null
                                          ? () {
                                              final nav = Navigator.of(context, rootNavigator: true);
                                              Navigator.pop(context);
                                              DetailScreen.openArtistForTrack(context, track, navigator: nav);
                                            }
                                          : null,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            track.title,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.spaceGrotesk(
                                              fontSize: compact ? 21 : 24,
                                              fontWeight: FontWeight.w700,
                                              height: 1.12,
                                              letterSpacing: -0.7,
                                              color: colors.textPrimary,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            track.album != null && track.album!.isNotEmpty
                                                ? '${track.artistLine} • ${track.album}'
                                                : track.artistLine,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w500,
                                              color: colors.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  FlightElement(
                                    tag: 'fav:${track.id}',
                                    borderRadius: BorderRadius.circular(14),
                                    enabled: waveEnabled,
                                    child: _SpringHeartButton(
                                      liked: isFav,
                                      accent: accent,
                                      inactiveColor: colors.textSecondary,
                                      onTap: () => ref.read(favoritesProvider.notifier).toggle(track),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: compact ? 10 : 14),

                              // Pílula de letras sincronizadas ao vivo (some por completo se não houver letra sincronizada)
                              _LiveLyricsPill(
                                track: track,
                                handler: handler,
                                accent: accent,
                                tint: backdropTint,
                                bottomGap: compact ? 8 : 12,
                                onTap: () => _openLyrics(context, ref, track, palette, accent),
                              ),

                              // Barra de progresso com ondinha animada
                              _WaveProgressSection(
                                handler: handler,
                                isPlaying: playing,
                                animateWave: waveEnabled,
                                activeColor: waveActiveColor,
                                inactiveColor: waveInactiveColor,
                                thumbColor: colors.isDark ? Colors.white : accent,
                                glowColor: glowColor,
                              ),
                              SizedBox(height: compact ? 10 : 14),

                              // Controles de transporte principais em squircle (Anterior, Play/Pause, Próxima)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  GlassSquircleButton(
                                    icon: SolarIconsBold.skipPrevious,
                                    width: compact ? 48 : 52,
                                    height: compact ? 42 : 46,
                                    borderRadius: 16,
                                    iconSize: 20,
                                    tint: secondaryTint,
                                    foregroundColor: colors.textPrimary,
                                    tooltip: 'Anterior',
                                    onTap: handler.skipToPrevious,
                                  ),
                                  const SizedBox(width: 12),
                                  GlassSquircleButton(
                                    icon: playing ? SolarIconsBold.pause : SolarIconsBold.play,
                                    width: compact ? 60 : 66,
                                    height: compact ? 48 : 54,
                                    borderRadius: 19,
                                    iconSize: 24,
                                    filledColor: playBtnBg,
                                    foregroundColor: playBtnFg,
                                    tooltip: playing ? 'Pausar' : 'Tocar',
                                    onTap: playing ? handler.pause : handler.play,
                                  ),
                                  const SizedBox(width: 12),
                                  GlassSquircleButton(
                                    icon: SolarIconsBold.skipNext,
                                    width: compact ? 48 : 52,
                                    height: compact ? 42 : 46,
                                    borderRadius: 16,
                                    iconSize: 20,
                                    tint: secondaryTint,
                                    foregroundColor: colors.textPrimary,
                                    tooltip: 'Próxima',
                                    onTap: handler.skipToNext,
                                  ),
                                ],
                              ),
                              SizedBox(height: compact ? 12 : 16),

                              // Dock inferior em Liquid Glass para opções utilitárias diretas
                              GlassSurface(
                                borderRadius: BorderRadius.circular(24),
                                blur: 24,
                                tint: backdropTint,
                                tintStrength: 0.30,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _DockIconButton(
                                      icon: handler.shuffle ? SolarIconsBold.shuffle : SolarIconsLinear.shuffle,
                                      color: handler.shuffle ? accent : colors.textSecondary,
                                      tooltip: handler.shuffle ? 'Aleatório ligado' : 'Aleatório desligado',
                                      onTap: handler.toggleShuffle,
                                    ),
                                    const SizedBox(width: 4),
                                    _DockIconButton(
                                      icon: handler.repeatMode == RepeatMode.one
                                          ? SolarIconsBold.repeatOne
                                          : SolarIconsLinear.repeat,
                                      color: handler.repeatMode != RepeatMode.off
                                          ? accent
                                          : colors.textSecondary,
                                      tooltip: 'Repetir',
                                      onTap: handler.cycleRepeat,
                                    ),
                                    const SizedBox(width: 4),
                                    _DockDownloadButton(
                                      record: downloadRec,
                                      isDownloading: isDownloading,
                                      hasDownload: hasDownload,
                                      accent: accent,
                                      inactiveColor: colors.textSecondary,
                                      onDownload: () => ref.read(downloadsProvider.notifier).request(track),
                                      onCancel: () => ref.read(downloadsProvider.notifier).cancel(track.id),
                                      onOpenDownloads: () => openDownloadsTab(context, ref),
                                    ),
                                    const SizedBox(width: 4),
                                    _DockIconButton(
                                      icon: SolarIconsBold.tuning2,
                                      color: fxActive ? accent : colors.textSecondary,
                                      tooltip: 'Equalizador & Som 8D',
                                      onTap: () => showAudioEffectsSheet(context, ref),
                                    ),
                                    const SizedBox(width: 4),
                                    _DockIconButton(
                                      icon: SolarIconsBold.clockCircle,
                                      color: handler.hasSleepTimer ? accent : colors.textSecondary,
                                      tooltip: 'Sleep timer',
                                      onTap: () => showSleepTimerSheet(context, ref),
                                    ),
                                    if (track.extra['album_id'] != null) ...[
                                      const SizedBox(width: 4),
                                      _DockIconButton(
                                        icon: SolarIconsBold.album,
                                        color: colors.textSecondary,
                                        tooltip: 'Ir para o álbum',
                                        onTap: () {
                                          Navigator.pop(context);
                                          final albumId = track.extra['album_id'].toString();
                                          Navigator.of(context, rootNavigator: true).push(
                                            MaterialPageRoute<void>(
                                              builder: (_) => DetailScreen.album(
                                                track.source == 'spotify' ? 'sp:album:$albumId' : 'ytal:$albumId',
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _openLyrics(
    BuildContext context,
    WidgetRef ref,
    Track track,
    ArtworkPalette palette,
    Color accent,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.88,
        minChildSize: 0.55,
        maxChildSize: 0.96,
        builder: (sheetContext, controller) => _LyricsSheet(
          track: track,
          palette: palette,
          accent: accent,
          controller: controller,
        ),
      ),
    );
  }
}

/// Pílula clicável acima da barra de onda: mostra a linha atual ao vivo.
/// Sem letra sincronizada, não ocupa espaço algum.
class _LiveLyricsPill extends StatelessWidget {
  const _LiveLyricsPill({
    required this.track,
    required this.handler,
    required this.accent,
    required this.tint,
    required this.bottomGap,
    required this.onTap,
  });

  final Track track;
  final ResongHandler handler;
  final Color accent;
  final Color tint;
  final double bottomGap;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return StreamBuilder<String>(
      stream: LyricsCache.instance.updatesStream,
      builder: (context, _) {
        final lines = LyricsCache.instance.getParsedSynced(track.id);
        if (lines.isEmpty) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: EdgeInsets.only(bottom: bottomGap),
          child: GlassSurface(
            borderRadius: BorderRadius.circular(18),
            blur: 18,
            tint: tint,
            tintStrength: 0.28,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Icon(SolarIconsBold.microphone, size: 17, color: accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: StreamBuilder<Duration>(
                        stream: handler.player.positionStream,
                        initialData: handler.player.position,
                        builder: (context, snapshot) {
                          final pos = snapshot.data ?? Duration.zero;
                          final idx = activeLrcIndex(lines, pos);
                          final text = idx >= 0 ? lines[idx].text : lines.first.text;
                          return AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            child: Align(
                              key: ValueKey(text),
                              alignment: Alignment.centerLeft,
                              child: Text(
                                text,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: idx >= 0 ? FontWeight.w600 : FontWeight.w500,
                                  color: idx >= 0 ? colors.textPrimary : colors.textSecondary,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(SolarIconsBold.altArrowRight, size: 16, color: colors.textTertiary),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Coração transparente sem card de fundo e com pop em física de spring ao curtir.
class _SpringHeartButton extends StatefulWidget {
  const _SpringHeartButton({
    required this.liked,
    required this.accent,
    required this.inactiveColor,
    required this.onTap,
  });

  final bool liked;
  final Color accent;
  final Color inactiveColor;
  final VoidCallback onTap;

  @override
  State<_SpringHeartButton> createState() => _SpringHeartButtonState();
}

class _SpringHeartButtonState extends State<_SpringHeartButton> with SingleTickerProviderStateMixin {
  late final AnimationController _scaleCtrl;

  @override
  void initState() {
    super.initState();
    _scaleCtrl = AnimationController.unbounded(vsync: this, value: 1.0);
  }

  @override
  void didUpdateWidget(covariant _SpringHeartButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.liked && !oldWidget.liked) {
      _runPop();
    }
  }

  void _runPop() {
    _scaleCtrl.value = 1.25;
    final sim = SpringSimulation(
      const SpringDescription(mass: 1.0, stiffness: 380.0, damping: 14.0),
      1.25,
      1.0,
      0.8,
    );
    _scaleCtrl.animateWith(sim);
  }

  @override
  void dispose() {
    _scaleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.liked ? 'Remover dos favoritos' : 'Curtir',
      child: InkResponse(
        radius: 22,
        splashColor: widget.accent.withValues(alpha: 0.18),
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: AnimatedBuilder(
            animation: _scaleCtrl,
            builder: (context, child) => Transform.scale(
              scale: _scaleCtrl.value.clamp(0.85, 1.35),
              child: child,
            ),
            child: Icon(
              widget.liked ? SolarIconsBold.heart : SolarIconsLinear.heart,
              size: 24,
              color: widget.liked ? widget.accent : widget.inactiveColor,
            ),
          ),
        ),
      ),
    );
  }
}

class _DockDownloadButton extends StatelessWidget {
  const _DockDownloadButton({
    required this.record,
    required this.isDownloading,
    required this.hasDownload,
    required this.accent,
    required this.inactiveColor,
    required this.onDownload,
    required this.onCancel,
    required this.onOpenDownloads,
  });

  final DownloadRecord? record;
  final bool isDownloading;
  final bool hasDownload;
  final Color accent;
  final Color inactiveColor;
  final VoidCallback onDownload;
  final VoidCallback onCancel;
  final VoidCallback onOpenDownloads;

  @override
  Widget build(BuildContext context) {
    if (isDownloading) {
      final p = (record?.progress ?? 0.0).clamp(0.0, 1.0);
      final pct = (p * 100).round();
      return Tooltip(
        message: 'Cancelar download ($pct%)',
        child: InkResponse(
          radius: 20,
          onTap: onCancel,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    value: record?.status == 'downloading' && p > 0 ? p : null,
                    strokeWidth: 2.2,
                    color: accent,
                    backgroundColor: accent.withValues(alpha: 0.2),
                  ),
                ),
                if (pct > 0 && record?.status == 'downloading')
                  Text(
                    '$pct',
                    style: TextStyle(fontSize: 7.5, fontWeight: FontWeight.w800, color: accent),
                  )
                else
                  Icon(Icons.close, size: 11, color: accent),
              ],
            ),
          ),
        ),
      );
    }
    if (hasDownload) {
      return _DockIconButton(
        icon: SolarIconsBold.folderCheck,
        color: accent,
        tooltip: 'Baixado — Abrir Downloads',
        onTap: onOpenDownloads,
      );
    }
    return _DockIconButton(
      icon: SolarIconsBold.downloadMinimalistic,
      color: inactiveColor,
      tooltip: 'Baixar',
      onTap: onDownload,
    );
  }
}

class _DockIconButton extends StatelessWidget {
  const _DockIconButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      iconSize: 20,
      color: color,
      onPressed: onTap,
      icon: Icon(icon),
    );
  }
}

class _WaveProgressSection extends StatefulWidget {
  const _WaveProgressSection({
    required this.handler,
    required this.isPlaying,
    required this.animateWave,
    required this.activeColor,
    required this.inactiveColor,
    required this.thumbColor,
    required this.glowColor,
  });

  final ResongHandler handler;
  final bool isPlaying;
  final bool animateWave;
  final Color activeColor;
  final Color inactiveColor;
  final Color thumbColor;
  final Color glowColor;

  @override
  State<_WaveProgressSection> createState() => _WaveProgressSectionState();
}

class _WaveProgressSectionState extends State<_WaveProgressSection> {
  Duration? _scrubPos;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return StreamBuilder<Duration>(
      stream: widget.handler.player.positionStream,
      initialData: widget.handler.player.position,
      builder: (context, posSnap) {
        return StreamBuilder<Duration?>(
          stream: widget.handler.player.durationStream,
          initialData: widget.handler.player.duration,
          builder: (context, durSnap) {
            final total = durSnap.data ?? widget.handler.player.duration ?? Duration.zero;
            final pos = _scrubPos ?? posSnap.data ?? Duration.zero;
            final posStr = formatDuration(pos.inMilliseconds);
            final totalStr = formatDuration(total.inMilliseconds);

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                WaveSeekBar(
                  position: pos,
                  duration: total,
                  isPlaying: widget.isPlaying,
                  animateWave: widget.animateWave,
                  activeColor: widget.activeColor,
                  inactiveColor: widget.inactiveColor,
                  thumbColor: widget.thumbColor,
                  glowColor: widget.glowColor,
                  onScrubUpdate: (d) => setState(() => _scrubPos = d),
                  onSeek: (d) => widget.handler.seek(d),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        posStr.isEmpty ? '0:00' : posStr,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: colors.textSecondary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text(
                        totalStr.isEmpty ? '0:00' : totalStr,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: colors.textSecondary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
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

// ------------------------------------------------------------ folha de letras (Liquid Glass estilo SQUARE)

class _LyricsSheet extends ConsumerWidget {
  const _LyricsSheet({
    required this.track,
    required this.palette,
    required this.accent,
    required this.controller,
  });

  final Track track;
  final ArtworkPalette palette;
  final Color accent;
  final ScrollController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final handler = ref.watch(handlerProvider);
    final activeTrack = ref.watch(currentTrackProvider) ?? track;
    final livePalette = ref.watch(currentPaletteProvider);
    final liveAccent = livePalette.accentFor(colors.isDark);
    final playing = ref.watch(isPlayingProvider);

    final topTint = livePalette.backdropFor(colors.isDark);
    final bottomTint = livePalette.secondaryFor(colors.isDark);
    final sheetBgTop = Color.lerp(
      colors.isDark ? const Color(0xFF141418) : const Color(0xFFF6F5FA),
      topTint,
      colors.isDark ? 0.56 : 0.34,
    )!;
    final sheetBgBottom = Color.lerp(
      colors.isDark ? const Color(0xFF0A0A0D) : const Color(0xFFEDEBF4),
      bottomTint,
      colors.isDark ? 0.44 : 0.24,
    )!;
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
            border: Border(
              top: BorderSide(
                color: Colors.white.withValues(alpha: colors.isDark ? 0.16 : 0.65),
                width: 1.0,
              ),
            ),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                sheetBgTop.withValues(alpha: 0.94),
                sheetBgBottom.withValues(alpha: 0.96),
              ],
            ),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: colors.textTertiary.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        GlassCircleButton(
                          icon: SolarIconsBold.altArrowDown,
                          size: 36,
                          iconSize: 18,
                          tint: topTint,
                          tooltip: 'Fechar letras',
                          onTap: () => Navigator.maybePop(context),
                        ),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Letras',
                                style: GoogleFonts.sora(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: colors.textPrimary,
                                ),
                              ),
                              Text(
                                '${activeTrack.title} • ${activeTrack.artistLine}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11.5, color: colors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        GlassCircleButton(
                          icon: SolarIconsBold.playlist2,
                          size: 36,
                          iconSize: 18,
                          tint: topTint,
                          tooltip: 'Fila',
                          onTap: () {
                            Navigator.maybePop(context);
                            QueueScreen.open(context);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: LyricsPanel(
                    track: activeTrack,
                    accent: liveAccent,
                    scrollController: controller,
                  ),
                ),
              ),
              // Barra compacta de controle dentro das letras (estilo SQUARE)
              Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, bottomPad + 14),
                child: GlassSurface(
                  borderRadius: BorderRadius.circular(22),
                  blur: 22,
                  tint: topTint,
                  tintStrength: 0.34,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Artwork(
                        url: activeTrack.artwork,
                        size: 40,
                        radius: 10,
                        tone: liveAccent,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              activeTrack.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: colors.textPrimary,
                              ),
                            ),
                            Text(
                              activeTrack.artistLine,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11.5, color: colors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Anterior',
                        visualDensity: VisualDensity.compact,
                        icon: Icon(SolarIconsBold.skipPrevious, size: 20, color: colors.textPrimary),
                        onPressed: handler.skipToPrevious,
                      ),
                      GlassSquircleButton(
                        icon: playing ? SolarIconsBold.pause : SolarIconsBold.play,
                        width: 40,
                        height: 40,
                        borderRadius: 14,
                        iconSize: 19,
                        filledColor: liveAccent,
                        tooltip: playing ? 'Pausar' : 'Tocar',
                        onTap: playing ? handler.pause : handler.play,
                      ),
                      IconButton(
                        tooltip: 'Próxima',
                        visualDensity: VisualDensity.compact,
                        icon: Icon(SolarIconsBold.skipNext, size: 20, color: colors.textPrimary),
                        onPressed: handler.skipToNext,
                      ),
                    ],
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


