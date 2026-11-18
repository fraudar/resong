// language: Dart, file: lib/state/update_platform.dart, target: any, runtime: resong app
// Abstração de plataforma para o auto-update (dart:io não existe na Web).
export 'update_platform_stub.dart'
    if (dart.library.io) 'update_platform_io.dart';
