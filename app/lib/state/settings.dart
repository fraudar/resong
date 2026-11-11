// language: Dart, file: lib/state/settings.dart, target: mobile-first + desktop, runtime: resong app
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

@immutable
class AppSettings {
  const AppSettings({
    this.waveEffectsEnabled = true,
    this.openPlayerOnTap = true,
    this.infiniteQueueEnabled = true,
    this.autoSkipEnabled = true,
    this.crossfadeSeconds = 0,
    this.profilePrivate = false,
    this.downloadFolder = '',
  });

  final bool waveEffectsEnabled;
  final bool openPlayerOnTap;
  final bool infiniteQueueEnabled;
  final bool autoSkipEnabled;
  final int crossfadeSeconds;
  final bool profilePrivate;
  final String downloadFolder;

  AppSettings copyWith({
    bool? waveEffectsEnabled,
    bool? openPlayerOnTap,
    bool? infiniteQueueEnabled,
    bool? autoSkipEnabled,
    int? crossfadeSeconds,
    bool? profilePrivate,
    String? downloadFolder,
  }) =>
      AppSettings(
        waveEffectsEnabled: waveEffectsEnabled ?? this.waveEffectsEnabled,
        openPlayerOnTap: openPlayerOnTap ?? this.openPlayerOnTap,
        infiniteQueueEnabled: infiniteQueueEnabled ?? this.infiniteQueueEnabled,
        autoSkipEnabled: autoSkipEnabled ?? this.autoSkipEnabled,
        crossfadeSeconds: crossfadeSeconds ?? this.crossfadeSeconds,
        profilePrivate: profilePrivate ?? this.profilePrivate,
        downloadFolder: downloadFolder ?? this.downloadFolder,
      );
}

class SettingsController extends StateNotifier<AppSettings> {
  SettingsController() : super(const AppSettings()) {
    _load();
  }

  static const _waveKey = 'resong_wave_effects';
  static const _openPlayerKey = 'resong_open_player_on_tap';
  static const _infiniteQueueKey = 'resong_infinite_queue';
  static const _autoSkipKey = 'resong_auto_skip';
  static const _crossfadeKey = 'resong_crossfade_seconds';
  static const _profilePrivateKey = 'resong_profile_private';
  static const _downloadFolderKey = 'resong_download_folder';

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = AppSettings(
        waveEffectsEnabled: prefs.getBool(_waveKey) ?? true,
        openPlayerOnTap: prefs.getBool(_openPlayerKey) ?? true,
        infiniteQueueEnabled: prefs.getBool(_infiniteQueueKey) ?? true,
        autoSkipEnabled: prefs.getBool(_autoSkipKey) ?? true,
        crossfadeSeconds: (prefs.getInt(_crossfadeKey) ?? 0).clamp(0, 12),
        profilePrivate: prefs.getBool(_profilePrivateKey) ?? false,
        downloadFolder: prefs.getString(_downloadFolderKey) ?? '',
      );
    } catch (_) {}
  }

  Future<void> setWaveEffects(bool enabled) async {
    state = state.copyWith(waveEffectsEnabled: enabled);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_waveKey, enabled);
    } catch (_) {}
  }

  Future<void> setOpenPlayerOnTap(bool enabled) async {
    state = state.copyWith(openPlayerOnTap: enabled);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_openPlayerKey, enabled);
    } catch (_) {}
  }

  Future<void> setInfiniteQueue(bool enabled) async {
    state = state.copyWith(infiniteQueueEnabled: enabled);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_infiniteQueueKey, enabled);
    } catch (_) {}
  }

  Future<void> setAutoSkip(bool enabled) async {
    state = state.copyWith(autoSkipEnabled: enabled);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_autoSkipKey, enabled);
    } catch (_) {}
  }

  Future<void> setCrossfadeSeconds(int seconds) async {
    final clamped = seconds.clamp(0, 12);
    state = state.copyWith(crossfadeSeconds: clamped);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_crossfadeKey, clamped);
    } catch (_) {}
  }

  Future<void> setProfilePrivate(bool isPrivate) async {
    state = state.copyWith(profilePrivate: isPrivate);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_profilePrivateKey, isPrivate);
    } catch (_) {}
  }

  Future<void> setDownloadFolder(String folderPath) async {
    final clean = folderPath.trim();
    state = state.copyWith(downloadFolder: clean);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (clean.isEmpty) {
        await prefs.remove(_downloadFolderKey);
      } else {
        await prefs.setString(_downloadFolderKey, clean);
      }
    } catch (_) {}
  }
}

final settingsProvider = StateNotifierProvider<SettingsController, AppSettings>(
  (ref) => SettingsController(),
);
