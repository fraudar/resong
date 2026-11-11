// language: Dart, file: lib/widgets/liquid_wave_backdrop.dart, target: mobile-first + desktop, runtime: resong app
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:solar_icons_flutter/solar_icons_flutter.dart';

import '../core/palette.dart';
import '../core/theme.dart';

/// Fundo animado com efeito de ondas d'água quando a cor da música muda
/// e corrente líquida suave enquanto toca, compatível com temas Black e Light.
class LiquidWaveBackdrop extends StatefulWidget {
  const LiquidWaveBackdrop({
    super.key,
    required this.palette,
    required this.child,
    this.intense = false,
    this.isPlaying = true,
    this.animateAmbient = true,
  });

  final ArtworkPalette palette;
  final Widget child;
  final bool intense;
  final bool isPlaying;
  final bool animateAmbient;

  @override
  State<LiquidWaveBackdrop> createState() => _LiquidWaveBackdropState();
}

class _LiquidWaveBackdropState extends State<LiquidWaveBackdrop> with TickerProviderStateMixin {
  late ArtworkPalette _fromPalette;
  late ArtworkPalette _toPalette;
  late final AnimationController _transitionCtrl;
  late final AnimationController _ambientCtrl;

  @override
  void initState() {
    super.initState();
    _fromPalette = widget.palette;
    _toPalette = widget.palette;
    _transitionCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1350),
      value: 1.0,
    );
    _ambientCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 11),
    );
    if (widget.animateAmbient) {
      _ambientCtrl.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant LiquidWaveBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.palette != _toPalette) {
      // Captura a paleta visual atual para transição contínua mesmo em trocas rápidas.
      _fromPalette = ArtworkPalette.lerp(_fromPalette, _toPalette, _transitionCtrl.value);
      _toPalette = widget.palette;
      _transitionCtrl.forward(from: 0.0);
    }
    if (widget.animateAmbient != oldWidget.animateAmbient) {
      if (widget.animateAmbient) {
        _ambientCtrl.repeat();
      } else {
        _ambientCtrl.stop();
      }
    }
  }

  @override
  void dispose() {
    _transitionCtrl.dispose();
    _ambientCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: Listenable.merge([_transitionCtrl, _ambientCtrl]),
            builder: (context, _) => CustomPaint(
              painter: _LiquidWavePainter(
                fromPalette: _fromPalette,
                toPalette: _toPalette,
                transition: Curves.easeInOutCubic.transform(_transitionCtrl.value),
                ambient: _ambientCtrl.value,
                baseBg: colors.bg,
                isDark: colors.isDark,
                intense: widget.intense,
                isPlaying: widget.isPlaying,
              ),
              isComplex: true,
              willChange: widget.animateAmbient || _transitionCtrl.isAnimating,
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _LiquidWavePainter extends CustomPainter {
  const _LiquidWavePainter({
    required this.fromPalette,
    required this.toPalette,
    required this.transition,
    required this.ambient,
    required this.baseBg,
    required this.isDark,
    required this.intense,
    required this.isPlaying,
  });

  final ArtworkPalette fromPalette;
  final ArtworkPalette toPalette;
  final double transition;
  final double ambient;
  final Color baseBg;
  final bool isDark;
  final bool intense;
  final bool isPlaying;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final phase = ambient * math.pi * 2;

    // 1. Gradiente base da paleta anterior (ou já assentada quando transition == 1)
    final activeBasePalette = transition >= 0.999 ? toPalette : fromPalette;
    _paintAtmosphere(canvas, rect, activeBasePalette);

    // 2. Onda de transição trazendo a nova cor de baixo pra cima, mesclando com a capa
    if (transition > 0.001 && transition < 0.999) {
      _paintWaveWash(canvas, size, rect, phase);
    }

    // 3. Correntes líquidas suaves enquanto a música toca
    final livePalette = ArtworkPalette.lerp(fromPalette, toPalette, transition);
    _paintLivingWaves(canvas, size, livePalette, phase);
  }

  void _paintAtmosphere(Canvas canvas, Rect rect, ArtworkPalette palette) {
    final topColor = palette.backdropFor(isDark);
    final midColor = palette.secondaryFor(isDark);
    final stops = intense ? const [0.0, 0.42, 0.80, 1.0] : const [0.0, 0.24, 0.56, 1.0];
    final colors = intense
        ? [
            topColor,
            Color.lerp(topColor, midColor, 0.55)!,
            Color.lerp(midColor, baseBg, isDark ? 0.48 : 0.40)!,
            Color.lerp(midColor, baseBg, isDark ? 0.80 : 0.82)!,
          ]
        : [
            topColor.withValues(alpha: isDark ? 0.52 : 0.48),
            midColor.withValues(alpha: isDark ? 0.24 : 0.22),
            baseBg.withValues(alpha: 0.94),
            baseBg,
          ];

    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: colors,
        stops: stops,
      ).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  void _paintWaveWash(Canvas canvas, Size size, Rect rect, double phase) {
    final newTop = toPalette.backdropFor(isDark);
    final newMid = toPalette.secondaryFor(isDark);
    final newGlow = toPalette.highlightFor(isDark);

    // A nova cor sobe em ondas suaves até cobrir a tela inteira e mesclar com a capa.
    final crestY = size.height * (1.16 - transition * 1.36);

    final wavePath = _buildWavePath(
      size: size,
      baselineY: crestY,
      amplitude: 28 + math.sin(transition * math.pi) * 26,
      frequency: 1.8,
      phase: phase * 1.4 + transition * 4.2,
      fillDownward: true,
    );

    canvas.save();
    canvas.clipPath(wavePath);
    _paintAtmosphere(canvas, rect, toPalette);
    canvas.restore();

    // Cristas translúcidas com desfoque suave para parecer água e não recorte seco.
    final softCrest = _buildWavePath(
      size: size,
      baselineY: crestY - 12,
      amplitude: 34,
      frequency: 1.45,
      phase: -phase * 1.1 + transition * 5.0,
      fillDownward: false,
      bandThickness: 96,
    );
    final glowPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          newGlow.withValues(alpha: 0.0),
          newGlow.withValues(alpha: (isDark ? 0.34 : 0.28) * math.sin(transition * math.pi)),
          newTop.withValues(alpha: (isDark ? 0.42 : 0.34) * math.sin(transition * math.pi)),
          newMid.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, crestY - 70, size.width, 160))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 26);
    canvas.drawPath(softCrest, glowPaint);
  }

  void _paintLivingWaves(Canvas canvas, Size size, ArtworkPalette palette, double phase) {
    final motion = isPlaying ? 1.0 : 0.35;
    // Respiração suave do fundo sincronizada com o play.
    final breath = isPlaying ? (0.86 + 0.28 * (0.5 + 0.5 * math.sin(phase * 2.0))) : 0.80;
    final primary = palette.highlightFor(isDark);
    final secondary = palette.secondaryFor(isDark);

    final y1 = size.height * (intense ? 0.44 : 0.16);
    final band1 = _buildWavePath(
      size: size,
      baselineY: y1,
      amplitude: (intense ? 26.0 : 18.0) * motion,
      frequency: 1.35,
      phase: phase,
      fillDownward: false,
      bandThickness: intense ? 150 : 110,
    );

    final paint1 = Paint()
      ..color = primary.withValues(alpha: ((intense ? (isDark ? 0.14 : 0.18) : (isDark ? 0.09 : 0.12)) * breath).clamp(0.0, 0.30))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 38);
    canvas.drawPath(band1, paint1);

    final y2 = size.height * (intense ? 0.62 : 0.28);
    final band2 = _buildWavePath(
      size: size,
      baselineY: y2,
      amplitude: (intense ? 22.0 : 14.0) * motion,
      frequency: 1.9,
      phase: -phase * 0.85 + 1.7,
      fillDownward: false,
      bandThickness: intense ? 130 : 95,
    );

    final paint2 = Paint()
      ..color = secondary.withValues(alpha: ((intense ? (isDark ? 0.20 : 0.16) : (isDark ? 0.08 : 0.10)) * breath).clamp(0.0, 0.30))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 42);
    canvas.drawPath(band2, paint2);
  }

  Path _buildWavePath({
    required Size size,
    required double baselineY,
    required double amplitude,
    required double frequency,
    required double phase,
    required bool fillDownward,
    double bandThickness = 120,
  }) {
    final path = Path();
    const steps = 28;
    final dx = size.width / steps;

    double waveY(double x) {
      final norm = x / size.width;
      final primary = math.sin(norm * math.pi * 2 * frequency + phase) * amplitude;
      final harmonic = math.cos(norm * math.pi * 2 * (frequency * 1.65) - phase * 0.7) * (amplitude * 0.42);
      return baselineY + primary + harmonic;
    }

    path.moveTo(0, waveY(0));
    for (var i = 1; i <= steps; i++) {
      final x = i * dx;
      path.lineTo(x, waveY(x));
    }

    if (fillDownward) {
      path.lineTo(size.width, size.height + 60);
      path.lineTo(0, size.height + 60);
      path.close();
    } else {
      for (var i = steps; i >= 0; i--) {
        final x = i * dx;
        final lowerOffset = bandThickness + math.cos((x / size.width) * math.pi * 2 + phase * 0.6) * 14;
        path.lineTo(x, waveY(x) + lowerOffset);
      }
      path.close();
    }
    return path;
  }

  @override
  bool shouldRepaint(covariant _LiquidWavePainter oldDelegate) =>
      oldDelegate.fromPalette != fromPalette ||
      oldDelegate.toPalette != toPalette ||
      oldDelegate.transition != transition ||
      oldDelegate.ambient != ambient ||
      oldDelegate.baseBg != baseBg ||
      oldDelegate.isDark != isDark ||
      oldDelegate.intense != intense ||
      oldDelegate.isPlaying != isPlaying;
}

/// Capa full-bleed no topo que se funde suavemente ao gradiente em ondas d'água,
/// idêntico ao visual das fotos de referência (Dawn FM / Michael).
class HeroArtworkBlend extends StatefulWidget {
  const HeroArtworkBlend({
    super.key,
    required this.url,
    this.localBytes,
    required this.palette,
    required this.height,
    this.fallbackIcon = SolarIconsBold.album,
    this.isPlaying = true,
    this.animateWaves = true,
  });

  final String? url;
  final Uint8List? localBytes;
  final ArtworkPalette palette;
  final double height;
  final IconData fallbackIcon;
  final bool isPlaying;
  final bool animateWaves;

  @override
  State<HeroArtworkBlend> createState() => _HeroArtworkBlendState();
}

class _HeroArtworkBlendState extends State<HeroArtworkBlend> with SingleTickerProviderStateMixin {
  late final AnimationController _seamCtrl;

  @override
  void initState() {
    super.initState();
    _seamCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 9));
    if (widget.animateWaves) {
      _seamCtrl.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant HeroArtworkBlend oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animateWaves != oldWidget.animateWaves) {
      if (widget.animateWaves) {
        _seamCtrl.repeat();
      } else {
        _seamCtrl.stop();
      }
    }
  }

  @override
  void dispose() {
    _seamCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.colors.isDark;
    final blendColor = widget.palette.backdropFor(isDark);
    final accentColor = widget.palette.accentFor(isDark);

    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Capa com máscara alfa suave para dissolver direto no fundo em ondas, sem linha de corte
          ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (bounds) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white,
                Colors.white,
                Color(0xA6FFFFFF),
                Color(0x33FFFFFF),
                Colors.transparent,
              ],
              stops: [0.0, 0.42, 0.68, 0.88, 1.0],
            ).createShader(bounds),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 520),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: _CoverImage(
                key: ValueKey(
                  widget.localBytes != null && widget.localBytes!.isNotEmpty
                      ? 'local:${widget.localBytes!.length}'
                      : (widget.url ?? ''),
                ),
                url: widget.url,
                localBytes: widget.localBytes,
                accent: accentColor,
                fallbackBg: blendColor,
                fallbackIcon: widget.fallbackIcon,
              ),
            ),
          ),
          // Vinheta sutil só no topo para legibilidade dos botões de vidro
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.34),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.26],
                ),
              ),
            ),
          ),
          // Onda translúcida suave na região de transição com a capa
          if (widget.animateWaves)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: widget.height * 0.32,
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _seamCtrl,
                  builder: (context, _) => CustomPaint(
                    painter: _CoverSeamWavePainter(
                      blendColor: blendColor,
                      secondaryColor: widget.palette.highlightFor(isDark),
                      phase: _seamCtrl.value * math.pi * 2,
                      amplitudeScale: widget.isPlaying ? 1.0 : 0.45,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CoverImage extends StatelessWidget {
  const _CoverImage({
    super.key,
    required this.url,
    this.localBytes,
    required this.accent,
    required this.fallbackBg,
    required this.fallbackIcon,
  });

  final String? url;
  final Uint8List? localBytes;
  final Color accent;
  final Color fallbackBg;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    if (localBytes != null && localBytes!.isNotEmpty) {
      return Image.memory(
        localBytes!,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _fallback(),
      );
    }
    if (url == null || url!.isEmpty) return _fallback();
    return CachedNetworkImage(
      imageUrl: url!,
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      placeholder: (_, __) => _fallback(),
      errorWidget: (_, __, ___) => _fallback(),
    );
  }

  Widget _fallback() => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [accent.withValues(alpha: 0.60), fallbackBg],
          ),
        ),
        child: Center(
          child: Icon(fallbackIcon, size: 78, color: Colors.white.withValues(alpha: 0.78)),
        ),
      );
}

class _CoverSeamWavePainter extends CustomPainter {
  const _CoverSeamWavePainter({
    required this.blendColor,
    required this.secondaryColor,
    required this.phase,
    required this.amplitudeScale,
  });

  final Color blendColor;
  final Color secondaryColor;
  final double phase;
  final double amplitudeScale;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final path = Path();
    const steps = 24;
    final dx = size.width / steps;
    final base = size.height * 0.62;
    final amp = 11.0 * amplitudeScale;

    double yAt(double x) {
      final n = x / size.width;
      return base + math.sin(n * math.pi * 2.2 + phase) * amp + math.cos(n * math.pi * 3.5 - phase) * (amp * 0.4);
    }

    path.moveTo(0, yAt(0));
    for (var i = 1; i <= steps; i++) {
      final x = i * dx;
      path.lineTo(x, yAt(x));
    }
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();

    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          secondaryColor.withValues(alpha: 0.0),
          Color.lerp(blendColor, secondaryColor, 0.45)!.withValues(alpha: 0.18),
          Colors.transparent,
        ],
      ).createShader(Offset.zero & size)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CoverSeamWavePainter oldDelegate) =>
      oldDelegate.blendColor != blendColor ||
      oldDelegate.secondaryColor != secondaryColor ||
      oldDelegate.phase != phase ||
      oldDelegate.amplitudeScale != amplitudeScale;
}
