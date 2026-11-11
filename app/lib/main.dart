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
import 'widgets/flight.dart';

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
    );
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
