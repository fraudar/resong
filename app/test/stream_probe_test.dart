// Prova de fogo do proxy de mídia: o motor aceita Range aberto/sem Range,
// costura os blocos do googlevideo e entrega o mesmo arquivo do upstream.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:resong/engine/local_engine_io.dart';

const _id = 'yt:W40W7L1fhUM';

String get _tmp => Directory.systemTemp.path;

Future<void> _probe(String label, String? range, {int maxBytes = 262144}) async {
  final port = LocalEngineServer.instance.port!;
  final client = HttpClient();
  try {
    final req = await client.getUrl(
      Uri.parse('http://127.0.0.1:$port/api/stream/$_id'),
    );
    if (range != null) req.headers.set(HttpHeaders.rangeHeader, range);
    final res = await req.close().timeout(const Duration(seconds: 30));
    final status = res.statusCode;
    final type = res.headers.value(HttpHeaders.contentTypeHeader) ?? '-';
    final cr = res.headers.value(HttpHeaders.contentRangeHeader) ?? '-';
    final len = res.headers.value(HttpHeaders.contentLengthHeader) ?? '-';
    var got = 0;
    await for (final chunk in res) {
      got += chunk.length;
      if (got >= maxBytes) break;
    }
    stdout.writeln('[probe] $label -> $status type=$type range=$cr len=$len lidos=$got');
    expect(status, anyOf(200, 206), reason: '$label devolveu $status');
    expect(got, greaterThan(0), reason: '$label sem bytes');
    expect(type.contains('audio') || type.contains('video') || type.contains('octet'), isTrue,
        reason: '$label content-type inesperado: $type');
  } finally {
    client.close(force: true);
  }
}

Future<int> _fullDownload(String path) async {
  final port = LocalEngineServer.instance.port!;
  final client = HttpClient();
  try {
    final req = await client.getUrl(
      Uri.parse('http://127.0.0.1:$port/api/stream/$_id/download'),
    );
    final res = await req.close().timeout(const Duration(seconds: 30));
    final len = int.tryParse(res.headers.value(HttpHeaders.contentLengthHeader) ?? '') ?? -1;
    final body = BytesBuilder(copy: false);
    await for (final chunk in res) {
      body.add(chunk);
    }
    final bytes = body.takeBytes();
    File(path).writeAsBytesSync(bytes, flush: true);
    stdout.writeln('[probe] download motor -> ${res.statusCode} header=$len bytes=${bytes.length}');
    expect(res.statusCode, 200);
    expect(bytes.length, len, reason: 'download truncado');
    return bytes.length;
  } finally {
    client.close(force: true);
  }
}

Future<int> _directDownload(String path) async {
  final port = LocalEngineServer.instance.port!;
  final client = HttpClient();
  try {
    final resolveReq = await client.getUrl(
      Uri.parse('http://127.0.0.1:$port/api/stream/$_id?resolve=1'),
    );
    final resolveRes = await resolveReq.close().timeout(const Duration(seconds: 20));
    final info = jsonDecode(await utf8.decoder.bind(resolveRes).join()) as Map<String, dynamic>;
    final url = info['url'] as String;

    final req = await client.getUrl(Uri.parse(url));
    req.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0');
    req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-');
    final res = await req.close().timeout(const Duration(seconds: 30));
    final body = BytesBuilder(copy: false);
    await for (final chunk in res) {
      body.add(chunk);
    }
    final bytes = body.takeBytes();
    File(path).writeAsBytesSync(bytes, flush: true);
    stdout.writeln('[probe] download direto -> ${res.statusCode} bytes=${bytes.length}');
    expect(res.statusCode, anyOf(200, 206));
    return bytes.length;
  } finally {
    client.close(force: true);
  }
}

void main() {
  test('motor serve mídia com e sem Range', () async {
    final port = await LocalEngineServer.instance.start();
    stdout.writeln('[probe] motor na porta $port');
    try {
      await _probe('sem range', null);
      await _probe('range aberto', 'bytes=0-');
      await _probe('range no meio', 'bytes=1048576-', maxBytes: 65536);
      await _probe('seek 2.5M', 'bytes=2500000-', maxBytes: 300000);
      await _probe('range fechado', 'bytes=100-500000', maxBytes: 600000);
      final motorPath = '$_tmp${Platform.pathSeparator}resong_probe_motor.bin';
      final directPath = '$_tmp${Platform.pathSeparator}resong_probe_direto.bin';
      final motor = await _fullDownload(motorPath);
      final direct = await _directDownload(directPath);
      expect(motor, direct, reason: 'tamanho do motor difere do upstream');
      stdout.writeln('[probe] arquivos: $motorPath | $directPath');
    } finally {
      await LocalEngineServer.instance.stop();
    }
  }, timeout: const Timeout(Duration(seconds: 240)));
}
