// language: Dart, file: lib/engine/stream_resolver.dart, target: mobile + desktop, runtime: resong engine
import 'addon_client.dart';
import 'archive_client.dart';
import 'audius_client.dart';
import 'engine_utils.dart';
import 'local_store.dart';
import 'soundcloud_client.dart';
import 'spotify_client.dart';
import 'ytmusic_client.dart';

class ResolveException implements Exception {
  ResolveException(this.message, {this.status = 502, String? code})
      : code = code ??
            (status == 400
                ? 'invalid'
                : (status == 401 || status == 403 || status == 429)
                    ? 'gated'
                    : 'unavailable');

  final String message;
  final int status;
  final String code;

  @override
  String toString() => message;
}

class StreamResolver {
  StreamResolver._();
  static final StreamResolver instance = StreamResolver._();

  ({String source, String rest}) _parseId(String id) {
    if (id.startsWith('addon:')) return (source: 'addon', rest: id);
    if (id.startsWith('yt:')) return (source: 'yt', rest: id.substring(3));
    if (id.startsWith('sc:')) return (source: 'sc', rest: id.substring(3));
    if (id.startsWith('sp:')) return (source: 'sp', rest: id.substring(3));
    if (id.startsWith('au:')) return (source: 'au', rest: id.substring(3));
    if (id.startsWith('ia:')) return (source: 'ia', rest: id.substring(3));
    throw ResolveException('ID de faixa desconhecido: $id', status: 400);
  }

  Future<ResolvedStreamResult?> _fallbackSoundCloud(
    String? title,
    List<String> artists, {
    bool progressiveOnly = false,
  }) async {
    if (title == null || title.trim().isEmpty) return null;
    final query = [title, if (artists.isNotEmpty) artists.first].join(' ').trim();
    if (query.isEmpty) return null;
    final hits = await SoundCloudClient.instance.search(query, limit: 5);
    for (final cand in hits) {
      final id = cand['id'] as String? ?? '';
      if (!id.startsWith('sc:')) continue;
      final sc = await SoundCloudClient.instance.resolveStream(id.substring(3), progressiveOnly: progressiveOnly);
      if (sc != null) return sc;
    }
    return null;
  }

  Future<ResolvedStreamResult> resolveStream(
    String id, {
    String? title,
    List<String> artists = const [],
    int? durationMs,
    String? isrc,
    String? album,
    bool progressive = false,
    bool forDownload = false,
  }) async {
    final parsed = _parseId(id);
    final needDownload = forDownload || progressive;

    if (parsed.source == 'addon') {
      final addon = AddonClient.instance.parseAddonTrackId(id);
      if (addon == null) throw ResolveException('ID de addon inválido: $id', status: 400);
      final src = LocalStore.instance.getAddonSource(addon.configId);
      final directAllowed = !needDownload || (src?['allow_downloads'] != false);
      if (directAllowed) {
        final direct = await AddonClient.instance.resolveStream(addon.configId, addon.remoteId, durationMs: durationMs);
        if (direct != null && (!progressive || direct.kind == 'direct')) return direct;
      }

      final crossAddon = await AddonClient.instance.fallbackStream(
        title: title,
        artists: artists,
        durationMs: durationMs,
        excludeSourceId: addon.configId,
        requireDownloadsAllowed: needDownload,
      );
      if (crossAddon != null && (!progressive || crossAddon.kind == 'direct')) return crossAddon;

      if (title != null && title.isNotEmpty) {
        final matched = await YtMusicClient.instance.matchTrack(title, artists, durationMs: durationMs);
        final matchedId = matched?['id'] as String?;
        if (matchedId != null && matchedId.startsWith('yt:')) {
          return YtMusicClient.instance.resolveStream(
            matchedId.substring(3),
            title: title,
            artists: artists,
            progressive: progressive,
          );
        }
        final sc = await _fallbackSoundCloud(title, artists, progressiveOnly: progressive);
        if (sc != null) return sc;
      }
      throw ResolveException('Stream do addon indisponível');
    }

    if (parsed.source == 'au') {
      final au = await AudiusClient.instance.resolveStream(parsed.rest);
      if (au != null) return au;
      throw ResolveException('Stream do Audius indisponível');
    }

    if (parsed.source == 'ia') {
      final ia = await ArchiveClient.instance.resolveStream(parsed.rest);
      if (ia != null) return ia;
      throw ResolveException('Áudio do Internet Archive indisponível');
    }

    if (parsed.source == 'sc') {
      final sc = await SoundCloudClient.instance.resolveStream(parsed.rest, progressiveOnly: progressive);
      if (sc != null) return sc;
      if (progressive && title != null && title.isNotEmpty) {
        final matched = await YtMusicClient.instance.matchTrack(title, artists, durationMs: durationMs);
        final mId = matched?['id'] as String?;
        if (mId != null && mId.startsWith('yt:')) {
          return YtMusicClient.instance.resolveStream(
            mId.substring(3),
            title: title,
            artists: artists,
            progressive: progressive,
          );
        }
      }
      throw ResolveException('Stream do SoundCloud indisponível');
    }

    if (parsed.source == 'yt') {
      return YtMusicClient.instance.resolveStream(
        parsed.rest,
        title: title,
        artists: artists,
        progressive: progressive,
      );
    }

    // sp:* — match persistente com ISRC/catálogo -> YT Music -> SoundCloud -> Audius
    final cachedMatch = LocalStore.instance.getMatch(id);
    if (cachedMatch != null) {
      if (cachedMatch.startsWith('yt:')) {
        return YtMusicClient.instance.resolveStream(cachedMatch.substring(3), title: title, artists: artists, progressive: progressive);
      }
      if (cachedMatch.startsWith('sc:')) {
        final sc = await SoundCloudClient.instance.resolveStream(cachedMatch.substring(3), progressiveOnly: progressive);
        if (sc != null) return sc;
      }
      if (cachedMatch.startsWith('au:')) {
        final au = await AudiusClient.instance.resolveStream(cachedMatch.substring(3));
        if (au != null) return au;
      }
    }

    var effectiveTitle = title;
    var effectiveArtists = artists;
    var effectiveDur = durationMs;
    var effectiveIsrc = isrc;
    var effectiveAlbum = album;

    if ((effectiveTitle == null || effectiveTitle.isEmpty || effectiveIsrc == null) && id.startsWith('sp:track:')) {
      final fetched = await SpotifyClient.instance.track(id.substring(9));
      if (fetched != null) {
        effectiveTitle = (effectiveTitle != null && effectiveTitle.isNotEmpty) ? effectiveTitle : fetched['title'] as String?;
        effectiveArtists = effectiveArtists.isNotEmpty ? effectiveArtists : ((fetched['artists'] as List?)?.cast<String>() ?? const []);
        effectiveDur ??= (fetched['duration_ms'] as num?)?.toInt();
        effectiveIsrc ??= (fetched['extra'] as Map?)?['isrc'] as String?;
        effectiveAlbum ??= fetched['album'] as String?;
      }
    }

    if (effectiveTitle == null || effectiveTitle.trim().isEmpty) {
      throw ResolveException('Faixa do Spotify requer metadados para resolver o áudio', status: 400);
    }

    final matched = await YtMusicClient.instance.matchTrack(
      effectiveTitle,
      effectiveArtists,
      durationMs: effectiveDur,
      isrc: effectiveIsrc,
      albumName: effectiveAlbum,
    );
    final mId = matched?['id'] as String?;
    if (mId != null) {
      await LocalStore.instance.saveMatch(id, mId);
      if (mId.startsWith('yt:')) {
        return YtMusicClient.instance.resolveStream(
          mId.substring(3),
          title: effectiveTitle,
          artists: effectiveArtists,
          progressive: progressive,
        );
      }
      if (mId.startsWith('sc:')) {
        final sc = await SoundCloudClient.instance.resolveStream(mId.substring(3), progressiveOnly: progressive);
        if (sc != null) return sc;
      }
    }

    final scHits = await SoundCloudClient.instance.search(
      [effectiveTitle, if (effectiveArtists.isNotEmpty) effectiveArtists.first].join(' '),
      limit: 5,
    );
    for (final cand in scHits) {
      final cid = cand['id'] as String? ?? '';
      if (!cid.startsWith('sc:')) continue;
      final sc = await SoundCloudClient.instance.resolveStream(cid.substring(3), progressiveOnly: progressive);
      if (sc != null) {
        await LocalStore.instance.saveMatch(id, cid);
        return sc;
      }
    }

    final auHits = await AudiusClient.instance.search(
      [effectiveTitle, if (effectiveArtists.isNotEmpty) effectiveArtists.first].join(' '),
      limit: 3,
    );
    for (final cand in auHits) {
      final cid = cand['id'] as String? ?? '';
      if (!cid.startsWith('au:')) continue;
      final au = await AudiusClient.instance.resolveStream(cid.substring(3));
      if (au != null) {
        await LocalStore.instance.saveMatch(id, cid);
        return au;
      }
    }

    throw ResolveException('Não foi possível resolver áudio para esta faixa', status: 504);
  }
}
