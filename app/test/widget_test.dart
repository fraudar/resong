// language: Dart, file: test/widget_test.dart, target: any, runtime: resong app
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resong/core/api.dart';
import 'package:resong/core/audio_tags.dart';
import 'package:resong/core/format.dart';
import 'package:resong/core/md5.dart';
import 'package:resong/core/models.dart';
import 'package:resong/core/palette.dart';
import 'package:resong/core/theme.dart';
import 'package:resong/engine/local_engine_io.dart';
import 'package:resong/screens/audio_fx_sheet.dart';
import 'package:resong/screens/detail_screen.dart';
import 'package:resong/screens/home_screen.dart';
import 'package:resong/screens/player_screen.dart';
import 'package:resong/screens/profile_screen.dart';
import 'package:resong/screens/queue_screen.dart';
import 'package:resong/screens/settings_screen.dart';
import 'package:resong/screens/shell.dart';
import 'package:resong/state/audio_fx.dart';
import 'package:resong/state/library.dart';
import 'package:resong/state/lyrics_cache.dart';
import 'package:resong/state/player.dart';
import 'package:resong/state/providers.dart';
import 'package:resong/state/scrobbles.dart';
import 'package:resong/state/settings.dart';
import 'package:resong/widgets/artwork.dart';
import 'package:resong/widgets/collection_hero_layout.dart';
import 'package:resong/widgets/flight.dart';
import 'package:resong/widgets/glass.dart';
import 'package:resong/widgets/liquid_wave_backdrop.dart';
import 'package:resong/widgets/sections.dart';
import 'package:resong/widgets/track_tile.dart';
import 'package:resong/widgets/volume_control.dart';
import 'package:resong/widgets/wave_seek_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solar_icons_flutter/solar_icons_flutter.dart';

void main() {
  test('formatDuration cobre null, minutos e horas', () {
    expect(formatDuration(null), '');
    expect(formatDuration(0), '');
    expect(formatDuration(95000), '1:35');
    expect(formatDuration(3723000), '1:02:03');
  });

  test('formatBytes usa unidades legíveis', () {
    expect(formatBytes(null), '');
    expect(formatBytes(512), '512 B');
    expect(formatBytes(2048), '2.0 KB');
    expect(formatBytes(3450000), '3.3 MB');
  });

  test('formatWhen devolve tempo relativo', () {
    expect(formatWhen(0), '');
    expect(formatWhen(DateTime.now().millisecondsSinceEpoch - 30000), 'agora');
    expect(formatWhen(DateTime.now().millisecondsSinceEpoch - 5 * 60000), 'há 5 min');
  });

  test('parseLrc suporta offset e múltiplos timestamps na mesma linha', () {
    const raw = '''
[offset:+500]
[00:05.00] Primeira linha
[00:12.00][00:30.50] Refrão repetido
''';
    final lines = parseLrc(raw);
    expect(lines.length, 3);
    expect(lines[0].at, const Duration(milliseconds: 4500));
    expect(lines[0].text, 'Primeira linha');
    expect(lines[1].at, const Duration(milliseconds: 11500));
    expect(lines[1].text, 'Refrão repetido');
    expect(lines[2].at, const Duration(milliseconds: 30000));
    expect(lines[2].text, 'Refrão repetido');

    expect(activeLrcIndex(lines, const Duration(seconds: 4)), -1);
    expect(activeLrcIndex(lines, const Duration(seconds: 5)), 0);
    expect(activeLrcIndex(lines, const Duration(seconds: 31)), 2);
  });

  test('ArtworkPalette adapta tons para tema Black e Light e interpola corretamente', () {
    const teal = ArtworkPalette(
      accent: Color(0xFF39A0BD),
      backdrop: Color(0xFF174353),
      secondary: Color(0xFF0E2C38),
      highlight: Color(0xFF5DC4DE),
    );
    const amber = ArtworkPalette(
      accent: Color(0xFFE09A42),
      backdrop: Color(0xFF6B4722),
      secondary: Color(0xFF472E16),
      highlight: Color(0xFFF3B86A),
    );

    expect(teal.backdropFor(true).computeLuminance(), lessThan(0.15));
    expect(teal.backdropFor(false).computeLuminance(), greaterThan(0.50));
    expect(amber.accentFor(true), isNot(equals(amber.accentFor(false))));

    final mid = ArtworkPalette.lerp(teal, amber, 0.5);
    expect(mid.backdrop, isNot(equals(teal.backdrop)));
    expect(mid.backdrop, isNot(equals(amber.backdrop)));
  });

  test('Cálculo de scrobbles agrega top artistas, top faixas, minutos e streak', () {
    final now = DateTime.now().millisecondsSinceEpoch;
    const t1 = Track(id: 'yt:1', source: 'ytmusic', title: 'Gasoline', artists: ['The Weeknd'], durationMs: 210000);
    const t2 = Track(id: 'yt:2', source: 'ytmusic', title: 'Out of Time', artists: ['The Weeknd'], durationMs: 210000);
    const t3 = Track(id: 'yt:3', source: 'ytmusic', title: 'Human Nature', artists: ['Michael Jackson'], durationMs: 240000);

    final entries = [
      ScrobbleEntry(track: t1, playedAtMs: now),
      ScrobbleEntry(track: t1, playedAtMs: now - 10000),
      ScrobbleEntry(track: t2, playedAtMs: now - 20000),
      ScrobbleEntry(track: t3, playedAtMs: now - 86400000),
    ];

    final artists = computeTopArtists(entries);
    expect(artists.first.name, 'The Weeknd');
    expect(artists.first.plays, 3);
    expect(artists.last.name, 'Michael Jackson');
    expect(artists.last.plays, 1);

    final tracks = computeTopTracks(entries);
    expect(tracks.first.track.id, 'yt:1');
    expect(tracks.first.plays, 2);

    expect(computeListeningMinutes(entries), 15);
    expect(computeListeningStreakDays(entries), 2);

    final week = computeWeeklyActivity(entries);
    expect(week.length, 7);
    expect(week.last.isToday, isTrue);
    expect(week.last.plays, 3);
  });

  testWidgets('SettingsScreen remove servidor/conexão e Scrobble, exibe Fontes/Privacidade e alterna tema', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final fakeHandler = ResongHandler();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          handlerProvider.overrideWithValue(fakeHandler),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            final mode = ref.watch(themeModeProvider);
            return MaterialApp(
              themeMode: mode,
              theme: AppTheme.light(),
              darkTheme: AppTheme.black(),
              home: const SettingsScreen(),
            );
          },
        ),
      ),
    );

    final container = ProviderScope.containerOf(tester.element(find.byType(SettingsScreen)));
    await container.read(settingsProvider.notifier).setWaveEffects(false);
    await tester.pumpAndSettle();

    expect(find.text('Configurações'), findsOneWidget);
    expect(find.text('API do resong'), findsNothing);
    expect(find.text('Chave Bearer (opcional)'), findsNothing);
    expect(find.text('Token do ListenBrainz'), findsNothing);
    expect(find.text('Conta Last.fm'), findsNothing);
    expect(find.text('Limpar histórico de scrobbles'), findsNothing);

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(container.read(themeModeProvider), ThemeMode.light);
    expect(Theme.of(tester.element(find.byType(SettingsScreen))).brightness, Brightness.light);

    await tester.scrollUntilVisible(find.text('Adicionar addon'), 250, scrollable: find.byType(Scrollable).first);
    expect(find.text('Adicionar addon'), findsOneWidget);
    expect(find.text('YouTube Music'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Spotify'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Spotify'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Audius'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Audius'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Internet Archive'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Internet Archive'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Perfil privado'), 250, scrollable: find.byType(Scrollable).first);
    expect(find.text('Pasta de downloads'), findsOneWidget);
    expect(find.text('Token do ListenBrainz'), findsNothing);
    expect(find.text('Conta Last.fm'), findsNothing);
    expect(find.text('Perfil privado'), findsOneWidget);
    expect(find.text('Apagar todos os dados'), findsNothing);
    expect(find.text('Apagar dados'), findsNothing);

    await tester.scrollUntilVisible(find.text('Limpar histórico de escutas'), 200, scrollable: find.byType(Scrollable).first);
    await container.read(scrobblesProvider.notifier).record(
          const Track(id: 'yt:hist1', source: 'ytmusic', title: 'Track Historico', artists: ['Artista']),
        );
    await tester.pump();
    expect(container.read(scrobblesProvider).length, 1);

    await tester.tap(find.text('Limpar histórico de escutas'));
    await tester.pumpAndSettle();
    expect(find.text('Limpar histórico de escutas?'), findsOneWidget);
    await tester.tap(find.text('Limpar'));
    await tester.pumpAndSettle();
    expect(container.read(scrobblesProvider), isEmpty);
  });

  testWidgets('ProfileScreen oculta estatísticas no modo privado e alterna de volta sem opção de apagar dados', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final fakeHandler = ResongHandler();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          handlerProvider.overrideWithValue(fakeHandler),
        ],
        child: MaterialApp(
          theme: AppTheme.black(),
          home: const ProfileScreen(),
        ),
      ),
    );

    final container = ProviderScope.containerOf(tester.element(find.byType(ProfileScreen)));
    await container.read(settingsProvider.notifier).setWaveEffects(false);
    await container.read(settingsProvider.notifier).setProfilePrivate(true);
    await tester.pumpAndSettle();

    expect(find.text('Perfil privado'), findsOneWidget);
    expect(find.text('Apagar todos os dados'), findsNothing);
    expect(find.text('Artistas do meu som'), findsNothing);

    await tester.tap(find.text('Tornar perfil público'));
    await tester.pumpAndSettle();
    expect(find.text('Artistas do meu som'), findsOneWidget);
    expect(find.text('Deixar privado'), findsOneWidget);
    expect(find.text('Apagar dados'), findsNothing);
  });

  test('ProfileIdentity usa apenas nome de exibição e persiste avatarBase64', () async {
    SharedPreferences.setMockInitialValues({});
    final ctrl = ProfileIdentityController();
    await ctrl.update(
      name: 'Igor',
      bio: 'Testando avatar',
      avatarBase64: 'AQIDBA==',
    );
    expect(ctrl.state.name, 'Igor');
    expect(ctrl.state.avatarBase64, 'AQIDBA==');
    expect(ctrl.state.avatarBytes, orderedEquals(const [1, 2, 3, 4]));

    await ctrl.update(
      name: 'Igor',
      bio: 'Sem foto',
      clearAvatar: true,
    );
    expect(ctrl.state.avatarBase64, isNull);
    expect(ctrl.state.avatarBytes, isNull);
  });

  testWidgets('QueueScreen renderiza contador Fila · tocando i/N e itens', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final fakeHandler = ResongHandler();
    fakeHandler.tracks.addAll(const [
      Track(id: 'yt:a', source: 'ytmusic', title: 'Gasoline', artists: ['The Weeknd']),
      Track(id: 'yt:b', source: 'ytmusic', title: 'Sacrifice', artists: ['The Weeknd']),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          handlerProvider.overrideWithValue(fakeHandler),
        ],
        child: MaterialApp(
          theme: AppTheme.black(),
          home: const QueueScreen(),
        ),
      ),
    );

    final container = ProviderScope.containerOf(tester.element(find.byType(QueueScreen)));
    await container.read(settingsProvider.notifier).setWaveEffects(false);
    await tester.pumpAndSettle();

    expect(find.text('Fila · tocando 1/2'), findsOneWidget);
    expect(find.text('Gasoline'), findsOneWidget);
    expect(find.text('Sacrifice'), findsOneWidget);
  });

  testWidgets('MediaRail com título longo em 2 linhas não causa overflow', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.black(),
          home: Scaffold(
            body: MediaRail(
              label: 'Playlists em alta',
              children: const [
                MediaCard(
                  kind: MediaKind.playlist,
                  playlist: PlaylistRef(
                    id: 'ytpl:1',
                    source: 'ytmusic',
                    title: 'Lançamentos 2026 da Semana: Top 100 Sertanejo Universitário e Pop',
                    owner: 'Músicas Mais Tocadas • 3,9 mi de visualizações',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  });

  testWidgets('LiquidWaveBackdrop anima transição de cor sem erros em Black e Light', (tester) async {
    const p1 = ArtworkPalette(
      accent: Color(0xFF39A0BD),
      backdrop: Color(0xFF174353),
      secondary: Color(0xFF0E2C38),
      highlight: Color(0xFF5DC4DE),
    );
    const p2 = ArtworkPalette(
      accent: Color(0xFFE09A42),
      backdrop: Color(0xFF6B4722),
      secondary: Color(0xFF472E16),
      highlight: Color(0xFFF3B86A),
    );

    ArtworkPalette active = p1;
    ThemeData theme = AppTheme.black();

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => MaterialApp(
          theme: theme,
          home: Scaffold(
            body: LiquidWaveBackdrop(
              palette: active,
              intense: true,
              animateAmbient: false,
              child: Center(
                child: TextButton(
                  onPressed: () => setState(() {
                    active = p2;
                    theme = AppTheme.light();
                  }),
                  child: const Text('Trocar'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Trocar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 650));
    await tester.pump(const Duration(milliseconds: 800));
    expect(tester.takeException(), isNull);
  });

  testWidgets('CollectionHeroLayout renderiza capa mesclada, título e botões de controle', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.black(),
          home: CollectionHeroLayout(
            palette: ArtworkPalette.fallback,
            artworkUrl: null,
            fallbackIcon: SolarIconsBold.album,
            title: 'Dawn FM',
            subtitle: 'The Weeknd',
            meta: '2022 • 16 faixas',
            isPlayingWaves: false,
            isCollectionPlaying: false,
            onPlayPause: () {},
            onShuffle: () {},
            trailingIcon: SolarIconsBold.downloadMinimalistic,
            onTrailingTap: () {},
            onMenuTap: () {},
            slivers: const [
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Gasoline'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Dawn FM'), findsOneWidget);
    expect(find.text('The Weeknd'), findsOneWidget);
    expect(find.text('Tocar'), findsOneWidget);
    expect(find.text('Gasoline'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('WaveSeekBar desenha onda no trecho reproduzido e responde ao toque e arraste', (tester) async {
    Duration? sought;
    Duration? scrubbed;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.black(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: WaveSeekBar(
                position: const Duration(seconds: 45),
                duration: const Duration(seconds: 180),
                isPlaying: true,
                animateWave: false,
                activeColor: Colors.tealAccent,
                inactiveColor: Colors.white24,
                onScrubUpdate: (d) => scrubbed = d,
                onSeek: (d) => sought = d,
              ),
            ),
          ),
        ),
      ),
    );

    final seekBox = find.byType(WaveSeekBar);
    await tester.tapAt(tester.getCenter(seekBox));
    await tester.pump();
    expect(sought, isNotNull);
    expect(sought!.inSeconds, closeTo(90, 6));

    await tester.drag(seekBox, const Offset(80, 0));
    await tester.pump();
    expect(scrubbed, isNull);
    expect(sought, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('PlayerScreen exibe capa quadrada 1:1 arredondada, WaveSeekBar e dock vidro sem overflow', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final fakeHandler = ResongHandler();
    const track = Track(
      id: 'yt:husn',
      source: 'ytmusic',
      title: 'Husn',
      artists: ['Anuv Jain'],
      album: 'Husn',
      durationMs: 217000,
    );
    fakeHandler.tracks.add(track);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          handlerProvider.overrideWithValue(fakeHandler),
        ],
        child: MaterialApp(
          theme: AppTheme.black(),
          home: const PlayerScreen(initialTrack: track),
        ),
      ),
    );

    final container = ProviderScope.containerOf(tester.element(find.byType(PlayerScreen)));
    await container.read(settingsProvider.notifier).setWaveEffects(false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final artworkSize = tester.getSize(find.byType(Artwork));
    expect(artworkSize.width, closeTo(artworkSize.height, 0.01));
    expect(artworkSize.width, greaterThanOrEqualTo(150));

    expect(find.text('Tocando agora'), findsOneWidget);
    expect(find.text('Husn'), findsOneWidget);
    expect(find.text('Anuv Jain • Husn'), findsOneWidget);
    // Sem letra sincronizada, a pílula placeholder não é exibida (Backlog 13a)
    expect(find.text('Letras sincronizadas'), findsNothing);
    expect(find.byType(WaveSeekBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('md5Hex, hmacMd5Hex e sanitizeHandleLocal validam hashes e handles com segurança', () {
    expect(md5Hex(''), 'd41d8cd98f00b204e9800998ecf8427e');
    expect(md5Hex('abc'), '900150983cd24fb0d6963f7d28e17f72');
    expect(
      hmacMd5Hex('key', 'The quick brown fox jumps over the lazy dog'),
      '80070713463e7749b90c2dc24911e275',
    );
    final good = sanitizeHandleLocal('  @Igor\u200B\u202E_Silva  ');
    expect(good.ok, isTrue);
    expect(good.value, '@Igor_Silva');
    expect(sanitizeHandleLocal('...').ok, isFalse);
    expect(sanitizeHandleLocal('x').ok, isFalse);
    expect(sanitizeHandleLocal('a<script>').ok, isFalse);
  });

  test('SourcesSnapshot decodifica addons BitChord e fontes nativas', () {
    final snap = SourcesSnapshot.fromJson({
      'sources': [
        {
          'id': 'qobuz-1',
          'base_url': 'https://qobuz.exemplo',
          'label': 'Qobuz Lossless',
          'ordem': 0,
          'enabled': true,
          'allow_downloads': false,
          'quality_options': ['FLAC', 'HIGH'],
          'last_status': 'ok',
        },
      ],
      'native_sources': [
        {'id': 'ytmusic', 'label': 'YouTube Music'},
      ],
    });
    expect(snap.sources.length, 1);
    expect(snap.sources.first.label, 'Qobuz Lossless');
    expect(snap.sources.first.allowDownloads, isFalse);
    expect(snap.sources.first.qualityOptions, ['FLAC', 'HIGH']);
    expect(snap.nativeSources.first.id, 'ytmusic');
  });

  test('SonoraFlightRegistry aplica janela 300ms, limiar >0.5px e pouso spring <0.01px', () {
    final base = DateTime(2026, 11, 11, 12, 0, 0);
    expect(SonoraFlightRegistry.isOriginFresh(base, base.add(const Duration(milliseconds: 250))), isTrue);
    expect(SonoraFlightRegistry.isOriginFresh(base, base.add(const Duration(milliseconds: 350))), isFalse);

    const r1 = Rect.fromLTWH(20, 600, 38, 38);
    const rMicro = Rect.fromLTWH(20.2, 600.2, 38, 38);
    const rBig = Rect.fromLTWH(40, 120, 280, 280);
    expect(SonoraFlightRegistry.hasMovedEnough(r1, rMicro), isFalse);
    expect(SonoraFlightRegistry.hasMovedEnough(r1, rBig), isTrue);

    final sim = SonoraFlightRegistry.createSpring(r1, rBig);
    expect(sim.isDone(0.05), isFalse);
    expect(sim.isDone(2.0), isTrue);
    expect((sim.x(2.0) - 1.0).abs(), lessThan(0.01));
  });

  testWidgets('FlightElement anima transição entre rotas com SonoraRouteObserver', (tester) async {
    SonoraFlightRegistry.instance.clear();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [SonoraRouteObserver.instance],
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: GestureDetector(
                onTap: () => Navigator.of(context).push(
                  PageRouteBuilder<void>(
                    pageBuilder: (_, __, ___) => Scaffold(
                      body: Align(
                        alignment: Alignment.topCenter,
                        child: FlightElement(
                          tag: 'test-art',
                          borderRadius: BorderRadius.circular(26),
                          child: const SizedBox(width: 220, height: 220, child: ColoredBox(color: Colors.teal)),
                        ),
                      ),
                    ),
                  ),
                ),
                child: FlightElement(
                  tag: 'test-art',
                  borderRadius: BorderRadius.circular(11),
                  child: const SizedBox(width: 40, height: 40, child: ColoredBox(color: Colors.teal)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(FlightElement));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  test('SettingsController persiste preferências locais sem chaves de scrobble externo', () async {
    SharedPreferences.setMockInitialValues({});
    final ctrl = SettingsController();
    await ctrl.setProfilePrivate(true);
    await ctrl.setCrossfadeSeconds(6);
    expect(ctrl.state.profilePrivate, isTrue);
    expect(ctrl.state.crossfadeSeconds, 6);
  });

  test('ResongHandler mantém faixa ativa exata ao reordenar/remover e LyricsCache não fixa falha null', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final handler = ResongHandler();
    const t0 = Track(id: 'yt:zero', source: 'ytmusic', title: 'Faixa Zero', artists: ['Artista A']);
    const t1 = Track(id: 'yt:um', source: 'ytmusic', title: 'Faixa Um', artists: ['Artista B']);
    const t2 = Track(id: 'yt:dois', source: 'ytmusic', title: 'Faixa Dois', artists: ['Artista C']);

    handler.tracks.addAll([t0, t1, t2]);
    expect(handler.currentIndex, 0);
    expect(handler.currentTrack?.id, 'yt:zero');

    // Move a faixa ativa do índice 0 para o índice 2 sem tocar em setAudioSources/índice errado.
    await handler.reorderQueue(0, 2);
    expect(handler.currentIndex, 2);
    expect(handler.currentTrack?.id, 'yt:zero');

    // Remove item anterior da fila: faixa ativa acompanha deslocamento (2 -> 1) e mantém mesma ID.
    await handler.removeFromQueue(0);
    expect(handler.tracks.length, 2);
    expect(handler.currentIndex, 1);
    expect(handler.currentTrack?.id, 'yt:zero');

    const badTrack = Track(id: 'yt:inexistente-cache-test', source: 'ytmusic', title: '', artists: []);
    final res = await LyricsCache.instance.getOrFetch(badTrack);
    expect(res, isNull);
    expect(LyricsCache.instance.hasCached('yt:inexistente-cache-test'), isFalse);
  });

  testWidgets('PlayerScreen mantém botões Prev/Play/Next proporcionais e compactos', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final fakeHandler = ResongHandler();
    const track = Track(
      id: 'yt:btn-test',
      source: 'ytmusic',
      title: 'Ele Quer Ser Eu',
      artists: ['Henrique e Juliano'],
      durationMs: 198000,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          handlerProvider.overrideWithValue(fakeHandler),
        ],
        child: MaterialApp(
          theme: AppTheme.black(),
          home: const PlayerScreen(initialTrack: track),
        ),
      ),
    );
    final container = ProviderScope.containerOf(tester.element(find.byType(PlayerScreen)));
    await container.read(settingsProvider.notifier).setWaveEffects(false);
    await tester.pumpAndSettle();

    final playBtn = tester.widget<GlassSquircleButton>(
      find.byWidgetPredicate((w) => w is GlassSquircleButton && (w.tooltip == 'Tocar' || w.tooltip == 'Pausar')),
    );
    final prevBtn = tester.widget<GlassSquircleButton>(
      find.byWidgetPredicate((w) => w is GlassSquircleButton && w.tooltip == 'Anterior'),
    );
    final nextBtn = tester.widget<GlassSquircleButton>(
      find.byWidgetPredicate((w) => w is GlassSquircleButton && w.tooltip == 'Próxima'),
    );

    expect(playBtn.width, lessThanOrEqualTo(66));
    expect(prevBtn.width, lessThanOrEqualTo(52));
    expect(nextBtn.width, lessThanOrEqualTo(52));
  });

  test('AudioTags embute ID3v2.3 (MP3) e átomos MP4 (M4A) com deslocamento de stco + capa', () {
    const track = Track(
      id: 'yt:tag-test',
      source: 'ytmusic',
      title: 'Faixa Local',
      artists: ['Artista 1', 'Artista 2'],
      album: 'Disco X',
      extra: {'year': '2026'},
    );
    final fakeCover = Uint8List.fromList([0xFF, 0xD8, 0xFF, ...List.filled(70, 0xAB)]);

    // 1) MP3
    final rawMp3 = Uint8List.fromList([0xFF, 0xFB, 0x90, 0x64, ...List.filled(32, 0x11)]);
    final taggedMp3 = AudioTags.write(
      audioBytes: rawMp3,
      ext: 'mp3',
      track: track,
      coverBytes: fakeCover,
    );
    expect(latin1.decode(taggedMp3.sublist(0, 3)), 'ID3');
    final mp3Text = latin1.decode(taggedMp3, allowInvalid: true);
    expect(mp3Text, contains('TIT2'));
    expect(mp3Text, contains('TPE1'));
    expect(mp3Text, contains('TALB'));
    expect(mp3Text, contains('TYER'));
    expect(mp3Text, contains('COMM'));
    expect(mp3Text, contains('APIC'));
    expect(mp3Text, contains('image/jpeg'));
    expect(taggedMp3.sublist(taggedMp3.length - rawMp3.length), rawMp3);

    // 2) MP4 / M4A (moov antes de mdat: stco deve deslocar pelo novo tamanho do moov)
    Uint8List box(String type, List<int> body) {
      final b = BytesBuilder();
      final total = 8 + body.length;
      b.add([(total >> 24) & 0xFF, (total >> 16) & 0xFF, (total >> 8) & 0xFF, total & 0xFF]);
      b.add(ascii.encode(type));
      b.add(body);
      return b.takeBytes();
    }

    final stco = box('stco', [
      0, 0, 0, 0, // version/flags
      0, 0, 0, 1, // entry_count = 1
      0, 0, 0, 100, // chunk offset inicial = 100
    ]);
    final stbl = box('stbl', stco);
    final minf = box('minf', stbl);
    final mdia = box('mdia', minf);
    final trak = box('trak', mdia);
    final moov = box('moov', trak);
    final ftyp = box('ftyp', ascii.encode('M4A \x00\x00\x00\x00'));
    final mdat = box('mdat', List.filled(24, 0x55));

    final sampleMp4 = Uint8List.fromList([...ftyp, ...moov, ...mdat]);
    final taggedMp4 = AudioTags.write(
      audioBytes: sampleMp4,
      ext: 'm4a',
      track: track,
      coverBytes: fakeCover,
    );

    final mp4Ascii = latin1.decode(taggedMp4, allowInvalid: true);
    expect(mp4Ascii, contains('udta'));
    expect(mp4Ascii, contains('ilst'));
    expect(mp4Ascii, contains('Faixa Local'));
    expect(mp4Ascii, contains('baixado via resong'));
    expect(mp4Ascii, contains('covr'));

    // Confirma que `stco` deslocou +delta exatamente igual ao ganho do moov
    final stcoPos = mp4Ascii.indexOf('stco');
    expect(stcoPos, greaterThan(0));
    final shiftedOffset = ByteData.sublistView(taggedMp4, stcoPos + 12, stcoPos + 16).getUint32(0);
    expect(shiftedOffset, greaterThan(100));
    expect(shiftedOffset - 100, taggedMp4.length - sampleMp4.length);
  });

  test('SettingsController persiste downloadFolder e resolvePlaybackUrl prioriza arquivo local', () async {
    SharedPreferences.setMockInitialValues({});
    final ctrl = SettingsController();
    await ctrl.setDownloadFolder('/tmp/minhas_musicas');
    expect(ctrl.state.downloadFolder, '/tmp/minhas_musicas');

    await ctrl.setDownloadFolder('');
    expect(ctrl.state.downloadFolder, isEmpty);

    const tLocal = Track(id: 'yt:loc', source: 'ytmusic', title: 'Offline', artists: ['Art']);
    const tRemote = Track(id: 'yt:rem', source: 'ytmusic', title: 'Online', artists: ['Art']);
    final records = [
      DownloadRecord(
        trackId: 'yt:loc',
        track: tLocal,
        status: 'done',
        progress: 1.0,
        localPath: '/tmp/Offline.m4a',
        fileSize: 12345,
        createdAt: 1000,
      ),
    ];

    expect(resolvePlaybackUrl(tLocal, records), contains('file:///tmp/Offline.m4a'));
    expect(resolvePlaybackUrl(tRemote, records), contains('/api/stream/yt%3Arem'));
  });

  testWidgets('Backlog 13: letra some sem sync, título Space Grotesk, curtir sem card e listen_together em Glass', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final fakeHandler = ResongHandler();
    const track = Track(
      id: 'yt:backlog13-test',
      source: 'ytmusic',
      title: 'Título Display Space',
      artists: ['Artista Teste'],
      durationMs: 210000,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          handlerProvider.overrideWithValue(fakeHandler),
        ],
        child: MaterialApp(
          theme: AppTheme.black(),
          home: const PlayerScreen(initialTrack: track),
        ),
      ),
    );
    final container = ProviderScope.containerOf(tester.element(find.byType(PlayerScreen)));
    await container.read(settingsProvider.notifier).setWaveEffects(false);
    await tester.pumpAndSettle();

    // (a) Sem letra sincronizada, pílula e microfone não existem na árvore; com sync, aparece com microfone
    expect(find.text('Letras sincronizadas'), findsNothing);
    expect(find.byIcon(SolarIconsBold.microphone), findsNothing);

    LyricsCache.instance.debugSeedSynced('yt:backlog13-test', '[00:00.00] Verso ao vivo');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byIcon(SolarIconsBold.microphone), findsOneWidget);
    expect(find.text('Verso ao vivo'), findsOneWidget);

    // (b) Título em Space Grotesk 700
    final titleWidget = tester.widget<Text>(find.text('Título Display Space'));
    expect(titleWidget.style?.fontFamily, contains('SpaceGrotesk'));
    expect(titleWidget.style?.fontWeight, FontWeight.w700);
    expect(titleWidget.style?.letterSpacing, closeTo(-0.7, 0.01));

    // (c) Curtir sem card (sem GlassSquircleButton em volta do coração)
    final heartFinder = find.byIcon(SolarIconsLinear.heart);
    expect(heartFinder, findsOneWidget);
    expect(
      find.ancestor(of: heartFinder, matching: find.byType(GlassSquircleButton)),
      findsNothing,
    );

    // (e) Ouvir juntos / Sessões removidos no modo standalone local
    expect(find.byTooltip('Ouvir juntos'), findsNothing);
  });

  test('DownloadsController.load valida existência real do arquivo local no SharedPreferences', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final existingFile = File('${Directory.systemTemp.path}${Platform.pathSeparator}resong_ctrl_ok.m4a')
      ..writeAsBytesSync([0, 1, 2, 3]);
    addTearDown(() {
      if (existingFile.existsSync()) existingFile.deleteSync();
    });

    SharedPreferences.setMockInitialValues({
      'resong_local_downloads_v1': jsonEncode([
        {
          'track_id': 'yt:dl-ok',
          'track': {'id': 'yt:dl-ok', 'source': 'ytmusic', 'title': 'Existe', 'artists': ['Art']},
          'status': 'done',
          'progress': 1.0,
          'local_path': existingFile.path,
          'file_size': 4,
          'created_at': 1000,
        },
        {
          'track_id': 'yt:dl-missing',
          'track': {'id': 'yt:dl-missing', 'source': 'ytmusic', 'title': 'Sumiu', 'artists': ['Art']},
          'status': 'done',
          'progress': 1.0,
          'local_path': '${existingFile.path}.nao_existe',
          'file_size': 4,
          'created_at': 2000,
        },
      ]),
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final ctrl = container.read(downloadsProvider.notifier);
    await ctrl.load();

    final loaded = container.read(downloadsProvider);
    expect(loaded.length, 1);
    expect(loaded.first.trackId, 'yt:dl-ok');
    expect(loaded.first.hasPlayableLocal, isTrue);
  });

  testWidgets('Backlog 13(d/f): TrackTile exibe progresso/concluído e SonoraFlightRegistry aplica teto 40%', (tester) async {
    SharedPreferences.setMockInitialValues({});

    const tDone = Track(id: 'yt:dl-done', source: 'ytmusic', title: 'Pronta Offline', artists: ['Art']);
    const tProg = Track(id: 'yt:dl-prog', source: 'ytmusic', title: 'Baixando Agora', artists: ['Art']);
    final fakeHandler = ResongHandler();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          handlerProvider.overrideWithValue(fakeHandler),
        ],
        child: MaterialApp(
          theme: AppTheme.black(),
          home: const Scaffold(
            body: Column(
              children: [
                TrackTile(track: tDone, showFavorite: false),
                TrackTile(track: tProg, showFavorite: false),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold)));
    container.read(downloadsProvider.notifier).debugSetRecords([
      const DownloadRecord(
        trackId: 'yt:dl-done',
        track: tDone,
        status: 'done',
        progress: 1.0,
        localPath: '/tmp/Pronta.m4a',
        fileSize: 2048,
        createdAt: 1000,
      ),
      const DownloadRecord(
        trackId: 'yt:dl-prog',
        track: tProg,
        status: 'downloading',
        progress: 0.55,
        createdAt: 2000,
      ),
    ]);
    await tester.pump();

    expect(find.byIcon(SolarIconsBold.folderCheck), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('55'), findsOneWidget);

    // (f) Regra 2 do Flight: > 40% da diagonal da tela (800x600 => diag=1000 => teto=400)
    const screen = Size(800, 600);
    const originRect = Rect.fromLTWH(20, 20, 40, 40);
    const nearRect = Rect.fromLTWH(160, 140, 40, 40); // dist ~ 184 <= 400
    const farRect = Rect.fromLTWH(500, 500, 40, 40); // dist ~ 679 > 400
    expect(SonoraFlightRegistry.exceedsMaxDistance(originRect, nearRect, screen), isFalse);
    expect(SonoraFlightRegistry.exceedsMaxDistance(originRect, farRect, screen), isTrue);
  });

  testWidgets('Sleep timer usa GlassSurface + paleta ativa e Fontes inclui Spotify',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final fakeHandler = ResongHandler();
    const customPalette = ArtworkPalette(
      accent: Color(0xFFFF4D6D),
      backdrop: Color(0xFF280B18),
      secondary: Color(0xFFCC294B),
      highlight: Color(0xFFFFD6E0),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          handlerProvider.overrideWithValue(fakeHandler),
          currentPaletteProvider.overrideWith((_) => _FixedPaletteController(customPalette)),
        ],
        child: MaterialApp(
          theme: AppTheme.black(),
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: Column(
                children: [
                  ElevatedButton(
                    onPressed: () => showSleepTimerSheet(context, ref),
                    child: const Text('Abrir timer'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // 1. Sleep timer com Liquid Glass + paleta dinâmica e destaque ativo
    fakeHandler.setSleepTimer(null, atTrackEnd: true);
    await tester.tap(find.text('Abrir timer'));
    await tester.pumpAndSettle();

    final sleepGlass = tester.widgetList<GlassSurface>(find.byType(GlassSurface)).first;
    expect(sleepGlass.tint, customPalette.backdropFor(true));
    expect(find.text('Desativar timer'), findsOneWidget);
    expect(find.byIcon(SolarIconsBold.checkCircle), findsOneWidget);

    await tester.tap(find.text('Desativar timer'));
    await tester.pumpAndSettle();
    expect(fakeHandler.hasSleepTimer, isFalse);

    // 2. Parsing de fonte nativa Spotify no SourcesSnapshot
    final snap = SourcesSnapshot.fromJson({
      'sources': [],
      'native_sources': [
        {'id': 'ytmusic', 'label': 'YouTube Music', 'fixed': true},
        {'id': 'soundcloud', 'label': 'SoundCloud', 'fixed': true},
        {
          'id': 'spotify',
          'label': 'Spotify',
          'fixed': true,
          'configured': true,
          'enabled': true,
          'configurable': true,
          'client_id_preview': 'a28b41...',
        },
      ],
    });
    expect(snap.nativeSources.length, 3);
    final sp = snap.nativeSources.firstWhere((n) => n.id == 'spotify');
    expect(sp.configured, isTrue);
    expect(sp.enabled, isTrue);
    expect(sp.configurable, isTrue);
  });

  testWidgets('AudioFxSheet renderiza EQ/8D/Gapless/Normalization e Lyrics suportam Karaokê/Vocal de fundo/Romanização',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final fakeHandler = ResongHandler();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          handlerProvider.overrideWithValue(fakeHandler),
        ],
        child: MaterialApp(
          theme: AppTheme.black(),
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: Column(
                children: [
                  ElevatedButton(
                    onPressed: () => showAudioEffectsSheet(context, ref),
                    child: const Text('EQ'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // 1. AudioEffectsSheet matte + Estado (Equalizador, Som 8D, Gapless, Normalização)
    await tester.tap(find.text('EQ'));
    await tester.pumpAndSettle();
    expect(find.text('Equalizador'), findsOneWidget);
    expect(find.text('60 Hz'), findsOneWidget);
    expect(find.text('14 kHz'), findsOneWidget);
    expect(find.text('Som 8D'), findsWidgets);
    expect(find.byType(RotatedBox), findsNothing);
    await tester.tap(find.text('Som 8D').first);
    await tester.pump(const Duration(milliseconds: 120));
    tester.widget<ListView>(find.byType(ListView).first).controller!.jumpTo(450);
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('Gapless'), findsOneWidget);
    expect(find.text('Normalização'), findsOneWidget);

    final container = ProviderScope.containerOf(tester.element(find.text('Equalizador')));
    final fx = container.read(audioFxProvider);
    expect(fx.enabled, isTrue);
    expect(fx.spatial8d, isTrue);
    expect(fx.gapless, isTrue);
    expect(fx.normalization, isTrue);
    expect(fakeHandler.gaplessEnabled, isTrue);
    expect(fakeHandler.normalizationEnabled, isTrue);

    Navigator.pop(tester.element(find.text('Equalizador')));
    await tester.pump(const Duration(milliseconds: 350));

    // 3. Letras ricas: Enhanced LRC Karaoke + Vocal de fundo + Romanização offline
    final enhancedLyrics = Lyrics.fromJson({
      'plain': 'Sin city cold (Oh)',
      'synced': '[00:10.00] <00:10.00> Sin <00:10.40> city <00:10.80> cold (Oh)',
      'source': 'netease',
      'word_synced': true,
      'has_karaoke': true,
      'has_background': true,
    });
    final rich = resolveRichLines(enhancedLyrics);
    expect(rich.length, 1);
    expect(rich.first.leadText, 'Sin city cold');
    expect(rich.first.bgText, '(Oh)');
    expect(rich.first.words.length, 3);
    expect(rich.first.words.first.atMs, 10000);
    expect(wordsForKaraokeText('Hello world', const [], 1000, 3000).length, 2);

    expect(hasNonLatinScript('사랑해'), isTrue);
    expect(fallbackRomanize('사랑해'), 'saranghae');
  });

  test('ResongHandler volume/mute, shuffle 2-estados e isolamento ao trocar de faixa', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final loadedUris = <String>[];
    final playEvents = <String>[];
    var disposedCount = 0;
    var failUriPattern = 'none';

    const mainChannel = MethodChannel('com.ryanheise.just_audio.methods');
    const sessionChannel = MethodChannel('com.ryanheise.audio_session');
    const androidMgrChannel = MethodChannel('com.ryanheise.android_audio_manager');
    messenger.setMockMethodCallHandler(androidMgrChannel, (call) async => null);
    messenger.setMockMethodCallHandler(sessionChannel, (call) async {
      if (call.method == 'setActive') return true;
      if (call.method == 'getConfiguration') return <String, dynamic>{};
      return null;
    });

    void registerPlayerChannel(String id) {
      final playerCh = MethodChannel('com.ryanheise.just_audio.methods.$id');
      final eventsCh = EventChannel('com.ryanheise.just_audio.events.$id');
      final dataCh = EventChannel('com.ryanheise.just_audio.data.$id');
      MockStreamHandlerEventSink? eventsSink;

      messenger.setMockStreamHandler(
        eventsCh,
        MockStreamHandler.inline(
          onListen: (_, sink) {
            eventsSink = sink;
          },
          onCancel: (_) => eventsSink = null,
        ),
      );
      messenger.setMockStreamHandler(
        dataCh,
        MockStreamHandler.inline(onListen: (_, __) {}),
      );

      messenger.setMockMethodCallHandler(playerCh, (call) async {
        if (call.method == 'androidEqualizerGetParameters') {
          return <String, dynamic>{
            'parameters': <String, dynamic>{
              'minDecibels': -15.0,
              'maxDecibels': 15.0,
              'bands': <Map<String, dynamic>>[],
            },
          };
        }
        if (call.method == 'load') {
          final args = call.arguments as Map<dynamic, dynamic>;
          final msg = args['audioSource'] as Map<dynamic, dynamic>;
          final children = (msg['children'] as List?) ?? const [];
          final uri = children.isNotEmpty
              ? ((children.first as Map)['uri'] as String? ?? '')
              : (msg['uri'] as String? ?? '');
          loadedUris.add(uri);
          if (uri.contains(failUriPattern)) {
            throw PlatformException(code: '4', message: 'stream failed');
          }
          eventsSink?.success({
            'processingState': 3, // ready
            'updateTime': DateTime.now().millisecondsSinceEpoch,
            'updatePosition': 0,
            'bufferedPosition': 0,
            'duration': 180000000,
            'currentIndex': 0,
          });
          return <String, dynamic>{'duration': 180000000};
        }
        if (call.method == 'play') {
          playEvents.add(loadedUris.isEmpty ? '' : loadedUris.last);
          return <String, dynamic>{};
        }
        return <String, dynamic>{};
      });
    }

    messenger.setMockMethodCallHandler(mainChannel, (call) async {
      if (call.method == 'init') {
        final id = (call.arguments as Map)['id'] as String;
        registerPlayerChannel(id);
        return null;
      }
      if (call.method == 'disposePlayer') {
        disposedCount++;
        return <String, dynamic>{};
      }
      if (call.method == 'disposeAllPlayers') {
        return <String, dynamic>{};
      }
      return <String, dynamic>{};
    });

    addTearDown(() {
      messenger.setMockMethodCallHandler(mainChannel, null);
      messenger.setMockMethodCallHandler(sessionChannel, null);
      messenger.setMockMethodCallHandler(androidMgrChannel, null);
    });

    final handler = ResongHandler();
    // Shuffle sem 3º modo Smart/Sparkle
    expect(handler.shuffleMode, ShuffleMode.off);
    handler.cycleShuffle();
    expect(handler.shuffleMode, ShuffleMode.normal);
    handler.cycleShuffle();
    expect(handler.shuffleMode, ShuffleMode.off);
    handler.cycleShuffle();
    expect(handler.shuffleMode, ShuffleMode.normal);

    await handler.setVolume(0.45);
    expect(handler.volume, closeTo(0.45, 0.001));
    expect(handler.isMuted, isFalse);

    await handler.toggleMute();
    expect(handler.isMuted, isTrue);
    expect(handler.volume, 0.0);
    expect(handler.unmutedVolume, closeTo(0.45, 0.001));

    await handler.toggleMute();
    expect(handler.isMuted, isFalse);
    expect(handler.volume, closeTo(0.45, 0.001));

    const t1 = Track(id: 'yt:jetski', source: 'ytmusic', title: 'JETSKI', artists: ['Pedro Sampaio']);
    const t2 = Track(
      id: 'yt:quem_ama',
      source: 'ytmusic',
      title: 'Quem Ama Sempre Entende',
      artists: ['Henrique & Juliano'],
    );
    await handler.load([t1, t2], start: 0, autoplay: false);
    expect(loadedUris, isNotEmpty);
    expect(handler.currentTrack?.id, 'yt:jetski');
    expect(handler.loadedSourceTrackId, 'yt:jetski');

    // Simula falha no carregamento da próxima faixa: faixa anterior precisa ser descartada e nunca re-tocada
    failUriPattern = 'quem_ama';
    final playCountBefore = playEvents.length;
    await handler.skipToNext();
    expect(handler.currentTrack?.id, 'yt:quem_ama');
    expect(handler.loadedSourceTrackId, isNull);
    expect(disposedCount, greaterThan(0));

    // Mesmo se usuário apertar play enquanto source de t2 falhou, t1 jamais deve tocar
    await handler.play();
    expect(playEvents.length, playCountBefore);
  });

  testWidgets('Desktop mode Sonora renderiza sidebar sem Perfil/Config, Avatar menu sem Sessões e volume hover/mute',
      (tester) async {
    SharedPreferences.setMockInitialValues({'resong_wave_effects': false});
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final fakeHandler = ResongHandler();
    await fakeHandler.setVolume(0.65);
    fakeHandler.tracks.addAll(const [
      Track(id: 'yt:d1', source: 'ytmusic', title: 'The Wild Rover', artists: ['Traditional']),
      Track(id: 'yt:d2', source: 'ytmusic', title: 'Morning Mood', artists: ['Edvard Grieg']),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          handlerProvider.overrideWithValue(fakeHandler),
          homeProvider.overrideWith((ref) async => const HomeFeed()),
        ],
        child: MaterialApp(
          theme: AppTheme.black(),
          home: const Shell(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    // Sidebar esquerda Sonora sem Perfil/Configurações fixos (movidos para o menu do Avatar) e sem Sessões
    expect(find.text('resong'), findsOneWidget);
    expect(find.text('Início'), findsOneWidget);
    expect(find.text('Buscar'), findsOneWidget);
    expect(find.text('Sua Biblioteca'), findsOneWidget);
    expect(find.text('Favoritos'), findsOneWidget);
    expect(find.text('Perfil'), findsNothing);
    expect(find.text('Configurações'), findsNothing);
    expect(find.byTooltip('Sessões'), findsNothing);
    expect(find.text('The Wild Rover'), findsOneWidget);
    expect(find.byType(HoverVolumeControl), findsOneWidget);

    // Menu da foto/avatar no canto superior direito abre apenas Perfil e Configurações
    await tester.tap(find.byTooltip('Conta'));
    await tester.pumpAndSettle();
    expect(find.text('Perfil'), findsOneWidget);
    expect(find.text('Configurações'), findsOneWidget);
    expect(find.text('Membros da Sessão'), findsNothing);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    // Hover sobre volume na barra inferior revela Slider (via OverlayPortal) e clique muta/desmuta
    final barVolBtn = find.byTooltip('Mutar');
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(barVolBtn));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(Slider), findsWidgets);
    await gesture.moveTo(Offset.zero);
    await tester.pump(const Duration(milliseconds: 220));

    await tester.tap(find.byTooltip('Mutar'));
    await tester.pumpAndSettle();
    expect(fakeHandler.isMuted, isTrue);
    expect(fakeHandler.volume, 0.0);

    await tester.tap(find.byTooltip('Ativar som'));
    await tester.pumpAndSettle();
    expect(fakeHandler.isMuted, isFalse);
    expect(fakeHandler.volume, closeTo(0.65, 0.01));

    // Expande player desktop estilo Sonora
    await tester.tap(find.byTooltip('Expandir player'));
    await tester.pumpAndSettle();
    expect(find.text('The Wild Rover'), findsWidgets);
    expect(find.byTooltip('Letras'), findsWidgets);
    expect(find.byTooltip('Fila'), findsWidgets);

    // Passar o mouse sobre o ícone de volume no player revela o Slider de volume
    final playerVolFinder = find.byTooltip('Mutar').last;
    await gesture.moveTo(tester.getCenter(playerVolFinder));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(Slider), findsWidgets);

    // Alterna para painel direito da Fila (TOCANDO AGORA / A SEGUIR)
    await tester.tap(find.byTooltip('Fila').last);
    await tester.pumpAndSettle();
    expect(find.text('TOCANDO AGORA'), findsOneWidget);
    expect(find.text('Morning Mood'), findsOneWidget);

    // Alterna para painel Equalizador & Som 8D
    await tester.tap(find.byTooltip('Equalizador & 8D').last);
    await tester.pumpAndSettle();
    expect(find.text('Som 8D'), findsWidgets);
    expect(find.text('Graves'), findsWidgets);
  });

  testWidgets('Mobile (<860px) preserva layout original com MiniPlayer e pill inferior',
      (tester) async {
    SharedPreferences.setMockInitialValues({'resong_wave_effects': false});
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final fakeHandler = ResongHandler();
    fakeHandler.tracks.add(
      const Track(id: 'yt:m1', source: 'ytmusic', title: 'Mobile Track', artists: ['Artist']),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          handlerProvider.overrideWithValue(fakeHandler),
          homeProvider.overrideWith((ref) async => const HomeFeed()),
        ],
        child: MaterialApp(
          theme: AppTheme.black(),
          home: const Shell(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byType(HoverVolumeControl), findsNothing);
    expect(find.text('Mobile Track'), findsOneWidget);
    expect(find.text('Início'), findsOneWidget);
  });

  test('ArtistDetail decodifica all_tracks e DetailScreen.artistIdForTrack resolve YouTube, Spotify e nome', () {
    final detail = ArtistDetail.fromJson({
      'artist': {'id': 'ytar:UC123', 'source': 'ytmusic', 'name': 'Henrique & Juliano'},
      'top_tracks': [
        {'id': 'yt:1', 'source': 'ytmusic', 'title': 'Faixa 1', 'artists': ['Henrique & Juliano']},
      ],
      'all_tracks': [
        {'id': 'yt:1', 'source': 'ytmusic', 'title': 'Faixa 1', 'artists': ['Henrique & Juliano']},
        {'id': 'yt:2', 'source': 'ytmusic', 'title': 'Faixa 2', 'artists': ['Henrique & Juliano']},
        {'id': 'yt:3', 'source': 'ytmusic', 'title': 'Faixa 3', 'artists': ['Henrique & Juliano']},
      ],
      'sections': [],
    });
    expect(detail.topTracks.length, 1);
    expect(detail.allTracks.length, 3);

    expect(
      DetailScreen.artistIdForTrack(
        const Track(
          id: 'yt:a',
          source: 'ytmusic',
          title: 'X',
          artists: ['Henrique & Juliano'],
          extra: {'channel_id': 'UC123'},
        ),
      ),
      'ytar:UC123',
    );
    expect(
      DetailScreen.artistIdForTrack(
        const Track(
          id: 'sp:track:abc',
          source: 'spotify',
          title: 'Y',
          artists: ['Pedro Sampaio'],
          extra: {'artist_id': 'sp999'},
        ),
      ),
      'sp:artist:sp999',
    );
    expect(
      DetailScreen.artistIdForTrack(
        const Track(
          id: 'yt:no_cid',
          source: 'ytmusic',
          title: 'Z',
          artists: ['Pedro Sampaio', 'MC Meno K'],
        ),
        artistName: 'MC Meno K',
      ),
      'name:MC Meno K',
    );
  });

  testWidgets('Backlog 14: capa local de playlist prevalece sobre URL, TrackTile exibe badge de fonte e PlaylistCoversController persiste',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    // 1x1 PNG mínimo válido
    final tinyPng = Uint8List.fromList(base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
    ));

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final coverCtrl = container.read(playlistCoversProvider.notifier);
    final ok = await tester.runAsync(() => coverCtrl.setCover('pl-local-test', tinyPng));
    expect(ok, isTrue);
    expect(container.read(playlistCoversProvider)['pl-local-test'], isNotNull);

    // Rejeita imagem acima de 512 KB que não possa ser comprimida
    final oversized = Uint8List(600 * 1024);
    expect(await tester.runAsync(() => coverCtrl.setCover('pl-too-big', oversized)), isFalse);

    final fakeHandler = ResongHandler();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [handlerProvider.overrideWithValue(fakeHandler)],
        child: MaterialApp(
          theme: AppTheme.black(),
          home: Scaffold(
            body: Column(
              children: [
                Artwork(url: 'https://invalid.local/cover.jpg', localBytes: tinyPng, size: 48),
                const TrackTile(
                  track: Track(id: 'sp:track:1', source: 'spotify', title: 'Faixa Spotify', artists: ['Artista']),
                  showFavorite: false,
                ),
                const TrackTile(
                  track: Track(id: 'au:123', source: 'audius', title: 'Faixa Audius', artists: ['Creator']),
                  showFavorite: false,
                ),
                const TrackTile(
                  track: Track(id: 'ia:abc', source: 'archive', title: 'Faixa Archive', artists: ['Podington Bear']),
                  showFavorite: false,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Spotify'), findsOneWidget);
    expect(find.text('Audius'), findsOneWidget);
    expect(find.text('Archive'), findsOneWidget);

    await tester.runAsync(() => coverCtrl.removeCover('pl-local-test'));
    expect(container.read(playlistCoversProvider).containsKey('pl-local-test'), isFalse);
  });

  testWidgets('HomeScreen exibe biblioteca local e banner offline quando sem internet', (tester) async {
    SharedPreferences.setMockInitialValues({'resong_wave_effects': false});
    final fakeHandler = ResongHandler();
    const offlineTrack = Track(
      id: 'yt:offline-home',
      source: 'ytmusic',
      title: 'Música Offline Salva',
      artists: ['Artista Local'],
    );
    final dlFile = File('${Directory.systemTemp.path}${Platform.pathSeparator}resong_home_off.m4a')
      ..writeAsBytesSync([0, 1, 2, 3]);
    addTearDown(() {
      if (dlFile.existsSync()) dlFile.deleteSync();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          handlerProvider.overrideWithValue(fakeHandler),
          homeProvider.overrideWith((ref) => Future<HomeFeed>.error(Exception('sem rede'))),
          quickPicksProvider.overrideWith((ref) async => const <Track>[]),
        ],
        child: MaterialApp(
          theme: AppTheme.black(),
          home: const HomeScreen(),
        ),
      ),
    );
    final container = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
    container.read(downloadsProvider.notifier).state = [
      DownloadRecord(
        trackId: offlineTrack.id,
        track: offlineTrack,
        status: 'done',
        progress: 1.0,
        localPath: dlFile.path,
        fileSize: 4,
        createdAt: 1000,
      ),
    ];
    await tester.pumpAndSettle();

    expect(find.textContaining('Modo offline'), findsOneWidget);
    expect(find.text('Disponível offline'), findsOneWidget);
    expect(find.text('Música Offline Salva'), findsOneWidget);
  });

  test('LocalEngineServer inicia em loopback, atende /api/health e CRUD local de playlists/fontes', () async {
    final prevHttp = HttpOverrides.current;
    HttpOverrides.global = null;
    Api.instance.resetHttpAdapter();
    addTearDown(() {
      HttpOverrides.global = prevHttp;
      Api.instance.resetHttpAdapter();
    });

    final port = await LocalEngineServer.instance.start();
    addTearDown(() => LocalEngineServer.instance.stop());

    expect(port, greaterThan(0));
    expect(Api.instance.baseUrl, 'http://127.0.0.1:$port');
    expect(await Api.instance.health(), isTrue);

    final created = await Api.instance.createPlaylist('Offline Mix');
    expect(created.name, 'Offline Mix');

    final listed = await Api.instance.playlists();
    expect(listed.any((p) => p.id == created.id), isTrue);

    await Api.instance.deletePlaylist(created.id);
    final afterDelete = await Api.instance.playlists();
    expect(afterDelete.any((p) => p.id == created.id), isFalse);

    final snap = await Api.instance.sources();
    expect(snap.nativeSources.any((s) => s.id == 'ytmusic'), isTrue);
    expect(snap.nativeSources.any((s) => s.id == 'spotify'), isTrue);
  });
}

class _FixedPaletteController extends CurrentPaletteController {
  _FixedPaletteController(ArtworkPalette initial) {
    state = initial;
  }
}
