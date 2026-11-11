// language: Dart, file: lib/engine/spotify_client.dart, target: mobile + desktop, runtime: resong engine
import 'dart:convert';

import 'package:dio/dio.dart';

import 'engine_utils.dart';
import 'local_store.dart';

class SpotifyClient {
  SpotifyClient._();
  static final SpotifyClient instance = SpotifyClient._();

  static const _base = 'https://api.spotify.com/v1';

  ({String id, String secret}) _readCredentials() => (
        id: (LocalStore.instance.getSetting('spotify.client_id') ?? '').trim(),
        secret: (LocalStore.instance.getSetting('spotify.client_secret') ?? '').trim(),
      );

  Map<String, dynamic> getStatus() {
    final creds = _readCredentials();
    final configured = creds.id.isNotEmpty && creds.secret.isNotEmpty;
    final enabledRaw = LocalStore.instance.getSetting('spotify.enabled');
    final enabled = enabledRaw != 'false';
    return {
      'configured': configured,
      'enabled': configured ? enabled : (enabledRaw == 'true' ? true : enabled),
      'active': configured && enabled,
      'client_id_preview': creds.id.length >= 6 ? '${creds.id.substring(0, 6)}...' : (creds.id.isNotEmpty ? creds.id : null),
    };
  }

  bool get isEnabled {
    final st = getStatus();
    return st['configured'] == true && st['enabled'] == true;
  }

  Future<({String token, int ttlMs})?> _fetchToken(String id, String secret) async {
    if (id.isEmpty || secret.isEmpty) return null;
    try {
      final basic = base64Encode(utf8.encode('$id:$secret'));
      final res = await engineDio.post<Map<String, dynamic>>(
        'https://accounts.spotify.com/api/token',
        data: 'grant_type=client_credentials',
        options: Options(
          headers: {
            'authorization': 'Basic $basic',
            'content-type': 'application/x-www-form-urlencoded',
          },
        ),
      );
      if (res.statusCode != 200 || res.data == null) return null;
      final token = res.data!['access_token'] as String?;
      final expiresIn = (res.data!['expires_in'] as num?)?.toInt() ?? 3600;
      if (token == null || token.isEmpty) return null;
      return (token: token, ttlMs: ((expiresIn - 60) * 1000).clamp(30000, 3600000));
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> setSettings({
    bool? enabled,
    String? clientId,
    String? clientSecret,
    bool clearCredentials = false,
  }) async {
    if (clearCredentials) {
      await LocalStore.instance.deleteSetting('spotify.client_id');
      await LocalStore.instance.deleteSetting('spotify.client_secret');
      engineCache.deletePrefix('spotify:');
    } else if (clientId != null || clientSecret != null) {
      final prev = _readCredentials();
      final nextId = (clientId ?? prev.id).trim();
      final nextSecret = (clientSecret ?? prev.secret).trim();
      if (nextId.isEmpty || nextSecret.isEmpty) {
        throw Exception('Informe Client ID e Client Secret do Spotify');
      }
      final tok = await _fetchToken(nextId, nextSecret);
      if (tok == null) {
        throw Exception('Credenciais do Spotify inválidas ou recusadas pela API');
      }
      await LocalStore.instance.setSetting('spotify.client_id', nextId);
      await LocalStore.instance.setSetting('spotify.client_secret', nextSecret);
      if (enabled == null) await LocalStore.instance.setSetting('spotify.enabled', 'true');
      engineCache.deletePrefix('spotify:');
      engineCache.set('spotify:token', tok.token, Duration(milliseconds: tok.ttlMs));
    }
    if (enabled != null) {
      await LocalStore.instance.setSetting('spotify.enabled', enabled ? 'true' : 'false');
      engineCache.deletePrefix('spotify:');
    }
    return getStatus();
  }

  Future<String?> _accessToken() async {
    if (!isEnabled) return null;
    final cached = engineCache.get<String>('spotify:token');
    if (cached != null) return cached;
    final creds = _readCredentials();
    final tok = await _fetchToken(creds.id, creds.secret);
    if (tok == null) return null;
    engineCache.set('spotify:token', tok.token, Duration(milliseconds: tok.ttlMs));
    return tok.token;
  }

  Future<Map<String, dynamic>?> _apiGet(String path, [Map<String, String> params = const {}]) async {
    final token = await _accessToken();
    if (token == null) return null;
    try {
      final res = await engineDio.get<Map<String, dynamic>>(
        '$_base$path',
        queryParameters: params.isEmpty ? null : params,
        options: Options(headers: {'authorization': 'Bearer $token'}),
      );
      return res.statusCode == 200 ? res.data : null;
    } catch (_) {
      return null;
    }
  }

  String? _bestImage(dynamic images) {
    if (images is! List || images.isEmpty) return null;
    final items = images.whereType<Map>().toList()
      ..sort((a, b) => ((b['width'] as num?)?.toInt() ?? 0).compareTo((a['width'] as num?)?.toInt() ?? 0));
    return items.firstOrNull?['url'] as String?;
  }

  Map<String, dynamic> _toTrack(Map<String, dynamic> raw) {
    final artists = ((raw['artists'] as List?) ?? const [])
        .whereType<Map>()
        .map((a) => '${a['name'] ?? ''}'.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final firstArtistId = ((raw['artists'] as List?)?.whereType<Map>().firstOrNull)?['id'] as String?;
    final album = raw['album'] as Map?;
    final isrc = ((raw['external_ids'] as Map?)?['isrc'] as String?)?.trim();
    return {
      'id': 'sp:track:${raw['id']}',
      'source': 'spotify',
      'title': raw['name'] ?? '',
      'artists': artists,
      if (album?['name'] != null) 'album': album!['name'],
      'artwork': _bestImage(album?['images']),
      'duration_ms': (raw['duration_ms'] as num?)?.toInt(),
      'explicit': raw['explicit'] == true,
      'extra': {
        if (album?['id'] != null) 'album_id': album!['id'],
        if (firstArtistId != null) 'artist_id': firstArtistId,
        if (isrc != null && isrc.isNotEmpty) 'isrc': isrc,
        if (raw['track_number'] != null) 'track_number': raw['track_number'],
        'source_label': 'Spotify',
      },
    };
  }

  ({String kind, String id})? parseUrl(String input) {
    final m = RegExp(
      r'(?:https?:\/\/open\.spotify\.com\/(?:intl-[a-z0-9-]+\/)?|spotify:)(track|album|artist|playlist)(?:\/|:)([A-Za-z0-9]+)',
      caseSensitive: false,
    ).firstMatch(input.trim());
    if (m == null) return null;
    return (kind: m.group(1)!.toLowerCase(), id: m.group(2)!);
  }

  Future<Map<String, dynamic>?> _fetchEmbed(String kind, String id) async {
    final key = 'spotify:embed:$kind:$id';
    final cached = engineCache.get<Map<String, dynamic>>(key);
    if (cached != null) return cached;
    try {
      final res = await engineDio.get<String>(
        'https://open.spotify.com/embed/$kind/${Uri.encodeComponent(id)}',
        options: Options(responseType: ResponseType.plain),
      );
      final html = res.data;
      if (res.statusCode != 200 || html == null) return null;
      final marker = html.indexOf('id="__NEXT_DATA__"');
      if (marker < 0) return null;
      final start = html.indexOf('>', marker) + 1;
      final end = html.indexOf('</script>', start);
      if (start <= 0 || end <= start) return null;
      final payload = jsonDecode(html.substring(start, end)) as Map<String, dynamic>;
      final entity = (((((payload['props'] as Map?)?['pageProps'] as Map?)?['state'] as Map?)?['data'] as Map?)?['entity'] as Map?)
          ?.cast<String, dynamic>();
      if (entity != null) engineCache.set(key, entity, const Duration(minutes: 15));
      return entity;
    } catch (_) {
      return null;
    }
  }

  List<Map<String, dynamic>> _embedTracks(Map<String, dynamic>? entity, String? artwork, [String? album]) {
    final list = (entity?['trackList'] as List?) ?? const [];
    final out = <Map<String, dynamic>>[];
    for (final item in list.whereType<Map>()) {
      final uri = (item['uri'] as String?) ?? '';
      final id = uri.startsWith('spotify:track:') ? uri.substring('spotify:track:'.length) : '';
      final title = (item['title'] as String? ?? '').trim();
      if (id.isEmpty || title.isEmpty) continue;
      final artists = ((item['subtitle'] as String?) ?? '')
          .replaceAll('\u00a0', ' ')
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      final dur = (item['duration'] as num?)?.toInt();
      out.add({
        'id': 'sp:track:$id',
        'source': 'spotify',
        'title': title,
        'artists': artists,
        if (album != null) 'album': album,
        'artwork': artwork,
        'duration_ms': dur != null && dur > 0 ? dur : null,
        'explicit': item['isExplicit'] == true,
        'extra': {'source_label': 'Spotify'},
      });
    }
    return out;
  }

  Future<Map<String, dynamic>?> track(String id) async {
    final raw = await _apiGet('/tracks/$id');
    if (raw != null) return _toTrack(raw);
    final embed = await _fetchEmbed('track', id);
    if (embed == null) return null;
    final art = _bestImage((embed['coverArt'] as Map?)?['sources']);
    final tracks = _embedTracks(embed, art);
    if (tracks.isNotEmpty) return tracks.first;
    final title = ((embed['title'] ?? embed['name']) as String? ?? '').trim();
    if (title.isEmpty) return null;
    final artists = ((embed['subtitle'] as String?) ?? '')
        .replaceAll('\u00a0', ' ')
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return {
      'id': 'sp:track:$id',
      'source': 'spotify',
      'title': title,
      'artists': artists,
      'artwork': art,
      'duration_ms': null,
      'explicit': false,
      'extra': {'source_label': 'Spotify'},
    };
  }

  Future<Map<String, List<Map<String, dynamic>>>> search(String query, {int limit = 10}) async {
    final data = await _apiGet('/search', {
      'q': query,
      'type': 'track,album,artist,playlist',
      'limit': '${limit.clamp(1, 10)}',
    });
    if (data == null) {
      return {'tracks': [], 'albums': [], 'artists': [], 'playlists': []};
    }
    final tracks = (((data['tracks'] as Map?)?['items'] as List?) ?? const [])
        .whereType<Map>()
        .where((t) => t['id'] != null)
        .map((t) => _toTrack(t.cast<String, dynamic>()))
        .toList();
    final albums = (((data['albums'] as Map?)?['items'] as List?) ?? const [])
        .whereType<Map>()
        .where((a) => a['id'] != null)
        .map((a) {
          final rel = a['release_date'] as String?;
          return {
            'id': 'sp:album:${a['id']}',
            'source': 'spotify',
            'title': a['name'] ?? '',
            'artists': ((a['artists'] as List?) ?? const []).whereType<Map>().map((x) => '${x['name'] ?? ''}').toList(),
            'artwork': _bestImage(a['images']),
            'year': rel != null && rel.length >= 4 ? rel.substring(0, 4) : null,
            'track_count': (a['total_tracks'] as num?)?.toInt(),
          };
        })
        .toList();
    final artists = (((data['artists'] as Map?)?['items'] as List?) ?? const [])
        .whereType<Map>()
        .where((a) => a['id'] != null)
        .map((a) => {
              'id': 'sp:artist:${a['id']}',
              'source': 'spotify',
              'name': a['name'] ?? '',
              'artwork': _bestImage(a['images']),
              'subscribers': null,
            })
        .toList();
    final playlists = (((data['playlists'] as Map?)?['items'] as List?) ?? const [])
        .whereType<Map>()
        .where((p) => p['id'] != null)
        .map((p) => {
              'id': 'sp:playlist:${p['id']}',
              'source': 'spotify',
              'title': p['name'] ?? '',
              'owner': (p['owner'] as Map?)?['display_name'],
              'artwork': _bestImage(p['images']),
              'track_count': ((p['tracks'] as Map?)?['total'] as num?)?.toInt(),
              'description': p['description'],
            })
        .toList();
    return {'tracks': tracks, 'albums': albums, 'artists': artists, 'playlists': playlists};
  }

  Future<Map<String, dynamic>?> album(String id) async {
    final album = await _apiGet('/albums/$id');
    if (album == null) {
      final embed = await _fetchEmbed('album', id);
      if (embed == null) return null;
      final title = ((embed['name'] ?? embed['title']) as String? ?? '').trim();
      if (title.isEmpty) return null;
      final art = _bestImage((embed['coverArt'] as Map?)?['sources']);
      final tracks = _embedTracks(embed, art, title);
      return {
        'album': {
          'id': 'sp:album:$id',
          'source': 'spotify',
          'title': title,
          'artists': ((embed['subtitle'] as String?) ?? '').split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
          'artwork': art,
          'year': null,
          'track_count': tracks.length,
        },
        'tracks': tracks,
      };
    }
    final tracksRaw = await _apiGet('/albums/$id/tracks', {'limit': '50'});
    final art = _bestImage(album['images']);
    final items = (tracksRaw?['items'] as List?) ?? const [];
    var tracks = items.whereType<Map>().map((raw) {
      final t = _toTrack(raw.cast<String, dynamic>());
      t['album'] = album['name'];
      t['artwork'] = art;
      (t['extra'] as Map)['album_id'] = album['id'];
      return t;
    }).toList();
    if (tracks.isEmpty) {
      tracks = _embedTracks(await _fetchEmbed('album', id), art, album['name'] as String?);
    }
    final rel = album['release_date'] as String?;
    return {
      'album': {
        'id': 'sp:album:${album['id']}',
        'source': 'spotify',
        'title': album['name'] ?? '',
        'artists': ((album['artists'] as List?) ?? const []).whereType<Map>().map((a) => '${a['name'] ?? ''}').toList(),
        'artwork': art,
        'year': rel != null && rel.length >= 4 ? rel.substring(0, 4) : null,
        'track_count': tracks.length,
      },
      'tracks': tracks,
    };
  }

  Future<Map<String, dynamic>?> artist(String id) async {
    final artist = await _apiGet('/artists/$id');
    if (artist == null) {
      final embed = await _fetchEmbed('artist', id);
      if (embed == null) return null;
      final name = ((embed['name'] ?? embed['title']) as String? ?? '').trim();
      if (name.isEmpty) return null;
      final art = _bestImage((embed['coverArt'] as Map?)?['sources']);
      final tracks = _embedTracks(embed, art);
      return {
        'artist': {'id': 'sp:artist:$id', 'source': 'spotify', 'name': name, 'artwork': art, 'subscribers': null},
        'sections': const [],
        'top_tracks': tracks,
        'all_tracks': tracks,
      };
    }
    final res = await Future.wait([
      _apiGet('/artists/$id/top-tracks', {'market': 'BR'}),
      _apiGet('/artists/$id/albums', {'include_groups': 'album,single', 'market': 'BR', 'limit': '30'}),
    ]);
    var topTracks = (((res[0]?['tracks'] as List?) ?? const []))
        .whereType<Map>()
        .map((t) => _toTrack(t.cast<String, dynamic>()))
        .toList();
    final albumsRaw = (((res[1]?['items'] as List?) ?? const [])).whereType<Map>().toList();
    final albums = albumsRaw.where((a) => a['album_type'] != 'single').map((a) {
      final rel = a['release_date'] as String?;
      return {
        'id': 'sp:album:${a['id']}',
        'source': 'spotify',
        'title': a['name'] ?? '',
        'artists': [artist['name'] ?? ''],
        'artwork': _bestImage(a['images']),
        'year': rel != null && rel.length >= 4 ? rel.substring(0, 4) : null,
        'track_count': (a['total_tracks'] as num?)?.toInt(),
      };
    }).toList();
    final singles = albumsRaw.where((a) => a['album_type'] == 'single').map((a) {
      final rel = a['release_date'] as String?;
      return {
        'id': 'sp:album:${a['id']}',
        'source': 'spotify',
        'title': a['name'] ?? '',
        'artists': [artist['name'] ?? ''],
        'artwork': _bestImage(a['images']),
        'year': rel != null && rel.length >= 4 ? rel.substring(0, 4) : null,
        'track_count': (a['total_tracks'] as num?)?.toInt(),
      };
    }).toList();
    final art = _bestImage(artist['images']);
    if (topTracks.isEmpty) topTracks = _embedTracks(await _fetchEmbed('artist', id), art);
    return {
      'artist': {'id': 'sp:artist:${artist['id']}', 'source': 'spotify', 'name': artist['name'] ?? '', 'artwork': art, 'subscribers': null},
      'sections': [
        if (albums.isNotEmpty) {'title': 'Álbuns', 'tracks': const [], 'albums': albums, 'artists': const [], 'playlists': const []},
        if (singles.isNotEmpty) {'title': 'Singles e EPs', 'tracks': const [], 'albums': singles, 'artists': const [], 'playlists': const []},
      ],
      'top_tracks': topTracks,
      'all_tracks': topTracks,
    };
  }

  Future<Map<String, dynamic>?> playlist(String id) async {
    final pl = await _apiGet('/playlists/$id', {'market': 'BR'});
    if (pl == null) {
      final embed = await _fetchEmbed('playlist', id);
      if (embed == null) return null;
      final title = ((embed['name'] ?? embed['title']) as String? ?? '').trim();
      if (title.isEmpty) return null;
      final art = _bestImage((embed['coverArt'] as Map?)?['sources']);
      final tracks = _embedTracks(embed, art);
      return {
        'playlist': {
          'id': 'sp:playlist:$id',
          'source': 'spotify',
          'title': title,
          'owner': embed['subtitle'],
          'artwork': art,
          'track_count': tracks.length,
        },
        'tracks': tracks,
      };
    }
    final items = (((pl['tracks'] as Map?)?['items'] as List?) ?? const []);
    var tracks = items
        .whereType<Map>()
        .map((it) => it['track'])
        .whereType<Map>()
        .where((t) => t['id'] != null)
        .map((t) => _toTrack(t.cast<String, dynamic>()))
        .toList();
    final art = _bestImage(pl['images']);
    if (tracks.isEmpty) tracks = _embedTracks(await _fetchEmbed('playlist', id), art);
    return {
      'playlist': {
        'id': 'sp:playlist:${pl['id']}',
        'source': 'spotify',
        'title': pl['name'] ?? '',
        'owner': (pl['owner'] as Map?)?['display_name'],
        'artwork': art,
        'track_count': tracks.length,
        'description': pl['description'],
      },
      'tracks': tracks,
    };
  }
}
