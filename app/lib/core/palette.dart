// language: Dart, file: lib/core/palette.dart, target: mobile-first + desktop, runtime: resong app
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

/// Paleta multi-tom coesa extraída da capa: alimenta o fundo em ondas,
/// o glow da capa quadrada, controles em vidro e acentos da UI.
@immutable
class ArtworkPalette {
  const ArtworkPalette({
    required this.accent,
    required this.backdrop,
    required this.secondary,
    required this.highlight,
    this.isFallback = false,
  });

  final Color accent;
  final Color backdrop;
  final Color secondary;
  final Color highlight;
  final bool isFallback;

  static const fallback = ArtworkPalette(
    accent: Color(0xFF9D8BFF),
    backdrop: Color(0xFF151828),
    secondary: Color(0xFF0C0E18),
    highlight: Color(0xFF6B5CE7),
    isFallback: true,
  );

  /// Tom principal do fundo adaptado ao modo Black ou Light, preservando o matiz da capa.
  Color backdropFor(bool isDark) {
    final hsl = HSLColor.fromColor(backdrop);
    if (isDark) {
      return hsl
          .withSaturation(hsl.saturation.clamp(0.16, 0.62))
          .withLightness(hsl.lightness.clamp(0.15, 0.26))
          .toColor();
    }
    return hsl
        .withSaturation(hsl.saturation.clamp(0.16, 0.44))
        .withLightness(0.88)
        .toColor();
  }

  /// Segundo tom harmônico (profundidade sem contraste bruto de matiz).
  Color secondaryFor(bool isDark) {
    final hsl = HSLColor.fromColor(secondary);
    if (isDark) {
      return hsl
          .withSaturation(hsl.saturation.clamp(0.14, 0.56))
          .withLightness(hsl.lightness.clamp(0.08, 0.16))
          .toColor();
    }
    return hsl
        .withSaturation(hsl.saturation.clamp(0.18, 0.46))
        .withLightness(0.81)
        .toColor();
  }

  /// Brilho suave das ondas e glow atrás da capa.
  Color highlightFor(bool isDark) {
    final hsl = HSLColor.fromColor(highlight);
    if (isDark) {
      return hsl
          .withSaturation(hsl.saturation.clamp(0.24, 0.72))
          .withLightness(hsl.lightness.clamp(0.32, 0.50))
          .toColor();
    }
    return hsl
        .withSaturation(hsl.saturation.clamp(0.24, 0.58))
        .withLightness(0.92)
        .toColor();
  }

  /// Acento vivo e legível para botões, barra ondulada e destaques.
  Color accentFor(bool isDark) {
    final hsl = HSLColor.fromColor(accent);
    if (isDark) {
      return hsl
          .withSaturation(hsl.saturation.clamp(0.34, 0.85))
          .withLightness(hsl.lightness.clamp(0.60, 0.78))
          .toColor();
    }
    return hsl
        .withSaturation(hsl.saturation.clamp(0.42, 0.88))
        .withLightness(hsl.lightness.clamp(0.34, 0.46))
        .toColor();
  }

  static ArtworkPalette lerp(ArtworkPalette a, ArtworkPalette b, double t) {
    final clamped = t.clamp(0.0, 1.0);
    return ArtworkPalette(
      accent: Color.lerp(a.accent, b.accent, clamped)!,
      backdrop: Color.lerp(a.backdrop, b.backdrop, clamped)!,
      secondary: Color.lerp(a.secondary, b.secondary, clamped)!,
      highlight: Color.lerp(a.highlight, b.highlight, clamped)!,
      isFallback: clamped < 0.5 ? a.isFallback : b.isFallback,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ArtworkPalette &&
      accent == other.accent &&
      backdrop == other.backdrop &&
      secondary == other.secondary &&
      highlight == other.highlight &&
      isFallback == other.isFallback;

  @override
  int get hashCode => Object.hash(accent, backdrop, secondary, highlight, isFallback);
}

final Map<String, ArtworkPalette> _paletteCache = {};

/// Consulta síncrona de cache para evitar flash de cor ao reabrir telas.
ArtworkPalette? cachedPaletteForArtwork(String? url) {
  if (url == null || url.isEmpty) return null;
  return _paletteCache[url];
}

/// Extrai uma paleta coesa da capa (estilo Material You / Square / Apple Music).
Future<ArtworkPalette> paletteFromArtwork(String? url) async {
  if (url == null || url.isEmpty) return ArtworkPalette.fallback;
  final hit = _paletteCache[url];
  if (hit != null) return hit;

  ArtworkPalette result = ArtworkPalette.fallback;
  try {
    final palette = await PaletteGenerator.fromImageProvider(
      NetworkImage(url),
      maximumColorCount: 24,
      size: const Size(96, 96),
    );
    result = _buildCohesivePalette(palette);
  } catch (_) {
    result = _seededFallback(url);
  }
  _paletteCache[url] = result;
  return result;
}

Future<Color> accentFromArtwork(String? url) async => (await paletteFromArtwork(url)).accent;

ArtworkPalette _buildCohesivePalette(PaletteGenerator pg) {
  final ordered = List<PaletteColor>.from(pg.paletteColors)
    ..sort((a, b) => b.population.compareTo(a.population));

  final backdropCandidate = _pickBackdrop(pg, ordered);
  final tunedBackdrop = _tuneBackdrop(backdropCandidate);
  final baseHue = HSLColor.fromColor(tunedBackdrop).hue;

  final accentCandidate = _pickHarmoniousAccent(pg, ordered, baseHue, tunedBackdrop);
  final secondaryCandidate = _harmonizeHue(
    _pickSecondary(pg, ordered, tunedBackdrop),
    baseHue,
    maxHueDelta: 24,
    targetLightness: 0.13,
  );
  final highlightCandidate = _harmonizeHue(
    accentCandidate,
    baseHue,
    maxHueDelta: 18,
    targetLightness: 0.44,
  );

  return ArtworkPalette(
    accent: accentCandidate,
    backdrop: tunedBackdrop,
    secondary: secondaryCandidate,
    highlight: highlightCandidate,
  );
}

Color _pickBackdrop(PaletteGenerator pg, List<PaletteColor> ordered) {
  final preferred = [
    pg.dominantColor?.color,
    pg.mutedColor?.color,
    pg.darkVibrantColor?.color,
    pg.darkMutedColor?.color,
    pg.vibrantColor?.color,
  ].whereType<Color>();

  for (final c in preferred) {
    final hsl = HSLColor.fromColor(c);
    if (hsl.saturation >= 0.10 && hsl.lightness >= 0.08 && hsl.lightness <= 0.80) {
      return c;
    }
  }
  for (final pc in ordered) {
    final hsl = HSLColor.fromColor(pc.color);
    if (hsl.lightness >= 0.08 && hsl.lightness <= 0.85) return pc.color;
  }
  return pg.dominantColor?.color ?? ArtworkPalette.fallback.backdrop;
}

Color _pickHarmoniousAccent(
  PaletteGenerator pg,
  List<PaletteColor> ordered,
  double baseHue,
  Color backdrop,
) {
  final preferred = [
    pg.lightVibrantColor?.color,
    pg.vibrantColor?.color,
    pg.lightMutedColor?.color,
    pg.dominantColor?.color,
  ].whereType<Color>();

  Color? best;
  double bestScore = -1;
  for (final c in [...preferred, ...ordered.map((e) => e.color)]) {
    final hsl = HSLColor.fromColor(c);
    if (hsl.lightness < 0.20 || hsl.lightness > 0.90) continue;
    final hueDist = _hueDistance(hsl.hue, baseHue);
    // Favorece cores harmônicas próximas ao matiz principal (como sálvia, areia, coral).
    final harmonyBonus = hueDist < 42 ? 0.55 : 0.0;
    final score = hsl.saturation * 1.2 + (1.0 - (hsl.lightness - 0.65).abs()) * 0.7 + harmonyBonus;
    if (score > bestScore) {
      bestScore = score;
      best = c;
    }
  }

  final chosen = best ?? backdrop;
  final hsl = HSLColor.fromColor(chosen);
  final hue = _hueDistance(hsl.hue, baseHue) > 55 ? baseHue : hsl.hue;
  return HSLColor.fromAHSL(
    1,
    hue,
    hsl.saturation < 0.22 ? 0.34 : hsl.saturation.clamp(0.36, 0.86),
    hsl.lightness.clamp(0.58, 0.76),
  ).toColor();
}

Color _pickSecondary(PaletteGenerator pg, List<PaletteColor> ordered, Color backdrop) {
  final candidates = [
    pg.darkMutedColor?.color,
    pg.darkVibrantColor?.color,
    pg.mutedColor?.color,
    ...ordered.map((e) => e.color),
  ].whereType<Color>();
  for (final c in candidates) {
    if (c != backdrop) return c;
  }
  return backdrop;
}

Color _harmonizeHue(
  Color c,
  double baseHue, {
  required double maxHueDelta,
  required double targetLightness,
}) {
  final hsl = HSLColor.fromColor(c);
  final delta = _signedHueDelta(baseHue, hsl.hue);
  final clampedDelta = delta.clamp(-maxHueDelta, maxHueDelta);
  final hue = (baseHue + clampedDelta + 360) % 360;
  final sat = hsl.saturation < 0.08 ? 0.16 : hsl.saturation.clamp(0.18, 0.58);
  return HSLColor.fromAHSL(1, hue, sat, targetLightness).toColor();
}

double _hueDistance(double a, double b) {
  final d = (a - b).abs();
  return d > 180 ? 360 - d : d;
}

double _signedHueDelta(double from, double to) {
  var d = (to - from + 540) % 360 - 180;
  return d;
}

Color _tuneBackdrop(Color c) {
  final hsl = HSLColor.fromColor(c);
  final sat = hsl.saturation < 0.08 ? 0.12 : hsl.saturation.clamp(0.18, 0.58);
  final light = hsl.lightness.clamp(0.17, 0.26);
  return hsl.withSaturation(sat).withLightness(light).toColor();
}

ArtworkPalette _seededFallback(String seed) {
  final hash = seed.codeUnits.fold<int>(0, (acc, v) => (acc * 31 + v) & 0x7fffffff);
  final hue = (hash % 360).toDouble();
  final accent = HSLColor.fromAHSL(1, hue, 0.58, 0.68).toColor();
  final backdrop = HSLColor.fromAHSL(1, hue, 0.36, 0.21).toColor();
  final secondary = HSLColor.fromAHSL(1, (hue + 14) % 360, 0.38, 0.13).toColor();
  final highlight = HSLColor.fromAHSL(1, (hue + 8) % 360, 0.48, 0.44).toColor();
  return ArtworkPalette(accent: accent, backdrop: backdrop, secondary: secondary, highlight: highlight);
}
