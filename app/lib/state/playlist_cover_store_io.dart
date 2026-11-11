// language: Dart, file: lib/state/playlist_cover_store_io.dart, target: Android/iOS/Desktop, runtime: resong app
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

Future<Directory> _coversDir() async {
  try {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}${Platform.pathSeparator}resong_covers');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  } catch (_) {
    final dir = Directory('${Directory.systemTemp.path}${Platform.pathSeparator}resong_covers');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
}

String _safeFileName(String playlistId) =>
    playlistId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

Future<Uint8List?> readLocalPlaylistCover(String playlistId) async {
  try {
    final dir = await _coversDir();
    final f = File('${dir.path}${Platform.pathSeparator}${_safeFileName(playlistId)}.img');
    if (await f.exists()) {
      return await f.readAsBytes();
    }
  } catch (_) {}
  return null;
}

Future<void> writeLocalPlaylistCover(String playlistId, Uint8List bytes) async {
  final dir = await _coversDir();
  final f = File('${dir.path}${Platform.pathSeparator}${_safeFileName(playlistId)}.img');
  await f.writeAsBytes(bytes, flush: true);
}

Future<void> deleteLocalPlaylistCover(String playlistId) async {
  try {
    final dir = await _coversDir();
    final f = File('${dir.path}${Platform.pathSeparator}${_safeFileName(playlistId)}.img');
    if (await f.exists()) {
      await f.delete();
    }
  } catch (_) {}
}
