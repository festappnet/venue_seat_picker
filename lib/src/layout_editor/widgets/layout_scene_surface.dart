import 'dart:math' as math;
import 'dart:async';
import 'dart:ui' as ui;
import 'layout_inline_label.dart';
import 'layout_table_selection.dart';
import 'layout_context_menu_stub.dart'
    if (dart.library.js_interop) 'layout_context_menu_web.dart'
    as context_menu;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import '../layout_scene_cache.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

// Matrix4's 3D maximum includes the unchanged z-axis (1), so it cannot
// measure a zoom below 1. The camera is a two-dimensional similarity transform.
double _cameraScale(Matrix4? value) => value == null
    ? 1
    : math.sqrt(
        value.entry(0, 0) * value.entry(0, 0) +
            value.entry(1, 0) * value.entry(1, 0),
      );

/// Shared display-list consumer. All document geometry comes from the core.
class LayoutSceneSurface extends StatefulWidget {
  const LayoutSceneSurface({
    super.key,
    required this.document,
    this.resources = const {},
    this.presentation = const {},
    this.selected = const {},
    this.highlightedIds = const {},
    this.canvasSelected = false,
    this.transientForegroundIds = const {},
    this.warningIds = const {},
    this.snapGuides = const [],
    this.onViewportScaleChanged,
    this.onTap,
    this.onSelectDown,
    this.onPointTap,
    this.onHover,
    this.pathPoints = const [],
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.onDragCancel,
    this.pan = true,
    this.showControls = true,
    this.compactZoomControls = false,
    this.showGrid = false,
    this.gridStep = 8,
    this.gridOrigin = Offset.zero,
    this.animate = true,
    this.onHandleStart,
    this.onDropPreview,
    this.onDrop,
    this.onDropCancel,
    this.onDoubleTap,
    this.marquee,
    this.inlineNode,
    this.onInlineSubmit,
    this.onInlineCancel,
    this.onDoubleTapAt,
    this.onContextMenu,
  });
  final VenueLayoutDocument document;
  final Map<String, dynamic> resources, presentation;
  final Set<String> selected, highlightedIds;
  final Set<String> transientForegroundIds, warningIds;
  final List<Map<String, dynamic>> snapGuides;
  final ValueChanged<double>? onViewportScaleChanged;
  final ValueChanged<Offset>? onTap, onDragStart, onDragUpdate;
  final ValueChanged<Offset>? onSelectDown, onPointTap, onHover;
  final List<Offset> pathPoints;
  final VoidCallback? onDragEnd, onDragCancel;
  final bool pan, showControls, animate;
  final bool compactZoomControls;
  final bool showGrid;
  final double gridStep;
  final Offset gridOrigin;
  final bool canvasSelected;
  final Rect? marquee;
  final LayoutNode? inlineNode;
  final ValueChanged<String>? onInlineSubmit;
  final VoidCallback? onInlineCancel;
  final ValueChanged<Offset>? onDoubleTapAt;
  final void Function(Offset world, Offset global)? onContextMenu;
  final void Function(String, Offset)? onHandleStart, onDropPreview, onDrop;
  final VoidCallback? onDropCancel, onDoubleTap;

  @override
  State<LayoutSceneSurface> createState() => _LayoutSceneSurfaceState();
}

class _LayoutSceneSurfaceState extends State<LayoutSceneSurface>
    with SingleTickerProviderStateMixin {
  List<List<double>>? _vertexPoints(LayoutNode node) {
    final points = node.properties['points'];
    if (points is List) {
      return points
          .map((p) => (p as List).map((v) => (v as num).toDouble()).toList())
          .toList();
    }
    return const [
          'line',
          'arrow',
          'polyline',
        ].contains(node.properties['shape'])
        ? [
            [-node.width / 2, 0],
            [node.width / 2, 0],
          ]
        : null;
  }

  final _camera = TransformationController();
  String? _hoverMessage, _hoverNodeId;
  Offset _hoverPosition = Offset.zero;
  GlobalKey<TooltipState> _hoverTooltipKey = GlobalKey<TooltipState>();

  MouseCursor get _pickerCursor {
    final id = _hoverNodeId;
    if (id != null &&
        widget.document.nodes.any(
          (n) => n.id == id && (n.kind == 'seat' || n.kind == 'capacityArea'),
        )) {
      final raw = widget.presentation[id];
      final p = raw is Map ? raw : const {};
      final unavailable =
          p['selectable'] == false ||
          p['pending'] == true ||
          const [
            'occupied',
            'unavailable',
            'disabled',
            'reserved',
            'blocked',
            'sold',
          ].contains(p['status']);
      return unavailable ? SystemMouseCursors.basic : SystemMouseCursors.click;
    }
    return widget.pan ? SystemMouseCursors.grab : SystemMouseCursors.basic;
  }

  void _hideHoverTooltip({bool clearNode = false}) {
    if (_hoverMessage != null || (clearNode && _hoverNodeId != null)) {
      setState(() {
        _hoverMessage = null;
        if (clearNode) _hoverNodeId = null;
      });
    }
  }

  void _showHoverTooltip(Offset global, Offset world) {
    final id = hitTest(widget.document, world.dx, world.dy);
    final presentation = id == null ? null : widget.presentation[id];
    final message = presentation is Map
        ? presentation['tooltip'] as String?
        : null;
    if (message == _hoverMessage && id == _hoverNodeId) return;
    final box = context.findRenderObject() as RenderBox?;
    setState(() {
      _hoverMessage = message;
      _hoverNodeId = id;
      _hoverPosition = box?.globalToLocal(global) ?? Offset.zero;
      _hoverTooltipKey = GlobalKey<TooltipState>();
    });
    if (message != null && message.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _hoverTooltipKey.currentState?.ensureTooltipVisible();
      });
    }
  }

  Offset? _doubleTapPosition;
  Offset? _pointTapDown;
  Offset? _dragPointerDown;
  late final _motion = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: layoutMotionTokens['reflowMs']!),
  );
  Map<String, dynamic>? _motionFrom;
  late final VoidCallback _stopContextMenu;
  @override
  void initState() {
    super.initState();
    _stopContextMenu = context_menu.suppressCanvasContextMenu((x, y) {
      if (!mounted || widget.onContextMenu == null) return false;
      final box = context.findRenderObject();
      return box is RenderBox &&
          box.hasSize &&
          (Offset.zero & box.size).contains(box.globalToLocal(Offset(x, y)));
    });
  }

  @override
  void didUpdateWidget(LayoutSceneSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.animate ||
        (MediaQuery.maybeOf(context)?.disableAnimations ?? false)) {
      _motion.stop();
      _motion.value = 1;
      _motionFrom = null;
      return;
    }
    if (_scene != null &&
        (!identical(oldWidget.document, widget.document) ||
            !identical(oldWidget.presentation, widget.presentation))) {
      _motionFrom = _motion.isAnimating && _motionFrom != null
          ? interpolateScene(_motionFrom!, _scene!, _motion.value)
          : _scene;
      _motion.forward(from: 0);
    }
  }

  bool _interactionDragging = false, _twoFinger = false;
  double _gestureScale = 1;

  Rect? _cameraCanvas;
  double get _fitCameraZoom {
    final bounds = _cameraCanvas, size = _size;
    if (bounds == null || size == null) return 1;
    return math.min(
      math.max(1, size.width - 32) / bounds.width,
      math.max(1, size.height - 32) / bounds.height,
    );
  }

  Matrix4 _boundCamera(Matrix4 value) {
    final bounds = _cameraCanvas, size = _size;
    if (bounds == null || size == null) return value;
    final zoom = _cameraScale(value);
    double translation(double value, double start, double end, double extent) {
      final a = 16 - start * zoom, b = extent - 16 - end * zoom;
      return value.clamp(math.min(a, b), math.max(a, b));
    }

    return value.clone()..setTranslationRaw(
      translation(value.entry(0, 3), bounds.left, bounds.right, size.width),
      translation(value.entry(1, 3), bounds.top, bounds.bottom, size.height),
      0,
    );
  }

  void _moveCamera(Offset focal, Offset delta, double scaleChange) {
    final current = _cameraScale(_camera.value);
    final fit = _fitCameraZoom;
    final factor =
        (current * scaleChange).clamp(
          fit * (widget.compactZoomControls ? 1 : .9),
          fit * (widget.compactZoomControls ? 5 : 20),
        ) /
        current;
    _camera.value = _boundCamera(
      Matrix4.translationValues(focal.dx, focal.dy, 0)
        ..multiply(Matrix4.diagonal3Values(factor, factor, 1))
        ..multiply(
          Matrix4.translationValues(
            -focal.dx + delta.dx,
            -focal.dy + delta.dy,
            0,
          ),
        )
        ..multiply(_camera.value),
    );
  }

  void _pointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent && event is! PointerScaleEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (signal) {
      if (signal is PointerScaleEvent) {
        _moveCamera(signal.localPosition, Offset.zero, signal.scale);
      } else if (signal is PointerScrollEvent) {
        final keyboard = HardwareKeyboard.instance;
        if (!keyboard.isShiftPressed) {
          _moveCamera(
            signal.localPosition,
            Offset.zero,
            math.exp(-signal.scrollDelta.dy / 200),
          );
        } else {
          final delta = keyboard.isShiftPressed && signal.scrollDelta.dx == 0
              ? Offset(signal.scrollDelta.dy, 0)
              : signal.scrollDelta;
          _moveCamera(signal.localPosition, -delta, 1);
        }
      }
    });
  }

  Timer? _autopanTimer;
  Offset? _autopanPosition;
  VoidCallback? _autopanUpdate;
  void _stopAutopan() {
    _autopanTimer?.cancel();
    _autopanTimer = null;
    _autopanUpdate = null;
  }

  void _trackAutopan(Offset localPosition, VoidCallback update) {
    _autopanPosition = localPosition;
    _autopanUpdate = update;
    _autopanTimer ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
      final point = _autopanPosition, size = _size;
      if (!mounted ||
          point == null ||
          size == null ||
          !(Offset.zero & size).contains(point)) {
        _stopAutopan();
        return;
      }
      double speed(double value, double extent) => value < 40
          ? (40 - value) / 40 * 10
          : value > extent - 40
          ? -(value - extent + 40) / 40 * 10
          : 0;
      final dx = speed(point.dx, size.width), dy = speed(point.dy, size.height);
      if (dx != 0 || dy != 0) {
        _moveCamera(Offset.zero, Offset(dx, dy), 1);
        _autopanUpdate?.call();
      }
    });
  }

  Map<String, dynamic>? _frame;
  Size? _size;
  final _sceneCache = LayoutSceneCache();
  Map<String, dynamic>? _scene;

  @override
  void dispose() {
    _stopAutopan();
    _stopContextMenu();
    _motion.dispose();
    _camera.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      if (_size != size) {
        _size = size;
        _frame = null;
        _camera.value = Matrix4.identity();
      }
      _frame ??= Map<String, dynamic>.from(widget.document.canvas);
      final frame = _frame!;
      final width = (frame['width'] as num? ?? 2400).toDouble();
      final height = (frame['height'] as num? ?? 1600).toDouble();
      final x = (frame['x'] as num? ?? 0).toDouble();
      final y = (frame['y'] as num? ?? 0).toDouble();
      final scale = math
          .min((size.width - 32) / width, (size.height - 32) / height)
          .clamp(.00001, 100.0);
      final offset = Offset(
        (size.width - width * scale) / 2,
        (size.height - height * scale) / 2,
      );
      final canvas = widget.document.canvas;
      _cameraCanvas = Rect.fromLTWH(
        offset.dx + ((canvas['x'] as num? ?? 0) - x) * scale,
        offset.dy + ((canvas['y'] as num? ?? 0) - y) * scale,
        (canvas['width'] as num).toDouble() * scale,
        (canvas['height'] as num).toDouble() * scale,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.onViewportScaleChanged?.call(
            scale * _cameraScale(_camera.value),
          );
        }
      });
      Offset world(Offset p) {
        widget.onViewportScaleChanged?.call(
          scale * _cameraScale(_camera.value),
        );
        return (_camera.toScene(p) - offset) / scale + Offset(x, y);
      }

      _scene = _sceneCache.update(
        widget.document,
        resources: widget.resources,
        presentation: widget.presentation,
      );
      final scene = _scene!;
      final issues = scene['issues'] as List? ?? const [];
      Offset globalWorld(Offset p) =>
          world((context.findRenderObject()! as RenderBox).globalToLocal(p));
      void dragAt(Offset global, [String? kind]) {
        void update() {
          if (kind == null) {
            widget.onDragUpdate?.call(globalWorld(global));
          } else {
            widget.onDropPreview?.call(kind, globalWorld(global));
          }
        }

        update();
        _trackAutopan(
          (context.findRenderObject()! as RenderBox).globalToLocal(global),
          update,
        );
      }

      Widget handle(
        String mode,
        List<double> at,
        IconData icon, {
        Offset screenOffset = Offset.zero,
        MouseCursor cursor = SystemMouseCursors.precise,
      }) => AnimatedBuilder(
        animation: _camera,
        builder: (context, _) {
          final screen =
              MatrixUtils.transformPoint(
                _camera.value,
                (Offset(at[0], at[1]) - Offset(x, y)) * scale + offset,
              ) +
              screenOffset;
          final rotation = mode == 'Rotate';
          final insert =
              mode.startsWith('Insert vertex ') ||
              mode.startsWith('Extend edge ');
          final amplitude = mode == 'Zigzag amplitude';
          final label = mode.startsWith('Zigzag endpoint ')
              ? 'Line endpoint handle'
              : amplitude
              ? 'Zigzag height handle'
              : insert
              ? (mode.startsWith('Extend edge ')
                    ? 'Extend surface'
                    : 'Add bend')
              : '$mode handle';
          return Positioned(
            left: screen.dx - 12,
            top: screen.dy - 12,
            child: Semantics(
              button: true,
              label: VenueLayoutStrings.text(context, label),
              child: Tooltip(
                message: VenueLayoutStrings.text(context, label),
                child: MouseRegion(
                  cursor: cursor,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (e) => widget.onHandleStart?.call(
                      mode,
                      globalWorld(e.globalPosition),
                    ),
                    onPanUpdate: (e) => dragAt(e.globalPosition),
                    onPanEnd: (_) {
                      _stopAutopan();
                      widget.onDragEnd?.call();
                    },
                    onPanCancel: () {
                      _stopAutopan();
                      widget.onDragCancel?.call();
                    },
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: Center(
                        child: Container(
                          width: rotation ? 12 : 10,
                          height: rotation ? 12 : 10,
                          decoration: BoxDecoration(
                            color: rotation || insert || amplitude
                                ? Theme.of(context).colorScheme.surface
                                : Theme.of(context).colorScheme.primary,
                            shape: rotation || insert || amplitude
                                ? BoxShape.circle
                                : BoxShape.rectangle,
                            border: rotation || insert || amplitude
                                ? Border.all(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    width: 1.5,
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
      bool unlocked(LayoutNode node) {
        final byId = {for (final n in widget.document.nodes) n.id: n};
        LayoutNode? current = node;
        while (current != null) {
          if (current.locked) return false;
          current = byId[current.parentId];
        }
        return true;
      }

      MouseCursor resizeCursor(LayoutNode node, double sx, double sy) {
        final matrix = worldMatrix(widget.document, node);
        final angle = math.atan2(
          matrix[1] * sx + matrix[3] * sy,
          matrix[0] * sx + matrix[2] * sy,
        );
        final axis = ((angle / (math.pi / 4)).round() % 4 + 4) % 4;
        return [
          SystemMouseCursors.resizeLeftRight,
          SystemMouseCursors.resizeUpLeftDownRight,
          SystemMouseCursors.resizeUpDown,
          SystemMouseCursors.resizeUpRightDownLeft,
        ][axis];
      }

      Widget inlineEditor(LayoutNode node) => AnimatedBuilder(
        animation: _camera,
        builder: (context, _) {
          final matrix = worldMatrix(widget.document, node);
          final fontSize =
              (node.properties['size'] as num? ??
                      (node.kind == 'text' ? 24 : 16))
                  .toDouble();
          final zoom = scale * _cameraScale(_camera.value);
          final width =
              math.max(24.0, node.width - (node.kind == 'text' ? 0 : 12)) *
              zoom;
          final height =
              (node.kind == 'text'
                  ? math.max(fontSize * 1.6, node.height)
                  : math.min(node.height, fontSize * 1.8)) *
              zoom;
          final center = MatrixUtils.transformPoint(
            _camera.value,
            (Offset(matrix[4], matrix[5]) - Offset(x, y)) * scale + offset,
          );
          final angle =
              math.atan2(matrix[1], matrix[0]) +
              math.atan2(_camera.value.entry(1, 0), _camera.value.entry(0, 0));
          final font =
              (widget.resources['fonts'] as Map?)?[node.properties['fontId']];
          // Native text input lays out in viewport pixels. Only rotation needs
          // a paint transform; camera zoom never scales the editable subtree.
          final editor = LayoutInlineLabel(
            key: ValueKey(node.id),
            value: node.kind == 'text'
                ? '${node.properties['text'] ?? node.label}'
                : node.label,
            style: TextStyle(
              fontFamily: font is Map ? font['family'] as String? : null,
              fontSize: fontSize * zoom,
              color: LayoutScenePainter.color(
                node.properties['color'],
                const Color(0xff202830),
              ),
              fontWeight: node.properties['bold'] == true
                  ? FontWeight.bold
                  : FontWeight.normal,
              fontStyle: node.properties['italic'] == true
                  ? FontStyle.italic
                  : FontStyle.normal,
            ),
            textAlign:
                node.kind == 'text' && node.properties['align'] != 'center'
                ? (node.properties['align'] == 'right'
                      ? TextAlign.right
                      : TextAlign.left)
                : TextAlign.center,
            background: LayoutScenePainter.color(
              node.kind == 'text' ? '#FFFFFFFF' : node.properties['fill'],
              const Color(0xffe2e8f0),
            ),
            onSubmit: (value) => widget.onInlineSubmit?.call(value),
            onCancel: () => widget.onInlineCancel?.call(),
          );
          return Positioned(
            left: center.dx - width / 2,
            top: center.dy - height / 2,
            width: width,
            height: height,
            child: angle.abs() < 1e-10
                ? editor
                : Transform.rotate(angle: angle, child: editor),
          );
        },
      );
      final seatLinks = tableSeatLinks(widget.document, widget.selected);
      final selectedNodes = widget.document.nodes
          .where((n) => widget.selected.contains(n.id))
          .toList();
      Map<String, double> localBounds(LayoutNode node) {
        if (node.properties['assembly'] != 'rows') {
          return {
            'x': -node.width / 2,
            'y': -node.height / 2,
            'width': node.width,
            'height': node.height,
          };
        }
        return rowAssemblyBounds(widget.document, node.id);
      }

      final handleBounds = {
        for (final node in selectedNodes) node.id: localBounds(node),
      };
      List<double> handlePoint(LayoutNode node, double dx, double dy) {
        if ((node.kind == 'group' && node.properties['assembly'] == null) ||
            const [
              'bus',
              'compartments',
            ].contains(node.properties['assembly'])) {
          final b = selectionBounds(widget.document, {node.id});
          return [
            b['x']! + b['width']! * (dx + 1) / 2,
            b['y']! + b['height']! * (dy + 1) / 2,
          ];
        }
        final b = handleBounds[node.id]!;
        return transformPoint(
          worldMatrix(widget.document, node),
          b['x']! + b['width']! * (dx + 1) / 2,
          b['y']! + b['height']! * (dy + 1) / 2,
        );
      }

      return Listener(
        onPointerSignal: _pointerSignal,
        onPointerCancel: (_) {
          _stopAutopan();
          _interactionDragging = false;
          widget.onDragCancel?.call();
        },
        child: DragTarget<String>(
          onWillAcceptWithDetails: (_) => widget.onDrop != null,
          onMove: (details) => dragAt(details.offset, details.data),
          onAcceptWithDetails: (details) {
            _stopAutopan();
            widget.onDrop?.call(details.data, globalWorld(details.offset));
          },
          onLeave: (_) {
            _stopAutopan();
            widget.onDropCancel?.call();
          },
          builder: (context, candidate, rejected) => Stack(
            children: [
              if (_hoverMessage != null && _hoverMessage!.isNotEmpty)
                Positioned(
                  left: _hoverPosition.dx,
                  top: _hoverPosition.dy,
                  child: IgnorePointer(
                    child: Tooltip(
                      key: _hoverTooltipKey,
                      message: _hoverMessage!,
                      triggerMode: TooltipTriggerMode.manual,
                      child: const SizedBox(width: 1, height: 1),
                    ),
                  ),
                ),
              Positioned.fill(
                key: const ValueKey('layout-map-gesture-surface'),
                child: ClipRect(
                  child: MouseRegion(
                    onExit: (_) => _hideHoverTooltip(clearNode: true),
                    cursor: widget.compactZoomControls
                        ? _pickerCursor
                        : widget.onPointTap != null
                        ? SystemMouseCursors.precise
                        : widget.pan
                        ? SystemMouseCursors.grab
                        : SystemMouseCursors.basic,
                    child: GestureDetector(
                      // The secondary-click recognizer otherwise advertises a
                      // primary semantic tap with no handler. Web semantics
                      // consumes coordinate clicks before selection sees them.
                      // Object actions remain available through the inspector.
                      excludeFromSemantics: true,
                      behavior: HitTestBehavior.opaque,
                      onSecondaryTapUp: widget.onContextMenu == null
                          ? null
                          : (details) => widget.onContextMenu!(
                              globalWorld(details.globalPosition),
                              details.globalPosition,
                            ),
                      onLongPressStart: widget.onContextMenu == null
                          ? null
                          : (details) {
                              _pointTapDown = null;
                              widget.onContextMenu!(
                                globalWorld(details.globalPosition),
                                details.globalPosition,
                              );
                            },
                      onScaleStart: (details) {
                        _gestureScale = 1;
                        if (!widget.pan &&
                            details.pointerCount == 1 &&
                            widget.onDragStart != null) {
                          _interactionDragging = true;
                          widget.onDragStart!(
                            globalWorld(_dragPointerDown ?? details.focalPoint),
                          );
                        }
                      },
                      onScaleUpdate: (details) {
                        if (details.pointerCount != 1) {
                          if (_interactionDragging) {
                            _stopAutopan();
                            widget.onDragCancel?.call();
                            _interactionDragging = false;
                          }
                          _twoFinger = true;
                        }
                        if (widget.pan || _twoFinger) {
                          _moveCamera(
                            details.localFocalPoint,
                            details.focalPointDelta,
                            details.scale / _gestureScale,
                          );
                        } else if (_interactionDragging) {
                          dragAt(details.focalPoint);
                        }
                        _gestureScale = details.scale;
                      },
                      onScaleEnd: (_) {
                        _stopAutopan();
                        if (_interactionDragging) widget.onDragEnd?.call();
                        _interactionDragging = false;
                        _twoFinger = false;
                      },
                      child: GestureDetector(
                        // A semantic tap synthesizes the center, losing the
                        // coordinate needed to place or select an object.
                        excludeFromSemantics: true,
                        behavior: HitTestBehavior.opaque,
                        onDoubleTapDown: widget.onDoubleTapAt == null
                            ? null
                            : (e) => _doubleTapPosition = globalWorld(
                                e.globalPosition,
                              ),
                        onDoubleTap: widget.onDoubleTapAt == null
                            ? widget.onDoubleTap
                            : () {
                                if (_doubleTapPosition != null) {
                                  widget.onDoubleTapAt!(_doubleTapPosition!);
                                }
                              },
                        onTapUp: widget.onTap == null
                            ? null
                            : (e) =>
                                  widget.onTap!(globalWorld(e.globalPosition)),
                        child: Listener(
                          behavior: HitTestBehavior.opaque,
                          onPointerDown: (event) {
                            _hideHoverTooltip();
                            if (event.buttons != kPrimaryButton) return;
                            _dragPointerDown ??= event.position;
                            _pointTapDown = widget.onPointTap == null
                                ? null
                                : event.position;
                            widget.onSelectDown?.call(
                              globalWorld(event.position),
                            );
                          },
                          onPointerHover: (event) {
                            final world = globalWorld(event.position);
                            _showHoverTooltip(event.position, world);
                            widget.onHover?.call(world);
                          },
                          onPointerMove: (event) {
                            if (_pointTapDown != null &&
                                (event.position - _pointTapDown!).distance >
                                    kTouchSlop) {
                              _pointTapDown = null;
                            }
                          },
                          onPointerCancel: (_) {
                            _pointTapDown = null;
                            _dragPointerDown = null;
                          },
                          onPointerUp: (event) {
                            _dragPointerDown = null;
                            final down = _pointTapDown;
                            _pointTapDown = null;
                            if (down != null) {
                              widget.onPointTap?.call(
                                globalWorld(event.position),
                              );
                            }
                          },
                          child: CustomPaint(
                            size: size,
                            painter: LayoutScenePainter(
                              scene: scene,
                              camera: _camera,
                              motion: _motion,
                              fromScene: _motionFrom,
                              resources: widget.resources,
                              selected: widget.selected,
                              seatLinks: seatLinks,
                              snapGuides: widget.snapGuides,
                              showGrid: widget.showGrid,
                              gridStep: widget.gridStep,
                              gridOrigin: widget.gridOrigin,
                              transientForegroundIds:
                                  widget.transientForegroundIds,
                              warningHulls: [
                                for (final node in widget.document.nodes)
                                  if (widget.warningIds.contains(node.id))
                                    (() {
                                      final b = selectionBounds(
                                        widget.document,
                                        {node.id},
                                      );
                                      return <List<double>>[
                                        [b['x']!, b['y']!],
                                        [b['x']! + b['width']!, b['y']!],
                                        [
                                          b['x']! + b['width']!,
                                          b['y']! + b['height']!,
                                        ],
                                        [b['x']!, b['y']! + b['height']!],
                                      ];
                                    })(),
                              ],
                              selectionHulls: [
                                for (final node in widget.document.nodes.where(
                                  (n) => widget.highlightedIds.contains(n.id),
                                ))
                                  worldHull(
                                    node,
                                    worldMatrix(widget.document, node),
                                  ),
                                if (widget.canvasSelected)
                                  (() {
                                    final c = widget.document.canvas;
                                    final l = (c['x'] as num).toDouble(),
                                        t = (c['y'] as num).toDouble(),
                                        r = l + (c['width'] as num),
                                        b = t + (c['height'] as num);
                                    return <List<double>>[
                                      [l, t],
                                      [r, t],
                                      [r, b],
                                      [l, b],
                                    ];
                                  })(),
                                for (final node in selectedNodes)
                                  if (node.kind == 'group')
                                    (() {
                                      final b = selectionBounds(
                                        widget.document,
                                        {node.id},
                                      );
                                      return <List<double>>[
                                        [b['x']!, b['y']!],
                                        [b['x']! + b['width']!, b['y']!],
                                        [
                                          b['x']! + b['width']!,
                                          b['y']! + b['height']!,
                                        ],
                                        [b['x']!, b['y']! + b['height']!],
                                      ];
                                    })()
                                  else
                                    [
                                      for (final corner in <List<double>>[
                                        [-node.width / 2, -node.height / 2],
                                        [node.width / 2, -node.height / 2],
                                        [node.width / 2, node.height / 2],
                                        [-node.width / 2, node.height / 2],
                                      ])
                                        transformPoint(
                                          worldMatrix(widget.document, node),
                                          corner[0],
                                          corner[1],
                                        ),
                                    ],
                              ],
                              scale: scale,
                              offset: offset - Offset(x, y) * scale,
                              canvasColor: Theme.of(
                                context,
                              ).colorScheme.surface,
                              selectionColor: Theme.of(
                                context,
                              ).colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (widget.marquee != null)
                AnimatedBuilder(
                  animation: _camera,
                  builder: (context, _) {
                    Offset screen(Offset p) => MatrixUtils.transformPoint(
                      _camera.value,
                      (p - Offset(x, y)) * scale + offset,
                    );
                    return Positioned.fromRect(
                      rect: Rect.fromPoints(
                        screen(widget.marquee!.topLeft),
                        screen(widget.marquee!.bottomRight),
                      ),
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Theme.of(context).colorScheme.primary,
                              width: 2,
                            ),
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: .1),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              for (final point in widget.pathPoints)
                AnimatedBuilder(
                  animation: _camera,
                  builder: (context, _) {
                    final at = MatrixUtils.transformPoint(
                      _camera.value,
                      (point - Offset(x, y)) * scale + offset,
                    );
                    return Positioned(
                      left: at.dx - 4,
                      top: at.dy - 4,
                      child: IgnorePointer(
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            border: Border.all(
                              color: Theme.of(context).colorScheme.surface,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              if (widget.canvasSelected && widget.onHandleStart != null)
                for (final direction in <String, List<double>>{
                  'n': [.5, 0],
                  'e': [1, .5],
                  's': [.5, 1],
                  'w': [0, .5],
                  'nw': [0, 0],
                  'ne': [1, 0],
                  'sw': [0, 1],
                  'se': [1, 1],
                }.entries)
                  handle(
                    'Canvas resize ${direction.key}',
                    [
                      (widget.document.canvas['x'] as num).toDouble() +
                          (widget.document.canvas['width'] as num) *
                              direction.value[0],
                      (widget.document.canvas['y'] as num).toDouble() +
                          (widget.document.canvas['height'] as num) *
                              direction.value[1],
                    ],
                    Icons.open_in_full,
                    cursor: direction.key == 'n' || direction.key == 's'
                        ? SystemMouseCursors.resizeUpDown
                        : direction.key == 'e' || direction.key == 'w'
                        ? SystemMouseCursors.resizeLeftRight
                        : direction.key == 'nw' || direction.key == 'se'
                        ? SystemMouseCursors.resizeUpLeftDownRight
                        : SystemMouseCursors.resizeUpRightDownLeft,
                  ),
              if (widget.onHandleStart != null &&
                  selectedNodes.length > 1 &&
                  selectedNodes.every(unlocked))
                handle(
                  'Rotate',
                  [
                    selectionBounds(widget.document, widget.selected)['x']! +
                        selectionBounds(
                              widget.document,
                              widget.selected,
                            )['width']! /
                            2,
                    selectionBounds(widget.document, widget.selected)['y']!,
                  ],
                  Icons.rotate_right,
                  screenOffset: const Offset(0, -24),
                  cursor: SystemMouseCursors.grab,
                ),
              if (widget.onHandleStart != null &&
                  selectedNodes.length == 1 &&
                  unlocked(selectedNodes.single)) ...[
                // Edge targets precede corner targets so corners win overlaps.
                if (!const [
                      'line',
                      'polyline',
                      'arrow',
                    ].contains(selectedNodes.single.properties['shape']) &&
                    !(selectedNodes.single.kind == 'table' &&
                        selectedNodes.single.properties['shape'] ==
                            'polygon') &&
                    !const [
                      'bus',
                      'compartments',
                    ].contains(selectedNodes.single.properties['assembly']))
                  for (final direction in <String, List<double>>{
                    'n': [0, -1],
                    'e': [1, 0],
                    's': [0, 1],
                    'w': [-1, 0],
                    'nw': [-1, -1],
                    'ne': [1, -1],
                    'sw': [-1, 1],
                    'se': [1, 1],
                  }.entries)
                    handle(
                      direction.key == 'se'
                          ? 'Resize'
                          : 'Resize ${direction.key}',
                      handlePoint(
                        selectedNodes.single,
                        direction.value[0],
                        direction.value[1],
                      ),
                      Icons.open_in_full,
                      cursor: resizeCursor(
                        selectedNodes.single,
                        direction.value[0],
                        direction.value[1],
                      ),
                    ),
                handle(
                  'Rotate',
                  handlePoint(selectedNodes.single, 0, -1),
                  Icons.rotate_right,
                  screenOffset: const Offset(0, -24),
                  cursor: SystemMouseCursors.grab,
                ),
                if (!isZigzagNode(selectedNodes.single) &&
                    const [
                      'polyline',
                      'polygon',
                    ].contains(selectedNodes.single.properties['shape']) &&
                    _vertexPoints(selectedNodes.single) != null)
                  for (
                    var i = 0;
                    i <
                        _vertexPoints(selectedNodes.single)!.length -
                            (selectedNodes.single.properties['shape'] ==
                                    'polygon'
                                ? 0
                                : 1);
                    i++
                  )
                    handle(
                      selectedNodes.single.kind == 'table'
                          ? 'Extend edge $i'
                          : 'Insert vertex $i',
                      (() {
                        final points = _vertexPoints(selectedNodes.single)!;
                        final a = points[i],
                            b = points[(i + 1) % points.length];
                        return transformPoint(
                          worldMatrix(widget.document, selectedNodes.single),
                          (a[0] + b[0]) / 2,
                          (a[1] + b[1]) / 2,
                        );
                      })(),
                      Icons.add,
                      cursor: SystemMouseCursors.precise,
                    ),
                if (!isZigzagNode(selectedNodes.single) &&
                    _vertexPoints(selectedNodes.single) != null)
                  for (
                    var i = 0;
                    i < _vertexPoints(selectedNodes.single)!.length;
                    i++
                  )
                    handle(
                      'Vertex $i',
                      transformPoint(
                        worldMatrix(widget.document, selectedNodes.single),
                        _vertexPoints(selectedNodes.single)![i][0],
                        _vertexPoints(selectedNodes.single)![i][1],
                      ),
                      Icons.circle_outlined,
                    ),
                if (isZigzagNode(selectedNodes.single)) ...[
                  for (final index in [
                    0,
                    _vertexPoints(selectedNodes.single)!.length - 1,
                  ])
                    handle(
                      'Zigzag endpoint $index',
                      transformPoint(
                        worldMatrix(widget.document, selectedNodes.single),
                        _vertexPoints(selectedNodes.single)![index][0],
                        _vertexPoints(selectedNodes.single)![index][1],
                      ),
                      Icons.circle_outlined,
                    ),
                  handle(
                    'Zigzag amplitude',
                    (() {
                      final node = selectedNodes.single;
                      final points = _vertexPoints(node)!;
                      final first = points.first, last = points.last;
                      final dx = last[0] - first[0], dy = last[1] - first[1];
                      final length = math.sqrt(dx * dx + dy * dy);
                      final height = (node.properties['zigzagAmplitude'] as num)
                          .toDouble();
                      final nx = length > 0 ? -dy / length : 0.0;
                      final ny = length > 0 ? dx / length : 1.0;
                      return transformPoint(
                        worldMatrix(widget.document, node),
                        (first[0] + last[0]) / 2 + nx * height,
                        (first[1] + last[1]) / 2 + ny * height,
                      );
                    })(),
                    Icons.height,
                  ),
                ],
              ],
              if (widget.inlineNode != null)
                inlineEditor(
                  widget.inlineNode!.copyWith(
                    properties: effectiveNodeProperties(
                      widget.document,
                      widget.inlineNode!,
                    ),
                  ),
                ),
              if (widget.showControls)
                Positioned(
                  right: widget.compactZoomControls ? 16 : 8,
                  bottom: widget.compactZoomControls ? 16 : 8,
                  child: widget.compactZoomControls
                      ? AnimatedBuilder(
                          animation: _camera,
                          builder: (context, _) {
                            final zoom = _cameraScale(_camera.value),
                                fit = _fitCameraZoom;
                            Widget button(
                              String label,
                              IconData icon,
                              VoidCallback? action,
                            ) => SizedBox(
                              width: 44,
                              height: 44,
                              child: IconButton(
                                tooltip: VenueLayoutStrings.text(
                                  context,
                                  label,
                                ),
                                iconSize: 20,
                                padding: EdgeInsets.zero,
                                onPressed: action,
                                icon: Icon(icon),
                              ),
                            );
                            return Material(
                              color: Theme.of(context).colorScheme.surface,
                              elevation: 4,
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.all(2),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    button(
                                      'Zoom in',
                                      Icons.add,
                                      zoom < fit * 5 - .001
                                          ? () => _moveCamera(
                                              Offset(
                                                size.width / 2,
                                                size.height / 2,
                                              ),
                                              Offset.zero,
                                              1.25,
                                            )
                                          : null,
                                    ),
                                    button(
                                      'Zoom out',
                                      Icons.remove,
                                      zoom > fit + .001
                                          ? () => _moveCamera(
                                              Offset(
                                                size.width / 2,
                                                size.height / 2,
                                              ),
                                              Offset.zero,
                                              1 / 1.25,
                                            )
                                          : null,
                                    ),
                                    const SizedBox(
                                      width: 44,
                                      child: Divider(height: 3),
                                    ),
                                    button(
                                      'Fit plan',
                                      Icons.fullscreen,
                                      () => setState(() {
                                        _frame = null;
                                        _camera.value = Matrix4.identity();
                                      }),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        )
                      : FilledButton.tonalIcon(
                          onPressed: () => setState(() {
                            _frame = null;
                            _camera.value = Matrix4.identity();
                          }),
                          icon: const Icon(Icons.fit_screen),
                          label: const LayoutText('Fit plan'),
                        ),
                ),
              if (widget.showControls && issues.isNotEmpty)
                Positioned(
                  left: 8,
                  top: 8,
                  right: 8,
                  child: Material(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: LayoutText(
                        'Rendering issue: ${issues.first}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class LayoutScenePainter extends CustomPainter {
  LayoutScenePainter({
    required this.scene,
    required this.resources,
    required this.selected,
    required this.scale,
    required this.offset,
    required this.canvasColor,
    required this.selectionColor,
    this.camera,
    this.showGrid = false,
    this.gridStep = 8,
    this.gridOrigin = Offset.zero,
    this.motion,
    this.fromScene,
    this.seatLinks = const [],
    this.selectionHulls = const [],
    this.warningHulls = const [],
    this.snapGuides = const [],
    this.transientForegroundIds = const {},
  }) : super(repaint: Listenable.merge([camera, motion]));
  final Map<String, dynamic> scene, resources;
  final Set<String> selected;
  final List<TableSeatLink> seatLinks;
  final List<List<List<double>>> selectionHulls, warningHulls;
  final List<Map<String, dynamic>> snapGuides;
  final Set<String> transientForegroundIds;
  final double scale;
  final bool showGrid;
  final double gridStep;
  final Offset gridOrigin;
  final Offset offset;
  final Color canvasColor, selectionColor;
  final TransformationController? camera;
  final Animation<double>? motion;
  final Map<String, dynamic>? fromScene;
  static final Expando<Path> _paths = Expando<Path>();
  static Color color(dynamic value, Color fallback) {
    if (value is! String) return fallback;
    final text = value.replaceFirst('#', '');
    final n = int.tryParse(text, radix: 16);
    if (n == null) return fallback;
    return text.length == 8
        ? Color(((n & 255) << 24) | (n >> 8))
        : Color(0xff000000 | n);
  }

  static Path path(List commands) {
    final p = Path();
    for (final raw in commands) {
      final c = raw as List;
      double v(int i) => (c[i] as num).toDouble();
      switch (c.first) {
        case 'M':
          p.moveTo(v(1), v(2));
        case 'L':
          p.lineTo(v(1), v(2));
        case 'Q':
          p.quadraticBezierTo(v(1), v(2), v(3), v(4));
        case 'C':
          p.cubicTo(v(1), v(2), v(3), v(4), v(5), v(6));
        case 'Z':
          p.close();
      }
    }
    return p;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final display = fromScene != null && motion != null && motion!.value < 1
        ? interpolateScene(fromScene!, scene, motion!.value)
        : scene;
    if (camera != null) canvas.transform(camera!.value.storage);
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(scale);
    final c = display['canvas'] as Map? ?? const {};
    double cv(String k, double fallback) =>
        (c[k] as num? ?? fallback).toDouble();
    canvas.drawRect(
      Rect.fromLTWH(
        cv('x', 0),
        cv('y', 0),
        cv('width', 2400),
        cv('height', 1600),
      ),
      Paint()..color = color(c['fill'] ?? c['color'], canvasColor),
    );
    final topLeft =
        ((camera?.toScene(Offset.zero) ?? Offset.zero) - offset) / scale;
    final bottomRight =
        ((camera?.toScene(Offset(size.width, size.height)) ??
                Offset(size.width, size.height)) -
            offset) /
        scale;
    final visible = cullScene(display, {
      'x': topLeft.dx,
      'y': topLeft.dy,
      'width': bottomRight.dx - topLeft.dx,
      'height': bottomRight.dy - topLeft.dy,
    }, zoom: scale * _cameraScale(camera?.value));
    // Raise complete assemblies for the gesture only, including their glyphs.
    bool foreground(dynamic item) =>
        transientForegroundIds.contains(item['nodeId'] ?? item['id']);
    final paintOrder = transientForegroundIds.isEmpty
        ? visible
        : [
            ...visible.where((item) => !foreground(item)),
            ...visible.where(foreground),
          ];
    var gridPainted = false;
    void paintGrid() {
      if (!showGrid) return;
      final zoom = scale * _cameraScale(camera?.value);
      final bounds = Rect.fromLTWH(
        cv('x', 0),
        cv('y', 0),
        cv('width', 2400),
        cv('height', 1600),
      ).intersect(Rect.fromPoints(topLeft, bottomRight));
      if (bounds.isEmpty) return;
      // Keep the selected lattice. Coarser multiples avoid dense
      // moire and cap work to the visible viewport when zoomed out.
      var step = gridStep;
      while (step * zoom < 12) {
        step *= 5;
      }
      final dark =
          color(c['fill'] ?? c['color'], canvasColor).computeLuminance() < .3;
      final minor = Paint()
        ..color = (dark ? Colors.white : const Color(0xff475569)).withValues(
          alpha: dark ? .18 : .14,
        )
        ..strokeWidth = .6 / zoom;
      final major = Paint()
        ..color = (dark ? Colors.white : const Color(0xff475569)).withValues(
          alpha: dark ? .3 : .26,
        )
        ..strokeWidth = .8 / zoom;
      canvas.save();
      canvas.clipRect(bounds);
      for (
        var x =
            gridOrigin.dx +
            ((bounds.left - gridOrigin.dx) / step).ceil() * step;
        x <= bounds.right;
        x += step
      ) {
        canvas.drawLine(
          Offset(x, bounds.top),
          Offset(x, bounds.bottom),
          ((x - gridOrigin.dx) / step).round() % 5 == 0 ? major : minor,
        );
      }
      for (
        var y =
            gridOrigin.dy + ((bounds.top - gridOrigin.dy) / step).ceil() * step;
        y <= bounds.bottom;
        y += step
      ) {
        canvas.drawLine(
          Offset(bounds.left, y),
          Offset(bounds.right, y),
          ((y - gridOrigin.dy) / step).round() % 5 == 0 ? major : minor,
        );
      }
      canvas.restore();
    }

    final relatedIds = seatLinks.map((link) => link.seatId).toSet();
    final zoom = scale * _cameraScale(camera?.value);
    for (final raw in paintOrder) {
      final item = raw as Map;
      if (!gridPainted &&
          item['id'] != 'background' &&
          item['kind'] != 'floor') {
        paintGrid();
        gridPainted = true;
      }
      canvas.save();
      final clip = item['clip'] as Map?;
      if (clip != null) {
        canvas.clipRect(
          Rect.fromLTWH(
            (clip['x'] as num? ?? 0).toDouble(),
            (clip['y'] as num? ?? 0).toDouble(),
            (clip['width'] as num).toDouble(),
            (clip['height'] as num).toDouble(),
          ),
        );
      }
      Color itemColor(dynamic value) {
        final c = color(value, Colors.transparent);
        return c.withValues(
          alpha: c.a * (item['opacity'] as num? ?? 1).toDouble(),
        );
      }

      final m = item['matrix'] as List? ?? [1, 0, 0, 1, 0, 0];
      canvas.transform(
        Matrix4(
          (m[0] as num).toDouble(),
          (m[1] as num).toDouble(),
          0,
          0,
          (m[2] as num).toDouble(),
          (m[3] as num).toDouble(),
          0,
          0,
          0,
          0,
          1,
          0,
          (m[4] as num).toDouble(),
          (m[5] as num).toDouble(),
          0,
          1,
        ).storage,
      );
      final commands = item['path'] as List?;
      if (commands != null) {
        final p = _paths[item] ??= path(commands);
        if (item['fill'] != null) {
          canvas.drawPath(p, Paint()..color = itemColor(item['fill']));
        }
        final strokeWidth = (item['strokeWidth'] as num? ?? 0).toDouble();
        if (item['stroke'] != null && strokeWidth > 0) {
          canvas.drawPath(
            p,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeCap = item['kind'] == 'state'
                  ? StrokeCap.round
                  : StrokeCap.butt
              ..strokeJoin = item['kind'] == 'state'
                  ? StrokeJoin.round
                  : StrokeJoin.miter
              ..strokeWidth = strokeWidth
              ..color = itemColor(item['stroke']),
          );
        }
      }
      if (commands != null && relatedIds.contains(item['id'])) {
        final outline = _paths[item] ??= path(commands);
        canvas.drawPath(
          outline,
          Paint()..color = selectionColor.withValues(alpha: .08),
        );
        canvas.drawPath(
          outline,
          Paint()
            ..color = selectionColor.withValues(alpha: .65)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2 / zoom,
        );
      }
      final images = resources['images'] as Map?;
      final image = images?[item['assetRef']];
      if (image is ui.Image) {
        Rect rectangle(Map values) => Rect.fromLTWH(
          (values['x'] as num).toDouble(),
          (values['y'] as num).toDouble(),
          (values['width'] as num).toDouble(),
          (values['height'] as num).toDouble(),
        );
        final src = rectangle(item['sourceRect'] as Map);
        final destination = rectangle(item['destinationRect'] as Map);
        canvas.drawImageRect(
          image,
          src,
          destination,
          Paint()
            ..color = Colors.white.withValues(
              alpha: (item['opacity'] as num? ?? 1).toDouble(),
            ),
        );
      }
      canvas.restore();
    }
    final connectionPaint = Paint()
      ..color = selectionColor.withValues(alpha: .55)
      ..strokeWidth = 1 / zoom
      ..strokeCap = StrokeCap.round;
    final viewport = Rect.fromPoints(topLeft, bottomRight);
    for (final link in seatLinks) {
      if (!Rect.fromPoints(
        link.tablePoint,
        link.seatPoint,
      ).inflate(3 / zoom).overlaps(viewport)) {
        continue;
      }
      final delta = link.seatPoint - link.tablePoint, length = delta.distance;
      if (length < 1e-6) continue;
      final direction = delta / length;
      // Bound work even for manually detached chairs far from their table.
      final dashStep = math.max(6 / zoom, length / 128);
      for (var distance = 0.0; distance < length; distance += dashStep) {
        canvas.drawLine(
          link.tablePoint + direction * distance,
          link.tablePoint + direction * math.min(length, distance + 3 / zoom),
          connectionPaint,
        );
      }
      canvas.drawCircle(
        link.tablePoint,
        2 / zoom,
        Paint()..color = connectionPaint.color,
      );
    }
    final guidePaint = Paint()
      ..color = selectionColor.withValues(alpha: .8)
      ..strokeWidth = 1 / (scale * _cameraScale(camera?.value));
    final extent =
        math.max(topLeft.distance, bottomRight.distance) +
        (bottomRight - topLeft).distance;
    if (!gridPainted) paintGrid();
    for (final guide in snapGuides) {
      canvas.save();
      canvas.rotate((guide['rotation'] as num? ?? 0) * math.pi / 180);
      final value = (guide['value'] as num).toDouble();
      if (guide['axis'] == 'x') {
        canvas.drawLine(
          Offset(value, -extent),
          Offset(value, extent),
          guidePaint,
        );
      } else {
        canvas.drawLine(
          Offset(-extent, value),
          Offset(extent, value),
          guidePaint,
        );
      }
      canvas.restore();
    }
    final outline = Paint()
      ..color = selectionColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 / (scale * _cameraScale(camera?.value));
    for (final hull in [...selectionHulls, ...warningHulls]) {
      outline.color = warningHulls.contains(hull)
          ? const Color(0xFFDC2626)
          : selectionColor;
      if (hull.isEmpty) continue;
      final path = Path()..moveTo(hull.first[0], hull.first[1]);
      for (final p in hull.skip(1)) {
        path.lineTo(p[0], p[1]);
      }
      path.close();
      canvas.drawPath(path, outline);
    }
  }

  @override
  bool shouldRepaint(covariant LayoutScenePainter oldDelegate) => true;
}
