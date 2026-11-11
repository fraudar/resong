// language: Dart, file: lib/state/scrobbles.dart, target: mobile-first + desktop, runtime: resong app
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api.dart';
import '../core/local_image.dart';
import '../core/models.dart';
import 'library.dart';
import 'providers.dart';
import 'settings.dart';

class ScrobbleEntry {
  const ScrobbleEntry({required this.track, required this.playedAtMs});

  final Track track;
  final int playedAtMs;

  factory ScrobbleEntry.fromJson(Map<String, dynamic> json) => ScrobbleEntry(
        track: Track.fromJson((json['track'] as Map).cast<String, dynamic>()),
        playedAtMs: (json['played_at'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'track': track.toJson(),
        'played_at': playedAtMs,
      };
}

class ArtistStat {
  const ArtistStat({required this.name, required this.plays, this.artwork});
  final String name;
  final int plays;
  final String? artwork;
}

class TrackStat {
  const TrackStat({required this.track, required this.plays});
  final Track track;
  final int plays;
}

class DayActivity {
  const DayActivity({required this.label, required this.plays, required this.isToday});
  final String label;
  final int plays;
  final bool isToday;
}

class ProfileIdentity {
  const ProfileIdentity({
    this.name = 'Ouvinte resong',
    this.bio = 'Meu som, artistas e histórico no resong.',
    this.avatarBase64,
  });

  final String name;
  final String bio;
  final String? avatarBase64;

  Uint8List? get avatarBytes {
    final raw = avatarBase64;
    if (raw == null || raw.isEmpty) return null;
    try {
      return base64Decode(raw);
    } catch (_) {
      return null;
    }
  }

  ProfileIdentity copyWith({
    String? name,
    String? bio,
    String? avatarBase64,
    bool clearAvatar = false,
  }) =>
      ProfileIdentity(
        name: name ?? this.name,
        bio: bio ?? this.bio,
        avatarBase64: clearAvatar ? null : (avatarBase64 ?? this.avatarBase64),
      );

  factory ProfileIdentity.fromJson(Map<String, dynamic> json) => ProfileIdentity(
        name: (json['name'] as String?)?.trim().isNotEmpty == true ? json['name'] as String : 'Ouvinte resong',
        bio: (json['bio'] as String?)?.trim().isNotEmpty == true
            ? json['bio'] as String
            : 'Meu som, artistas e histórico no resong.',
        avatarBase64: (json['avatarBase64'] as String?)?.trim().isNotEmpty == true
            ? json['avatarBase64'] as String
            : null,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'bio': bio,
        if (avatarBase64 != null && avatarBase64!.isNotEmpty) 'avatarBase64': avatarBase64,
      };
}

class ProfileIdentityController extends StateNotifier<ProfileIdentity> {
  ProfileIdentityController() : super(const ProfileIdentity()) {
    _load();
  }

  static const _prefKey = 'resong_profile_identity';

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        state = ProfileIdentity.fromJson(decoded.cast<String, dynamic>());
      }
    } catch (_) {}
  }

  Future<void> update({
    required String name,
    required String bio,
    String? avatarBase64,
    bool clearAvatar = false,
  }) async {
    String? safeAvatar = clearAvatar ? null : (avatarBase64 ?? state.avatarBase64);
    if (safeAvatar != null && safeAvatar.isNotEmpty) {
      try {
        if (base64Decode(safeAvatar).lengthInBytes > kMaxLocalCoverBytes) {
          safeAvatar = state.avatarBase64;
        }
      } catch (_) {
        safeAvatar = state.avatarBase64;
      }
    }
    state = ProfileIdentity(
      name: name.trim().isEmpty ? 'Ouvinte resong' : name.trim(),
      bio: bio.trim().isEmpty ? 'Meu som, artistas e histórico no resong.' : bio.trim(),
      avatarBase64: safeAvatar,
    );
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, jsonEncode(state.toJson()));
    } catch (_) {}
  }
}

final profileIdentityProvider = StateNotifierProvider<ProfileIdentityController, ProfileIdentity>(
  (ref) => ProfileIdentityController(),
);

class ScrobbleController extends StateNotifier<List<ScrobbleEntry>> {
  ScrobbleController() : super(const []) {
    _load();
  }

  static const _prefKey = 'resong_scrobbles_v1';
  static const _maxEntries = 300;
  bool _loaded = false;

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          state = decoded
              .whereType<Map>()
              .map((e) => ScrobbleEntry.fromJson(e.cast<String, dynamic>()))
              .toList();
        }
      }
    } catch (_) {}
    _loaded = true;
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, jsonEncode([for (final e in state) e.toJson()]));
    } catch (_) {}
  }

  Future<void> record(Track track) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (state.isNotEmpty) {
      final latest = state.first;
      if (latest.track.id == track.id && (now - latest.playedAtMs) < 15000) {
        return;
      }
    }
    state = [ScrobbleEntry(track: track, playedAtMs: now), ...state].take(_maxEntries).toList();
    await _persist();
  }

  void seedFromRecentIfEmpty(List<Track> recent) {
    if (!_loaded || state.isNotEmpty || recent.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final seeded = <ScrobbleEntry>[];
    for (var i = 0; i < recent.length; i++) {
      seeded.add(ScrobbleEntry(track: recent[i], playedAtMs: now - (i + 1) * 18 * 60000));
    }
    state = seeded;
    _persist();
  }

  Future<void> clear() async {
    state = const [];
    await _persist();
  }
}

final scrobblesProvider = StateNotifierProvider<ScrobbleController, List<ScrobbleEntry>>(
  (ref) => ScrobbleController(),
);

/// Conecta o player à regra local de histórico (50% ou 4 min) e fila infinita inteligente via /api/suggest.
final scrobbleBinderProvider = Provider<void>((ref) {
  final handler = ref.watch(handlerProvider);
  final settings = ref.watch(settingsProvider);
  handler.infiniteQueue = settings.infiniteQueueEnabled;
  handler.autoSkipEnabled = settings.autoSkipEnabled;
  handler.crossfadeSeconds = settings.crossfadeSeconds;

  handler.onTrackChanged = null;

  handler.onScrobbleEligible = (track) {
    Future.microtask(() {
      ref.read(scrobblesProvider.notifier).record(track);
      ref.read(recentProvider.notifier).push(track);
    });
  };

  handler.onNeedMoreTracks = (seed, existingIds) async {
    try {
      final baseArtist = seed.artists.isNotEmpty ? seed.artists.first : '';
      final seedText = '$baseArtist ${seed.title}'.trim();
      final suggestions = await Api.instance.suggest(seedText);
      final query = suggestions.isNotEmpty
          ? suggestions.firstWhere(
              (s) => s.toLowerCase() != seed.title.toLowerCase(),
              orElse: () => suggestions.first,
            )
          : (baseArtist.isNotEmpty ? baseArtist : seed.title);
      final res = await Api.instance.search(query, limit: 14);
      final picked = res.tracks.where((t) => !existingIds.contains(t.id)).take(5).toList();
      if (picked.isNotEmpty) return picked;
      if (baseArtist.isNotEmpty) {
        final fallback = await Api.instance.search(baseArtist, limit: 12);
        return fallback.tracks.where((t) => !existingIds.contains(t.id)).take(5).toList();
      }
    } catch (_) {}
    return const [];
  };

  final recent = ref.watch(recentProvider);
  if (recent.isNotEmpty) {
    Future.microtask(() => ref.read(scrobblesProvider.notifier).seedFromRecentIfEmpty(recent));
  }
});

/// Quick picks gerados a partir do artista/histórico mais ouvido pelo usuário.
final quickPicksProvider = FutureProvider<List<Track>>((ref) async {
  final scrobbles = ref.watch(scrobblesProvider);
  final recent = ref.watch(recentProvider);
  final favorites = ref.watch(favoritesProvider);

  final topArtists = computeTopArtists(scrobbles, limit: 3);
  String? seedQuery;
  if (topArtists.isNotEmpty) {
    seedQuery = topArtists.first.name;
  } else if (favorites.isNotEmpty && favorites.first.artists.isNotEmpty) {
    seedQuery = favorites.first.artists.first;
  } else if (recent.isNotEmpty && recent.first.artists.isNotEmpty) {
    seedQuery = recent.first.artists.first;
  }
  if (seedQuery == null || seedQuery.isEmpty) return const [];

  final seen = {for (final e in scrobbles) e.track.id};
  final res = await Api.instance.search(seedQuery, limit: 12);
  final fresh = res.tracks.where((t) => !seen.contains(t.id)).take(6).toList();
  return fresh.isNotEmpty ? fresh : res.tracks.take(6).toList();
});

List<ArtistStat> computeTopArtists(List<ScrobbleEntry> entries, {int limit = 6}) {
  final counts = <String, int>{};
  final artworks = <String, String?>{};
  for (final e in entries) {
    final artist = e.track.artists.isNotEmpty ? e.track.artists.first.trim() : '';
    if (artist.isEmpty) continue;
    counts[artist] = (counts[artist] ?? 0) + 1;
    artworks[artist] ??= e.track.artwork;
  }
  final out = [
    for (final kv in counts.entries) ArtistStat(name: kv.key, plays: kv.value, artwork: artworks[kv.key]),
  ]..sort((a, b) => b.plays.compareTo(a.plays));
  return out.take(limit).toList();
}

List<TrackStat> computeTopTracks(List<ScrobbleEntry> entries, {int limit = 6}) {
  final counts = <String, int>{};
  final tracks = <String, Track>{};
  for (final e in entries) {
    counts[e.track.id] = (counts[e.track.id] ?? 0) + 1;
    final prev = tracks[e.track.id];
    if (prev == null || ((prev.artwork == null || prev.artwork!.isEmpty) && (e.track.artwork?.isNotEmpty ?? false))) {
      tracks[e.track.id] = e.track;
    }
  }
  final out = [
    for (final kv in counts.entries) TrackStat(track: tracks[kv.key]!, plays: kv.value),
  ]..sort((a, b) => b.plays.compareTo(a.plays));
  return out.take(limit).toList();
}

int computeListeningMinutes(List<ScrobbleEntry> entries) {
  var totalMs = 0;
  for (final e in entries) {
    totalMs += e.track.durationMs ?? 195000;
  }
  return (totalMs / 60000).round();
}

int computeListeningStreakDays(List<ScrobbleEntry> entries) {
  if (entries.isEmpty) return 0;
  final days = <DateTime>{};
  for (final e in entries) {
    if (e.playedAtMs <= 0) continue;
    final dt = DateTime.fromMillisecondsSinceEpoch(e.playedAtMs);
    days.add(DateTime(dt.year, dt.month, dt.day));
  }
  final now = DateTime.now();
  var cursor = DateTime(now.year, now.month, now.day);
  if (!days.contains(cursor)) {
    cursor = cursor.subtract(const Duration(days: 1));
  }
  var streak = 0;
  while (days.contains(cursor)) {
    streak++;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return streak;
}

List<DayActivity> computeWeeklyActivity(List<ScrobbleEntry> entries) {
  const weekdayLabels = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
  final now = DateTime.now();
  final todayStart = DateTime(now.year, now.month, now.day);
  final out = <DayActivity>[];
  for (var offset = 6; offset >= 0; offset--) {
    final day = todayStart.subtract(Duration(days: offset));
    final nextDay = day.add(const Duration(days: 1));
    final startMs = day.millisecondsSinceEpoch;
    final endMs = nextDay.millisecondsSinceEpoch;
    final count = entries.where((e) => e.playedAtMs >= startMs && e.playedAtMs < endMs).length;
    out.add(
      DayActivity(
        label: weekdayLabels[day.weekday - 1],
        plays: count,
        isToday: offset == 0,
      ),
    );
  }
  return out;
}
