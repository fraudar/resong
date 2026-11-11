// language: Dart, file: lib/state/local_downloads_platform_io.dart, target: Android/iOS/Desktop, runtime: resong app
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

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

const _channel = MethodChannel('resong/downloads');

bool get canChooseLocalFolder => true;
bool get isWebDownloadPlatform => false;

Future<Directory> _resolveDesktopDefaultDir() async {
  final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
  if (home != null && home.isNotEmpty) {
    final sep = Platform.pathSeparator;
    final ptMusic = Directory('$home${sep}Músicas');
    if (await ptMusic.exists()) {
      return Directory('${ptMusic.path}${sep}resong');
    }
    final enMusic = Directory('$home${sep}Music');
    if (await enMusic.exists()) {
      return Directory('${enMusic.path}${sep}resong');
    }
    return Directory('$home${sep}Music${sep}resong');
  }
  final docs = await getApplicationDocumentsDirectory();
  return Directory('${docs.path}${Platform.pathSeparator}resong');
}

Future<String> defaultDownloadFolderDisplay() async {
  if (Platform.isAndroid) {
    return 'Music/resong (MediaStore)';
  }
  if (Platform.isIOS) {
    final docs = await getApplicationDocumentsDirectory();
    return '${docs.path}/resong';
  }
  final dir = await _resolveDesktopDefaultDir();
  return dir.path;
}

Future<Directory> _resolveDirectory(String customFolder) async {
  final custom = customFolder.trim();
  if (custom.isNotEmpty) {
    return Directory(custom);
  }
  if (Platform.isIOS) {
    final docs = await getApplicationDocumentsDirectory();
    return Directory('${docs.path}/resong');
  }
  if (Platform.isAndroid) {
    final base = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
    return Directory('${base.path}/resong');
  }
  return _resolveDesktopDefaultDir();
}

Future<SavedLocalAudio> saveTaggedAudioToDevice({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
  required String customFolder,
}) async {
  if (Platform.isAndroid && customFolder.trim().isEmpty) {
    final tmpDir = await getTemporaryDirectory();
    final tmpFile = File(
      '${tmpDir.path}${Platform.pathSeparator}resong_${DateTime.now().microsecondsSinceEpoch}_$fileName',
    );
    await tmpFile.writeAsBytes(bytes, flush: true);
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('saveToMusicMediaStore', {
        'tempPath': tmpFile.path,
        'fileName': fileName,
        'mimeType': mimeType,
      });
      if (res != null && res['uriOrPath'] is String) {
        return SavedLocalAudio(
          uriOrPath: res['uriOrPath'] as String,
          displayPath: (res['displayPath'] as String?) ?? 'Music/resong/$fileName',
          size: (res['size'] as num?)?.toInt() ?? bytes.length,
        );
      }
    } on MissingPluginException {
      // Fallback para testes ou emuladores sem Activity registrada.
    } finally {
      if (await tmpFile.exists()) {
        try {
          await tmpFile.delete();
        } catch (_) {}
      }
    }
  }

  final dir = await _resolveDirectory(customFolder);
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  final sep = Platform.pathSeparator;
  var dest = File('${dir.path}$sep$fileName');
  if (await dest.exists()) {
    final dot = fileName.lastIndexOf('.');
    final stem = dot > 0 ? fileName.substring(0, dot) : fileName;
    final ext = dot > 0 ? fileName.substring(dot) : '';
    var suffix = 2;
    while (await dest.exists()) {
      dest = File('${dir.path}$sep$stem ($suffix)$ext');
      suffix++;
    }
  }
  await dest.writeAsBytes(bytes, flush: true);
  return SavedLocalAudio(
    uriOrPath: dest.path,
    displayPath: dest.path,
    size: bytes.length,
  );
}

Future<bool> localFileExists(String? uriOrPath) async {
  if (uriOrPath == null || uriOrPath.isEmpty) return false;
  if (Platform.isAndroid && uriOrPath.startsWith('content://')) {
    try {
      return await _channel.invokeMethod<bool>('exists', {'uriOrPath': uriOrPath}) ?? false;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }
  return File(uriOrPath).exists();
}

Future<void> deleteLocalFile(String? uriOrPath) async {
  if (uriOrPath == null || uriOrPath.isEmpty) return;
  if (Platform.isAndroid && uriOrPath.startsWith('content://')) {
    try {
      await _channel.invokeMethod<bool>('delete', {'uriOrPath': uriOrPath});
    } catch (_) {}
    return;
  }
  final file = File(uriOrPath);
  if (await file.exists()) {
    try {
      await file.delete();
    } catch (_) {}
  }
}

String? playableUriForLocal(String? uriOrPath) {
  if (uriOrPath == null || uriOrPath.isEmpty) return null;
  if (uriOrPath.startsWith('content://') ||
      uriOrPath.startsWith('http://') ||
      uriOrPath.startsWith('https://')) {
    return uriOrPath;
  }
  return Uri.file(uriOrPath).toString();
}

Future<void> triggerBrowserFileSave({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
}) async {}
