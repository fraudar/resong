// language: Dart, file: lib/state/local_downloads_platform_web.dart, target: Web, runtime: resong app
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

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
bool get isWebDownloadPlatform => true;

Future<String> defaultDownloadFolderDisplay() async => 'Downloads do navegador (com tags)';

Future<SavedLocalAudio> saveTaggedAudioToDevice({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
  required String customFolder,
}) async {
  await triggerBrowserFileSave(bytes: bytes, fileName: fileName, mimeType: mimeType);
  return SavedLocalAudio(
    uriOrPath: '',
    displayPath: 'Navegador · $fileName',
    size: bytes.length,
  );
}

Future<bool> localFileExists(String? uriOrPath) async => false;

Future<void> deleteLocalFile(String? uriOrPath) async {}

String? playableUriForLocal(String? uriOrPath) => null;

Future<void> triggerBrowserFileSave({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
}) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final objectUrl = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = objectUrl
    ..download = fileName
    ..style.display = 'none';
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  Future<void>.delayed(const Duration(seconds: 10), () {
    web.URL.revokeObjectURL(objectUrl);
  });
}
