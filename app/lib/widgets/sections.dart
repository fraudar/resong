// language: Dart, file: lib/widgets/sections.dart, target: mobile-first + desktop, runtime: resong app
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons_flutter/solar_icons_flutter.dart';

import '../core/models.dart';
import '../core/theme.dart';
import '../screens/detail_screen.dart';
import '../state/library.dart';
import '../state/settings.dart';
import 'artwork.dart';
import 'flight.dart';
import 'track_tile.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 16, 12),
        child: Row(
          children: [
            Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
            if (trailing != null) trailing!,
          ],
        ),
      );
}

/// Card horizontal de álbum / artista / playlist do feed.
class MediaCard extends ConsumerWidget {
  const MediaCard({super.key, required this.kind, this.album, this.artist, this.playlist, this.width = 148});

  final MediaKind kind;
  final AlbumRef? album;
  final ArtistRef? artist;
  final PlaylistRef? playlist;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final accent = ref.watch(accentProvider);
    final waveEnabled = ref.watch(settingsProvider.select((s) => s.waveEffectsEnabled));
    final String refId;
    final String title;
    final String? subtitle;
    final String? artwork;
    final bool round;

    switch (kind) {
      case MediaKind.album:
        final a = album!;
        refId = a.id;
        title = a.title;
        subtitle = [if (a.artists.isNotEmpty) a.artists.join(', '), if (a.year != null) a.year].join(' • ');
        artwork = a.artwork;
        round = false;
      case MediaKind.artist:
        final a = artist!;
        refId = a.id;
        title = a.name;
        subtitle = a.subscribers ?? 'Artista';
        artwork = a.artwork;
        round = true;
      case MediaKind.playlist:
        final p = playlist!;
        refId = p.id;
        title = p.title;
        subtitle = p.owner ?? '${p.trackCount ?? 0} faixas';
        artwork = p.artwork;
        round = false;
    }

    final size = width;
    final radius = BorderRadius.circular(round ? size / 2 : 18);
    return SizedBox(
      width: size,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          final route = switch (kind) {
            MediaKind.album => DetailScreen.album(album!.id, initialRef: album),
            MediaKind.artist => DetailScreen.artist(artist!.id, initialRef: artist),
            MediaKind.playlist => DetailScreen.playlistRef(playlist!.id, initialRef: playlist),
          };
          Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => route));
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: colors.isDark ? 0.30 : 0.10),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: FlightElement(
                tag: 'collection:$refId',
                borderRadius: radius,
                enabled: waveEnabled,
                child: Artwork(
                  url: artwork,
                  size: size,
                  radius: round ? size / 2 : 18,
                  tone: accent,
                  icon: switch (kind) {
                    MediaKind.album => SolarIconsBold.album,
                    MediaKind.artist => SolarIconsBold.user,
                    MediaKind.playlist => SolarIconsBold.playlist,
                  },
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.22, color: colors.textPrimary),
            ),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: colors.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum MediaKind { album, artist, playlist }

/// Lista vertical simples com título de seção.
class TrackListSection extends ConsumerWidget {
  const TrackListSection({super.key, required this.title, required this.tracks, this.showNumbers = false, this.subtitleOf});

  final String title;
  final List<Track> tracks;
  final bool showNumbers;
  final String? Function(Track track)? subtitleOf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (tracks.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title),
        for (var i = 0; i < tracks.length; i++)
          TrackTile(
            track: tracks[i],
            queue: tracks,
            index: i,
            number: showNumbers ? i + 1 : null,
            subtitle: subtitleOf?.call(tracks[i]),
          ),
      ],
    );
  }
}

/// Rail horizontal de itens misturados do feed.
class MediaRail extends StatelessWidget {
  const MediaRail({super.key, required this.label, required this.children});
  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(label),
          SizedBox(
            height: 232,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: children.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (_, i) => children[i],
            ),
          ),
        ],
      );
}

/// Converte refs do feed em navegação dentro da aba atual.
void openMedia(BuildContext context, WidgetRef ref, {AlbumRef? album, ArtistRef? artist, PlaylistRef? playlist}) {
  final route = album != null
      ? DetailScreen.album(album.id)
      : artist != null
          ? DetailScreen.artist(artist.id)
          : DetailScreen.playlistRef(playlist!.id);
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => route));
}
