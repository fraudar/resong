// language: Dart, file: lib/state/playlist_cover_store_web.dart, target: Web IndexedDB, runtime: resong app
import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

const _dbName = 'resong_local_media';
const _storeName = 'playlist_covers';

Future<web.IDBDatabase> _openDb() {
  final completer = Completer<web.IDBDatabase>();
  final req = web.window.indexedDB.open(_dbName, 1);

  req.onupgradeneeded = (web.IDBVersionChangeEvent _) {
    final db = req.result as web.IDBDatabase;
    if (!db.objectStoreNames.contains(_storeName)) {
      db.createObjectStore(_storeName);
    }
  }.toJS;

  req.onsuccess = (web.Event _) {
    if (!completer.isCompleted) {
      completer.complete(req.result as web.IDBDatabase);
    }
  }.toJS;

  req.onerror = (web.Event _) {
    if (!completer.isCompleted) {
      completer.completeError(Exception('Falha ao abrir IndexedDB local'));
    }
  }.toJS;

  return completer.future;
}

Future<T?> _awaitRequest<T extends JSAny?>(web.IDBRequest req) {
  final completer = Completer<T?>();
  req.onsuccess = (web.Event _) {
    if (!completer.isCompleted) completer.complete(req.result as T?);
  }.toJS;
  req.onerror = (web.Event _) {
    if (!completer.isCompleted) completer.completeError(Exception('Erro em IndexedDB'));
  }.toJS;
  return completer.future;
}

Future<Uint8List?> readLocalPlaylistCover(String playlistId) async {
  try {
    final db = await _openDb();
    final tx = db.transaction(_storeName.toJS, 'readonly');
    final store = tx.objectStore(_storeName);
    final raw = await _awaitRequest<JSAny?>(store.get(playlistId.toJS));
    db.close();
    if (raw == null) return null;
    return (raw as JSUint8Array).toDart;
  } catch (_) {
    return null;
  }
}

Future<void> writeLocalPlaylistCover(String playlistId, Uint8List bytes) async {
  final db = await _openDb();
  final tx = db.transaction(_storeName.toJS, 'readwrite');
  final store = tx.objectStore(_storeName);
  await _awaitRequest<JSAny?>(store.put(bytes.toJS, playlistId.toJS));
  db.close();
}

Future<void> deleteLocalPlaylistCover(String playlistId) async {
  try {
    final db = await _openDb();
    final tx = db.transaction(_storeName.toJS, 'readwrite');
    final store = tx.objectStore(_storeName);
    await _awaitRequest<JSAny?>(store.delete(playlistId.toJS));
    db.close();
  } catch (_) {}
}
