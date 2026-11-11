// language: Dart, file: lib/core/local_image.dart, target: mobile-first + desktop + web, runtime: resong app
import 'dart:typed_data';
import 'dart:ui' as ui;

const int kMaxLocalCoverBytes = 512 * 1024; // ~512 KB

/// Redimensiona e comprime uma imagem selecionada pelo usuário até caber em `maxBytes`.
Future<Uint8List?> compressLocalCoverBytes(
  Uint8List rawBytes, {
  int targetWidth = 320,
  int maxBytes = kMaxLocalCoverBytes,
}) async {
  if (rawBytes.isEmpty) return null;

  for (final width in [targetWidth, (targetWidth * 0.72).round(), 160]) {
    if (width <= 0) continue;
    try {
      final codec = await ui
          .instantiateImageCodec(rawBytes, targetWidth: width)
          .timeout(const Duration(seconds: 3));
      final frame = await codec.getNextFrame().timeout(const Duration(seconds: 3));
      final data = await frame.image
          .toByteData(format: ui.ImageByteFormat.png)
          .timeout(const Duration(seconds: 3));
      frame.image.dispose();
      codec.dispose();
      if (data != null) {
        final png = data.buffer.asUint8List();
        if (png.lengthInBytes <= maxBytes) return png;
      }
    } catch (_) {
      break; // Ex.: codec ausente em teste headless com bytes mockados
    }
  }

  return rawBytes.lengthInBytes <= maxBytes ? rawBytes : null;
}
