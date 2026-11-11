// language: Dart, file: lib/widgets/artwork.dart, target: mobile-first + desktop, runtime: resong app
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:solar_icons_flutter/solar_icons_flutter.dart';

import '../core/theme.dart';

/// Capa com canto arredondado, placeholder sutil e fallback quando a URL morre.
/// Quando [localBytes] está presente, prevalece sobre [url].
class Artwork extends StatelessWidget {
  const Artwork({
    super.key,
    required this.url,
    this.localBytes,
    this.size = 56,
    this.radius = 14,
    this.tone = AppColors.accent,
    this.icon = SolarIconsBold.musicNote,
  });

  final String? url;
  final Uint8List? localBytes;
  final double size;
  final double radius;
  final Color tone;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasLocal = localBytes != null && localBytes!.isNotEmpty;
    final child = hasLocal
        ? Image.memory(
            localBytes!,
            fit: BoxFit.cover,
            width: size,
            height: size,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => _fallback(colors),
          )
        : (url == null || url!.isEmpty
            ? _fallback(colors)
            : CachedNetworkImage(
                imageUrl: url!,
                fit: BoxFit.cover,
                width: size,
                height: size,
                placeholder: (_, __) => Container(color: colors.surface),
                errorWidget: (_, __, ___) => _fallback(colors),
              ));

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(width: size, height: size, child: child),
    );
  }

  Widget _fallback(ThemeColors colors) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [tone.withValues(alpha: 0.55), colors.bgElevated],
          ),
        ),
        child: Center(
          child: Icon(icon, size: size * 0.42, color: colors.textPrimary.withValues(alpha: 0.85)),
        ),
      );
}
