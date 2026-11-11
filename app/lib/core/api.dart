// language: Dart, file: lib/core/api.dart, target: mobile-first + desktop, runtime: resong app
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'format.dart';
import 'models.dart';

class ResolvedDownloadSource {
  const ResolvedDownloadSource({
    required this.url,
    required this.mime,
    required this.ext,
  });

  final String url;
  final String mime;
  final String ext;
}

/// Base inicial (em mobile/desktop o motor local embutido chama [setBaseUrl] em runtime).
const String kApiBase = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'http://127.0.0.1:8787',
);

class Api {
  Api._();
  static final Api instance = Api._();

  String _baseUrl = kApiBase;
  String get baseUrl => _baseUrl;

  /// Atualiza dinamicamente a base HTTP (apontada para o motor local embutido).
  void setBaseUrl(String url) {
    final clean = url.trim().replaceAll(RegExp(r'/+$'), '');
    if (clean.isEmpty) return;
    _baseUrl = clean;
    _dio.options.baseUrl = clean;
  }

  /// Recria o adaptador HTTP (útil em testes após restaurar HttpOverrides).
  void resetHttpAdapter() {
    _dio.httpClientAdapter.close();
    _dio.httpClientAdapter = HttpClientAdapter();
  }

  late final Dio _dio = Dio(
    BaseOptions(
      baseUrl: kApiBase,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 45),
      headers: {'accept': 'application/json'},
    ),
  );

  Future<Map<String, dynamic>> _get(String path, [Map<String, dynamic>? query]) async {
    final res = await _dio.get<Map<String, dynamic>>(path, queryParameters: query);
    return res.data ?? const {};
  }

  Future<Map<String, dynamic>> _send(String method, String path, [Object? body]) async {
    final res = await _dio.request<Map<String, dynamic>>(path, data: body, options: Options(method: method));
    return res.data ?? const {};
  }

  // --- catálogo / busca ---
  Future<HomeFeed> home() async => HomeFeed.fromJson(await _get('/api/home'));

  Future<SearchResults> search(String q, {int limit = 30}) async =>
      SearchResults.fromJson(await _get('/api/search', {'q': q, 'limit': limit}));

  Future<List<String>> suggest(String q) async {
    final data = await _get('/api/suggest', {'q': q});
    return (data['suggestions'] as List?)?.whereType<String>().toList() ?? const [];
  }

  Future<AlbumDetail> album(String id) async =>
      AlbumDetail.fromJson(await _get('/api/album/${Uri.encodeComponent(id)}'));

  Future<Track?> trackDetail(String id) async {
    try {
      final data = await _get('/api/track/${Uri.encodeComponent(id)}');
      final raw = data['track'];
      if (raw is Map) {
        return Track.fromJson(raw.cast<String, dynamic>());
      }
    } catch (_) {}
    return null;
  }

  Future<ArtistDetail> artist(String id) async =>
      ArtistDetail.fromJson(await _get('/api/artist/${Uri.encodeComponent(id)}'));

  Future<PlaylistDetail> playlistRef(String id) async =>
      PlaylistDetail.fromJson(await _get('/api/playlist-ref/${Uri.encodeComponent(id)}'));

  Future<Lyrics?> lyrics({
    String? track,
    String? artist,
    String? album,
    int? durationMs,
    String? videoId,
    String? isrc,
    String? spId,
    int? trackNumber,
  }) async {
    try {
      final durationSec = durationMs != null && durationMs > 0 ? durationMs ~/ 1000 : null;
      final data = await _get('/api/lyrics', {
        if (track != null && track.isNotEmpty) 'track': track,
        if (artist != null && artist.isNotEmpty) 'artist': artist,
        if (album != null && album.isNotEmpty) 'album': album,
        if (durationSec != null && durationSec > 0) 'duration': durationSec,
        if (videoId != null && videoId.isNotEmpty) 'video_id': videoId,
        if (isrc != null && isrc.isNotEmpty) 'isrc': isrc,
        if (spId != null && spId.isNotEmpty) 'sp_id': spId,
        if (trackNumber != null && trackNumber > 0) 'track_number': trackNumber,
      });
      final lyrics = Lyrics.fromJson(data);
      return lyrics.isEmpty ? null : lyrics;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Valida/higieniza localmente nomes de playlist e exibição.
  Future<HandleValidation> validateIdentity(String input) async => sanitizeHandleLocal(input);

  // --- streaming ---
  /// URL que o player consome direto (Range + HLS transparente pro player)
  String streamUrl(Track track, {int? durationMs}) {
    final query = <String, String>{
      if (track.title.isNotEmpty) 'title': track.title,
      if (track.artists.isNotEmpty) 'artist': track.artists.first,
      if ((durationMs ?? track.durationMs) != null) 'duration': '${durationMs ?? track.durationMs}',
    };
    final qs = query.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&');
    final base = '$_baseUrl/api/stream/${Uri.encodeComponent(track.id)}';
    return qs.isEmpty ? base : '$base?$qs';
  }

  /// Faz pré-resolução da próxima faixa no servidor para reprodução Gapless.
  Future<void> prewarmStream(Track track) async {
    try {
      await _get('/api/stream/${Uri.encodeComponent(track.id)}', {
        'resolve': '1',
        if (track.title.isNotEmpty) 'title': track.title,
        if (track.artists.isNotEmpty) 'artist': track.artists.first,
        if (track.durationMs != null) 'duration': track.durationMs,
      });
    } catch (_) {}
  }

  /// URL direta no proxy com ?format=progressive (sem HLS para download local)
  String progressiveStreamUrl(Track track) {
    final query = <String, String>{
      'format': 'progressive',
      'download': '1',
      if (track.title.isNotEmpty) 'title': track.title,
      if (track.artists.isNotEmpty) 'artist': track.artists.first,
      if (track.durationMs != null) 'duration': '${track.durationMs}',
    };
    final qs = query.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&');
    return '$_baseUrl/api/stream/${Uri.encodeComponent(track.id)}?$qs';
  }

  /// Resolve a URL direta na fonte via GET /api/stream/:id?format=progressive&resolve=1
  Future<ResolvedDownloadSource> resolveProgressiveDownload(Track track) async {
    final data = await _get('/api/stream/${Uri.encodeComponent(track.id)}', {
      'format': 'progressive',
      'download': '1',
      'resolve': '1',
      if (track.title.isNotEmpty) 'title': track.title,
      if (track.artists.isNotEmpty) 'artist': track.artists.first,
      if (track.durationMs != null) 'duration': track.durationMs,
    });
    final url = (data['url'] as String? ?? '').trim();
    if (url.isEmpty) {
      throw Exception('Fonte sem URL progressiva disponível');
    }
    return ResolvedDownloadSource(
      url: url,
      mime: (data['mime'] as String?) ?? 'audio/mp4',
      ext: (data['ext'] as String?) ?? 'm4a',
    );
  }

  /// Endpoint transiente para Web: o backend transcodiza/aplica tags e descarta sem gravar em disco.
  String transientWebDownloadUrl(Track track) {
    final query = <String, String>{
      if (track.title.isNotEmpty) 'title': track.title,
      if (track.artists.isNotEmpty) 'artist': track.artists.join(', '),
      if ((track.album ?? '').isNotEmpty) 'album': track.album!,
      if ((track.artwork ?? '').isNotEmpty) 'artwork': track.artwork!,
      if ((track.extra['year'] ?? '').isNotEmpty) 'year': track.extra['year']!,
      if ((track.extra['permalink'] ?? '').isNotEmpty) 'permalink': track.extra['permalink']!,
      if (track.durationMs != null) 'duration': '${track.durationMs}',
    };
    final qs = query.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&');
    final base = '$_baseUrl/api/stream/${Uri.encodeComponent(track.id)}/download';
    return qs.isEmpty ? base : '$base?$qs';
  }

  Future<Uint8List> downloadBytes(
    String url, {
    CancelToken? cancelToken,
    void Function(int received, int total)? onProgress,
    Duration timeout = const Duration(minutes: 4),
  }) async {
    final client = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: timeout,
        responseType: ResponseType.bytes,
        followRedirects: true,
        headers: {'accept': '*/*'},
      ),
    );
    final res = await client.get<List<int>>(
      url,
      cancelToken: cancelToken,
      onReceiveProgress: onProgress,
    );
    return Uint8List.fromList(res.data ?? const <int>[]);
  }

  // --- biblioteca ---
  Future<List<Track>> favorites() async =>
      _listTracks((await _get('/api/library/favorites'))['favorites']);

  Future<void> addFavorite(Track t) => _send('POST', '/api/library/favorites', {'track': t.toJson()});

  Future<void> removeFavorite(String id) => _send('DELETE', '/api/library/favorites/${Uri.encodeComponent(id)}');

  Future<List<Track>> recent() async {
    final data = await _get('/api/library/recent');
    return _listTracks(data['recent_tracks'] ?? data['tracks']);
  }

  Future<void> addRecent(Track t) => _send('POST', '/api/library/recent', {'track': t.toJson()});

  Future<void> clearRecent() => _send('DELETE', '/api/library/recent');

  Future<void> clearSearches() => _send('DELETE', '/api/library/searches');

  Future<List<PlaylistRecord>> playlists() async {
    final data = await _get('/api/playlists');
    return (data['playlists'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => PlaylistRecord.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<PlaylistRecord> createPlaylist(String name, {String description = ''}) async {
    final data = await _send('POST', '/api/playlists', {'name': name, 'description': description});
    return PlaylistRecord.fromJson((data['playlist'] as Map).cast<String, dynamic>());
  }

  Future<PlaylistRecord> playlist(String id) async {
    final data = await _get('/api/playlists/${Uri.encodeComponent(id)}');
    return PlaylistRecord.fromJson((data['playlist'] as Map).cast<String, dynamic>());
  }

  Future<void> renamePlaylist(String id, {String? name, String? description}) =>
      _send('PATCH', '/api/playlists/${Uri.encodeComponent(id)}', {
        if (name != null) 'name': name,
        if (description != null) 'description': description,
      });

  Future<void> deletePlaylist(String id) => _send('DELETE', '/api/playlists/${Uri.encodeComponent(id)}');

  Future<void> addToPlaylist(String playlistId, Track t) =>
      _send('POST', '/api/playlists/${Uri.encodeComponent(playlistId)}/tracks', {'track': t.toJson()});

  Future<void> removeFromPlaylist(String playlistId, String trackId) =>
      _send('DELETE', '/api/playlists/${Uri.encodeComponent(playlistId)}/tracks/${Uri.encodeComponent(trackId)}');

  Future<void> reorderPlaylist(String playlistId, List<String> order) =>
      _send('PUT', '/api/playlists/${Uri.encodeComponent(playlistId)}/tracks/order', {'order': order});

  String playlistExportUrl(String playlistId, {String format = 'json'}) =>
      '$_baseUrl/api/playlists/${Uri.encodeComponent(playlistId)}/export?format=$format';

  // --- letras tradução & romanização ---
  Future<TranslatedLyrics> translateLyrics(List<String> lines, {String target = 'pt'}) async {
    final data = await _send('POST', '/api/lyrics/translate', {
      'lines': lines,
      'target': target,
    });
    return TranslatedLyrics.fromJson(data);
  }

  Future<TranslatedLyrics> romanizeLyrics(List<String> lines) async {
    final data = await _send('POST', '/api/lyrics/romanize', {
      'lines': lines,
    });
    return TranslatedLyrics.fromJson(data);
  }

  // --- fontes / addons (BitChord) ---
  Future<SourcesSnapshot> sources() async =>
      SourcesSnapshot.fromJson(await _get('/api/sources'));

  Future<AddonSource> addSource(String url, {String? label}) async {
    final data = await _send('POST', '/api/sources', {
      'url': url,
      if (label != null && label.trim().isNotEmpty) 'label': label.trim(),
    });
    return AddonSource.fromJson((data['source'] as Map).cast<String, dynamic>());
  }

  Future<AddonSource> updateSource(String id, {bool? enabled, String? label}) async {
    final data = await _send('PATCH', '/api/sources/${Uri.encodeComponent(id)}', {
      if (enabled != null) 'enabled': enabled,
      if (label != null) 'label': label,
    });
    return AddonSource.fromJson((data['source'] as Map).cast<String, dynamic>());
  }

  Future<void> reorderSources(List<String> order) =>
      _send('PUT', '/api/sources/order', {'order': order});

  Future<AddonSource> checkSourceHealth(String id) async {
    final data = await _send('POST', '/api/sources/${Uri.encodeComponent(id)}/check');
    return AddonSource.fromJson((data['source'] as Map).cast<String, dynamic>());
  }

  Future<void> deleteSource(String id) =>
      _send('DELETE', '/api/sources/${Uri.encodeComponent(id)}');

  Future<List<NativeSourceInfo>> configureSpotify({
    bool? enabled,
    String? clientId,
    String? clientSecret,
    bool clearCredentials = false,
  }) async {
    final data = await _send('PUT', '/api/sources/spotify', {
      if (enabled != null) 'enabled': enabled,
      if (clientId != null) 'client_id': clientId,
      if (clientSecret != null) 'client_secret': clientSecret,
      if (clearCredentials) 'clear_credentials': true,
    });
    final list = (data['native_sources'] as List? ?? const [])
        .map((e) => NativeSourceInfo.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    return list;
  }

  Future<List<NativeSourceInfo>> setNativeSourceEnabled(String id, bool enabled) async {
    final data = await _send(
      'PATCH',
      '/api/sources/native/${Uri.encodeComponent(id)}',
      {'enabled': enabled},
    );
    final list = (data['native_sources'] as List? ?? const [])
        .map((e) => NativeSourceInfo.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    return list;
  }

  Future<bool> health() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/api/health');
      return res.data?['ok'] == true;
    } on DioException {
      return false;
    }
  }

  List<Track> _listTracks(dynamic json) {
    if (json is! List) return const [];
    return json.whereType<Map>().map((e) => Track.fromJson(e.cast<String, dynamic>())).toList();
  }
}
