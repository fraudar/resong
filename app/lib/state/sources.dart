// language: Dart, file: lib/state/sources.dart, target: mobile-first + desktop, runtime: resong app
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import '../core/models.dart';

class SourcesController extends StateNotifier<AsyncValue<SourcesSnapshot>> {
  SourcesController() : super(const AsyncValue.data(SourcesSnapshot())) {
    refresh();
  }

  Future<void> refresh() async {
    try {
      final snap = await Api.instance.sources();
      if (!mounted) return;
      state = AsyncValue.data(snap);
    } catch (_) {
      // Mantém snapshot atual se backend estiver offline (ex.: testes)
    }
  }

  Future<AddonSource> add(String url, {String? label}) async {
    final created = await Api.instance.addSource(url, label: label);
    final cur = state.valueOrNull ?? const SourcesSnapshot();
    final updated = [
      for (final s in cur.sources)
        if (s.id != created.id) s,
      created,
    ]..sort((a, b) => a.ordem.compareTo(b.ordem));
    if (mounted) {
      state = AsyncValue.data(cur.copyWith(sources: updated));
    }
    return created;
  }

  Future<void> toggleEnabled(String id, bool enabled) async {
    final cur = state.valueOrNull;
    if (cur == null) return;
    final optimistic = [
      for (final s in cur.sources)
        if (s.id == id) s.copyWith(enabled: enabled) else s,
    ];
    state = AsyncValue.data(cur.copyWith(sources: optimistic));
    try {
      await Api.instance.updateSource(id, enabled: enabled);
    } catch (_) {
      await refresh();
    }
  }

  Future<void> reorder(int oldIndex, int targetIndex) async {
    final cur = state.valueOrNull;
    if (cur == null) return;
    final list = [...cur.sources];
    if (oldIndex < 0 || oldIndex >= list.length) return;
    final target = targetIndex.clamp(0, list.length - 1);
    if (target == oldIndex) return;
    final moved = list.removeAt(oldIndex);
    list.insert(target, moved);
    final reindexed = [
      for (var i = 0; i < list.length; i++) list[i].copyWith(ordem: i),
    ];
    state = AsyncValue.data(cur.copyWith(sources: reindexed));
    try {
      await Api.instance.reorderSources([for (final s in reindexed) s.id]);
    } catch (_) {
      await refresh();
    }
  }

  Future<void> checkHealth(String id) async {
    try {
      final updated = await Api.instance.checkSourceHealth(id);
      final cur = state.valueOrNull;
      if (cur == null || !mounted) return;
      state = AsyncValue.data(
        cur.copyWith(
          sources: [
            for (final s in cur.sources)
              if (s.id == id) updated else s,
          ],
        ),
      );
    } catch (_) {}
  }

  Future<void> remove(String id) async {
    final cur = state.valueOrNull;
    if (cur != null) {
      state = AsyncValue.data(
        cur.copyWith(sources: cur.sources.where((s) => s.id != id).toList()),
      );
    }
    try {
      await Api.instance.deleteSource(id);
    } catch (_) {
      await refresh();
    }
  }

  Future<void> configureSpotify({
    bool? enabled,
    String? clientId,
    String? clientSecret,
    bool clearCredentials = false,
  }) async {
    final natives = await Api.instance.configureSpotify(
      enabled: enabled,
      clientId: clientId,
      clientSecret: clientSecret,
      clearCredentials: clearCredentials,
    );
    if (!mounted) return;
    final cur = state.valueOrNull ?? const SourcesSnapshot();
    if (natives.isNotEmpty) {
      state = AsyncValue.data(cur.copyWith(nativeSources: natives));
    } else {
      await refresh();
    }
  }

  Future<void> toggleNative(String id, bool enabled) async {
    final natives = await Api.instance.setNativeSourceEnabled(id, enabled);
    if (!mounted) return;
    final cur = state.valueOrNull ?? const SourcesSnapshot();
    if (natives.isNotEmpty) {
      state = AsyncValue.data(cur.copyWith(nativeSources: natives));
    } else {
      await refresh();
    }
  }
}

final sourcesProvider = StateNotifierProvider<SourcesController, AsyncValue<SourcesSnapshot>>(
  (ref) => SourcesController(),
);
