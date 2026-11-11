// language: Dart, file: lib/state/local_downloads_platform.dart, target: any, runtime: resong app
export 'local_downloads_platform_stub.dart'
    if (dart.library.io) 'local_downloads_platform_io.dart'
    if (dart.library.js_interop) 'local_downloads_platform_web.dart';
