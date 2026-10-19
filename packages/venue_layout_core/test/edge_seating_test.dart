import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

VenueLayoutDocument hall({int count = 4, String shape = 'rect'}) {
  final d = tableLayout(
    shape: shape,
    count: count,
    x: 250,
    y: 50,
    width: 180,
    height: 100,
  );
  return d.copyWith(canvas: {...d.canvas, 'width': 500, 'height': 400});
}

bool inside(VenueLayoutDocument d, LayoutNode n) {
  final b = nodeBounds(d, n), c = d.canvas;
  return b['x']! >= (c['x'] as num) - 1e-6 &&
      b['y']! >= (c['y'] as num) - 1e-6 &&
      b['x']! + b['width']! <= (c['x'] as num) + (c['width'] as num) + 1e-6 &&
      b['y']! + b['height']! <= (c['y'] as num) + (c['height'] as num) + 1e-6;
}

void main() {
  test(
    'bounded movement lets feasible table body meet wall without losing chairs',
    () {
      final baseline = hall();
      final table = baseline.nodes.firstWhere((n) => n.kind == 'table');
      final middle = transformNodes(baseline, {table.id}, dy: 150);
      final result = moveLayoutWithinCanvas(middle, {table.id}, dy: -500);
      expect(result.nodes.firstWhere((n) => n.id == table.id).y, 50);
      expect(result.nodes.every((n) => inside(result, n)), isTrue);
      expect(result.nodes.map((n) => n.id), middle.nodes.map((n) => n.id));
      expect(result.canvas, middle.canvas);
      expect(layoutCollisions(result), isEmpty);
    },
  );

  test('six chair table uses free end slots and reaches the wall', () {
    final baseline = hall(count: 6);
    final table = baseline.nodes.firstWhere((n) => n.kind == 'table');
    final middle = transformNodes(baseline, {table.id}, dy: 150);
    final result = moveLayoutWithinCanvas(middle, {table.id}, dy: -500);
    expect(result.nodes.firstWhere((n) => n.id == table.id).y, 50);
    expect(result.nodes.every((n) => inside(result, n)), isTrue);
    expect(layoutCollisions(result), isEmpty);
    expect(result.nodes.map((n) => n.id), middle.nodes.map((n) => n.id));
    expect(
      moveLayoutWithinCanvas(middle, {table.id}, dy: -510).toJson(),
      result.toJson(),
    );
  });

  test(
    'bounded movement handles rotated nesting, multiple objects and corners',
    () {
      final group = LayoutNode(
        id: newLayoutId(),
        kind: 'group',
        x: 200,
        y: 200,
        rotation: 37,
      );
      final child = LayoutNode(
        id: newLayoutId(),
        kind: 'shape',
        parentId: group.id,
        x: 60,
        y: 0,
        width: 100,
        height: 50,
      );
      final other = LayoutNode(
        id: newLayoutId(),
        kind: 'shape',
        x: 100,
        y: 100,
        width: 80,
        height: 60,
      );
      final before = hall(count: 0).copyWith(nodes: [group, child, other]);
      final result = moveLayoutWithinCanvas(
        before,
        {group.id, other.id},
        dx: 900,
        dy: -900,
      );
      expect(
        result.nodes
            .where((n) => n.kind != 'group')
            .every((n) => inside(result, n)),
        isTrue,
      );
      final a = worldMatrix(before, child), b = worldMatrix(result, child);
      final movedOther = result.nodes.firstWhere((n) => n.id == other.id);
      expect(b[4] - a[4], closeTo(movedOther.x - other.x, .001));
      expect(b[5] - a[5], closeTo(movedOther.y - other.y, .001));
      expect(result.canvas, before.canvas);
    },
  );

  test(
    'manual chair yields at canvas edge but an obstructing table blocks placement',
    () {
      final original = hall();
      final table = original.nodes.firstWhere((n) => n.kind == 'table');
      final first = original.nodes.firstWhere((n) => n.kind == 'seat');
      final manual = original.copyWith(
        nodes: original.nodes
            .map(
              (n) => n.id == first.id
                  ? n.copyWith(properties: {...n.properties, 'manual': true})
                  : n,
            )
            .toList(),
      );
      final middle = transformNodes(manual, {table.id}, dy: 150);
      final obstacle = LayoutNode(
        id: newLayoutId(),
        kind: 'table',
        x: 250,
        y: 102,
        width: 180,
        height: 100,
      );
      final blocked = middle.copyWith(nodes: [...middle.nodes, obstacle]);
      expect(
        moveLayoutWithinCanvas(blocked, {table.id}, dy: -500),
        same(blocked),
      );
      final result = moveLayoutWithinCanvas(middle, {table.id}, dy: -500);
      expect(result.nodes.firstWhere((n) => n.id == table.id).y, 50);
      expect(result.nodes.every((n) => inside(result, n)), isTrue);
      expect(layoutCollisions(result), isEmpty);
      final relocated = result.nodes.firstWhere((n) => n.id == first.id);
      expect(relocated.properties['manual'], true);
      expect(relocated.parentId, table.id);
      expect(relocated.y, isNot(first.y));
      expect(result.attachments, hasLength(original.attachments.length));
    },
  );

  test(
    'bounded insertion recovers origin fragment and preserves locked behavior',
    () {
      final item = LayoutNode(
        id: newLayoutId(),
        kind: 'shape',
        x: -100,
        y: -100,
        width: 40,
        height: 40,
      );
      final before = hall(count: 0).copyWith(nodes: [item]);
      final result = moveLayoutWithinCanvas(
        before,
        {item.id},
        dx: 900,
        dy: 900,
      );
      expect(result.nodes.single.x, 480);
      expect(result.nodes.single.y, 380);
      expect(inside(result, result.nodes.single), isTrue);
      final locked = before.copyWith(nodes: [item.copyWith(locked: true)]);
      expect(
        () => moveLayoutWithinCanvas(locked, {item.id}, dx: 100),
        throwsStateError,
      );
    },
  );

  test('wall reflow preserves chairs, slots, metadata and fixed canvas', () {
    final source = hall();
    final before = source.copyWith(
      nodes: source.nodes
          .map(
            (n) => n.kind == 'seat'
                ? n.copyWith(properties: {...n.properties, 'fill': '#123456FF'})
                : n,
          )
          .toList(),
    );
    final table = before.nodes.firstWhere((n) => n.kind == 'table');
    final after = reflowTablesAtCanvasEdges(before, {table.id});
    expect(after.canvas, before.canvas);
    expect(after.nodes.map((n) => n.id), before.nodes.map((n) => n.id));
    for (final seat in after.nodes.where((n) => n.kind == 'seat')) {
      expect(inside(after, seat), isTrue);
      final original = before.nodes.firstWhere((n) => n.id == seat.id);
      expect(seat.parentId, original.parentId);
      expect(seat.properties, original.properties);
      final a = after.attachments.firstWhere((a) => a['seatId'] == seat.id);
      expect(a['targetId'], table.id);
      expect(a['x'], seat.x);
      expect(a['y'], seat.y);
    }
    expect(layoutCollisions(after), isEmpty);
    expect(validateDocument(after), isEmpty);
    expect(
      reflowTablesAtCanvasEdges(after, {table.id}).toJson(),
      after.toJson(),
    );
    expect(
      reflowTablesAtCanvasEdges(before, {table.id}).toJson(),
      after.toJson(),
    );
  });

  test('world canvas constraints work through rotated nested parents', () {
    final original = hall();
    final table = original.nodes.firstWhere((n) => n.kind == 'table');
    final group = LayoutNode(
      id: newLayoutId(),
      kind: 'group',
      x: 50,
      y: 250,
      rotation: 90,
    );
    final nested = original.copyWith(
      nodes: [
        group,
        ...original.nodes.map(
          (n) =>
              n.id == table.id ? n.copyWith(parentId: group.id, x: 0, y: 0) : n,
        ),
      ],
    );
    final result = reflowTablesAtCanvasEdges(nested, {table.id});
    expect(
      result.nodes
          .where((n) => n.kind == 'seat')
          .every((n) => inside(result, n)),
      isTrue,
    );
    expect(layoutCollisions(result), isEmpty);
    expect(validateDocument(result), isEmpty);
  });

  test('round table reflows chairs away from the wall', () {
    final before = hall(count: 3, shape: 'round');
    final table = before.nodes.firstWhere((n) => n.kind == 'table');
    final result = reflowTablesAtCanvasEdges(before, {table.id});
    expect(
      result.nodes
          .where((n) => n.kind == 'seat')
          .every((n) => inside(result, n)),
      isTrue,
    );
    expect(layoutCollisions(result), isEmpty);
    expect(validateDocument(result), isEmpty);
  });

  test('returning to open space restores the gesture baseline placements', () {
    final baseline = hall();
    final table = baseline.nodes.firstWhere((n) => n.kind == 'table');
    final edge = reflowTablesAtCanvasEdges(baseline, {table.id});
    expect(edge.toJson(), isNot(baseline.toJson()));
    final middle = transformNodes(baseline, {table.id}, dy: 150);
    final result = reflowTablesAtCanvasEdges(middle, {table.id});
    expect(result.toJson(), middle.toJson());
  });

  test(
    'locked chairs stay exact, outside manual chairs reflow and impossible chairs remain',
    () {
      final original = hall(count: 8);
      final seats = original.nodes.where((n) => n.kind == 'seat').toList();
      final before = original.copyWith(
        nodes: original.nodes
            .map(
              (n) => n.id == seats.first.id
                  ? n.copyWith(locked: true)
                  : n.id == seats[1].id
                  ? n.copyWith(properties: {...n.properties, 'manual': true})
                  : n,
            )
            .toList(),
      );
      final table = before.nodes.firstWhere((n) => n.kind == 'table');
      final result = reflowTablesAtCanvasEdges(before, {table.id});
      expect(result.nodes.map((n) => n.id), before.nodes.map((n) => n.id));
      for (final id in [seats[0].id]) {
        expect(
          result.nodes.firstWhere((n) => n.id == id).toJson(),
          before.nodes.firstWhere((n) => n.id == id).toJson(),
        );
        expect(
          result.attachments.firstWhere((a) => a['seatId'] == id),
          before.attachments.firstWhere((a) => a['seatId'] == id),
        );
      }
      final manual = result.nodes.firstWhere((n) => n.id == seats[1].id);
      expect(manual.properties['manual'], true);
      expect(manual.parentId, table.id);
      expect(inside(result, manual), isTrue);
      expect(
        result.nodes
            .where((n) => n.kind == 'seat')
            .any((n) => !inside(result, n)),
        isTrue,
      );
      expect(result.canvas, before.canvas);
      expect(validateDocument(result), isEmpty);
    },
  );

  test(
    'manual chair inside stays exact when other chairs need wall reflow',
    () {
      final original = hall();
      final table = original.nodes.firstWhere((n) => n.kind == 'table');
      final seat = original.nodes.firstWhere(
        (n) => n.kind == 'seat' && n.y > 0,
      );
      final before = original.copyWith(
        nodes: original.nodes
            .map(
              (n) => n.id == seat.id
                  ? n.copyWith(properties: {...n.properties, 'manual': true})
                  : n,
            )
            .toList(),
      );
      final result = reflowTablesAtCanvasEdges(before, {table.id});
      expect(
        result.nodes.firstWhere((n) => n.id == seat.id).toJson(),
        before.nodes.firstWhere((n) => n.id == seat.id).toJson(),
      );
      expect(result.nodes.every((n) => inside(result, n)), isTrue);
    },
  );

  test(
    'neighbouring table stays fixed while obstructed chairs find free perimeter slots',
    () {
      final before = hall();
      final table = before.nodes.firstWhere((n) => n.kind == 'table');
      final clear = reflowTablesAtCanvasEdges(before, {table.id});
      final obstacle = LayoutNode(
        id: newLayoutId(),
        kind: 'table',
        x: 250,
        y: 120,
        width: 180,
        height: 100,
      );
      final overlap = reflowTablesAtCanvasEdges(
        before.copyWith(nodes: [...before.nodes, obstacle]),
        {table.id},
      );
      expect(overlap.nodes.first.toJson(), clear.nodes.first.toJson());
      expect(overlap.nodes.last.toJson(), obstacle.toJson());
      expect(overlap.nodes.map((n) => n.id), [
        ...before.nodes.map((n) => n.id),
        obstacle.id,
      ]);
      final seats = before.nodes
          .where((n) => n.kind == 'seat')
          .map((n) => n.id)
          .toSet();
      expect(
        layoutCollisions(overlap).where((pair) => pair.any(seats.contains)),
        isEmpty,
      );
    },
  );
}
