import 'dart:math';
import 'geometry.dart';
import 'model.dart';
import 'node_outline.dart';

final _tableLabelOffsets = Expando<List<double>>();

/// Place irregular table labels in the broadest filled part of the rendered
/// tabletop, excluding holes and concavities. Shared by glyphs and native text.
List<double> tableLabelOffset(LayoutNode node) {
  if (node.kind != 'table' ||
      surfaceGeometryProperties(node)['shape'] != 'polygon') {
    return const [0, 0];
  }
  return _tableLabelOffsets[node] ??= _interiorOffset(
    nodeOutlineContours(node),
  );
}

List<double> _interiorOffset(List<List<List<double>>> rings) {
  if (rings.isEmpty) return const [0, 0];
  final bounds = boundsOfPoints(rings.first);
  final width = bounds['width']!, height = bounds['height']!;
  if (width <= 0 || height <= 0) return const [0, 0];
  double clearance(double x, double y) {
    var inside = false, distanceSquared = double.infinity;
    for (final ring in rings) {
      if (pointInPolygon(ring, x, y)) inside = !inside;
      for (var i = 0; i < ring.length; i++) {
        final a = ring[i], b = ring[(i + 1) % ring.length];
        final dx = b[0] - a[0], dy = b[1] - a[1];
        final lengthSquared = dx * dx + dy * dy;
        final t = lengthSquared == 0
            ? 0.0
            : (((x - a[0]) * dx + (y - a[1]) * dy) / lengthSquared).clamp(
                0.0,
                1.0,
              );
        final ox = x - a[0] - t * dx, oy = y - a[1] - t * dy;
        distanceSquared = min(distanceSquared, ox * ox + oy * oy);
      }
    }
    return (inside ? 1 : -1) * sqrt(distanceSquared);
  }

  ({double x, double y, double h, double distance, double bound}) cell(
    double x,
    double y,
    double h,
  ) {
    final d = clearance(x, y);
    return (x: x, y: y, h: h, distance: d, bound: d + h * sqrt2);
  }

  var best = cell(0, 0, 0);
  final pending = [
    cell(
      bounds['x']! + width / 2,
      bounds['y']! + height / 2,
      max(width, height) / 2,
    ),
  ];
  // Best-first subdivision bounds placement error independently of zoom.
  const precision = .5;
  while (pending.isNotEmpty) {
    final current = pending.removeLast();
    if (current.distance > best.distance ||
        (current.distance == best.distance &&
            current.x * current.x + current.y * current.y <
                best.x * best.x + best.y * best.y)) {
      best = current;
    }
    if (current.bound - best.distance <= precision) continue;
    final h = current.h / 2;
    for (final dx in [-h, h]) {
      for (final dy in [-h, h]) {
        final next = cell(current.x + dx, current.y + dy, h);
        var low = 0, high = pending.length;
        while (low < high) {
          final mid = (low + high) ~/ 2;
          if (pending[mid].bound < next.bound) {
            low = mid + 1;
          } else {
            high = mid;
          }
        }
        pending.insert(low, next);
      }
    }
  }
  return [quantize(best.x), quantize(best.y)];
}
