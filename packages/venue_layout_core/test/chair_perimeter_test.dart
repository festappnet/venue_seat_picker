import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

bool fits(VenueLayoutDocument d, LayoutNode n) {
  final b = nodeBounds(d, n), c = d.canvas;
  return b['x']! >= (c['x'] as num) - .001 &&
      b['y']! >= (c['y'] as num) - .001 &&
      b['x']! + b['width']! <= (c['x'] as num) + (c['width'] as num) + .001 &&
      b['y']! + b['height']! <= (c['y'] as num) + (c['height'] as num) + .001;
}

void main() {
  test(
    'six chairs reflow against each of the four walls with stable identities',
    () {
      final d = tableLayout(shape: 'rect', count: 6, x: 250, y: 200).copyWith(
            canvas: {
              'x': 0,
              'y': 0,
              'width': 500,
              'height': 400,
              'fill': '#FFFFFFFF',
            },
          ),
          table = d.nodes.firstWhere((n) => n.kind == 'table');
      for (final (dx, dy, x, y) in [
        (0.0, -500.0, 250, 50),
        (0.0, 500.0, 250, 350),
        (-500.0, 0.0, 90, 200),
        (500.0, 0.0, 410, 200),
      ]) {
        final result = moveLayoutWithinCanvas(d, {table.id}, dx: dx, dy: dy),
            moved = result.nodes.firstWhere((n) => n.id == table.id);
        expect(moved.x, x);
        expect(moved.y, y);
        expect(result.nodes.every((n) => fits(result, n)), isTrue);
        expect(layoutCollisions(result), isEmpty);
        expect(result.nodes.map((n) => n.id), d.nodes.map((n) => n.id));
        expect(result.canvas, d.canvas);
        expect(validateDocument(result), isEmpty);
      }
    },
  );

  test('feasible six chair corner reaches both adjacent walls', () {
    final d = tableLayout(shape: 'rect', count: 6, x: 250, y: 200).copyWith(
          canvas: {
            'x': 0,
            'y': 0,
            'width': 500,
            'height': 400,
            'fill': '#FFFFFFFF',
          },
        ),
        table = d.nodes.firstWhere((n) => n.kind == 'table');
    for (final (dx, dy, x, y) in [
      (-500.0, -500.0, 90, 50),
      (500.0, -500.0, 410, 50),
      (-500.0, 500.0, 90, 350),
      (500.0, 500.0, 410, 350),
    ]) {
      final result = moveLayoutWithinCanvas(d, {table.id}, dx: dx, dy: dy),
          moved = result.nodes.firstWhere((n) => n.id == table.id);
      expect(moved.x, x);
      expect(moved.y, y);
      expect(result.nodes.every((n) => fits(result, n)), isTrue);
      expect(layoutCollisions(result), isEmpty);
    }
  });

  test(
    'actual 190x110 demo table fits every wall and corner by clipping the seat phase',
    () {
      final d =
              tableLayout(
                shape: 'rect',
                count: 6,
                x: 250,
                y: 200,
                width: 190,
                height: 110,
              ).copyWith(
                canvas: {
                  'x': 0,
                  'y': 0,
                  'width': 500,
                  'height': 400,
                  'fill': '#FFFFFFFF',
                },
              ),
          table = d.nodes.firstWhere((n) => n.kind == 'table');
      for (final (dx, dy, x, y) in [
        (-500.0, -500.0, 95, 55),
        (500.0, -500.0, 405, 55),
        (-500.0, 500.0, 95, 345),
        (500.0, 500.0, 405, 345),
        (0.0, -500.0, 250, 55),
        (0.0, 500.0, 250, 345),
        (-500.0, 0.0, 95, 200),
        (500.0, 0.0, 405, 200),
      ]) {
        final result = moveLayoutWithinCanvas(d, {table.id}, dx: dx, dy: dy),
            moved = result.nodes.firstWhere((n) => n.id == table.id);
        expect(moved.x, x);
        expect(moved.y, y);
        expect(result.nodes.every((n) => fits(result, n)), isTrue);
        expect(layoutCollisions(result), isEmpty);
        expect(result.nodes.map((n) => n.id), d.nodes.map((n) => n.id));
        expect(validateDocument(result), isEmpty);
      }
    },
  );

  test(
    'manual chair snaps near a free standard slot without changing bindings',
    () {
      final original = tableLayout(shape: 'rect', count: 4),
          seat = original.nodes.firstWhere((n) => n.kind == 'seat'),
          d = original.copyWith(
            nodes: original.nodes
                .map(
                  (n) => n.id == seat.id
                      ? n.copyWith(
                          x: n.x + 10,
                          y: n.y + 6,
                          properties: {...n.properties, 'manual': true},
                        )
                      : n,
                )
                .toList(),
          ),
          result = snapAttachedChairPosition(d, seat.id),
          snapped = result.nodes.firstWhere((n) => n.id == seat.id);
      expect(snapped.x, seat.x);
      expect(snapped.y, seat.y);
      expect(snapped.id, seat.id);
      expect(snapped.parentId, seat.parentId);
      expect(snapped.properties['manual'], isTrue);
      final attachment = result.attachments.firstWhere(
        (a) => a['seatId'] == seat.id,
      );
      expect(attachment['manual'], isTrue);
      expect(attachment['x'], snapped.x);
      expect(attachment['y'], snapped.y);
      expect(layoutCollisions(result), isEmpty);
      expect(validateDocument(result), isEmpty);
    },
  );

  test(
    'far chair does not teleport and occupied or outside slots do not attract',
    () {
      final original = tableLayout(shape: 'rect', count: 4),
          seats = original.nodes.where((n) => n.kind == 'seat').toList(),
          seat = seats.first,
          other = seats[2];
      VenueLayoutDocument moved(double x, double y) => original.copyWith(
        nodes: original.nodes
            .map((n) => n.id == seat.id ? n.copyWith(x: x, y: y) : n)
            .toList(),
      );
      final far = moved(600, 600);
      expect(snapAttachedChairPosition(far, seat.id), same(far));
      final occupied = moved(other.x, other.y);
      expect(snapAttachedChairPosition(occupied, seat.id), same(occupied));
      final near = moved(seat.x + 10, seat.y + 6);
      expect(
        snapAttachedChairPosition(near, seat.id, tolerance: 1),
        same(near),
      );
      expect(
        () => snapAttachedChairPosition(near, seat.id, tolerance: double.nan),
        throwsArgumentError,
      );
    },
  );
}
