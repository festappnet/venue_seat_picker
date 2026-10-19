import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

VenueLayoutDocument wideTable(String shortEdge) {
  final original = tableLayout(
        shape: 'rect',
        count: 14,
        width: 366,
        height: 128,
        x: 500,
        y: 300,
      ),
      seats = original.nodes.where((n) => n.kind == 'seat').toList(),
      assigned = <String, Map<String, dynamic>>{};
  final next = <LayoutNode>[];
  for (var i = 0; i < seats.length; i++) {
    final seat = seats[i],
        edge = i < 6
            ? 'top'
            : i < 12
            ? 'bottom'
            : shortEdge,
        x = i < 12
            ? ((i % 6) - 2.5) * 57
            : shortEdge == 'left'
            ? -215.0
            : 215.0,
        y = i < 6
            ? -96.0
            : i < 12
            ? 96.0
            : (i - 12.5) * 52,
        rotation = edge == 'top'
            ? 180.0
            : edge == 'bottom'
            ? 0.0
            : edge == 'left'
            ? 90.0
            : 270.0;
    next.add(seat.copyWith(x: x, y: y, rotation: rotation));
    assigned[seat.id] = {'edge': edge, 'x': x, 'y': y, 'rotation': rotation};
  }
  return original.copyWith(
    nodes: [original.nodes.firstWhere((n) => n.kind == 'table'), ...next],
    canvas: {'x': 0, 'y': 0, 'width': 1000, 'height': 600, 'fill': '#FFFFFFFF'},
    attachments: original.attachments
        .map((a) => {...a, ...assigned[a['seatId']]!})
        .toList(),
  );
}

List<LayoutNode> side(VenueLayoutDocument d, String edge) {
  final ids = d.attachments
      .where((a) => a['edge'] == edge)
      .map((a) => a['seatId'])
      .toSet();
  return d.nodes.where((n) => ids.contains(n.id)).toList()..sort(
    (a, b) => (edge == 'top' || edge == 'bottom' ? a.x : a.y).compareTo(
      edge == 'top' || edge == 'bottom' ? b.x : b.y,
    ),
  );
}

void checkRows(VenueLayoutDocument result, String shortEdge) {
  for (final edge in ['top', 'bottom']) {
    final row = side(result, edge);
    expect(row.length, 6);
    expect(row.map((n) => n.x).reduce((a, b) => a + b), closeTo(0, .001));
    for (var i = 1; i < row.length; i++) {
      expect(row[i].x - row[i - 1].x, closeTo(57, .001));
    }
  }
  expect(side(result, shortEdge).map((n) => n.y).toList(), [-26, 26]);
  expect(layoutCollisions(result), isEmpty);
  expect(validateDocument(result), isEmpty);
}

void main() {
  test(
    'blocked short row moves opposite while six-chair long rows remain centered',
    () {
      for (final blocked in ['right', 'left']) {
        final d = wideTable(blocked),
            table = d.nodes.first,
            result = moveLayoutWithinCanvas(d, {
              table.id,
            }, dx: blocked == 'right' ? 1000 : -1000),
            opposite = blocked == 'right' ? 'left' : 'right';
        checkRows(result, opposite);
        expect(side(result, blocked), isEmpty);
        expect(result.nodes.map((n) => n.id), d.nodes.map((n) => n.id));
        for (final edge in ['top', 'bottom']) {
          final before = side(d, edge), after = side(result, edge);
          expect(
            after.map((n) => [n.id, n.x, n.y]).toList(),
            before.map((n) => [n.id, n.x, n.y]).toList(),
          );
        }
        expect(
          reflowTablesAtCanvasEdges(result, {table.id}).toJson(),
          result.toJson(),
        );
      }
    },
  );

  test(
    'already fitting wall draft normalizes uneven rows without another drag',
    () {
      final original = wideTable('left'),
          table = original.nodes.first,
          atWall = transformNodes(original, {table.id}, dx: 317),
          bottom = side(atWall, 'bottom'),
          left = side(atWall, 'left'),
          changes = <String, LayoutNode>{};
      for (var i = 0; i < bottom.length; i++) {
        changes[bottom[i].id] = bottom[i].copyWith(
          x: [-145.0, -88.0, -31.0, 26.0, 83.0, 149.0][i],
        );
      }
      changes[left[0].id] = left[0].copyWith(y: 0);
      changes[left[1].id] = left[1].copyWith(y: 52);
      final messy = atWall.copyWith(
            nodes: atWall.nodes.map((n) => changes[n.id] ?? n).toList(),
          ),
          result = moveLayoutWithinCanvas(messy, {table.id});
      checkRows(result, 'left');
      expect(
        moveLayoutWithinCanvas(result, {table.id}).toJson(),
        result.toJson(),
      );
      expect(result.canvas, messy.canvas);
    },
  );

  test('manual chair inside stays exact while free side rows normalize', () {
    final original = wideTable('right'),
        table = original.nodes.first,
        manual = side(original, 'top').first,
        before = original.copyWith(
          nodes: original.nodes
              .map(
                (n) => n.id == manual.id
                    ? n.copyWith(properties: {...n.properties, 'manual': true})
                    : n,
              )
              .toList(),
        ),
        result = moveLayoutWithinCanvas(before, {table.id}, dx: 1000);
    expect(
      result.nodes.firstWhere((n) => n.id == manual.id).toJson(),
      before.nodes.firstWhere((n) => n.id == manual.id).toJson(),
    );
    checkRows(result, 'left');
  });
}
