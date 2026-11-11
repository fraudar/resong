// language: Dart, file: lib/screens/search_screen.dart, target: mobile-first + desktop, runtime: resong app
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons_flutter/solar_icons_flutter.dart';

import '../core/theme.dart';
import '../state/library.dart';
import '../state/providers.dart';
import '../state/settings.dart';
import '../widgets/glass.dart';
import '../widgets/liquid_wave_backdrop.dart';
import '../widgets/sections.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.initialQuery = ''});

  final String initialQuery;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
    if (widget.initialQuery.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(searchProvider.notifier).changed(widget.initialQuery);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    ref.read(searchProvider.notifier).clear();
  }

  void _submit(String value) {
    final q = value.trim();
    if (q.isEmpty) return;
    _controller.text = q;
    _controller.selection = TextSelection.collapsed(offset: q.length);
    ref.read(searchProvider.notifier).changed(q);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final state = ref.watch(searchProvider);
    final palette = ref.watch(currentPaletteProvider);
    final playing = ref.watch(isPlayingProvider);
    final waveEnabled = ref.watch(settingsProvider.select((s) => s.waveEffectsEnabled));
    final canPop = Navigator.canPop(context);

    return Scaffold(
      backgroundColor: colors.bg,
      body: LiquidWaveBackdrop(
        palette: palette,
        intense: false,
        isPlaying: playing,
        animateAmbient: waveEnabled,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(canPop ? 8 : 20, 12, 20, 6),
                child: Row(
                  children: [
                    if (canPop) ...[
                      GlassCircleButton(
                        icon: SolarIconsBold.altArrowLeft,
                        size: 42,
                        iconSize: 20,
                        onTap: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: GlassSurface(
                        borderRadius: BorderRadius.circular(22),
                        blur: 20,
                        child: TextField(
                          controller: _controller,
                          onChanged: ref.read(searchProvider.notifier).changed,
                          onSubmitted: _submit,
                          textInputAction: TextInputAction.search,
                          textCapitalization: TextCapitalization.sentences,
                          style: TextStyle(color: colors.textPrimary),
                          decoration: InputDecoration(
                            filled: false,
                            hintText: 'Faixas, álbuns, artistas…',
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            prefixIcon: Padding(
                              padding: const EdgeInsets.only(left: 14, right: 10),
                              child: Icon(SolarIconsBold.magnifier, size: 20, color: colors.textTertiary),
                            ),
                            prefixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 0),
                            suffixIcon: state.query.isEmpty
                                ? null
                                : IconButton(
                                    icon: Icon(SolarIconsBold.close, size: 18, color: colors.textTertiary),
                                    onPressed: _clear,
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: _body(context, state)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, SearchState state) {
    final colors = context.colors;
    final query = state.query.trim();

    if (query.isEmpty) {
      return const _Hint(
        icon: SolarIconsBold.magnifier,
        title: 'O que vamos ouvir?',
        subtitle: 'Busque por música, artista, álbum, playlist ou link do Spotify.',
      );
    }

    if (state.loading) return const Center(child: CircularProgressIndicator());

    final results = state.results;
    if (results == null) {
      if (state.suggestions.isEmpty) {
        return const _Hint(
          icon: SolarIconsBold.musicNote,
          title: 'Digite para buscar',
          subtitle: 'Sugestões aparecem aqui enquanto você escreve.',
        );
      }
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 170),
        children: [
          Text(
            'Sugestões',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colors.textTertiary, letterSpacing: 0.4),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 9,
            runSpacing: 9,
            children: [
              for (final s in state.suggestions)
                ActionChip(
                  avatar: Icon(SolarIconsBold.magnifier, size: 15, color: colors.textSecondary),
                  label: Text(s, style: TextStyle(fontSize: 13, color: colors.textPrimary)),
                  backgroundColor: colors.glassFill,
                  side: BorderSide(color: colors.stroke),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  onPressed: () => _submit(s),
                ),
            ],
          ),
        ],
      );
    }

    if (results.isEmpty) {
      return _Hint(
        icon: SolarIconsBold.closeCircle,
        title: 'Nada encontrado',
        subtitle: 'Nada para “$query” — tente outro nome ou artista.',
      );
    }

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        if (results.artists.isNotEmpty)
          SliverToBoxAdapter(
            child: MediaRail(
              label: 'Artistas',
              children: [for (final a in results.artists) MediaCard(kind: MediaKind.artist, artist: a)],
            ),
          ),
        if (results.tracks.isNotEmpty)
          SliverToBoxAdapter(child: TrackListSection(title: 'Faixas', tracks: results.tracks)),
        if (results.albums.isNotEmpty)
          SliverToBoxAdapter(
            child: MediaRail(
              label: 'Álbuns',
              children: [for (final a in results.albums) MediaCard(kind: MediaKind.album, album: a)],
            ),
          ),
        if (results.playlists.isNotEmpty)
          SliverToBoxAdapter(
            child: MediaRail(
              label: 'Playlists',
              children: [for (final p in results.playlists) MediaCard(kind: MediaKind.playlist, playlist: p)],
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 170)),
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.title, required this.subtitle});
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
