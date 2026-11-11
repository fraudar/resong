// language: Dart, file: lib/engine/addon_client.dart, target: mobile + desktop, runtime: resong engine
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import 'engine_utils.dart';
import 'local_store.dart';

class AddonClient {
  AddonClient._();
  static final AddonClient instance = AddonClient._();

  final Map<String, Map<String, dynamic>> _trackCache = {};
  final Map<String, String> _fallbackRowStreams = {};
  final Map<String, ({int cooldownUntil, int backoffMs})> _cooldowns = {};

  ({String configId, String remoteId})? parseAddonTrackId(String fullId) {
    if (!fullId.startsWith('addon:')) return null;
    final rest = fullId.substring(6);
    final idx = rest.indexOf(':');
    if (idx <= 0 || idx >= rest.length - 1) return null;
    return (configId: rest.substring(0, idx), remoteId: rest.substring(idx + 1));
  }

  String _normalizeUrl(String raw) {
    final trimmed = raw.trim();
    final withScheme = RegExp(r'^https?://', caseSensitive: false).hasMatch(trimmed)
        ? trimmed
        : 'https://$trimmed';
    final uri = Uri.parse(withScheme);
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw Exception('URL do addon deve usar http ou https');
    }
    var path = uri.path.replaceAll(RegExp(r'/+$'), '');
    if (path.endsWith('/manifest.json')) {
      path = path.substring(0, path.length - '/manifest.json'.length);
    }
    final cleaned = uri.replace(path: path, query: null, fragment: null).toString();
    return cleaned.replaceAll(RegExp(r'/+$'), '');
  }

  String _makeConfigId(String baseUrl, [String? manifestId]) {
    var seed = (manifestId ?? baseUrl)
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (seed.length > 24) seed = seed.substring(0, 24);
    final hash = sha1.convert(utf8.encode(baseUrl)).toString().substring(0, 6);
    return '${seed.isNotEmpty ? seed : 'addon'}-$hash';
  }

  Future<({int status, Object? json})> _addonFetch(
    String baseUrl,
    String pathWithQuery, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final cd = _cooldowns[baseUrl];
    final now = DateTime.now().millisecondsSinceEpoch;
    if (cd != null && now < cd.cooldownUntil) {
      return (status: 429, json: null);
    }
    try {
      final res = await engineDio.get<Object?>(
        '$baseUrl$pathWithQuery',
        options: Options(
          sendTimeout: timeout,
          receiveTimeout: timeout,
          headers: {'accept': 'application/json'},
        ),
      );
      final status = res.statusCode ?? 500;
      if (status == 429) {
        final prevBackoff = cd?.backoffMs ?? 500;
        var waitMs = prevBackoff;
        final retryAfter = res.headers.value('retry-after');
        if (retryAfter != null) {
          final secs = double.tryParse(retryAfter);
          if (secs != null && secs >= 0) {
            waitMs = (secs * 1000).round().clamp(500, 60000);
          }
        }
        _cooldowns[baseUrl] = (
          cooldownUntil: now + waitMs,
          backoffMs: (prevBackoff * 2).clamp(500, 8000),
        );
        return (status: 429, json: null);
      }
      if (status < 200 || status >= 400) {
        return (status: status, json: null);
      }
      _cooldowns.remove(baseUrl);
      final data = res.data is String ? jsonDecode(res.data as String) : res.data;
      return (status: status, json: data);
    } catch (_) {
      return (status: 502, json: null);
    }
  }

  List<String> _parseQualityOptions(Object? raw) {
    if (raw is! List) return const [];
    final out = <String>[];
    for (final item in raw) {
      if (item is String && item.trim().isNotEmpty) {
        out.add(item.trim());
      } else if (item is Map) {
        final v = (item['id'] ?? item['tier'] ?? item['value'] ?? item['name'] ?? item['label'] ?? '').toString().trim();
        if (v.isNotEmpty) out.add(v);
      }
    }
    return out;
  }

  Future<Map<String, dynamic>> identifyAddon(
    String rawUrl, {
    String? customLabel,
    bool force = false,
  }) async {
    final baseUrl = _normalizeUrl(rawUrl);
    final cacheKey = 'addon:manifest:$baseUrl';
    if (!force) {
      final cached = engineCache.get<Map<String, dynamic>>(cacheKey);
      if (cached != null) {
        if (customLabel != null && customLabel.trim().isNotEmpty) {
          return {...cached, 'label': customLabel.trim()};
        }
        return cached;
      }
    }

    final fetched = await _addonFetch(baseUrl, '/manifest.json');
    if (fetched.status >= 400 || fetched.json is! Map) {
      throw Exception('Manifest inválido (${fetched.status}) em $baseUrl/manifest.json');
    }
    final raw = (fetched.json as Map).cast<String, dynamic>();
    final manifestId = raw['id'] as String?;
    final manifestName = (raw['name'] as String?)?.trim() ??
        (raw['label'] as String?)?.trim() ??
        Uri.parse(baseUrl).host;
    final allowRaw = raw['allowDownloads'] ?? raw['allow_downloads'] ?? true;
    final allowDownloads = !(allowRaw == false || allowRaw == 0 || allowRaw == '0' || allowRaw == 'false');
    final qualityOptions = _parseQualityOptions(raw['qualityOptions'] ?? raw['quality_options'] ?? raw['qualities']);
    final versionRaw = raw['schemaVersion'] ?? raw['protocolVersion'];
    final status = (versionRaw is num && versionRaw > 1) ? 'desatualizado' : 'ok';

    final identified = <String, dynamic>{
      'id': _makeConfigId(baseUrl, manifestId),
      'base_url': baseUrl,
      'label': (customLabel != null && customLabel.trim().isNotEmpty) ? customLabel.trim() : manifestName,
      'allow_downloads': allowDownloads,
      'quality_options': qualityOptions,
      'manifest_json': jsonEncode(raw),
      'last_status': status,
      'last_checked_at': DateTime.now().millisecondsSinceEpoch,
      'enabled': true,
    };
    engineCache.set(cacheKey, identified, const Duration(minutes: 30));
    return identified;
  }

  Future<Map<String, dynamic>?> checkSourceHealth(String id) async {
    final source = LocalStore.instance.getAddonSource(id);
    if (source == null) return null;
    try {
      final info = await identifyAddon(
        source['base_url'] as String,
        customLabel: source['label'] as String?,
        force: true,
      );
      return await LocalStore.instance.updateAddonSource(id, {
        'last_status': info['last_status'],
        'last_checked_at': info['last_checked_at'],
        'allow_downloads': info['allow_downloads'],
        'quality_options': info['quality_options'],
        'manifest_json': info['manifest_json'],
      });
    } catch (_) {
      return await LocalStore.instance.updateAddonSource(id, {
        'last_status': 'inacessivel',
        'last_checked_at': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

  String _mapQuality(List<dynamic>? options, String tier) {
    final opts = options?.map((e) => e.toString()).toList() ?? const <String>[];
    if (opts.isEmpty) return tier;
    for (final o in opts) {
      if (o.toUpperCase() == tier.toUpperCase()) return o;
    }
    const aliases = {
      'LOSSLESS': ['FLAC', 'HI_RES', 'HIRES', 'MASTER', 'MAX', 'CD'],
      'HIGH': ['320', 'AAC', 'OGG', 'BEST', 'MP3'],
      'LOW': ['128', '96', 'DATA', 'SAVER', 'OPUS'],
    };
    for (final needle in aliases[tier.toUpperCase()] ?? const <String>[]) {
      for (final o in opts) {
        if (o.toUpperCase().contains(needle)) return o;
      }
    }
    return tier;
  }

  bool _durationMatches(int? expectedMs, int? candidateMs) {
    if (expectedMs == null || expectedMs <= 0 || candidateMs == null || candidateMs <= 0) {
      return true;
    }
    return (expectedMs - candidateMs).abs() <= 5500;
  }

  String _absolutizeUrl(String rawUrl, String baseUrl) {
    try {
      return Uri.parse('$baseUrl/').resolve(rawUrl).toString();
    } catch (_) {
      return rawUrl;
    }
  }

  Map<String, dynamic>? _mapRemoteTrack(Map<String, dynamic> source, Map<String, dynamic> raw) {
    final remoteId = (raw['id'] ?? raw['trackId'] ?? raw['track_id'] ?? '').toString().trim();
    final title = (raw['title'] ?? raw['name'] ?? '').toString().trim();
    if (remoteId.isEmpty || title.isEmpty) return null;

    final artists = raw['artists'] is List
        ? (raw['artists'] as List).map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList()
        : raw['artist'] is String && (raw['artist'] as String).trim().isNotEmpty
            ? [(raw['artist'] as String).trim()]
            : raw['artistName'] is String && (raw['artistName'] as String).trim().isNotEmpty
                ? [(raw['artistName'] as String).trim()]
                : ['Desconhecido'];

    int? durMs;
    final durRaw = raw['duration_ms'] ?? raw['durationMs'] ?? raw['duration'];
    if (durRaw is num) {
      durMs = (durRaw > 10000 ? durRaw : durRaw * 1000).round();
    }

    final rowStream = (raw['streamURL'] ?? raw['streamUrl'] ?? raw['stream_url']) as String?;
    final fullId = 'addon:${source['id']}:$remoteId';
    final resolvedStream = rowStream != null && rowStream.trim().isNotEmpty
        ? _absolutizeUrl(rowStream.trim(), source['base_url'] as String)
        : null;
    if (resolvedStream != null) {
      _fallbackRowStreams[fullId] = resolvedStream;
    }

    final artworkRaw = raw['artwork'] ?? raw['cover'] ?? raw['thumbnail'] ?? raw['coverUrl'] ?? raw['image'];
    final track = <String, dynamic>{
      'id': fullId,
      'source': 'addon',
      'title': title,
      'artists': artists,
      if (raw['album'] is String) 'album': raw['album'],
      'artwork': artworkRaw is String && artworkRaw.isNotEmpty
          ? _absolutizeUrl(artworkRaw, source['base_url'] as String)
          : null,
      'duration_ms': durMs,
      'explicit': raw['explicit'] == true,
      'extra': {
        'source_label': source['label'],
        if (resolvedStream != null) 'stream_url': resolvedStream,
      },
    };
    _trackCache[fullId] = track;
    return track;
  }

  Map<String, dynamic>? getCachedTrack(String fullId) => _trackCache[fullId];

  Future<List<Map<String, dynamic>>> searchSource(
    Map<String, dynamic> source,
    String query, {
    int limit = 12,
    String tier = 'HIGH',
  }) async {
    if (source['enabled'] == false) return const [];
    final mappedQuality = _mapQuality(source['quality_options'] as List?, tier);
    final cacheKey = 'addon:search:${source['id']}:$mappedQuality:${query.toLowerCase()}';
    final cached = engineCache.get<List<Map<String, dynamic>>>(cacheKey);
    if (cached != null) return cached.take(limit).toList();

    final path = '/search?q=${Uri.encodeQueryComponent(query)}&quality=${Uri.encodeQueryComponent(mappedQuality)}';
    final fetched = await _addonFetch(source['base_url'] as String, path);
    if (fetched.status == 404 || fetched.status >= 500 || fetched.json == null) {
      if (fetched.status >= 500) {
        await LocalStore.instance.updateAddonSource(source['id'] as String, {
          'last_status': 'inacessivel',
          'last_checked_at': DateTime.now().millisecondsSinceEpoch,
        });
      }
      return const [];
    }

    final rows = fetched.json is List
        ? fetched.json as List
        : fetched.json is Map
            ? ((fetched.json as Map)['tracks'] ??
                (fetched.json as Map)['results'] ??
                (fetched.json as Map)['items'] ??
                const []) as List
            : const [];

    final tracks = <Map<String, dynamic>>[];
    for (final r in rows.whereType<Map>()) {
      final mapped = _mapRemoteTrack(source, r.cast<String, dynamic>());
      if (mapped != null) tracks.add(mapped);
    }

    await LocalStore.instance.updateAddonSource(source['id'] as String, {
      'last_status': 'ok',
      'last_checked_at': DateTime.now().millisecondsSinceEpoch,
    });
    engineCache.set(cacheKey, tracks, const Duration(minutes: 10));
    return tracks.take(limit).toList();
  }

  Future<List<Map<String, dynamic>>> searchEnabledAddons(String query, {int limit = 15}) async {
    final sources = LocalStore.instance.listAddonSources().where((s) => s['enabled'] != false).toList();
    if (sources.isEmpty) return const [];
    final results = await Future.wait(sources.map((src) => searchSource(src, query, limit: limit)));
    return [for (final list in results) ...list];
  }

  ResolvedStreamResult? _resolvePayload(
    Object? payload,
    Map<String, dynamic> source,
    int? expectedDurationMs,
  ) {
    if (payload is! Map) return null;
    final obj = payload.cast<String, dynamic>();
    final durRaw = obj['duration_ms'] ?? obj['durationMs'] ?? obj['duration'];
    final durMs = durRaw is num ? (durRaw > 10000 ? durRaw.round() : (durRaw * 1000).round()) : null;
    if (!_durationMatches(expectedDurationMs, durMs)) return null;

    final rawUrl = (obj['streamURL'] ?? obj['streamUrl'] ?? obj['stream_url'] ?? obj['url'] ?? obj['playlist_url']) as String?;
    if (rawUrl == null || rawUrl.trim().isEmpty) return null;
    final url = _absolutizeUrl(rawUrl.trim(), source['base_url'] as String);
    registerAllowedHost(url);

    final now = DateTime.now().millisecondsSinceEpoch;
    final expRaw = obj['expires_at'] ?? obj['expiresAt'];
    final expiresAt = (expRaw is num && expRaw > now) ? expRaw.toInt() : now + 3 * 3600 * 1000;
    final isHls = obj['kind'] == 'hls' || url.contains('.m3u8');
    return ResolvedStreamResult(
      kind: isHls ? 'hls' : 'direct',
      url: url,
      mime: isHls
          ? 'application/vnd.apple.mpegurl'
          : ((obj['mime'] ?? obj['mimeType'] ?? guessAudioMime(url)).toString()),
      expiresAtMs: expiresAt,
    );
  }

  Future<ResolvedStreamResult?> resolveStream(
    String configId,
    String remoteId, {
    int? durationMs,
    String tier = 'HIGH',
  }) async {
    final fullId = 'addon:$configId:$remoteId';
    final cacheKey = 'addon:stream:$fullId:$tier';
    final now = DateTime.now().millisecondsSinceEpoch;
    final cached = engineCache.get<ResolvedStreamResult>(cacheKey);
    if (cached != null && cached.expiresAtMs > now) return cached;

    final source = LocalStore.instance.getAddonSource(configId);
    if (source == null || source['enabled'] == false) return null;

    final mappedQuality = _mapQuality(source['quality_options'] as List?, tier);
    final path = '/stream/${Uri.encodeComponent(remoteId)}?quality=${Uri.encodeQueryComponent(mappedQuality)}';
    final fetched = await _addonFetch(source['base_url'] as String, path, timeout: const Duration(seconds: 10));
    if (fetched.status == 200 && fetched.json != null) {
      final resolved = _resolvePayload(fetched.json, source, durationMs);
      if (resolved != null) {
        engineCache.set(cacheKey, resolved, const Duration(minutes: 45));
        return resolved;
      }
    }

    final fallback = _fallbackRowStreams[fullId];
    if (fallback != null) {
      registerAllowedHost(fallback);
      final isHls = fallback.contains('.m3u8');
      final resolved = ResolvedStreamResult(
        kind: isHls ? 'hls' : 'direct',
        url: fallback,
        mime: isHls ? 'application/vnd.apple.mpegurl' : guessAudioMime(fallback),
        expiresAtMs: now + 3 * 3600 * 1000,
      );
      engineCache.set(cacheKey, resolved, const Duration(minutes: 30));
      return resolved;
    }
    return null;
  }

  Future<ResolvedStreamResult?> fallbackStream({
    String? title,
    List<String> artists = const [],
    int? durationMs,
    String? excludeSourceId,
    bool requireDownloadsAllowed = false,
  }) async {
    if (title == null || title.trim().isEmpty) return null;
    final q = cleanMusicQuery([title, if (artists.isNotEmpty) artists.first].join(' '));
    if (q.isEmpty) return null;

    final sources = LocalStore.instance.listAddonSources().where((s) {
      if (s['enabled'] == false) return false;
      if (excludeSourceId != null && s['id'] == excludeSourceId) return false;
      if (requireDownloadsAllowed && s['allow_downloads'] == false) return false;
      return true;
    });

    for (final src in sources) {
      final hits = await searchSource(src, q, limit: 5);
      for (final matched in hits) {
        final dur = (matched['duration_ms'] as num?)?.toInt();
        if (!_durationMatches(durationMs, dur)) continue;
        final parsed = parseAddonTrackId(matched['id'] as String);
        if (parsed == null) continue;
        final stream = await resolveStream(parsed.configId, parsed.remoteId, durationMs: durationMs ?? dur);
        if (stream != null) return stream;
      }
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> lyricsCandidates({
    required String track,
    String? artist,
    String? album,
    int? durationSec,
  }) async {
    final sources = LocalStore.instance.listAddonSources().where((s) => s['enabled'] != false).toList();
    if (sources.isEmpty || track.isEmpty) return const [];

    final futures = sources.map((src) async {
      final params = <String, String>{
        'track': track,
        if (artist != null && artist.isNotEmpty) 'artist': artist,
        if (album != null && album.isNotEmpty) 'album': album,
        if (durationSec != null && durationSec > 0) 'duration': '$durationSec',
      };
      final qs = params.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&');
      final fetched = await _addonFetch(src['base_url'] as String, '/lyrics?$qs', timeout: const Duration(seconds: 5));
      if (fetched.status != 200 || fetched.json is! Map) return null;
      final obj = (fetched.json as Map).cast<String, dynamic>();
      final plain = (obj['plain'] as String?)?.trim();
      final synced = (obj['synced'] as String?)?.trim();
      if ((plain == null || plain.isEmpty) && (synced == null || synced.isEmpty)) return null;
      final durRaw = obj['duration'];
      final dur = durRaw is num ? (durRaw > 10000 ? (durRaw / 1000).round() : durRaw.round()) : null;
      return <String, dynamic>{
        'title': obj['title'] ?? obj['track'],
        'artist': obj['artist'],
        'album': obj['album'],
        'duration': dur,
        'plain': (plain != null && plain.isNotEmpty) ? plain : null,
        'synced': (synced != null && synced.isNotEmpty) ? synced : null,
        'word_synced': obj['word_synced'] == true || obj['wordSynced'] == true,
        'source': 'addon',
      };
    });

    final results = await Future.wait(futures);
    return [for (final r in results) if (r != null) r];
  }
}
