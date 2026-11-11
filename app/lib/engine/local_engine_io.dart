// language: Dart, file: lib/engine/local_engine_io.dart, target: mobile + desktop, runtime: resong engine
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/api.dart';
import '../core/format.dart';
import 'addon_client.dart';
import 'archive_client.dart';
import 'audius_client.dart';
import 'engine_utils.dart';
import 'local_store.dart';
import 'lyrics_engine.dart';
import 'soundcloud_client.dart';
import 'spotify_client.dart';
import 'stream_resolver.dart';
import 'translate_engine.dart';
import 'ytmusic_client.dart';

class LocalEngineServer {
  LocalEngineServer._();
  static final LocalEngineServer instance = LocalEngineServer._();

  HttpServer? _server;
  HttpClient? _upstreamClient;
  Future<int>? _starting;

  int? get port => _server?.port;
  bool get isRunning => _server != null;

  HttpClient get _http {
    final existing = _upstreamClient;
    if (existing != null) return existing;
    final c = HttpClient();
    c.connectionTimeout = const Duration(seconds: 15);
    c.idleTimeout = const Duration(seconds: 15);
    _upstreamClient = c;
    return c;
  }

  Future<int> start() => _starting ??= _startInternal();

  Future<int> _startInternal() async {
    if (_server != null) return _server!.port;
    await LocalStore.instance.ensureReady();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    Api.instance.setBaseUrl('http://127.0.0.1:${server.port}');
    unawaited(_serveLoop(server));
    return server.port;
  }

  Future<void> stop() async {
    _starting = null;
    await _server?.close(force: true);
    _server = null;
    _upstreamClient?.close(force: true);
    _upstreamClient = null;
  }

  Future<void> _serveLoop(HttpServer server) async {
    await for (final req in server) {
      unawaited(_dispatch(req));
    }
  }

  void _setCors(HttpResponse res) {
    res.headers.set('access-control-allow-origin', '*');
    res.headers.set('access-control-allow-methods', 'GET, POST, PATCH, PUT, DELETE, OPTIONS');
    res.headers.set('access-control-allow-headers', 'Content-Type, Range');
  }

  Future<void> _sendJson(HttpResponse res, int status, Object body) async {
    _setCors(res);
    res.statusCode = status;
    res.headers.contentType = ContentType.json;
    res.write(jsonEncode(body));
    await res.close();
  }

  Future<void> _sendText(HttpResponse res, int status, String contentType, String body) async {
    _setCors(res);
    res.statusCode = status;
    res.headers.set('content-type', contentType);
    res.headers.set('cache-control', 'no-store');
    res.write(body);
    await res.close();
  }

  Future<Map<String, dynamic>> _readJsonBody(HttpRequest req) async {
    try {
      final raw = await utf8.decoder.bind(req).join();
      if (raw.trim().isEmpty) return const {};
      final decoded = jsonDecode(raw);
      return decoded is Map ? decoded.cast<String, dynamic>() : const {};
    } catch (_) {
      return const {};
    }
  }

  Future<void> _dispatch(HttpRequest req) async {
    final res = req.response;
    _setCors(res);
    if (req.method == 'OPTIONS') {
      res.statusCode = HttpStatus.noContent;
      await res.close();
      return;
    }

    final seg = req.uri.pathSegments;
    final method = req.method.toUpperCase();
    try {
      // /api/health
      if (method == 'GET' && seg.length == 2 && seg[0] == 'api' && seg[1] == 'health') {
        await _sendJson(res, 200, {'ok': true, 'engine': 'embedded'});
        return;
      }

      // BitChord producer endpoints: /manifest.json, /search, /stream/:id
      if (method == 'GET' && seg.length == 1 && seg[0] == 'manifest.json') {
        await _sendJson(res, 200, {
          'id': 'resong',
          'name': 'resong',
          'version': '0.1.0',
          'schemaVersion': 1,
          'description': 'Fonte resong local',
          'allowDownloads': true,
          'qualityOptions': ['HIGH', 'LOW'],
        });
        return;
      }
      if (method == 'GET' && seg.length == 1 && seg[0] == 'search') {
        await _handleSearch(req, bitchordMode: true);
        return;
      }
      if (method == 'GET' && seg.length == 2 && seg[0] == 'stream') {
        await _handleStreamProducer(req, seg[1]);
        return;
      }

      if (seg.isEmpty || seg[0] != 'api') {
        await _sendJson(res, 404, {'error': 'rota não encontrada'});
        return;
      }

      // /api/home
      if (method == 'GET' && seg.length == 2 && seg[1] == 'home') {
        final sections = await YtMusicClient.instance.home();
        await _sendJson(res, 200, {
          'sections': sections,
          'recent_tracks': LocalStore.instance.listRecent(limit: 12),
          'playlists': LocalStore.instance.listPlaylists(limit: 8),
        });
        return;
      }

      // /api/search & /api/suggest
      if (method == 'GET' && seg.length == 2 && seg[1] == 'search') {
        await _handleSearch(req);
        return;
      }
      if (method == 'GET' && seg.length == 2 && seg[1] == 'suggest') {
        final q = (req.uri.queryParameters['q'] ?? '').trim();
        if (q.isEmpty) {
          await _sendJson(res, 400, {'error': 'parâmetro q obrigatório'});
          return;
        }
        await _sendJson(res, 200, {'suggestions': await YtMusicClient.instance.suggest(q)});
        return;
      }

      // /api/track/:id
      if (method == 'GET' && seg.length == 3 && seg[1] == 'track') {
        await _handleTrackDetail(res, seg[2]);
        return;
      }

      // /api/album/:id
      if (method == 'GET' && seg.length == 3 && seg[1] == 'album') {
        await _handleAlbumDetail(res, seg[2]);
        return;
      }

      // /api/artist/resolve & /api/artist/:id
      if (method == 'GET' && seg.length == 3 && seg[1] == 'artist' && seg[2] == 'resolve') {
        final name = (req.uri.queryParameters['name'] ?? '').trim();
        if (name.isEmpty) {
          await _sendJson(res, 400, {'error': 'nome do artista obrigatório'});
          return;
        }
        final data = await YtMusicClient.instance.searchArtistByName(name);
        if (data == null) {
          await _sendJson(res, 404, {'error': 'artista não encontrado'});
        } else {
          await _sendJson(res, 200, data);
        }
        return;
      }
      if (method == 'GET' && seg.length == 3 && seg[1] == 'artist') {
        await _handleArtistDetail(res, seg[2]);
        return;
      }

      // /api/playlist-ref/:id
      if (method == 'GET' && seg.length == 3 && seg[1] == 'playlist-ref') {
        await _handlePlaylistRef(res, seg[2]);
        return;
      }

      // /api/lyrics, /api/lyrics/translate, /api/lyrics/romanize
      if (method == 'GET' && seg.length == 2 && seg[1] == 'lyrics') {
        final qp = req.uri.queryParameters;
        final track = (qp['track'] ?? '').trim();
        if (track.isEmpty) {
          await _sendJson(res, 400, {'error': 'parâmetro track obrigatório'});
          return;
        }
        final data = await LyricsEngine.instance.getLyrics(
          track: track,
          artist: qp['artist'],
          album: qp['album'],
          durationSec: int.tryParse(qp['duration'] ?? ''),
          videoId: qp['video_id'],
          isrc: qp['isrc'],
          spId: qp['sp_id'],
        );
        if (data == null) {
          await _sendJson(res, 404, {'error': 'letras não encontradas'});
        } else {
          await _sendJson(res, 200, data);
        }
        return;
      }
      if (method == 'POST' && seg.length == 3 && seg[1] == 'lyrics' && seg[2] == 'translate') {
        final body = await _readJsonBody(req);
        final rawLines = body['lines'];
        if (rawLines is! List || rawLines.isEmpty) {
          await _sendJson(res, 400, {'error': 'lines obrigatório'});
          return;
        }
        final lines = rawLines.take(400).map((e) => e.toString()).toList();
        final data = await TranslateEngine.instance.translateLyrics(lines, target: (body['target'] as String?) ?? 'pt');
        await _sendJson(res, 200, data);
        return;
      }
      if (method == 'POST' && seg.length == 3 && seg[1] == 'lyrics' && seg[2] == 'romanize') {
        final body = await _readJsonBody(req);
        final rawLines = body['lines'];
        if (rawLines is! List || rawLines.isEmpty) {
          await _sendJson(res, 400, {'error': 'lines obrigatório'});
          return;
        }
        final lines = rawLines.take(400).map((e) => e.toString()).toList();
        final data = await TranslateEngine.instance.romanizeLyrics(lines);
        await _sendJson(res, 200, data);
        return;
      }

      // /api/hls
      if (method == 'GET' && seg.length == 2 && seg[1] == 'hls') {
        await _handleHlsProxy(req);
        return;
      }

      // /api/stream/:id & /api/stream/:id/download
      if (method == 'GET' && seg.length == 4 && seg[1] == 'stream' && seg[3] == 'download') {
        await _handleStreamDownload(req, seg[2]);
        return;
      }
      if (method == 'GET' && seg.length == 3 && seg[1] == 'stream') {
        await _handleStream(req, seg[2]);
        return;
      }

      // /api/library/*
      if (seg.length >= 2 && seg[1] == 'library') {
        await _handleLibrary(req, method, seg);
        return;
      }

      // /api/playlists/*
      if (seg.length >= 2 && seg[1] == 'playlists') {
        await _handlePlaylists(req, method, seg);
        return;
      }

      // /api/sources/*
      if (seg.length >= 2 && seg[1] == 'sources') {
        await _handleSources(req, method, seg);
        return;
      }

      await _sendJson(res, 404, {'error': 'rota não encontrada'});
    } catch (err) {
      try {
        await _sendJson(res, 502, {'error': err.toString()});
      } catch (_) {}
    }
  }

  // ---------------- Search & Catalog ----------------

  List<Map<String, dynamic>> _dedupeTracks(List<Map<String, dynamic>> list) {
    final seen = <String>{};
    final out = <Map<String, dynamic>>[];
    for (final t in list) {
      final id = t['id']?.toString() ?? '';
      if (id.isEmpty || seen.contains(id)) continue;
      seen.add(id);
      out.add(t);
    }
    return out;
  }

  Future<void> _handleSearch(HttpRequest req, {bool bitchordMode = false}) async {
    final q = (req.uri.queryParameters['q'] ?? '').trim();
    if (q.isEmpty) {
      await _sendJson(req.response, 400, {'error': 'parâmetro q obrigatório'});
      return;
    }
    final limit = (int.tryParse(req.uri.queryParameters['limit'] ?? '') ?? 20).clamp(1, 50);

    if (!bitchordMode) {
      final spLink = SpotifyClient.instance.parseUrl(q);
      if (spLink != null) {
        try {
          if (spLink.kind == 'track') {
            final t = await SpotifyClient.instance.track(spLink.id);
            await _sendJson(req.response, 200, {
              'query': q,
              'top': t,
              'tracks': [if (t != null) t],
              'albums': const [],
              'artists': const [],
              'playlists': const [],
              'sources': {'ytmusic': false, 'soundcloud': false, 'spotify': t != null, 'addons': 0},
            });
            return;
          } else if (spLink.kind == 'album') {
            final d = await SpotifyClient.instance.album(spLink.id);
            final tracks = (d?['tracks'] as List?) ?? const [];
            await _sendJson(req.response, 200, {
              'query': q,
              'top': tracks.firstOrNull,
              'tracks': tracks,
              'albums': [if (d?['album'] != null) d!['album']],
              'artists': const [],
              'playlists': const [],
              'sources': {'ytmusic': false, 'soundcloud': false, 'spotify': d != null, 'addons': 0},
            });
            return;
          } else if (spLink.kind == 'artist') {
            final d = await SpotifyClient.instance.artist(spLink.id);
            final topTracks = (d?['top_tracks'] as List?) ?? const [];
            await _sendJson(req.response, 200, {
              'query': q,
              'top': topTracks.firstOrNull,
              'tracks': topTracks,
              'albums': const [],
              'artists': [if (d?['artist'] != null) d!['artist']],
              'playlists': const [],
              'sources': {'ytmusic': false, 'soundcloud': false, 'spotify': d != null, 'addons': 0},
            });
            return;
          } else {
            final d = await SpotifyClient.instance.playlist(spLink.id);
            final tracks = (d?['tracks'] as List?) ?? const [];
            await _sendJson(req.response, 200, {
              'query': q,
              'top': tracks.firstOrNull,
              'tracks': tracks,
              'albums': const [],
              'artists': const [],
              'playlists': [if (d?['playlist'] != null) d!['playlist']],
              'sources': {'ytmusic': false, 'soundcloud': false, 'spotify': d != null, 'addons': 0},
            });
            return;
          }
        } catch (_) {}
      }
    }

    final results = await Future.wait([
      YtMusicClient.instance.search(q, limit: limit).catchError((_) => <String, dynamic>{}),
      SoundCloudClient.instance.search(q, limit: limit.clamp(1, 8)).catchError((_) => <Map<String, dynamic>>[]),
      SpotifyClient.instance.isEnabled
          ? SpotifyClient.instance.search(q, limit: limit).catchError((_) => <String, List<Map<String, dynamic>>>{})
          : Future.value(<String, List<Map<String, dynamic>>>{}),
      AudiusClient.instance.search(q, limit: limit.clamp(1, 6)).catchError((_) => <Map<String, dynamic>>[]),
      ArchiveClient.instance.search(q, limit: limit.clamp(1, 4)).catchError((_) => <Map<String, dynamic>>[]),
      bitchordMode
          ? Future.value(<Map<String, dynamic>>[])
          : AddonClient.instance.searchEnabledAddons(q, limit: limit.clamp(1, 12)).catchError((_) => <Map<String, dynamic>>[]),
    ]);

    final yt = results[0] as Map<String, dynamic>;
    final scTracks = results[1] as List<Map<String, dynamic>>;
    final sp = results[2] as Map<String, List<Map<String, dynamic>>>;
    final auTracks = results[3] as List<Map<String, dynamic>>;
    final iaTracks = results[4] as List<Map<String, dynamic>>;
    final addonTracks = results[5] as List<Map<String, dynamic>>;

    var ytTracks = (yt['tracks'] as List?)?.cast<Map<String, dynamic>>() ?? const <Map<String, dynamic>>[];
    final ytTop = yt['top'] as Map<String, dynamic>?;
    if (ytTracks.isEmpty && ytTop == null) {
      ytTracks = await YtMusicClient.instance.webSearchTracks(q, limit: limit);
    }

    final primaryYt = [if (ytTop != null) ytTop, ...ytTracks];
    final spTracks = sp['tracks'] ?? const <Map<String, dynamic>>[];
    final mergedPrimary = <Map<String, dynamic>>[];
    final maxLen = spTracks.length > primaryYt.length ? spTracks.length : primaryYt.length;
    for (var i = 0; i < maxLen; i++) {
      if (i < spTracks.length) mergedPrimary.add(spTracks[i]);
      if (i < primaryYt.length) mergedPrimary.add(primaryYt[i]);
    }

    final combined = _dedupeTracks([
      ...addonTracks,
      ...mergedPrimary,
      ...auTracks,
      ...scTracks,
      ...iaTracks,
    ]).take(limit > 32 ? limit : 32).toList();

    if (bitchordMode) {
      final origin = 'http://127.0.0.1:${_server!.port}';
      final mapped = [
        for (final t in combined.take(limit))
          {
            'id': t['id'],
            'title': t['title'],
            'artist': ((t['artists'] as List?)?.isNotEmpty ?? false) ? (t['artists'] as List).first : 'Desconhecido',
            'artists': t['artists'],
            'album': t['album'],
            'artwork': t['artwork'],
            'duration': t['duration_ms'] is num ? ((t['duration_ms'] as num) / 1000).round() : null,
            'duration_ms': t['duration_ms'],
            'streamURL':
                '$origin/api/stream/${Uri.encodeComponent(t['id'] as String)}?title=${Uri.encodeQueryComponent(t['title'] as String? ?? '')}',
          },
      ];
      await _sendJson(req.response, 200, {'tracks': mapped});
      return;
    }

    LocalStore.instance.saveSearch(q);
    await _sendJson(req.response, 200, {
      'query': q,
      'top': ytTop ?? spTracks.firstOrNull,
      'tracks': combined,
      'albums': [...(sp['albums'] ?? const []), ...(yt['albums'] as List? ?? const [])].take(16).toList(),
      'artists': [...(yt['artists'] as List? ?? const []), ...(sp['artists'] ?? const [])].take(12).toList(),
      'playlists': [...(yt['playlists'] as List? ?? const []), ...(sp['playlists'] ?? const [])].take(12).toList(),
      'sources': {
        'ytmusic': ytTracks.isNotEmpty || ytTop != null,
        'soundcloud': scTracks.isNotEmpty,
        'spotify': SpotifyClient.instance.isEnabled && sp.isNotEmpty,
        'audius': auTracks.isNotEmpty,
        'archive': iaTracks.isNotEmpty,
        'addons': addonTracks.length,
      },
    });
  }

  Future<void> _handleTrackDetail(HttpResponse res, String id) async {
    Map<String, dynamic>? track;
    if (id.startsWith('addon:')) {
      track = AddonClient.instance.getCachedTrack(id);
    } else if (id.startsWith('yt:')) {
      track = await YtMusicClient.instance.track(id.substring(3));
    } else if (id.startsWith('sc:')) {
      track = await SoundCloudClient.instance.track(id.substring(3));
    } else if (id.startsWith('au:')) {
      track = await AudiusClient.instance.track(id.substring(3));
    } else if (id.startsWith('ia:')) {
      track = await ArchiveClient.instance.track(id.substring(3));
    } else if (id.startsWith('sp:track:')) {
      track = await SpotifyClient.instance.track(id.substring(9));
    } else {
      await _sendJson(res, 400, {'error': 'ID de faixa desconhecido'});
      return;
    }
    if (track == null) {
      await _sendJson(res, 404, {'error': 'Faixa não encontrada'});
    } else {
      await _sendJson(res, 200, {'track': track});
    }
  }

  Future<void> _handleAlbumDetail(HttpResponse res, String id) async {
    Map<String, dynamic>? data;
    if (id.startsWith('ytal:')) {
      data = await YtMusicClient.instance.album(id.substring(5));
    } else if (id.startsWith('sp:album:')) {
      data = await SpotifyClient.instance.album(id.substring(9));
    } else {
      await _sendJson(res, 400, {'error': 'ID de álbum desconhecido'});
      return;
    }
    if (data == null) {
      await _sendJson(res, 404, {'error': 'Álbum não encontrado'});
    } else {
      await _sendJson(res, 200, data);
    }
  }

  Future<void> _handleArtistDetail(HttpResponse res, String id) async {
    Map<String, dynamic>? data;
    if (id.startsWith('ytar:')) {
      data = await YtMusicClient.instance.artist(id.substring(5));
    } else if (id.startsWith('name:')) {
      final name = Uri.decodeComponent(id.substring(5)).trim();
      if (name.isEmpty) {
        await _sendJson(res, 400, {'error': 'Nome do artista inválido'});
        return;
      }
      data = await YtMusicClient.instance.searchArtistByName(name);
    } else if (id.startsWith('sp:artist:')) {
      data = await SpotifyClient.instance.artist(id.substring(10));
    } else {
      await _sendJson(res, 400, {'error': 'ID de artista desconhecido'});
      return;
    }
    if (data == null) {
      await _sendJson(res, 404, {'error': 'Artista não encontrado'});
    } else {
      await _sendJson(res, 200, data);
    }
  }

  Future<void> _handlePlaylistRef(HttpResponse res, String id) async {
    Map<String, dynamic>? data;
    if (id.startsWith('ytpl:')) {
      data = await YtMusicClient.instance.playlist(id.substring(5));
    } else if (id.startsWith('sp:playlist:')) {
      data = await SpotifyClient.instance.playlist(id.substring(12));
    } else {
      await _sendJson(res, 400, {'error': 'ID de playlist desconhecido'});
      return;
    }
    if (data == null) {
      await _sendJson(res, 404, {'error': 'Playlist não encontrada'});
    } else {
      await _sendJson(res, 200, data);
    }
  }

  // ---------------- Stream & HLS Proxy ----------------

  Future<void> _handleStreamProducer(HttpRequest req, String id) async {
    final qp = req.uri.queryParameters;
    final resolved = await StreamResolver.instance.resolveStream(
      id,
      title: qp['title'],
      artists: (qp['artist'] ?? '').isNotEmpty ? [qp['artist']!] : const [],
      durationMs: int.tryParse(qp['duration'] ?? ''),
    );
    final origin = 'http://127.0.0.1:${_server!.port}';
    final proxied = '$origin/api/stream/${Uri.encodeComponent(id)}';
    await _sendJson(req.response, 200, {
      'kind': resolved.kind,
      'url': proxied,
      'streamURL': proxied,
      'mime': resolved.kind == 'hls' ? 'application/vnd.apple.mpegurl' : resolved.mime,
      'expiresAt': resolved.expiresAtMs,
    });
  }

  Future<void> _handleStream(HttpRequest req, String id) async {
    final qp = req.uri.queryParameters;
    final resolveOnly = qp['resolve'] == '1';
    final progressive = qp['format'] == 'progressive';
    final forDownload = qp['download'] == '1';
    final rawArtist = qp['artist'] ?? '';
    final artists = rawArtist.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final durMs = int.tryParse(qp['duration'] ?? '');

    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final resolved = await StreamResolver.instance.resolveStream(
          id,
          title: qp['title'],
          artists: artists,
          durationMs: durMs,
          isrc: qp['isrc'],
          album: qp['album'],
          progressive: progressive,
          forDownload: forDownload,
        );

        if (progressive && resolved.kind != 'direct') {
          await _sendJson(req.response, 502, {'error': 'Stream progressivo indisponível', 'code': 'unavailable'});
          return;
        }

        if (resolveOnly) {
          if (resolved.kind == 'hls') {
            await _sendJson(req.response, 200, {
              'kind': 'hls',
              'url': resolved.url,
              'mime': 'application/vnd.apple.mpegurl',
              'ext': 'm3u8',
              'expires_at': resolved.expiresAtMs,
            });
          } else {
            await _sendJson(req.response, 200, {
              'kind': 'direct',
              'url': resolved.url,
              'mime': resolved.mime,
              'ext': extFromMime(resolved.mime, resolved.url),
              'expires_at': resolved.expiresAtMs,
            });
          }
          return;
        }

        if (resolved.kind == 'hls') {
          final playlist = await _fetchAndRewriteHls(resolved.url);
          await _sendText(req.response, 200, 'application/vnd.apple.mpegurl; charset=utf-8', playlist);
          return;
        }

        final upstreamReq = await _http.getUrl(Uri.parse(resolved.url));
        upstreamReq.headers.set(HttpHeaders.userAgentHeader, kEngineUserAgent);
        final range = req.headers.value(HttpHeaders.rangeHeader);
        if (range != null && range.isNotEmpty) {
          upstreamReq.headers.set(HttpHeaders.rangeHeader, range);
        }
        final upstreamRes = await upstreamReq.close();

        if ((upstreamRes.statusCode == 401 || upstreamRes.statusCode == 403) && attempt == 0) {
          await upstreamRes.drain<void>().catchError((Object _) {});
          engineCache.deletePrefix('stream:');
          continue;
        }

        await _pipeUpstreamResponse(req.response, upstreamRes);
        return;
      } on ResolveException catch (e) {
        await _sendJson(req.response, e.status, {'error': e.message, 'code': e.code});
        return;
      } catch (e) {
        if (attempt == 1) {
          await _sendJson(req.response, 502, {'error': e.toString(), 'code': 'unavailable'});
          return;
        }
      }
    }
  }

  Future<void> _handleStreamDownload(HttpRequest req, String id) async {
    final qp = req.uri.queryParameters;
    final rawArtist = qp['artist'] ?? '';
    final artists = rawArtist.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final resolved = await StreamResolver.instance.resolveStream(
      id,
      title: qp['title'],
      artists: artists,
      durationMs: int.tryParse(qp['duration'] ?? ''),
      progressive: true,
      forDownload: true,
    );
    final upstreamReq = await _http.getUrl(Uri.parse(resolved.url));
    upstreamReq.headers.set(HttpHeaders.userAgentHeader, kEngineUserAgent);
    final upstreamRes = await upstreamReq.close();

    final ext = extFromMime(resolved.mime, resolved.url);
    final rawName = '${artists.isNotEmpty ? '${artists.first} - ' : ''}${qp['title'] ?? 'track'}';
    final safeName = rawName.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]+'), '_').trim();
    final fileName = '${safeName.isEmpty ? 'resong' : safeName}.$ext';

    req.response.headers.set('content-disposition', 'attachment; filename="$fileName"');
    await _pipeUpstreamResponse(req.response, upstreamRes);
  }

  Future<void> _handleHlsProxy(HttpRequest req) async {
    final encoded = req.uri.queryParameters['u'];
    if (encoded == null || encoded.isEmpty) {
      await _sendJson(req.response, 400, {'error': 'u obrigatório'});
      return;
    }
    Uri parsed;
    try {
      final padded = encoded.padRight((encoded.length + 3) & ~3, '=');
      final target = utf8.decode(base64Url.decode(padded));
      parsed = Uri.parse(target);
    } catch (_) {
      await _sendJson(req.response, 400, {'error': 'u inválido'});
      return;
    }
    if ((parsed.scheme != 'https' && parsed.scheme != 'http') || !isHostAllowedForProxy(parsed.host)) {
      await _sendJson(req.response, 403, {'error': 'host não permitido'});
      return;
    }

    final upstreamReq = await _http.getUrl(parsed);
    upstreamReq.headers.set(HttpHeaders.userAgentHeader, kEngineUserAgent);
    final range = req.headers.value(HttpHeaders.rangeHeader);
    if (range != null && range.isNotEmpty) {
      upstreamReq.headers.set(HttpHeaders.rangeHeader, range);
    }
    final upstreamRes = await upstreamReq.close();
    final ct = upstreamRes.headers.value(HttpHeaders.contentTypeHeader) ?? '';
    if (ct.contains('mpegurl') || parsed.toString().contains('.m3u8')) {
      final body = await utf8.decoder.bind(upstreamRes).join();
      final rewritten = _rewriteHlsPlaylist(body, parsed);
      await _sendText(req.response, 200, 'application/vnd.apple.mpegurl; charset=utf-8', rewritten);
      return;
    }
    await _pipeUpstreamResponse(req.response, upstreamRes);
  }

  Future<String> _fetchAndRewriteHls(String playlistUrl) async {
    final uri = Uri.parse(playlistUrl);
    final req = await _http.getUrl(uri);
    req.headers.set(HttpHeaders.userAgentHeader, kEngineUserAgent);
    final res = await req.close();
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ResolveException('Playlist HLS respondeu ${res.statusCode}', status: 502);
    }
    final text = await utf8.decoder.bind(res).join();
    return _rewriteHlsPlaylist(text, uri);
  }

  String _rewriteHlsPlaylist(String text, Uri baseUri) {
    String sign(String rawRef) {
      try {
        final abs = baseUri.resolve(rawRef).toString();
        registerAllowedHost(abs);
        final token = base64Url.encode(utf8.encode(abs)).replaceAll('=', '');
        return '/api/hls?u=$token';
      } catch (_) {
        return rawRef;
      }
    }

    final out = <String>[];
    for (final line in text.split(RegExp(r'\r?\n'))) {
      final t = line.trim();
      if (t.isEmpty) {
        out.add(line);
      } else if (t.startsWith('#')) {
        out.add(line.replaceAllMapped(RegExp(r'URI="([^"]+)"'), (m) => 'URI="${sign(m.group(1)!)}"'));
      } else {
        out.add(sign(t));
      }
    }
    return out.join('\n');
  }

  Future<void> _pipeUpstreamResponse(HttpResponse out, HttpClientResponse upstream) async {
    _setCors(out);
    out.statusCode = upstream.statusCode;
    out.bufferOutput = false;
    for (final headerName in const [
      'content-type',
      'content-length',
      'content-range',
      'accept-ranges',
    ]) {
      final v = upstream.headers.value(headerName);
      if (v != null && v.isNotEmpty) out.headers.set(headerName, v);
    }
    out.headers.set('cache-control', 'no-store');
    try {
      await upstream.pipe(out);
    } catch (_) {
      try {
        await out.close();
      } catch (_) {}
    }
  }

  // ---------------- Library & Playlists ----------------

  Future<void> _handleLibrary(HttpRequest req, String method, List<String> seg) async {
    final res = req.response;
    if (method == 'GET' && seg.length == 2) {
      await _sendJson(res, 200, {
        'favorites': LocalStore.instance.listFavorites(),
        'recent_tracks': LocalStore.instance.listRecent(),
        'playlists': LocalStore.instance.listPlaylists(),
        'searches': LocalStore.instance.listSearches(),
      });
      return;
    }

    if (seg.length >= 3 && seg[2] == 'favorites') {
      if (method == 'GET' && seg.length == 3) {
        await _sendJson(res, 200, {'favorites': LocalStore.instance.listFavorites()});
        return;
      }
      if (method == 'POST' && seg.length == 3) {
        final body = await _readJsonBody(req);
        final track = (body['track'] as Map?)?.cast<String, dynamic>();
        if (track == null || track['id'] == null) {
          await _sendJson(res, 400, {'error': 'track inválida'});
          return;
        }
        await LocalStore.instance.addFavorite(track);
        await _sendJson(res, 200, {'ok': true, 'track_id': track['id']});
        return;
      }
      if (method == 'DELETE' && seg.length == 4) {
        await LocalStore.instance.removeFavorite(seg[3]);
        await _sendJson(res, 200, {'ok': true});
        return;
      }
    }

    if (seg.length == 3 && seg[2] == 'recent') {
      if (method == 'GET') {
        await _sendJson(res, 200, {'recent_tracks': LocalStore.instance.listRecent()});
        return;
      }
      if (method == 'POST') {
        final body = await _readJsonBody(req);
        final track = (body['track'] as Map?)?.cast<String, dynamic>();
        if (track == null || track['id'] == null) {
          await _sendJson(res, 400, {'error': 'track inválida'});
          return;
        }
        await LocalStore.instance.addRecent(track);
        await _sendJson(res, 200, {'ok': true});
        return;
      }
      if (method == 'DELETE') {
        await LocalStore.instance.clearRecent();
        await _sendJson(res, 200, {'ok': true});
        return;
      }
    }

    if (seg.length == 3 && seg[2] == 'searches') {
      if (method == 'DELETE') {
        await LocalStore.instance.clearSearches();
        await _sendJson(res, 200, {'ok': true});
        return;
      }
      if (method == 'POST') {
        final body = await _readJsonBody(req);
        final q = (body['q'] as String? ?? '').trim();
        if (q.isNotEmpty) LocalStore.instance.saveSearch(q);
        await _sendJson(res, 200, {'ok': true});
        return;
      }
    }

    await _sendJson(res, 404, {'error': 'rota não encontrada'});
  }

  Future<void> _handlePlaylists(HttpRequest req, String method, List<String> seg) async {
    final res = req.response;
    if (method == 'GET' && seg.length == 2) {
      await _sendJson(res, 200, {'playlists': LocalStore.instance.listPlaylists()});
      return;
    }
    if (method == 'POST' && seg.length == 2) {
      final body = await _readJsonBody(req);
      final checked = sanitizeHandleLocal((body['name'] as String?) ?? '');
      if (!checked.ok) {
        await _sendJson(res, 400, {'error': 'invalid_name', 'reason': checked.reason});
        return;
      }
      final id = 'pl_${DateTime.now().microsecondsSinceEpoch}';
      final created = await LocalStore.instance.createPlaylist(
        id: id,
        name: checked.value,
        description: ((body['description'] as String?) ?? '').trim(),
        artwork: body['artwork'] as String?,
      );
      await _sendJson(res, 200, {'playlist': created});
      return;
    }

    if (seg.length == 3) {
      final id = seg[2];
      if (method == 'GET') {
        final pl = LocalStore.instance.getPlaylist(id);
        if (pl == null) {
          await _sendJson(res, 404, {'error': 'playlist não encontrada'});
        } else {
          await _sendJson(res, 200, {'playlist': pl});
        }
        return;
      }
      if (method == 'PATCH') {
        final body = await _readJsonBody(req);
        String? nextName;
        if (body.containsKey('name')) {
          final checked = sanitizeHandleLocal((body['name'] as String?) ?? '');
          if (!checked.ok) {
            await _sendJson(res, 400, {'error': 'invalid_name', 'reason': checked.reason});
            return;
          }
          nextName = checked.value;
        }
        final ok = await LocalStore.instance.patchPlaylist(
          id,
          name: nextName,
          description: body['description'] as String?,
          artwork: body['artwork'] as String?,
          updateArtwork: body.containsKey('artwork'),
        );
        if (!ok) {
          await _sendJson(res, 404, {'error': 'playlist não encontrada'});
        } else {
          await _sendJson(res, 200, {'ok': true});
        }
        return;
      }
      if (method == 'DELETE') {
        await LocalStore.instance.deletePlaylist(id);
        await _sendJson(res, 200, {'ok': true});
        return;
      }
    }

    if (seg.length == 4 && seg[3] == 'tracks' && method == 'POST') {
      final body = await _readJsonBody(req);
      final track = (body['track'] as Map?)?.cast<String, dynamic>();
      if (track == null || track['id'] == null) {
        await _sendJson(res, 400, {'error': 'track inválida'});
        return;
      }
      final result = await LocalStore.instance.addTrackToPlaylist(seg[2], track);
      if (!result.found) {
        await _sendJson(res, 404, {'error': 'playlist não encontrada'});
      } else {
        await _sendJson(res, 200, {'ok': true, if (result.deduped) 'deduped': true});
      }
      return;
    }

    if (seg.length == 5 && seg[3] == 'tracks' && method == 'DELETE') {
      await LocalStore.instance.removeTrackFromPlaylist(seg[2], seg[4]);
      await _sendJson(res, 200, {'ok': true});
      return;
    }

    if (seg.length == 5 && seg[3] == 'tracks' && seg[4] == 'order' && method == 'PUT') {
      final body = await _readJsonBody(req);
      final order = (body['order'] as List?)?.map((e) => e.toString()).toList();
      if (order == null) {
        await _sendJson(res, 400, {'error': 'order obrigatório'});
        return;
      }
      await LocalStore.instance.reorderPlaylist(seg[2], order);
      await _sendJson(res, 200, {'ok': true});
      return;
    }

    if (seg.length == 4 && seg[3] == 'export' && method == 'GET') {
      final pl = LocalStore.instance.getPlaylist(seg[2]);
      if (pl == null) {
        await _sendJson(res, 404, {'error': 'playlist não encontrada'});
        return;
      }
      final tracks = (pl['tracks'] as List).cast<Map<String, dynamic>>();
      final name = pl['name'] as String? ?? 'Playlist';
      final fmt = (req.uri.queryParameters['format'] ?? 'json').toLowerCase();
      if (fmt == 'csv') {
        String esc(String v) => '"${v.replaceAll('"', '""')}"';
        final lines = ['title,artists,album,duration_ms,id'];
        for (final t in tracks) {
          lines.add([
            esc(t['title']?.toString() ?? ''),
            esc(((t['artists'] as List?) ?? const []).join('; ')),
            esc(t['album']?.toString() ?? ''),
            t['duration_ms']?.toString() ?? '',
            esc(t['id']?.toString() ?? ''),
          ].join(','));
        }
        await _sendText(res, 200, 'text/csv; charset=utf-8', lines.join('\n'));
        return;
      }
      if (fmt == 'm3u') {
        final lines = ['#EXTM3U', '#PLAYLIST:$name'];
        for (final t in tracks) {
          final sec = (((t['duration_ms'] as num?) ?? 0) / 1000).round();
          lines.add('#EXTINF:$sec,${((t['artists'] as List?) ?? const []).join(', ')} - ${t['title']}');
          lines.add('resong://${t['id']}');
        }
        await _sendText(res, 200, 'audio/x-mpegurl; charset=utf-8', lines.join('\n'));
        return;
      }
      if (fmt == 'jspf') {
        await _sendJson(res, 200, {
          'playlist': {
            'title': name,
            'track': [
              for (final t in tracks)
                {
                  'title': t['title'],
                  'creator': ((t['artists'] as List?) ?? const []).join(', '),
                  if (t['album'] != null) 'album': t['album'],
                  if (t['duration_ms'] != null) 'duration': t['duration_ms'],
                },
            ],
          },
        });
        return;
      }
      await _sendJson(res, 200, {'playlist': pl});
      return;
    }

    await _sendJson(res, 404, {'error': 'rota não encontrada'});
  }

  // ---------------- Sources / Addons ----------------

  List<Map<String, dynamic>> _nativeSourcesList() {
    final sp = SpotifyClient.instance.getStatus();
    return [
      {
        'id': 'ytmusic',
        'label': 'YouTube Music',
        'fixed': true,
        'allow_downloads': true,
        'configured': true,
        'enabled': true,
        'configurable': false,
        'toggleable': false,
      },
      {
        'id': 'soundcloud',
        'label': 'SoundCloud',
        'fixed': true,
        'allow_downloads': true,
        'configured': true,
        'enabled': true,
        'configurable': false,
        'toggleable': false,
      },
      {
        'id': 'spotify',
        'label': 'Spotify',
        'fixed': true,
        'allow_downloads': true,
        'configured': sp['configured'],
        'enabled': sp['enabled'],
        'configurable': true,
        'toggleable': sp['configured'],
        'client_id_preview': sp['client_id_preview'],
      },
      {
        'id': 'audius',
        'label': 'Audius',
        'fixed': true,
        'allow_downloads': true,
        'configured': true,
        'enabled': AudiusClient.instance.isEnabled,
        'configurable': false,
        'toggleable': true,
      },
      {
        'id': 'archive',
        'label': 'Internet Archive',
        'fixed': true,
        'allow_downloads': true,
        'configured': true,
        'enabled': ArchiveClient.instance.isEnabled,
        'configurable': false,
        'toggleable': true,
      },
    ];
  }

  Future<void> _handleSources(HttpRequest req, String method, List<String> seg) async {
    final res = req.response;
    if (method == 'GET' && seg.length == 2) {
      await _sendJson(res, 200, {
        'sources': LocalStore.instance.listAddonSources(),
        'native_sources': _nativeSourcesList(),
        'spotify': SpotifyClient.instance.getStatus(),
      });
      return;
    }
    if (method == 'PUT' && seg.length == 3 && seg[2] == 'spotify') {
      final body = await _readJsonBody(req);
      try {
        final sp = await SpotifyClient.instance.setSettings(
          enabled: body['enabled'] as bool?,
          clientId: body['client_id'] as String?,
          clientSecret: body['client_secret'] as String?,
          clearCredentials: body['clear_credentials'] == true,
        );
        await _sendJson(res, 200, {'spotify': sp, 'native_sources': _nativeSourcesList()});
      } catch (e) {
        await _sendJson(res, 400, {'error': e.toString()});
      }
      return;
    }
    if (method == 'PATCH' && seg.length == 4 && seg[2] == 'native') {
      final body = await _readJsonBody(req);
      final enabled = body['enabled'] is bool ? body['enabled'] as bool : true;
      if (seg[3] == 'audius') {
        await AudiusClient.instance.setEnabled(enabled);
        await _sendJson(res, 200, {'native_sources': _nativeSourcesList()});
        return;
      }
      if (seg[3] == 'archive') {
        await ArchiveClient.instance.setEnabled(enabled);
        await _sendJson(res, 200, {'native_sources': _nativeSourcesList()});
        return;
      }
      await _sendJson(res, 404, {'error': 'provedor nativo não alternável'});
      return;
    }
    if (method == 'POST' && seg.length == 2) {
      final body = await _readJsonBody(req);
      final rawUrl = (body['url'] as String? ?? '').trim();
      if (rawUrl.isEmpty) {
        await _sendJson(res, 400, {'error': 'url do addon obrigatória'});
        return;
      }
      final info = await AddonClient.instance.identifyAddon(
        rawUrl,
        customLabel: body['label'] as String?,
        force: true,
      );
      final saved = await LocalStore.instance.saveAddonSource(info);
      await _sendJson(res, 200, {'source': saved});
      return;
    }
    if (method == 'PUT' && seg.length == 3 && seg[2] == 'order') {
      final body = await _readJsonBody(req);
      final order = (body['order'] as List?)?.map((e) => e.toString()).toList();
      if (order == null) {
        await _sendJson(res, 400, {'error': 'order obrigatório'});
        return;
      }
      await LocalStore.instance.reorderAddonSources(order);
      await _sendJson(res, 200, {'sources': LocalStore.instance.listAddonSources()});
      return;
    }
    if (method == 'PATCH' && seg.length == 3) {
      final body = await _readJsonBody(req);
      final patch = <String, dynamic>{};
      if (body['enabled'] is bool) patch['enabled'] = body['enabled'];
      if (body['label'] is String && (body['label'] as String).trim().isNotEmpty) {
        final lbl = (body['label'] as String).trim();
        patch['label'] = lbl.length > 80 ? lbl.substring(0, 80) : lbl;
      }
      final updated = await LocalStore.instance.updateAddonSource(seg[2], patch);
      if (updated == null) {
        await _sendJson(res, 404, {'error': 'fonte não encontrada'});
      } else {
        await _sendJson(res, 200, {'source': updated});
      }
      return;
    }
    if (method == 'POST' && seg.length == 4 && seg[3] == 'check') {
      final updated = await AddonClient.instance.checkSourceHealth(seg[2]);
      if (updated == null) {
        await _sendJson(res, 404, {'error': 'fonte não encontrada'});
      } else {
        await _sendJson(res, 200, {'source': updated});
      }
      return;
    }
    if (method == 'DELETE' && seg.length == 3) {
      if (LocalStore.instance.getAddonSource(seg[2]) == null) {
        await _sendJson(res, 404, {'error': 'fonte não encontrada'});
        return;
      }
      await LocalStore.instance.deleteAddonSource(seg[2]);
      await _sendJson(res, 200, {'ok': true});
      return;
    }

    await _sendJson(res, 404, {'error': 'rota não encontrada'});
  }
}

Future<void> ensureLocalEngineStarted() async {
  await LocalEngineServer.instance.start();
}
