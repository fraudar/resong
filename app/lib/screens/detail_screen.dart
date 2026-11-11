// language: Dart, file: lib/screens/detail_screen.dart, target: mobile-first + desktop, runtime: resong app
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons_flutter/solar_icons_flutter.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../state/library.dart';
import '../state/providers.dart';
import '../widgets/collection_hero_layout.dart';
import '../widgets/glass.dart';
import '../widgets/sections.dart';
import '../widgets/track_tile.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

final _albumProvider = FutureProvider.family<AlbumDetail, String>((ref, id) => Api.instance.album(id));
final _playlistRefProvider = FutureProvider.family<PlaylistDetail, String>((ref, id) => Api.instance.playlistRef(id));
final _artistProvider = FutureProvider.family<ArtistDetail, String>((ref, id) => Api.instance.artist(id));

abstract final class DetailScreen {
  static Widget album(String id, {AlbumRef? initialRef}) => _AlbumScreen(id: id, initialRef: initialRef);
  static Widget playlistRef(String id, {PlaylistRef? initialRef}) => _PlaylistScreen(id: id, initialRef: initialRef);
  static Widget artist(String id, {ArtistRef? initialRef}) => _ArtistScreen(id: id, initialRef: initialRef);
  static Widget searchFor(String query) => SearchScreen(initialQuery: query);

  static String? artistIdForTrack(Track track, {String? artistName}) {
    final targetName = (artistName ?? (track.artists.isNotEmpty ? track.artists.first : '')).trim();
    final isPrimary = track.artists.isEmpty || artistName == null || targetName == track.artists.first.trim();
    if (isPrimary) {
      final ch = (track.extra['channel_id'] as String?)?.trim();
      if (ch != null && ch.isNotEmpty) return 'ytar:$ch';
      final spArtist = (track.extra['artist_id'] as String?)?.trim();
      if (spArtist != null && spArtist.isNotEmpty) return 'sp:artist:$spArtist';
    }
    if (targetName.isEmpty) return null;
    return 'name:$targetName';
  }

  static Widget? artistForTrack(Track track, {String? artistName}) {
    final id = artistIdForTrack(track, artistName: artistName);
    if (id == null) return null;
    final display = (artistName ?? (track.artists.isNotEmpty ? track.artists.first : '')).trim();
    return _ArtistScreen(
      id: id,
      initialRef: display.isEmpty
          ? null
          : ArtistRef(id: id, source: track.source, name: display, artwork: null),
    );
  }

  static Future<void> openArtistForTrack(
    BuildContext context,
    Track track, {
    String? artistName,
    NavigatorState? navigator,
  }) async {
    final screen = artistForTrack(track, artistName: artistName);
    if (screen == null) return;
    final nav = navigator ?? Navigator.of(context);
    await nav.push(MaterialPageRoute<void>(builder: (_) => screen));
  }
}

// ------------------------------------------------------------------ álbum

class _AlbumScreen extends ConsumerWidget {
  const _AlbumScreen({required this.id, this.initialRef});
  final String id;
  final AlbumRef? initialRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(_albumProvider(id));
    final playing = ref.watch(isPlayingProvider);
    return data.when(
      loading: () {
        if (initialRef == null) return const _LoadingDetailScaffold();
        final r = initialRef!;
        final palette = watchCollectionPalette(ref, r.artwork);
        return CollectionHeroLayout(
          palette: palette,
          heroFlightTag: 'collection:$id',
          artworkUrl: r.artwork,
          fallbackIcon: SolarIconsBold.album,
          title: r.title,
          subtitle: r.artists.isNotEmpty ? r.artists.join(', ') : null,
          meta: r.year,
          isPlayingWaves: playing,
          isCollectionPlaying: false,
          onPlayPause: null,
          trailingIcon: SolarIconsBold.downloadMinimalistic,
          slivers: const [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          ],
        );
      },
      error: (e, _) => _ErrorDetailScaffold(message: 'Não deu pra carregar o álbum.\n$e'),
      data: (detail) {
        final tracks = detail.tracks;
        final palette = watchCollectionPalette(ref, detail.ref.artwork);
        final currentTrack = ref.watch(currentTrackProvider);
        ref.watch(playerModeProvider);
        final handler = ref.watch(handlerProvider);
        final inThisList = currentTrack != null && tracks.any((t) => t.id == currentTrack.id);
        final downloads = ref.watch(downloadsProvider);
        final dlState = _collectionDlState(tracks, downloads);

        return CollectionHeroLayout(
          palette: palette,
          heroFlightTag: 'collection:$id',
          artworkUrl: detail.ref.artwork,
          fallbackIcon: SolarIconsBold.album,
          title: detail.ref.title,
          subtitle: detail.ref.artists.isNotEmpty ? detail.ref.artists.join(', ') : null,
          meta: [
            if (detail.ref.year != null && detail.ref.year!.isNotEmpty) detail.ref.year!,
            if (tracks.isNotEmpty) '${tracks.length} ${tracks.length == 1 ? 'faixa' : 'faixas'}',
          ].join(' • '),
          isPlayingWaves: playing,
          isCollectionPlaying: inThisList && playing,
          shuffleActive: handler.shuffle,
          onPlayPause: tracks.isEmpty
              ? null
              : () => _togglePlayCollection(ref, tracks, inThisList: inThisList, isPlaying: playing),
          onShuffle: tracks.isEmpty ? null : () => _playShuffled(ref, tracks),
          trailingIcon: dlState.allDownloaded ? SolarIconsBold.folderCheck : SolarIconsBold.downloadMinimalistic,
          trailingTooltip: dlState.downloadingAny
              ? 'Cancelar downloads (${(dlState.progress * 100).round()}%)'
              : (dlState.allDownloaded ? 'Disponível offline — Ver Downloads' : 'Baixar todas'),
          trailingActive: dlState.allDownloaded,
          trailingProgress: dlState.downloadingAny ? dlState.progress : null,
          onTrailingTap: tracks.isEmpty
              ? null
              : dlState.downloadingAny
                  ? () => _cancelDownloads(ref, tracks)
                  : dlState.allDownloaded
                      ? () => openDownloadsTab(context, ref)
                      : () => _downloadAll(context, ref, tracks),
          onMenuTap: () => _openCollectionMenu(
            context,
            ref,
            title: detail.ref.title,
            tracks: tracks,
            onDownloadAll: () => _downloadAll(context, ref, tracks),
          ),
          slivers: [
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => TrackTile(
                  track: tracks[i],
                  queue: tracks,
                  index: i,
                  number: i + 1,
                  showArtwork: false,
                ),
                childCount: tracks.length,
              ),
            ),
          ],
        );
      },
    );
  }
}

// --------------------------------------------------------------- playlist

class _PlaylistScreen extends ConsumerWidget {
  const _PlaylistScreen({required this.id, this.initialRef});
  final String id;
  final PlaylistRef? initialRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(_playlistRefProvider(id));
    final playing = ref.watch(isPlayingProvider);
    return data.when(
      loading: () {
        if (initialRef == null) return const _LoadingDetailScaffold();
        final r = initialRef!;
        final palette = watchCollectionPalette(ref, r.artwork);
        return CollectionHeroLayout(
          palette: palette,
          heroFlightTag: 'collection:$id',
          artworkUrl: r.artwork,
          fallbackIcon: SolarIconsBold.playlist,
          title: r.title,
          subtitle: r.owner != null && r.owner != 'Playlist' ? r.owner : null,
          isPlayingWaves: playing,
          isCollectionPlaying: false,
          onPlayPause: null,
          trailingIcon: SolarIconsBold.downloadMinimalistic,
          slivers: const [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          ],
        );
      },
      error: (e, _) => _ErrorDetailScaffold(message: 'Não deu pra carregar a playlist.\n$e'),
      data: (detail) {
        final tracks = detail.tracks;
        final palette = watchCollectionPalette(ref, detail.ref.artwork);
        final currentTrack = ref.watch(currentTrackProvider);
        ref.watch(playerModeProvider);
        final handler = ref.watch(handlerProvider);
        final inThisList = currentTrack != null && tracks.any((t) => t.id == currentTrack.id);
        final downloads = ref.watch(downloadsProvider);
        final dlState = _collectionDlState(tracks, downloads);

        return CollectionHeroLayout(
          palette: palette,
          heroFlightTag: 'collection:$id',
          artworkUrl: detail.ref.artwork,
          fallbackIcon: SolarIconsBold.playlist,
          title: detail.ref.title,
          subtitle: detail.ref.owner != null && detail.ref.owner != 'Playlist' ? detail.ref.owner : null,
          meta: [
            '${tracks.length} ${tracks.length == 1 ? 'faixa' : 'faixas'}',
            if (detail.ref.trackCount != null && detail.ref.trackCount! > tracks.length)
              '${detail.ref.trackCount} no total',
          ].join(' • '),
          isPlayingWaves: playing,
          isCollectionPlaying: inThisList && playing,
          shuffleActive: handler.shuffle,
          onPlayPause: tracks.isEmpty
              ? null
              : () => _togglePlayCollection(ref, tracks, inThisList: inThisList, isPlaying: playing),
          onShuffle: tracks.isEmpty ? null : () => _playShuffled(ref, tracks),
          trailingIcon: dlState.allDownloaded ? SolarIconsBold.folderCheck : SolarIconsBold.downloadMinimalistic,
          trailingTooltip: dlState.downloadingAny
              ? 'Cancelar downloads (${(dlState.progress * 100).round()}%)'
              : (dlState.allDownloaded ? 'Disponível offline — Ver Downloads' : 'Baixar todas'),
          trailingActive: dlState.allDownloaded,
          trailingProgress: dlState.downloadingAny ? dlState.progress : null,
          onTrailingTap: tracks.isEmpty
              ? null
              : dlState.downloadingAny
                  ? () => _cancelDownloads(ref, tracks)
                  : dlState.allDownloaded
                      ? () => openDownloadsTab(context, ref)
                      : () => _downloadAll(context, ref, tracks),
          onMenuTap: () => _openCollectionMenu(
            context,
            ref,
            title: detail.ref.title,
            tracks: tracks,
            onDownloadAll: () => _downloadAll(context, ref, tracks),
          ),
          slivers: [
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => TrackTile(
                  track: tracks[i],
                  queue: tracks,
                  index: i,
                  number: i + 1,
                  showArtwork: false,
                ),
                childCount: tracks.length,
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------- artista

enum _ArtistTab { overview, songs, albums, singles, related }

class _ArtistScreen extends ConsumerStatefulWidget {
  const _ArtistScreen({required this.id, this.initialRef});
  final String id;
  final ArtistRef? initialRef;

  @override
  ConsumerState<_ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends ConsumerState<_ArtistScreen> {
  _ArtistTab _tab = _ArtistTab.overview;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(_artistProvider(widget.id));
    final playing = ref.watch(isPlayingProvider);
    final colors = context.colors;

    return data.when(
      loading: () {
        if (widget.initialRef == null) return const _LoadingDetailScaffold();
        final r = widget.initialRef!;
        final palette = watchCollectionPalette(ref, r.artwork);
        return CollectionHeroLayout(
          palette: palette,
          heroFlightTag: 'collection:${widget.id}',
          artworkUrl: r.artwork,
          fallbackIcon: SolarIconsBold.user,
          title: r.name,
          subtitle: 'Artista',
          meta: r.subscribers != null ? '${r.subscribers} inscritos' : null,
          isPlayingWaves: playing,
          isCollectionPlaying: false,
          onPlayPause: null,
          trailingIcon: SolarIconsLinear.magnifier,
          slivers: const [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
          ],
        );
      },
      error: (e, _) => _ErrorDetailScaffold(message: 'Não deu pra carregar o artista.\n$e'),
      data: (detail) {
        final palette = watchCollectionPalette(ref, detail.ref.artwork);
        final currentTrack = ref.watch(currentTrackProvider);
        ref.watch(playerModeProvider);
        final handler = ref.watch(handlerProvider);

        // Consolida faixas, álbuns, singles, playlists e artistas parecidos sem duplicatas
        final seenSongIds = <String>{};
        final allSongs = <Track>[];
        for (final t in [...detail.allTracks, ...detail.topTracks, for (final s in detail.sections) ...s.tracks]) {
          if (seenSongIds.add(t.id)) allSongs.add(t);
        }
        final topPreview = (detail.topTracks.isNotEmpty ? detail.topTracks : allSongs).take(5).toList();

        final albums = <AlbumRef>[];
        final singles = <AlbumRef>[];
        final seenAlbumIds = <String>{};
        final playlists = <PlaylistRef>[];
        final seenPlaylistIds = <String>{};
        final relatedArtists = <ArtistRef>[];
        final seenArtistIds = <String>{detail.ref.id};

        for (final sec in detail.sections) {
          final tLower = sec.title.toLowerCase();
          final isSingleSec = tLower.contains('single') || tLower.contains('ep');
          for (final a in sec.albums) {
            if (!seenAlbumIds.add(a.id)) continue;
            if (isSingleSec) {
              singles.add(a);
            } else {
              albums.add(a);
            }
          }
          for (final p in sec.playlists) {
            if (seenPlaylistIds.add(p.id)) playlists.add(p);
          }
          for (final ar in sec.artists) {
            if (seenArtistIds.add(ar.id)) relatedArtists.add(ar);
          }
        }

        final playSource = allSongs.isNotEmpty ? allSongs : topPreview;
        final inThisList = currentTrack != null && playSource.any((t) => t.id == currentTrack.id);

        final availableTabs = <(_ArtistTab, String)>[
          (_ArtistTab.overview, 'Visão geral'),
          if (allSongs.isNotEmpty) (_ArtistTab.songs, 'Músicas (${allSongs.length})'),
          if (albums.isNotEmpty) (_ArtistTab.albums, 'Álbuns (${albums.length})'),
          if (singles.isNotEmpty) (_ArtistTab.singles, 'Singles (${singles.length})'),
          if (relatedArtists.isNotEmpty) (_ArtistTab.related, 'Parecidos (${relatedArtists.length})'),
        ];
        final activeTab = availableTabs.any((e) => e.$1 == _tab) ? _tab : _ArtistTab.overview;

        final metaParts = <String>[
          if (detail.ref.subscribers != null && detail.ref.subscribers!.trim().isNotEmpty)
            '${detail.ref.subscribers} inscritos',
          if (allSongs.isNotEmpty) '${allSongs.length} músicas',
          if (albums.isNotEmpty) '${albums.length} álbuns',
          if (singles.isNotEmpty) '${singles.length} singles',
        ];

        return CollectionHeroLayout(
          palette: palette,
          heroFlightTag: 'collection:${widget.id}',
          artworkUrl: detail.ref.artwork,
          fallbackIcon: SolarIconsBold.user,
          title: detail.ref.name,
          subtitle: 'Artista',
          meta: metaParts.isEmpty ? null : metaParts.join(' • '),
          isPlayingWaves: playing,
          isCollectionPlaying: inThisList && playing,
          shuffleActive: handler.shuffle,
          onPlayPause: playSource.isEmpty
              ? null
              : () => _togglePlayCollection(ref, playSource, inThisList: inThisList, isPlaying: playing),
          onShuffle: playSource.isEmpty ? null : () => _playShuffled(ref, playSource),
          trailingIcon: SolarIconsLinear.magnifier,
          trailingTooltip: 'Buscar ${detail.ref.name}',
          onTrailingTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => DetailScreen.searchFor(detail.ref.name)),
          ),
          onMenuTap: () => _openCollectionMenu(
            context,
            ref,
            title: detail.ref.name,
            tracks: playSource,
            onDownloadAll: playSource.isEmpty ? null : () => _downloadAll(context, ref, playSource),
          ),
          slivers: [
            if (availableTabs.length > 1)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (var i = 0; i < availableTabs.length; i++) ...[
                          if (i > 0) const SizedBox(width: 8),
                          _ArtistTabPill(
                            label: availableTabs[i].$2,
                            selected: activeTab == availableTabs[i].$1,
                            onTap: () => setState(() => _tab = availableTabs[i].$1),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),

            if (activeTab == _ArtistTab.overview) ...[
              if (topPreview.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 2, 16, 6),
                    child: Row(
                      children: [
                        Text('Mais tocadas', style: Theme.of(context).textTheme.titleLarge),
                        const Spacer(),
                        if (allSongs.length > topPreview.length)
                          TextButton(
                            onPressed: () => setState(() => _tab = _ArtistTab.songs),
                            child: Text(
                              'Ver todas (${allSongs.length})',
                              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: colors.textSecondary),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              if (topPreview.isNotEmpty)
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => TrackTile(
                      track: topPreview[i],
                      queue: allSongs.isNotEmpty ? allSongs : topPreview,
                      index: allSongs.indexWhere((t) => t.id == topPreview[i].id).clamp(0, math.max(0, allSongs.length - 1)),
                      number: i + 1,
                      showArtwork: true,
                    ),
                    childCount: topPreview.length,
                  ),
                ),
              if (albums.isNotEmpty)
                SliverToBoxAdapter(
                  child: MediaRail(
                    label: 'Álbuns',
                    children: [for (final a in albums) MediaCard(kind: MediaKind.album, album: a)],
                  ),
                ),
              if (singles.isNotEmpty)
                SliverToBoxAdapter(
                  child: MediaRail(
                    label: 'Singles e EPs',
                    children: [for (final s in singles) MediaCard(kind: MediaKind.album, album: s)],
                  ),
                ),
              if (playlists.isNotEmpty)
                SliverToBoxAdapter(
                  child: MediaRail(
                    label: 'Playlists e participações',
                    children: [for (final p in playlists) MediaCard(kind: MediaKind.playlist, playlist: p)],
                  ),
                ),
              if (relatedArtists.isNotEmpty)
                SliverToBoxAdapter(
                  child: MediaRail(
                    label: 'Fãs também ouvem',
                    children: [for (final r in relatedArtists) MediaCard(kind: MediaKind.artist, artist: r)],
                  ),
                ),
            ] else if (activeTab == _ArtistTab.songs) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 2, 16, 8),
                  child: Text(
                    'Todas as músicas (${allSongs.length})',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => TrackTile(
                    track: allSongs[i],
                    queue: allSongs,
                    index: i,
                    number: i + 1,
                    showArtwork: true,
                  ),
                  childCount: allSongs.length,
                ),
              ),
            ] else if (activeTab == _ArtistTab.albums) ...[
              SliverToBoxAdapter(
                child: _ArtistCardsGrid(
                  title: 'Álbuns (${albums.length})',
                  children: [for (final a in albums) MediaCard(kind: MediaKind.album, album: a)],
                ),
              ),
            ] else if (activeTab == _ArtistTab.singles) ...[
              SliverToBoxAdapter(
                child: _ArtistCardsGrid(
                  title: 'Singles e EPs (${singles.length})',
                  children: [for (final s in singles) MediaCard(kind: MediaKind.album, album: s)],
                ),
              ),
            ] else if (activeTab == _ArtistTab.related) ...[
              SliverToBoxAdapter(
                child: _ArtistCardsGrid(
                  title: 'Artistas semelhantes',
                  children: [for (final r in relatedArtists) MediaCard(kind: MediaKind.artist, artist: r)],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _ArtistTabPill extends StatelessWidget {
  const _ArtistTabPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final activeBg = c.isDark ? Colors.white : const Color(0xFF14161A);
    final activeFg = c.isDark ? const Color(0xFF0E1014) : Colors.white;

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: selected
              ? activeBg
              : (c.isDark ? Colors.white.withValues(alpha: 0.07) : Colors.black.withValues(alpha: 0.06)),
          border: Border.all(
            color: selected ? activeBg : c.stroke,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? activeFg : c.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _ArtistCardsGrid extends StatelessWidget {
  const _ArtistCardsGrid({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          Wrap(
            spacing: 14,
            runSpacing: 18,
            children: children,
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------- helpers compartilhados

void _playTracks(WidgetRef ref, List<Track> tracks, {int start = 0}) {
  if (tracks.isEmpty) return;
  final downloads = ref.read(downloadsProvider);
  ref.read(handlerProvider).load(
        tracks,
        start: start,
        urlFor: (t) => resolvePlaybackUrl(t, downloads),
      );
  ref.read(recentProvider.notifier).push(tracks[start]);
}

void _togglePlayCollection(
  WidgetRef ref,
  List<Track> tracks, {
  required bool inThisList,
  required bool isPlaying,
}) {
  final handler = ref.read(handlerProvider);
  if (inThisList) {
    if (isPlaying) {
      handler.pause();
    } else {
      handler.play();
    }
    return;
  }
  _playTracks(ref, tracks);
}

void _playShuffled(WidgetRef ref, List<Track> tracks) {
  if (tracks.isEmpty) return;
  final handler = ref.read(handlerProvider);
  if (!handler.shuffle) handler.toggleShuffle();
  final index = math.Random().nextInt(tracks.length);
  _playTracks(ref, tracks, start: index);
}

class _CollectionDlState {
  const _CollectionDlState({
    required this.allDownloaded,
    required this.downloadingAny,
    required this.progress,
  });

  final bool allDownloaded;
  final bool downloadingAny;
  final double progress;
}

_CollectionDlState _collectionDlState(List<Track> tracks, List<DownloadRecord> downloads) {
  if (tracks.isEmpty) {
    return const _CollectionDlState(allDownloaded: false, downloadingAny: false, progress: 0);
  }
  final byId = {for (final d in downloads) d.trackId: d};
  var doneCount = 0;
  var activeCount = 0;
  var sum = 0.0;
  for (final t in tracks) {
    final d = byId[t.id];
    if (d != null && d.hasPlayableLocal) {
      doneCount++;
      sum += 1.0;
    } else if (d != null && (d.status == 'queued' || d.status == 'downloading')) {
      activeCount++;
      sum += d.progress.clamp(0.0, 1.0);
    }
  }
  return _CollectionDlState(
    allDownloaded: doneCount == tracks.length,
    downloadingAny: activeCount > 0,
    progress: (sum / tracks.length).clamp(0.0, 1.0),
  );
}

Future<void> _downloadAll(BuildContext context, WidgetRef ref, List<Track> tracks) async {
  final notifier = ref.read(downloadsProvider.notifier);
  for (final t in tracks) {
    await notifier.request(t);
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${tracks.length} faixas na fila de download')),
    );
  }
}

Future<void> _cancelDownloads(WidgetRef ref, List<Track> tracks) async {
  final notifier = ref.read(downloadsProvider.notifier);
  for (final t in tracks) {
    await notifier.cancel(t.id);
  }
}

Future<void> _openCollectionMenu(
  BuildContext context,
  WidgetRef ref, {
  required String title,
  required List<Track> tracks,
  VoidCallback? onDownloadAll,
}) {
  final colors = context.colors;
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    backgroundColor: colors.bgElevated,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(sheetContext).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
          ),
          const Divider(indent: 20, endIndent: 20),
          if (tracks.isNotEmpty) ...[
            ListTile(
              leading: Icon(SolarIconsBold.play, color: colors.textSecondary),
              title: const Text('Tocar tudo'),
              onTap: () {
                Navigator.pop(sheetContext);
                _playTracks(ref, tracks);
              },
            ),
            ListTile(
              leading: Icon(SolarIconsBold.shuffle, color: colors.textSecondary),
              title: const Text('Tocar em ordem aleatória'),
              onTap: () {
                Navigator.pop(sheetContext);
                _playShuffled(ref, tracks);
              },
            ),
          ],
          if (onDownloadAll != null)
            ListTile(
              leading: Icon(SolarIconsBold.downloadMinimalistic, color: colors.textSecondary),
              title: const Text('Baixar todas as faixas'),
              onTap: () {
                Navigator.pop(sheetContext);
                onDownloadAll();
              },
            ),
          ListTile(
            leading: Icon(SolarIconsBold.settings, color: colors.accent),
            title: const Text('Configurações'),
            onTap: () {
              Navigator.pop(sheetContext);
              SettingsScreen.open(context);
            },
          ),
          const SizedBox(height: 10),
        ],
      ),
    ),
  );
}

class _LoadingDetailScaffold extends StatelessWidget {
  const _LoadingDetailScaffold();

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    return Scaffold(
      body: Stack(
        children: [
          const Center(child: CircularProgressIndicator()),
          Positioned(
            top: topPad + 10,
            left: 16,
            child: GlassCircleButton(
              icon: SolarIconsBold.altArrowLeft,
              size: 40,
              iconSize: 20,
              onTap: () => Navigator.maybePop(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorDetailScaffold extends StatelessWidget {
  const _ErrorDetailScaffold({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final topPad = MediaQuery.paddingOf(context).top;
    return Scaffold(
      body: Stack(
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Text(message, textAlign: TextAlign.center, style: TextStyle(color: colors.textSecondary)),
            ),
          ),
          Positioned(
            top: topPad + 10,
            left: 16,
            child: GlassCircleButton(
              icon: SolarIconsBold.altArrowLeft,
              size: 40,
              iconSize: 20,
              onTap: () => Navigator.maybePop(context),
            ),
          ),
        ],
      ),
    );
  }
}
