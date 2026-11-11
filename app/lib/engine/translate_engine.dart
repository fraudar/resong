// language: Dart, file: lib/engine/translate_engine.dart, target: mobile + desktop, runtime: resong engine
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import 'engine_utils.dart';

class TranslateEngine {
  TranslateEngine._();
  static final TranslateEngine instance = TranslateEngine._();

  static const _maxChunkChars = 2200;
  static const _marker = '⟪L⟫';

  String _cacheKey(String target, List<String> lines) {
    final hash = sha256.convert(utf8.encode(lines.join('\n'))).toString();
    return 'tx:v2:$target:$hash';
  }

  List<List<({int index, String text})>> _chunkLines(List<String> lines) {
    final indexed = <({int index, String text})>[];
    for (var i = 0; i < lines.length; i++) {
      final clean = lines[i].replaceAll('\r', '').trim();
      if (clean.isNotEmpty) indexed.add((index: i, text: clean));
    }
    final chunks = <List<({int index, String text})>>[];
    var current = <({int index, String text})>[];
    var len = 0;
    for (final item in indexed) {
      final added = item.text.length + 14;
      if (current.isNotEmpty && len + added > _maxChunkChars) {
        chunks.add(current);
        current = [];
        len = 0;
      }
      current.add(item);
      len += added;
    }
    if (current.isNotEmpty) chunks.add(current);
    return chunks;
  }

  Future<({Map<int, String> translated, Map<int, String> romanized, String? sourceLang})> _translateChunk(
    List<({int index, String text})> chunk,
    String target,
  ) async {
    final payload = chunk.map((c) => c.text).join('\n$_marker\n');
    final uri = Uri.https('translate.googleapis.com', '/translate_a/single', {
      'client': 'gtx',
      'sl': 'auto',
      'tl': target,
      'q': payload,
    });
    // Dio queryParameters doesn't repeat `dt=t&dt=rm` easily when passed as Map<String, String>; build explicit URL.
    final fullUrl = '$uri&dt=t&dt=rm';
    final res = await engineDio.get<Object?>(
      fullUrl,
      options: Options(
        headers: {'user-agent': 'Mozilla/5.0', 'accept': 'application/json'},
        receiveTimeout: const Duration(seconds: 9),
      ),
    );
    if (res.statusCode != 200 || res.data == null) {
      throw Exception('translate status ${res.statusCode}');
    }
    final data = res.data is String ? jsonDecode(res.data as String) : res.data;
    if (data is! List || data.isEmpty) {
      throw Exception('translate response invalid');
    }

    final segments = data[0] is List ? data[0] as List : const [];
    final sourceLang = data.length > 2 && data[2] is String ? data[2] as String : null;
    final fullBuf = StringBuffer();
    final romaBuf = StringBuffer();
    for (final seg in segments) {
      if (seg is! List) continue;
      if (seg.isNotEmpty && seg[0] is String) fullBuf.write(seg[0]);
      if (seg.length > 3 && seg[3] is String && seg[0] == null) romaBuf.write(seg[3]);
    }

    final full = fullBuf.toString();
    final fullRoma = romaBuf.toString();
    final markerRx = RegExp(r'\s*⟪L⟫\s*');
    var parts = full.split(markerRx);
    if (parts.length != chunk.length) {
      final lineParts = full
          .split(RegExp(r'\n+'))
          .map((l) => l.replaceAll(_marker, '').trim())
          .where((l) => l.isNotEmpty)
          .toList();
      if (lineParts.length == chunk.length) parts = lineParts;
    }

    final romaParts = fullRoma.isNotEmpty
        ? fullRoma.split(RegExp(r'\s*⟪\s*L\s*⟫\s*')).map((s) => s.trim()).toList()
        : const <String>[];

    final translatedMap = <int, String>{};
    final romanizedMap = <int, String>{};
    for (var i = 0; i < chunk.length; i++) {
      final item = chunk[i];
      final rawVal = i < parts.length ? parts[i] : item.text;
      final cleanVal = rawVal.replaceAll(_marker, '').trim();
      translatedMap[item.index] = cleanVal.isNotEmpty ? cleanVal : item.text;
      if (i < romaParts.length && romaParts[i].isNotEmpty) {
        romanizedMap[item.index] = romaParts[i];
      }
    }
    return (translated: translatedMap, romanized: romanizedMap, sourceLang: sourceLang);
  }

  Future<Map<String, dynamic>> translateLyrics(List<String> lines, {String target = 'pt'}) async {
    final safeTarget = target.trim().toLowerCase();
    final effectiveTarget = safeTarget.isEmpty ? 'pt' : (safeTarget.length > 12 ? safeTarget.substring(0, 12) : safeTarget);
    if (lines.isEmpty) {
      return {'target': effectiveTarget, 'lines': const <String>[], 'romanized': const <String>[]};
    }

    final key = _cacheKey(effectiveTarget, lines);
    final hit = engineCache.get<Map<String, dynamic>>(key);
    if (hit != null) return {'target': effectiveTarget, ...hit};

    final chunks = _chunkLines(lines);
    if (chunks.isEmpty) {
      return {
        'target': effectiveTarget,
        'lines': List<String>.filled(lines.length, ''),
        'romanized': List<String>.filled(lines.length, ''),
      };
    }

    final out = List<String>.from(lines);
    final romaOut = List<String>.filled(lines.length, '');
    String? detectedLang;

    // Executa em lotes de até 4 chunks simultâneos respeitando o timeout total.
    for (var i = 0; i < chunks.length; i += 4) {
      final batch = chunks.skip(i).take(4);
      final results = await Future.wait(batch.map((c) => _translateChunk(c, effectiveTarget)));
      for (final res in results) {
        detectedLang ??= res.sourceLang;
        res.translated.forEach((idx, text) => out[idx] = text);
        res.romanized.forEach((idx, text) => romaOut[idx] = text);
      }
    }

    final hasRoma = romaOut.any((r) => r.trim().isNotEmpty);
    final payload = <String, dynamic>{
      'lines': out,
      if (hasRoma) 'romanized': romaOut,
      if (detectedLang != null) 'source_lang': detectedLang,
    };
    engineCache.set(key, payload, const Duration(hours: 24));
    return {'target': effectiveTarget, ...payload};
  }

  Future<Map<String, dynamic>> romanizeLyrics(List<String> lines) async {
    final res = await translateLyrics(lines, target: 'en');
    final rom = res['romanized'] as List<String>?;
    final hasAny = rom != null && rom.any((r) => r.trim().isNotEmpty);
    return {
      'target': 'romaji',
      'lines': hasAny ? rom : lines,
      if (res['source_lang'] != null) 'source_lang': res['source_lang'],
    };
  }
}
