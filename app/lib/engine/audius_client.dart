// language: Dart, file: lib/engine/audius_client.dart, target: mobile + desktop, runtime: resong engine
import 'dart:io';

import 'package:dio/dio.dart';

import 'engine_utils.dart';
import 'local_store.dart';

class AudiusClient {
  AudiusClient._();
  static final AudiusClient instance = AudiusClient._();

  static const _appName = 'resong';
  final Map<String, Map<String, dynamic>> _rawTracks = {};

  bool get isEnabled => LocalStore.instance.getSetting('provider.audius.enabled') != 'false';

  Future<bool> setEnabled(bool enabled) async {
    await LocalStore.instance.setSetting('provider.audius.enabled', enabled ? 'true' : 'false');
    return isEnabled;
  }

  Future<String?> _discoverHost() async {
    final cached = engineCache.get<String>('audius:host');
    if (cached != null) return cached;
    try {
      final res = await engineDio.get<Map<String, dynamic>>(
        'https://api.audius.co',
        options: Options(sendTimeout: const Duration(seconds: 5), receiveTimeout: const Duration(seconds: 5)),
      );
      final data = res.data?['data'];
      if (data is List) {
        final host = data.whereType<String>().firstWhere(
              (u) => u.startsWith('https://'),
              orElse: () => '',
            );
        if (host.isNotEmpty) {
          engineCache.set('audius:host', host, const Duration(minutes: 30));
          return host;
        }
      }
    } catch (_) {}
    return null;
  }

  Map<String, dynamic>? _toTrack(Map<String, dynamic> raw) {
    final id = (raw['id'] as String? ?? '').trim();
    final title = (raw['title'] as String? ?? '').trim();
    if (id.isEmpty || title.isEmpty || raw['is_streamable'] == false) return null;
    final user = raw['user'] as Map?;
    final artist = (user?['name'] as String? ?? '').trim();
    final artMap = raw['artwork'] as Map?;
    final art = (artMap?['1000x1000'] ?? artMap?['480x480'] ?? artMap?['150x150']) as String?;
    final dur = (raw['duration'] as num?)?.toDouble();
    final isrc = (raw['isrc'] as String?)?.trim();
    final permalink = (raw['permalink'] as String?)?.trim();

    final track = <String, dynamic>{
      'id': 'au:$id',
      'source': 'audius',
      'title': title,
      'artists': artist.isNotEmpty ? [artist] : <String>[],
      'artwork': art,
      'duration_ms': dur != null && dur > 0 ? (dur * 1000).round() : null,
      'explicit': false,
      'extra': {
        if (isrc != null && isrc.isNotEmpty) 'isrc': isrc,
        if (permalink != null && permalink.isNotEmpty) 'permalink': permalink,
        'source_label': 'Audius',
      },
    };
    _rawTracks[id] = raw;
    engineCache.set('audius:track:$id', track, const Duration(minutes: 15));
    final stream = raw['stream'] as Map?;
    if (stream?['url'] is String) registerAllowedHost(stream!['url'] as String);
    if (stream?['mirrors'] is List) {
      for (final m in (stream!['mirrors'] as List).whereType<String>()) {
        registerAllowedHost(m);
      }
    }
    return track;
  }

  Future<List<Map<String, dynamic>>> search(String query, {int limit = 8}) async {
    if (!isEnabled) return const [];
    final clean = query.trim();
    if (clean.isEmpty) return const [];
    final key = 'audius:search:${clean.toLowerCase()}:$limit';
    final cached = engineCache.get<List<Map<String, dynamic>>>(key);
    if (cached != null) return cached;

    final host = await _discoverHost();
    if (host == null) return const [];
    try {
      final res = await engineDio.get<Map<String, dynamic>>(
        '$host/v1/tracks/search',
        queryParameters: {'query': clean, 'app_name': _appName, 'limit': limit.clamp(1, 12)},
      );
      final list = res.data?['data'];
      if (list is! List) return const [];
      final tracks = <Map<String, dynamic>>[];
      for (final item in list.whereType<Map>()) {
        final t = _toTrack(item.cast<String, dynamic>());
        if (t != null) tracks.add(t);
      }
      engineCache.set(key, tracks, const Duration(minutes: 10));
      return tracks;
    } catch (_) {
      return const [];
    }
  }

  Future<Map<String, dynamic>?> track(String id) async {
    final cached = engineCache.get<Map<String, dynamic>>('audius:track:$id');
    if (cached != null) return cached;
    final host = await _discoverHost();
    if (host == null) return null;
    try {
      final res = await engineDio.get<Map<String, dynamic>>(
        '$host/v1/tracks/${Uri.encodeComponent(id)}',
        queryParameters: {'app_name': _appName},
      );
      final data = res.data?['data'];
      if (data is Map) return _toTrack(data.cast<String, dynamic>());
    } catch (_) {}
    return null;
  }

  Future<ResolvedStreamResult?> resolveStream(String id) async {
    final cached = engineCache.get<ResolvedStreamResult>('audius:stream:$id');
    if (cached != null && cached.expiresAtMs > DateTime.now().millisecondsSinceEpoch) {
      return cached;
    }
    if (!_rawTracks.containsKey(id)) await track(id);
    final raw = _rawTracks[id];
    final streamUrl = (raw?['stream'] as Map?)?['url'] as String?;
    final host = await _discoverHost();
    final candidates = <String>[
      if (streamUrl != null && streamUrl.isNotEmpty) streamUrl,
      if (host != null) '$host/v1/tracks/${Uri.encodeComponent(id)}/stream?app_name=$_appName',
    ];
    final hc = HttpClient()..connectionTimeout = const Duration(seconds: 7);
    try {
      for (final target in candidates) {
        try {
          final req = await hc.getUrl(Uri.parse(target));
          req.followRedirects = false;
          req.headers.set('user-agent', kEngineUserAgent);
          req.headers.set('range', 'bytes=0-1');
          final res = await req.close();
          final loc = res.headers.value('location');
          await res.drain<void>().catchError((Object _) {});
          final finalUrl = loc ?? (res.statusCode >= 200 && res.statusCode < 300 ? target : null);
          if (finalUrl == null) continue;
          registerAllowedHost(finalUrl);
          final result = ResolvedStreamResult(
            kind: 'direct',
            url: finalUrl,
            mime: 'audio/mpeg',
            expiresAtMs: DateTime.now().millisecondsSinceEpoch + 20 * 60 * 1000,
          );
          engineCache.set('audius:stream:$id', result, const Duration(minutes: 10));
          return result;
        } catch (_) {}
      }
    } finally {
      hc.close(force: true);
    }
    return null;
  }
}
