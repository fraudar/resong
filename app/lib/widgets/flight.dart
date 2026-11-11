// language: Dart, file: lib/widgets/flight.dart, target: mobile-first + desktop + web, runtime: resong app
// Transição voando estilo Sonora (`flight.rs`):
// - Só anima se moveu > 0.5 px
// - Origem válida apenas se vista nos últimos 300 ms
// - Física em Spring (SpringSimulation), nunca curva fixa
// - Pousa quando offset restante < 0.01 px e delta de escala < 1e-4
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';

class FlightSnapshot {
  const FlightSnapshot({
    required this.rect,
    required this.borderRadius,
    required this.seenAt,
    required this.route,
    required this.interactedAt,
  });

  final Rect rect;
  final BorderRadius borderRadius;
  final DateTime seenAt;
  final ModalRoute<dynamic>? route;
  final DateTime? interactedAt;
}

/// Registro global de origens recentes e elementos montados para transições Flight (Sonora).
class SonoraFlightRegistry {
  SonoraFlightRegistry._();
  static final SonoraFlightRegistry instance = SonoraFlightRegistry._();

  static const Duration originMaxAge = Duration(milliseconds: 300);
  static const double minMovePx = 0.5;
  static const double settleOffsetPx = 0.01;
  static const double settleScaleDelta = 1e-4;
  static const SpringDescription defaultSpring = SpringDescription(
    mass: 1.0,
    stiffness: 360.0,
    damping: 29.0,
  );

  final Map<String, Set<_FlightElementState>> _mounted = {};
  final Map<String, List<FlightSnapshot>> _snapshots = {};
  final Map<ModalRoute<dynamic>, Set<String>> _prePushTags = {};
  final Map<ModalRoute<dynamic>, DateTime> _returningRoutes = {};
  final Set<VoidCallback> _routePopListeners = {};

  static bool isOriginFresh(DateTime seenAt, DateTime now) {
    final diff = now.difference(seenAt);
    return !diff.isNegative && diff <= originMaxAge;
  }

  static bool hasMovedEnough(Rect from, Rect to) {
    return (to.topLeft - from.topLeft).distance > minMovePx ||
        (to.width - from.width).abs() > minMovePx ||
        (to.height - from.height).abs() > minMovePx;
  }

  /// Teto de distância (40% da diagonal da tela) para evitar voos exagerados.
  static bool exceedsMaxDistance(Rect from, Rect to, Size screenSize) {
    if (screenSize.isEmpty) return false;
    final diag = math.sqrt(screenSize.width * screenSize.width + screenSize.height * screenSize.height);
    if (diag <= 0) return false;
    return (to.center - from.center).distance > diag * 0.40;
  }

  static SpringSimulation createSpring(Rect from, Rect to) {
    final moveDist = math.max(
      (to.topLeft - from.topLeft).distance,
      math.max((to.width - from.width).abs(), (to.height - from.height).abs()),
    );
    final distTol = math.min(settleOffsetPx / math.max(moveDist, 1.0), settleScaleDelta);
    return SpringSimulation(
      defaultSpring,
      0.0,
      1.0,
      0.0,
      tolerance: Tolerance(distance: distTol, velocity: settleScaleDelta),
    );
  }

  void _register(String tag, _FlightElementState state) {
    _mounted.putIfAbsent(tag, () => {}).add(state);
  }

  void _unregister(String tag, _FlightElementState state) {
    final set = _mounted[tag];
    if (set == null) return;
    set.remove(state);
    if (set.isEmpty) _mounted.remove(tag);
  }

  void recordSnapshot(
    String tag,
    Rect rect,
    BorderRadius borderRadius,
    ModalRoute<dynamic>? route, {
    DateTime? interactedAt,
  }) {
    if (rect.isEmpty) return;
    final list = _snapshots.putIfAbsent(tag, () => []);
    list.removeWhere((s) => s.route == route);
    list.add(
      FlightSnapshot(
        rect: rect,
        borderRadius: borderRadius,
        seenAt: DateTime.now(),
        route: route,
        interactedAt: interactedAt,
      ),
    );
  }

  /// Captura retângulos de todos os elementos montados (ex.: antes de push/pop de rota).
  void captureAll({ModalRoute<dynamic>? onlyRoute, bool markPrePush = false}) {
    final prePushSet = (markPrePush && onlyRoute != null) ? <String>{} : null;
    for (final entries in _mounted.values) {
      for (final state in entries) {
        if (onlyRoute == null || state.owningRoute == onlyRoute) {
          final captured = state.captureNow();
          if (captured && prePushSet != null) {
            prePushSet.add(state.widget.tag);
          }
        }
      }
    }
    if (markPrePush && onlyRoute != null && prePushSet != null) {
      _prePushTags[onlyRoute] = prePushSet;
    }
  }

  bool hasPrePushSnapshot(String tag, {required ModalRoute<dynamic>? destinationRoute}) {
    if (destinationRoute == null) return false;
    final set = _prePushTags[destinationRoute];
    if (set != null) return set.contains(tag);
    final list = _snapshots[tag];
    if (list == null) return false;
    return list.any((s) => s.route == destinationRoute);
  }

  FlightSnapshot? takeOrigin(
    String tag, {
    required ModalRoute<dynamic>? destinationRoute,
    DateTime? now,
  }) {
    final list = _snapshots[tag];
    if (list == null || list.isEmpty) return null;
    final ts = now ?? DateTime.now();

    FlightSnapshot? best;
    for (final s in list) {
      if (destinationRoute != null && s.route == destinationRoute) continue;
      if (!isOriginFresh(s.seenAt, ts)) continue;
      if (best == null) {
        best = s;
      } else {
        final aTouch = s.interactedAt ?? s.seenAt;
        final bTouch = best.interactedAt ?? best.seenAt;
        if (aTouch.isAfter(bTouch)) {
          best = s;
        }
      }
    }
    list.removeWhere((s) => s.route != destinationRoute && !isOriginFresh(s.seenAt, ts));
    return best;
  }

  void addRouteReturnListener(VoidCallback cb) => _routePopListeners.add(cb);
  void removeRouteReturnListener(VoidCallback cb) => _routePopListeners.remove(cb);

  void markRouteReturning(ModalRoute<dynamic>? route) {
    if (route == null) return;
    final now = DateTime.now();
    _returningRoutes.removeWhere((_, ts) => !isOriginFresh(ts, now));
    _returningRoutes[route] = now;
  }

  void clearRouteReturning(ModalRoute<dynamic>? route) {
    if (route != null) _returningRoutes.remove(route);
  }

  bool isReturningRoute(ModalRoute<dynamic>? route) {
    if (route == null) return false;
    final ts = _returningRoutes[route];
    if (ts == null) return false;
    if (isOriginFresh(ts, DateTime.now())) return true;
    _returningRoutes.remove(route);
    return false;
  }

  void notifyRouteReturned({ModalRoute<dynamic>? restoredRoute}) {
    for (final cb in [..._routePopListeners]) {
      cb();
    }
    if (restoredRoute != null) {
      _prePushTags.remove(restoredRoute);
    }
  }

  void clear() {
    _snapshots.clear();
    _prePushTags.clear();
    _returningRoutes.clear();
  }
}

/// NavigatorObserver que tira snapshot dos elementos na rota atual imediatamente antes
/// da transição de entrada/saída para manter a janela de 300 ms precisa.
class SonoraRouteObserver extends NavigatorObserver {
  SonoraRouteObserver._();
  static final SonoraRouteObserver instance = SonoraRouteObserver._();

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is ModalRoute) {
      SonoraFlightRegistry.instance.clearRouteReturning(route);
    }
    if (previousRoute is ModalRoute) {
      SonoraFlightRegistry.instance.captureAll(onlyRoute: previousRoute, markPrePush: true);
    } else {
      SonoraFlightRegistry.instance.captureAll();
    }
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is ModalRoute) {
      SonoraFlightRegistry.instance.captureAll(onlyRoute: route);
    }
    if (previousRoute is ModalRoute) {
      SonoraFlightRegistry.instance.markRouteReturning(previousRoute);
    }
    super.didPop(route, previousRoute);
    SchedulerBinding.instance.addPostFrameCallback((_) {
      SonoraFlightRegistry.instance.notifyRouteReturned(
        restoredRoute: previousRoute is ModalRoute ? previousRoute : null,
      );
    });
  }
}

/// Elemento que anima suavemente com física de spring entre rotas (capa, curtir, lista → detalhe).
class FlightElement extends StatefulWidget {
  const FlightElement({
    super.key,
    required this.tag,
    required this.child,
    this.borderRadius = BorderRadius.zero,
    this.shuttleChild,
    this.enabled = true,
  });

  final String tag;
  final Widget child;
  final BorderRadius borderRadius;
  final Widget? shuttleChild;
  final bool enabled;

  @override
  State<FlightElement> createState() => _FlightElementState();
}

class _FlightElementState extends State<FlightElement> with SingleTickerProviderStateMixin {
  late final AnimationController _springCtrl;
  OverlayEntry? _overlay;
  bool _flying = false;
  int _fadeSeq = 0;
  DateTime? _lastInteracted;
  ModalRoute<dynamic>? _owningRoute;
  bool _triedInitialFlight = false;

  ModalRoute<dynamic>? get owningRoute => _owningRoute;

  @override
  void initState() {
    super.initState();
    _springCtrl = AnimationController.unbounded(vsync: this);
    SonoraFlightRegistry.instance._register(widget.tag, this);
    SonoraFlightRegistry.instance.addRouteReturnListener(_handleRouteReturn);
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_triedInitialFlight) {
        _triedInitialFlight = true;
        _tryStartFlight();
      }
      captureNow();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _owningRoute = ModalRoute.of(context);
  }

  @override
  void didUpdateWidget(covariant FlightElement oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tag != widget.tag) {
      SonoraFlightRegistry.instance._unregister(oldWidget.tag, this);
      SonoraFlightRegistry.instance._register(widget.tag, this);
      _triedInitialFlight = false;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _tryStartFlight();
        captureNow();
      });
    } else {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) captureNow();
      });
    }
  }

  @override
  void dispose() {
    _cancelOverlay();
    SonoraFlightRegistry.instance.removeRouteReturnListener(_handleRouteReturn);
    SonoraFlightRegistry.instance._unregister(widget.tag, this);
    _springCtrl.dispose();
    super.dispose();
  }

  void _handleRouteReturn() {
    if (!mounted || !(_owningRoute?.isCurrent ?? false)) return;
    _tryStartFlight(isReturn: true);
  }

  void _triggerFadeIn() {
    if (!mounted) return;
    setState(() => _fadeSeq++);
  }

  Rect? _measureRect() {
    if (!mounted) return null;
    final renderObj = context.findRenderObject();
    if (renderObj is! RenderBox || !renderObj.hasSize) return null;
    final size = renderObj.size;
    if (size.isEmpty) return null;
    final topLeft = renderObj.localToGlobal(Offset.zero);
    return topLeft & size;
  }

  bool captureNow() {
    if (!mounted || _flying) return false;
    final rect = _measureRect();
    if (rect == null) return false;
    SonoraFlightRegistry.instance.recordSnapshot(
      widget.tag,
      rect,
      widget.borderRadius,
      _owningRoute,
      interactedAt: _lastInteracted,
    );
    return true;
  }

  void _tryStartFlight({bool isReturn = false}) {
    if (!mounted || !widget.enabled || _flying) return;
    final effectivelyReturning = isReturn || SonoraFlightRegistry.instance.isReturningRoute(_owningRoute);
    final destRect = _measureRect();
    if (destRect == null) return;

    final origin = SonoraFlightRegistry.instance.takeOrigin(
      widget.tag,
      destinationRoute: _owningRoute,
    );
    if (origin == null) return;

    // Regra 1: no pop, só voa se o destino já tinha snapshot registrado antes do push.
    if (effectivelyReturning && !SonoraFlightRegistry.instance.hasPrePushSnapshot(widget.tag, destinationRoute: _owningRoute)) {
      _triggerFadeIn();
      return;
    }

    if (!SonoraFlightRegistry.hasMovedEnough(origin.rect, destRect)) return;

    // Regra 2: acima de 40% da diagonal da tela não voa — faz fade de 150 ms no destino.
    final screenSize = MediaQuery.maybeSizeOf(context) ?? Size.zero;
    if (SonoraFlightRegistry.exceedsMaxDistance(origin.rect, destRect, screenSize)) {
      _triggerFadeIn();
      return;
    }

    final overlayState = Overlay.maybeOf(context, rootOverlay: true);
    if (overlayState == null) return;

    _cancelOverlay();
    setState(() => _flying = true);

    final simulation = SonoraFlightRegistry.createSpring(origin.rect, destRect);
    final shuttle = widget.shuttleChild ?? widget.child;

    _overlay = OverlayEntry(
      builder: (_) => AnimatedBuilder(
        animation: _springCtrl,
        builder: (context, _) {
          final t = _springCtrl.value;
          final currentRect = Rect.lerp(origin.rect, destRect, t) ?? destRect;
          final radius = BorderRadius.lerp(origin.borderRadius, widget.borderRadius, t.clamp(0.0, 1.4)) ??
              widget.borderRadius;
          return Positioned(
            left: currentRect.left,
            top: currentRect.top,
            width: math.max(1.0, currentRect.width),
            height: math.max(1.0, currentRect.height),
            child: IgnorePointer(
              child: ClipRRect(
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(math.max(0.0, radius.topLeft.x)),
                  topRight: Radius.circular(math.max(0.0, radius.topRight.x)),
                  bottomLeft: Radius.circular(math.max(0.0, radius.bottomLeft.x)),
                  bottomRight: Radius.circular(math.max(0.0, radius.bottomRight.x)),
                ),
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: math.max(1.0, destRect.width),
                    height: math.max(1.0, destRect.height),
                    child: shuttle,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );

    overlayState.insert(_overlay!);
    _springCtrl.animateWith(simulation).whenCompleteOrCancel(() {
      _cancelOverlay();
      if (mounted) {
        setState(() => _flying = false);
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) captureNow();
        });
      }
    });
  }

  void _cancelOverlay() {
    _overlay?.remove();
    _overlay = null;
    if (_springCtrl.isAnimating) {
      _springCtrl.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        _lastInteracted = DateTime.now();
        captureNow();
      },
      child: _fadeSeq > 0 && !_flying
          ? TweenAnimationBuilder<double>(
              key: ValueKey(_fadeSeq),
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              builder: (_, value, child) => Opacity(opacity: value, child: child),
              child: widget.child,
            )
          : Opacity(
              opacity: _flying ? 0.0 : 1.0,
              child: widget.child,
            ),
    );
  }
}
