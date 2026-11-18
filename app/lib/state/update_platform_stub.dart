// language: Dart, file: lib/state/update_platform_stub.dart, target: fallback/web, runtime: resong app

enum UpdatePlatform { android, windows, linux, macOS, iOS, web, unknown }

UpdatePlatform get currentUpdatePlatform => UpdatePlatform.web;

/// Salva o arquivo baixado e devolve um caminho/URI utilizável.
Future<String> saveUpdateFile(String fileName, List<int> bytes) async {
  throw UnsupportedError('Instalação automática indisponível nesta plataforma');
}

/// Dispara o instalador do pacote baixado.
Future<void> installUpdateFile(String path) async {
  throw UnsupportedError('Instalação automática indisponível nesta plataforma');
}

/// Encerra o app para que o instalador possa substituir os arquivos (desktop).
Future<void> restartApp() async {}
