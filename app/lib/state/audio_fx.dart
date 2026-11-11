// language: Dart, file: lib/state/audio_fx.dart, target: web + mobile + desktop, runtime: resong app
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audio_fx_bridge_stub.dart' if (dart.library.js_interop) 'audio_fx_bridge_web.dart';
import 'player.dart';
import 'providers.dart';

class AudioPresetSpec {
  const AudioPresetSpec({
    required this.id,
    required this.label,
    required this.bands,
    this.bassBoost = 0,
    this.reverb = 0,
    this.spatial8d = false,
    this.speed = 1.0,
    this.preservePitch = true,
  });

  final String id;
  final String label;
  final List<double> bands;
  final double bassBoost;
  final double reverb;
  final bool spatial8d;
  final double speed;
  final bool preservePitch;
}

const audioBandLabels = ['60 Hz', '230 Hz', '910 Hz', '3.6 kHz', '14 kHz'];

const List<AudioPresetSpec> audioPresets = [
  AudioPresetSpec(id: 'flat', label: 'Flat', bands: [0, 0, 0, 0, 0]),
  AudioPresetSpec(
    id: '8d',
    label: 'Som 8D',
    bands: [2.0, 0.5, 0.0, 1.5, 2.5],
    bassBoost: 0.25,
    reverb: 0.28,
    spatial8d: true,
  ),
  AudioPresetSpec(
    id: 'bass',
    label: 'Graves',
    bands: [6.5, 4.0, 0.0, 1.0, 2.0],
    bassBoost: 0.55,
  ),
  AudioPresetSpec(
    id: 'pop',
    label: 'Pop',
    bands: [2.0, 4.0, 2.0, 3.5, 2.5],
  ),
  AudioPresetSpec(
    id: 'rock',
    label: 'Rock',
    bands: [4.5, 2.0, -1.5, 3.5, 5.0],
  ),
  AudioPresetSpec(
    id: 'electronic',
    label: 'Eletrônica',
    bands: [6.0, 3.5, -1.0, 3.0, 5.5],
    bassBoost: 0.35,
  ),
  AudioPresetSpec(
    id: 'acoustic',
    label: 'Acústico',
    bands: [2.5, 1.5, 3.0, 2.5, 2.0],
    reverb: 0.14,
  ),
  AudioPresetSpec(
    id: 'slowed',
    label: 'Slowed + Reverb',
    bands: [3.5, 2.0, -0.5, -1.0, -1.5],
    bassBoost: 0.28,
    reverb: 0.48,
    speed: 0.85,
    preservePitch: false,
  ),
  AudioPresetSpec(
    id: 'nightcore',
    label: 'Nightcore',
    bands: [2.5, 1.0, 1.5, 3.0, 3.5],
    speed: 1.22,
    preservePitch: false,
  ),
];

@immutable
class AudioFxState {
  const AudioFxState({
    this.enabled = false,
    this.preset = 'flat',
    this.bands = const [0, 0, 0, 0, 0],
    this.bassBoost = 0.0,
    this.reverb = 0.0,
    this.spatial8d = false,
    this.rotationHz = 0.18,
    this.speed = 1.0,
    this.preservePitch = true,
    this.monoAudio = false,
    this.normalization = true,
    this.gapless = true,
  });

  final bool enabled;
  final String preset;
  final List<double> bands;
  final double bassBoost;
  final double reverb;
  final bool spatial8d;
  final double rotationHz;
  final double speed;
  final bool preservePitch;
  final bool monoAudio;
  final bool normalization;
  final bool gapless;

  bool get hasActiveEffects =>
      enabled &&
      (spatial8d ||
          monoAudio ||
          bassBoost > 0.01 ||
          reverb > 0.01 ||
          (speed - 1.0).abs() > 0.01 ||
          bands.any((b) => b.abs() > 0.1));

  AudioFxState copyWith({
    bool? enabled,
    String? preset,
    List<double>? bands,
    double? bassBoost,
    double? reverb,
    bool? spatial8d,
    double? rotationHz,
    double? speed,
    bool? preservePitch,
    bool? monoAudio,
    bool? normalization,
    bool? gapless,
  }) =>
      AudioFxState(
        enabled: enabled ?? this.enabled,
        preset: preset ?? this.preset,
        bands: bands ?? this.bands,
        bassBoost: bassBoost ?? this.bassBoost,
        reverb: reverb ?? this.reverb,
        spatial8d: spatial8d ?? this.spatial8d,
        rotationHz: rotationHz ?? this.rotationHz,
        speed: speed ?? this.speed,
        preservePitch: preservePitch ?? this.preservePitch,
        monoAudio: monoAudio ?? this.monoAudio,
        normalization: normalization ?? this.normalization,
        gapless: gapless ?? this.gapless,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'preset': preset,
        'bands': bands,
        'bassBoost': bassBoost,
        'reverb': reverb,
        'spatial8d': spatial8d,
        'rotationHz': rotationHz,
        'speed': speed,
        'preservePitch': preservePitch,
        'monoAudio': monoAudio,
        'normalization': normalization,
        'gapless': gapless,
      };

  factory AudioFxState.fromJson(Map<String, dynamic> json) {
    final rawBands = (json['bands'] as List?)?.map((e) => (e as num).toDouble().clamp(-12.0, 12.0)).toList();
    final safeBands = (rawBands != null && rawBands.length == 5)
        ? rawBands
        : const <double>[0, 0, 0, 0, 0];
    return AudioFxState(
      enabled: json['enabled'] as bool? ?? false,
      preset: json['preset'] as String? ?? 'flat',
      bands: safeBands,
      bassBoost: ((json['bassBoost'] as num?)?.toDouble() ?? 0.0).clamp(0.0, 1.0),
      reverb: ((json['reverb'] as num?)?.toDouble() ?? 0.0).clamp(0.0, 1.0),
      spatial8d: json['spatial8d'] as bool? ?? false,
      rotationHz: ((json['rotationHz'] as num?)?.toDouble() ?? 0.18).clamp(0.08, 0.45),
      speed: ((json['speed'] as num?)?.toDouble() ?? 1.0).clamp(0.70, 1.50),
      preservePitch: json['preservePitch'] as bool? ?? true,
      monoAudio: json['monoAudio'] as bool? ?? false,
      normalization: json['normalization'] as bool? ?? true,
      gapless: json['gapless'] as bool? ?? true,
    );
  }
}

class AudioFxController extends StateNotifier<AudioFxState> {
  AudioFxController(this._handler) : super(const AudioFxState()) {
    _load();
  }

  final ResongHandler _handler;
  static const _prefKey = 'resong_audio_fx_v1';

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          state = AudioFxState.fromJson(decoded.cast<String, dynamic>());
        }
      }
    } catch (_) {}
    await _sync();
  }

  Future<void> _saveAndSync(AudioFxState next) async {
    state = next;
    await _sync();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, jsonEncode(next.toJson()));
    } catch (_) {}
  }

  Future<void> _sync() async {
    resumeWebAudioContext();
    applyWebAudioEffectsJson(jsonEncode(state.toJson()));
    await _handler.applyAudioEffects(state);
  }

  Future<void> setEnabled(bool enabled) => _saveAndSync(state.copyWith(enabled: enabled));

  Future<void> setBand(int index, double db) {
    if (index < 0 || index >= 5) return Future.value();
    final updated = [...state.bands];
    updated[index] = db.clamp(-12.0, 12.0);
    return _saveAndSync(state.copyWith(enabled: true, preset: 'custom', bands: updated));
  }

  Future<void> applyPreset(AudioPresetSpec spec) => _saveAndSync(
        state.copyWith(
          enabled: spec.id != 'flat' ||
              state.spatial8d ||
              state.bassBoost > 0 ||
              state.reverb > 0,
          preset: spec.id,
          bands: List<double>.from(spec.bands),
          bassBoost: spec.bassBoost,
          reverb: spec.reverb,
          spatial8d: spec.spatial8d,
          speed: spec.speed,
          preservePitch: spec.preservePitch,
        ),
      );

  Future<void> reset() => _saveAndSync(
        AudioFxState(
          normalization: state.normalization,
          gapless: state.gapless,
        ),
      );

  Future<void> setBassBoost(double value) =>
      _saveAndSync(state.copyWith(enabled: true, preset: 'custom', bassBoost: value.clamp(0.0, 1.0)));

  Future<void> setReverb(double value) =>
      _saveAndSync(state.copyWith(enabled: true, preset: 'custom', reverb: value.clamp(0.0, 1.0)));

  Future<void> setSpatial8d(bool value) =>
      _saveAndSync(state.copyWith(enabled: value ? true : state.enabled, spatial8d: value));

  Future<void> setRotationHz(double hz) =>
      _saveAndSync(state.copyWith(enabled: true, rotationHz: hz.clamp(0.08, 0.45)));

  Future<void> setSpeed(double speed) =>
      _saveAndSync(state.copyWith(enabled: true, speed: speed.clamp(0.70, 1.50)));

  Future<void> setPreservePitch(bool preserve) =>
      _saveAndSync(state.copyWith(preservePitch: preserve));

  Future<void> setMonoAudio(bool mono) =>
      _saveAndSync(state.copyWith(enabled: mono ? true : state.enabled, monoAudio: mono));

  Future<void> setNormalization(bool normalization) =>
      _saveAndSync(state.copyWith(normalization: normalization));

  Future<void> setGapless(bool gapless) =>
      _saveAndSync(state.copyWith(gapless: gapless));
}

final audioFxProvider = StateNotifierProvider<AudioFxController, AudioFxState>(
  (ref) => AudioFxController(ref.watch(handlerProvider)),
);
