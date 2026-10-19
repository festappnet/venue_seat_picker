import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:venue_layout_core/venue_layout_core.dart';
import 'layout_scene_surface.dart';

/// Display-only catalogue preview. Uses the canonical painter without creating
/// a separate interactive canvas, camera, gesture handlers or focus target.
class LayoutPaletteThumbnail extends StatefulWidget {
  const LayoutPaletteThumbnail({
    super.key,
    required this.document,
    required this.resources,
    required this.kind,
  });
  final VenueLayoutDocument document;
  final Map<String, dynamic> resources;
  final String kind;
  @override
  State<LayoutPaletteThumbnail> createState() => _ThumbnailState();
}

class _ThumbnailState extends State<LayoutPaletteThumbnail> {
  VenueLayoutDocument? _document;
  Map<String, dynamic>? _resources;
  late Map<String, dynamic> _scene;
  late Rect _bounds;

  @override
  Widget build(BuildContext context) {
    if (!identical(_document, widget.document) ||
        !identical(_resources, widget.resources)) {
      final b = selectionBounds(
        widget.document,
        widget.document.nodes.map((n) => n.id).toSet(),
      );
      _bounds = Rect.fromLTWH(b['x']!, b['y']!, b['width']!, b['height']!);
      _scene = compileScene(widget.document, resources: widget.resources);
      _document = widget.document;
      _resources = widget.resources;
    }
    final extent = switch (widget.kind) {
      'Seat' => const Size(32, 32),
      'Round table' => const Size(56, 56),
      'Couch' => const Size(66, 44),
      'Bar' => const Size(82, 46),
      'Standing' || 'Rectangle' || 'Ellipse' || 'Polygon' => const Size(62, 40),
      'Line' || 'Arrow' || 'Polyline' => const Size(74, 32),
      'Text' => const Size(54, 34),
      _ => const Size(82, 54),
    };
    return ExcludeSemantics(
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox.fromSize(
            size: extent,
            child: LayoutBuilder(
              builder: (context, constraints) {
                const padding = 3.0;
                final width = constraints.maxWidth,
                    height = constraints.maxHeight;
                final scale = math.min(
                  (width - padding * 2) / math.max(1, _bounds.width),
                  (height - padding * 2) / math.max(1, _bounds.height),
                );
                return RepaintBoundary(
                  child: CustomPaint(
                    size: extent,
                    painter: LayoutScenePainter(
                      scene: _scene,
                      resources: widget.resources,
                      selected: const {},
                      scale: scale,
                      offset: Offset(
                        (width - _bounds.width * scale) / 2 -
                            _bounds.left * scale,
                        (height - _bounds.height * scale) / 2 -
                            _bounds.top * scale,
                      ),
                      canvasColor: Colors.transparent,
                      selectionColor: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
