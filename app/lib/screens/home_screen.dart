// language: Dart, file: lib/screens/home_screen.dart, target: mobile-first + desktop, runtime: resong app
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:solar_icons_flutter/solar_icons_flutter.dart';

import '../core/models.dart';
import '../core/theme.dart';
import '../state/library.dart';
import '../state/providers.dart';
import '../state/scrobbles.dart';
import '../state/settings.dart';
import '../widgets/glass.dart';
import '../widgets/liquid_wave_backdrop.dart';
import '../widgets/sections.dart';
import '../widgets/track_tile.dart';
import 'settings_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final feed = ref.watch(homeProvider);
    final quickPicks = ref.watch(quickPicksProvider).valueOrNull ?? const <Track>[];
    final downloads = ref.watch(downloadsProvider);
    final recent = ref.watch(recentProvider);
    final favorites = ref.watch(favoritesProvider);
    final playlists = ref.watch(playlistsProvider);
    final palette = ref.watch(currentPaletteProvider);
    final playing = ref.watch(isPlayingProvider);
    final waveEnabled = ref.watch(settingsProvider.select((s) => s.waveEffectsEnabled));
    final accent = palette.accentFor(colors.isDark);
    final topPad = MediaQuery.paddingOf(context).top;

    final offlineTracks = [
      for (final d in downloads)
        if (d.hasPlayableLocal) d.track,
    ];
    final localPlaylists = [
      for (final p in playlists)
        PlaylistRef(
          id: p.id,
          source: 'local',
          title: p.name,
          artwork: p.artwork,
          trackCount: p.trackCount,
          description: p.description,
        ),
    ];

    final offlineSlivers = _offlineSlivers(
      offlineTracks: offlineTracks,
      recent: recent,
      favorites: favorites,
      playlists: localPlaylists,
    );

    return Scaffold(
      backgroundColor: colors.bg,
      body: LiquidWaveBackdrop(
        palette: palette,
        intense: false,
        isPlaying: playing,
        animateAmbient: waveEnabled,
        child: feed.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => offlineSlivers.isNotEmpty
              ? RefreshIndicator(
                  color: accent,
                  onRefresh: () async {
                    ref.invalidate(homeProvider);
                    ref.invalidate(quickPicksProvider);
                  },
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                    slivers: [
                      SliverToBoxAdapter(child: SizedBox(height: topPad + 4)),
                      if (MediaQuery.sizeOf(context).width < 860)
                        const SliverToBoxAdapter(child: _Header()),
                      SliverToBoxAdapter(
                        child: _OfflineBanner(
                          onRetry: () {
                            ref.invalidate(homeProvider);
                            ref.invalidate(quickPicksProvider);
                          },
                        ),
                      ),
                      ...offlineSlivers,
                      const SliverToBoxAdapter(child: SizedBox(height: 170)),
                    ],
                  ),
                )
              : _HomeError(
                  message: 'Sem conexão com a internet.\nVocê pode baixar faixas para ouvir offline.',
                  onRetry: () => ref.invalidate(homeProvider),
                ),
          data: (home) => RefreshIndicator(
            color: accent,
            onRefresh: () async {
              ref.invalidate(homeProvider);
              ref.invalidate(quickPicksProvider);
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              slivers: [
                SliverToBoxAdapter(child: SizedBox(height: topPad + 4)),
                if (MediaQuery.sizeOf(context).width < 860)
                  const SliverToBoxAdapter(child: _Header()),
                if (quickPicks.isNotEmpty)
                  SliverToBoxAdapter(child: _QuickPicksSection(tracks: quickPicks, accent: accent)),
                ..._body(home, offlineSlivers: offlineSlivers),
                const SliverToBoxAdapter(child: SizedBox(height: 170)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _offlineSlivers({
    required List<Track> offlineTracks,
    required List<Track> recent,
    required List<Track> favorites,
    required List<PlaylistRef> playlists,
  }) {
    return [
      if (offlineTracks.isNotEmpty)
        SliverToBoxAdapter(child: TrackListSection(title: 'Disponível offline', tracks: offlineTracks)),
      if (recent.isNotEmpty)
        SliverToBoxAdapter(child: TrackListSection(title: 'Ouvidos por último', tracks: recent)),
      if (favorites.isNotEmpty)
        SliverToBoxAdapter(child: TrackListSection(title: 'Curtidas', tracks: favorites)),
      if (playlists.isNotEmpty)
        SliverToBoxAdapter(
          child: MediaRail(
            label: 'Suas playlists',
            children: [for (final p in playlists) MediaCard(kind: MediaKind.playlist, playlist: p)],
          ),
        ),
    ];
  }

  List<Widget> _body(HomeFeed home, {List<Widget> offlineSlivers = const []}) {
    final out = <Widget>[];
    for (final section in home.sections) {
      if (section.isEmpty) continue;
      var albumLabelDone = false;
      if (section.tracks.isNotEmpty) {
        out.add(SliverToBoxAdapter(child: TrackListSection(title: section.title, tracks: section.tracks)));
      }
      if (section.albums.isNotEmpty) {
        out.add(SliverToBoxAdapter(
          child: MediaRail(
            label: section.tracks.isEmpty ? section.title : 'Álbuns',
            children: [for (final a in section.albums) MediaCard(kind: MediaKind.album, album: a)],
          ),
        ));
        albumLabelDone = true;
      }
      if (section.artists.isNotEmpty) {
        out.add(SliverToBoxAdapter(
          child: MediaRail(
            label: section.tracks.isEmpty && !albumLabelDone ? section.title : 'Artistas',
            children: [for (final a in section.artists) MediaCard(kind: MediaKind.artist, artist: a)],
          ),
        ));
      }
      if (section.playlists.isNotEmpty) {
        out.add(SliverToBoxAdapter(
          child: MediaRail(
            label: section.playlists.length == 1 && section.tracks.isEmpty && section.albums.isEmpty && section.artists.isEmpty
                ? section.title
                : 'Playlists',
            children: [for (final p in section.playlists) MediaCard(kind: MediaKind.playlist, playlist: p)],
          ),
        ));
      }
    }
    if (home.recent.isNotEmpty) {
      out.add(SliverToBoxAdapter(child: TrackListSection(title: 'Ouvidos por último', tracks: home.recent)));
    }
    if (home.playlists.isNotEmpty) {
      out.add(SliverToBoxAdapter(
        child: MediaRail(
          label: 'Suas playlists',
          children: [for (final p in home.playlists) MediaCard(kind: MediaKind.playlist, playlist: p)],
        ),
      ));
    }
    if (out.isEmpty) {
      if (offlineSlivers.isNotEmpty) {
        out.addAll(offlineSlivers);
      } else {
        out.add(const _EmptyFeed());
      }
    }
    return out;
  }
}

class _QuickPicksSection extends ConsumerWidget {
  const _QuickPicksSection({required this.tracks, required this.accent});
  final List<Track> tracks;
  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Quick picks pra você',
          trailing: TextButton.icon(
            onPressed: () {
              final downloads = ref.read(downloadsProvider);
              ref.read(handlerProvider).load(
                    tracks,
                    urlFor: (t) => resolvePlaybackUrl(t, downloads),
                  );
            },
            icon: Icon(SolarIconsBold.play, size: 15, color: accent),
            label: Text('Tocar mix', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: accent)),
          ),
        ),
        for (var i = 0; i < tracks.length; i++)
          TrackTile(track: tracks[i], queue: tracks, index: i, compact: true),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Row(
        children: [
          const SizedBox(width: 38),
          Expanded(
            child: Center(
              child: Text(
                'resong',
                style: GoogleFonts.sora(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2.5,
                  color: colors.textPrimary,
                ),
              ),
            ),
          ),
          GlassCircleButton(
            icon: SolarIconsBold.settings,
            size: 38,
            iconSize: 18,
            tooltip: 'Configurações',
            onTap: () => SettingsScreen.open(context),
          ),
        ],
      ),
    );
  }
}

class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 48, 20, 0),
        child: Column(
          children: [
            Icon(SolarIconsBold.musicNote, size: 46, color: colors.textTertiary),
            const SizedBox(height: 16),
            Text('Tudo quieto por aqui', style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'Busque por uma música, artista ou álbum e toque na hora.',
              style: TextStyle(fontSize: 13.5, color: colors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.stroke),
        ),
        child: Row(
          children: [
            Icon(Icons.cloud_off_rounded, size: 17, color: colors.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Modo offline • exibindo sua biblioteca local',
                style: TextStyle(fontSize: 12.5, color: colors.textSecondary),
              ),
            ),
            TextButton(
              onPressed: onRetry,
              child: const Text('Reconectar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeError extends StatelessWidget {
  const _HomeError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(SolarIconsBold.closeCircle, size: 42, color: colors.danger),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: colors.textSecondary)),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: colors.accent, foregroundColor: Colors.white),
              onPressed: onRetry,
              child: const Text('Tentar de novo'),
            ),
          ],
        ),
      ),
    );
  }
}
