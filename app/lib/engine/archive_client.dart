// language: Dart, file: lib/engine/archive_client.dart, target: mobile + desktop, runtime: resong engine
import 'engine_utils.dart';
import 'local_store.dart';

class ArchiveClient {
  ArchiveClient._();
  static final ArchiveClient instance = ArchiveClient._();

  bool get isEnabled => LocalStore.instance.getSetting('provider.archive.enabled') != 'false';

  Future<bool> setEnabled(bool enabled) async {
    await LocalStore.instance.setSetting('provider.archive.enabled', enabled ? 'true' : 'false');
    return isEnabled;
  }

  Map<String, dynamic>? _toTrack(Map<String, dynamic> doc) {
    final id = (doc['identifier'] as String? ?? '').trim();
    final title = (doc['title'] as String? ?? '').trim();
    if (id.isEmpty || title.isEmpty) return null;
    final rawCreator = doc['creator'];
    final artist = rawCreator is List
        ? (rawCreator.isNotEmpty ? '${rawCreator.first}'.trim() : 'Internet Archive')
        : ('${rawCreator ?? 'Internet Archive'}').trim();
    final track = <String, dynamic>{
      'id': 'ia:$id',
      'source': 'archive',
      'title': title,
      'artists': artist.isNotEmpty ? [artist] : <String>[],
      'artwork': 'https://archive.org/services/img/${Uri.encodeComponent(id)}',
      'duration_ms': null,
      'explicit': false,
      'extra': {'source_label': 'Internet Archive'},
    };
    engineCache.set('archive:track:$id', track, const Duration(minutes: 15));
    return track;
  }

  Future<List<Map<String, dynamic>>> search(String query, {int limit = 6}) async {
    if (!isEnabled) return const [];
    final clean = query.replaceAll(RegExp(r'''[()[\]{}"']'''), ' ').trim();
    if (clean.isEmpty) return const [];
    final key = 'archive:search:${clean.toLowerCase()}:$limit';
    final cached = engineCache.get<List<Map<String, dynamic>>>(key);
    if (cached != null) return cached;

    try {
      final q = 'mediatype:audio AND format:"VBR MP3" AND ($clean)';
      final url =
          'https://archive.org/advancedsearch.php?q=${Uri.encodeQueryComponent(q)}'
          '&fl[]=identifier,title,creator&rows=${limit.clamp(1, 10)}&output=json';
      final res = await engineDio.get<Map<String, dynamic>>(url);
      final docs = (res.data?['response'] as Map?)?['docs'];
      if (docs is! List) return const [];
      final tracks = <Map<String, dynamic>>[];
      for (final d in docs.whereType<Map>()) {
        final t = _toTrack(d.cast<String, dynamic>());
        if (t != null) tracks.add(t);
      }
      engineCache.set(key, tracks, const Duration(minutes: 10));
      return tracks;
    } catch (_) {
      return const [];
    }
  }

  Map<String, dynamic>? _pickAudioFile(List files) {
    final audio = <Map<String, dynamic>>[];
    for (final item in files.whereType<Map>()) {
      final name = item['name'] as String?;
      if (name != null && RegExp(r'\.(mp3|m4a|ogg|flac)$', caseSensitive: false).hasMatch(name)) {
        audio.add(item.cast<String, dynamic>());
      }
    }
    if (audio.isEmpty) return null;
    for (final ext in ['.mp3', '.m4a', '.ogg']) {
      final hit = audio.where((f) => (f['name'] as String).toLowerCase().endsWith(ext));
      if (hit.isNotEmpty) return hit.first;
    }
    return audio.first;
  }

  Future<Map<String, dynamic>?> track(String identifier) async {
    final cached = engineCache.get<Map<String, dynamic>>('archive:track:$identifier');
    if (cached != null) return cached;
    try {
      final res = await engineDio.get<Map<String, dynamic>>(
        'https://archive.org/metadata/${Uri.encodeComponent(identifier)}',
      );
      final meta = (res.data?['metadata'] as Map?)?.cast<String, dynamic>();
      if (meta == null) return null;
      final base = _toTrack({
        'identifier': identifier,
        'title': meta['title'] ?? identifier,
        'creator': meta['creator'],
      });
      if (base == null) return null;
      final picked = _pickAudioFile((res.data?['files'] as List?) ?? const []);
      final lenSec = double.tryParse('${picked?['length'] ?? ''}');
      if (lenSec != null && lenSec > 0) {
        base['duration_ms'] = (lenSec * 1000).round();
      }
      engineCache.set('archive:track:$identifier', base, const Duration(minutes: 15));
      return base;
    } catch (_) {
      return null;
    }
  }

  Future<ResolvedStreamResult?> resolveStream(String identifier) async {
    final cached = engineCache.get<ResolvedStreamResult>('archive:stream:$identifier');
    if (cached != null && cached.expiresAtMs > DateTime.now().millisecondsSinceEpoch) {
      return cached;
    }
    try {
      final res = await engineDio.get<Map<String, dynamic>>(
        'https://archive.org/metadata/${Uri.encodeComponent(identifier)}',
      );
      final picked = _pickAudioFile((res.data?['files'] as List?) ?? const []);
      final fileName = picked?['name'] as String?;
      if (fileName == null || fileName.isEmpty) return null;
      final encodedPath = fileName.split('/').map(Uri.encodeComponent).join('/');
      final url = 'https://archive.org/download/${Uri.encodeComponent(identifier)}/$encodedPath';
      registerAllowedHost(url);
      final lower = fileName.toLowerCase();
      final mime = lower.endsWith('.m4a')
          ? 'audio/mp4'
          : lower.endsWith('.flac')
              ? 'audio/flac'
              : lower.endsWith('.ogg')
                  ? 'audio/ogg'
                  : 'audio/mpeg';
      final result = ResolvedStreamResult(
        kind: 'direct',
        url: url,
        mime: mime,
        expiresAtMs: DateTime.now().millisecondsSinceEpoch + 6 * 3600 * 1000,
      );
      engineCache.set('archive:stream:$identifier', result, const Duration(minutes: 30));
      return result;
    } catch (_) {
      return null;
    }
  }
}
