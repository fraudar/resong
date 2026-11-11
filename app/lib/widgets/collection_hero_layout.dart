// language: Dart, file: lib/widgets/collection_hero_layout.dart, target: mobile-first + desktop, runtime: resong app
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons_flutter/solar_icons_flutter.dart';

import '../core/palette.dart';
import '../core/theme.dart';
import '../state/settings.dart';
import 'flight.dart';
import 'glass.dart';
import 'liquid_wave_backdrop.dart';

/// Layout compartilhado de álbum, playlist e artista no estilo das fotos de referência:
/// capa full-bleed fundida no gradiente em ondas d'água, título centralizado,
/// botões [Aleatório] [Tocar/Pausar] [Ação] e lista transparente que desliza sob o vidro.
class CollectionHeroLayout extends ConsumerWidget {
  const CollectionHeroLayout({
    super.key,
    required this.palette,
    required this.artworkUrl,
    this.localArtworkBytes,
    required this.fallbackIcon,
    required this.title,
    this.subtitle,
    this.meta,
    required this.isPlayingWaves,
    required this.isCollectionPlaying,
    required this.onPlayPause,
    this.onShuffle,
    this.shuffleActive = false,
    required this.trailingIcon,
    this.trailingTooltip,
    this.trailingActive = false,
    this.trailingProgress,
    this.onTrailingTap,
    this.onMenuTap,
    this.heroFlightTag,
    required this.slivers,
  });

  final ArtworkPalette palette;
  final String? artworkUrl;
  final Uint8List? localArtworkBytes;
  final IconData fallbackIcon;
  final String title;
  final String? subtitle;
  final String? meta;
  final bool isPlayingWaves;
  final bool isCollectionPlaying;
  final VoidCallback? onPlayPause;
  final VoidCallback? onShuffle;
  final bool shuffleActive;
  final IconData trailingIcon;
  final String? trailingTooltip;
  final bool trailingActive;
  final double? trailingProgress;
  final VoidCallback? onTrailingTap;
  final VoidCallback? onMenuTap;
  final String? heroFlightTag;
  final List<Widget> slivers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final size = MediaQuery.sizeOf(context);
    final topPad = MediaQuery.paddingOf(context).top;
    final heroHeight = (size.height * 0.44).clamp(310.0, 410.0) + topPad * 0.4;
    final accent = palette.accentFor(colors.isDark);
    final waveEnabled = ref.watch(settingsProvider.select((s) => s.waveEffectsEnabled));

    return Scaffold(
      backgroundColor: colors.bg,
      body: LiquidWaveBackdrop(
        palette: palette,
        intense: true,
        isPlaying: isPlayingWaves,
        animateAmbient: waveEnabled,
        child: Stack(
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Column(
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            alignment: Alignment.bottomCenter,
                            children: [
                              if (heroFlightTag != null)
                                FlightElement(
                                  tag: heroFlightTag!,
                                  borderRadius: BorderRadius.circular(18),
                                  enabled: waveEnabled,
                                  child: HeroArtworkBlend(
                                    url: artworkUrl,
                                    localBytes: localArtworkBytes,
                                    palette: palette,
                                    height: heroHeight,
                                    fallbackIcon: fallbackIcon,
                                    isPlaying: isPlayingWaves,
                                    animateWaves: waveEnabled,
                                  ),
                                )
                              else
                                HeroArtworkBlend(
                                  url: artworkUrl,
                                  localBytes: localArtworkBytes,
                                  palette: palette,
                                  height: heroHeight,
                                  fallbackIcon: fallbackIcon,
                                  isPlaying: isPlayingWaves,
                                  animateWaves: waveEnabled,
                                ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(26, 0, 26, 8),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      title,
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                            fontSize: 22,
                                            fontWeight: FontWeight.w700,
                                            height: 1.15,
                                            color: colors.textPrimary,
                                          ),
                                    ),
                                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        subtitle!,
                                        textAlign: TextAlign.center,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w500,
                                          color: colors.textSecondary,
                                        ),
                                      ),
                                    ],
                                    if (meta != null && meta!.isNotEmpty) ...[
                                      const SizedBox(height: 3),
                                      Text(
                                        meta!,
                                        textAlign: TextAlign.center,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: colors.textTertiary,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              GlassCircleButton(
                                icon: SolarIconsBold.shuffle,
                                size: 44,
                                iconSize: 20,
                                active: shuffleActive,
                                activeColor: accent,
                                tint: palette.backdropFor(colors.isDark),
                                tooltip: 'Aleatório',
                                onTap: onShuffle,
                              ),
                              const SizedBox(width: 14),
                              HeroPlayPill(
                                playing: isCollectionPlaying,
                                onTap: onPlayPause,
                              ),
                              const SizedBox(width: 14),
                              if (trailingProgress != null)
                                Tooltip(
                                  message: trailingTooltip ?? 'Cancelar downloads',
                                  child: GlassSurface(
                                    borderRadius: BorderRadius.circular(22),
                                    blur: 20,
                                    tint: palette.backdropFor(colors.isDark),
                                    tintStrength: 0.34,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(22),
                                      onTap: onTrailingTap,
                                      child: SizedBox(
                                        width: 44,
                                        height: 44,
                                        child: Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            SizedBox(
                                              width: 24,
                                              height: 24,
                                              child: CircularProgressIndicator(
                                                value: trailingProgress! > 0
                                                    ? trailingProgress!.clamp(0.04, 1.0)
                                                    : null,
                                                strokeWidth: 2.3,
                                                color: accent,
                                                backgroundColor: accent.withValues(alpha: 0.2),
                                              ),
                                            ),
                                            if (trailingProgress! > 0)
                                              Text(
                                                '${(trailingProgress! * 100).round()}',
                                                style: TextStyle(
                                                  fontSize: 8,
                                                  fontWeight: FontWeight.w800,
                                                  color: accent,
                                                ),
                                              )
                                            else
                                              Icon(Icons.close, size: 12, color: accent),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                              else
                                GlassCircleButton(
                                  icon: trailingIcon,
                                  size: 44,
                                  iconSize: 20,
                                  active: trailingActive,
                                  activeColor: accent,
                                  tint: palette.backdropFor(colors.isDark),
                                  tooltip: trailingTooltip,
                                  onTap: onTrailingTap,
                                ),
                            ],
                          ),
                          const SizedBox(height: 18),
                        ],
                      ),
                    ),
                    ...slivers,
                    const SliverToBoxAdapter(child: SizedBox(height: 170)),
                  ],
                ),
              ),
            ),
            // Botões flutuantes em vidro no topo (< e ...)
            Positioned(
              top: topPad + 10,
              left: 16,
              right: 16,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Row(
                    children: [
                      GlassCircleButton(
                        icon: SolarIconsBold.altArrowLeft,
                        size: 40,
                        iconSize: 20,
                        onDarkHero: true,
                        tooltip: 'Voltar',
                        onTap: () => Navigator.maybePop(context),
                      ),
                      const Spacer(),
                      if (onMenuTap != null)
                        GlassCircleButton(
                          icon: SolarIconsBold.menuDots,
                          size: 40,
                          iconSize: 20,
                          onDarkHero: true,
                          tooltip: 'Opções',
                          onTap: onMenuTap,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
