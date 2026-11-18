// language: Dart, file: lib/state/updater.dart, target: any, runtime: resong app
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'update_platform.dart';

/// Repositório e endpoints do auto-update. Cada versão publicada no GitHub
/// Releases com uma tag maior que a versão atual dispara a atualização.
const String kUpdateRepo = 'fraudar/resong';
const String _latestReleaseApi =
    'https://api.github.com/repos/$kUpdateRepo/releases/latest';
const String _releasePageUrl =
    'https://github.com/$kUpdateRepo/releases/latest';

class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.notes,
    required this.assetName,
    this.assetUrl,
  });

  final String version;
  final String notes;
  final String assetName;
  final String? assetUrl;

  bool get hasAsset => assetUrl != null && assetUrl!.isNotEmpty;
}

enum UpdatePhase {
  idle,
  checking,
  available,
  downloading,
  installing,
  done,
  error
}

class UpdateState {
  const UpdateState({
    this.phase = UpdatePhase.idle,
    this.info,
    this.progress = 0,
    this.error,
  });

  final UpdatePhase phase;
  final UpdateInfo? info;
  final double progress;
  final String? error;

  UpdateState copyWith({
    UpdatePhase? phase,
    UpdateInfo? info,
    double? progress,
    String? error,
    bool clearError = false,
  }) =>
      UpdateState(
        phase: phase ?? this.phase,
        info: info ?? this.info,
        progress: progress ?? this.progress,
        error: clearError ? null : (error ?? this.error),
      );
}

class UpdaterController extends StateNotifier<UpdateState> {
  UpdaterController() : super(const UpdateState());

  CancelToken? _downloadToken;
  bool _checked = false;

  /// Checa o GitHub Releases no início do app. Falhas de rede são silenciosas.
  Future<void> check({bool force = false}) async {
    if (_checked && !force) return;
    _checked = true;
    if (state.phase == UpdatePhase.downloading ||
        state.phase == UpdatePhase.installing) {
      return;
    }
    state = state.copyWith(phase: UpdatePhase.checking, clearError: true);

    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 20),
        headers: const {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'resong-auto-updater',
        },
      ));
      final res = await dio.get<Map<String, dynamic>>(_latestReleaseApi);
      final data = res.data ?? const <String, dynamic>{};

      final latest = _normalizeVersion((data['tag_name'] as String?) ?? '');
      if (latest.isEmpty) {
        state = const UpdateState();
        return;
      }
      final current = await _currentVersion();
      if (!_isNewer(latest, current)) {
        state = const UpdateState();
        return;
      }

      final asset = _pickAsset((data['assets'] as List?) ?? const <dynamic>[]);
      state = UpdateState(
        phase: UpdatePhase.available,
        info: UpdateInfo(
          version: latest,
          notes: ((data['body'] as String?) ?? '').trim(),
          assetName: (asset?['name'] as String?) ?? '',
          assetUrl: asset?['browser_download_url'] as String?,
        ),
      );
    } catch (_) {
      state = const UpdateState();
    }
  }

  /// Baixa o pacote da plataforma e dispara o instalador.
  Future<void> downloadAndInstall() async {
    final info = state.info;
    if (info == null) return;

    if (!info.hasAsset) {
      // iOS/macOS/Web/asset ausente: não há como instalar sozinho.
      await openReleasePage();
      state = state.copyWith(phase: UpdatePhase.done);
      return;
    }

    _downloadToken = CancelToken();
    try {
      state = state.copyWith(
          phase: UpdatePhase.downloading, progress: 0, clearError: true);
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(minutes: 15),
        headers: const {'User-Agent': 'resong-auto-updater'},
      ));
      final res = await dio.get<List<int>>(
        info.assetUrl!,
        cancelToken: _downloadToken,
        options:
            Options(responseType: ResponseType.bytes, followRedirects: true),
        onReceiveProgress: (received, total) {
          if (total > 0 && mounted) {
            state =
                state.copyWith(progress: (received / total).clamp(0.0, 1.0));
          }
        },
      );
      final bytes = res.data ?? const <int>[];
      if (bytes.isEmpty) throw Exception('Arquivo de atualização vazio');

      state = state.copyWith(phase: UpdatePhase.installing, progress: 1);
      final path = await saveUpdateFile(info.assetName, bytes);
      await installUpdateFile(path);
      state = state.copyWith(phase: UpdatePhase.done);
      await restartApp();
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        state = const UpdateState();
        return;
      }
      state = state.copyWith(
          phase: UpdatePhase.error,
          error: e.message ?? 'Falha ao baixar a atualização');
    } catch (e) {
      state = state.copyWith(
        phase: UpdatePhase.error,
        error: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  void cancel() {
    _downloadToken?.cancel('cancelado pelo usuário');
    _downloadToken = null;
    state = const UpdateState();
  }

  Future<void> openReleasePage() async {
    try {
      final uri = Uri.parse(_releasePageUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  Future<String> _currentVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return info.version;
    } catch (_) {
      return '0.0.0';
    }
  }

  static String _normalizeVersion(String raw) {
    final match = RegExp(r'(\d+(?:\.\d+){0,3})').firstMatch(raw.trim());
    return match?.group(1) ?? '';
  }

  static List<int> _parts(String version) =>
      version.split('.').map((e) => int.tryParse(e) ?? 0).toList();

  static bool _isNewer(String latest, String current) {
    final a = _parts(latest);
    final b = _parts(current);
    for (var i = 0; i < 4; i++) {
      final av = i < a.length ? a[i] : 0;
      final bv = i < b.length ? b[i] : 0;
      if (av > bv) return true;
      if (av < bv) return false;
    }
    return false;
  }

  static Map<String, dynamic>? _pickAsset(List assets) {
    final platform = currentUpdatePlatform;
    final String? suffix;
    switch (platform) {
      case UpdatePlatform.android:
        suffix = '.apk';
        break;
      case UpdatePlatform.windows:
        suffix = '.exe';
        break;
      case UpdatePlatform.linux:
        suffix = '.deb';
        break;
      default:
        return null;
    }

    for (final raw in assets) {
      if (raw is! Map) continue;
      final name = (raw['name'] as String? ?? '').toLowerCase();
      final url = raw['browser_download_url'] as String?;
      if (name.endsWith(suffix) && url != null && url.isNotEmpty) {
        return raw.cast<String, dynamic>();
      }
    }
    return null;
  }
}

final updaterProvider = StateNotifierProvider<UpdaterController, UpdateState>(
  (ref) => UpdaterController(),
);
