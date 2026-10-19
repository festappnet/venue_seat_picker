import 'geometry.dart';
import 'model.dart';

/// One module is a compact square table with one seat on each side.
const double tableSurfaceModuleSize = 100;

/// Counters have a shallower footprint than a four-seat table module.
const double barSurfaceModuleSize = 60;

/// Transient authoring brush. Only its compact polygon outline is persisted.
/// Shared cell edges cancel incrementally; preview cost follows the boundary.
class GridSurfaceBrush {
  GridSurfaceBrush({
    this.step = tableSurfaceModuleSize,
    this.diameter = 1,
    this.clip,
    this.originX = 0,
    this.originY = 0,
  });
  final double step, originX, originY;
  final int diameter;
  final Map<String, dynamic>? clip;
  final _cells = <(int, int)>{};
  final _edges = <(int, int), Set<(int, int)>>{};
  (int, int)? _last;
  int get cellCount => _cells.length;
  bool paint(double x, double y) {
    if (!originX.isFinite ||
        !originY.isFinite ||
        !x.isFinite ||
        !y.isFinite ||
        x.abs() > layoutLimits['geometryAbsMax']! ||
        y.abs() > layoutLimits['geometryAbsMax']! ||
        step <= 0 ||
        !step.isFinite ||
        diameter < 1 ||
        diameter > 32)
      throw ArgumentError('Invalid brush');
    if (clip != null) {
      x = x.clamp(
        (clip!['x'] as num).toDouble(),
        ((clip!['x'] as num) + (clip!['width'] as num)).toDouble(),
      );
      y = y.clamp(
        (clip!['y'] as num).toDouble(),
        ((clip!['y'] as num) + (clip!['height'] as num)).toDouble(),
      );
    }
    final end = (
      ((x - originX) / step).floor(),
      ((y - originY) / step).floor(),
    );
    var at = _last ?? end;
    var changed = false;
    void stamp((int, int) p) {
      final half = diameter ~/ 2;
      for (var yy = p.$2 - half; yy < p.$2 - half + diameter; yy++)
        for (var xx = p.$1 - half; xx < p.$1 - half + diameter; xx++) {
          if (clip != null &&
              (originX + xx * step < (clip!['x'] as num) ||
                  originY + yy * step < (clip!['y'] as num) ||
                  originX + (xx + 1) * step >
                      (clip!['x'] as num) + (clip!['width'] as num) ||
                  originY + (yy + 1) * step >
                      (clip!['y'] as num) + (clip!['height'] as num)))
            continue;
          final cell = (xx, yy);
          if (_cells.contains(cell)) continue;
          if (_cells.length >= 16384)
            throw StateError('Surface brush limit reached.');
          _cells.add(cell);
          changed = true;
          edge((xx, yy), (xx + 1, yy));
          edge((xx + 1, yy), (xx + 1, yy + 1));
          edge((xx + 1, yy + 1), (xx, yy + 1));
          edge((xx, yy + 1), (xx, yy));
        }
    }

    stamp(at);
    final dx = (end.$1 - at.$1).abs(),
        dy = (end.$2 - at.$2).abs(),
        sx = at.$1 < end.$1 ? 1 : -1,
        sy = at.$2 < end.$2 ? 1 : -1;
    var error = dx - dy;
    while (at != end) {
      final twice = error * 2;
      if (twice > -dy) {
        error -= dy;
        at = (at.$1 + sx, at.$2);
        stamp(at);
      }
      if (twice < dx) {
        error += dx;
        at = (at.$1, at.$2 + sy);
        stamp(at);
      }
    }
    _last = end;
    return changed;
  }

  void edge((int, int) a, (int, int) b) {
    if (_edges[b]?.remove(a) == true) {
      if (_edges[b]!.isEmpty) _edges.remove(b);
    } else {
      (_edges[a] ??= {}).add(b);
    }
  }

  LayoutNode node({required String id, bool bar = false}) {
    if (_edges.isEmpty) throw StateError('Paint inside the canvas.');
    final remaining = {
      for (final e in _edges.entries) e.key: {...e.value},
    };
    final rings = <List<List<double>>>[];
    while (remaining.isNotEmpty) {
      final start = remaining.keys.first;
      var at = start;
      (int, int)? previous;
      final vertices = <(int, int)>[];
      do {
        vertices.add(at);
        final nexts = remaining[at];
        if (nexts == null || nexts.isEmpty)
          throw StateError('Invalid painted outline');
        final candidates = nexts.toList();
        if (previous != null && candidates.length > 1) {
          final dx = at.$1 - previous.$1, dy = at.$2 - previous.$2;
          int turn((int, int) b) {
            final nx = b.$1 - at.$1, ny = b.$2 - at.$2;
            final cross = dx * ny - dy * nx;
            return cross > 0
                ? 0
                : dx * nx + dy * ny > 0
                ? 1
                : cross < 0
                ? 2
                : 3;
          }

          candidates.sort((a, b) => turn(a).compareTo(turn(b)));
        }
        final next = candidates.first;
        nexts.remove(next);
        if (nexts.isEmpty) remaining.remove(at);
        previous = at;
        at = next;
      } while (at != start && vertices.length <= 65536);
      if (at != start) throw StateError('Invalid painted outline');
      final ring = <List<double>>[];
      for (var i = 0; i < vertices.length; i++) {
        final p = vertices[(i + vertices.length - 1) % vertices.length],
            a = vertices[i],
            b = vertices[(i + 1) % vertices.length];
        if ((a.$1 - p.$1) * (b.$2 - a.$2) - (a.$2 - p.$2) * (b.$1 - a.$1) != 0)
          ring.add([originX + a.$1 * step, originY + a.$2 * step]);
      }
      if (ring.length < 3 || polygonSelfIntersects(ring))
        throw StateError('The surface outline cannot cross itself.');
      rings.add(ring);
    }
    double area(List<List<double>> ring) {
      var a = 0.0;
      for (var i = 0; i < ring.length; i++) {
        final p = ring[i], q = ring[(i + 1) % ring.length];
        a += p[0] * q[1] - q[0] * p[1];
      }
      return a;
    }

    rings.sort((a, b) => area(b).abs().compareTo(area(a).abs()));
    if (rings.skip(1).any((r) => area(r) > 0))
      throw StateError('Paint a connected surface.');
    if (rings.fold<int>(0, (s, r) => s + r.length) >
        layoutLimits['verticesMax']!)
      throw StateError('Path vertex limit reached');
    final base = shapeFromPoints(
      'polygon',
      rings.first,
      id: id,
      properties: {
        'fill': '#E2E8F0FF',
        'stroke': '#475569FF',
        'strokeWidth': 1,
        if (bar) ...{'furniture': 'bar', 'guestSide': 'bottom'},
      },
    );
    return base.copyWith(
      kind: 'table',
      properties: {
        ...base.properties,
        if (rings.length > 1)
          'holes': [
            for (final ring in rings.skip(1))
              [
                for (final p in ring)
                  [quantize(p[0] - base.x), quantize(p[1] - base.y)],
              ],
          ],
      },
    );
  }
}
