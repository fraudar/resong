// language: Dart, file: lib/state/audio_fx_bridge_web.dart, target: web, runtime: resong app
import 'dart:js_interop';

@JS('__resongAudioFx')
external _ResongFxJs? get _resongFxJs;

extension type _ResongFxJs(JSObject _) implements JSObject {
  external void apply(String json);
  external void prewarm(String url);
  external void resume();
}

void applyWebAudioEffectsJson(String json) {
  try {
    _resongFxJs?.apply(json);
  } catch (_) {}
}

void prewarmWebAudioUrl(String url) {
  try {
    _resongFxJs?.prewarm(url);
  } catch (_) {}
}

void resumeWebAudioContext() {
  try {
    _resongFxJs?.resume();
  } catch (_) {}
}
