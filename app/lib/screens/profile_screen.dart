// language: Dart, file: lib/screens/profile_screen.dart, target: mobile-first + desktop, runtime: resong app
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons_flutter/solar_icons_flutter.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/local_image.dart';
import '../core/models.dart';
import '../core/palette.dart';
import '../core/theme.dart';
import '../state/library.dart';
import '../state/providers.dart';
import '../state/scrobbles.dart';
import '../state/settings.dart';
import '../widgets/artwork.dart';
import '../widgets/glass.dart';
import '../widgets/liquid_wave_backdrop.dart';
import 'detail_screen.dart';
import 'player_screen.dart';
import 'settings_screen.dart';

/// Perfil editorial e compartilhável: identidade musical, artistas favoritos em destaque,
/// faixas em rotação, modo privado e cartão pronto para compartilhar gostos musicais.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final palette = ref.watch(currentPaletteProvider);
    final accent = palette.accentFor(colors.isDark);
    final playing = ref.watch(isPlayingProvider);
    final settings = ref.watch(settingsProvider);
    final waveEnabled = settings.waveEffectsEnabled;
    final isPrivate = settings.profilePrivate;
    final currentTrack = ref.watch(currentTrackProvider);

    final identity = ref.watch(profileIdentityProvider);
    final scrobbles = ref.watch(scrobblesProvider);
    final favorites = ref.watch(favoritesProvider);

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final monthScrobbles = scrobbles.where((e) => (nowMs - e.playedAtMs) <= 30 * 86400000).toList();
    final showcaseSource = monthScrobbles.isNotEmpty ? monthScrobbles : scrobbles;

    final topArtists = computeTopArtists(showcaseSource, limit: 6);
    final topTracks = computeTopTracks(showcaseSource, limit: 4);
    final uniqueArtists = {
      for (final e in scrobbles)
        if (e.track.artists.isNotEmpty) e.track.artists.first.trim(),
    }.length;
    final minutesListened = computeListeningMinutes(scrobbles);
    final streakDays = computeListeningStreakDays(scrobbles);

    final avatarBytes = isPrivate ? null : identity.avatarBytes;
    final topPad = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: colors.bg,
      body: LiquidWaveBackdrop(
        palette: palette,
        intense: false,
        isPlaying: playing,
        animateAmbient: waveEnabled,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              slivers: [
                SliverToBoxAdapter(child: SizedBox(height: topPad + 10)),
                // Barra superior limpa
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 16, 8),
                    child: Row(
                      children: [
                        Text(
                          'Perfil',
                          style: Theme.of(context).textTheme.displayMedium?.copyWith(fontSize: 25),
                        ),
                        const Spacer(),
                        if (!isPrivate) ...[
                          GlassCircleButton(
                            icon: SolarIconsBold.share,
                            size: 38,
                            iconSize: 17,
                            tooltip: 'Compartilhar perfil',
                            onTap: () => _openShareCard(
                              context,
                              identity: identity,
                              palette: palette,
                              totalScrobbles: scrobbles.length,
                              minutesListened: minutesListened,
                              uniqueArtists: uniqueArtists,
                              topArtists: topArtists,
                              topTracks: topTracks,
                              avatarBytes: avatarBytes,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        GlassCircleButton(
                          icon: SolarIconsBold.settings,
                          size: 38,
                          iconSize: 18,
                          tooltip: 'Configurações',
                          onTap: () => SettingsScreen.open(context),
                        ),
                      ],
                    ),
                  ),
                ),
                // Cabeçalho editorial centralizado
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 14, 24, 6),
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: () => _editProfile(context, ref, identity),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                width: 84,
                                height: 84,
                                padding: const EdgeInsets.all(2.5),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [accent, accent.withValues(alpha: 0.25)],
                                  ),
                                ),
                                child: ClipOval(
                                  child: avatarBytes != null
                                      ? Image.memory(
                                          avatarBytes,
                                          width: 79,
                                          height: 79,
                                          fit: BoxFit.cover,
                                          gaplessPlayback: true,
                                        )
                                      : DecoratedBox(
                                          decoration: BoxDecoration(color: accent.withValues(alpha: 0.22)),
                                          child: Center(
                                            child: isPrivate
                                                ? Icon(SolarIconsBold.lock, size: 28, color: colors.textPrimary)
                                                : Text(
                                                    identity.name.isEmpty ? 'R' : identity.name.characters.first.toUpperCase(),
                                                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: colors.textPrimary),
                                                  ),
                                          ),
                                        ),
                                ),
                              ),
                              Positioned(
                                right: -2,
                                bottom: -2,
                                child: Container(
                                  width: 26,
                                  height: 26,
                                  decoration: BoxDecoration(
                                    color: colors.bgElevated,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: colors.stroke, width: 1),
                                  ),
                                  child: Icon(SolarIconsBold.pen2, size: 12, color: colors.textSecondary),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          identity.name,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          identity.bio,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: colors.textSecondary, height: 1.35),
                        ),
                      ],
                    ),
                  ),
                ),
                if (isPrivate)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                      child: GlassSurface(
                        borderRadius: BorderRadius.circular(24),
                        blur: 22,
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            Icon(SolarIconsBold.lock, size: 36, color: accent),
                            const SizedBox(height: 14),
                            Text(
                              'Perfil privado',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Só você vê o que escuta. Métricas, artistas e histórico ficam ocultos enquanto o modo privado estiver ativo.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 13, color: colors.textSecondary, height: 1.4),
                            ),
                            const SizedBox(height: 18),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: colors.heroPillBg,
                                foregroundColor: colors.heroPillFg,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                              ),
                              onPressed: () => ref.read(settingsProvider.notifier).setProfilePrivate(false),
                              icon: const Icon(SolarIconsBold.lockUnlocked, size: 17),
                              label: const Text('Tornar perfil público', style: TextStyle(fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else ...[
                  // Linha limpa de métricas + streak + ouvindo agora
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 6),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _InlineMetric(value: '${scrobbles.length}', label: 'scrobbles'),
                              _MetricDivider(color: colors.stroke),
                              _InlineMetric(value: '$minutesListened', label: 'min'),
                              _MetricDivider(color: colors.stroke),
                              _InlineMetric(value: '$uniqueArtists', label: 'artistas'),
                              _MetricDivider(color: colors.stroke),
                              _InlineMetric(value: '${favorites.length}', label: 'curtidas'),
                            ],
                          ),
                          if (streakDays > 0) ...[
                            const SizedBox(height: 12),
                            Text(
                              '$streakDays ${streakDays == 1 ? 'dia seguido ouvindo' : 'dias seguidos ouvindo'}',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: accent),
                            ),
                          ],
                          if (currentTrack != null) ...[
                            const SizedBox(height: 14),
                            InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () => PlayerScreen.open(context, ref, initialTrack: currentTrack),
                              child: GlassSurface(
                                borderRadius: BorderRadius.circular(20),
                                blur: 18,
                                tint: accent,
                                tintStrength: 0.22,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(SolarIconsBold.soundwave, size: 14, color: accent),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        'Ouvindo ${currentTrack.title} • ${currentTrack.artistLine}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colors.textPrimary),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  // Mosaico visual de artistas favoritos (mês)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text('Artistas do meu som', style: Theme.of(context).textTheme.titleLarge),
                          ),
                          if (topArtists.isNotEmpty)
                            TextButton.icon(
                              onPressed: () => _openShareCard(
                                context,
                                identity: identity,
                                palette: palette,
                                totalScrobbles: scrobbles.length,
                                minutesListened: minutesListened,
                                uniqueArtists: uniqueArtists,
                                topArtists: topArtists,
                                topTracks: topTracks,
                                avatarBytes: avatarBytes,
                              ),
                              icon: Icon(SolarIconsBold.share, size: 15, color: accent),
                              label: Text('Cartão', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: accent)),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (topArtists.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          'Ouça algumas faixas até a metade para montar sua vitrine de gostos.',
                          style: TextStyle(fontSize: 13, color: colors.textTertiary),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 14,
                          childAspectRatio: 0.78,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, i) {
                            final a = topArtists[i];
                            return InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(builder: (_) => DetailScreen.searchFor(a.name)),
                              ),
                              child: Column(
                                children: [
                                  AspectRatio(
                                    aspectRatio: 1,
                                    child: LayoutBuilder(
                                      builder: (_, box) => Artwork(
                                        url: a.artwork,
                                        size: box.maxWidth,
                                        radius: 18,
                                        tone: accent,
                                        icon: SolarIconsBold.user,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    a.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: colors.textPrimary),
                                  ),
                                  Text(
                                    '${a.plays} ${a.plays == 1 ? 'play' : 'plays'}',
                                    maxLines: 1,
                                    style: TextStyle(fontSize: 10.5, color: colors.textTertiary),
                                  ),
                                ],
                              ),
                            );
                          },
                          childCount: topArtists.length,
                        ),
                      ),
                    ),
                  // Faixas em rotação
                  if (topTracks.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 26, 20, 8),
                        child: Text('Em rotação no mês', style: Theme.of(context).textTheme.titleLarge),
                      ),
                    ),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) {
                          final stat = topTracks[i];
                          return InkWell(
                            onTap: () => _playFromProfile(
                              context,
                              ref,
                              [for (final item in topTracks) item.track],
                              i,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
                              child: Row(
                                children: [
                                  Artwork(url: stat.track.artwork, size: 46, radius: 12, tone: accent),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          stat.track.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: colors.textPrimary),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          stat.track.artistLine,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(fontSize: 12.5, color: colors.textSecondary),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    '${stat.plays}×',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: accent,
                                      fontFeatures: const [FontFeature.tabularFigures()],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                        childCount: topTracks.length,
                      ),
                    ),
                  ],
                  // Últimas tocadas (enxuto, máx 5)
                  if (scrobbles.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                        child: Text('Ouvidas por último', style: Theme.of(context).textTheme.titleLarge),
                      ),
                    ),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) {
                          final entry = scrobbles[i];
                          return InkWell(
                            onTap: () => _playFromProfile(
                              context,
                              ref,
                              [for (final e in scrobbles.take(20)) e.track],
                              i,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                              child: Row(
                                children: [
                                  Artwork(url: entry.track.artwork, size: 38, radius: 10, tone: accent),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      '${entry.track.title} — ${entry.track.artistLine}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 13.5, color: colors.textPrimary),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    formatWhen(entry.playedAtMs),
                                    style: TextStyle(fontSize: 11, color: colors.textTertiary),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                        childCount: scrobbles.length.clamp(0, 5),
                      ),
                    ),
                  ],
                  // Ação discreta de privacidade e limpeza de histórico no rodapé do perfil
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 12,
                        runSpacing: 6,
                        children: [
                          TextButton.icon(
                            onPressed: () => ref.read(settingsProvider.notifier).setProfilePrivate(true),
                            icon: Icon(SolarIconsBold.lock, size: 15, color: colors.textTertiary),
                            label: Text('Deixar privado', style: TextStyle(fontSize: 12, color: colors.textTertiary)),
                          ),
                          if (scrobbles.isNotEmpty)
                            TextButton.icon(
                              onPressed: () => _confirmClearHistory(context, ref),
                              icon: Icon(SolarIconsLinear.trashBinTrash, size: 15, color: colors.textTertiary),
                              label: Text('Limpar histórico', style: TextStyle(fontSize: 12, color: colors.textTertiary)),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 170)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _playFromProfile(BuildContext context, WidgetRef ref, List<Track> list, int index) async {
    if (list.isEmpty) return;
    final downloads = ref.read(downloadsProvider);
    final target = list[index];
    final handler = ref.read(handlerProvider);
    final loadFuture = handler.load(
      list,
      start: index,
      urlFor: (t) => resolvePlaybackUrl(t, downloads),
    );
    if (ref.read(settingsProvider).openPlayerOnTap && context.mounted) {
      PlayerScreen.open(context, ref, initialTrack: target);
    }
    try {
      await loadFuture;
    } catch (_) {
      // Silencia interrupção rápida ao trocar de faixa.
    }
  }

  Future<void> _openShareCard(
    BuildContext context, {
    required ProfileIdentity identity,
    required ArtworkPalette palette,
    required int totalScrobbles,
    required int minutesListened,
    required int uniqueArtists,
    required List<ArtistStat> topArtists,
    required List<TrackStat> topTracks,
    required Uint8List? avatarBytes,
  }) async {
    final colors = context.colors;
    final accent = palette.accentFor(colors.isDark);
    final topArtistNames = [for (final a in topArtists.take(3)) a.name];
    final topTrackNames = [for (final t in topTracks.take(3)) '${t.track.title} (${t.track.artistLine})'];

    final shareText = StringBuffer()
      ..writeln('${identity.name} no resong')
      ..writeln('$totalScrobbles scrobbles • $minutesListened min • $uniqueArtists artistas')
      ..writeln()
      ..writeln(topArtistNames.isEmpty ? 'Ainda explorando novos artistas' : 'Top artistas: ${topArtistNames.join(', ')}')
      ..writeln(topTrackNames.isEmpty ? '' : 'Em rotação: ${topTrackNames.join(' • ')}');

    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      palette.backdropFor(true),
                      palette.secondaryFor(true),
                      const Color(0xFF0A0B0F),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 32, offset: const Offset(0, 16)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        if (avatarBytes != null)
                          ClipOval(
                            child: Image.memory(
                              avatarBytes,
                              width: 52,
                              height: 52,
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                            ),
                          )
                        else
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: accent.withValues(alpha: 0.25),
                            ),
                            child: Center(
                              child: Text(
                                identity.name.isEmpty ? 'R' : identity.name.characters.first.toUpperCase(),
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
                              ),
                            ),
                          ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                identity.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
                              ),
                              Text(
                                '$totalScrobbles scrobbles • $minutesListened min',
                                style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.72)),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Text(
                            'resong',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    if (topArtists.isNotEmpty) ...[
                      Text(
                        'TOP ARTISTAS',
                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: Colors.white.withValues(alpha: 0.62)),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          for (final a in topArtists.take(3))
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Column(
                                  children: [
                                    Artwork(url: a.artwork, size: 64, radius: 14, tone: accent, icon: SolarIconsBold.user),
                                    const SizedBox(height: 5),
                                    Text(
                                      a.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.white),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                    if (topTracks.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        'EM ROTAÇÃO',
                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: Colors.white.withValues(alpha: 0.62)),
                      ),
                      const SizedBox(height: 8),
                      for (final t in topTracks.take(3))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Text(
                            '${t.track.title} — ${t.track.artistLine}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.90)),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: colors.heroPillBg,
                        foregroundColor: colors.heroPillFg,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: shareText.toString().trim()));
                        if (sheetContext.mounted) Navigator.pop(sheetContext);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Resumo do perfil copiado para compartilhar')),
                          );
                        }
                      },
                      icon: const Icon(SolarIconsBold.copy, size: 18),
                      label: const Text('Copiar resumo', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<String?> _encodeProfilePhoto(Uint8List rawBytes) async {
    final compact = await compressLocalCoverBytes(
      rawBytes,
      targetWidth: 256,
      maxBytes: kMaxLocalCoverBytes,
    );
    if (compact == null || compact.isEmpty) return null;
    return base64Encode(compact);
  }

  Future<void> _confirmClearHistory(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Limpar histórico de escutas?'),
        content: const Text('Remove todas as reproduções e métricas registradas neste dispositivo.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Limpar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(scrobblesProvider.notifier).clear();
    await ref.read(recentProvider.notifier).clear();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Histórico de escutas apagado')),
      );
    }
  }

  Future<void> _editProfile(BuildContext context, WidgetRef ref, ProfileIdentity current) async {
    final nameCtrl = TextEditingController(text: current.name);
    final bioCtrl = TextEditingController(text: current.bio);
    final colors = context.colors;
    String? draftAvatarBase64 = current.avatarBase64;
    var clearAvatar = false;
    var pickingPhoto = false;
    var savingProfile = false;
    String? photoError;
    String? nameError;

    Uint8List? decodeDraft() {
      if (clearAvatar || draftAvatarBase64 == null || draftAvatarBase64!.isEmpty) return null;
      try {
        return base64Decode(draftAvatarBase64!);
      } catch (_) {
        return null;
      }
    }

    ({String name, String bio})? validatedResult;

    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocalState) {
          final previewBytes = decodeDraft();
          final previewName = nameCtrl.text.trim().isEmpty ? current.name : nameCtrl.text.trim();
          return AlertDialog(
            title: const Text('Editar perfil'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      ClipOval(
                        child: previewBytes != null
                            ? Image.memory(
                                previewBytes,
                                width: 64,
                                height: 64,
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                              )
                            : Container(
                                width: 64,
                                height: 64,
                                color: colors.accent.withValues(alpha: 0.22),
                                child: Center(
                                  child: Text(
                                    previewName.isEmpty ? 'R' : previewName.characters.first.toUpperCase(),
                                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: colors.textPrimary),
                                  ),
                                ),
                              ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            OutlinedButton.icon(
                              onPressed: pickingPhoto
                                  ? null
                                  : () async {
                                      setLocalState(() {
                                        pickingPhoto = true;
                                        photoError = null;
                                      });
                                      try {
                                        final picked = await FilePicker.pickFile(
                                          type: FileType.image,
                                        );
                                        final bytes = picked == null ? null : await picked.readAsBytes();
                                        if (bytes != null && bytes.isNotEmpty) {
                                          final encoded = await _encodeProfilePhoto(bytes);
                                          if (dialogContext.mounted) {
                                            setLocalState(() {
                                              if (encoded != null) {
                                                draftAvatarBase64 = encoded;
                                                clearAvatar = false;
                                              } else {
                                                photoError = 'Imagem acima do limite (512 KB). Tente uma menor.';
                                              }
                                            });
                                          }
                                        }
                                      } catch (_) {
                                        if (dialogContext.mounted) {
                                          setLocalState(() => photoError = 'Não deu pra carregar a foto.');
                                        }
                                      } finally {
                                        if (dialogContext.mounted) {
                                          setLocalState(() => pickingPhoto = false);
                                        }
                                      }
                                    },
                              icon: pickingPhoto
                                  ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(SolarIconsBold.gallery, size: 17),
                              label: Text(previewBytes != null ? 'Trocar foto' : 'Escolher foto'),
                            ),
                            if (previewBytes != null)
                              TextButton.icon(
                                onPressed: () => setLocalState(() {
                                  draftAvatarBase64 = null;
                                  clearAvatar = true;
                                  photoError = null;
                                }),
                                icon: Icon(SolarIconsBold.close, size: 15, color: colors.textTertiary),
                                label: Text('Remover foto', style: TextStyle(fontSize: 12, color: colors.textTertiary)),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (photoError != null) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(photoError!, style: TextStyle(fontSize: 12, color: colors.danger)),
                    ),
                  ],
                  const SizedBox(height: 14),
                  TextField(
                    controller: nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    onChanged: (_) => setLocalState(() => nameError = null),
                    decoration: InputDecoration(
                      labelText: 'Nome de exibição',
                      errorText: nameError,
                      errorStyle: TextStyle(color: colors.danger, fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: bioCtrl,
                    maxLines: 2,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(labelText: 'Bio'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: savingProfile ? null : () => Navigator.pop(dialogContext),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: colors.accent, foregroundColor: Colors.white),
                onPressed: savingProfile
                    ? null
                    : () async {
                        setLocalState(() {
                          savingProfile = true;
                          nameError = null;
                        });
                        final nameRes = await Api.instance.validateIdentity(nameCtrl.text);
                        if (!dialogContext.mounted) return;
                        if (!nameRes.ok) {
                          setLocalState(() {
                            savingProfile = false;
                            nameError = nameRes.reason ?? 'Nome inválido.';
                          });
                          return;
                        }
                        validatedResult = (
                          name: nameRes.value,
                          bio: bioCtrl.text,
                        );
                        Navigator.pop(dialogContext);
                      },
                child: savingProfile
                    ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Salvar'),
              ),
            ],
          );
        },
      ),
    );

    if (validatedResult != null) {
      await ref.read(profileIdentityProvider.notifier).update(
            name: validatedResult!.name,
            bio: validatedResult!.bio,
            avatarBase64: draftAvatarBase64,
            clearAvatar: clearAvatar,
          );
    }
    nameCtrl.dispose();
    bioCtrl.dispose();
  }
}

class _InlineMetric extends StatelessWidget {
  const _InlineMetric({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 11),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 16.5,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _MetricDivider extends StatelessWidget {
  const _MetricDivider({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(width: 1, height: 22, color: color);
}
