// language: Dart, file: lib/widgets/track_tile.dart, target: mobile-first + desktop, runtime: resong app
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:solar_icons_flutter/solar_icons_flutter.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../screens/detail_screen.dart';
import '../screens/player_screen.dart';
import '../state/library.dart';
import '../state/providers.dart';
import '../state/settings.dart';
import 'artwork.dart';
import 'artist_link.dart';
import 'flight.dart';

class TrackTile extends ConsumerWidget {
  const TrackTile({
    super.key,
    required this.track,
    this.queue,
    this.index,
    this.number,
    this.subtitle,
    this.showArtwork = true,
    this.compact = false,
    this.showFavorite = true,
    this.openPlayerOnTap = true,
  });

  final Track track;
  final List<Track>? queue;
  final int? index;
  final int? number;
  final String? subtitle;
  final bool showArtwork;
  final bool compact;
  final bool showFavorite;
  final bool openPlayerOnTap;

  Future<void> _play(BuildContext context, WidgetRef ref) async {
    final handler = ref.read(handlerProvider);
    final list = queue ?? [track];
    var i = index ?? list.indexWhere((t) => t.id == track.id);
    if (i < 0) i = 0;
    final downloads = ref.read(downloadsProvider);

    final loadFuture = handler.load(
      list,
      start: i,
      urlFor: (t) => resolvePlaybackUrl(t, downloads),
    );
    final shouldOpenPlayer = openPlayerOnTap && ref.read(settingsProvider).openPlayerOnTap;
    if (shouldOpenPlayer && context.mounted) {
      PlayerScreen.open(context, ref, initialTrack: track);
    }
    try {
      await loadFuture;
    } on PlayerInterruptedException {
      // Outra faixa selecionada em seguida antes desta concluir o carregamento.
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível tocar esta faixa agora')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final isCurrent = ref.watch(currentTrackProvider.select((t) => t?.id == track.id));
    final isFav = ref.watch(favoritesProvider.select((favs) => favs.any((t) => t.id == track.id)));
    final dlRecord = ref.watch(
      downloadsProvider.select((list) {
        for (final d in list) {
          if (d.trackId == track.id) return d;
        }
        return null;
      }),
    );
    final accent = ref.watch(accentProvider);
    final waveEnabled = ref.watch(settingsProvider.select((s) => s.waveEffectsEnabled));
    final isDownloading = dlRecord != null &&
        (dlRecord.status == 'queued' || dlRecord.status == 'downloading');
    final isDownloaded = dlRecord?.hasPlayableLocal ?? false;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _play(context, ref),
      onLongPress: () => TrackMenu.open(context, ref, track, queue: queue),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: compact ? 7 : 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: isCurrent ? accent.withValues(alpha: colors.isDark ? 0.14 : 0.10) : Colors.transparent,
        ),
        child: Row(
          children: [
            if (number != null) ...[
              SizedBox(
                width: 26,
                child: isCurrent
                    ? Icon(SolarIconsBold.soundwave, size: 16, color: accent)
                    : Text(
                        '${number!}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          color: colors.textTertiary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
              ),
              const SizedBox(width: 12),
            ] else if (showArtwork) ...[
              FlightElement(
                tag: 'artwork:${track.id}',
                borderRadius: BorderRadius.circular(compact ? 11 : 13),
                enabled: waveEnabled,
                child: Artwork(url: track.artwork, size: compact ? 44 : 48, radius: compact ? 11 : 13, tone: accent),
              ),
              const SizedBox(width: 13),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: compact ? 14.5 : 15,
                            fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w600,
                            color: isCurrent ? accent : colors.textPrimary,
                          ),
                        ),
                      ),
                      if (track.explicit) ...[
                        const SizedBox(width: 6),
                        const _ExplicitBadge(),
                      ],
                      if (track.source == 'spotify' || track.source == 'audius' || track.source == 'archive') ...[
                        const SizedBox(width: 6),
                        _SourceBadge(source: track.source),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  if (subtitle == null && track.artists.isNotEmpty)
                    _ClickableArtistsLine(
                      track: track,
                      color: colors.textSecondary,
                      album: track.album,
                    )
                  else
                    Text(
                      subtitle ?? _subtitle(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: colors.textSecondary),
                    ),
                ],
              ),
            ),
            if (track.durationMs != null && !compact) ...[
              const SizedBox(width: 8),
              Text(
                formatDuration(track.durationMs),
                style: TextStyle(
                  fontSize: 12,
                  color: colors.textTertiary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
            if (isDownloading)
              _InlineDownloadProgress(
                progress: dlRecord.progress,
                queued: dlRecord.status == 'queued',
                accent: accent,
                onCancel: () => ref.read(downloadsProvider.notifier).cancel(track.id),
              )
            else if (isDownloaded)
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(SolarIconsBold.folderCheck, size: 18, color: accent),
                tooltip: 'Baixado — Ver Downloads',
                onPressed: () => openDownloadsTab(context, ref),
              ),
            if (showFavorite)
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: FlightElement(
                  tag: 'fav:${track.id}',
                  borderRadius: BorderRadius.circular(10),
                  enabled: waveEnabled,
                  child: Icon(
                    isFav ? SolarIconsBold.heart : SolarIconsLinear.heart,
                    size: 19,
                    color: isFav ? accent : colors.textSecondary,
                  ),
                ),
                onPressed: () => ref.read(favoritesProvider.notifier).toggle(track),
                tooltip: isFav ? 'Remover dos favoritos' : 'Favoritar',
              ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(SolarIconsBold.menuDots, size: 18, color: colors.textTertiary),
              onPressed: () => TrackMenu.open(context, ref, track, queue: queue),
            ),
          ],
        ),
      ),
    );
  }

  String _subtitle() {
    final parts = <String>[track.artistLine];
    if (track.album != null && track.album!.isNotEmpty && queue == null) parts.add(track.album!);
    return parts.join(' • ');
  }
}

class _ExplicitBadge extends StatelessWidget {
  const _ExplicitBadge();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1.5),
      decoration: BoxDecoration(
        color: (colors.isDark ? Colors.white : Colors.black).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'E',
        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: colors.textSecondary),
      ),
    );
  }
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.source});
  final String source;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final label = switch (source) {
      'spotify' => 'Spotify',
      'audius' => 'Audius',
      'archive' => 'Archive',
      _ => source,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5.5, vertical: 1.5),
      decoration: BoxDecoration(
        color: (colors.isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: (colors.isDark ? Colors.white : Colors.black).withValues(alpha: 0.14),
          width: 0.7,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
          color: colors.textSecondary,
        ),
      ),
    );
  }
}

class _InlineDownloadProgress extends StatelessWidget {
  const _InlineDownloadProgress({
    required this.progress,
    required this.queued,
    required this.accent,
    required this.onCancel,
  });

  final double progress;
  final bool queued;
  final Color accent;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final p = progress.clamp(0.0, 1.0);
    final pct = (p * 100).round();
    return Tooltip(
      message: queued ? 'Na fila — Toque pra cancelar' : 'Baixando $pct% — Toque pra cancelar',
      child: InkResponse(
        radius: 18,
        onTap: onCancel,
        child: SizedBox(
          width: 32,
          height: 32,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  value: !queued && p > 0 ? p : null,
                  strokeWidth: 2.2,
                  color: accent,
                  backgroundColor: accent.withValues(alpha: 0.2),
                ),
              ),
              if (!queued && pct > 0)
                Text(
                  '$pct',
                  style: TextStyle(fontSize: 7, fontWeight: FontWeight.w800, color: accent),
                )
              else
                Icon(Icons.close, size: 10, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ações de long-press / menu "...": favoritar, baixar, playlist, ir pro álbum/artista.
abstract final class TrackMenu {
  static Future<void> open(
    BuildContext context,
    WidgetRef ref,
    Track track, {
    List<Track>? queue,
    VoidCallback? onChanged,
  }) {
    final colors = context.colors;
    final isFav = ref.read(favoritesProvider).any((t) => t.id == track.id);
    final albumId = track.extra['album_id'];

    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: colors.bgElevated,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              child: Row(
                children: [
                  Artwork(url: track.artwork, size: 52, radius: 13, tone: colors.accent),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(sheetContext).textTheme.titleMedium),
                        const SizedBox(height: 3),
                        Text(track.artistLine, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(sheetContext).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(indent: 20, endIndent: 20),
            _action(
              sheetContext,
              icon: isFav ? SolarIconsBold.heart : SolarIconsLinear.heart,
              label: isFav ? 'Remover dos favoritos' : 'Salvar nos favoritos',
              onTap: () async {
                Navigator.pop(sheetContext);
                await ref.read(favoritesProvider.notifier).toggle(track);
                onChanged?.call();
              },
            ),
            Consumer(
              builder: (menuContext, menuRef, _) {
                final dl = menuRef.watch(
                  downloadsProvider.select((list) {
                    for (final d in list) {
                      if (d.trackId == track.id) return d;
                    }
                    return null;
                  }),
                );
                final accentColor = menuRef.watch(accentProvider);
                final active = dl != null && (dl.status == 'queued' || dl.status == 'downloading');
                if (active) {
                  final p = dl.progress.clamp(0.0, 1.0);
                  final pct = (p * 100).round();
                  return ListTile(
                    leading: SizedBox(
                      width: 22,
                      height: 22,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircularProgressIndicator(
                            value: dl.status == 'downloading' && p > 0 ? p : null,
                            strokeWidth: 2.3,
                            color: accentColor,
                            backgroundColor: accentColor.withValues(alpha: 0.2),
                          ),
                          if (pct > 0 && dl.status == 'downloading')
                            Text(
                              '$pct',
                              style: TextStyle(fontSize: 7.5, fontWeight: FontWeight.w800, color: accentColor),
                            ),
                        ],
                      ),
                    ),
                    title: Text(
                      dl.status == 'queued'
                          ? 'Na fila — Toque pra cancelar'
                          : 'Baixando ($pct%) — Toque pra cancelar',
                    ),
                    onTap: () async {
                      await menuRef.read(downloadsProvider.notifier).cancel(track.id);
                      onChanged?.call();
                    },
                  );
                }
                if (dl != null && dl.hasPlayableLocal) {
                  return _action(
                    sheetContext,
                    icon: SolarIconsBold.folderCheck,
                    label: 'Disponível offline — Ver em Downloads',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      openDownloadsTab(context, ref);
                    },
                  );
                }
                if (dl != null && dl.status == 'error') {
                  return _action(
                    sheetContext,
                    icon: SolarIconsBold.refresh,
                    label: 'Falhou — Tentar baixar novamente',
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      await ref.read(downloadsProvider.notifier).retry(track.id);
                      onChanged?.call();
                    },
                  );
                }
                return _action(
                  sheetContext,
                  icon: SolarIconsBold.downloadMinimalistic,
                  label: 'Baixar',
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await ref.read(downloadsProvider.notifier).request(track);
                    onChanged?.call();
                  },
                );
              },
            ),
            _action(
              sheetContext,
              icon: SolarIconsBold.addCircle,
              label: 'Adicionar a playlist',
              onTap: () {
                Navigator.pop(sheetContext);
                _addToPlaylist(context, ref, track, onChanged);
              },
            ),
            if (albumId != null)
              _action(
                sheetContext,
                icon: SolarIconsBold.album,
                label: 'Ir para o álbum',
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => DetailScreen.album('ytal:$albumId')),
                  );
                },
              ),
            if (track.artists.isNotEmpty)
              _action(
                sheetContext,
                icon: SolarIconsBold.user,
                label: 'Ir para ${track.artists.first}',
                onTap: () {
                  Navigator.pop(sheetContext);
                  DetailScreen.openArtistForTrack(context, track);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  static Widget _action(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final colors = context.colors;
    return ListTile(
      leading: Icon(icon, size: 21, color: colors.textSecondary),
      title: Text(label, style: TextStyle(fontSize: 14.5, color: colors.textPrimary)),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 22),
    );
  }

  static Future<void> _addToPlaylist(BuildContext context, WidgetRef ref, Track track, VoidCallback? onChanged) async {
    final colors = context.colors;
    final playlists = ref.read(playlistsProvider);
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: colors.bgElevated,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 6, bottom: 10),
              child: Text('Adicionar a', style: Theme.of(sheetContext).textTheme.titleLarge),
            ),
            ListTile(
              leading: Icon(SolarIconsBold.addCircle, color: colors.accent),
              title: const Text('Nova playlist'),
              onTap: () async {
                Navigator.pop(sheetContext);
                final name = await askPlaylistName(context);
                if (name == null || name.isEmpty) return;
                final p = await ref.read(playlistsProvider.notifier).create(name);
                await ref.read(playlistsProvider.notifier).addTrack(p.id, track);
                onChanged?.call();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Salva em “$name”')));
                }
              },
            ),
            for (final p in playlists)
              ListTile(
                leading: Artwork(url: p.artwork, size: 34, radius: 9, icon: SolarIconsBold.playlist, tone: colors.accent),
                title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${p.trackCount} faixas', style: Theme.of(sheetContext).textTheme.bodySmall),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await ref.read(playlistsProvider.notifier).addTrack(p.id, track);
                  onChanged?.call();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Adicionada a “${p.name}”')));
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}

Future<String?> askValidatedPlaylistName(
  BuildContext context, {
  required String title,
  String initial = '',
  String actionLabel = 'Criar',
}) {
  final controller = TextEditingController(text: initial);
  final colors = context.colors;
  var busy = false;
  String? errorMsg;

  Future<void> submit(BuildContext dialogContext, void Function(VoidCallback) setLocalState) async {
    setLocalState(() {
      busy = true;
      errorMsg = null;
    });
    final res = await Api.instance.validateIdentity(controller.text);
    if (!dialogContext.mounted) return;
    if (!res.ok) {
      setLocalState(() {
        busy = false;
        errorMsg = res.reason ?? 'Nome inválido.';
      });
      return;
    }
    Navigator.pop(dialogContext, res.value);
  }

  return showDialog<String>(
    context: context,
    useRootNavigator: true,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setLocalState) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setLocalState(() => errorMsg = null),
          decoration: InputDecoration(
            hintText: 'Nome da playlist',
            errorText: errorMsg,
            errorStyle: TextStyle(color: colors.danger, fontSize: 12),
          ),
          onSubmitted: (_) => busy ? null : submit(dialogContext, setLocalState),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: colors.accent, foregroundColor: Colors.white),
            onPressed: busy ? null : () => submit(dialogContext, setLocalState),
            child: busy
                ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(actionLabel),
          ),
        ],
      ),
    ),
  );
}

Future<String?> askPlaylistName(BuildContext context) =>
    askValidatedPlaylistName(context, title: 'Nova playlist', actionLabel: 'Criar');

class _ClickableArtistsLine extends StatelessWidget {
  const _ClickableArtistsLine({
    required this.track,
    required this.color,
    this.album,
  });

  final Track track;
  final Color color;
  final String? album;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: 12.5, color: color);
    final albumSuffix = album != null && album!.isNotEmpty && album != track.title ? album : null;
    return Row(
      children: [
        Flexible(
          child: ArtistTextLink(
            track: track,
            style: style,
            suffix: albumSuffix,
          ),
        ),
      ],
    );
  }
}
