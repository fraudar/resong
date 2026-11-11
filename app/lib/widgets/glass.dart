// language: Dart, file: lib/widgets/glass.dart, target: mobile-first + desktop, runtime: resong app
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons_flutter/solar_icons_flutter.dart';

import '../core/theme.dart';
import '../state/library.dart';
import 'flight.dart';

/// Superfície de vidro fosco (glassmorphism real com BackdropFilter).
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    this.blur = 24,
    this.tint,
    this.tintStrength = 0.20,
    this.padding,
    this.shadows,
    this.borderColor,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final double blur;
  final Color? tint;
  final double tintStrength;
  final EdgeInsetsGeometry? padding;
  final List<BoxShadow>? shadows;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final baseFill = colors.isDark
        ? Colors.white.withValues(alpha: 0.11)
        : Colors.white.withValues(alpha: 0.68);
    final effectiveFill = tint != null
        ? Color.lerp(baseFill, tint!.withValues(alpha: colors.isDark ? 0.34 : 0.24), tintStrength)!
        : baseFill;
    final secondaryFill = tint != null
        ? Color.lerp(
            colors.isDark ? Colors.black.withValues(alpha: 0.24) : Colors.white.withValues(alpha: 0.52),
            tint!.withValues(alpha: colors.isDark ? 0.22 : 0.14),
            tintStrength * 0.85,
          )!
        : (colors.isDark ? Colors.black.withValues(alpha: 0.22) : Colors.white.withValues(alpha: 0.54));

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: shadows ??
            [
              BoxShadow(
                color: Colors.black.withValues(alpha: colors.isDark ? 0.32 : 0.10),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              border: Border.all(
                color: borderColor ??
                    (colors.isDark
                        ? Colors.white.withValues(alpha: 0.16)
                        : colors.glassBorder),
                width: 1.0,
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                stops: const [0.0, 0.45, 1.0],
                colors: [
                  effectiveFill,
                  Color.lerp(effectiveFill, secondaryFill, 0.55)!,
                  secondaryFill,
                ],
              ),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Botão circular translúcido em vidro fosco, fiel ao topo e controles das fotos.
class GlassCircleButton extends StatelessWidget {
  const GlassCircleButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 44,
    this.iconSize = 20,
    this.active = false,
    this.activeColor,
    this.tint,
    this.tooltip,
    this.onDarkHero = false,
    this.flightTag,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;
  final bool active;
  final Color? activeColor;
  final Color? tint;
  final String? tooltip;
  final bool onDarkHero;
  final String? flightTag;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final useLightFg = onDarkHero || colors.isDark;
    final fg = active
        ? (activeColor ?? colors.accent)
        : (useLightFg ? Colors.white.withValues(alpha: 0.94) : colors.textPrimary);
    final bg = active
        ? (activeColor ?? colors.accent).withValues(alpha: 0.26)
        : (onDarkHero && !colors.isDark
            ? Colors.black.withValues(alpha: 0.28)
            : (tint ?? (colors.isDark ? Colors.white : Colors.white)).withValues(alpha: colors.isDark ? 0.14 : 0.72));
    final border = active
        ? (activeColor ?? colors.accent).withValues(alpha: 0.55)
        : (onDarkHero && !colors.isDark ? Colors.white.withValues(alpha: 0.25) : colors.glassBorder);

    Widget button = Opacity(
      opacity: onTap == null ? 0.45 : 1.0,
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: bg,
                  border: Border.all(color: border, width: 1.0),
                ),
                child: flightTag != null
                    ? Center(
                        child: FlightElement(
                          tag: flightTag!,
                          borderRadius: BorderRadius.circular(iconSize / 2),
                          child: Icon(icon, size: iconSize, color: fg),
                        ),
                      )
                    : Icon(icon, size: iconSize, color: fg),
              ),
            ),
          ),
        ),
      ),
    );

    if (tooltip != null) {
      button = Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}

/// Botão central em pílula de alto contraste (Tocar / Pausar), estilo capa da foto.
class HeroPlayPill extends StatelessWidget {
  const HeroPlayPill({
    super.key,
    required this.playing,
    required this.onTap,
    this.playLabel = 'Tocar',
    this.pauseLabel = 'Pausar',
    this.width = 136,
    this.height = 48,
  });

  final bool playing;
  final VoidCallback? onTap;
  final String playLabel;
  final String pauseLabel;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Opacity(
      opacity: onTap == null ? 0.45 : 1.0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(height / 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: colors.isDark ? 0.35 : 0.16),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: colors.heroPillBg,
          borderRadius: BorderRadius.circular(height / 2),
          child: InkWell(
            borderRadius: BorderRadius.circular(height / 2),
            onTap: onTap,
            child: SizedBox(
              width: width,
              height: height,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Row(
                  key: ValueKey(playing),
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      playing ? SolarIconsBold.pause : SolarIconsBold.play,
                      size: 18,
                      color: colors.heroPillFg,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      playing ? pauseLabel : playLabel,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: colors.heroPillFg,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Alternador rápido entre tema Black (OLED) e tema Light.
class ThemeToggleButton extends ConsumerWidget {
  const ThemeToggleButton({
    super.key,
    this.compact = false,
    this.onDarkHero = false,
  });

  final bool compact;
  final bool onDarkHero;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final isDark = mode == ThemeMode.dark;
    final tooltip = isDark ? 'Mudar para tema Light' : 'Mudar para tema Black';

    if (compact) {
      return GlassCircleButton(
        icon: isDark ? SolarIconsBold.sun2 : SolarIconsBold.moon,
        size: 38,
        iconSize: 18,
        tooltip: tooltip,
        onDarkHero: onDarkHero,
        onTap: () => ref.read(themeModeProvider.notifier).toggle(),
      );
    }

    final colors = context.colors;
    return Tooltip(
      message: tooltip,
      child: GlassSurface(
        borderRadius: BorderRadius.circular(18),
        blur: 18,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => ref.read(themeModeProvider.notifier).toggle(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: Row(
                key: ValueKey(isDark),
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isDark ? SolarIconsBold.moon : SolarIconsBold.sun2,
                    size: 15,
                    color: colors.accent,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isDark ? 'Black' : 'Light',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
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

/// Botão arredondado em squircle (Liquid Glass ou preenchido), inspirado em Husn / SQUARE.
class GlassSquircleButton extends StatelessWidget {
  const GlassSquircleButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.width = 56,
    this.height = 56,
    this.borderRadius = 20,
    this.iconSize = 24,
    this.filledColor,
    this.foregroundColor,
    this.tint,
    this.active = false,
    this.activeColor,
    this.tooltip,
    this.shadows,
    this.flightTag,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double width;
  final double height;
  final double borderRadius;
  final double iconSize;
  final Color? filledColor;
  final Color? foregroundColor;
  final Color? tint;
  final bool active;
  final Color? activeColor;
  final String? tooltip;
  final List<BoxShadow>? shadows;
  final String? flightTag;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radius = BorderRadius.circular(borderRadius);
    final resolvedActive = activeColor ?? colors.accent;

    final Color bg;
    final Color fg;
    final Color border;

    if (filledColor != null) {
      bg = filledColor!;
      fg = foregroundColor ??
          (filledColor!.computeLuminance() > 0.45 ? Colors.black : Colors.white);
      border = Colors.white.withValues(alpha: colors.isDark ? 0.22 : 0.45);
    } else if (active) {
      bg = resolvedActive.withValues(alpha: colors.isDark ? 0.26 : 0.18);
      fg = foregroundColor ?? resolvedActive;
      border = resolvedActive.withValues(alpha: 0.55);
    } else {
      bg = (tint ?? Colors.white).withValues(
          alpha: tint != null ? (colors.isDark ? 0.24 : 0.22) : (colors.isDark ? 0.11 : 0.72));
      fg = foregroundColor ??
          (colors.isDark ? Colors.white.withValues(alpha: 0.94) : colors.textPrimary);
      border = colors.isDark
          ? Colors.white.withValues(alpha: 0.16)
          : colors.glassBorder;
    }

    Widget core = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: radius,
            color: bg,
            border: Border.all(color: border, width: 1.0),
          ),
          child: flightTag != null
              ? Center(
                  child: FlightElement(
                    tag: flightTag!,
                    borderRadius: BorderRadius.circular(iconSize / 2),
                    child: Icon(icon, size: iconSize, color: fg),
                  ),
                )
              : Icon(icon, size: iconSize, color: fg),
        ),
      ),
    );

    if (filledColor == null) {
      core = ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: core,
        ),
      );
    }

    Widget button = Opacity(
      opacity: onTap == null ? 0.45 : 1.0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: shadows ??
              (filledColor != null
                  ? [
                      BoxShadow(
                        color: filledColor!.withValues(alpha: colors.isDark ? 0.28 : 0.22),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : null),
        ),
        child: core,
      ),
    );

    if (tooltip != null) {
      button = Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}
