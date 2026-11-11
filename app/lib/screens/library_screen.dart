// language: Dart, file: lib/screens/library_screen.dart, target: mobile-first + desktop, runtime: resong app
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons_flutter/solar_icons_flutter.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../state/library.dart';
import '../state/providers.dart';
import '../state/settings.dart';
import '../widgets/artwork.dart';
import '../widgets/collection_hero_layout.dart';
import '../widgets/liquid_wave_backdrop.dart';
import '../widgets/track_tile.dart';

final _localPlaylistProvider = FutureProvider.family<PlaylistRecord, String>((ref, id) => Api.instance.playlist(id));

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(
      length: 4,
      vsync: this,
      initialIndex: ref.read(libraryTabProvider).clamp(0, 3),
    )..addListener(() {
        if (!_tabCtrl.indexIsChanging && ref.read(libraryTabProvider) != _tabCtrl.index) {
          ref.read(libraryTabProvider.notifier).state = _tabCtrl.index;
        }
      });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final palette = ref.watch(currentPaletteProvider);
    final playing = ref.watch(isPlayingProvider);
    final waveEnabled = ref.watch(settingsProvider.select((s) => s.waveEffectsEnabled));
    ref.listen<int>(libraryTabProvider, (_, next) {
      final target = next.clamp(0, 3);
      if (_tabCtrl.index != target) {
        _tabCtrl.animateTo(target);
      }
    });

    return Scaffold(
      backgroundColor: colors.bg,
      body: LiquidWaveBackdrop(
        palette: palette,
        intense: false,
        isPlaying: playing,
        animateAmbient: waveEnabled,
        child: NestedScrollView(
          headerSliverBuilder: (context, _) => [
            SliverAppBar(
              pinned: true,
              floating: true,
              toolbarHeight: 58,
              titleSpacing: 20,
              backgroundColor: Colors.transparent,
              title: Text('Biblioteca', style: Theme.of(context).textTheme.displayMedium?.copyWith(fontSize: 25)),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(52),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TabBar(
                    controller: _tabCtrl,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                    labelPadding: const EdgeInsets.symmetric(horizontal: 15),
                    dividerColor: Colors.transparent,
                    indicatorSize: TabBarIndicatorSize.tab,
                    splashBorderRadius: BorderRadius.circular(20),
                    indicator: BoxDecoration(
                      color: colors.accent.withValues(alpha: colors.isDark ? 0.24 : 0.16),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: colors.accent.withValues(alpha: 0.42), width: 0.9),
                    ),
                    labelColor: colors.isDark ? Colors.white : colors.accent,
                    unselectedLabelColor: colors.textSecondary,
                    labelStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                    unselectedLabelStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
                    tabs: const [
                      Tab(height: 36, text: 'Favoritos'),
                      Tab(height: 36, text: 'Playlists'),
                      Tab(height: 36, text: 'Downloads'),
                      Tab(height: 36, text: 'Recentes'),
                    ],
                  ),
                ),
              ),
            ),
          ],
          body: TabBarView(
            controller: _tabCtrl,
            children: const [
              _FavoritesTab(),
              _PlaylistsTab(),
              _DownloadsTab(),
              _RecentTab(),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- favoritos

class _FavoritesTab extends ConsumerWidget {
  const _FavoritesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritesProvider);
    if (favorites.isEmpty) {
      return const _Empty(
        icon: SolarIconsBold.heart,
        title: 'Nenhum favorito ainda',
        subtitle: 'Toque no coração de uma faixa pra salvar aqui.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 170),
      itemCount: favorites.length,
      itemBuilder: (_, i) => TrackTile(track: favorites[i], queue: favorites, index: i, compact: true),
    );
  }
}

// ------------------------------------------------------------ recentes

class _RecentTab extends ConsumerWidget {
  const _RecentTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(recentProvider);
    if (recent.isEmpty) {
      return const _Empty(
        icon: SolarIconsBold.headphonesRound,
        title: 'Nada ouvido por aqui',
        subtitle: 'O que você tocar aparece nesta lista.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 170),
      itemCount: recent.length,
      itemBuilder: (_, i) => TrackTile(track: recent[i], queue: recent, index: i, compact: true),
    );
  }
}

// ------------------------------------------------------------ playlists

class _PlaylistsTab extends ConsumerWidget {
  const _PlaylistsTab();

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final name = await askPlaylistName(context);
    if (name == null || name.isEmpty) return;
    final p = await ref.read(playlistsProvider.notifier).create(name);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Playlist “$name” criada')));
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => _LocalPlaylistScreen(id: p.id)),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final playlists = ref.watch(playlistsProvider);
    final covers = ref.watch(playlistCoversProvider);
    final accent = ref.watch(accentProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
          child: Row(
            children: [
              Text(
                '${playlists.length} ${playlists.length == 1 ? 'playlist' : 'playlists'}',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: colors.textTertiary, letterSpacing: 0.5),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _importPlaylist(context, ref),
                icon: Icon(SolarIconsBold.downloadMinimalistic, size: 17, color: colors.textSecondary),
                label: Text('Importar', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.textSecondary)),
              ),
              TextButton.icon(
                onPressed: () => _create(context, ref),
                icon: Icon(SolarIconsBold.add, size: 18, color: accent),
                label: Text('Nova', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: accent)),
              ),
            ],
          ),
        ),
        Expanded(
          child: playlists.isEmpty
              ? const _Empty(
                  icon: SolarIconsBold.playlist,
                  title: 'Nenhuma playlist',
                  subtitle: 'Crie a primeira e guarde suas faixas favoritas.',
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    const gap = 14.0;
                    const sidePad = 20.0;
                    final cols = constraints.maxWidth > 700 ? 4 : 2;
                    final cell = (constraints.maxWidth - sidePad * 2 - gap * (cols - 1)) / cols;
                    return GridView.builder(
                      padding: const EdgeInsets.fromLTRB(sidePad, 10, sidePad, 170),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cols,
                        mainAxisSpacing: 18,
                        crossAxisSpacing: gap,
                        mainAxisExtent: cell + 66,
                      ),
                      itemCount: playlists.length,
                      itemBuilder: (_, i) => _PlaylistCard(
                        playlist: playlists[i],
                        localCoverBytes: covers[playlists[i].id],
                        cell: cell,
                        accent: accent,
                        onOpen: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(builder: (_) => _LocalPlaylistScreen(id: playlists[i].id)),
                        ),
                        onMenu: () => _menu(context, ref, playlists[i]),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _importPlaylist(BuildContext context, WidgetRef ref) async {
    final colors = context.colors;
    final nameCtrl = TextEditingController();
    final linesCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Importar playlist'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Nome da playlist'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: linesCtrl,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: 'Cole uma lista de faixas (uma por linha), M3U ou JSPF',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: colors.accent, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Importar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final queries = _parseImportedQueries(linesCtrl.text);
    if (queries.isEmpty) return;

    final typedName = nameCtrl.text.trim().isEmpty ? 'Importada' : nameCtrl.text.trim();
    final checkedName = await Api.instance.validateIdentity(typedName);
    final name = checkedName.ok ? checkedName.value : 'Importada';
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Importando ${queries.length} faixas…')),
      );
    }
    final playlist = await ref.read(playlistsProvider.notifier).create(name);
    var added = 0;
    for (final q in queries.take(30)) {
      try {
        final res = await Api.instance.search(q, limit: 3);
        if (res.tracks.isNotEmpty) {
          await ref.read(playlistsProvider.notifier).addTrack(playlist.id, res.tracks.first);
          added++;
        }
      } catch (_) {}
    }
    ref.invalidate(_localPlaylistProvider(playlist.id));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$added faixas adicionadas em “$name”')),
      );
    }
  }

  Future<void> _menu(BuildContext context, WidgetRef ref, PlaylistRecord p) async {
    final colors = context.colors;
    final covers = ref.read(playlistCoversProvider);
    final localBytes = covers[p.id];
    await showModalBottomSheet<void>(
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
                  Artwork(
                    url: p.artwork,
                    localBytes: localBytes,
                    size: 46,
                    radius: 12,
                    icon: SolarIconsBold.playlist,
                    tone: colors.accent,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(sheetContext).textTheme.titleMedium),
                  ),
                ],
              ),
            ),
            const Divider(indent: 20, endIndent: 20),
            ListTile(
              leading: Icon(SolarIconsBold.gallery, size: 21, color: colors.textSecondary),
              title: Text(localBytes != null ? 'Trocar capa' : 'Escolher capa', style: const TextStyle(fontSize: 14.5)),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _pickPlaylistCover(context, ref, p.id);
              },
            ),
            if (localBytes != null)
              ListTile(
                leading: Icon(SolarIconsBold.closeCircle, size: 21, color: colors.textSecondary),
                title: const Text('Remover capa personalizada', style: TextStyle(fontSize: 14.5)),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await ref.read(playlistCoversProvider.notifier).removeCover(p.id);
                },
              ),
            ListTile(
              leading: Icon(SolarIconsBold.pen2, size: 21, color: colors.textSecondary),
              title: const Text('Renomear', style: TextStyle(fontSize: 14.5)),
              onTap: () async {
                Navigator.pop(sheetContext);
                final name = await askValidatedPlaylistName(
                  context,
                  title: 'Renomear playlist',
                  initial: p.name,
                  actionLabel: 'Salvar',
                );
                if (name == null || name.isEmpty || name == p.name) return;
                await ref.read(playlistsProvider.notifier).rename(p.id, name);
                ref.invalidate(_localPlaylistProvider(p.id));
              },
            ),
            ListTile(
              leading: Icon(SolarIconsBold.copy, size: 21, color: colors.textSecondary),
              title: const Text('Exportar como M3U', style: TextStyle(fontSize: 14.5)),
              onTap: () async {
                Navigator.pop(sheetContext);
                final full = await Api.instance.playlist(p.id);
                await Clipboard.setData(ClipboardData(text: _exportM3u(full)));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Playlist M3U copiada')));
                }
              },
            ),
            ListTile(
              leading: Icon(SolarIconsBold.playlist, size: 21, color: colors.textSecondary),
              title: const Text('Exportar como JSPF', style: TextStyle(fontSize: 14.5)),
              onTap: () async {
                Navigator.pop(sheetContext);
                final full = await Api.instance.playlist(p.id);
                await Clipboard.setData(ClipboardData(text: _exportJspf(full)));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Playlist JSPF copiada')));
                }
              },
            ),
            ListTile(
              leading: Icon(SolarIconsBold.documentText, size: 21, color: colors.textSecondary),
              title: const Text('Exportar como CSV', style: TextStyle(fontSize: 14.5)),
              onTap: () async {
                Navigator.pop(sheetContext);
                final full = await Api.instance.playlist(p.id);
                await Clipboard.setData(ClipboardData(text: _exportCsv(full)));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Playlist CSV copiada')));
                }
              },
            ),
            ListTile(
              leading: Icon(SolarIconsBold.link, size: 21, color: colors.textSecondary),
              title: const Text('Copiar link público', style: TextStyle(fontSize: 14.5)),
              onTap: () async {
                Navigator.pop(sheetContext);
                await Clipboard.setData(ClipboardData(text: Api.instance.playlistExportUrl(p.id)));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link da playlist copiado')));
                }
              },
            ),
            ListTile(
              leading: Icon(SolarIconsBold.trashBinMinimalistic, size: 21, color: colors.danger),
              title: Text('Excluir', style: TextStyle(fontSize: 14.5, color: colors.danger)),
              onTap: () async {
                Navigator.pop(sheetContext);
                await ref.read(playlistsProvider.notifier).remove(p.id);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({
    required this.playlist,
    this.localCoverBytes,
    required this.cell,
    required this.accent,
    required this.onOpen,
    required this.onMenu,
  });

  final PlaylistRecord playlist;
  final Uint8List? localCoverBytes;
  final double cell;
  final Color accent;
  final VoidCallback onOpen;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onOpen,
      onLongPress: onMenu,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Artwork(
            url: playlist.artwork,
            localBytes: localCoverBytes,
            size: cell,
            radius: 16,
            tone: accent,
            icon: SolarIconsBold.playlist,
          ),
          const SizedBox(height: 10),
          Text(
            playlist.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colors.textPrimary),
          ),
          const SizedBox(height: 3),
          Text(
            '${playlist.trackCount} ${playlist.trackCount == 1 ? 'faixa' : 'faixas'}',
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------- downloads

class _DownloadsTab extends ConsumerWidget {
  const _DownloadsTab();

  void _playAll(WidgetRef ref, List<DownloadRecord> records, int index) {
    final tracks = [for (final d in records) d.track];
    ref.read(handlerProvider).load(
          tracks,
          start: index,
          urlFor: (t) => resolvePlaybackUrl(t, records),
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final downloads = ref.watch(downloadsProvider);
    if (downloads.isEmpty) {
      return const _Empty(
        icon: SolarIconsBold.downloadMinimalistic,
        title: 'Nenhum download local',
        subtitle: 'Toque em “Baixar” pra salvar músicas com capa e tags direto no aparelho.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 170),
      itemCount: downloads.length,
      itemBuilder: (_, i) {
        final d = downloads[i];
        final accent = ref.watch(accentProvider);
        final String status;
        final Color statusColor;
        switch (d.status) {
          case 'done':
            final sizeStr = d.fileSize != null ? formatBytes(d.fileSize) : 'Salvo';
            status = (d.displayPath ?? '').isNotEmpty ? '$sizeStr · ${d.displayPath}' : sizeStr;
            statusColor = colors.accentAlt;
          case 'error':
            status = d.error ?? 'Falhou';
            statusColor = colors.danger;
          case 'downloading':
            final pct = (d.progress * 100).round().clamp(1, 99);
            status = 'Baixando · $pct%';
            statusColor = accent;
          default:
            status = 'Na fila';
            statusColor = colors.textTertiary;
        }
        final inProgress = d.status == 'queued' || d.status == 'downloading';
        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _playAll(ref, downloads, i),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Artwork(url: d.track.artwork, size: 44, radius: 11, tone: accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        d.track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: colors.textPrimary),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: statusColor),
                      ),
                      if (d.status == 'downloading') ...[
                        const SizedBox(height: 5),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: d.progress.clamp(0.02, 1.0),
                            minHeight: 3,
                            color: accent,
                            backgroundColor: colors.stroke.withValues(alpha: 0.35),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (inProgress)
                  IconButton(
                    tooltip: 'Cancelar download',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(SolarIconsBold.closeCircle, size: 19, color: colors.textSecondary),
                    onPressed: () => ref.read(downloadsProvider.notifier).cancel(d.trackId),
                  )
                else ...[
                  if (d.status == 'error')
                    IconButton(
                      tooltip: 'Tentar novamente',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(SolarIconsBold.refresh, size: 18, color: accent),
                      onPressed: () => ref.read(downloadsProvider.notifier).retry(d.trackId),
                    ),
                  IconButton(
                    tooltip: 'Remover do aparelho',
                    visualDensity: VisualDensity.compact,
                    icon: Icon(SolarIconsBold.trashBinMinimalistic, size: 19, color: colors.textTertiary),
                    onPressed: () => ref.read(downloadsProvider.notifier).remove(d.trackId),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

// ------------------------------------------- detalhe de playlist local

class _LocalPlaylistScreen extends ConsumerWidget {
  const _LocalPlaylistScreen({required this.id});
  final String id;

  void _play(WidgetRef ref, List<Track> tracks, int index) {
    if (tracks.isEmpty) return;
    final downloads = ref.read(downloadsProvider);
    ref.read(handlerProvider).load(
          tracks,
          start: index,
          urlFor: (t) => resolvePlaybackUrl(t, downloads),
        );
    ref.read(recentProvider.notifier).push(tracks[index]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final data = ref.watch(_localPlaylistProvider(id));
    return data.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Text('Não deu pra carregar a playlist.\n$e', textAlign: TextAlign.center, style: TextStyle(color: colors.textSecondary)),
        ),
      ),
      data: (playlist) {
        final tracks = playlist.tracks ?? const <Track>[];
        final localCover = ref.watch(playlistCoversProvider)[playlist.id];
        final coverUrl = playlist.artwork ?? (tracks.isNotEmpty ? tracks.first.artwork : null);
        final palette = watchCollectionPalette(ref, coverUrl);
        final currentTrack = ref.watch(currentTrackProvider);
        final playing = ref.watch(isPlayingProvider);
        ref.watch(playerModeProvider);
        final handler = ref.watch(handlerProvider);
        final inThisList = currentTrack != null && tracks.any((t) => t.id == currentTrack.id);

        return CollectionHeroLayout(
          palette: palette,
          artworkUrl: coverUrl,
          localArtworkBytes: localCover,
          fallbackIcon: SolarIconsBold.playlist,
          title: playlist.name,
          subtitle: 'Sua playlist',
          meta: '${tracks.length} ${tracks.length == 1 ? 'faixa' : 'faixas'}',
          isPlayingWaves: playing,
          isCollectionPlaying: inThisList && playing,
          shuffleActive: handler.shuffle,
          onPlayPause: tracks.isEmpty
              ? null
              : () {
                  if (inThisList) {
                    playing ? handler.pause() : handler.play();
                  } else {
                    _play(ref, tracks, 0);
                  }
                },
          onShuffle: tracks.isEmpty
              ? null
              : () {
                  if (!handler.shuffle) handler.toggleShuffle();
                  _play(ref, tracks, DateTime.now().millisecondsSinceEpoch % tracks.length);
                },
          trailingIcon: SolarIconsBold.pen2,
          trailingTooltip: 'Renomear',
          onTrailingTap: () async {
            final name = await askValidatedPlaylistName(
              context,
              title: 'Renomear playlist',
              initial: playlist.name,
              actionLabel: 'Salvar',
            );
            if (name == null || name.isEmpty || name == playlist.name) return;
            await ref.read(playlistsProvider.notifier).rename(playlist.id, name);
            ref.invalidate(_localPlaylistProvider(playlist.id));
          },
          onMenuTap: () => _menu(context, ref, playlist),
          slivers: [
            if (tracks.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                  child: Text(
                    'Playlist vazia — adicione faixas pelo menu “…” de qualquer música.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13.5, color: colors.textSecondary),
                  ),
                ),
              ),
            SliverReorderableList(
              itemCount: tracks.length,
              onReorderItem: (oldIndex, newIndex) async {
                final reordered = List<Track>.from(tracks);
                final item = reordered.removeAt(oldIndex);
                reordered.insert(newIndex, item);
                await ref.read(playlistsProvider.notifier).reorder(
                      playlist.id,
                      [for (final t in reordered) t.id],
                    );
                ref.invalidate(_localPlaylistProvider(playlist.id));
              },
              itemBuilder: (context, i) {
                final t = tracks[i];
                return Dismissible(
                  key: ValueKey('${playlist.id}:${t.id}'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 26),
                    color: colors.danger.withValues(alpha: 0.22),
                    child: Icon(SolarIconsBold.trashBinMinimalistic, color: colors.danger),
                  ),
                  onDismissed: (_) async {
                    await ref.read(playlistsProvider.notifier).removeTrack(playlist.id, t.id);
                    ref.invalidate(_localPlaylistProvider(playlist.id));
                  },
                  child: Row(
                    children: [
                      Expanded(
                        child: TrackTile(
                          track: t,
                          queue: tracks,
                          index: i,
                          number: i + 1,
                          showArtwork: false,
                          compact: true,
                        ),
                      ),
                      ReorderableDragStartListener(
                        index: i,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Icon(SolarIconsBold.hamburgerMenu, size: 18, color: colors.textTertiary),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _menu(BuildContext context, WidgetRef ref, PlaylistRecord playlist) async {
    final colors = context.colors;
    final hasCustomCover = ref.read(playlistCoversProvider).containsKey(playlist.id);
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: colors.bgElevated,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(SolarIconsBold.gallery, size: 21, color: colors.textSecondary),
              title: Text(hasCustomCover ? 'Trocar capa' : 'Escolher capa', style: const TextStyle(fontSize: 14.5)),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _pickPlaylistCover(context, ref, playlist.id);
              },
            ),
            if (hasCustomCover)
              ListTile(
                leading: Icon(SolarIconsBold.closeCircle, size: 21, color: colors.textSecondary),
                title: const Text('Remover capa personalizada', style: TextStyle(fontSize: 14.5)),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await ref.read(playlistCoversProvider.notifier).removeCover(playlist.id);
                },
              ),
            ListTile(
              leading: Icon(SolarIconsBold.pen2, size: 21, color: colors.textSecondary),
              title: const Text('Renomear', style: TextStyle(fontSize: 14.5)),
              onTap: () async {
                Navigator.pop(sheetContext);
                final name = await askValidatedPlaylistName(
                  context,
                  title: 'Renomear playlist',
                  initial: playlist.name,
                  actionLabel: 'Salvar',
                );
                if (name == null || name.isEmpty || name == playlist.name) return;
                await ref.read(playlistsProvider.notifier).rename(playlist.id, name);
                ref.invalidate(_localPlaylistProvider(playlist.id));
              },
            ),
            ListTile(
              leading: Icon(SolarIconsBold.copy, size: 21, color: colors.textSecondary),
              title: const Text('Exportar como M3U', style: TextStyle(fontSize: 14.5)),
              onTap: () async {
                Navigator.pop(sheetContext);
                final m3u = _exportM3u(playlist);
                await Clipboard.setData(ClipboardData(text: m3u));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Playlist M3U copiada')));
                }
              },
            ),
            ListTile(
              leading: Icon(SolarIconsBold.playlist, size: 21, color: colors.textSecondary),
              title: const Text('Exportar como JSPF', style: TextStyle(fontSize: 14.5)),
              onTap: () async {
                Navigator.pop(sheetContext);
                final jspf = _exportJspf(playlist);
                await Clipboard.setData(ClipboardData(text: jspf));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Playlist JSPF copiada')));
                }
              },
            ),
            ListTile(
              leading: Icon(SolarIconsBold.trashBinMinimalistic, size: 21, color: colors.danger),
              title: Text('Excluir playlist', style: TextStyle(fontSize: 14.5, color: colors.danger)),
              onTap: () async {
                Navigator.pop(sheetContext);
                await ref.read(playlistsProvider.notifier).remove(playlist.id);
                if (context.mounted) Navigator.maybePop(context);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- auxiliares

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(36, 0, 36, 120),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: colors.textTertiary),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(subtitle, style: TextStyle(fontSize: 13.5, color: colors.textSecondary), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

List<String> _parseImportedQueries(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return const [];
  if (trimmed.startsWith('{')) {
    try {
      final decoded = jsonDecode(trimmed);
      final tracks = (decoded as Map?)?['playlist']?['track'] as List?;
      if (tracks != null) {
        return [
          for (final item in tracks.whereType<Map>())
            '${item['creator'] ?? ''} ${item['title'] ?? ''}'.trim(),
        ].where((s) => s.isNotEmpty).toList();
      }
    } catch (_) {}
  }
  final out = <String>[];
  for (final line in trimmed.split('\n')) {
    final l = line.trim();
    if (l.isEmpty) continue;
    if (l.startsWith('#EXTINF:')) {
      final idx = l.indexOf(',');
      if (idx >= 0 && idx + 1 < l.length) out.add(l.substring(idx + 1).trim());
      continue;
    }
    if (l.startsWith('#') || l.startsWith('http://') || l.startsWith('https://')) continue;
    if (l.toLowerCase().startsWith('title,artists')) continue;
    if (l.contains(',')) {
      final cols = l.split(',').map((c) => c.replaceAll('"', '').trim()).toList();
      if (cols.length >= 2) {
        final q = '${cols[1]} ${cols[0]}'.trim();
        if (q.isNotEmpty) {
          out.add(q);
          continue;
        }
      }
    }
    out.add(l);
  }
  return out;
}

String _exportCsv(PlaylistRecord p) {
  String esc(String v) => '"${v.replaceAll('"', '""')}"';
  final buf = StringBuffer()..writeln('title,artists,album,duration_ms,id');
  for (final t in p.tracks ?? const <Track>[]) {
    buf.writeln([
      esc(t.title),
      esc(t.artists.join('; ')),
      esc(t.album ?? ''),
      '${t.durationMs ?? ''}',
      esc(t.id),
    ].join(','));
  }
  return buf.toString().trim();
}

String _exportM3u(PlaylistRecord p) {
  final buf = StringBuffer()..writeln('#EXTM3U')..writeln('#PLAYLIST:${p.name}');
  for (final t in p.tracks ?? const <Track>[]) {
    final sec = ((t.durationMs ?? 0) / 1000).round();
    buf.writeln('#EXTINF:$sec,${t.artistLine} - ${t.title}');
    buf.writeln('resong://${t.id}');
  }
  return buf.toString().trim();
}

String _exportJspf(PlaylistRecord p) => const JsonEncoder.withIndent('  ').convert({
      'playlist': {
        'title': p.name,
        'track': [
          for (final t in p.tracks ?? const <Track>[])
            {
              'title': t.title,
              'creator': t.artistLine,
              if (t.album != null) 'album': t.album,
              if (t.durationMs != null) 'duration': t.durationMs,
            },
        ],
      },
    });

Future<void> _pickPlaylistCover(BuildContext context, WidgetRef ref, String playlistId) async {
  try {
    final picked = await FilePicker.pickFile(type: FileType.image);
    final bytes = picked == null ? null : await picked.readAsBytes();
    if (bytes == null || bytes.isEmpty) return;
    final saved = await ref.read(playlistCoversProvider.notifier).setCover(playlistId, bytes);
    if (context.mounted && !saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Imagem acima do limite (512 KB). Tente uma menor.')),
      );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não deu pra carregar a capa.')),
      );
    }
  }
}
