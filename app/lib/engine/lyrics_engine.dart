// language: Dart, file: lib/engine/lyrics_engine.dart, target: mobile + desktop, runtime: resong engine
import 'dart:convert';

import 'package:dio/dio.dart';

import 'addon_client.dart';
import 'engine_utils.dart';
import 'spotify_client.dart';
import 'ytmusic_client.dart';

class _LyricsCandidate {
  _LyricsCandidate({
    this.title,
    this.artist,
    this.album,
    this.durationSec,
    this.plain,
    this.synced,
    this.wordSynced = false,
    this.richLines,
    this.romanizedSynced,
    required this.source,
  });

  final String? title;
  final String? artist;
  final String? album;
  final int? durationSec;
  final String? plain;
  final String? synced;
  final bool wordSynced;
  final List<Map<String, dynamic>>? richLines;
  final String? romanizedSynced;
  final String source;
}

class _ScoredLyrics {
  _ScoredLyrics({
    required this.candidate,
    required this.grade,
    required this.score,
    required this.fingerprint,
    required this.sourcePriority,
  });

  final _LyricsCandidate candidate;
  final int grade; // 2 word-synced, 1 line-synced, 0 plain
  final int score;
  final String fingerprint;
  final int sourcePriority;
}

class LyricsEngine {
  LyricsEngine._();
  static final LyricsEngine instance = LyricsEngine._();

  static const _sourcePriority = {
    'lyricsplus': 4,
    'netease': 4,
    'lrclib': 3,
    'addon': 2,
    'ytmusic': 1,
  };

  static const _lyricsPlusMirrors = [
    'https://lyricsplus.prjktla.my.id/v2/lyrics/get',
    'https://lyrics.binimum.org/v2/lyrics/get',
  ];

  static final _creditLineRx = RegExp(
    r'^(?:作词|作曲|编曲|制作人|混音|母带|出品|和声|监制|录音|吉他|贝斯|鼓|弦乐|文案|企划|统筹)\s*[:：]',
  );

  List<double> _parseTimestampsSec(String synced) {
    final out = <double>[];
    final rx = RegExp(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]');
    for (final m in rx.allMatches(synced)) {
      final min = int.parse(m.group(1)!);
      final sec = int.parse(m.group(2)!);
      final fracRaw = m.group(3);
      final frac = fracRaw != null ? int.parse(fracRaw.padRight(3, '0').substring(0, 3)) / 1000.0 : 0.0;
      out.add(min * 60 + sec + frac);
    }
    return out;
  }

  bool _hasDriftAnomaly(String? synced, int? durationSec) {
    if (synced == null || synced.isEmpty) return false;
    final stamps = _parseTimestampsSec(synced);
    if (stamps.isEmpty) return true;
    if (durationSec != null && durationSec > 0) {
      final maxTs = stamps.reduce((a, b) => a > b ? a : b);
      if (maxTs - durationSec > 3) return true;
    }
    for (var i = 1; i < stamps.length; i++) {
      if (stamps[i] < stamps[i - 1] - 3 && stamps[i - 1] - stamps[i] > 3) return true;
    }
    return false;
  }

  bool _isTruncated(String? plain, String? synced, int? durationSec) {
    final body = (plain ?? synced ?? '').trim();
    if (body.isEmpty) return true;
    if (RegExp(r'(\.\.\.\s*(?:lyrics\s+are\s+truncated|truncated|\[\.\.\.\])|incomplete\s+lyrics|\*\*\*\*\*|not\s+all\s+lyrics)',
            caseSensitive: false)
        .hasMatch(body)) {
      return true;
    }
    final lines = body
        .split(RegExp(r'\r?\n'))
        .map((l) => l.replaceAll(RegExp(r'\[\d{1,3}:\d{2}(?:[.:]\d{1,3})?\]'), '').trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (durationSec != null && durationSec > 60 && lines.length < 4) return true;
    return false;
  }

  String _fingerprint(_LyricsCandidate cand, String track, String? artist, int? durationSec) {
    final ext = extractCleanTrack(track, artist);
    final t = normCompareText(cand.title != null ? extractCleanTrack(cand.title!, cand.artist).track : ext.track);
    final a = normCompareText(cand.artist ?? ext.artist ?? '');
    final dur = (cand.durationSec != null && cand.durationSec! > 0) ? cand.durationSec! : (durationSec ?? 0);
    final bucket = dur > 0 ? (dur / 5).round() : 0;
    return '$t|$a|$bucket';
  }

  _ScoredLyrics? _scoreCandidate(
    _LyricsCandidate cand, {
    required String queryTrack,
    String? queryArtist,
    String? queryAlbum,
    int? queryDurationSec,
    String? isrc,
    String? spId,
    int maxDurationDiff = 10,
    bool requireStrongMeta = false,
  }) {
    if ((cand.plain?.trim().isEmpty ?? true) && (cand.synced?.trim().isEmpty ?? true)) return null;
    var score = 0;
    final extracted = extractCleanTrack(queryTrack, queryArtist);
    final candTitleClean = cand.title != null ? extractCleanTrack(cand.title!, cand.artist).track : '';
    final titleSim = cand.title != null
        ? tokenSimilarity(extracted.track, candTitleClean.isNotEmpty ? candTitleClean : cand.title!)
        : 0.7;
    if (cand.title != null && titleSim < (requireStrongMeta ? 0.72 : 0.45)) return null;

    final effectiveArtist = queryArtist != null && queryArtist.isNotEmpty ? cleanArtistName(queryArtist) : extracted.artist;
    var artistSim = 0.6;
    if (effectiveArtist != null && effectiveArtist.isNotEmpty) {
      artistSim = cand.artist != null ? tokenSimilarity(effectiveArtist, cleanArtistName(cand.artist!)) : 0.5;
      if (cand.artist != null && artistSim < (requireStrongMeta ? 0.55 : 0.3)) return null;
    }

    if (queryDurationSec != null && queryDurationSec > 0 && cand.durationSec != null && cand.durationSec! > 0) {
      final diff = (cand.durationSec! - queryDurationSec).abs();
      if (diff > maxDurationDiff) return null;
      if (diff <= 3) {
        score += 35;
      } else if (diff <= 10) {
        score += (((10 - diff) / 7) * 15).round();
      } else {
        if (titleSim < 0.72 || (effectiveArtist != null && cand.artist != null && artistSim < 0.55)) return null;
        score -= (60 + ((diff - 10) / (maxDurationDiff - 10).clamp(1, 999)) * 40).round();
      }
    }

    score += (titleSim * 40).round();
    if (effectiveArtist != null && effectiveArtist.isNotEmpty) score += (artistSim * 30).round();
    if (queryAlbum != null && cand.album != null) score += (tokenSimilarity(queryAlbum, cand.album!) * 15).round();

    final wordSynced = cand.wordSynced && (cand.synced?.isNotEmpty ?? false);
    final grade = wordSynced ? 2 : ((cand.synced?.isNotEmpty ?? false) ? 1 : 0);
    if (grade == 2) {
      score += 400;
    } else if (grade == 1) {
      score += 200;
    }

    if (cand.source != 'ytmusic') score += 25;

    if ((isrc != null || spId != null) &&
        queryAlbum != null &&
        cand.album != null &&
        tokenSimilarity(queryAlbum, cand.album!) >= 0.7 &&
        queryDurationSec != null &&
        cand.durationSec != null &&
        (cand.durationSec! - queryDurationSec).abs() <= 3) {
      score += 30;
    }

    final effDur = (maxDurationDiff > 10 && cand.durationSec != null)
        ? (queryDurationSec != null && queryDurationSec > cand.durationSec! ? queryDurationSec : cand.durationSec)
        : queryDurationSec;
    if (_hasDriftAnomaly(cand.synced, effDur)) score -= 50;
    if (_isTruncated(cand.plain, cand.synced, effDur)) score -= 500;

    return _ScoredLyrics(
      candidate: cand,
      grade: grade,
      score: score,
      fingerprint: _fingerprint(cand, queryTrack, queryArtist, queryDurationSec),
      sourcePriority: _sourcePriority[cand.source] ?? 1,
    );
  }

  List<_ScoredLyrics> _rank(
    List<_LyricsCandidate> pool, {
    required String queryTrack,
    String? queryArtist,
    String? queryAlbum,
    int? queryDurationSec,
    String? isrc,
    String? spId,
    int maxDurationDiff = 10,
    bool requireStrongMeta = false,
  }) {
    final scored = <_ScoredLyrics>[];
    for (final c in pool) {
      final s = _scoreCandidate(
        c,
        queryTrack: queryTrack,
        queryArtist: queryArtist,
        queryAlbum: queryAlbum,
        queryDurationSec: queryDurationSec,
        isrc: isrc,
        spId: spId,
        maxDurationDiff: maxDurationDiff,
        requireStrongMeta: requireStrongMeta,
      );
      if (s != null) scored.add(s);
    }
    if (scored.isEmpty) return const [];

    int cmp(_ScoredLyrics a, _ScoredLyrics b) {
      if (a.grade != b.grade) return b.grade - a.grade;
      if (a.score != b.score) {
        if ((a.score - b.score).abs() < 15 && a.sourcePriority != b.sourcePriority) {
          return b.sourcePriority - a.sourcePriority;
        }
        return b.score - a.score;
      }
      return b.sourcePriority - a.sourcePriority;
    }

    final deduped = <String, _ScoredLyrics>{};
    for (final s in scored) {
      final prev = deduped[s.fingerprint];
      if (prev == null || cmp(s, prev) < 0) deduped[s.fingerprint] = s;
    }
    final list = deduped.values.toList()..sort(cmp);
    return list;
  }

  String _formatLrcTime(int ms) {
    final safe = ms < 0 ? 0 : ms;
    final min = safe ~/ 60000;
    final sec = (safe % 60000) ~/ 1000;
    final cs = (safe % 1000) ~/ 10;
    return '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}.${cs.toString().padLeft(2, '0')}';
  }

  ({String lead, String? bg, bool isBackground}) _splitBackgroundVocals(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return (lead: '', bg: null, isBackground: false);
    final full = RegExp(r'^[(（]([^()（）]{2,})[)）]$').firstMatch(trimmed);
    if (full != null) {
      return (lead: '', bg: trimmed, isBackground: true);
    }
    final trailing = RegExp(r'^(.*?)\s+([(（][^()（）]{2,}[)）])$').firstMatch(trimmed);
    if (trailing != null && trailing.group(1)!.trim().length >= 3) {
      return (lead: trailing.group(1)!.trim(), bg: trailing.group(2)!.trim(), isBackground: false);
    }
    return (lead: trimmed, bg: null, isBackground: false);
  }

  List<Map<String, dynamic>> _tagWordsBackground(
    List<Map<String, dynamic>> words,
    ({String lead, String? bg, bool isBackground}) split,
  ) {
    if (split.bg == null && !split.isBackground) return words;
    if (split.isBackground) {
      return [for (final w in words) {...w, 'bg': true}];
    }
    final leadLen = split.lead.length;
    var cursor = 0;
    return [
      for (final w in words)
        () {
          final start = cursor;
          cursor += (w['text'] as String).length;
          return {...w, 'bg': w['bg'] == true || start >= leadLen};
        }(),
    ];
  }

  ({List<Map<String, dynamic>> richLines, bool hasEnhancedWords}) _buildRichFromLrc(String synced) {
    final lineTagRx = RegExp(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]');
    final wordTagRx = RegExp(r'<(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?>\s*([^<\n]+)');
    final richLines = <Map<String, dynamic>>[];
    var hasEnhancedWords = false;

    int toMs(String m, String s, [String? f]) =>
        int.parse(m) * 60000 + int.parse(s) * 1000 + (f != null ? int.parse(f.padRight(3, '0').substring(0, 3)) : 0);

    for (final rawLine in synced.split(RegExp(r'\r?\n'))) {
      final trimmed = rawLine.trim();
      if (trimmed.isEmpty) continue;
      final stamps = [
        for (final match in lineTagRx.allMatches(trimmed)) toMs(match.group(1)!, match.group(2)!, match.group(3)),
      ];
      if (stamps.isEmpty) continue;
      final body = trimmed.replaceAll(lineTagRx, '').trim();
      if (body.isEmpty) continue;

      final words = <Map<String, dynamic>>[];
      for (final wm in wordTagRx.allMatches(body)) {
        final wText = wm.group(4) ?? '';
        if (wText.isEmpty) continue;
        words.add({'at_ms': toMs(wm.group(1)!, wm.group(2)!, wm.group(3)), 'dur_ms': 0, 'text': wText});
      }
      for (var i = 0; i < words.length; i++) {
        final cur = words[i];
        final next = i + 1 < words.length ? words[i + 1] : null;
        cur['dur_ms'] = next != null ? ((next['at_ms'] as int) - (cur['at_ms'] as int)).clamp(80, 60000) : 450;
      }
      if (words.isNotEmpty) hasEnhancedWords = true;

      final cleanText = body.replaceAll(RegExp(r'<\d{1,3}:\d{2}(?:[.:]\d{1,3})?>\s*'), '').trim();
      if (cleanText.isEmpty) continue;
      final split = _splitBackgroundVocals(cleanText);
      final taggedWords = words.isNotEmpty ? _tagWordsBackground(words, split) : null;

      for (final ts in stamps) {
        richLines.add({
          'at_ms': ts,
          'text': cleanText,
          if (split.lead.isNotEmpty) 'lead_text': split.lead,
          if (split.bg != null) 'bg_text': split.bg,
          if (split.isBackground) 'is_background': true,
          if (taggedWords != null) 'words': taggedWords,
        });
      }
    }
    richLines.sort((a, b) => (a['at_ms'] as int).compareTo(b['at_ms'] as int));
    return (richLines: richLines, hasEnhancedWords: hasEnhancedWords);
  }

  // ---------------- Providers ----------------

  Future<List<_LyricsCandidate>> _fromLrclib(String track, {String? artist, String? album, int? durationSec}) async {
    final out = <_LyricsCandidate>[];
    final headers = {'user-agent': 'resong/0.1 (music app)', 'accept': 'application/json'};

    Future<void> addOne(String url) async {
      try {
        final res = await engineDio.get<Object?>(url, options: Options(headers: headers, receiveTimeout: const Duration(seconds: 7)));
        if (res.statusCode != 200 || res.data == null) return;
        final data = res.data is String ? jsonDecode(res.data as String) : res.data;
        if (data is Map) {
          final p = data['plainLyrics'] as String?;
          final s = data['syncedLyrics'] as String?;
          if ((p?.isNotEmpty ?? false) || (s?.isNotEmpty ?? false)) {
            out.add(_LyricsCandidate(
              title: (data['trackName'] as String?) ?? track,
              artist: (data['artistName'] as String?) ?? artist,
              album: (data['albumName'] as String?) ?? album,
              durationSec: (data['duration'] as num?)?.round(),
              plain: p,
              synced: s,
              source: 'lrclib',
            ));
          }
        } else if (data is List) {
          for (final item in data.whereType<Map>().take(20)) {
            final p = item['plainLyrics'] as String?;
            final s = item['syncedLyrics'] as String?;
            if ((p?.isNotEmpty ?? false) || (s?.isNotEmpty ?? false)) {
              out.add(_LyricsCandidate(
                title: item['trackName'] as String?,
                artist: item['artistName'] as String?,
                album: item['albumName'] as String?,
                durationSec: (item['duration'] as num?)?.round(),
                plain: p,
                synced: s,
                source: 'lrclib',
              ));
            }
          }
        }
      } catch (_) {}
    }

    final exact = Uri.https('lrclib.net', '/api/get', {
      'track_name': track,
      if (artist != null && artist.isNotEmpty) 'artist_name': artist,
      if (album != null && album.isNotEmpty) 'album_name': album,
      if (durationSec != null && durationSec > 0) 'duration': '$durationSec',
    }).toString();
    final search = Uri.https('lrclib.net', '/api/search', {
      'track_name': track,
      if (artist != null && artist.isNotEmpty) 'artist_name': artist,
    }).toString();
    final titleOnly = (artist != null && artist.isNotEmpty)
        ? Uri.https('lrclib.net', '/api/search', {'track_name': track}).toString()
        : null;

    await Future.wait([
      addOne(exact),
      addOne(search),
      if (titleOnly != null) addOne(titleOnly),
    ]);
    return out;
  }

  Future<List<_LyricsCandidate>> _fromLyricsPlus(String track, {String? artist, String? album, int? durationSec}) async {
    if (track.isEmpty) return const [];
    final out = <_LyricsCandidate>[];
    for (final base in _lyricsPlusMirrors) {
      try {
        final uri = Uri.parse(base).replace(queryParameters: {
          'title': track,
          if (artist != null && artist.isNotEmpty) 'artist': artist,
          if (album != null && album.isNotEmpty) 'album': album,
          if (durationSec != null && durationSec > 0) 'duration': '$durationSec',
        });
        final res = await engineDio.get<Object?>(
          uri.toString(),
          options: Options(headers: {'user-agent': 'resong/0.1', 'accept': 'application/json'}, receiveTimeout: const Duration(seconds: 6)),
        );
        if (res.statusCode != 200 || res.data == null) continue;
        final body = (res.data is String ? jsonDecode(res.data as String) : res.data) as Map?;
        final rawLyrics = body?['lyrics'] as List?;
        if (rawLyrics == null || rawLyrics.isEmpty) continue;

        final syncedLines = <String>[];
        final plainLines = <String>[];
        final richLines = <Map<String, dynamic>>[];
        var hasWordSync = false;

        for (final line in rawLyrics.whereType<Map>()) {
          final syllabus = line['syllabus'] as List?;
          if (syllabus != null && syllabus.isNotEmpty) hasWordSync = true;
          final text = (line['text'] as String?)?.trim() ??
              (syllabus?.whereType<Map>().map((w) => '${w['text'] ?? ''}').join().trim() ?? '');
          if (text.isEmpty) continue;
          plainLines.add(text);

          final tMs = (line['time'] as num?)?.round() ?? (line['startTimeMs'] as num?)?.round();
          final dMs = (line['duration'] as num?)?.round();
          final split = _splitBackgroundVocals(text);
          final elemBg = line['isBackground'] == true ||
              (line['element'] as Map?)?['isBackground'] == true ||
              split.isBackground;
          final rom = ((line['transliteration'] as String?) ?? (line['romanized'] as String?))?.trim();

          final words = <Map<String, dynamic>>[];
          if (syllabus != null) {
            for (final w in syllabus.whereType<Map>()) {
              final wText = '${w['text'] ?? ''}';
              if (wText.isEmpty) continue;
              words.add({
                'at_ms': (w['time'] as num?)?.round() ?? (tMs ?? 0),
                'dur_ms': (w['duration'] as num?)?.round() ?? 250,
                'text': wText,
                if (elemBg || w['isBackground'] == true) 'bg': true,
              });
            }
          }
          final finalWords = words.isNotEmpty ? _tagWordsBackground(words, split) : null;

          if (tMs != null && tMs >= 0) {
            syncedLines.add('[${_formatLrcTime(tMs)}] $text');
            richLines.add({
              'at_ms': tMs,
              if (dMs != null) 'dur_ms': dMs,
              'text': text,
              if (!elemBg && split.lead.isNotEmpty) 'lead_text': split.lead,
              if (elemBg || split.bg != null) 'bg_text': elemBg ? text : split.bg,
              if (elemBg) 'is_background': true,
              if (rom != null && rom.isNotEmpty) 'romanized': rom,
              if (finalWords != null) 'words': finalWords,
            });
          }
        }
        if (plainLines.isEmpty) continue;

        final meta = (body?['metadata'] as Map?) ?? const {};
        final durRaw = meta['duration'] as num?;
        final durSec = durRaw != null ? (durRaw > 10000 ? (durRaw / 1000).round() : durRaw.round()) : durationSec;
        out.add(_LyricsCandidate(
          title: (meta['title'] as String?) ?? track,
          artist: (meta['artist'] as String?) ?? artist,
          album: (meta['album'] as String?) ?? album,
          durationSec: durSec,
          plain: plainLines.join('\n'),
          synced: syncedLines.isNotEmpty ? syncedLines.join('\n') : null,
          wordSynced: hasWordSync,
          richLines: richLines.isNotEmpty ? richLines : null,
          source: 'lyricsplus',
        ));
        break;
      } catch (_) {}
    }
    return out;
  }

  List<({int atMs, String text})> _parseRomaLrc(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    final rx = RegExp(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]');
    final out = <({int atMs, String text})>[];
    for (final line in raw.split(RegExp(r'\r?\n'))) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final text = trimmed.replaceAll(rx, '').trim();
      if (text.isEmpty) continue;
      for (final m in rx.allMatches(trimmed)) {
        final ms = int.parse(m.group(1)!) * 60000 +
            int.parse(m.group(2)!) * 1000 +
            (m.group(3) != null ? int.parse(m.group(3)!.padRight(3, '0').substring(0, 3)) : 0);
        out.add((atMs: ms, text: text));
      }
    }
    out.sort((a, b) => a.atMs.compareTo(b.atMs));
    return out;
  }

  ({String plain, String synced, List<Map<String, dynamic>> richLines, bool wordSynced})? _parseNeteaseYrc(
    String rawYrc,
    String? romaRaw,
  ) {
    final romaLines = _parseRomaLrc(romaRaw);
    final plainLines = <String>[];
    final syncedLines = <String>[];
    final richLines = <Map<String, dynamic>>[];
    var hasWords = false;
    final lineRx = RegExp(r'^\[(\d+),(\d+)\](.*)$');
    final wordRx = RegExp(r'\((\d+),(\d+),\d+\)([\s\S]*?)(?=\(\d+,\d+,\d+\)|$)');

    for (final rawLine in rawYrc.split(RegExp(r'\r?\n'))) {
      final lm = lineRx.firstMatch(rawLine.trim());
      if (lm == null) continue;
      final atMs = int.parse(lm.group(1)!);
      final durMs = int.parse(lm.group(2)!);
      final rest = lm.group(3) ?? '';

      final words = <Map<String, dynamic>>[];
      final joined = StringBuffer();
      for (final wm in wordRx.allMatches(rest)) {
        final token = wm.group(3) ?? '';
        joined.write(token);
        if (token.isNotEmpty) {
          words.add({
            'at_ms': int.parse(wm.group(1)!),
            'dur_ms': int.parse(wm.group(2)!).clamp(40, 60000),
            'text': token,
          });
        }
      }
      final cleanText = (joined.isNotEmpty ? joined.toString() : rest).trim();
      if (cleanText.isEmpty || _creditLineRx.hasMatch(cleanText)) continue;
      if (words.isNotEmpty) hasWords = true;

      final split = _splitBackgroundVocals(cleanText);
      final taggedWords = words.isNotEmpty ? _tagWordsBackground(words, split) : null;
      String? romaText;
      var bestDiff = 851;
      for (final r in romaLines) {
        final diff = (r.atMs - atMs).abs();
        if (diff < bestDiff) {
          bestDiff = diff;
          romaText = r.text;
        }
      }

      plainLines.add(cleanText);
      syncedLines.add('[${_formatLrcTime(atMs)}] $cleanText');
      richLines.add({
        'at_ms': atMs,
        if (durMs > 0) 'dur_ms': durMs,
        'text': cleanText,
        if (!split.isBackground && split.lead.isNotEmpty) 'lead_text': split.lead,
        if (split.isBackground || split.bg != null) 'bg_text': split.isBackground ? cleanText : split.bg,
        if (split.isBackground) 'is_background': true,
        if (romaText != null) 'romanized': romaText,
        if (taggedWords != null) 'words': taggedWords,
      });
    }

    if (richLines.isEmpty) return null;
    return (
      plain: plainLines.join('\n'),
      synced: syncedLines.join('\n'),
      richLines: richLines,
      wordSynced: hasWords,
    );
  }

  Future<List<_LyricsCandidate>> _fromNetease(String track, {String? artist, String? album, int? durationSec}) async {
    if (track.isEmpty) return const [];
    final out = <_LyricsCandidate>[];
    final headers = {'user-agent': 'Mozilla/5.0', 'accept': 'application/json'};
    try {
      final q = [track, if (artist != null && artist.isNotEmpty) artist].join(' ');
      final sRes = await engineDio.get<Object?>(
        'https://music.163.com/api/search/get?s=${Uri.encodeQueryComponent(q)}&type=1&limit=3',
        options: Options(headers: headers, receiveTimeout: const Duration(seconds: 5)),
      );
      final sBody = (sRes.data is String ? jsonDecode(sRes.data as String) : sRes.data) as Map?;
      final songs = ((sBody?['result'] as Map?)?['songs'] as List?)?.whereType<Map>().take(2) ?? const [];
      for (final song in songs) {
        final songId = song['id'];
        final lRes = await engineDio.get<Object?>(
          'https://music.163.com/api/song/lyric?id=$songId&lv=1&tv=1&rv=1&yv=1',
          options: Options(headers: headers, receiveTimeout: const Duration(seconds: 5)),
        );
        if (lRes.statusCode != 200 || lRes.data == null) continue;
        final lBody = (lRes.data is String ? jsonDecode(lRes.data as String) : lRes.data) as Map?;
        final songDurRaw = song['duration'] as num?;
        final songDur = songDurRaw != null ? (songDurRaw / 1000).round() : durationSec;
        final songArtist = ((song['artists'] as List?)?.whereType<Map>().map((a) => '${a['name'] ?? ''}').join(', '));
        final yrcRaw = ((lBody?['yrc'] as Map?)?['lyric'] as String?)?.trim();
        final romaRaw = (lBody?['romalrc'] as Map?)?['lyric'] as String?;

        if (yrcRaw != null && yrcRaw.isNotEmpty) {
          final parsed = _parseNeteaseYrc(yrcRaw, romaRaw);
          if (parsed != null) {
            out.add(_LyricsCandidate(
              title: (song['name'] as String?) ?? track,
              artist: (songArtist != null && songArtist.isNotEmpty) ? songArtist : artist,
              album: ((song['album'] as Map?)?['name'] as String?) ?? album,
              durationSec: songDur,
              plain: parsed.plain,
              synced: parsed.synced,
              wordSynced: parsed.wordSynced,
              richLines: parsed.richLines,
              romanizedSynced: romaRaw,
              source: 'netease',
            ));
            continue;
          }
        }

        final lrcRaw = ((lBody?['lrc'] as Map?)?['lyric'] as String?)?.trim();
        if (lrcRaw != null && lrcRaw.isNotEmpty) {
          final plainOnly = lrcRaw
              .split(RegExp(r'\r?\n'))
              .map((l) => l.replaceAll(RegExp(r'\[\d{1,3}:\d{2}(?:[.:]\d{1,3})?\]'), '').trim())
              .where((l) => l.isNotEmpty && !_creditLineRx.hasMatch(l))
              .join('\n');
          if (plainOnly.isNotEmpty) {
            out.add(_LyricsCandidate(
              title: (song['name'] as String?) ?? track,
              artist: (songArtist != null && songArtist.isNotEmpty) ? songArtist : artist,
              album: ((song['album'] as Map?)?['name'] as String?) ?? album,
              durationSec: songDur,
              plain: plainOnly,
              synced: lrcRaw,
              romanizedSynced: romaRaw,
              source: 'netease',
            ));
          }
        }
      }
    } catch (_) {}
    return out;
  }

  Future<Map<String, dynamic>?> getLyrics({
    required String track,
    String? artist,
    String? album,
    int? durationSec,
    String? videoId,
    String? isrc,
    String? spId,
  }) async {
    final extracted = extractCleanTrack(track, artist);
    var cleanTrack = extracted.track.isNotEmpty ? extracted.track : cleanMusicQuery(track);
    if (cleanTrack.isEmpty) cleanTrack = track.trim();
    var cleanArtist = (artist != null && artist.isNotEmpty) ? cleanArtistName(artist) : extracted.artist;
    var effectiveAlbum = album;
    var effectiveDur = durationSec;
    var effectiveIsrc = isrc;

    var hasSpotifyMeta = false;
    if (spId != null && spId.startsWith('sp:track:')) {
      final spTrack = await SpotifyClient.instance.track(spId.substring(9));
      if (spTrack != null) {
        hasSpotifyMeta = true;
        cleanTrack = spTrack['title'] as String? ?? cleanTrack;
        final aList = (spTrack['artists'] as List?)?.cast<String>() ?? const [];
        if (aList.isNotEmpty) cleanArtist = aList.first;
        effectiveAlbum ??= spTrack['album'] as String?;
        final dMs = (spTrack['duration_ms'] as num?)?.toInt();
        if (dMs != null) effectiveDur = (dMs / 1000).round();
        effectiveIsrc ??= (spTrack['extra'] as Map?)?['isrc'] as String?;
      }
    } else if (SpotifyClient.instance.isEnabled && cleanTrack.isNotEmpty) {
      final q = [cleanTrack, if (cleanArtist != null) cleanArtist].join(' ').trim();
      final sp = await SpotifyClient.instance.search(q, limit: 3);
      for (final t in sp['tracks'] ?? const []) {
        final tTitle = t['title'] as String? ?? '';
        final tArtists = (t['artists'] as List?)?.cast<String>() ?? const [];
        final extT = extractCleanTrack(tTitle, tArtists.firstOrNull);
        if (tokenSimilarity(cleanTrack, extT.track.isNotEmpty ? extT.track : tTitle) < 0.72) continue;
        if (cleanArtist != null && !tArtists.any((a) => tokenSimilarity(cleanArtist!, cleanArtistName(a)) >= 0.55)) continue;
        hasSpotifyMeta = true;
        spId = t['id'] as String?;
        cleanTrack = extT.track.isNotEmpty ? extT.track : tTitle;
        if (tArtists.isNotEmpty) cleanArtist = tArtists.first;
        effectiveAlbum ??= t['album'] as String?;
        final dMs = (t['duration_ms'] as num?)?.toInt();
        if (dMs != null) effectiveDur = (dMs / 1000).round();
        effectiveIsrc ??= (t['extra'] as Map?)?['isrc'] as String?;
        break;
      }
    }

    final durBucket = effectiveDur != null ? (effectiveDur / 5).round().toString() : '';
    final cacheKey = 'lyrics:v5:$cleanTrack|${cleanArtist ?? ''}|${effectiveAlbum ?? ''}|${effectiveIsrc ?? ''}|$durBucket';
    final cached = engineCache.get<Map<String, dynamic>>(cacheKey);
    if (cached != null) return cached;

    final results = await Future.wait([
      if (hasSpotifyMeta) _fromLrclib(cleanTrack, artist: cleanArtist, album: effectiveAlbum, durationSec: effectiveDur) else Future.value(const <_LyricsCandidate>[]),
      _fromLrclib(track, artist: artist, album: album, durationSec: durationSec),
      if (cleanTrack != track || cleanArtist != artist) _fromLrclib(cleanTrack, artist: cleanArtist, album: effectiveAlbum, durationSec: effectiveDur) else Future.value(const <_LyricsCandidate>[]),
      _fromLyricsPlus(cleanTrack, artist: cleanArtist, album: effectiveAlbum, durationSec: effectiveDur),
      _fromNetease(cleanTrack, artist: cleanArtist, album: effectiveAlbum, durationSec: effectiveDur),
      if (videoId != null && videoId.isNotEmpty) YtMusicClient.instance.getPlainLyrics(videoId) else Future.value(null),
      AddonClient.instance.lyricsCandidates(track: cleanTrack, artist: cleanArtist, album: effectiveAlbum, durationSec: effectiveDur),
    ]);

    final pool = <_LyricsCandidate>[
      ...(results[0] as List<_LyricsCandidate>),
      ...(results[1] as List<_LyricsCandidate>),
      ...(results[2] as List<_LyricsCandidate>),
      ...(results[3] as List<_LyricsCandidate>),
      ...(results[4] as List<_LyricsCandidate>),
    ];
    final ytPlain = results[5] as String?;
    if (ytPlain != null && ytPlain.isNotEmpty) {
      pool.add(_LyricsCandidate(title: track, artist: artist, durationSec: durationSec, plain: ytPlain, source: 'ytmusic'));
    }
    for (final a in results[6] as List<Map<String, dynamic>>) {
      pool.add(_LyricsCandidate(
        title: a['title'] as String?,
        artist: a['artist'] as String?,
        album: a['album'] as String?,
        durationSec: a['duration'] as int?,
        plain: a['plain'] as String?,
        synced: a['synced'] as String?,
        wordSynced: a['word_synced'] == true,
        source: 'addon',
      ));
    }

    var ranked = _rank(
      pool,
      queryTrack: cleanTrack,
      queryArtist: cleanArtist,
      queryAlbum: effectiveAlbum,
      queryDurationSec: effectiveDur,
      isrc: effectiveIsrc,
      spId: spId,
    );
    if (ranked.isEmpty && effectiveDur != null && effectiveDur > 0) {
      ranked = _rank(
        pool,
        queryTrack: cleanTrack,
        queryArtist: cleanArtist,
        queryAlbum: effectiveAlbum,
        queryDurationSec: effectiveDur,
        isrc: effectiveIsrc,
        spId: spId,
        maxDurationDiff: 35,
        requireStrongMeta: true,
      );
    }
    if (ranked.isEmpty) return null;

    final winner = ranked.first;
    var richLines = winner.candidate.richLines;
    var wordSynced = winner.grade == 2;
    if ((richLines == null || richLines.isEmpty) && winner.candidate.synced != null) {
      final parsed = _buildRichFromLrc(winner.candidate.synced!);
      richLines = parsed.richLines;
      if (parsed.hasEnhancedWords) wordSynced = true;
    }

    final hasBg = richLines?.any((l) => l['is_background'] == true || l['bg_text'] != null) ?? false;
    final payload = <String, dynamic>{
      'plain': winner.candidate.plain,
      'synced': winner.candidate.synced,
      'source': winner.candidate.source,
      'word_synced': wordSynced,
      'score': winner.score,
      if (richLines != null && richLines.isNotEmpty) 'lines': richLines,
      'has_karaoke': wordSynced || (richLines?.any((l) => ((l['words'] as List?)?.isNotEmpty ?? false)) ?? false),
      'has_background': hasBg,
      if (winner.candidate.romanizedSynced != null) 'romanized_synced': winner.candidate.romanizedSynced,
    };
    engineCache.set(cacheKey, payload, const Duration(hours: 12));
    return payload;
  }
}
