// language: Dart, file: lib/engine/soundcloud_client.dart, target: mobile + desktop, runtime: resong engine
import 'dart:async';

import 'package:dio/dio.dart';

import 'engine_utils.dart';

class SoundCloudClient {
  SoundCloudClient._();
  static final SoundCloudClient instance = SoundCloudClient._();

  static const _home = 'https://soundcloud.com';
  static const _api = 'https://api-v2.soundcloud.com';

  String? _clientId;
  Future<String?>? _refreshing;

  Future<String?> _extractClientId() async {
    try {
      final page = await engineDio.get<String>(
        _home,
        options: Options(responseType: ResponseType.plain, headers: {'accept-language': 'en-US,en;q=0.9'}),
      );
      if (page.statusCode != 200 || page.data == null) return null;
      final matches = RegExp(r'<script[^>]*src="([^"]+)"').allMatches(page.data!);
      for (final m in matches) {
        final src = m.group(1) ?? '';
        if (!src.contains('sndcdn.com') || !src.contains('/assets/')) continue;
        final abs = src.startsWith('http')
            ? src
            : src.startsWith('//')
                ? 'https:$src'
                : '$_home$src';
        try {
          final js = await engineDio.get<String>(abs, options: Options(responseType: ResponseType.plain));
          final body = js.data;
          if (js.statusCode != 200 || body == null) continue;
          final found = RegExp(r'client_id[:=]"([A-Za-z0-9]{16,64})"').firstMatch(body) ??
              RegExp(r'client_id=([A-Za-z0-9]{16,64})').firstMatch(body);
          if (found != null) return found.group(1);
        } catch (_) {}
      }
    } catch (_) {}
    return null;
  }

  Future<String?> _ensureClientId() {
    if (_clientId != null && _clientId!.isNotEmpty) return Future.value(_clientId);
    return _refreshing ??= _extractClientId().then((id) {
      _clientId = id;
      _refreshing = null;
      return id;
    }).catchError((Object _) {
      _refreshing = null;
      return null;
    });
  }

  Future<Map<String, dynamic>?> _apiGet(String path, Map<String, Object> params) async {
    var id = await _ensureClientId();
    if (id == null) return null;
    for (var attempt = 0; attempt < 2; attempt++) {
      final res = await engineDio.get<Map<String, dynamic>>(
        '$_api$path',
        queryParameters: {'client_id': id, ...params},
      );
      if ((res.statusCode == 401 || res.statusCode == 403) && attempt == 0) {
        _clientId = null;
        id = await _ensureClientId();
        if (id == null) return null;
        continue;
      }
      if (res.statusCode == 200) return res.data;
      return null;
    }
    return null;
  }

  Map<String, dynamic> _toTrack(Map<String, dynamic> raw) {
    var art = raw['artwork_url'] as String?;
    if (art != null) {
      art = art
          .replaceAll('-large.', '-t500x500.')
          .replaceAll('-t67x67.', '-t500x500.')
          .replaceAll('-t120x120.', '-t500x500.');
    }
    final user = raw['user'] as Map?;
    final artist = ((user?['username'] as String?) ?? (raw['label_name'] as String?) ?? '').trim();
    return {
      'id': 'sc:${raw['id']}',
      'source': 'soundcloud',
      'title': raw['title'] ?? '',
      'artists': artist.isNotEmpty ? [artist] : <String>[],
      'artwork': art,
      'duration_ms': (raw['duration'] as num?)?.toInt(),
      'extra': {'permalink': raw['permalink_url']},
    };
  }

  Future<List<Map<String, dynamic>>> search(String query, {int limit = 10}) async {
    final data = await _apiGet('/search/tracks', {'q': query, 'limit': limit, 'offset': 0});
    final col = data?['collection'];
    if (col is! List) return const [];
    return [for (final item in col.whereType<Map>()) _toTrack(item.cast<String, dynamic>())];
  }

  Future<Map<String, dynamic>?> track(String trackId) async {
    final raw = await _apiGet('/tracks/$trackId', {'representation': 'full'});
    return raw == null ? null : _toTrack(raw);
  }

  Future<ResolvedStreamResult?> resolveStream(String trackId, {bool progressiveOnly = false}) async {
    final key = progressiveOnly ? 'stream:sc:prog:$trackId' : 'stream:sc:$trackId';
    final cached = engineCache.get<ResolvedStreamResult>(key);
    if (cached != null && cached.expiresAtMs > DateTime.now().millisecondsSinceEpoch) {
      return cached;
    }
    final raw = await _apiGet('/tracks/$trackId', {'representation': 'full'});
    final transcodings = ((raw?['media'] as Map?)?['transcodings'] as List?)
            ?.whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList() ??
        const [];
    if (transcodings.isEmpty) return null;

    Map<String, dynamic>? prog;
    Map<String, dynamic>? hls;
    for (final t in transcodings) {
      final proto = (t['format'] as Map?)?['protocol'] as String?;
      if (proto == 'progressive' && prog == null) prog = t;
      if (proto == 'hls' && hls == null) hls = t;
    }
    final chosen = progressiveOnly ? prog : (prog ?? hls);
    if (chosen == null) return null;
    final id = await _ensureClientId();
    if (id == null) return null;
    final url = chosen['url'] as String?;
    if (url == null) return null;

    final res = await engineDio.get<Map<String, dynamic>>('$url?client_id=$id');
    final finalUrl = res.data?['url'] as String?;
    if (res.statusCode != 200 || finalUrl == null || finalUrl.isEmpty) return null;
    registerAllowedHost(finalUrl);

    final isProg = (chosen['format'] as Map?)?['protocol'] == 'progressive';
    final result = ResolvedStreamResult(
      kind: isProg ? 'direct' : 'hls',
      url: finalUrl,
      mime: isProg ? (((chosen['format'] as Map?)?['mime_type'] as String?) ?? 'audio/mpeg') : 'application/vnd.apple.mpegurl',
      expiresAtMs: DateTime.now().millisecondsSinceEpoch + 55 * 60 * 1000,
    );
    engineCache.set(key, result, const Duration(minutes: 50));
    return result;
  }
}
