// language: Dart, file: lib/screens/audio_fx_sheet.dart, target: mobile-first + desktop + web, runtime: resong app
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:solar_icons_flutter/solar_icons_flutter.dart';

import '../core/theme.dart';
import '../state/audio_fx.dart';

Future<void> showAudioEffectsSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.62),
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.84,
      minChildSize: 0.55,
      maxChildSize: 0.94,
      builder: (_, scrollController) => _AudioFxSheet(scrollController: scrollController),
    ),
  );
}

class _AudioFxSheet extends ConsumerWidget {
  const _AudioFxSheet({required this.scrollController});

  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final fx = ref.watch(audioFxProvider);
    final ctrl = ref.read(audioFxProvider.notifier);
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    final bg = colors.isDark ? const Color(0xFF0E0F12) : const Color(0xFFF6F7FA);

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        border: Border(top: BorderSide(color: colors.stroke, width: 1)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 34,
            height: 3.5,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              color: colors.textTertiary.withValues(alpha: 0.45),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 16, 10),
            child: _EqHeaderRow(fx: fx, ctrl: ctrl),
          ),
          Divider(height: 1, color: colors.stroke),
          Expanded(
            child: AudioFxBody(
              scrollController: scrollController,
              padding: EdgeInsets.fromLTRB(20, 14, 20, bottomPad + 24),
            ),
          ),
        ],
      ),
    );
  }
}

class _EqHeaderRow extends StatelessWidget {
  const _EqHeaderRow({
    required this.fx,
    required this.ctrl,
  });

  final AudioFxState fx;
  final AudioFxController ctrl;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final primary = colors.textPrimary;
    final switchTrackActive = colors.isDark ? Colors.white : const Color(0xFF14161A);
    final switchThumbActive = colors.isDark ? const Color(0xFF0E0F12) : Colors.white;

    return Row(
      children: [
        Text(
          'Equalizador',
          style: GoogleFonts.inter(
            fontSize: 16.5,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            color: primary,
          ),
        ),
        const Spacer(),
        if (fx.hasActiveEffects)
          TextButton(
            onPressed: ctrl.reset,
            style: TextButton.styleFrom(
              foregroundColor: colors.textSecondary,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Resetar', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500)),
          ),
        const SizedBox(width: 6),
        Transform.scale(
          scale: 0.84,
          child: Switch.adaptive(
            value: fx.enabled,
            activeTrackColor: switchTrackActive,
            activeThumbColor: switchThumbActive,
            onChanged: ctrl.setEnabled,
          ),
        ),
      ],
    );
  }
}

/// Painel monocromático de console de áudio (Equalizador 5 bandas, Som 8D, Graves, Reverb, Gapless).
class AudioFxBody extends ConsumerWidget {
  const AudioFxBody({
    super.key,
    this.scrollController,
    this.padding = const EdgeInsets.fromLTRB(20, 14, 20, 24),
    this.showHeader = false,
    this.translucent = false,
  });

  final ScrollController? scrollController;
  final EdgeInsetsGeometry padding;
  final bool showHeader;
  final bool translucent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final fx = ref.watch(audioFxProvider);
    final ctrl = ref.read(audioFxProvider.notifier);

    final mono = colors.isDark ? Colors.white : const Color(0xFF14161A);
    final onMono = colors.isDark ? const Color(0xFF0E0F12) : Colors.white;
    final faderBg = translucent
        ? (colors.isDark ? Colors.white.withValues(alpha: 0.045) : Colors.black.withValues(alpha: 0.04))
        : (colors.isDark ? const Color(0xFF14161B) : Colors.white);
    final dividerColor = colors.isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.08);

    return ListView(
      controller: scrollController,
      padding: padding,
      children: [
        if (showHeader) ...[
          _EqHeaderRow(fx: fx, ctrl: ctrl),
          const SizedBox(height: 12),
        ],

        // Presets discretos e alinhados sem excesso visual
        SizedBox(
          height: 30,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: audioPresets.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final p = audioPresets[i];
              final selected = fx.preset == p.id &&
                  (p.id == 'flat' ? !fx.enabled || fx.bands.every((b) => b == 0) : fx.enabled);
              return InkWell(
                borderRadius: BorderRadius.circular(7),
                onTap: () => ctrl.applyPreset(p),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  padding: const EdgeInsets.symmetric(horizontal: 11),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(7),
                    color: selected
                        ? mono
                        : (colors.isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.black.withValues(alpha: 0.045)),
                  ),
                  child: Text(
                    p.label,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected ? onMono : colors.textSecondary,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),

        // Mesa de 5 faders verticais de estúdio (zero curvas neon genéricas)
        Container(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
          decoration: BoxDecoration(
            color: faderBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: dividerColor, width: 1),
          ),
          child: _ConsoleEqFaderBank(
            bands: fx.bands,
            enabled: fx.enabled,
            activeColor: mono,
            capNotchColor: onMono,
            onBandChanged: ctrl.setBand,
          ),
        ),
        const SizedBox(height: 14),

        // Controles contínuos + chaves limpas sem bordas/cards aninhados
        _ToggleRow(
          icon: SolarIconsLinear.headphonesRound,
          title: 'Som 8D',
          subtitle: 'Órbita espacial nos fones',
          value: fx.enabled && fx.spatial8d,
          activeTrack: mono,
          activeThumb: onMono,
          onChanged: ctrl.setSpatial8d,
        ),
        if (fx.spatial8d)
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
            child: _MonoSliderRow(
              label: 'Velocidade da órbita',
              valueLabel: '${(1 / fx.rotationHz).toStringAsFixed(1)}s',
              value: fx.rotationHz.clamp(0.08, 0.45),
              min: 0.08,
              max: 0.45,
              activeColor: mono,
              onChanged: ctrl.setRotationHz,
            ),
          ),
        Divider(height: 1, color: dividerColor),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              _MonoSliderRow(
                label: 'Graves',
                valueLabel: '${(fx.bassBoost * 100).round()}%',
                value: fx.bassBoost,
                min: 0,
                max: 1,
                activeColor: mono,
                onChanged: ctrl.setBassBoost,
              ),
              const SizedBox(height: 12),
              _MonoSliderRow(
                label: 'Reverb',
                valueLabel: '${(fx.reverb * 100).round()}%',
                value: fx.reverb,
                min: 0,
                max: 1,
                activeColor: mono,
                onChanged: ctrl.setReverb,
              ),
              const SizedBox(height: 12),
              _MonoSliderRow(
                label: 'Velocidade',
                valueLabel: '${fx.speed.toStringAsFixed(2)}×',
                value: fx.speed,
                min: 0.70,
                max: 1.40,
                activeColor: mono,
                onChanged: ctrl.setSpeed,
              ),
            ],
          ),
        ),
        Divider(height: 1, color: dividerColor),
        _ToggleRow(
          title: 'Manter tom original',
          subtitle: 'Desative para Slowed ou Nightcore',
          value: fx.preservePitch,
          activeTrack: mono,
          activeThumb: onMono,
          onChanged: ctrl.setPreservePitch,
        ),
        Divider(height: 1, color: dividerColor),
        _ToggleRow(
          title: 'Gapless',
          subtitle: 'Sem silêncio entre faixas',
          value: fx.gapless,
          activeTrack: mono,
          activeThumb: onMono,
          onChanged: ctrl.setGapless,
        ),
        Divider(height: 1, color: dividerColor),
        _ToggleRow(
          title: 'Normalização',
          subtitle: 'Equilibra o volume (-14 LUFS)',
          value: fx.normalization,
          activeTrack: mono,
          activeThumb: onMono,
          onChanged: ctrl.setNormalization,
        ),
        Divider(height: 1, color: dividerColor),
        _ToggleRow(
          title: 'Áudio Mono',
          subtitle: 'Une canais esquerdo e direito',
          value: fx.monoAudio,
          activeTrack: mono,
          activeThumb: onMono,
          onChanged: ctrl.setMonoAudio,
        ),
      ],
    );
  }
}

class _ConsoleEqFaderBank extends StatelessWidget {
  const _ConsoleEqFaderBank({
    required this.bands,
    required this.enabled,
    required this.activeColor,
    required this.capNotchColor,
    required this.onBandChanged,
  });

  final List<double> bands;
  final bool enabled;
  final Color activeColor;
  final Color capNotchColor;
  final void Function(int index, double db) onBandChanged;

  static const _trackHeight = 136.0;
  static const _axisWidth = 28.0;

  double _yToDb(double dy, double height) {
    final norm = (dy / height).clamp(0.0, 1.0);
    final raw = 12.0 - norm * 24.0;
    if (raw.abs() < 0.65) return 0.0;
    return (raw * 2).round() / 2.0;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fg = enabled ? activeColor : colors.textTertiary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const SizedBox(width: _axisWidth),
            for (var i = 0; i < 5; i++)
              Expanded(
                child: Text(
                  '${bands[i] > 0 ? '+' : ''}${bands[i].toStringAsFixed(bands[i] % 1 == 0 ? 0 : 1)}',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: bands[i].abs() > 0.2 ? FontWeight.w600 : FontWeight.w400,
                    color: enabled && bands[i].abs() > 0.2 ? colors.textPrimary : colors.textTertiary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: _trackHeight,
          child: Row(
            children: [
              SizedBox(
                width: _axisWidth,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Text('+12', style: TextStyle(fontSize: 9.5, color: colors.textTertiary)),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Text('0', style: TextStyle(fontSize: 9.5, color: colors.textSecondary)),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Text('-12', style: TextStyle(fontSize: 9.5, color: colors.textTertiary)),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CustomPaint(
                      painter: _ConsoleFadersPainter(
                        bands: bands,
                        fgColor: fg,
                        notchColor: capNotchColor,
                        centerLineColor: colors.isDark
                            ? Colors.white.withValues(alpha: 0.14)
                            : Colors.black.withValues(alpha: 0.14),
                        railColor: colors.isDark
                            ? Colors.white.withValues(alpha: 0.09)
                            : Colors.black.withValues(alpha: 0.09),
                      ),
                    ),
                    Row(
                      children: [
                        for (var i = 0; i < 5; i++)
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapDown: (d) => onBandChanged(i, _yToDb(d.localPosition.dy, _trackHeight)),
                              onVerticalDragDown: (d) =>
                                  onBandChanged(i, _yToDb(d.localPosition.dy, _trackHeight)),
                              onVerticalDragUpdate: (d) =>
                                  onBandChanged(i, _yToDb(d.localPosition.dy, _trackHeight)),
                              onDoubleTap: () => onBandChanged(i, 0.0),
                              child: const SizedBox.expand(),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const SizedBox(width: _axisWidth),
            for (var i = 0; i < 5; i++)
              Expanded(
                child: Text(
                  audioBandLabels[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                    color: colors.textTertiary,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _ConsoleFadersPainter extends CustomPainter {
  _ConsoleFadersPainter({
    required this.bands,
    required this.fgColor,
    required this.notchColor,
    required this.centerLineColor,
    required this.railColor,
  });

  final List<double> bands;
  final Color fgColor;
  final Color notchColor;
  final Color centerLineColor;
  final Color railColor;

  @override
  void paint(Canvas canvas, Size size) {
    const vPad = 6.0;
    final plotH = math.max(1.0, size.height - vPad * 2);
    final zeroY = vPad + plotH * 0.5;
    final colW = size.width / bands.length;

    // Linha discreta 0 dB ao centro
    canvas.drawLine(
      Offset(4, zeroY),
      Offset(size.width - 4, zeroY),
      Paint()
        ..color = centerLineColor
        ..strokeWidth = 1.0,
    );

    final railPaint = Paint()
      ..color = railColor
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    final activeFillPaint = Paint()
      ..color = fgColor.withValues(alpha: 0.72)
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    final capPaint = Paint()..color = fgColor;
    final notchPaint = Paint()
      ..color = notchColor
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < bands.length; i++) {
      final cx = colW * (i + 0.5);
      final db = bands[i].clamp(-12.0, 12.0);
      final norm = (12.0 - db) / 24.0;
      final cy = vPad + norm * plotH;

      // Canal vertical limpo + preenchimento bidirecional a partir de 0 dB
      canvas.drawLine(Offset(cx, vPad), Offset(cx, size.height - vPad), railPaint);
      canvas.drawLine(Offset(cx, zeroY), Offset(cx, cy), activeFillPaint);

      // Botão deslizante retangular arredondado estilo mesa de estúdio
      final capRect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy), width: 20, height: 8.5),
        const Radius.circular(3.5),
      );
      canvas.drawRRect(capRect, capPaint);
      canvas.drawLine(Offset(cx - 5, cy), Offset(cx + 5, cy), notchPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ConsoleFadersPainter old) {
    if (old.fgColor != fgColor ||
        old.notchColor != notchColor ||
        old.centerLineColor != centerLineColor ||
        old.railColor != railColor ||
        old.bands.length != bands.length) {
      return true;
    }
    for (var i = 0; i < bands.length; i++) {
      if ((old.bands[i] - bands[i]).abs() > 0.01) return true;
    }
    return false;
  }
}

class _MonoSliderRow extends StatelessWidget {
  const _MonoSliderRow({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.activeColor,
    required this.onChanged,
  });

  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final Color activeColor;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final inactive = colors.isDark
        ? Colors.white.withValues(alpha: 0.16)
        : Colors.black.withValues(alpha: 0.14);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: colors.textPrimary),
            ),
            const Spacer(),
            Text(
              valueLabel,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: colors.textSecondary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        SizedBox(
          height: 22,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2.2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4.5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
              activeTrackColor: activeColor,
              inactiveTrackColor: inactive,
              thumbColor: activeColor,
              overlayColor: activeColor.withValues(alpha: 0.12),
            ),
            child: Slider(
              min: min,
              max: max,
              value: value.clamp(min, max),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.activeTrack,
    required this.activeThumb,
    required this.onChanged,
  });

  final IconData? icon;
  final String title;
  final String subtitle;
  final bool value;
  final Color activeTrack;
  final Color activeThumb;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 17, color: value ? colors.textPrimary : colors.textSecondary),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: colors.textPrimary),
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11.5, color: colors.textTertiary),
                ),
              ],
            ),
          ),
          Transform.scale(
            scale: 0.84,
            child: Switch.adaptive(
              value: value,
              activeTrackColor: activeTrack,
              activeThumbColor: activeThumb,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
