// language: Dart, file: lib/core/models.dart, target: mobile-first (Android/iOS) + desktop, runtime: resong app
// DTOs espelhados do backend (backend/src/types.ts) — JSON direto, sem código morto.

class Track {
  const Track({
    required this.id,
    required this.source,
    required this.title,
    this.artists = const [],
    this.album,
    this.artwork,
    this.durationMs,
    this.explicit = false,
    this.extra = const {},
  });

  final String id;
  final String source;
  final String title;
  final List<String> artists;
  final String? album;
  final String? artwork;
  final int? durationMs;
  final bool explicit;
  final Map<String, dynamic> extra;

  factory Track.fromJson(Map<String, dynamic> json) => Track(
        id: json['id'] as String,
        source: json['source'] as String? ?? 'ytmusic',
        title: json['title'] as String? ?? '',
        artists: (json['artists'] as List?)?.whereType<String>().toList() ?? const [],
        album: json['album'] as String?,
        artwork: json['artwork'] as String?,
        durationMs: (json['duration_ms'] as num?)?.toInt(),
        explicit: json['explicit'] as bool? ?? false,
        extra: (json['extra'] as Map?)?.cast<String, dynamic>() ?? const {},
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'source': source,
        'title': title,
        'artists': artists,
        if (album != null) 'album': album,
        'artwork': artwork,
        'duration_ms': durationMs,
        'explicit': explicit,
        'extra': extra,
      };

  String get artistLine => artists.isEmpty ? 'Desconhecido' : artists.join(', ');
}

class AlbumRef {
  const AlbumRef({
    required this.id,
    required this.source,
    required this.title,
    this.artists = const [],
    this.artwork,
    this.year,
    this.trackCount,
  });

  final String id;
  final String source;
  final String title;
  final List<String> artists;
  final String? artwork;
  final String? year;
  final int? trackCount;

  factory AlbumRef.fromJson(Map<String, dynamic> json) => AlbumRef(
        id: json['id'] as String,
        source: json['source'] as String? ?? 'ytmusic',
        title: json['title'] as String? ?? '',
        artists: (json['artists'] as List?)?.whereType<String>().toList() ?? const [],
        artwork: json['artwork'] as String?,
        year: json['year'] as String?,
        trackCount: (json['track_count'] as num?)?.toInt(),
      );
}

class ArtistRef {
  const ArtistRef({
    required this.id,
    required this.source,
    required this.name,
    this.artwork,
    this.subscribers,
  });

  final String id;
  final String source;
  final String name;
  final String? artwork;
  final String? subscribers;

  factory ArtistRef.fromJson(Map<String, dynamic> json) => ArtistRef(
        id: json['id'] as String,
        source: json['source'] as String? ?? 'ytmusic',
        name: json['name'] as String? ?? '',
        artwork: json['artwork'] as String?,
        subscribers: json['subscribers'] as String?,
      );
}

class PlaylistRef {
  const PlaylistRef({
    required this.id,
    required this.source,
    required this.title,
    this.owner,
    this.artwork,
    this.trackCount,
    this.description,
  });

  final String id;
  final String source;
  final String title;
  final String? owner;
  final String? artwork;
  final int? trackCount;
  final String? description;

  factory PlaylistRef.fromJson(Map<String, dynamic> json) => PlaylistRef(
        id: json['id'] as String,
        source: json['source'] as String? ?? 'ytmusic',
        title: json['title'] as String? ?? '',
        owner: json['owner'] as String?,
        artwork: json['artwork'] as String?,
        trackCount: (json['track_count'] as num?)?.toInt(),
        description: json['description'] as String?,
      );
}

class Section {
  const Section({required this.title, this.tracks = const [], this.albums = const [], this.artists = const [], this.playlists = const []});

  final String title;
  final List<Track> tracks;
  final List<AlbumRef> albums;
  final List<ArtistRef> artists;
  final List<PlaylistRef> playlists;

  factory Section.fromJson(Map<String, dynamic> json) => Section(
        title: json['title'] as String? ?? '',
        tracks: _list(json['tracks'], Track.fromJson),
        albums: _list(json['albums'], AlbumRef.fromJson),
        artists: _list(json['artists'], ArtistRef.fromJson),
        playlists: _list(json['playlists'], PlaylistRef.fromJson),
      );

  bool get isEmpty => tracks.isEmpty && albums.isEmpty && artists.isEmpty && playlists.isEmpty;
}

class HomeFeed {
  const HomeFeed({this.sections = const [], this.recent = const [], this.playlists = const []});

  final List<Section> sections;
  final List<Track> recent;
  final List<PlaylistRef> playlists;

  factory HomeFeed.fromJson(Map<String, dynamic> json) => HomeFeed(
        sections: _list(json['sections'], Section.fromJson),
        recent: _list(json['recent_tracks'], Track.fromJson),
        playlists: _list(json['playlists'], PlaylistRef.fromJson),
      );
}

class SearchResults {
  const SearchResults({this.tracks = const [], this.albums = const [], this.artists = const [], this.playlists = const []});

  final List<Track> tracks;
  final List<AlbumRef> albums;
  final List<ArtistRef> artists;
  final List<PlaylistRef> playlists;

  bool get isEmpty => tracks.isEmpty && albums.isEmpty && artists.isEmpty && playlists.isEmpty;

  factory SearchResults.fromJson(Map<String, dynamic> json) => SearchResults(
        tracks: _list(json['tracks'], Track.fromJson),
        albums: _list(json['albums'], AlbumRef.fromJson),
        artists: _list(json['artists'], ArtistRef.fromJson),
        playlists: _list(json['playlists'], PlaylistRef.fromJson),
      );
}

class PlaylistDetail {
  const PlaylistDetail({required this.ref, this.tracks = const []});
  final PlaylistRef ref;
  final List<Track> tracks;

  factory PlaylistDetail.fromJson(Map<String, dynamic> json) => PlaylistDetail(
        ref: PlaylistRef.fromJson((json['playlist'] as Map).cast<String, dynamic>()),
        tracks: _list(json['tracks'], Track.fromJson),
      );
}

class AlbumDetail {
  const AlbumDetail({required this.ref, this.tracks = const []});
  final AlbumRef ref;
  final List<Track> tracks;

  factory AlbumDetail.fromJson(Map<String, dynamic> json) => AlbumDetail(
        ref: AlbumRef.fromJson((json['album'] as Map).cast<String, dynamic>()),
        tracks: _list(json['tracks'], Track.fromJson),
      );
}

class ArtistDetail {
  const ArtistDetail({
    required this.ref,
    this.sections = const [],
    this.topTracks = const [],
    this.allTracks = const [],
  });
  final ArtistRef ref;
  final List<Section> sections;
  final List<Track> topTracks;
  final List<Track> allTracks;

  factory ArtistDetail.fromJson(Map<String, dynamic> json) {
    final top = _list(json['top_tracks'], Track.fromJson);
    final all = _list(json['all_tracks'], Track.fromJson);
    return ArtistDetail(
      ref: ArtistRef.fromJson((json['artist'] as Map).cast<String, dynamic>()),
      sections: _list(json['sections'], Section.fromJson),
      topTracks: top,
      allTracks: all.isNotEmpty ? all : top,
    );
  }
}

class LyricWordToken {
  const LyricWordToken({
    required this.atMs,
    required this.durMs,
    required this.text,
    this.isBackground = false,
  });

  final int atMs;
  final int durMs;
  final String text;
  final bool isBackground;

  factory LyricWordToken.fromJson(Map<String, dynamic> json) => LyricWordToken(
        atMs: (json['at_ms'] as num?)?.toInt() ?? 0,
        durMs: (json['dur_ms'] as num?)?.toInt() ?? 250,
        text: json['text'] as String? ?? '',
        isBackground: json['bg'] as bool? ?? false,
      );
}

class LyricRichLine {
  const LyricRichLine({
    required this.atMs,
    this.durMs,
    required this.text,
    this.leadText,
    this.bgText,
    this.isBackground = false,
    this.romanized,
    this.words = const [],
  });

  final int atMs;
  final int? durMs;
  final String text;
  final String? leadText;
  final String? bgText;
  final bool isBackground;
  final String? romanized;
  final List<LyricWordToken> words;

  factory LyricRichLine.fromJson(Map<String, dynamic> json) => LyricRichLine(
        atMs: (json['at_ms'] as num?)?.toInt() ?? 0,
        durMs: (json['dur_ms'] as num?)?.toInt(),
        text: json['text'] as String? ?? '',
        leadText: json['lead_text'] as String?,
        bgText: json['bg_text'] as String?,
        isBackground: json['is_background'] as bool? ?? false,
        romanized: json['romanized'] as String?,
        words: _list(json['words'], LyricWordToken.fromJson),
      );
}

class Lyrics {
  const Lyrics({
    this.plain,
    this.synced,
    this.source,
    this.wordSynced = false,
    this.hasKaraoke = false,
    this.hasBackground = false,
    this.romanizedSynced,
    this.lines = const [],
  });

  final String? plain;
  final String? synced;
  final String? source;
  final bool wordSynced;
  final bool hasKaraoke;
  final bool hasBackground;
  final String? romanizedSynced;
  final List<LyricRichLine> lines;

  bool get isEmpty => (plain ?? '').trim().isEmpty && (synced ?? '').trim().isEmpty;

  factory Lyrics.fromJson(Map<String, dynamic> json) => Lyrics(
        plain: json['plain'] as String?,
        synced: json['synced'] as String?,
        source: json['source'] as String?,
        wordSynced: json['word_synced'] as bool? ?? false,
        hasKaraoke: json['has_karaoke'] as bool? ?? (json['word_synced'] as bool? ?? false),
        hasBackground: json['has_background'] as bool? ?? false,
        romanizedSynced: json['romanized_synced'] as String?,
        lines: _list(json['lines'], LyricRichLine.fromJson),
      );
}

class DownloadRecord {
  const DownloadRecord({
    required this.trackId,
    required this.track,
    required this.status,
    this.progress = 0,
    this.localPath,
    this.displayPath,
    this.error,
    this.fileSize,
    required this.createdAt,
  });

  final String trackId;
  final Track track;
  final String status;
  final double progress;
  final String? localPath;
  final String? displayPath;
  final String? error;
  final int? fileSize;
  final int createdAt;

  bool get isDone => status == 'done';
  bool get hasPlayableLocal => isDone && (localPath ?? '').isNotEmpty;

  DownloadRecord copyWith({
    Track? track,
    String? status,
    double? progress,
    String? localPath,
    String? displayPath,
    String? error,
    bool clearError = false,
    int? fileSize,
  }) =>
      DownloadRecord(
        trackId: trackId,
        track: track ?? this.track,
        status: status ?? this.status,
        progress: progress ?? this.progress,
        localPath: localPath ?? this.localPath,
        displayPath: displayPath ?? this.displayPath,
        error: clearError ? null : (error ?? this.error),
        fileSize: fileSize ?? this.fileSize,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'track_id': trackId,
        'track': track.toJson(),
        'status': status,
        'progress': progress,
        if (localPath != null) 'local_path': localPath,
        if (displayPath != null) 'display_path': displayPath,
        if (error != null) 'error': error,
        if (fileSize != null) 'file_size': fileSize,
        'created_at': createdAt,
      };

  factory DownloadRecord.fromJson(Map<String, dynamic> json) => DownloadRecord(
        trackId: json['track_id'] as String,
        track: Track.fromJson((json['track'] as Map).cast<String, dynamic>()),
        status: json['status'] as String? ?? 'queued',
        progress: (json['progress'] as num?)?.toDouble() ?? (json['status'] == 'done' ? 1.0 : 0.0),
        localPath: json['local_path'] as String?,
        displayPath: json['display_path'] as String?,
        error: json['error'] as String?,
        fileSize: (json['file_size'] as num?)?.toInt(),
        createdAt: (json['created_at'] as num?)?.toInt() ?? 0,
      );
}

class PlaylistRecord {
  const PlaylistRecord({
    required this.id,
    required this.name,
    this.description = '',
    this.artwork,
    this.trackCount = 0,
    this.tracks,
  });

  final String id;
  final String name;
  final String description;
  final String? artwork;
  final int trackCount;
  final List<Track>? tracks;

  factory PlaylistRecord.fromJson(Map<String, dynamic> json) => PlaylistRecord(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
        artwork: json['artwork'] as String?,
        trackCount: (json['track_count'] as num?)?.toInt() ?? 0,
        tracks: json['tracks'] is List ? _list(json['tracks'], Track.fromJson) : null,
      );
}

class AddonSource {
  const AddonSource({
    required this.id,
    required this.baseUrl,
    required this.label,
    required this.ordem,
    required this.enabled,
    required this.allowDownloads,
    this.qualityOptions = const [],
    this.lastCheckedAt,
    this.lastStatus = 'ok',
  });

  final String id;
  final String baseUrl;
  final String label;
  final int ordem;
  final bool enabled;
  final bool allowDownloads;
  final List<String> qualityOptions;
  final int? lastCheckedAt;
  final String lastStatus;

  AddonSource copyWith({
    String? label,
    int? ordem,
    bool? enabled,
    bool? allowDownloads,
    List<String>? qualityOptions,
    int? lastCheckedAt,
    String? lastStatus,
  }) =>
      AddonSource(
        id: id,
        baseUrl: baseUrl,
        label: label ?? this.label,
        ordem: ordem ?? this.ordem,
        enabled: enabled ?? this.enabled,
        allowDownloads: allowDownloads ?? this.allowDownloads,
        qualityOptions: qualityOptions ?? this.qualityOptions,
        lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
        lastStatus: lastStatus ?? this.lastStatus,
      );

  factory AddonSource.fromJson(Map<String, dynamic> json) => AddonSource(
        id: json['id'] as String,
        baseUrl: json['base_url'] as String? ?? '',
        label: json['label'] as String? ?? '',
        ordem: (json['ordem'] as num?)?.toInt() ?? 0,
        enabled: json['enabled'] as bool? ?? true,
        allowDownloads: json['allow_downloads'] as bool? ?? true,
        qualityOptions: (json['quality_options'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        lastCheckedAt: (json['last_checked_at'] as num?)?.toInt(),
        lastStatus: json['last_status'] as String? ?? 'ok',
      );
}

class NativeSourceInfo {
  const NativeSourceInfo({
    required this.id,
    required this.label,
    this.fixed = true,
    this.configured = true,
    this.enabled = true,
    this.configurable = false,
    this.toggleable = false,
    this.clientIdPreview,
  });
  final String id;
  final String label;
  final bool fixed;
  final bool configured;
  final bool enabled;
  final bool configurable;
  final bool toggleable;
  final String? clientIdPreview;

  factory NativeSourceInfo.fromJson(Map<String, dynamic> json) => NativeSourceInfo(
        id: json['id'] as String? ?? '',
        label: json['label'] as String? ?? '',
        fixed: json['fixed'] as bool? ?? true,
        configured: json['configured'] as bool? ?? true,
        enabled: json['enabled'] as bool? ?? true,
        configurable: json['configurable'] as bool? ?? (json['id'] == 'spotify'),
        toggleable: json['toggleable'] as bool? ??
            (json['id'] == 'audius' || json['id'] == 'archive'),
        clientIdPreview: json['client_id_preview'] as String?,
      );
}

class SourcesSnapshot {
  const SourcesSnapshot({
    this.sources = const [],
    this.nativeSources = const [
      NativeSourceInfo(id: 'ytmusic', label: 'YouTube Music'),
      NativeSourceInfo(id: 'soundcloud', label: 'SoundCloud'),
      NativeSourceInfo(
        id: 'spotify',
        label: 'Spotify',
        configured: false,
        enabled: true,
        configurable: true,
      ),
      NativeSourceInfo(id: 'audius', label: 'Audius', toggleable: true),
      NativeSourceInfo(id: 'archive', label: 'Internet Archive', toggleable: true),
    ],
  });

  final List<AddonSource> sources;
  final List<NativeSourceInfo> nativeSources;

  SourcesSnapshot copyWith({
    List<AddonSource>? sources,
    List<NativeSourceInfo>? nativeSources,
  }) =>
      SourcesSnapshot(
        sources: sources ?? this.sources,
        nativeSources: nativeSources ?? this.nativeSources,
      );

  factory SourcesSnapshot.fromJson(Map<String, dynamic> json) => SourcesSnapshot(
        sources: _list(json['sources'], AddonSource.fromJson),
        nativeSources: json['native_sources'] is List
            ? _list(json['native_sources'], NativeSourceInfo.fromJson)
            : const [
                NativeSourceInfo(id: 'ytmusic', label: 'YouTube Music'),
                NativeSourceInfo(id: 'soundcloud', label: 'SoundCloud'),
                NativeSourceInfo(
                  id: 'spotify',
                  label: 'Spotify',
                  configured: false,
                  enabled: true,
                  configurable: true,
                ),
                NativeSourceInfo(id: 'audius', label: 'Audius', toggleable: true),
                NativeSourceInfo(id: 'archive', label: 'Internet Archive', toggleable: true),
              ],
      );
}

class TranslatedLyrics {
  const TranslatedLyrics({
    required this.target,
    required this.lines,
    this.romanized = const [],
    this.sourceLang,
  });
  final String target;
  final List<String> lines;
  final List<String> romanized;
  final String? sourceLang;

  factory TranslatedLyrics.fromJson(Map<String, dynamic> json) => TranslatedLyrics(
        target: json['target'] as String? ?? 'pt',
        lines: (json['lines'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        romanized: (json['romanized'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        sourceLang: json['source_lang'] as String?,
      );
}

List<T> _list<T>(dynamic json, T Function(Map<String, dynamic>) from) {
  if (json is! List) return const [];
  return json.whereType<Map>().map((e) => from(e.cast<String, dynamic>())).toList();
}
