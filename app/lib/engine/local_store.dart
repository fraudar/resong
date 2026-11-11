// language: Dart, file: lib/engine/local_store.dart, target: mobile + desktop, runtime: resong engine
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Banco local leve e atômico em JSON dentro do diretório do app (sem servidor externo).
class LocalStore {
  LocalStore._();
  static final LocalStore instance = LocalStore._();

  bool _ready = false;
  File? _file;
  Future<void>? _initFuture;
  Future<void> _writeChain = Future.value();

  final Map<String, Map<String, dynamic>> playlists = {};
  final Map<String, List<Map<String, dynamic>>> playlistTracks = {};
  final Map<String, Map<String, dynamic>> favorites = {}; // id -> {track, added_at}
  final List<Map<String, dynamic>> recent = []; // [{track, played_at}]
  final List<Map<String, dynamic>> searches = []; // [{q, at}]
  final Map<String, String> matches = {};
  final List<Map<String, dynamic>> addonSources = [];
  final Map<String, String> settings = {};

  Future<void> ensureReady() => _initFuture ??= _load();

  Future<void> _load() async {
    if (_ready) return;
    Directory dir;
    try {
      dir = await getApplicationSupportDirectory();
    } catch (_) {
      dir = Directory('${Directory.systemTemp.path}${Platform.pathSeparator}resong_engine');
    }
    if (!await dir.exists()) await dir.create(recursive: true);
    _file = File('${dir.path}${Platform.pathSeparator}resong_store.json');
    if (await _file!.exists()) {
      try {
        final raw = await _file!.readAsString();
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          _hydrate(decoded);
        }
      } catch (_) {}
    }
    _ready = true;
  }

  void _hydrate(Map<String, dynamic> data) {
    final pl = data['playlists'];
    if (pl is Map) {
      for (final e in pl.entries) {
        if (e.value is Map) playlists[e.key.toString()] = (e.value as Map).cast<String, dynamic>();
      }
    }
    final plt = data['playlist_tracks'];
    if (plt is Map) {
      for (final e in plt.entries) {
        if (e.value is List) {
          playlistTracks[e.key.toString()] = [
            for (final item in e.value.whereType<Map>()) item.cast<String, dynamic>(),
          ];
        }
      }
    }
    final favs = data['favorites'];
    if (favs is Map) {
      for (final e in favs.entries) {
        if (e.value is Map) favorites[e.key.toString()] = (e.value as Map).cast<String, dynamic>();
      }
    }
    final rec = data['recent'];
    if (rec is List) {
      recent.addAll([for (final r in rec.whereType<Map>()) r.cast<String, dynamic>()]);
    }
    final srch = data['searches'];
    if (srch is List) {
      searches.addAll([for (final s in srch.whereType<Map>()) s.cast<String, dynamic>()]);
    }
    final m = data['matches'];
    if (m is Map) {
      for (final e in m.entries) {
        matches[e.key.toString()] = e.value.toString();
      }
    }
    final src = data['sources'];
    if (src is List) {
      addonSources.addAll([for (final s in src.whereType<Map>()) s.cast<String, dynamic>()]);
    }
    final st = data['settings'];
    if (st is Map) {
      for (final e in st.entries) {
        settings[e.key.toString()] = e.value.toString();
      }
    }
  }

  Future<void> _flush() {
    _writeChain = _writeChain.then((_) async {
      await ensureReady();
      final f = _file;
      if (f == null) return;
      final payload = jsonEncode({
        'playlists': playlists,
        'playlist_tracks': playlistTracks,
        'favorites': favorites,
        'recent': recent,
        'searches': searches,
        'matches': matches,
        'sources': addonSources,
        'settings': settings,
      });
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(payload, flush: true);
      await tmp.rename(f.path);
    }).catchError((Object _) {});
    return _writeChain;
  }

  // --- settings ---
  String? getSetting(String key) => settings[key];
  Future<void> setSetting(String key, String value) async {
    await ensureReady();
    settings[key] = value;
    await _flush();
  }

  Future<void> deleteSetting(String key) async {
    await ensureReady();
    settings.remove(key);
    await _flush();
  }

  // --- matches ---
  String? getMatch(String sourceId) => matches[sourceId];
  Future<void> saveMatch(String sourceId, String targetId) async {
    await ensureReady();
    matches[sourceId] = targetId;
    await _flush();
  }

  // --- searches ---
  void saveSearch(String q) {
    final clean = q.trim();
    if (clean.isEmpty || clean.length > 160) return;
    searches.removeWhere((e) => e['q'] == clean);
    searches.insert(0, {'q': clean, 'at': DateTime.now().millisecondsSinceEpoch});
    if (searches.length > 12) searches.removeRange(12, searches.length);
    unawaited(_flush());
  }

  List<Map<String, dynamic>> listSearches() => List.unmodifiable(searches);

  Future<void> clearSearches() async {
    await ensureReady();
    searches.clear();
    await _flush();
  }

  // --- favorites ---
  List<Map<String, dynamic>> listFavorites() {
    final entries = favorites.values.toList()
      ..sort((a, b) => ((b['added_at'] as num?)?.toInt() ?? 0).compareTo((a['added_at'] as num?)?.toInt() ?? 0));
    return [for (final e in entries) (e['track'] as Map).cast<String, dynamic>()];
  }

  Future<void> addFavorite(Map<String, dynamic> track) async {
    await ensureReady();
    final id = track['id']?.toString() ?? '';
    if (id.isEmpty) return;
    favorites[id] = {'track': track, 'added_at': DateTime.now().millisecondsSinceEpoch};
    await _flush();
  }

  Future<void> removeFavorite(String id) async {
    await ensureReady();
    favorites.remove(id);
    await _flush();
  }

  // --- recent ---
  List<Map<String, dynamic>> listRecent({int limit = 50}) => [
        for (final r in recent.take(limit)) (r['track'] as Map).cast<String, dynamic>(),
      ];

  Future<void> addRecent(Map<String, dynamic> track) async {
    await ensureReady();
    final id = track['id']?.toString() ?? '';
    if (id.isEmpty) return;
    recent.removeWhere((e) => (e['track'] as Map?)?['id'] == id);
    recent.insert(0, {'track': track, 'played_at': DateTime.now().millisecondsSinceEpoch});
    if (recent.length > 50) recent.removeRange(50, recent.length);
    await _flush();
  }

  Future<void> clearRecent() async {
    await ensureReady();
    recent.clear();
    await _flush();
  }

  // --- playlists ---
  String? _firstArtworkFor(String id) {
    final list = playlistTracks[id];
    if (list == null || list.isEmpty) return null;
    return list.first['artwork'] as String?;
  }

  List<Map<String, dynamic>> listPlaylists({int? limit}) {
    final rows = playlists.values.toList()
      ..sort((a, b) => ((b['updated_at'] as num?)?.toInt() ?? 0).compareTo((a['updated_at'] as num?)?.toInt() ?? 0));
    final sliced = limit != null ? rows.take(limit) : rows;
    return [
      for (final row in sliced)
        {
          ...row,
          'artwork': row['artwork'] ?? _firstArtworkFor(row['id'] as String),
          'track_count': (playlistTracks[row['id']] ?? const []).length,
        },
    ];
  }

  Future<Map<String, dynamic>> createPlaylist({
    required String id,
    required String name,
    String description = '',
    String? artwork,
  }) async {
    await ensureReady();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final row = <String, dynamic>{
      'id': id,
      'name': name,
      'description': description,
      'artwork': artwork,
      'created_at': ts,
      'updated_at': ts,
    };
    playlists[id] = row;
    playlistTracks.putIfAbsent(id, () => []);
    await _flush();
    return {...row, 'track_count': 0};
  }

  Map<String, dynamic>? getPlaylist(String id) {
    final row = playlists[id];
    if (row == null) return null;
    final tracks = playlistTracks[id] ?? const <Map<String, dynamic>>[];
    return {
      ...row,
      'artwork': row['artwork'] ?? _firstArtworkFor(id),
      'track_count': tracks.length,
      'tracks': List<Map<String, dynamic>>.from(tracks),
    };
  }

  Future<bool> patchPlaylist(String id, {String? name, String? description, String? artwork, bool updateArtwork = false}) async {
    await ensureReady();
    final row = playlists[id];
    if (row == null) return false;
    if (name != null) row['name'] = name;
    if (description != null) row['description'] = description;
    if (updateArtwork) row['artwork'] = artwork;
    row['updated_at'] = DateTime.now().millisecondsSinceEpoch;
    await _flush();
    return true;
  }

  Future<void> deletePlaylist(String id) async {
    await ensureReady();
    playlists.remove(id);
    playlistTracks.remove(id);
    await _flush();
  }

  Future<({bool found, bool deduped})> addTrackToPlaylist(String playlistId, Map<String, dynamic> track) async {
    await ensureReady();
    final row = playlists[playlistId];
    if (row == null) return (found: false, deduped: false);
    final list = playlistTracks.putIfAbsent(playlistId, () => []);
    final trackId = track['id']?.toString() ?? '';
    if (list.any((t) => t['id'] == trackId)) {
      return (found: true, deduped: true);
    }
    list.add(track);
    row['updated_at'] = DateTime.now().millisecondsSinceEpoch;
    await _flush();
    return (found: true, deduped: false);
  }

  Future<void> removeTrackFromPlaylist(String playlistId, String trackId) async {
    await ensureReady();
    final list = playlistTracks[playlistId];
    if (list == null) return;
    list.removeWhere((t) => t['id'] == trackId);
    final row = playlists[playlistId];
    if (row != null) row['updated_at'] = DateTime.now().millisecondsSinceEpoch;
    await _flush();
  }

  Future<void> reorderPlaylist(String playlistId, List<String> order) async {
    await ensureReady();
    final list = playlistTracks[playlistId];
    if (list == null) return;
    final byId = {for (final t in list) (t['id']?.toString() ?? ''): t};
    final reordered = <Map<String, dynamic>>[];
    for (final tid in order) {
      final t = byId.remove(tid);
      if (t != null) reordered.add(t);
    }
    reordered.addAll(byId.values);
    playlistTracks[playlistId] = reordered;
    final row = playlists[playlistId];
    if (row != null) row['updated_at'] = DateTime.now().millisecondsSinceEpoch;
    await _flush();
  }

  // --- sources (BitChord addons) ---
  List<Map<String, dynamic>> listAddonSources() =>
      [for (final s in addonSources) Map<String, dynamic>.from(s)]
        ..sort((a, b) => ((a['ordem'] as num?)?.toInt() ?? 0).compareTo((b['ordem'] as num?)?.toInt() ?? 0));

  Map<String, dynamic>? getAddonSource(String id) =>
      addonSources.cast<Map<String, dynamic>?>().firstWhere((s) => s?['id'] == id, orElse: () => null);

  Future<Map<String, dynamic>> saveAddonSource(Map<String, dynamic> input) async {
    await ensureReady();
    final existingIdx = addonSources.indexWhere((s) => s['base_url'] == input['base_url'] || s['id'] == input['id']);
    if (existingIdx >= 0) {
      addonSources[existingIdx] = {...addonSources[existingIdx], ...input};
      await _flush();
      return Map<String, dynamic>.from(addonSources[existingIdx]);
    }
    final maxOrdem = addonSources.fold<int>(-1, (m, s) => ((s['ordem'] as num?)?.toInt() ?? 0) > m ? (s['ordem'] as num).toInt() : m);
    final saved = {...input, 'ordem': maxOrdem + 1};
    addonSources.add(saved);
    await _flush();
    return Map<String, dynamic>.from(saved);
  }

  Future<Map<String, dynamic>?> updateAddonSource(String id, Map<String, dynamic> patch) async {
    await ensureReady();
    final idx = addonSources.indexWhere((s) => s['id'] == id);
    if (idx < 0) return null;
    addonSources[idx] = {...addonSources[idx], ...patch};
    await _flush();
    return Map<String, dynamic>.from(addonSources[idx]);
  }

  Future<void> reorderAddonSources(List<String> order) async {
    await ensureReady();
    for (var i = 0; i < order.length; i++) {
      final idx = addonSources.indexWhere((s) => s['id'] == order[i]);
      if (idx >= 0) addonSources[idx]['ordem'] = i;
    }
    await _flush();
  }

  Future<void> deleteAddonSource(String id) async {
    await ensureReady();
    addonSources.removeWhere((s) => s['id'] == id);
    await _flush();
  }
}
