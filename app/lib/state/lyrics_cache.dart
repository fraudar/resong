// language: Dart, file: lib/state/lyrics_cache.dart, target: mobile-first + desktop, runtime: resong app
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import '../core/models.dart';
import 'providers.dart';

@immutable
class LrcLine {
  const LrcLine(this.at, this.text);
  final Duration at;
  final String text;
}

final _offsetRegex = RegExp(r'^\[offset:\s*([+-]?\d+)\s*\]$', caseSensitive: false);
final _tagRegex = RegExp(r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]');
final _inlineWordRegex = RegExp(r'<(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?>\s*');

/// Parser LRC completo: suporta `[offset:±ms]`, múltiplos timestamps por linha e remove tags `<mm:ss.xx>`.
List<LrcLine> parseLrc(String raw) {
  if (raw.trim().isEmpty) return const [];
  var offsetMs = 0;
  final parsed = <({int rawMs, String text})>[];

  for (final line in raw.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;

    final offsetMatch = _offsetRegex.firstMatch(trimmed);
    if (offsetMatch != null) {
      offsetMs = int.tryParse(offsetMatch.group(1)!) ?? 0;
      continue;
    }

    final matches = _tagRegex.allMatches(trimmed).toList();
    if (matches.isEmpty) continue;

    final lyric = trimmed.replaceAll(_tagRegex, '').replaceAll(_inlineWordRegex, '').trim();
    if (lyric.isEmpty) continue;

    for (final m in matches) {
      final min = int.parse(m.group(1)!);
      final sec = int.parse(m.group(2)!);
      final frac = m.group(3) ?? '0';
      final ms = int.parse(frac.padRight(3, '0').substring(0, 3));
      parsed.add((rawMs: min * 60000 + sec * 1000 + ms, text: lyric));
    }
  }

  final out = [
    for (final item in parsed)
      LrcLine(Duration(milliseconds: (item.rawMs - offsetMs).clamp(0, 86400000)), item.text),
  ]..sort((a, b) => a.at.compareTo(b.at));
  return out;
}

({String lead, String? bg, bool isBg}) splitBackgroundVocals(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return (lead: '', bg: null, isBg: false);
  final full = RegExp(r'^[(（]([^()（）]{2,})[)）]$').firstMatch(trimmed);
  if (full != null) {
    return (lead: '', bg: trimmed, isBg: true);
  }
  final trailing = RegExp(r'^(.*?)\s+([(（][^()（）]{2,}[)）])$').firstMatch(trimmed);
  if (trailing != null && trailing.group(1)!.trim().length >= 3) {
    return (lead: trailing.group(1)!.trim(), bg: trailing.group(2)!.trim(), isBg: false);
  }
  return (lead: trimmed, bg: null, isBg: false);
}

List<LyricRichLine> resolveRichLines(Lyrics lyrics) {
  if (lyrics.lines.isNotEmpty) return lyrics.lines;
  final raw = lyrics.synced ?? '';
  if (raw.trim().isEmpty) return const [];

  var offsetMs = 0;
  final out = <LyricRichLine>[];
  final wordRx = RegExp(r'<(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?>\s*([^<\n]+)');

  int parseStampMs(String m, String s, String? frac) {
    final ms = int.parse((frac ?? '0').padRight(3, '0').substring(0, 3));
    return int.parse(m) * 60000 + int.parse(s) * 1000 + ms;
  }

  for (final line in raw.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    final offsetMatch = _offsetRegex.firstMatch(trimmed);
    if (offsetMatch != null) {
      offsetMs = int.tryParse(offsetMatch.group(1)!) ?? 0;
      continue;
    }
    final stamps = _tagRegex.allMatches(trimmed).toList();
    if (stamps.isEmpty) continue;
    final body = trimmed.replaceAll(_tagRegex, '').trim();
    if (body.isEmpty) continue;

    final rawWords = <LyricWordToken>[];
    for (final wm in wordRx.allMatches(body)) {
      final t = wm.group(4) ?? '';
      if (t.isEmpty) continue;
      rawWords.add(
        LyricWordToken(
          atMs: (parseStampMs(wm.group(1)!, wm.group(2)!, wm.group(3)) - offsetMs).clamp(0, 86400000),
          durMs: 350,
          text: t,
        ),
      );
    }
    final words = <LyricWordToken>[];
    for (var i = 0; i < rawWords.length; i++) {
      final w = rawWords[i];
      final dur = i + 1 < rawWords.length ? (rawWords[i + 1].atMs - w.atMs).clamp(60, 4000) : 450;
      words.add(LyricWordToken(atMs: w.atMs, durMs: dur, text: w.text));
    }

    final clean = body.replaceAll(_inlineWordRegex, '').trim();
    if (clean.isEmpty) continue;
    final split = splitBackgroundVocals(clean);
    for (final m in stamps) {
      final atMs = (parseStampMs(m.group(1)!, m.group(2)!, m.group(3)) - offsetMs).clamp(0, 86400000);
      out.add(
        LyricRichLine(
          atMs: atMs,
          text: clean,
          leadText: split.isBg ? null : split.lead,
          bgText: split.isBg ? clean : split.bg,
          isBackground: split.isBg,
          words: words,
        ),
      );
    }
  }
  out.sort((a, b) => a.atMs.compareTo(b.atMs));
  return out;
}

/// Calcula tokens por palavra para Karaokê (usa timing real por sílaba/palavra ou interpolação proporcional).
List<LyricWordToken> wordsForKaraokeText(
  String text,
  List<LyricWordToken> explicitWords,
  int lineAtMs,
  int lineEndMs, {
  bool filterBg = false,
}) {
  if (explicitWords.isNotEmpty) {
    final picked = filterBg ? explicitWords.where((w) => !w.isBackground).toList() : explicitWords;
    if (picked.isNotEmpty) return picked;
  }
  final clean = text.trim();
  if (clean.isEmpty) return const [];
  final matches = RegExp(r'\S+\s*').allMatches(clean).toList();
  if (matches.isEmpty) {
    return [LyricWordToken(atMs: lineAtMs, durMs: (lineEndMs - lineAtMs).clamp(300, 12000), text: clean)];
  }
  final totalSpan = (lineEndMs - lineAtMs).clamp(400, 12000);
  final totalChars = matches.fold<int>(0, (s, m) => s + m.group(0)!.trimRight().length).clamp(1, 500);
  var cursor = lineAtMs;
  final out = <LyricWordToken>[];
  for (var i = 0; i < matches.length; i++) {
    final token = matches[i].group(0)!;
    final weight = token.trimRight().length.clamp(1, 60);
    final dur = i == matches.length - 1
        ? (lineAtMs + totalSpan - cursor).clamp(80, 6000)
        : ((totalSpan * weight) ~/ totalChars).clamp(80, 4000);
    out.add(LyricWordToken(atMs: cursor, durMs: dur, text: token));
    cursor += dur;
  }
  return out;
}

bool hasNonLatinScript(String text) =>
    RegExp(r'[\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af\u0400-\u04ff\u0370-\u03ff\u0600-\u06ff\u0e00-\u0e7f]')
        .hasMatch(text);

/// Fallback instantâneo de romanização Unicode para Hangul (coreano) e Cirílico quando offline.
String fallbackRomanize(String input) {
  const initials = [
    'g', 'kk', 'n', 'd', 'tt', 'r', 'm', 'b', 'pp', 's', 'ss', '', 'j', 'jj', 'ch', 'k', 't', 'p', 'h',
  ];
  const medials = [
    'a', 'ae', 'ya', 'yae', 'eo', 'e', 'yeo', 'ye', 'o', 'wa', 'wae', 'oe', 'yo', 'u', 'wo', 'we', 'wi', 'yu', 'eu', 'ui', 'i',
  ];
  const finals = [
    '', 'k', 'k', 'k', 'n', 'n', 'n', 't', 'l', 'l', 'l', 'l', 'l', 'l', 'l', 'l', 'm', 'p', 'p', 't', 't', 'ng', 't', 't', 'k', 't', 'p', 't',
  ];
  const cyrillic = {
    'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd', 'е': 'e', 'ё': 'yo', 'ж': 'zh', 'з': 'z',
    'и': 'i', 'й': 'y', 'к': 'k', 'л': 'l', 'м': 'm', 'н': 'n', 'о': 'o', 'п': 'p', 'р': 'r',
    'с': 's', 'т': 't', 'у': 'u', 'ф': 'f', 'х': 'kh', 'ц': 'ts', 'ч': 'ch', 'ш': 'sh', 'щ': 'shch',
    'ъ': '', 'ы': 'y', 'ь': '', 'э': 'e', 'ю': 'yu', 'я': 'ya',
  };
  final sb = StringBuffer();
  for (final rune in input.runes) {
    if (rune >= 0xAC00 && rune <= 0xD7A3) {
      final code = rune - 0xAC00;
      final l = code ~/ (21 * 28);
      final v = (code % (21 * 28)) ~/ 28;
      final t = code % 28;
      sb.write(initials[l]);
      sb.write(medials[v]);
      sb.write(finals[t]);
    } else {
      final ch = String.fromCharCode(rune);
      final mapped = cyrillic[ch.toLowerCase()];
      if (mapped != null) {
        sb.write(ch == ch.toUpperCase() && mapped.isNotEmpty
            ? '${mapped[0].toUpperCase()}${mapped.substring(1)}'
            : mapped);
      } else {
        sb.write(ch);
      }
    }
  }
  return sb.toString();
}

int activeLrcIndex(List<LrcLine> lines, Duration pos) {
  var active = -1;
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].at <= pos) {
      active = i;
    } else {
      break;
    }
  }
  return active;
}

/// Cache + prefetch automático de letras na entrada da fila.
class LyricsCache {
  LyricsCache._();
  static final LyricsCache instance = LyricsCache._();

  final Map<String, Lyrics?> _cache = {};
  final Map<String, List<LrcLine>> _parsedSynced = {};
  final Map<String, Future<Lyrics?>> _inflight = {};
  final _updates = StreamController<String>.broadcast();

  Stream<String> get updatesStream => _updates.stream;

  bool hasCached(String trackId) => _cache.containsKey(trackId);
  Lyrics? getCached(String trackId) => _cache[trackId];
  List<LrcLine> getParsedSynced(String trackId) => _parsedSynced[trackId] ?? const [];

  @visibleForTesting
  void debugSeedSynced(String trackId, String syncedLrc) {
    _cache[trackId] = Lyrics(plain: syncedLrc, synced: syncedLrc, source: 'lrclib');
    _parsedSynced[trackId] = parseLrc(syncedLrc);
    _updates.add(trackId);
  }

  Future<Lyrics?> getOrFetch(Track track) {
    if (_cache.containsKey(track.id)) {
      return Future.value(_cache[track.id]);
    }
    return _inflight[track.id] ??= _fetch(track);
  }

  Future<Lyrics?> _fetch(Track track) async {
    try {
      final data = await Api.instance.lyrics(
        track: track.title,
        artist: track.artists.isNotEmpty ? track.artists.first : null,
        album: track.album,
        durationMs: track.durationMs,
        videoId: track.extra['video_id'] as String?,
        isrc: track.extra['isrc'] as String?,
        spId: track.id.startsWith('sp:track:') ? track.id : null,
        trackNumber: track.extra['track_number'] is num
            ? (track.extra['track_number'] as num).toInt()
            : null,
      );
      if (data == null) {
        _updates.add(track.id);
        return null;
      }
      if (_cache.length > 60) {
        final oldest = _cache.keys.first;
        _cache.remove(oldest);
        _parsedSynced.remove(oldest);
      }
      _cache[track.id] = data;
      if (data.synced != null && data.synced!.isNotEmpty) {
        _parsedSynced[track.id] = parseLrc(data.synced!);
      }
      _updates.add(track.id);
      return data;
    } catch (_) {
      return null;
    } finally {
      _inflight.remove(track.id);
    }
  }

  /// Faz prefetch da faixa atual e da próxima da fila em segundo plano.
  void prefetchForQueue(List<Track> queue, int currentIndex) {
    if (queue.isEmpty) return;
    final idx = currentIndex.clamp(0, queue.length - 1);
    unawaited(getOrFetch(queue[idx]));
    if (idx + 1 < queue.length) {
      unawaited(getOrFetch(queue[idx + 1]));
    }
  }
}

/// Dispara prefetch de letras sempre que a faixa ou a fila mudam.
final lyricsPrefetchProvider = Provider<void>((ref) {
  final track = ref.watch(currentTrackProvider);
  ref.watch(queueTracksProvider);
  if (track == null) return;
  final handler = ref.read(handlerProvider);
  Future.microtask(() {
    LyricsCache.instance.prefetchForQueue(handler.tracks, handler.currentIndex);
  });
});
