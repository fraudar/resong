// Diagnóstico: o motor local nasce e sobrevive às requisições do app?
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:resong/engine/local_engine_io.dart';
import 'package:resong/core/api.dart';

void main() {
  test('motor local sobrevive a health + home por 15s', () async {
    final port = await LocalEngineServer.instance.start();
    stdout.writeln('[smoke] motor na porta $port');
    expect(LocalEngineServer.instance.isRunning, isTrue);

    var alive = true;
    final t = Timer.periodic(const Duration(seconds: 1), (t) async {
      try {
        final res = await HttpClient()
            .getUrl(Uri.parse('http://127.0.0.1:$port/api/health'))
            .timeout(const Duration(seconds: 2));
        final body = await res.close().timeout(const Duration(seconds: 2));
        stdout.writeln('[smoke] t=${t.tick}s health ${body.statusCode}');
      } catch (e) {
        stdout.writeln('[smoke] t=${t.tick}s MORREU: $e');
        alive = false;
        t.cancel();
      }
    });

    await Future<void>.delayed(const Duration(seconds: 3));
    try {
      final home = await Api.instance.home();
      stdout.writeln('[smoke] home ok: ${home.sections.length} secoes');
    } catch (e) {
      stdout.writeln('[smoke] home falhou: $e');
    }

    await Future<void>.delayed(const Duration(seconds: 12));
    t.cancel();
    stdout.writeln('[smoke] rodou com motor vivo: $alive');
    expect(alive, isTrue);
  }, timeout: const Timeout(Duration(seconds: 90)));
}
