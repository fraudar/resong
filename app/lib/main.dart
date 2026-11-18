// language: Dart, file: lib/main.dart, target: Android/iOS/desktop, runtime: resong app
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';

import 'core/theme.dart';
import 'engine/local_engine.dart';
import 'screens/shell.dart';
import 'state/audio_fx.dart';
import 'state/library.dart';
import 'state/lyrics_cache.dart';
import 'state/providers.dart';
import 'state/scrobbles.dart';
import 'state/updater.dart';
import 'widgets/flight.dart';
import 'widgets/update_dialog.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux)) {
    JustAudioMediaKit.ensureInitialized(
      windows: true,
      linux: true,
      android: false,
      iOS: false,
      macOS: false,
    );
  }

  await ensureLocalEngineStarted();

  if (kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS) {
    // uma única instância do handler: notificação/lockscreen e UI compartilham a mesma
    await AudioService.init(
      builder: handlerInstance,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'dev.resong.resong.audio',
        androidNotificationChannelName: 'resong',
        androidNotificationIcon: 'mipmap/ic_launcher',
        androidShowNotificationBadge: true,
        androidStopForegroundOnPause: true,
      ),
    );
  } else {
    handlerInstance();
  }

  runApp(const ProviderScope(child: ResongApp()));
}

class ResongApp extends ConsumerWidget {
  const ResongApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(paletteSyncProvider);
    ref.watch(scrobbleBinderProvider);
    ref.watch(lyricsPrefetchProvider);
    ref.watch(audioFxProvider);
    final accent = ref.watch(accentProvider);
    final mode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'resong',
      debugShowCheckedModeBanner: false,
      navigatorObservers: [SonoraRouteObserver.instance],
      themeMode: mode,
      theme: AppTheme.light(accent: accent),
      darkTheme: AppTheme.black(accent: accent),
      scrollBehavior: const _NoScrollbarBehavior(),
      themeAnimationDuration: const Duration(milliseconds: 350),
      themeAnimationCurve: Curves.easeOutCubic,
      home: const Shell(),
      builder: (context, child) => _AutoUpdateGate(child: child ?? const SizedBox.shrink()),
    );
  }
}

/// Dispara a checagem ao abrir o app e mostra o progresso do auto-update.
/// Fica abaixo do Navigator do MaterialApp para poder abrir o diálogo.
class _AutoUpdateGate extends ConsumerStatefulWidget {
  const _AutoUpdateGate({required this.child});
  final Widget child;

  @override
  ConsumerState<_AutoUpdateGate> createState() => _AutoUpdateGateState();
}

class _AutoUpdateGateState extends ConsumerState<_AutoUpdateGate> {
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(updaterProvider.notifier).check();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<UpdateState>(updaterProvider, (previous, next) {
      final shouldShow = next.phase == UpdatePhase.available ||
          next.phase == UpdatePhase.downloading ||
          next.phase == UpdatePhase.installing ||
          next.phase == UpdatePhase.error;

      if (shouldShow && !_dialogOpen) {
        _dialogOpen = true;
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const UpdateDialog(),
        ).whenComplete(() => _dialogOpen = false);
        if (next.phase == UpdatePhase.available) {
          ref.read(updaterProvider.notifier).downloadAndInstall();
        }
      } else if (next.phase == UpdatePhase.done && _dialogOpen) {
        Navigator.of(context).maybePop();
      }
    });
    return widget.child;
  }
}

/// Remove barras de rolagem visíveis nas listas e abas roláveis (estilo desktop limpo).
class _NoScrollbarBehavior extends MaterialScrollBehavior {
  const _NoScrollbarBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };

  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) => child;
}
