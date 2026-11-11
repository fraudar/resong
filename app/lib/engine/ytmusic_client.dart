// language: Dart, file: lib/engine/ytmusic_client.dart, target: mobile + desktop, runtime: resong engine
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'engine_utils.dart';
import 'soundcloud_client.dart';

class YtMusicClient {
  YtMusicClient._();
  static final YtMusicClient instance = YtMusicClient._();

  static const _apiBase = 'https://music.youtube.com/youtubei/v1';
  static const _clientVersion = '1.20250401.01.00';

  YoutubeExplode? _yt;
  YoutubeExplode get _explode => _yt ??= YoutubeExplode();

  Future<Map<String, dynamic>?> _innertube(String endpoint, Map<String, dynamic> body) async {
    try {
      final res = await engineDio.post<Map<String, dynamic>>(
        '$_apiBase/$endpoint?prettyPrint=false',
        data: {
          'context': {
            'client': {
              'clientName': 'WEB_REMIX',
              'clientVersion': _clientVersion,
              'hl': 'pt',
              'gl': 'BR',
            },
          },
          ...body,
        },
        options: Options(
          headers: {
            'origin': 'https://music.youtube.com',
            'referer': 'https://music.youtube.com/',
            'content-type': 'application/json',
            'user-agent': kEngineUserAgent,
            'x-youtube-client-name': '67',
            'x-youtube-client-version': _clientVersion,
            'accept-language': 'pt-BR,pt;q=0.9,en-US;q=0.8,en;q=0.7',
          },
          receiveTimeout: const Duration(seconds: 15),
        ),
      );
      if (res.statusCode == 200) return res.data;
    } catch (_) {}
    return null;
  }

  // ---------------- JSON extraction helpers ----------------

  String _runsText(Object? node) {
    if (node is String) return node.trim();
    if (node is! Map) return '';
    final simple = node['simpleText'];
    if (simple is String && simple.trim().isNotEmpty) return simple.trim();
    final runs = node['runs'];
    if (runs is List) {
      return runs
          .whereType<Map>()
          .map((r) => (r['text'] ?? '').toString())
          .join()
          .trim();
    }
    final text = node['text'];
    if (text is String) return text.trim();
    return '';
  }

  List<Map<String, dynamic>> _runsList(Object? node) {
    if (node is! Map) return const [];
    final runs = node['runs'];
    if (runs is! List) return const [];
    return [for (final r in runs.whereType<Map>()) r.cast<String, dynamic>()];
  }

  String? _bestThumb(Object? node) {
    List? list;
    if (node is List) {
      list = node;
    } else if (node is Map) {
      if (node['thumbnails'] is List) {
        list = node['thumbnails'] as List;
      } else if (node['thumbnail'] is Map) {
        return _bestThumb(node['thumbnail']);
      } else if (node['musicThumbnailRenderer'] is Map) {
        return _bestThumb((node['musicThumbnailRenderer'] as Map)['thumbnail']);
      } else if (node['croppedSquareThumbnailRenderer'] is Map) {
        return _bestThumb((node['croppedSquareThumbnailRenderer'] as Map)['thumbnail']);
      }
    }
    if (list == null || list.isEmpty) return null;
    Map? best;
    var bestArea = -1;
    for (final item in list.whereType<Map>()) {
      final w = (item['width'] as num?)?.toInt() ?? 0;
      final h = (item['height'] as num?)?.toInt() ?? 0;
      final area = w * h;
      if (area >= bestArea) {
        bestArea = area;
        best = item;
      }
    }
    final url = (best?['url'] as String?)?.trim();
    if (url == null || url.isEmpty) return null;
    return url.startsWith('//') ? 'https:$url' : url;
  }

  String? _videoIdFromEndpoint(Object? ep) {
    if (ep is! Map) return null;
    final watch = ep['watchEndpoint'];
    if (watch is Map && watch['videoId'] is String) return watch['videoId'] as String;
    final wpe = ep['watchPlaylistEndpoint'];
    if (wpe is Map && wpe['videoId'] is String) return wpe['videoId'] as String;
    return null;
  }

  String? _browseIdFromEndpoint(Object? ep) {
    if (ep is! Map) return null;
    final be = ep['browseEndpoint'];
    if (be is Map && be['browseId'] is String) return be['browseId'] as String;
    return null;
  }

  bool _hasExplicitBadge(Object? badges) {
    if (badges is! List) return false;
    return jsonEncode(badges).contains('EXPLICIT');
  }

  bool _isBrowseArtistId(String? id) => id != null && id.startsWith('UC');
  bool _isBrowseAlbumId(String? id) => id != null && (id.startsWith('MPRE') || id.startsWith('OLAK'));
  bool _isBrowsePlaylistId(String? id) =>
      id != null && RegExp(r'^(VL|PL|RD|OLAK|UU)').hasMatch(id) && !id.startsWith('OLAK5uy_');

  bool _isMetaSeparator(String text) {
    final t = text.trim();
    return t.isEmpty || t == '•' || t == '&' || t == ',' || t == '/' || t.toLowerCase() == 'e';
  }

  bool _isDurationText(String text) => RegExp(r'^(?:\d+:)?\d{1,2}:\d{2}$').hasMatch(text.trim());

  bool _isCountOrTypeLabel(String text) {
    final lower = text.trim().toLowerCase();
    return const {
      'música',
      'musica',
      'vídeo',
      'video',
      'álbum',
      'album',
      'ep',
      'single',
      'artista',
      'playlist',
      'song',
      'artist',
    }.contains(lower) ||
        RegExp(r'^\d{4}$').hasMatch(lower) ||
        RegExp(r'exibições|visualizações|views|ouvintes|inscritos|subscribers|listeners|plays|reproduções', caseSensitive: false)
            .hasMatch(lower);
  }

  Map<String, dynamic>? _parseListItemAsTrack(Map<String, dynamic> renderer, {String? fallbackAlbum, String? fallbackArt}) {
    final navEp = renderer['navigationEndpoint'];
    final overlayEp = (((renderer['overlay'] as Map?)?['musicItemThumbnailOverlayRenderer'] as Map?)?['content']
            as Map?)?['musicPlayButtonRenderer']?['playNavigationEndpoint'];
    final menuEp = _findWatchEndpointInMenu(renderer['menu']);
    final videoId = _videoIdFromEndpoint(overlayEp) ?? _videoIdFromEndpoint(navEp) ?? _videoIdFromEndpoint(menuEp) ??
        (((renderer['playlistItemData'] as Map?)?['videoId']) as String?);
    if (videoId == null || videoId.isEmpty) return null;

    final flexCols = (renderer['flexColumns'] as List?)?.whereType<Map>().toList() ?? const [];
    final title = flexCols.isNotEmpty
        ? _runsText(flexCols[0]['musicResponsiveListItemFlexColumnRenderer']?['text'])
        : _runsText(renderer['title']);
    if (title.isEmpty) return null;

    final artists = <String>[];
    String? albumName = fallbackAlbum;
    String? albumId;
    String? channelId;
    int? durationSec;

    if (flexCols.length > 1) {
      final runs = _runsList(flexCols[1]['musicResponsiveListItemFlexColumnRenderer']?['text']);
      for (final run in runs) {
        final t = (run['text'] ?? '').toString().trim();
        if (_isMetaSeparator(t)) continue;
        if (_isDurationText(t)) {
          durationSec ??= parseDurationSeconds(t);
          continue;
        }
        final bId = _browseIdFromEndpoint(run['navigationEndpoint']);
        final pageType = ((((run['navigationEndpoint'] as Map?)?['browseEndpoint'] as Map?)?['browseEndpointContextSupportedConfigs']
                as Map?)?['browseEndpointContextMusicConfig'] as Map?)?['pageType'] as String?;
        if (pageType == 'MUSIC_PAGE_TYPE_ALBUM' || (bId != null && _isBrowseAlbumId(bId))) {
          albumName ??= t;
          albumId ??= bId;
        } else if (pageType == 'MUSIC_PAGE_TYPE_ARTIST' || _isBrowseArtistId(bId)) {
          if (!artists.contains(t)) artists.add(t);
          channelId ??= bId;
        } else if (!_isCountOrTypeLabel(t)) {
          if (!artists.contains(t)) artists.add(t);
        }
      }
    }
    if (flexCols.length > 2 && (albumName == null || albumName.isEmpty)) {
      final runs = _runsList(flexCols[2]['musicResponsiveListItemFlexColumnRenderer']?['text']);
      for (final run in runs) {
        final t = (run['text'] ?? '').toString().trim();
        if (_isMetaSeparator(t) || _isDurationText(t) || _isCountOrTypeLabel(t)) continue;
        final bId = _browseIdFromEndpoint(run['navigationEndpoint']);
        if (bId != null && (_isBrowseAlbumId(bId) || albumName == null)) {
          albumName ??= t;
          albumId ??= bId;
          break;
        }
      }
    }

    final fixedCols = (renderer['fixedColumns'] as List?)?.whereType<Map>().toList() ?? const [];
    for (final fc in fixedCols) {
      final t = _runsText(fc['musicResponsiveListItemFixedColumnRenderer']?['text']);
      final sec = parseDurationSeconds(t);
      if (sec != null) {
        durationSec ??= sec;
        break;
      }
    }

    final art = _bestThumb(renderer['thumbnail']) ?? fallbackArt;
    return {
      'id': 'yt:$videoId',
      'source': 'ytmusic',
      'title': title,
      'artists': artists.take(4).toList(),
      if (albumName != null && albumName.isNotEmpty) 'album': albumName,
      'artwork': art,
      'duration_ms': durationSec != null ? durationSec * 1000 : null,
      'explicit': _hasExplicitBadge(renderer['badges']),
      'extra': {
        'video_id': videoId,
        if (albumId != null) 'album_id': albumId,
        if (channelId != null) 'channel_id': channelId,
      },
    };
  }

  Object? _findWatchEndpointInMenu(Object? menu) {
    final items = ((menu as Map?)?['menuRenderer'] as Map?)?['items'];
    if (items is! List) return null;
    for (final it in items.whereType<Map>()) {
      final nav = (it['menuNavigationItemRenderer'] as Map?)?['navigationEndpoint'];
      if (_videoIdFromEndpoint(nav) != null) return nav;
    }
    return null;
  }

  Map<String, dynamic>? _parseTwoRowItem(Map<String, dynamic> renderer) {
    final navEp = renderer['navigationEndpoint'];
    final overlayEp = (((renderer['thumbnailOverlay'] as Map?)?['musicItemThumbnailOverlayRenderer'] as Map?)?['content']
            as Map?)?['musicPlayButtonRenderer']?['playNavigationEndpoint'];
    final title = _runsText(renderer['title']);
    if (title.isEmpty) return null;

    final videoId = _videoIdFromEndpoint(navEp) ?? _videoIdFromEndpoint(overlayEp);
    final browseId = _browseIdFromEndpoint(navEp);
    final art = _bestThumb(renderer['thumbnailRenderer']);
    final subRuns = _runsList(renderer['subtitle']);
    final subtitleText = _runsText(renderer['subtitle']);

    final pageType = ((((navEp as Map?)?['browseEndpoint'] as Map?)?['browseEndpointContextSupportedConfigs']
            as Map?)?['browseEndpointContextMusicConfig'] as Map?)?['pageType'] as String?;

    if (videoId != null && browseId == null) {
      final artists = <String>[];
      String? channelId;
      for (final run in subRuns) {
        final t = (run['text'] ?? '').toString().trim();
        if (_isMetaSeparator(t) || _isDurationText(t) || _isCountOrTypeLabel(t)) continue;
        final bId = _browseIdFromEndpoint(run['navigationEndpoint']);
        if (_isBrowseArtistId(bId)) channelId ??= bId;
        if (!artists.contains(t)) artists.add(t);
      }
      return {
        '_kind': 'track',
        'data': {
          'id': 'yt:$videoId',
          'source': 'ytmusic',
          'title': title,
          'artists': artists.take(4).toList(),
          'artwork': art,
          'duration_ms': null,
          'explicit': _hasExplicitBadge(renderer['subtitleBadges']),
          'extra': {
            'video_id': videoId,
            if (channelId != null) 'channel_id': channelId,
          },
        },
      };
    }

    if (browseId != null) {
      if (pageType == 'MUSIC_PAGE_TYPE_ALBUM' || browseId.startsWith('MPRE')) {
        String? year;
        final artists = <String>[];
        for (final run in subRuns) {
          final t = (run['text'] ?? '').toString().trim();
          if (_isMetaSeparator(t)) continue;
          if (RegExp(r'^\d{4}$').hasMatch(t)) {
            year ??= t;
            continue;
          }
          if (_isCountOrTypeLabel(t)) continue;
          if (!artists.contains(t)) artists.add(t);
        }
        return {
          '_kind': 'album',
          'data': {
            'id': 'ytal:$browseId',
            'source': 'ytmusic',
            'title': title,
            'artists': artists,
            'artwork': art,
            'year': year,
            'track_count': null,
          },
        };
      }
      if (pageType == 'MUSIC_PAGE_TYPE_ARTIST' || browseId.startsWith('UC')) {
        return {
          '_kind': 'artist',
          'data': {
            'id': 'ytar:$browseId',
            'source': 'ytmusic',
            'name': title,
            'artwork': art,
            'subscribers': subtitleText.isNotEmpty ? subtitleText : null,
          },
        };
      }
      return {
        '_kind': 'playlist',
        'data': {
          'id': 'ytpl:$browseId',
          'source': 'ytmusic',
          'title': title,
          'owner': subtitleText.isNotEmpty ? subtitleText.split(' • ').first : null,
          'artwork': art,
          'track_count': null,
          'description': null,
        },
      };
    }
    return null;
  }

  Map<String, dynamic>? _parseListItemTyped(Map<String, dynamic> renderer) {
    final navEp = renderer['navigationEndpoint'];
    final browseId = _browseIdFromEndpoint(navEp);
    final videoId = _videoIdFromEndpoint(navEp) ??
        _videoIdFromEndpoint((((renderer['overlay'] as Map?)?['musicItemThumbnailOverlayRenderer'] as Map?)?['content']
                as Map?)?['musicPlayButtonRenderer']?['playNavigationEndpoint']);
    final pageType = ((((navEp as Map?)?['browseEndpoint'] as Map?)?['browseEndpointContextSupportedConfigs']
            as Map?)?['browseEndpointContextMusicConfig'] as Map?)?['pageType'] as String?;

    if (browseId != null && (pageType == 'MUSIC_PAGE_TYPE_ARTIST' || browseId.startsWith('UC'))) {
      final flexCols = (renderer['flexColumns'] as List?)?.whereType<Map>().toList() ?? const [];
      final name = flexCols.isNotEmpty ? _runsText(flexCols[0]['musicResponsiveListItemFlexColumnRenderer']?['text']) : '';
      if (name.isEmpty) return null;
      final sub = flexCols.length > 1 ? _runsText(flexCols[1]['musicResponsiveListItemFlexColumnRenderer']?['text']) : '';
      return {
        '_kind': 'artist',
        'data': {
          'id': 'ytar:$browseId',
          'source': 'ytmusic',
          'name': name,
          'artwork': _bestThumb(renderer['thumbnail']),
          'subscribers': sub.isNotEmpty ? sub : null,
        },
      };
    }

    if (browseId != null && (pageType == 'MUSIC_PAGE_TYPE_ALBUM' || browseId.startsWith('MPRE'))) {
      final flexCols = (renderer['flexColumns'] as List?)?.whereType<Map>().toList() ?? const [];
      final title = flexCols.isNotEmpty ? _runsText(flexCols[0]['musicResponsiveListItemFlexColumnRenderer']?['text']) : '';
      if (title.isEmpty) return null;
      final runs = flexCols.length > 1 ? _runsList(flexCols[1]['musicResponsiveListItemFlexColumnRenderer']?['text']) : const <Map<String, dynamic>>[];
      String? year;
      final artists = <String>[];
      for (final run in runs) {
        final t = (run['text'] ?? '').toString().trim();
        if (_isMetaSeparator(t) || _isCountOrTypeLabel(t)) continue;
        if (RegExp(r'^\d{4}$').hasMatch(t)) {
          year ??= t;
          continue;
        }
        artists.add(t);
      }
      return {
        '_kind': 'album',
        'data': {
          'id': 'ytal:$browseId',
          'source': 'ytmusic',
          'title': title,
          'artists': artists,
          'artwork': _bestThumb(renderer['thumbnail']),
          'year': year,
          'track_count': null,
        },
      };
    }

    if (browseId != null && (pageType == 'MUSIC_PAGE_TYPE_PLAYLIST' || _isBrowsePlaylistId(browseId))) {
      final flexCols = (renderer['flexColumns'] as List?)?.whereType<Map>().toList() ?? const [];
      final title = flexCols.isNotEmpty ? _runsText(flexCols[0]['musicResponsiveListItemFlexColumnRenderer']?['text']) : '';
      if (title.isEmpty) return null;
      final sub = flexCols.length > 1 ? _runsText(flexCols[1]['musicResponsiveListItemFlexColumnRenderer']?['text']) : '';
      return {
        '_kind': 'playlist',
        'data': {
          'id': 'ytpl:$browseId',
          'source': 'ytmusic',
          'title': title,
          'owner': sub.isNotEmpty ? sub.split(' • ').first : null,
          'artwork': _bestThumb(renderer['thumbnail']),
          'track_count': null,
          'description': null,
        },
      };
    }

    if (videoId != null || renderer['playlistItemData'] != null) {
      final tr = _parseListItemAsTrack(renderer);
      if (tr != null) return {'_kind': 'track', 'data': tr};
    }
    return null;
  }

  List<Map<String, dynamic>> _extractSectionContents(Map<String, dynamic> root) {
    final out = <Map<String, dynamic>>[];
    void walk(Object? node) {
      if (node is List) {
        for (final item in node) {
          walk(item);
        }
        return;
      }
      if (node is! Map) return;
      if (node.containsKey('musicCarouselShelfRenderer')) {
        out.add({'type': 'carousel', 'node': node['musicCarouselShelfRenderer']});
        return;
      }
      if (node.containsKey('musicShelfRenderer')) {
        out.add({'type': 'shelf', 'node': node['musicShelfRenderer']});
        return;
      }
      if (node.containsKey('musicCardShelfRenderer')) {
        out.add({'type': 'card', 'node': node['musicCardShelfRenderer']});
        return;
      }
      if (node.containsKey('musicPlaylistShelfRenderer')) {
        out.add({'type': 'playlist_shelf', 'node': node['musicPlaylistShelfRenderer']});
        return;
      }
      for (final val in node.values) {
        if (val is Map || val is List) walk(val);
      }
    }
    walk(root['contents']);
    return out;
  }

  List<Map<String, dynamic>> _dedupeById(List<Map<String, dynamic>> items) {
    final seen = <String>{};
    final out = <Map<String, dynamic>>[];
    for (final item in items) {
      final id = item['id']?.toString() ?? '';
      if (id.isEmpty || seen.contains(id)) continue;
      seen.add(id);
      out.add(item);
    }
    return out;
  }

  // ---------------- Public Catalog Methods ----------------

  Future<List<Map<String, dynamic>>> home() async {
    final cached = engineCache.get<List<Map<String, dynamic>>>('ytmusic:home');
    if (cached != null) return cached;

    final res = await _innertube('browse', {'browseId': 'FEmusic_home'});
    if (res == null) return const [];

    final sections = <Map<String, dynamic>>[];
    for (final entry in _extractSectionContents(res)) {
      final node = (entry['node'] as Map?)?.cast<String, dynamic>() ?? const {};
      final header = (node['header'] as Map?)?['musicCarouselShelfBasicHeaderRenderer'] ??
          (node['header'] as Map?)?['musicShelfBasicHeaderRenderer'];
      final title = _runsText((header as Map?)?['title'] ?? node['title']);
      final contents = (node['contents'] as List?)?.whereType<Map>() ?? const [];

      final tracks = <Map<String, dynamic>>[];
      final albums = <Map<String, dynamic>>[];
      final artists = <Map<String, dynamic>>[];
      final playlists = <Map<String, dynamic>>[];

      for (final item in contents) {
        Map<String, dynamic>? parsed;
        if (item['musicResponsiveListItemRenderer'] is Map) {
          parsed = _parseListItemTyped((item['musicResponsiveListItemRenderer'] as Map).cast<String, dynamic>());
        } else if (item['musicTwoRowItemRenderer'] is Map) {
          parsed = _parseTwoRowItem((item['musicTwoRowItemRenderer'] as Map).cast<String, dynamic>());
        }
        if (parsed == null) continue;
        switch (parsed['_kind']) {
          case 'track':
            tracks.add(parsed['data'] as Map<String, dynamic>);
            break;
          case 'album':
            albums.add(parsed['data'] as Map<String, dynamic>);
            break;
          case 'artist':
            artists.add(parsed['data'] as Map<String, dynamic>);
            break;
          case 'playlist':
            playlists.add(parsed['data'] as Map<String, dynamic>);
            break;
        }
      }
      if (tracks.isEmpty && albums.isEmpty && artists.isEmpty && playlists.isEmpty) continue;
      sections.add({
        'title': title.isNotEmpty ? title : 'Destaques',
        'tracks': _dedupeById(tracks),
        'albums': _dedupeById(albums),
        'artists': _dedupeById(artists),
        'playlists': _dedupeById(playlists),
      });
    }
    if (sections.isNotEmpty) {
      engineCache.set('ytmusic:home', sections, const Duration(minutes: 10));
    }
    return sections;
  }

  Future<Map<String, dynamic>> search(String query, {int limit = 20, String? params}) async {
    final body = <String, dynamic>{'query': query};
    if (params != null && params.isNotEmpty) body['params'] = params;
    final res = await _innertube('search', body);
    if (res == null) {
      return {
        'tracks': <Map<String, dynamic>>[],
        'albums': <Map<String, dynamic>>[],
        'artists': <Map<String, dynamic>>[],
        'playlists': <Map<String, dynamic>>[],
        'top': null,
      };
    }

    Map<String, dynamic>? topTrack;
    final tracks = <Map<String, dynamic>>[];
    final albums = <Map<String, dynamic>>[];
    final artists = <Map<String, dynamic>>[];
    final playlists = <Map<String, dynamic>>[];

    for (final entry in _extractSectionContents(res)) {
      final node = (entry['node'] as Map?)?.cast<String, dynamic>() ?? const {};
      if (entry['type'] == 'card') {
        final onTap = node['onTap'] ?? (node['buttons'] is List ? (node['buttons'] as List).firstOrNull?['buttonRenderer']?['command'] : null);
        final cardVideoId = _videoIdFromEndpoint(onTap);
        final cardBrowseId = _browseIdFromEndpoint(onTap);
        final cardTitle = _runsText(node['title']);
        final cardSub = _runsText(node['subtitle']);
        final cardArt = _bestThumb(node['thumbnail']);
        if (cardVideoId != null && cardTitle.isNotEmpty) {
          final subRuns = _runsList(node['subtitle']);
          final cardArtists = <String>[];
          String? chId;
          int? durSec;
          for (final run in subRuns) {
            final t = (run['text'] ?? '').toString().trim();
            if (_isMetaSeparator(t) || _isCountOrTypeLabel(t)) continue;
            if (_isDurationText(t)) {
              durSec ??= parseDurationSeconds(t);
              continue;
            }
            final bId = _browseIdFromEndpoint(run['navigationEndpoint']);
            if (_isBrowseArtistId(bId)) chId ??= bId;
            if (!cardArtists.contains(t)) cardArtists.add(t);
          }
          topTrack ??= {
            'id': 'yt:$cardVideoId',
            'source': 'ytmusic',
            'title': cardTitle,
            'artists': cardArtists,
            'artwork': cardArt,
            'duration_ms': durSec != null ? durSec * 1000 : null,
            'explicit': false,
            'extra': {'video_id': cardVideoId, if (chId != null) 'channel_id': chId},
          };
          tracks.add(topTrack);
        } else if (cardBrowseId != null && cardBrowseId.startsWith('UC') && cardTitle.isNotEmpty) {
          artists.add({
            'id': 'ytar:$cardBrowseId',
            'source': 'ytmusic',
            'name': cardTitle,
            'artwork': cardArt,
            'subscribers': cardSub.isNotEmpty ? cardSub : null,
          });
        }
      }

      final contents = (node['contents'] as List?)?.whereType<Map>() ?? const [];
      for (final item in contents) {
        Map<String, dynamic>? parsed;
        if (item['musicResponsiveListItemRenderer'] is Map) {
          parsed = _parseListItemTyped((item['musicResponsiveListItemRenderer'] as Map).cast<String, dynamic>());
        } else if (item['musicTwoRowItemRenderer'] is Map) {
          parsed = _parseTwoRowItem((item['musicTwoRowItemRenderer'] as Map).cast<String, dynamic>());
        }
        if (parsed == null) continue;
        switch (parsed['_kind']) {
          case 'track':
            tracks.add(parsed['data'] as Map<String, dynamic>);
            break;
          case 'album':
            albums.add(parsed['data'] as Map<String, dynamic>);
            break;
          case 'artist':
            artists.add(parsed['data'] as Map<String, dynamic>);
            break;
          case 'playlist':
            playlists.add(parsed['data'] as Map<String, dynamic>);
            break;
        }
      }
    }

    final cleanTracks = _dedupeById(tracks).take(limit).toList();
    return {
      'top': topTrack ?? (cleanTracks.isNotEmpty ? cleanTracks.first : null),
      'tracks': cleanTracks,
      'albums': _dedupeById(albums).take(limit).toList(),
      'artists': _dedupeById(artists).take(limit).toList(),
      'playlists': _dedupeById(playlists).take(limit).toList(),
    };
  }

  Future<List<Map<String, dynamic>>> webSearchTracks(String query, {int limit = 15}) async {
    try {
      final list = await _explode.search.search(query);
      final tracks = <Map<String, dynamic>>[];
      for (final v in list.take(limit)) {
        final durMs = v.duration?.inMilliseconds;
        final vid = v.id.value;
        tracks.add({
          'id': 'yt:$vid',
          'source': 'ytmusic',
          'title': v.title,
          'artists': [cleanArtistName(v.author)],
          'artwork': v.thumbnails.highResUrl,
          'duration_ms': durMs,
          'explicit': false,
          'extra': {'video_id': vid, if (v.channelId.value.isNotEmpty) 'channel_id': v.channelId.value},
        });
      }
      return tracks;
    } catch (_) {
      return const [];
    }
  }

  Future<List<String>> suggest(String query) async {
    final res = await _innertube('music/get_search_suggestions', {'input': query});
    if (res == null) return const [];
    final out = <String>[];
    final contents = res['contents'] as List?;
    if (contents != null) {
      for (final sec in contents.whereType<Map>()) {
        final items = (sec['searchSuggestionsSectionRenderer'] as Map?)?['contents'] as List?;
        if (items == null) continue;
        for (final item in items.whereType<Map>()) {
          final sugg = (item['searchSuggestionRenderer'] as Map?)?['suggestion'];
          final text = _runsText(sugg);
          if (text.isNotEmpty && text != query && !out.contains(text)) {
            out.add(text);
          }
        }
      }
    }
    return out.take(8).toList();
  }

  Map<String, dynamic> _headerFields(Map<String, dynamic>? root) {
    final header = root?['header'] as Map?;
    final twoCol = (root?['contents'] as Map?)?['twoColumnBrowseResultsRenderer'] as Map?;
    final twoColHeaderList = (twoCol?['tabs'] as List?)?.firstOrNull?['tabRenderer']?['content']?['sectionListRenderer']?['contents'] as List?;
    final embeddedHeader = twoColHeaderList?.firstOrNull as Map?;
    final h = header?['musicResponsiveHeaderRenderer'] ??
        header?['musicDetailHeaderRenderer'] ??
        header?['musicImmersiveHeaderRenderer'] ??
        header?['musicVisualHeaderRenderer'] ??
        embeddedHeader?['musicResponsiveHeaderRenderer'] ??
        embeddedHeader?['musicEditablePlaylistDetailHeaderRenderer']?['header']?['musicResponsiveHeaderRenderer'] ??
        const {};
    final map = h.cast<String, dynamic>();
    final subtitle = _runsText(map['subtitle']);
    String? year;
    final ym = RegExp(r'\b(19\d{2}|20\d{2})\b').firstMatch(subtitle);
    if (ym != null) year = ym.group(1);
    final bg = root?['background'];
    final artwork = _bestThumb(map['thumbnail']) ?? _bestThumb(bg);
    return {
      'title': _runsText(map['title']),
      'subtitle': subtitle,
      'strapline': _runsText(map['straplineTextOne']),
      'artwork': artwork,
      'year': year,
      'raw': map,
    };
  }

  Future<Map<String, dynamic>?> album(String browseId) async {
    final res = await _innertube('browse', {'browseId': browseId});
    if (res == null) return null;
    final head = _headerFields(res);
    final title = (head['title'] as String).isNotEmpty ? head['title'] as String : 'Álbum';
    final strapline = head['strapline'] as String;
    final subtitle = head['subtitle'] as String;
    final artists = (strapline.isNotEmpty ? strapline : subtitle)
        .split(' • ')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty && !RegExp(r'^\d{4}$').hasMatch(p) && !_isCountOrTypeLabel(p))
        .take(3)
        .toList();
    final artwork = head['artwork'] as String?;

    final tracks = <Map<String, dynamic>>[];
    for (final entry in _extractSectionContents(res)) {
      final contents = ((entry['node'] as Map?)?['contents'] as List?)?.whereType<Map>() ?? const [];
      for (final item in contents) {
        final r = item['musicResponsiveListItemRenderer'];
        if (r is! Map) continue;
        final t = _parseListItemAsTrack(r.cast<String, dynamic>(), fallbackAlbum: title, fallbackArt: artwork);
        if (t == null) continue;
        if ((t['artists'] as List).isEmpty && artists.isNotEmpty) {
          t['artists'] = artists;
        }
        tracks.add(t);
      }
    }
    return {
      'album': {
        'id': 'ytal:$browseId',
        'source': 'ytmusic',
        'title': title,
        'artists': artists,
        'artwork': artwork,
        'year': head['year'],
        'track_count': tracks.length,
      },
      'tracks': tracks,
    };
  }

  Future<Map<String, dynamic>?> artist(String browseId) async {
    final res = await _innertube('browse', {'browseId': browseId});
    if (res == null) return null;
    final head = _headerFields(res);
    final name = head['title'] as String;
    final rawHeader = head['raw'] as Map<String, dynamic>;
    final subBtn = (rawHeader['subscriptionButton'] as Map?)?['subscribeButtonRenderer'] as Map?;
    final subscribers = _runsText(subBtn?['subscriberCountText']).isNotEmpty
        ? _runsText(subBtn?['subscriberCountText'])
        : (_runsText(subBtn?['longSubscriberCountText']).isNotEmpty ? _runsText(subBtn?['longSubscriberCountText']) : null);

    final sections = <Map<String, dynamic>>[];
    final rawEntries = _extractSectionContents(res);
    String? allSongsBrowseId;

    for (final entry in rawEntries) {
      final node = (entry['node'] as Map?)?.cast<String, dynamic>() ?? const {};
      final rawHeader = node['header'];
      final header = rawHeader is Map
          ? (rawHeader['musicCarouselShelfBasicHeaderRenderer'] ?? rawHeader['musicShelfBasicHeaderRenderer'])
          : null;
      final headerMap = header is Map ? header : null;
      final title = _runsText(headerMap?['title'] ?? node['title']);
      final bottomBrowseId = _browseIdFromEndpoint(node['bottomEndpoint']) ??
          _browseIdFromEndpoint(
            ((headerMap?['moreContentButton'] as Map?)?['buttonRenderer'] as Map?)?['navigationEndpoint'],
          );
      if (allSongsBrowseId == null &&
          bottomBrowseId != null &&
          (bottomBrowseId.startsWith('VL') || bottomBrowseId.startsWith('PL') || bottomBrowseId.startsWith('OLAK'))) {
        allSongsBrowseId = bottomBrowseId;
      }

      final contents = (node['contents'] as List?)?.whereType<Map>() ?? const [];
      final tracks = <Map<String, dynamic>>[];
      final albums = <Map<String, dynamic>>[];
      final artists = <Map<String, dynamic>>[];
      final playlists = <Map<String, dynamic>>[];

      for (final item in contents) {
        Map<String, dynamic>? parsed;
        if (item['musicResponsiveListItemRenderer'] is Map) {
          parsed = _parseListItemTyped((item['musicResponsiveListItemRenderer'] as Map).cast<String, dynamic>());
        } else if (item['musicTwoRowItemRenderer'] is Map) {
          parsed = _parseTwoRowItem((item['musicTwoRowItemRenderer'] as Map).cast<String, dynamic>());
        }
        if (parsed == null) continue;
        switch (parsed['_kind']) {
          case 'track':
            tracks.add(parsed['data'] as Map<String, dynamic>);
            break;
          case 'album':
            albums.add(parsed['data'] as Map<String, dynamic>);
            break;
          case 'artist':
            artists.add(parsed['data'] as Map<String, dynamic>);
            break;
          case 'playlist':
            playlists.add(parsed['data'] as Map<String, dynamic>);
            break;
        }
      }
      if (tracks.isEmpty && albums.isEmpty && artists.isEmpty && playlists.isEmpty) continue;
      sections.add({
        'title': title.isNotEmpty ? title : 'Seção',
        'tracks': _dedupeById(tracks),
        'albums': _dedupeById(albums),
        'artists': _dedupeById(artists),
        'playlists': _dedupeById(playlists),
      });
    }

    final topTracks = _dedupeById([for (final s in sections) ...?(s['tracks'] as List?)?.cast<Map<String, dynamic>>()])
        .take(15)
        .toList();

    var fullSongs = <Map<String, dynamic>>[];
    if (allSongsBrowseId != null) {
      final pl = await playlist(allSongsBrowseId);
      if (pl != null) {
        fullSongs = (pl['tracks'] as List).cast<Map<String, dynamic>>();
      }
    }

    var allTracks = _dedupeById([...topTracks, ...fullSongs]).take(150).toList();
    if (allTracks.length <= 5 && name.isNotEmpty) {
      final searched = await search(name, limit: 25);
      final lower = name.toLowerCase();
      final matching = (searched['tracks'] as List).cast<Map<String, dynamic>>().where((t) {
        final tArtists = (t['artists'] as List?)?.cast<String>() ?? const [];
        final ch = (t['extra'] as Map?)?['channel_id'] as String?;
        return tArtists.any((a) => a.toLowerCase().contains(lower)) || ch == browseId;
      }).toList();
      allTracks = _dedupeById([...allTracks, ...matching]).take(150).toList();
    }

    return {
      'artist': {
        'id': 'ytar:$browseId',
        'source': 'ytmusic',
        'name': name,
        'artwork': head['artwork'],
        'subscribers': subscribers,
      },
      'sections': sections,
      'top_tracks': topTracks,
      'all_tracks': allTracks,
    };
  }

  Future<Map<String, dynamic>?> searchArtistByName(String artistName) async {
    final cleanName = artistName.trim();
    if (cleanName.isEmpty) return null;
    final targetNorm = normCompareText(cleanName);

    final results = await Future.wait([
      search(cleanName, limit: 15, params: 'EgWKAQIgAWoKEAkQChADEAUQBA%3D%3D'),
      search(cleanName, limit: 25),
    ]);
    final artistOnly = (results[0]['artists'] as List).cast<Map<String, dynamic>>();
    final catalog = results[1];
    final catArtists = (catalog['artists'] as List).cast<Map<String, dynamic>>();
    final catTracks = (catalog['tracks'] as List).cast<Map<String, dynamic>>();

    bool exact(String n) => normCompareText(n) == targetNorm && targetNorm.isNotEmpty;
    bool partial(String n) {
      final norm = normCompareText(n);
      return norm.isNotEmpty && (norm.contains(targetNorm) || targetNorm.contains(norm));
    }

    var picked = artistOnly.where((a) => exact(a['name'] as String)).firstOrNull ??
        catArtists.where((a) => exact(a['name'] as String)).firstOrNull ??
        artistOnly.where((a) => partial(a['name'] as String)).firstOrNull ??
        artistOnly.firstOrNull;

    if (picked == null) {
      for (final t in catTracks) {
        final ch = (t['extra'] as Map?)?['channel_id'] as String?;
        final tArtists = (t['artists'] as List?)?.cast<String>() ?? const [];
        if (ch != null && ch.startsWith('UC') && tArtists.any(partial)) {
          picked = {
            'id': 'ytar:$ch',
            'source': 'ytmusic',
            'name': tArtists.isNotEmpty ? tArtists.first : cleanName,
            'artwork': t['artwork'],
            'subscribers': null,
          };
          break;
        }
      }
      picked ??= catArtists.where((a) => partial(a['name'] as String)).firstOrNull;
    }

    if (picked != null && (picked['id'] as String).startsWith('ytar:')) {
      final full = await artist((picked['id'] as String).substring(5));
      if (full != null) return full;
    }

    final matchingTracks = catTracks.where((t) => ((t['artists'] as List?)?.cast<String>() ?? const []).any(partial)).toList();
    final top = (matchingTracks.isNotEmpty ? matchingTracks : catTracks).take(15).toList();
    final artwork = picked?['artwork'] ?? top.where((t) => t['artwork'] != null).map((t) => t['artwork']).firstOrNull;

    return {
      'artist': {
        'id': picked?['id'] ?? 'name:${Uri.encodeComponent(cleanName)}',
        'source': 'ytmusic',
        'name': picked?['name'] ?? cleanName,
        'artwork': artwork,
        'subscribers': picked?['subscribers'],
      },
      'sections': [
        if ((catalog['albums'] as List).isNotEmpty)
          {'title': 'Álbuns', 'tracks': const [], 'albums': catalog['albums'], 'artists': const [], 'playlists': const []},
        if ((catalog['playlists'] as List).isNotEmpty)
          {'title': 'Playlists', 'tracks': const [], 'albums': const [], 'artists': const [], 'playlists': catalog['playlists']},
        if (catArtists.length > 1)
          {'title': 'Fãs também ouvem', 'tracks': const [], 'albums': const [], 'artists': catArtists.skip(1).toList(), 'playlists': const []},
      ],
      'top_tracks': top,
      'all_tracks': top,
    };
  }

  Future<Map<String, dynamic>?> playlist(String browseId) async {
    final targetId = (browseId.startsWith('PL') || browseId.startsWith('RD') || browseId.startsWith('UU'))
        ? 'VL$browseId'
        : browseId;
    var res = await _innertube('browse', {'browseId': targetId});
    res ??= await _innertube('browse', {'browseId': browseId});
    if (res == null) return null;

    final head = _headerFields(res);
    final artwork = head['artwork'] as String?;
    final tracks = <Map<String, dynamic>>[];

    for (final entry in _extractSectionContents(res)) {
      final contents = ((entry['node'] as Map?)?['contents'] as List?)?.whereType<Map>() ?? const [];
      for (final item in contents) {
        final r = item['musicResponsiveListItemRenderer'];
        if (r is! Map) continue;
        final t = _parseListItemAsTrack(r.cast<String, dynamic>(), fallbackArt: artwork);
        if (t != null) tracks.add(t);
      }
    }

    final subtitle = head['subtitle'] as String;
    final owner = subtitle.isNotEmpty ? subtitle.split(' • ').first.trim() : null;
    return {
      'playlist': {
        'id': 'ytpl:$browseId',
        'source': 'ytmusic',
        'title': (head['title'] as String).isNotEmpty ? head['title'] : 'Playlist',
        'owner': owner,
        'artwork': artwork,
        'track_count': tracks.length,
      },
      'tracks': tracks,
    };
  }

  Future<Map<String, dynamic>?> track(String videoId) async {
    try {
      final v = await _explode.videos.get(videoId);
      final cleaned = extractCleanTrack(v.title, v.author);
      final thumb = v.thumbnails.highResUrl.isNotEmpty
          ? v.thumbnails.highResUrl
          : 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
      return {
        'id': 'yt:$videoId',
        'source': 'ytmusic',
        'title': cleaned.track,
        'artists': [if (cleaned.artist != null) cleaned.artist!],
        'artwork': thumb,
        'duration_ms': v.duration?.inMilliseconds,
        'explicit': false,
        'extra': {
          'video_id': videoId,
          if (v.channelId.value.isNotEmpty) 'channel_id': v.channelId.value,
        },
      };
    } catch (_) {
      return null;
    }
  }

  Future<String?> getPlainLyrics(String videoId) async {
    try {
      final nextRes = await _innertube('next', {'videoId': videoId});
      final tabs = (((nextRes?['contents'] as Map?)?['singleColumnMusicWatchNextResultsRenderer'] as Map?)?['tabbedRenderer']
              as Map?)?['watchNextTabbedResultsRenderer']?['tabs'] as List?;
      String? lyricsBrowseId;
      if (tabs != null) {
        for (final tab in tabs.whereType<Map>()) {
          final bId = _browseIdFromEndpoint((tab['tabRenderer'] as Map?)?['endpoint']);
          if (bId != null && bId.startsWith('MPLY')) {
            lyricsBrowseId = bId;
            break;
          }
        }
      }
      if (lyricsBrowseId == null) return null;
      final browseRes = await _innertube('browse', {'browseId': lyricsBrowseId});
      final sections = (((browseRes?['contents'] as Map?)?['sectionListRenderer'] as Map?)?['contents'] as List?) ?? const [];
      for (final sec in sections.whereType<Map>()) {
        final desc = (sec['musicDescriptionShelfRenderer'] as Map?)?['description'];
        final text = _runsText(desc);
        if (text.isNotEmpty) return text;
      }
    } catch (_) {}
    return null;
  }

  static final _variantRx = RegExp(
    r'\b(?:live|ao\s+vivo|ac[uú]stic[oa]|remix|slowed|reverb|sped\s*up|karaoke|instrumental|cover)\b',
    caseSensitive: false,
  );

  Future<Map<String, dynamic>?> matchTrack(
    String title,
    List<String> artists, {
    int? durationMs,
    String? isrc,
    String? albumName,
  }) async {
    final primaryQuery = [title, if (artists.isNotEmpty) artists.first].join(' ').trim();
    if (primaryQuery.isEmpty) return null;

    final searches = <Future<Map<String, dynamic>>>[
      search(primaryQuery, limit: 10),
      if (isrc != null && isrc.trim().length >= 8) search(isrc.trim(), limit: 5),
    ];
    final results = await Future.wait(searches);
    final candidates = _dedupeById([
      for (final r in results) ...?(r['tracks'] as List?)?.cast<Map<String, dynamic>>(),
    ]);
    if (candidates.isEmpty) return null;

    final targetHasVariant = _variantRx.hasMatch(title);
    final primaryArtist = artists.isNotEmpty ? artists.first : '';
    Map<String, dynamic>? best;
    var bestScore = -999.0;

    for (var i = 0; i < candidates.length; i++) {
      final c = candidates[i];
      final cTitle = c['title'] as String? ?? '';
      final cArtists = (c['artists'] as List?)?.cast<String>() ?? const [];
      final cAlbum = c['album'] as String?;
      final cDurMs = (c['duration_ms'] as num?)?.toInt();

      final titleScore = tokenSimilarity(title, cTitle) * 50;
      final artistScore = primaryArtist.isNotEmpty
          ? ([
                tokenSimilarity(primaryArtist, cArtists.isNotEmpty ? cArtists.first : ''),
                tokenSimilarity(primaryArtist, cArtists.join(' ')),
              ]..sort())
                  .last *
              35
          : 15.0;
      final albumScore = (albumName != null && cAlbum != null) ? tokenSimilarity(albumName, cAlbum) * 15 : 0.0;

      var durScore = 0.0;
      if (durationMs != null && durationMs > 0 && cDurMs != null && cDurMs > 0) {
        final diffSec = (cDurMs - durationMs).abs() / 1000.0;
        if (diffSec <= 3) {
          durScore = 40;
        } else if (diffSec <= 7) {
          durScore = 24;
        } else if (diffSec <= 14) {
          durScore = 8;
        } else if (diffSec > 25) {
          durScore = -45;
        } else {
          durScore = -18;
        }
      }

      final variantPenalty = (!targetHasVariant && _variantRx.hasMatch(cTitle)) ? -28.0 : 0.0;
      final rankBias = (6 - i).clamp(0, 6).toDouble();
      final total = titleScore + artistScore + albumScore + durScore + variantPenalty + rankBias;
      if (total > bestScore) {
        bestScore = total;
        best = c;
      }
    }
    return best ?? candidates.first;
  }

  // ---------------- Stream Resolution ----------------

  Future<ResolvedStreamResult> resolveStream(
    String videoId, {
    String? title,
    List<String> artists = const [],
    bool progressive = false,
  }) async {
    final cacheKey = progressive ? 'stream:yt:prog:$videoId' : 'stream:yt:$videoId';
    final now = DateTime.now().millisecondsSinceEpoch;
    final cached = engineCache.get<ResolvedStreamResult>(cacheKey);
    if (cached != null && cached.expiresAtMs > now) return cached;

    String? streamUrl;
    String? mime;

    try {
      final manifest = await _explode.videos.streams.getManifest(videoId);
      final audioStreams = manifest.audioOnly.toList()
        ..sort((a, b) => b.bitrate.bitsPerSecond.compareTo(a.bitrate.bitsPerSecond));
      final mp4Audio = audioStreams.where((s) => s.container.name.toLowerCase() == 'mp4').toList();
      final chosen = progressive
          ? (mp4Audio.firstOrNull ?? audioStreams.firstOrNull ?? manifest.muxed.withHighestBitrate())
          : (mp4Audio.firstOrNull ?? audioStreams.firstOrNull);
      if (chosen != null) {
        streamUrl = chosen.url.toString();
        mime = chosen.container.name.toLowerCase() == 'webm' ? 'audio/webm' : 'audio/mp4';
      }
    } catch (_) {}

    // Secondary desktop fallback se youtube_explode_dart falhar e yt-dlp estiver no sistema.
    if (streamUrl == null && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      try {
        final fmt = progressive ? 'bestaudio[ext=m4a]/bestaudio[protocol=https]/bestaudio' : 'bestaudio[ext=m4a]/bestaudio';
        final proc = await Process.run('yt-dlp', [
          '--no-playlist',
          '--no-warnings',
          '-f',
          fmt,
          '-g',
          'https://www.youtube.com/watch?v=$videoId',
        ]).timeout(const Duration(seconds: 12));
        if (proc.exitCode == 0) {
          final lines = proc.stdout.toString().split(RegExp(r'\r?\n')).map((l) => l.trim()).where((l) => l.startsWith('http'));
          if (lines.isNotEmpty) {
            streamUrl = lines.first;
            mime = guessAudioMime(streamUrl);
          }
        }
      } catch (_) {}
    }

    if (streamUrl == null || streamUrl.isEmpty) {
      // Último recurso: fallback SoundCloud
      if (title != null && title.isNotEmpty) {
        final q = [title, if (artists.isNotEmpty) artists.first].join(' ');
        final hits = await SoundCloudClient.instance.search(q, limit: 5);
        for (final cand in hits) {
          final id = cand['id'] as String? ?? '';
          if (!id.startsWith('sc:')) continue;
          final sc = await SoundCloudClient.instance.resolveStream(id.substring(3), progressiveOnly: progressive);
          if (sc != null) {
            engineCache.set(cacheKey, sc, const Duration(minutes: 30));
            return sc;
          }
        }
      }
      throw Exception('Nenhum stream disponível para yt:$videoId');
    }

    registerAllowedHost(streamUrl);
    final isHls = streamUrl.contains('.m3u8');
    final ttlMs = isHls ? 3 * 3600 * 1000 : ttlMsFromUrl(streamUrl);
    final result = ResolvedStreamResult(
      kind: isHls ? 'hls' : 'direct',
      url: streamUrl,
      mime: isHls ? 'application/vnd.apple.mpegurl' : (mime ?? guessAudioMime(streamUrl)),
      expiresAtMs: now + ttlMs,
    );
    engineCache.set(cacheKey, result, Duration(milliseconds: (ttlMs - 60000).clamp(60000, 5 * 3600 * 1000)));
    return result;
  }
}
