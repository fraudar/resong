// language: Dart, file: lib/state/local_downloads_platform_stub.dart, target: fallback, runtime: resong app
import 'dart:typed_data';

class SavedLocalAudio {
  const SavedLocalAudio({
    required this.uriOrPath,
    required this.displayPath,
    required this.size,
  });

  final String uriOrPath;
  final String displayPath;
  final int size;
}

bool get canChooseLocalFolder => false;
bool get isWebDownloadPlatform => false;

Future<String> defaultDownloadFolderDisplay() async => 'Música/resong';

Future<SavedLocalAudio> saveTaggedAudioToDevice({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
  required String customFolder,
}) async {
  throw UnsupportedError('Armazenamento local indisponível nesta plataforma');
}

Future<bool> localFileExists(String? uriOrPath) async => false;

Future<void> deleteLocalFile(String? uriOrPath) async {}

String? playableUriForLocal(String? uriOrPath) => null;

Future<void> triggerBrowserFileSave({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
}) async {}
