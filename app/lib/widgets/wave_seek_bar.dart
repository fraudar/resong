import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Barra de progresso com onda animada no trecho reproduzido (estilo Husn / Lossless).
/// Quando pausada, a amplitude suaviza até ficar reta; ao tocar, a onda desliza
/// continuamente até o thumb interativo.
class WaveSeekBar extends StatefulWidget {
  const WaveSeekBar({
    super.key,
    required this.position,
    required this.duration,
    required this.isPlaying,
    required this.activeColor,
    required this.inactiveColor,
    required this.onSeek,
    this.thumbColor,
    this.glowColor,
    this.onScrubUpdate,
    this.animateWave = true,
    this.height = 30,
  });

  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final Color activeColor;
  final Color inactiveColor;
  final Color? thumbColor;
  final Color? glowColor;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<Duration?>? onScrubUpdate;
  final bool animateWave;
  final double height;

  @override
  State<WaveSeekBar> createState() => _WaveSeekBarState();
}

class _WaveSeekBarState extends State<WaveSeekBar> with TickerProviderStateMixin {
  late final AnimationController _phaseController;
  late final AnimationController _amplitudeController;
  double? _dragFraction;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _phaseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _amplitudeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      value: widget.isPlaying ? 1.0 : 0.0,
    );
    _syncAnimations();
  }

  @override
  void didUpdateWidget(covariant WaveSeekBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isPlaying != widget.isPlaying ||
        oldWidget.animateWave != widget.animateWave) {
      _syncAnimations();
    }
  }

  void _syncAnimations() {
    if (!widget.animateWave) {
      _phaseController.stop();
      _amplitudeController.value = widget.isPlaying ? 1.0 : 0.0;
      return;
    }
    if (widget.isPlaying) {
      if (!_phaseController.isAnimating) {
        _phaseController.repeat();
      }
      _amplitudeController.forward();
    } else {
      _amplitudeController.reverse().whenComplete(() {
        if (mounted && !widget.isPlaying) {
          _phaseController.stop();
        }
      });
    }
  }

  @override
  void dispose() {
    _phaseController.dispose();
    _amplitudeController.dispose();
    super.dispose();
  }

  double _fractionForDx(double dx, double width) {
    const pad = 8.0;
    final usable = math.max(1.0, width - pad * 2);
    return ((dx - pad) / usable).clamp(0.0, 1.0);
  }

  Duration _durationForFraction(double fraction) {
    final totalMs = widget.duration.inMilliseconds;
    if (totalMs <= 0) return Duration.zero;
    return Duration(milliseconds: (fraction * totalMs).round());
  }

  void _handleTapDown(TapDownDetails details, double width) {
    if (widget.duration.inMilliseconds <= 0) return;
    final f = _fractionForDx(details.localPosition.dx, width);
    widget.onSeek(_durationForFraction(f));
  }

  void _handleDragStart(DragStartDetails details, double width) {
    if (widget.duration.inMilliseconds <= 0) return;
    final f = _fractionForDx(details.localPosition.dx, width);
    setState(() {
      _dragging = true;
      _dragFraction = f;
    });
    widget.onScrubUpdate?.call(_durationForFraction(f));
  }

  void _handleDragUpdate(DragUpdateDetails details, double width) {
    if (!_dragging || widget.duration.inMilliseconds <= 0) return;
    final f = _fractionForDx(details.localPosition.dx, width);
    setState(() => _dragFraction = f);
    widget.onScrubUpdate?.call(_durationForFraction(f));
  }

  void _handleDragEnd() {
    if (!_dragging) return;
    final target = _dragFraction;
    setState(() {
      _dragging = false;
      _dragFraction = null;
    });
    widget.onScrubUpdate?.call(null);
    if (target != null) {
      widget.onSeek(_durationForFraction(target));
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalMs = widget.duration.inMilliseconds;
    final baseProgress = totalMs > 0
        ? (widget.position.inMilliseconds / totalMs).clamp(0.0, 1.0)
        : 0.0;
    final progress = _dragFraction ?? baseProgress;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _handleTapDown(d, width),
          onHorizontalDragStart: (d) => _handleDragStart(d, width),
          onHorizontalDragUpdate: (d) => _handleDragUpdate(d, width),
          onHorizontalDragEnd: (_) => _handleDragEnd(),
          onHorizontalDragCancel: () {
            if (_dragging) {
              setState(() {
                _dragging = false;
                _dragFraction = null;
              });
              widget.onScrubUpdate?.call(null);
            }
          },
          child: SizedBox(
            height: widget.height,
            width: double.infinity,
            child: AnimatedBuilder(
              animation: Listenable.merge([_phaseController, _amplitudeController]),
              builder: (context, _) {
                return CustomPaint(
                  painter: _WaveSeekPainter(
                    progress: progress,
                    phase: _phaseController.value,
                    amplitudeFactor: Curves.easeOutCubic.transform(_amplitudeController.value),
                    dragging: _dragging,
                    activeColor: widget.activeColor,
                    inactiveColor: widget.inactiveColor,
                    thumbColor: widget.thumbColor ?? widget.activeColor,
                    glowColor: widget.glowColor ?? widget.activeColor,
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _WaveSeekPainter extends CustomPainter {
  const _WaveSeekPainter({
    required this.progress,
    required this.phase,
    required this.amplitudeFactor,
    required this.dragging,
    required this.activeColor,
    required this.inactiveColor,
    required this.thumbColor,
    required this.glowColor,
  });

  final double progress;
  final double phase;
  final double amplitudeFactor;
  final bool dragging;
  final Color activeColor;
  final Color inactiveColor;
  final Color thumbColor;
  final Color glowColor;

  static const double _horizontalPad = 8.0;
  static const double _wavelengthPx = 20.0;
  static const double _maxAmplitudePx = 3.2;

  @override
  void paint(Canvas canvas, Size size) {
    final trackStart = _horizontalPad;
    final trackEnd = math.max(trackStart + 1.0, size.width - _horizontalPad);
    final trackWidth = trackEnd - trackStart;
    final centerY = size.height / 2;
    final thumbX = trackStart + trackWidth * progress.clamp(0.0, 1.0);

    // Trecho ainda não reproduzido (reta limpa)
    if (thumbX < trackEnd) {
      final inactivePaint = Paint()
        ..color = inactiveColor
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      canvas.drawLine(
        Offset(thumbX, centerY),
        Offset(trackEnd, centerY),
        inactivePaint,
      );
    }

    // Trecho reproduzido com ondinha senoidal suave
    final playedWidth = thumbX - trackStart;
    if (playedWidth > 0.5) {
      final activePaint = Paint()
        ..color = activeColor
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      final amp = _maxAmplitudePx * amplitudeFactor;
      if (amp <= 0.08) {
        canvas.drawLine(
          Offset(trackStart, centerY),
          Offset(thumbX, centerY),
          activePaint,
        );
      } else {
        final path = Path();
        const k = (2 * math.pi) / _wavelengthPx;
        final phaseShift = phase * 2 * math.pi;
        const step = 1.5;

        double yAt(double x) {
          final distFromStart = x - trackStart;
          final distFromThumb = thumbX - x;
          final startTaper = math.min(1.0, distFromStart / 5.0);
          final endTaper = math.min(1.0, distFromThumb / 6.0);
          final localAmp = amp * startTaper * endTaper;
          return centerY + math.sin(distFromStart * k - phaseShift) * localAmp;
        }

        path.moveTo(trackStart, yAt(trackStart));
        for (double x = trackStart + step; x < thumbX; x += step) {
          path.lineTo(x, yAt(x));
        }
        path.lineTo(thumbX, centerY);
        canvas.drawPath(path, activePaint);
      }
    }

    // Brilho suave e thumb circular
    final thumbRadius = dragging ? 8.5 : 6.5;
    final glowPaint = Paint()
      ..color = glowColor.withValues(alpha: dragging ? 0.34 : 0.20)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawCircle(Offset(thumbX, centerY), thumbRadius + 3.0, glowPaint);

    final thumbPaint = Paint()
      ..color = thumbColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(thumbX, centerY), thumbRadius, thumbPaint);
  }

  @override
  bool shouldRepaint(covariant _WaveSeekPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.phase != phase ||
        oldDelegate.amplitudeFactor != amplitudeFactor ||
        oldDelegate.dragging != dragging ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor ||
        oldDelegate.thumbColor != thumbColor ||
        oldDelegate.glowColor != glowColor;
  }
}
