// language: Dart, file: lib/engine/engine_utils.dart, target: mobile + desktop, runtime: resong engine
import 'package:dio/dio.dart';

const String kEngineUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

class _CacheEntry {
  _CacheEntry(this.value, this.expiresAtMs);
  final Object? value;
  final int expiresAtMs;
}

class TtlCache {
  final Map<String, _CacheEntry> _map = {};

  T? get<T>(String key) {
    final e = _map[key];
    if (e == null) return null;
    if (DateTime.now().millisecondsSinceEpoch > e.expiresAtMs) {
      _map.remove(key);
      return null;
    }
    if (e.value is T) return e.value as T;
    return null;
  }

  void set(String key, Object? value, Duration ttl) {
    if (_map.length > 600) {
      final now = DateTime.now().millisecondsSinceEpoch;
      _map.removeWhere((_, v) => now > v.expiresAtMs);
      if (_map.length > 600) {
        _map.remove(_map.keys.first);
      }
    }
    _map[key] = _CacheEntry(value, DateTime.now().millisecondsSinceEpoch + ttl.inMilliseconds);
  }

  void deletePrefix(String prefix) {
    _map.removeWhere((k, _) => k.startsWith(prefix));
  }
}

final TtlCache engineCache = TtlCache();

final Set<String> dynamicAllowedHosts = {};

void registerAllowedHost(String rawUrl) {
  try {
    final uri = Uri.parse(rawUrl);
    if ((uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty) {
      dynamicAllowedHosts.add(uri.host.toLowerCase());
    }
  } catch (_) {}
}

bool isHostAllowedForProxy(String host) {
  final lower = host.toLowerCase();
  const suffixes = [
    '.googlevideo.com',
    '.youtube.com',
    '.ytimg.com',
    '.sndcdn.com',
    '.soundcloud.com',
    '.soundcloud.cloud',
    '.media-streaming.soundcloud.cloud',
    '.audius.co',
    '.archive.org',
  ];
  return suffixes.any((s) => lower == s.substring(1) || lower.endsWith(s)) ||
      dynamicAllowedHosts.contains(lower);
}

final Dio engineDio = Dio(
  BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 18),
    headers: {'user-agent': kEngineUserAgent},
    validateStatus: (status) => status != null && status < 500,
  ),
);

int ttlMsFromUrl(String rawUrl) {
  try {
    final uri = Uri.parse(rawUrl);
    final exp = int.tryParse(uri.queryParameters['expire'] ?? '');
    if (exp != null && exp > 0) {
      final deltaMs = exp * 1000 - DateTime.now().millisecondsSinceEpoch - 120000;
      return deltaMs.clamp(60000, 6 * 3600 * 1000);
    }
  } catch (_) {}
  return 4 * 3600 * 1000;
}

String guessAudioMime(String url) {
  final clean = url.split('?').first.toLowerCase();
  if (clean.endsWith('.m4a') || url.contains('audio/mp4') || url.contains('mime=audio%2Fmp4')) {
    return 'audio/mp4';
  }
  if (clean.endsWith('.webm') || url.contains('audio/webm') || url.contains('mime=audio%2Fwebm')) {
    return 'audio/webm';
  }
  if (clean.endsWith('.mp3') || url.contains('audio/mpeg')) return 'audio/mpeg';
  if (clean.endsWith('.flac')) return 'audio/flac';
  if (clean.endsWith('.ogg')) return 'audio/ogg';
  return 'audio/mp4';
}

String extFromMime(String mime, String url) {
  final cleanUrl = url.split('?').first.toLowerCase();
  if (mime.contains('mp4') || mime.contains('aac') || cleanUrl.endsWith('.m4a')) return 'm4a';
  if (mime.contains('mpeg') || cleanUrl.endsWith('.mp3')) return 'mp3';
  if (mime.contains('flac') || cleanUrl.endsWith('.flac')) return 'flac';
  if (mime.contains('webm') || cleanUrl.endsWith('.webm')) return 'webm';
  if (mime.contains('ogg') || cleanUrl.endsWith('.ogg')) return 'ogg';
  return 'm4a';
}

final _noiseParensRx = RegExp(
  r'\s*[([](?:feat\.?|ft\.?|part\.?\s+[^)\]]+|with\s+[^)\]]+|official\s+(?:music\s+)?video|official\s+audio|clipe\s+oficial|v[ií]deo\s+oficial|lyric\s+video|audio|visualizer|live|ao\s+vivo|dvd[^)\]]*|ac[uú]stico[^)\]]*|hd|4k|remaster(?:ed)?(?:\s+\d{4})?)[^)\]]*[)\]]',
  caseSensitive: false,
);
final _trailingFeatRx = RegExp(r'\s+(?:feat\.?|ft\.?)\s+.+$', caseSensitive: false);
final _trailingPipeRx = RegExp(r'\s*(?:\||\/\/).*$');
final _trailingHyphenNoiseRx = RegExp(
  r'\s+[-–—]\s+(?:ao\s+vivo(?:\b.*)?|dvd(?:\b.*)?|v[ií]deo\s+oficial.*|clipe\s+oficial.*|official\s+(?:music\s+)?(?:video|audio).*|lyric\s+video.*|ac[uú]stico.*|vers[aã]o\s+.*|remaster(?:ed)?(?:\s+\d{4})?.*|turn[eê]\b.*|live\s+at\b.*|live\s+in\b.*)$',
  caseSensitive: false,
);
final _topicSuffixRx = RegExp(r'\s*-\s*Topic$', caseSensitive: false);

String stripAccents(String input) {
  const src = 'áàãâäéèêëíìîïóòõôöúùûüçñýÿÁÀÃÂÄÉÈÊËÍÌÎÏÓÒÕÔÖÚÙÛÜÇÑÝ';
  const dst = 'aaaaaeeeeiiiiooooouuuucnyyAAAAAEEEEIIIIOOOOOUUUUCNY';
  final sb = StringBuffer();
  for (var i = 0; i < input.length; i++) {
    final idx = src.indexOf(input[i]);
    sb.write(idx >= 0 ? dst[idx] : input[i]);
  }
  return sb.toString();
}

String cleanArtistName(String raw) =>
    raw.replaceAll(_topicSuffixRx, '').replaceAll(RegExp(r'\s+'), ' ').trim();

String cleanMusicQuery(String raw) {
  var out = raw
      .replaceAll(_trailingPipeRx, '')
      .replaceAll(_noiseParensRx, ' ')
      .replaceAll(_trailingFeatRx, '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  for (var i = 0; i < 3; i++) {
    final next = out.replaceAll(_trailingHyphenNoiseRx, '').trim();
    if (next == out || next.isEmpty) break;
    out = next;
  }
  return out;
}

String normCompareText(String raw) => stripAccents(raw)
    .toLowerCase()
    .replaceAll('&', ' e ')
    .replaceAll(RegExp(r'\band\b'), ' e ')
    .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

double tokenSimilarity(String expected, String actual) {
  final a = normCompareText(expected);
  final b = normCompareText(actual);
  if (a.isEmpty || b.isEmpty) return 0;
  if (a == b) return 1;
  if (a.contains(b) || b.contains(a)) return 0.85;
  final setA = a.split(' ').where((s) => s.isNotEmpty).toSet();
  final setB = b.split(' ').where((s) => s.isNotEmpty).toSet();
  final inter = setA.intersection(setB).length;
  final union = setA.length + setB.length - inter;
  return union > 0 ? inter / union : 0;
}

({String track, String? artist}) extractCleanTrack(String rawTitle, [String? rawArtist]) {
  final artistClean = rawArtist != null && rawArtist.trim().isNotEmpty ? cleanArtistName(rawArtist) : null;
  var title = rawTitle.replaceAll(_trailingPipeRx, '').replaceAll(RegExp(r'\s+'), ' ').trim();

  final dashMatch = RegExp(r'^(.+?)\s+[-–—]\s+(.+)$').firstMatch(title);
  var inferredArtist = artistClean;
  if (dashMatch != null) {
    final prefix = dashMatch.group(1)!.trim();
    final rest = dashMatch.group(2)!.trim();
    final normPrefix = normCompareText(prefix);
    final normArtist = artistClean != null ? normCompareText(artistClean) : '';
    final matchesArtist = normArtist.isNotEmpty &&
        normPrefix.isNotEmpty &&
        (normPrefix == normArtist || normArtist.contains(normPrefix) || normPrefix.contains(normArtist));
    if (matchesArtist && rest.isNotEmpty) {
      title = rest;
    } else if (artistClean == null && prefix.length >= 2 && rest.length >= 2) {
      inferredArtist = cleanArtistName(prefix);
      title = rest;
    }
  }

  final cleaned = cleanMusicQuery(title);
  return (
    track: cleaned.isNotEmpty ? cleaned : (title.isNotEmpty ? title : rawTitle.trim()),
    artist: (inferredArtist != null && inferredArtist.isNotEmpty) ? inferredArtist : null,
  );
}

int? parseDurationSeconds(String text) {
  final m = RegExp(r'^(?:(\d+):)?(\d{1,2}):(\d{2})$').firstMatch(text.trim());
  if (m == null) return null;
  final h = m.group(1) != null ? int.parse(m.group(1)!) : 0;
  return h * 3600 + int.parse(m.group(2)!) * 60 + int.parse(m.group(3)!);
}

class ResolvedStreamResult {
  const ResolvedStreamResult({
    required this.kind, // 'direct' | 'hls'
    required this.url,
    required this.mime,
    required this.expiresAtMs,
  });

  final String kind;
  final String url;
  final String mime;
  final int expiresAtMs;
}
