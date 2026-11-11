// language: Dart, file: lib/widgets/volume_control.dart, target: desktop + web + mobile, runtime: resong app
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons_flutter/solar_icons_flutter.dart';

import '../core/theme.dart';
import '../state/providers.dart';

enum VolumeSliderPlacement {
  /// Abre o slider flutuante para a esquerda sobre a barra (ideal no canto direito inferior).
  floatingLeft,

  /// Abre o slider flutuante para a direita (ideal no player maximizado).
  floatingRight,

  /// Renderiza o slider inline ao lado do ícone sem popup.
  inline,
}

/// Controle de volume estilo Sonora via OverlayPortal:
/// clicar no ícone muta/desmuta e passar o mouse revela o slider interativo sem deslocar botões.
class HoverVolumeControl extends ConsumerStatefulWidget {
  const HoverVolumeControl({
    super.key,
    this.iconColor,
    this.mutedColor,
    this.trackColor,
    this.inactiveTrackColor,
    this.iconSize = 18,
    this.sliderWidth = 92,
    this.placement = VolumeSliderPlacement.floatingRight,
    this.surfaceColor,
  });

  final Color? iconColor;
  final Color? mutedColor;
  final Color? trackColor;
  final Color? inactiveTrackColor;
  final double iconSize;
  final double sliderWidth;
  final VolumeSliderPlacement placement;
  final Color? surfaceColor;

  @override
  ConsumerState<HoverVolumeControl> createState() => _HoverVolumeControlState();
}

class _HoverVolumeControlState extends ConsumerState<HoverVolumeControl> {
  final _link = LayerLink();
  final _portalCtrl = OverlayPortalController();
  bool _overTrigger = false;
  bool _overPopup = false;
  bool _dragging = false;
  Timer? _hideTimer;

  bool get _open => _overTrigger || _overPopup || _dragging;

  void _syncPortal() {
    _hideTimer?.cancel();
    if (widget.placement == VolumeSliderPlacement.inline) return;
    if (_open) {
      if (!_portalCtrl.isShowing && mounted) {
        _portalCtrl.show();
      }
      if (mounted) setState(() {});
    } else {
      _hideTimer = Timer(const Duration(milliseconds: 160), () {
        if (!mounted || _open) return;
        if (_portalCtrl.isShowing) _portalCtrl.hide();
        setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  IconData _iconFor(double volume, bool muted) {
    if (muted || volume <= 0.001) return SolarIconsLinear.muted;
    if (volume < 0.45) return SolarIconsLinear.volumeSmall;
    return SolarIconsLinear.volumeLoud;
  }

  Widget _buildSlider(
    BuildContext context, {
    required double volume,
    required Color activeTrack,
    required Color inactiveTrack,
    required ValueChanged<double> onChanged,
  }) {
    return SizedBox(
      width: widget.sliderWidth,
      height: 30,
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 2.4,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4.5),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
          activeTrackColor: activeTrack,
          inactiveTrackColor: inactiveTrack,
          thumbColor: activeTrack,
          overlayColor: activeTrack.withValues(alpha: 0.14),
        ),
        child: Slider(
          min: 0.0,
          max: 1.0,
          value: volume.clamp(0.0, 1.0),
          onChangeStart: (_) {
            _dragging = true;
            _syncPortal();
          },
          onChanged: onChanged,
          onChangeEnd: (_) {
            _dragging = false;
            _syncPortal();
          },
        ),
      ),
    );
  }

  Widget _speakerButton({
    required double vol,
    required bool muted,
    required Color iconFg,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      tooltip: muted ? 'Ativar som' : 'Mutar',
      iconSize: widget.iconSize,
      icon: Icon(_iconFor(vol, muted), color: iconFg),
      onPressed: onPressed,
    );
  }

  @override
  Widget build(BuildContext context) {
    final handler = ref.watch(handlerProvider);
    final colors = context.colors;
    final baseFg = widget.iconColor ?? colors.textSecondary;
    final mutedFg = widget.mutedColor ?? colors.textTertiary;
    final activeTrack = widget.trackColor ?? (colors.isDark ? Colors.white : colors.textPrimary);
    final inactiveTrack = widget.inactiveTrackColor ??
        (colors.isDark ? Colors.white.withValues(alpha: 0.20) : Colors.black.withValues(alpha: 0.16));

    return StreamBuilder<double>(
      stream: handler.volumeStream,
      initialData: handler.volume,
      builder: (context, snap) {
        final vol = (snap.data ?? handler.volume).clamp(0.0, 1.0);
        final muted = handler.isMuted || vol <= 0.001;
        final iconFg = muted ? mutedFg : baseFg;

        if (widget.placement == VolumeSliderPlacement.inline) {
          return MouseRegion(
            onEnter: (_) => setState(() => _overTrigger = true),
            onExit: (_) => setState(() => _overTrigger = false),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_open)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: _buildSlider(
                      context,
                      volume: vol,
                      activeTrack: activeTrack,
                      inactiveTrack: inactiveTrack,
                      onChanged: handler.setVolume,
                    ),
                  ),
                _speakerButton(
                  vol: vol,
                  muted: muted,
                  iconFg: iconFg,
                  onPressed: handler.toggleMute,
                ),
              ],
            ),
          );
        }

        final isLeft = widget.placement == VolumeSliderPlacement.floatingLeft;
        final pillBg = widget.surfaceColor ??
            (colors.isDark ? const Color(0xFF16181D) : Colors.white);
        final pillBorder = colors.stroke;

        return CompositedTransformTarget(
          link: _link,
          child: OverlayPortal(
            controller: _portalCtrl,
            overlayChildBuilder: (overlayCtx) {
              final anchor = isLeft ? Alignment.centerRight : Alignment.centerLeft;
              final slider = _buildSlider(
                overlayCtx,
                volume: vol,
                activeTrack: activeTrack,
                inactiveTrack: inactiveTrack,
                onChanged: handler.setVolume,
              );
              final btn = _speakerButton(
                vol: vol,
                muted: muted,
                iconFg: iconFg,
                onPressed: handler.toggleMute,
              );

              return UnconstrainedBox(
                alignment: Alignment.topLeft,
                child: CompositedTransformFollower(
                  link: _link,
                  targetAnchor: anchor,
                  followerAnchor: anchor,
                  showWhenUnlinked: false,
                  child: Material(
                    type: MaterialType.transparency,
                    child: MouseRegion(
                      onEnter: (_) {
                        _overPopup = true;
                        _syncPortal();
                      },
                      onExit: (_) {
                        _overPopup = false;
                        _syncPortal();
                      },
                      child: Container(
                        height: 34,
                        padding: EdgeInsets.only(
                          left: isLeft ? 10 : 2,
                          right: isLeft ? 2 : 10,
                        ),
                        decoration: BoxDecoration(
                          color: pillBg,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: pillBorder, width: 1),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: colors.isDark ? 0.42 : 0.14),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: isLeft ? [slider, btn] : [btn, slider],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
            child: MouseRegion(
              onEnter: (_) {
                _overTrigger = true;
                _syncPortal();
              },
              onExit: (_) {
                _overTrigger = false;
                _syncPortal();
              },
              child: SizedBox(
                width: 32,
                height: 32,
                child: _speakerButton(
                  vol: vol,
                  muted: muted,
                  iconFg: iconFg,
                  onPressed: handler.toggleMute,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
