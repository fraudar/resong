// language: Dart, file: lib/screens/settings_screen.dart, target: mobile-first + desktop, runtime: resong app
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:solar_icons_flutter/solar_icons_flutter.dart';

import '../core/format.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../state/audio_fx.dart';
import '../state/library.dart';
import '../state/local_downloads_platform.dart';
import '../state/player.dart';
import '../state/providers.dart';
import '../state/scrobbles.dart';
import '../state/settings.dart';
import '../state/sources.dart';
import '../widgets/glass.dart';
import 'audio_fx_sheet.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final mono = colors.isDark ? Colors.white : const Color(0xFF14161A);
    final monoThumb = colors.isDark ? const Color(0xFF0E1014) : Colors.white;
    final bg = colors.isDark ? const Color(0xFF0A0B0D) : const Color(0xFFF6F7FA);
    final divider = Divider(height: 1, indent: 16, endIndent: 16, color: colors.stroke);
    final mode = ref.watch(themeModeProvider);
    final settings = ref.watch(settingsProvider);
    final fx = ref.watch(audioFxProvider);
    final handler = ref.watch(handlerProvider);
    ref.watch(playerModeProvider);
    ref.watch(sleepTimerProvider);
    final downloadsList = ref.watch(downloadsProvider).where((d) => d.isDone).toList();
    final downloadsCount = downloadsList.length;
    final downloadsBytes = downloadsList.fold<int>(0, (sum, d) => sum + (d.fileSize ?? 0));
    final scrobblesCount = ref.watch(scrobblesProvider).length;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 14, 16, 20),
                    child: Row(
                      children: [
                        IconButton(
                          icon: Icon(SolarIconsLinear.altArrowLeft, size: 20, color: colors.textPrimary),
                          tooltip: 'Voltar',
                          onPressed: () => Navigator.maybePop(context),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Configurações',
                          style: GoogleFonts.inter(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.4,
                            color: colors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Aparência
                SliverToBoxAdapter(
                  child: _SettingsSection(
                    title: 'Aparência',
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Tema do aplicativo',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colors.textPrimary),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'Alterne entre preto profundo (OLED) e claro.',
                                style: TextStyle(fontSize: 12, color: colors.textSecondary),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: _ThemeOptionTile(
                                      label: 'Black',
                                      icon: SolarIconsLinear.moon,
                                      selected: mode == ThemeMode.dark,
                                      onTap: () => ref.read(themeModeProvider.notifier).setMode(ThemeMode.dark),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _ThemeOptionTile(
                                      label: 'Light',
                                      icon: SolarIconsLinear.sun2,
                                      selected: mode == ThemeMode.light,
                                      onTap: () => ref.read(themeModeProvider.notifier).setMode(ThemeMode.light),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        divider,
                        SwitchListTile.adaptive(
                          value: settings.waveEffectsEnabled,
                          activeTrackColor: mono,
                          activeThumbColor: monoThumb,
                          title: Text('Ondas líquidas da capa', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: colors.textPrimary)),
                          subtitle: Text(
                            'Transição em ondas no player mobile',
                            style: TextStyle(fontSize: 12, color: colors.textSecondary),
                          ),
                          onChanged: (v) => ref.read(settingsProvider.notifier).setWaveEffects(v),
                        ),
                      ],
                    ),
                  ),
                ),
                // Reprodução
                SliverToBoxAdapter(
                  child: _SettingsSection(
                    title: 'Reprodução',
                    child: Column(
                      children: [
                        SwitchListTile.adaptive(
                          value: settings.openPlayerOnTap,
                          activeTrackColor: mono,
                          activeThumbColor: monoThumb,
                          title: Text('Abrir player ao tocar faixa', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: colors.textPrimary)),
                          subtitle: Text(
                            'Abre a tela cheia do player ao escolher uma música',
                            style: TextStyle(fontSize: 12, color: colors.textSecondary),
                          ),
                          onChanged: (v) => ref.read(settingsProvider.notifier).setOpenPlayerOnTap(v),
                        ),
                        divider,
                        SwitchListTile.adaptive(
                          value: settings.infiniteQueueEnabled,
                          activeTrackColor: mono,
                          activeThumbColor: monoThumb,
                          title: Text('Fila infinita', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: colors.textPrimary)),
                          subtitle: Text(
                            'Adiciona faixas parecidas automaticamente ao terminar a fila',
                            style: TextStyle(fontSize: 12, color: colors.textSecondary),
                          ),
                          onChanged: (v) => ref.read(settingsProvider.notifier).setInfiniteQueue(v),
                        ),
                        divider,
                        SwitchListTile.adaptive(
                          value: settings.autoSkipEnabled,
                          activeTrackColor: mono,
                          activeThumbColor: monoThumb,
                          title: Text('Auto-skip em falha (10 s)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: colors.textPrimary)),
                          subtitle: Text(
                            'Pula automaticamente se o stream travar por mais de 10 s',
                            style: TextStyle(fontSize: 12, color: colors.textSecondary),
                          ),
                          onChanged: (v) => ref.read(settingsProvider.notifier).setAutoSkip(v),
                        ),
                        divider,
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Transição suave (Crossfade)',
                                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: colors.textPrimary),
                                  ),
                                  const Spacer(),
                                  Text(
                                    settings.crossfadeSeconds == 0 ? 'Desligado' : '${settings.crossfadeSeconds} s',
                                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: colors.textSecondary),
                                  ),
                                ],
                              ),
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 2.2,
                                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4.5),
                                  activeTrackColor: mono,
                                  inactiveTrackColor: colors.stroke,
                                  thumbColor: mono,
                                ),
                                child: Slider(
                                  min: 0,
                                  max: 12,
                                  divisions: 12,
                                  value: settings.crossfadeSeconds.toDouble(),
                                  onChanged: (v) => ref.read(settingsProvider.notifier).setCrossfadeSeconds(v.round()),
                                ),
                              ),
                            ],
                          ),
                        ),
                        divider,
                        ListTile(
                          leading: Icon(SolarIconsLinear.shuffle, color: colors.textPrimary, size: 19),
                          title: Text('Modo aleatório', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: colors.textPrimary)),
                          trailing: Text(
                            handler.shuffle ? 'Ligado' : 'Desligado',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: colors.textSecondary),
                          ),
                          onTap: handler.toggleShuffle,
                        ),
                        divider,
                        ListTile(
                          leading: Icon(SolarIconsLinear.repeat, color: colors.textPrimary, size: 19),
                          title: Text('Repetição', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: colors.textPrimary)),
                          trailing: Text(
                            switch (handler.repeatMode) {
                              RepeatMode.off => 'Desligada',
                              RepeatMode.all => 'Fila toda',
                              RepeatMode.one => 'Faixa atual',
                            },
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: colors.textSecondary),
                          ),
                          onTap: handler.cycleRepeat,
                        ),
                        divider,
                        ListTile(
                          leading: Icon(SolarIconsLinear.tuning2, color: colors.textPrimary, size: 19),
                          title: Text('Equalizador, Som 8D e efeitos', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: colors.textPrimary)),
                          subtitle: Text(
                            fx.hasActiveEffects
                                ? (fx.spatial8d ? 'Som 8D ativo • Reverb & EQ' : 'Efeitos ativos')
                                : '5 bandas, 8D espacial, graves e reverb',
                            style: TextStyle(fontSize: 12, color: colors.textSecondary),
                          ),
                          trailing: Icon(SolarIconsLinear.altArrowRight, size: 16, color: colors.textTertiary),
                          onTap: () => showAudioEffectsSheet(context, ref),
                        ),
                        divider,
                        SwitchListTile.adaptive(
                          value: fx.gapless,
                          activeTrackColor: mono,
                          activeThumbColor: monoThumb,
                          title: Text('Gapless (reprodução contínua)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: colors.textPrimary)),
                          subtitle: Text(
                            'Pré-carrega a próxima faixa para tocar sem cortes entre músicas',
                            style: TextStyle(fontSize: 12, color: colors.textSecondary),
                          ),
                          onChanged: (v) => ref.read(audioFxProvider.notifier).setGapless(v),
                        ),
                        divider,
                        SwitchListTile.adaptive(
                          value: fx.normalization,
                          activeTrackColor: mono,
                          activeThumbColor: monoThumb,
                          title: Text('Normalização de volume (-14 LUFS)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: colors.textPrimary)),
                          subtitle: Text(
                            'Nivela o volume entre faixas diferentes e protege contra distorção',
                            style: TextStyle(fontSize: 12, color: colors.textSecondary),
                          ),
                          onChanged: (v) => ref.read(audioFxProvider.notifier).setNormalization(v),
                        ),
                        divider,
                        ListTile(
                          leading: Icon(SolarIconsLinear.clockCircle, color: colors.textPrimary, size: 19),
                          title: Text('Sleep timer', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: colors.textPrimary)),
                          trailing: Text(
                            _sleepLabel(handler),
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: colors.textSecondary),
                          ),
                          onTap: () => showSleepTimerSheet(context, ref),
                        ),
                      ],
                    ),
                  ),
                ),
                // Fontes (Addons BitChord + nativos)
                const SliverToBoxAdapter(
                  child: _SourcesSection(),
                ),
                // Downloads locais
                SliverToBoxAdapter(
                  child: _SettingsSection(
                    title: 'Downloads no dispositivo',
                    child: Column(
                      children: [
                        FutureBuilder<String>(
                          future: defaultDownloadFolderDisplay(),
                          builder: (context, snap) {
                            final fallbackLabel = snap.data ?? 'Música/resong';
                            final folderLabel = settings.downloadFolder.isNotEmpty
                                ? settings.downloadFolder
                                : fallbackLabel;
                            return ListTile(
                              leading: Icon(SolarIconsLinear.folderWithFiles, color: colors.textPrimary, size: 19),
                              title: Text('Pasta de downloads', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: colors.textPrimary)),
                              subtitle: Text(
                                folderLabel,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: colors.textSecondary),
                              ),
                              trailing: settings.downloadFolder.isNotEmpty
                                  ? IconButton(
                                      tooltip: 'Usar pasta padrão',
                                      icon: Icon(SolarIconsLinear.closeCircle, size: 18, color: colors.textSecondary),
                                      onPressed: () => ref.read(settingsProvider.notifier).setDownloadFolder(''),
                                    )
                                  : (canChooseLocalFolder
                                      ? Icon(SolarIconsLinear.altArrowRight, size: 16, color: colors.textTertiary)
                                      : null),
                              onTap: canChooseLocalFolder
                                  ? () async {
                                      final picked = await FilePicker.getDirectoryPath(
                                        dialogTitle: 'Escolha a pasta para downloads',
                                      );
                                      if (picked != null && picked.trim().isNotEmpty) {
                                        await ref.read(settingsProvider.notifier).setDownloadFolder(picked);
                                      }
                                    }
                                  : null,
                            );
                          },
                        ),
                        divider,
                        ListTile(
                          leading: Icon(SolarIconsLinear.folderCheck, color: colors.textPrimary, size: 19),
                          title: Text('Faixas offline no aparelho', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: colors.textPrimary)),
                          trailing: Text(
                            downloadsBytes > 0 ? '$downloadsCount • ${formatBytes(downloadsBytes)}' : '$downloadsCount',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: colors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Privacidade
                SliverToBoxAdapter(
                  child: _SettingsSection(
                    title: 'Privacidade',
                    child: Column(
                      children: [
                        SwitchListTile.adaptive(
                          value: settings.profilePrivate,
                          activeTrackColor: mono,
                          activeThumbColor: monoThumb,
                          title: Text('Perfil privado', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: colors.textPrimary)),
                          subtitle: Text(
                            'Oculta métricas, artistas e histórico na tela de Perfil',
                            style: TextStyle(fontSize: 12, color: colors.textSecondary),
                          ),
                          onChanged: (v) => ref.read(settingsProvider.notifier).setProfilePrivate(v),
                        ),
                        divider,
                        ListTile(
                          leading: Icon(SolarIconsLinear.trashBinTrash, color: colors.textPrimary),
                          title: Text(
                            'Limpar histórico de escutas',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: colors.textPrimary),
                          ),
                          subtitle: Text(
                            scrobblesCount == 0
                                ? 'Nenhuma reprodução registrada'
                                : '$scrobblesCount ${scrobblesCount == 1 ? 'reprodução registrada' : 'reproduções registradas'} neste dispositivo',
                            style: TextStyle(fontSize: 12, color: colors.textSecondary),
                          ),
                          trailing: Icon(SolarIconsLinear.altArrowRight, size: 18, color: colors.textTertiary),
                          onTap: () => _confirmClearHistory(context, ref),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                    child: Center(
                      child: Text(
                        'resong • v0.1.0',
                        style: TextStyle(fontSize: 12, color: colors.textTertiary),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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

  String _sleepLabel(ResongHandler handler) {
    if (handler.sleepAtTrackEnd) return 'Fim da faixa';
    final rem = handler.sleepRemaining;
    if (rem == null) return 'Desligado';
    final min = rem.inMinutes;
    final sec = rem.inSeconds % 60;
    return min > 0 ? '$min min' : '${sec}s';
  }
}

class _SourcesSection extends ConsumerWidget {
  const _SourcesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final mono = colors.isDark ? Colors.white : const Color(0xFF14161A);
    final monoThumb = colors.isDark ? const Color(0xFF0E1014) : Colors.white;
    final snapshot = ref.watch(sourcesProvider).valueOrNull ?? const SourcesSnapshot();
    final addons = snapshot.sources;
    final natives = snapshot.nativeSources;

    return _SettingsSection(
      title: 'Fontes',
      child: Column(
        children: [
          if (addons.isNotEmpty)
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: addons.length,
              onReorderItem: (oldIdx, newIdx) => ref.read(sourcesProvider.notifier).reorder(oldIdx, newIdx),
              itemBuilder: (context, i) {
                final src = addons[i];
                final statusColor = switch (src.lastStatus) {
                  'ok' => const Color(0xFF34D399),
                  'desatualizado' => const Color(0xFFFBBF24),
                  _ => colors.danger,
                };
                final statusLabel = switch (src.lastStatus) {
                  'ok' => 'ok',
                  'desatualizado' => 'desatualizado',
                  _ => 'inacessível',
                };
                return Column(
                  key: ValueKey('src:${src.id}'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                      child: Row(
                        children: [
                          ReorderableDragStartListener(
                            index: i,
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Icon(SolarIconsLinear.hamburgerMenu, size: 17, color: colors.textTertiary),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  src.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: colors.textPrimary),
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Container(
                                      width: 6.5,
                                      height: 6.5,
                                      decoration: BoxDecoration(shape: BoxShape.circle, color: statusColor),
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      src.allowDownloads ? statusLabel : '$statusLabel • sem download',
                                      style: TextStyle(fontSize: 11.5, color: colors.textSecondary),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            iconSize: 17,
                            tooltip: 'Testar conexão',
                            icon: Icon(SolarIconsLinear.refresh, color: colors.textSecondary),
                            onPressed: () => ref.read(sourcesProvider.notifier).checkHealth(src.id),
                          ),
                          Switch.adaptive(
                            value: src.enabled,
                            activeTrackColor: mono,
                            activeThumbColor: monoThumb,
                            onChanged: (v) => ref.read(sourcesProvider.notifier).toggleEnabled(src.id, v),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            iconSize: 17,
                            tooltip: 'Remover addon',
                            icon: Icon(SolarIconsLinear.trashBinMinimalistic, color: colors.textTertiary),
                            onPressed: () => ref.read(sourcesProvider.notifier).remove(src.id),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, indent: 16, endIndent: 16, color: colors.stroke),
                  ],
                );
              },
            ),
          ListTile(
            leading: Icon(SolarIconsLinear.plugCircle, color: colors.textPrimary, size: 19),
            title: Text('Adicionar addon', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: colors.textPrimary)),
            subtitle: Text(
              'Protocolo BitChord (cola URL raiz ou manifest.json)',
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
            trailing: Icon(SolarIconsLinear.addCircle, size: 19, color: colors.textPrimary),
            onTap: () => _askAddAddon(context, ref),
          ),
          for (final native in natives) ...[
            Divider(height: 1, indent: 16, endIndent: 16, color: colors.stroke),
            if (native.id == 'spotify')
              ListTile(
                dense: true,
                leading: Icon(SolarIconsLinear.musicNote, color: colors.textPrimary, size: 18),
                title: Text(native.label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: colors.textPrimary)),
                subtitle: Text(
                  native.configured
                      ? (native.enabled ? 'Ativo • catálogo + links (áudio via YT Music)' : 'Desativado • links públicos ainda funcionam')
                      : 'Links públicos ativos • configure a API pra busca completa',
                  style: TextStyle(fontSize: 11.5, color: colors.textSecondary),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      iconSize: 17,
                      tooltip: 'Configurar Spotify',
                      icon: Icon(SolarIconsLinear.settings, color: colors.textSecondary),
                      onPressed: () => _askConfigureSpotify(context, ref, native),
                    ),
                    if (native.configured)
                      Switch.adaptive(
                        value: native.enabled,
                        activeTrackColor: mono,
                        activeThumbColor: monoThumb,
                        onChanged: (v) async {
                          try {
                            await ref.read(sourcesProvider.notifier).configureSpotify(enabled: v);
                          } catch (_) {}
                        },
                      ),
                  ],
                ),
                onTap: () => _askConfigureSpotify(context, ref, native),
              )
            else if (native.toggleable)
              SwitchListTile.adaptive(
                dense: true,
                value: native.enabled,
                activeTrackColor: mono,
                activeThumbColor: monoThumb,
                secondary: Icon(SolarIconsLinear.musicNote, color: colors.textPrimary, size: 18),
                title: Text(native.label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: colors.textPrimary)),
                subtitle: Text(
                  native.id == 'audius'
                      ? 'Streaming gratuito • sem autenticação'
                      : 'Catálogo aberto • áudio MP3 direto',
                  style: TextStyle(fontSize: 11.5, color: colors.textSecondary),
                ),
                onChanged: (v) async {
                  try {
                    await ref.read(sourcesProvider.notifier).toggleNative(native.id, v);
                  } catch (_) {}
                },
              )
            else
              ListTile(
                dense: true,
                leading: Icon(SolarIconsLinear.musicNote, color: colors.textPrimary, size: 18),
                title: Text(native.label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: colors.textPrimary)),
                trailing: Text('Nativa • fixa', style: TextStyle(fontSize: 11.5, color: colors.textTertiary)),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _askConfigureSpotify(
    BuildContext context,
    WidgetRef ref,
    NativeSourceInfo native,
  ) async {
    final idCtrl = TextEditingController();
    final secretCtrl = TextEditingController();
    var busy = false;
    String? errorMsg;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocalState) => AlertDialog(
          title: const Text('Configurar Spotify'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                native.configured
                    ? 'Spotify conectado (${native.clientIdPreview ?? 'credenciais salvas'}). Cole novas chaves para substituir ou limpe.'
                    : 'Crie um app em developer.spotify.com/dashboard e cole o Client ID e Client Secret. O áudio é tocado via YT Music.',
                style: TextStyle(fontSize: 12.5, color: context.colors.textSecondary),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: idCtrl,
                decoration: const InputDecoration(
                  labelText: 'Client ID',
                  hintText: 'Ex: a28b4142832a...',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: secretCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Client Secret',
                ),
              ),
              if (errorMsg != null) ...[
                const SizedBox(height: 10),
                Text(errorMsg!, style: TextStyle(fontSize: 12, color: context.colors.danger)),
              ],
            ],
          ),
          actions: [
            if (native.configured)
              TextButton(
                onPressed: busy
                    ? null
                    : () async {
                        setLocalState(() {
                          busy = true;
                          errorMsg = null;
                        });
                        try {
                          await ref.read(sourcesProvider.notifier).configureSpotify(clearCredentials: true);
                          if (dialogContext.mounted) Navigator.pop(dialogContext);
                        } catch (e) {
                          setLocalState(() {
                            busy = false;
                            errorMsg = '$e';
                          });
                        }
                      },
                child: Text('Limpar', style: TextStyle(color: context.colors.danger)),
              ),
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: context.colors.isDark ? Colors.white : const Color(0xFF14161A),
                foregroundColor: context.colors.isDark ? const Color(0xFF0E1014) : Colors.white,
              ),
              onPressed: busy
                  ? null
                  : () async {
                      final clientId = idCtrl.text.trim();
                      final clientSecret = secretCtrl.text.trim();
                      if (clientId.isEmpty || clientSecret.isEmpty) {
                        setLocalState(() => errorMsg = 'Informe Client ID e Client Secret');
                        return;
                      }
                      setLocalState(() {
                        busy = true;
                        errorMsg = null;
                      });
                      try {
                        await ref.read(sourcesProvider.notifier).configureSpotify(
                              clientId: clientId,
                              clientSecret: clientSecret,
                              enabled: true,
                            );
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      } catch (e) {
                        setLocalState(() {
                          busy = false;
                          errorMsg = '$e';
                        });
                      }
                    },
              child: busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
    idCtrl.dispose();
    secretCtrl.dispose();
  }

  Future<void> _askAddAddon(BuildContext context, WidgetRef ref) async {
    final urlCtrl = TextEditingController();
    final labelCtrl = TextEditingController();
    var busy = false;
    String? errorMsg;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocalState) => AlertDialog(
          title: const Text('Adicionar fonte addon'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: urlCtrl,
                autofocus: true,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'URL do addon',
                  hintText: 'https://meu-addon.exemplo/manifest.json',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: labelCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nome personalizado (opcional)',
                ),
              ),
              if (errorMsg != null) ...[
                const SizedBox(height: 10),
                Text(errorMsg!, style: TextStyle(fontSize: 12, color: context.colors.danger)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: context.colors.isDark ? Colors.white : const Color(0xFF14161A),
                foregroundColor: context.colors.isDark ? const Color(0xFF0E1014) : Colors.white,
              ),
              onPressed: busy
                  ? null
                  : () async {
                      final url = urlCtrl.text.trim();
                      if (url.isEmpty) {
                        setLocalState(() => errorMsg = 'Cole a URL do addon');
                        return;
                      }
                      setLocalState(() {
                        busy = true;
                        errorMsg = null;
                      });
                      try {
                        await ref.read(sourcesProvider.notifier).add(url, label: labelCtrl.text);
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      } catch (e) {
                        setLocalState(() {
                          busy = false;
                          errorMsg = 'Falha ao validar addon: $e';
                        });
                      }
                    },
              child: busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Testar e salvar'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showSleepTimerSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.48),
    builder: (_) => const _SleepTimerSheet(),
  );
}

class _SleepTimerSheet extends ConsumerWidget {
  const _SleepTimerSheet();

  String _formatRemaining(Duration remaining) {
    final totalSecs = remaining.inSeconds;
    final mins = totalSecs ~/ 60;
    final secs = totalSecs % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final palette = ref.watch(currentPaletteProvider);
    final accent = palette.accentFor(colors.isDark);
    final backdropTint = palette.backdropFor(colors.isDark);
    final secondaryTint = palette.secondaryFor(colors.isDark);
    final handler = ref.watch(handlerProvider);
    ref.watch(sleepTimerProvider);

    final remaining = handler.sleepRemaining;

    return GlassSurface(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      blur: 28,
      tint: backdropTint,
      tintStrength: 0.44,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.stroke,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(SolarIconsBold.clockCircle, size: 22, color: accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Sleep timer', style: Theme.of(context).textTheme.titleLarge),
                  ),
                  if (handler.hasSleepTimer)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: accent.withValues(alpha: 0.42)),
                      ),
                      child: Text(
                        handler.sleepAtTrackEnd
                            ? 'Fim da faixa'
                            : (remaining != null ? _formatRemaining(remaining) : 'Ativo'),
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: accent),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              GlassSurface(
                borderRadius: BorderRadius.circular(20),
                blur: 18,
                tint: secondaryTint,
                tintStrength: 0.24,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final mins in const [15, 30, 45, 60]) ...[
                      Builder(
                        builder: (context) {
                          final active = !handler.sleepAtTrackEnd &&
                              remaining != null &&
                              remaining.inSeconds > (mins - 15) * 60 &&
                              remaining.inSeconds <= mins * 60;
                          return ListTile(
                            leading: Icon(
                              SolarIconsBold.clockCircle,
                              color: active ? accent : colors.textSecondary,
                              size: 20,
                            ),
                            title: Text(
                              '$mins minutos',
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                                color: active ? accent : colors.textPrimary,
                              ),
                            ),
                            trailing: active ? Icon(SolarIconsBold.checkCircle, size: 19, color: accent) : null,
                            onTap: () {
                              handler.setSleepTimer(Duration(minutes: mins));
                              Navigator.pop(context);
                            },
                          );
                        },
                      ),
                      Divider(height: 1, indent: 16, endIndent: 16, color: colors.stroke),
                    ],
                    ListTile(
                      leading: Icon(
                        SolarIconsBold.musicNote,
                        color: handler.sleepAtTrackEnd ? accent : colors.textSecondary,
                        size: 20,
                      ),
                      title: Text(
                        'Fim da faixa atual',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: handler.sleepAtTrackEnd ? FontWeight.w700 : FontWeight.w600,
                          color: handler.sleepAtTrackEnd ? accent : colors.textPrimary,
                        ),
                      ),
                      trailing: handler.sleepAtTrackEnd
                          ? Icon(SolarIconsBold.checkCircle, size: 19, color: accent)
                          : null,
                      onTap: () {
                        handler.setSleepTimer(null, atTrackEnd: true);
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              ),
              if (handler.hasSleepTimer) ...[
                const SizedBox(height: 12),
                Material(
                  color: colors.danger.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      handler.cancelSleepTimer();
                      Navigator.pop(context);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: colors.danger.withValues(alpha: 0.45)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(SolarIconsBold.close, size: 18, color: colors.danger),
                          const SizedBox(width: 8),
                          Text(
                            'Desativar timer',
                            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: colors.danger),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 10),
                Text(
                  'A reprodução pausa automaticamente quando o tempo terminar.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: colors.textTertiary),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final cardBg = colors.isDark ? const Color(0xFF121317) : Colors.white;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              title.toUpperCase(),
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.0,
                color: colors.textTertiary,
              ),
            ),
          ),
          Material(
            color: cardBg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: colors.stroke, width: 1),
            ),
            clipBehavior: Clip.antiAlias,
            child: child,
          ),
        ],
      ),
    );
  }
}

class _ThemeOptionTile extends StatelessWidget {
  const _ThemeOptionTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final activeBg = colors.isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.black.withValues(alpha: 0.06);

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: selected ? activeBg : Colors.transparent,
          border: Border.all(
            color: selected ? colors.textPrimary : colors.stroke,
            width: selected ? 1.2 : 1.0,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 17, color: selected ? colors.textPrimary : colors.textSecondary),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? colors.textPrimary : colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
