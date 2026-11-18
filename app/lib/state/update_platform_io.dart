// language: Dart, file: lib/state/update_platform_io.dart, target: mobile + desktop, runtime: resong app
import 'dart:io';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

enum UpdatePlatform { android, windows, linux, macOS, iOS, web, unknown }

UpdatePlatform get currentUpdatePlatform {
  if (Platform.isAndroid) return UpdatePlatform.android;
  if (Platform.isWindows) return UpdatePlatform.windows;
  if (Platform.isLinux) return UpdatePlatform.linux;
  if (Platform.isMacOS) return UpdatePlatform.macOS;
  if (Platform.isIOS) return UpdatePlatform.iOS;
  return UpdatePlatform.unknown;
}

Future<String> saveUpdateFile(String fileName, List<int> bytes) async {
  final dir = Platform.isAndroid
      ? (await getExternalStorageDirectory() ?? await getTemporaryDirectory())
      : await getTemporaryDirectory();
  final safeName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  final file = File('${dir.path}${Platform.pathSeparator}$safeName');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

Future<void> installUpdateFile(String path) async {
  if (Platform.isWindows) {
    // Instalador Inno Setup: silencioso, por usuário, fecha instâncias abertas.
    await Process.start(
      path,
      const ['/VERYSILENT', '/NORESTART', '/CLOSEAPPLICATIONS'],
      mode: ProcessStartMode.detached,
    );
    return;
  }
  if (Platform.isLinux && path.toLowerCase().endsWith('.deb')) {
    await Process.start('pkexec', ['dpkg', '-i', path],
        mode: ProcessStartMode.detached);
    return;
  }

  // Android/iOS (e desktop como fallback): abre o pacote no instalador do sistema.
  final mime = path.toLowerCase().endsWith('.apk')
      ? 'application/vnd.android.package-archive'
      : null;
  final result = await OpenFilex.open(path, type: mime);
  if (result.type != ResultType.done) {
    throw Exception(result.message.isEmpty
        ? 'Não foi possível abrir o instalador'
        : result.message);
  }
}

Future<void> restartApp() async {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    exit(0);
  }
}
