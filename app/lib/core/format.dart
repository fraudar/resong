// language: Dart, file: lib/core/format.dart, target: mobile-first + desktop, runtime: resong app

String formatDuration(int? ms) {
  if (ms == null || ms <= 0) return '';
  final total = ms ~/ 1000;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final mm = h > 0 ? m.toString().padLeft(2, '0') : '$m';
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

String formatBytes(int? bytes) {
  if (bytes == null || bytes <= 0) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

String formatCount(int? n) {
  if (n == null) return '';
  if (n < 1000) return '$n';
  if (n < 1000000) return '${(n / 1000).toStringAsFixed(n < 10000 ? 1 : 0)} mil';
  if (n < 1000000000) return '${(n / 1000000).toStringAsFixed(1)} mi';
  return '${(n / 1000000000).toStringAsFixed(1)} bi';
}

String formatWhen(int epochMs) {
  if (epochMs <= 0) return '';
  final diff = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(epochMs));
  if (diff.inMinutes < 1) return 'agora';
  if (diff.inHours < 1) return 'há ${diff.inMinutes} min';
  if (diff.inDays < 1) return 'há ${diff.inHours} h';
  if (diff.inDays < 30) return 'há ${diff.inDays} d';
  final d = DateTime.fromMillisecondsSinceEpoch(epochMs);
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

typedef HandleValidation = ({bool ok, String value, String? reason});

final _invisibleOrControlRx = RegExp(
  r'[\u0000-\u001F\u007F-\u009F\u200B-\u200F\u202A-\u202E\u2060\u2066-\u2069\uFEFF]',
);
final _allowedHandleRx = RegExp(r'^[\p{L}\p{N} _.\-@]+$', unicode: true);
final _hasAlnumRx = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// Valida/higieniza localmente espelhando `sanitize_handle` do backend (fallback offline/testes).
HandleValidation sanitizeHandleLocal(String input) {
  final cleaned = input
      .replaceAll(_invisibleOrControlRx, '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (cleaned.isEmpty) {
    return (ok: false, value: '', reason: 'Informe um nome com 2 a 32 caracteres.');
  }
  if (cleaned.length < 2 || cleaned.length > 32) {
    return (
      ok: false,
      value: cleaned.length > 32 ? cleaned.substring(0, 32) : cleaned,
      reason: 'O nome deve ter entre 2 e 32 caracteres.',
    );
  }
  if (!_allowedHandleRx.hasMatch(cleaned)) {
    return (
      ok: false,
      value: cleaned,
      reason: 'Use apenas letras, números, espaços e _ . - @.',
    );
  }
  if (!_hasAlnumRx.hasMatch(cleaned)) {
    return (ok: false, value: cleaned, reason: 'Use pelo menos uma letra ou número.');
  }
  return (ok: true, value: cleaned, reason: null);
}
