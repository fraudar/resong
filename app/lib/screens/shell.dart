// language: Dart, file: lib/screens/shell.dart, target: mobile-first + desktop, runtime: resong app
import 'dart:math' as math;

import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:solar_icons_flutter/solar_icons_flutter.dart';

import '../core/format.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../state/audio_fx.dart';
import '../state/library.dart';
import '../state/player.dart';
import '../state/providers.dart';
import '../state/scrobbles.dart';
import '../widgets/artist_link.dart';
import '../widgets/artwork.dart';
import '../widgets/glass.dart';
import '../widgets/mini_player.dart';
import '../widgets/volume_control.dart';
import 'desktop_player.dart';
import 'detail_screen.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'player_screen.dart';
import 'profile_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

/// Casca raiz: navegadores por aba + mini-player compacto + pill fina em vidro fosco.
class Shell extends ConsumerStatefulWidget {
  const Shell({super.key});

  @override
  ConsumerState<Shell> createState() => _ShellState();
}

class _ShellState extends ConsumerState<Shell> {
  final _navKeys = [
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
  ];

  static const _roots = [
    HomeScreen(),
    SearchScreen(),
    LibraryScreen(),
    ProfileScreen(),
  ];

  bool _sidebarCollapsed = false;
  bool _libraryExpanded = true;

  void _go(int i) {
    final current = ref.read(shellTabProvider);
    if (i == current) {
      _navKeys[i].currentState?.popUntil((route) => route.isFirst);
      return;
    }
    ref.read(shellTabProvider.notifier).state = i;
  }

  void _goLibrarySubTab(int subIndex) {
    ref.read(libraryTabProvider.notifier).state = subIndex;
    _go(2);
  }

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(shellTabProvider);
    final libSubIndex = ref.watch(libraryTabProvider);
    ref.listen<int>(shellTabProvider, (_, next) {
      _navKeys[next].currentState?.popUntil((route) => route.isFirst);
    });
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final palette = ref.watch(currentPaletteProvider);
    final colors = context.colors;
    final isDesktop = MediaQuery.sizeOf(context).width >= 860;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final currentNav = _navKeys[index].currentState;
        if (currentNav != null && await currentNav.maybePop()) return;
        if (index != 0) {
          ref.read(shellTabProvider.notifier).state = 0;
        }
      },
      child: Scaffold(
        backgroundColor: colors.bg,
        body: isDesktop
            ? Column(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        _SonoraDesktopSidebar(
                          index: index,
                          librarySubIndex: libSubIndex,
                          collapsed: _sidebarCollapsed,
                          libraryExpanded: _libraryExpanded,
                          onToggleCollapsed: () =>
                              setState(() => _sidebarCollapsed = !_sidebarCollapsed),
                          onToggleLibraryExpanded: () =>
                              setState(() => _libraryExpanded = !_libraryExpanded),
                          onChanged: _go,
                          onSelectLibrarySub: _goLibrarySubTab,
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              _DesktopTopUtilityRow(
                                onBack: () => _navKeys[index].currentState?.maybePop(),
                                onOpenProfile: () => _go(3),
                              ),
                              Expanded(
                                child: IndexedStack(
                                  index: index,
                                  children: [
                                    for (var i = 0; i < _roots.length; i++)
                                      _TabNavigator(navigatorKey: _navKeys[i], root: _roots[i]),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  _DesktopNowPlayingBar(
                    onOpenArtist: (track, artistName) => DetailScreen.openArtistForTrack(
                      context,
                      track,
                      artistName: artistName,
                      navigator: _navKeys[index].currentState,
                    ),
                  ),
                ],
              )
            : Stack(
                children: [
                  IndexedStack(
                    index: index,
                    children: [
                      for (var i = 0; i < _roots.length; i++)
                        _TabNavigator(navigatorKey: _navKeys[i], root: _roots[i]),
                    ],
                  ),
                  // Dock inferior flutuante compacto (MiniPlayer + NavPill fina em vidro) — layout mobile preservado
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: bottomInset + 10,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const MiniPlayer(),
                            const SizedBox(height: 6),
                            _GlassNavPill(
                              index: index,
                              tint: palette.backdropFor(colors.isDark),
                              accent: palette.accentFor(colors.isDark),
                              onChanged: _go,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _TabNavigator extends StatelessWidget {
  const _TabNavigator({required this.navigatorKey, required this.root});

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget root;

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: navigatorKey,
      onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => root),
    );
  }
}

class _GlassNavPill extends StatelessWidget {
  const _GlassNavPill({
    required this.index,
    required this.tint,
    required this.accent,
    required this.onChanged,
  });

  final int index;
  final Color tint;
  final Color accent;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      borderRadius: BorderRadius.circular(26),
      blur: 28,
      tint: tint,
      tintStrength: 0.40,
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      child: Row(
        children: [
          _NavItem(
            label: 'Início',
            icon: SolarIconsBold.homeSmile,
            active: index == 0,
            accent: accent,
            onTap: () => onChanged(0),
          ),
          _NavItem(
            label: 'Buscar',
            icon: SolarIconsBold.magnifier,
            active: index == 1,
            accent: accent,
            onTap: () => onChanged(1),
          ),
          _NavItem(
            label: 'Biblioteca',
            icon: SolarIconsBold.library,
            active: index == 2,
            accent: accent,
            onTap: () => onChanged(2),
          ),
          _NavItem(
            label: 'Perfil',
            icon: SolarIconsBold.user,
            active: index == 3,
            accent: accent,
            onTap: () => onChanged(3),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.active,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final activeText = colors.isDark ? Colors.white : colors.textPrimary;
    final inactiveText = colors.textSecondary;
    final color = active ? activeText : inactiveText;
    final activeBg = colors.isDark
        ? Color.lerp(Colors.white.withValues(alpha: 0.14), accent.withValues(alpha: 0.34), 0.55)!
        : Color.lerp(Colors.black.withValues(alpha: 0.08), accent.withValues(alpha: 0.18), 0.45)!;

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(
            color: active ? activeBg : Colors.transparent,
            borderRadius: BorderRadius.circular(22),
            border: active
                ? Border.all(
                    color: (colors.isDark ? Colors.white : Colors.black).withValues(alpha: 0.10),
                    width: 0.8,
                  )
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 19, color: color),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: color,
                  letterSpacing: 0.15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sidebar lateral esquerda retrátil estilo Sonora (modo Desktop >= 860 px).
class _SonoraDesktopSidebar extends ConsumerWidget {
  const _SonoraDesktopSidebar({
    required this.index,
    required this.librarySubIndex,
    required this.collapsed,
    required this.libraryExpanded,
    required this.onToggleCollapsed,
    required this.onToggleLibraryExpanded,
    required this.onChanged,
    required this.onSelectLibrarySub,
  });

  final int index;
  final int librarySubIndex;
  final bool collapsed;
  final bool libraryExpanded;
  final VoidCallback onToggleCollapsed;
  final VoidCallback onToggleLibraryExpanded;
  final ValueChanged<int> onChanged;
  final ValueChanged<int> onSelectLibrarySub;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final playlists = ref.watch(playlistsProvider);
    final playlistCovers = ref.watch(playlistCoversProvider);
    final sidebarBg = colors.isDark ? const Color(0xFF0A0B0D) : const Color(0xFFF4F5F8);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: collapsed ? 60 : 210,
      decoration: BoxDecoration(
        color: sidebarBg,
        border: Border(right: BorderSide(color: colors.stroke, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Cabeçalho discreto: recolher barra lateral + marca limpa
          SizedBox(
            height: 44,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  IconButton(
                    tooltip: collapsed ? 'Expandir barra lateral' : 'Recolher barra lateral',
                    visualDensity: VisualDensity.compact,
                    iconSize: 17,
                    icon: Icon(SolarIconsLinear.sidebarMinimalistic, color: colors.textSecondary),
                    onPressed: onToggleCollapsed,
                  ),
                  if (!collapsed) ...[
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'resong',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.4,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
              children: [
                _SonoraNavRow(
                  label: 'Início',
                  icon: SolarIconsLinear.homeSmile,
                  activeIcon: SolarIconsBold.homeSmile,
                  active: index == 0,
                  collapsed: collapsed,
                  onTap: () => onChanged(0),
                ),
                _SonoraNavRow(
                  label: 'Buscar',
                  icon: SolarIconsLinear.magnifier,
                  activeIcon: SolarIconsBold.magnifier,
                  active: index == 1,
                  collapsed: collapsed,
                  onTap: () => onChanged(1),
                ),
                _SonoraNavRow(
                  label: 'Sua Biblioteca',
                  icon: SolarIconsLinear.library,
                  activeIcon: SolarIconsBold.library,
                  active: index == 2 && collapsed,
                  collapsed: collapsed,
                  trailing: collapsed
                      ? null
                      : InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: onToggleLibraryExpanded,
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(
                              libraryExpanded
                                  ? Icons.keyboard_arrow_down_rounded
                                  : Icons.chevron_right_rounded,
                              size: 16,
                              color: colors.textTertiary,
                            ),
                          ),
                        ),
                  onTap: () => onChanged(2),
                ),
                if (!collapsed && libraryExpanded) ...[
                  _SonoraSubNavRow(
                    label: 'Favoritos',
                    active: index == 2 && librarySubIndex == 0,
                    onTap: () => onSelectLibrarySub(0),
                  ),
                  _SonoraSubNavRow(
                    label: 'Playlists',
                    active: index == 2 && librarySubIndex == 1,
                    onTap: () => onSelectLibrarySub(1),
                  ),
                  _SonoraSubNavRow(
                    label: 'Downloads',
                    active: index == 2 && librarySubIndex == 2,
                    onTap: () => onSelectLibrarySub(2),
                  ),
                  _SonoraSubNavRow(
                    label: 'Histórico',
                    active: index == 2 && librarySubIndex == 3,
                    onTap: () => onSelectLibrarySub(3),
                  ),
                ],

                if (!collapsed && playlists.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                    child: Divider(height: 1, color: colors.stroke),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
                    child: Text(
                      'FIXADOS',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.9,
                        color: colors.textTertiary,
                      ),
                    ),
                  ),
                  for (final p in playlists.take(8))
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => onSelectLibrarySub(1),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        child: Row(
                          children: [
                            Artwork(
                              url: p.artwork,
                              localBytes: playlistCovers[p.id],
                              size: 30,
                              radius: 6,
                              tone: colors.textSecondary,
                              icon: SolarIconsLinear.playlist,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    p.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w500,
                                      color: colors.textPrimary,
                                    ),
                                  ),
                                  Text(
                                    'Playlist · ${p.trackCount}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 11, color: colors.textTertiary),
                                  ),
                                ],
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
        ],
      ),
    );
  }
}

class _SonoraNavRow extends StatelessWidget {
  const _SonoraNavRow({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.active,
    required this.collapsed,
    required this.onTap,
    this.trailing,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
  final bool active;
  final bool collapsed;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final activeBg = colors.isDark
        ? Colors.white.withValues(alpha: 0.085)
        : Colors.black.withValues(alpha: 0.065);

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Tooltip(
        message: collapsed ? label : '',
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            height: 34,
            padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: active ? activeBg : Colors.transparent,
            ),
            child: collapsed
                ? Center(
                    child: Icon(
                      active ? activeIcon : icon,
                      size: 17,
                      color: active ? colors.textPrimary : colors.textSecondary,
                    ),
                  )
                : Row(
                    children: [
                      Icon(
                        active ? activeIcon : icon,
                        size: 16.5,
                        color: active ? colors.textPrimary : colors.textSecondary,
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                            color: active ? colors.textPrimary : colors.textSecondary,
                          ),
                        ),
                      ),
                      if (trailing != null) trailing!,
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _SonoraSubNavRow extends StatelessWidget {
  const _SonoraSubNavRow({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final activeBg = colors.isDark
        ? Colors.white.withValues(alpha: 0.075)
        : Colors.black.withValues(alpha: 0.055);

    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: InkWell(
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        child: Container(
          height: 30,
          padding: const EdgeInsets.only(left: 38, right: 10),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(7),
            color: active ? activeBg : Colors.transparent,
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 12.5,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              color: active ? colors.textPrimary : colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Barra superior limpa com botão voltar e foto de perfil (Perfil, Configurações).
class _DesktopTopUtilityRow extends ConsumerWidget {
  const _DesktopTopUtilityRow({
    required this.onBack,
    required this.onOpenProfile,
  });

  final VoidCallback onBack;
  final VoidCallback onOpenProfile;

  Future<void> _openAccountMenu(BuildContext btnCtx, WidgetRef ref) async {
    final colors = btnCtx.colors;
    final identity = ref.read(profileIdentityProvider);
    final box = btnCtx.findRenderObject() as RenderBox?;
    final overlay = Navigator.of(btnCtx).overlay?.context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;

    final rect = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
    final pos = RelativeRect.fromRect(
      Rect.fromLTWH(rect.left - 140, rect.bottom + 6, rect.width + 140, 0),
      Offset.zero & overlay.size,
    );

    final choice = await showMenu<String>(
      context: btnCtx,
      position: pos,
      color: colors.isDark ? const Color(0xFF18191C) : Colors.white,
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: colors.stroke, width: 1),
      ),
      items: [
        PopupMenuItem<String>(
          enabled: false,
          height: 32,
          child: Text(
            identity.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.textTertiary,
            ),
          ),
        ),
        const PopupMenuDivider(height: 6),
        PopupMenuItem<String>(
          value: 'profile',
          height: 36,
          child: Row(
            children: [
              Icon(SolarIconsLinear.user, size: 16, color: colors.textPrimary),
              const SizedBox(width: 10),
              Text('Perfil', style: GoogleFonts.inter(fontSize: 13, color: colors.textPrimary)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'settings',
          height: 36,
          child: Row(
            children: [
              Icon(SolarIconsLinear.settings, size: 16, color: colors.textPrimary),
              const SizedBox(width: 10),
              Text('Configurações', style: GoogleFonts.inter(fontSize: 13, color: colors.textPrimary)),
            ],
          ),
        ),
      ],
    );

    if (choice == null || !btnCtx.mounted) return;
    switch (choice) {
      case 'profile':
        onOpenProfile();
        break;
      case 'settings':
        await SettingsScreen.open(btnCtx);
        break;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final identity = ref.watch(profileIdentityProvider);
    final avatarBytes = identity.avatarBytes;
    final initial = identity.name.trim().isEmpty
        ? 'O'
        : identity.name.trim().characters.first.toUpperCase();

    return SizedBox(
      height: 46,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Voltar',
              visualDensity: VisualDensity.compact,
              iconSize: 17,
              icon: Icon(SolarIconsLinear.altArrowLeft, color: colors.textSecondary),
              onPressed: onBack,
            ),
            const Spacer(),
            Builder(
              builder: (btnCtx) => Tooltip(
                message: 'Conta',
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => _openAccountMenu(btnCtx, ref),
                  child: Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.isDark
                          ? const Color(0xFF1B1D22)
                          : const Color(0xFFE5E7EC),
                      border: Border.all(color: colors.stroke, width: 1),
                      image: avatarBytes != null
                          ? DecorationImage(
                              image: MemoryImage(avatarBytes),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: avatarBytes == null
                        ? Text(
                            initial,
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: colors.textPrimary,
                            ),
                          )
                        : null,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Barra inferior minimalista do modo Desktop no estilo Sonora (com Volume hover/mute e controles limpos).
class _DesktopNowPlayingBar extends ConsumerWidget {
  const _DesktopNowPlayingBar({
    required this.onOpenArtist,
  });

  final void Function(Track track, String artistName) onOpenArtist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final track = ref.watch(currentTrackProvider);
    if (track == null) return const SizedBox.shrink();

    final handler = ref.watch(handlerProvider);
    final palette = ref.watch(currentPaletteProvider);
    final accent = palette.accentFor(colors.isDark);
    final playing = ref.watch(isPlayingProvider);
    ref.watch(playerModeProvider);
    final isFav = ref.watch(favoritesProvider.select((favs) => favs.any((t) => t.id == track.id)));
    final fxActive = ref.watch(audioFxProvider.select((f) => f.hasActiveEffects));
    final barBg = colors.isDark ? const Color(0xFF0A0B0E) : const Color(0xFFF6F7FA);

    return Container(
      height: 66,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: barBg,
        border: Border(top: BorderSide(color: colors.stroke, width: 1)),
      ),
      child: Row(
        children: [
          // Esquerda: capa + título + coração fino + artista clicável
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => PlayerScreen.open(context, ref),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Artwork(
                        url: track.artwork,
                        size: 42,
                        radius: 7,
                        tone: accent,
                        icon: SolarIconsBold.musicNote,
                      ),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: GestureDetector(
                                onTap: () => PlayerScreen.open(context, ref),
                                child: MouseRegion(
                                  cursor: SystemMouseCursors.click,
                                  child: Text(
                                    track.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: colors.textPrimary,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            InkWell(
                              borderRadius: BorderRadius.circular(999),
                              onTap: () => ref.read(favoritesProvider.notifier).toggle(track),
                              child: Icon(
                                isFav ? SolarIconsBold.heart : SolarIconsLinear.heart,
                                size: 14.5,
                                color: isFav ? accent : colors.textTertiary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        ArtistTextLink(
                          track: track,
                          style: TextStyle(fontSize: 11.5, color: colors.textSecondary),
                          onOpenArtist: (name) => onOpenArtist(track, name),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Centro: transporte fino + linha de progresso
          Expanded(
            flex: 4,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      iconSize: 15,
                      tooltip: 'Aleatório',
                      icon: Icon(
                        SolarIconsLinear.shuffle,
                        color: handler.shuffle ? accent : colors.textSecondary,
                      ),
                      onPressed: handler.toggleShuffle,
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      iconSize: 18,
                      tooltip: 'Anterior',
                      icon: Icon(SolarIconsLinear.skipPrevious, color: colors.textPrimary),
                      onPressed: handler.skipToPrevious,
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      iconSize: 20,
                      tooltip: playing ? 'Pausar' : 'Tocar',
                      icon: Icon(
                        playing ? SolarIconsBold.pause : SolarIconsBold.play,
                        color: colors.textPrimary,
                      ),
                      onPressed: playing ? handler.pause : handler.play,
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      iconSize: 18,
                      tooltip: 'Próxima',
                      icon: Icon(SolarIconsLinear.skipNext, color: colors.textPrimary),
                      onPressed: handler.skipToNext,
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      iconSize: 15,
                      tooltip: 'Repetir',
                      icon: Icon(
                        handler.repeatMode == RepeatMode.one
                            ? SolarIconsBold.repeatOne
                            : SolarIconsLinear.repeat,
                        color: handler.repeatMode != RepeatMode.off ? accent : colors.textSecondary,
                      ),
                      onPressed: handler.cycleRepeat,
                    ),
                  ],
                ),
                _DesktopBarSeekRow(handler: handler, track: track),
              ],
            ),
          ),

          // Direita: Equalizador, Letras, Fila, Volume hover/mute e expandir
          Expanded(
            flex: 3,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Equalizador & Som 8D',
                  iconSize: 17,
                  icon: Icon(
                    SolarIconsLinear.tuning2,
                    color: fxActive ? accent : colors.textSecondary,
                  ),
                  onPressed: () => PlayerScreen.open(
                    context,
                    ref,
                    desktopPanel: DesktopSidePanel.fx,
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Letras',
                  iconSize: 17,
                  icon: Icon(SolarIconsLinear.microphone, color: colors.textSecondary),
                  onPressed: () => PlayerScreen.open(
                    context,
                    ref,
                    desktopPanel: DesktopSidePanel.lyrics,
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Fila',
                  iconSize: 17,
                  icon: Icon(SolarIconsLinear.playlist2, color: colors.textSecondary),
                  onPressed: () => PlayerScreen.open(
                    context,
                    ref,
                    desktopPanel: DesktopSidePanel.queue,
                  ),
                ),
                const SizedBox(width: 2),
                HoverVolumeControl(
                  placement: VolumeSliderPlacement.floatingLeft,
                  iconSize: 17,
                  sliderWidth: 92,
                  iconColor: colors.textSecondary,
                  mutedColor: colors.textTertiary,
                  trackColor: colors.isDark ? Colors.white : colors.textPrimary,
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Expandir player',
                  iconSize: 17,
                  icon: Icon(SolarIconsLinear.altArrowUp, color: colors.textSecondary),
                  onPressed: () => PlayerScreen.open(context, ref),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopBarSeekRow extends StatefulWidget {
  const _DesktopBarSeekRow({required this.handler, required this.track});

  final ResongHandler handler;
  final Track track;

  @override
  State<_DesktopBarSeekRow> createState() => _DesktopBarSeekRowState();
}

class _DesktopBarSeekRowState extends State<_DesktopBarSeekRow> {
  double? _dragMs;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fg = colors.isDark ? Colors.white : colors.textPrimary;
    final trackBg = colors.isDark
        ? Colors.white.withValues(alpha: 0.16)
        : Colors.black.withValues(alpha: 0.15);

    return StreamBuilder<Duration>(
      stream: widget.handler.player.positionStream,
      initialData: widget.handler.player.position,
      builder: (context, posSnap) {
        return StreamBuilder<Duration?>(
          stream: widget.handler.player.durationStream,
          initialData: widget.handler.player.duration,
          builder: (context, durSnap) {
            final pos = posSnap.data ?? Duration.zero;
            final rawDur = durSnap.data ??
                (widget.track.durationMs != null
                    ? Duration(milliseconds: widget.track.durationMs!)
                    : Duration.zero);
            final maxMs = math.max(1.0, rawDur.inMilliseconds.toDouble());
            final shownMs = (_dragMs ?? pos.inMilliseconds.toDouble()).clamp(0.0, maxMs);

            return SizedBox(
              height: 18,
              child: Row(
                children: [
                  Text(
                    formatDuration(shownMs.round()),
                    style: TextStyle(
                      fontSize: 10,
                      color: colors.textTertiary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2.0,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 3.8),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 9),
                        activeTrackColor: fg,
                        inactiveTrackColor: trackBg,
                        thumbColor: fg,
                      ),
                      child: Slider(
                        min: 0,
                        max: maxMs,
                        value: shownMs,
                        onChangeStart: (v) => setState(() => _dragMs = v),
                        onChanged: (v) => setState(() => _dragMs = v),
                        onChangeEnd: (v) {
                          setState(() => _dragMs = null);
                          widget.handler.seek(Duration(milliseconds: v.round()));
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    rawDur > Duration.zero ? formatDuration(rawDur.inMilliseconds) : '--:--',
                    style: TextStyle(
                      fontSize: 10,
                      color: colors.textTertiary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
