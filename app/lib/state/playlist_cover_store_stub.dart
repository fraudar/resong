// language: Dart, file: lib/state/playlist_cover_store_stub.dart, target: test fallback, runtime: resong app
import 'dart:typed_data';

final Map<String, Uint8List> _memCovers = <String, Uint8List>{};

Future<Uint8List?> readLocalPlaylistCover(String playlistId) async => _memCovers[playlistId];

Future<void> writeLocalPlaylistCover(String playlistId, Uint8List bytes) async {
  _memCovers[playlistId] = bytes;
}

Future<void> deleteLocalPlaylistCover(String playlistId) async {
  _memCovers.remove(playlistId);
}
