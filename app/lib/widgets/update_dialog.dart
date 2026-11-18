// language: Dart, file: lib/widgets/update_dialog.dart, target: any, runtime: resong app
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons_flutter/solar_icons_flutter.dart';

import '../core/theme.dart';
import '../state/updater.dart';

/// Diálogo único que acompanha o fluxo inteiro: disponível → baixando → instalando → erro.
class UpdateDialog extends ConsumerWidget {
  const UpdateDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(updaterProvider);
    final colors = context.colors;
    final info = state.info;

    final downloading = state.phase == UpdatePhase.downloading;
    final installing = state.phase == UpdatePhase.installing;
    final failed = state.phase == UpdatePhase.error;
    final pct = downloading ? (state.progress * 100).round() : 100;

    return AlertDialog(
      backgroundColor: colors.bgElevated,
      surfaceTintColor: colors.bgElevated,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Row(
        children: [
          Icon(
            failed
                ? SolarIconsBold.infoCircle
                : SolarIconsBold.downloadMinimalistic,
            size: 21,
            color: failed ? colors.danger : colors.accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              failed
                  ? 'Não foi possível atualizar'
                  : installing
                      ? 'Instalando atualização...'
                      : 'Atualizando resong',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (info != null && !failed) ...[
              Text(
                'Versão ${info.version}',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary),
              ),
              const SizedBox(height: 8),
            ],
            if (failed)
              Text(
                state.error ?? 'Erro desconhecido ao atualizar.',
                style: TextStyle(
                    fontSize: 13, color: colors.textSecondary, height: 1.4),
              )
            else ...[
              LinearProgressIndicator(
                value: installing ? null : state.progress,
                minHeight: 6,
                borderRadius: BorderRadius.circular(6),
                color: colors.accent,
                backgroundColor: colors.stroke,
              ),
              const SizedBox(height: 10),
              Text(
                installing
                    ? 'Abrindo o instalador. O app pode fechar em instantes.'
                    : 'Baixando o pacote... $pct%',
                style: TextStyle(fontSize: 12.5, color: colors.textSecondary),
              ),
              if (info != null && info.notes.isNotEmpty && downloading) ...[
                const SizedBox(height: 14),
                Text(
                  info.notes,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12, color: colors.textTertiary, height: 1.35),
                ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        if (failed)
          TextButton(
            onPressed: () =>
                ref.read(updaterProvider.notifier).openReleasePage(),
            child: const Text('Abrir página de download'),
          ),
        TextButton(
          onPressed: () {
            ref.read(updaterProvider.notifier).cancel();
            Navigator.of(context).maybePop();
          },
          child: Text(failed ? 'Fechar' : 'Cancelar'),
        ),
      ],
    );
  }
}
