import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

VenueLayoutDocument drag(
  VenueLayoutDocument d,
  String id,
  double width,
  String handle,
) => resizeNode(
  d,
  id,
  width,
  d.nodes.firstWhere((n) => n.id == id).height,
  handle: handle,
);

void main() {
  for (final handle in ['n', 'ne', 'e', 'se', 's', 'sw', 'w', 'nw']) {
    test('$handle keeps the opposite anchor under a rotated parent', () {
      final source = tableLayout(
        shape: 'rect',
        count: 6,
        width: 420,
        height: 200,
        x: 0,
        y: 0,
      );
      final root = source.nodes.first;
      final parent = LayoutNode(
        id: newLayoutId(),
        kind: 'group',
        x: 1000,
        y: 800,
        rotation: 23,
      );
      final before = source.copyWith(
        nodes: [
          parent,
          for (final n in source.nodes)
            n.id == root.id ? n.copyWith(parentId: parent.id, rotation: 17) : n,
        ],
      );
      final sx = handle.contains('w') ? -1 : (handle.contains('e') ? 1 : 0);
      final sy = handle.contains('n') ? -1 : (handle.contains('s') ? 1 : 0);
      final anchor = transformPoint(
        worldMatrices(before)[root.id]!,
        -sx * root.width / 2,
        -sy * root.height / 2,
      );
      final after = resizeNode(
        before,
        root.id,
        sx == 0 ? root.width : 300,
        sy == 0 ? root.height : 160,
        handle: handle,
      );
      final resized = after.nodes.firstWhere((n) => n.id == root.id);
      final actual = transformPoint(
        worldMatrices(after)[root.id]!,
        -sx * resized.width / 2,
        -sy * resized.height / 2,
      );
      expect(actual[0], closeTo(anchor[0], .002));
      expect(actual[1], closeTo(anchor[1], .002));
      expect(validateDocument(after), isEmpty);
      expect(layoutCollisions(after), isEmpty);
    });
  }
  test(
    'handle resize releases manual chair positions and retains protected IDs',
    () {
      final source = tableLayout(
        shape: 'rect',
        count: 8,
        width: 420,
        height: 120,
        x: 400,
        y: 300,
      );
      final id = source.nodes.first.id;
      final before = source.copyWith(
        nodes: [
          for (final n in source.nodes)
            n.kind == 'seat'
                ? n.copyWith(
                    properties: {
                      ...n.properties,
                      'manual': true,
                      'manualRotation': true,
                    },
                  )
                : n,
        ],
        attachments: [
          for (final a in source.attachments) {...a, 'manual': true},
        ],
      );
      final protected = before.nodes
          .where((n) => n.kind == 'seat')
          .map((n) => n.id)
          .toSet();
      final snapshot = before.toJson();
      final after = resizeNode(
        before,
        id,
        300,
        120,
        handle: 'w',
        protectedSeatIds: protected,
      );
      expect(
        after.nodes.map((n) => n.id).toSet(),
        before.nodes.map((n) => n.id).toSet(),
      );
      expect(
        after.nodes
            .where((n) => n.kind == 'seat')
            .every(
              (n) =>
                  n.properties['manual'] != true &&
                  n.properties['manualRotation'] != true,
            ),
        isTrue,
      );
      expect(after.attachments.every((a) => a['manual'] != true), isTrue);
      expect(layoutCollisions(after), isEmpty);
      expect(
        () => resizeNode(
          before,
          id,
          20,
          20,
          handle: 'w',
          protectedSeatIds: protected,
        ),
        throwsA(isA<TableResizeRejected>()),
      );
      expect(before.toJson(), snapshot);
    },
  );
  test('locked descendants reject handle resize atomically', () {
    final source = tableLayout(
      shape: 'rect',
      count: 6,
      width: 420,
      height: 200,
    );
    final id = source.nodes.first.id;
    final locked = source.copyWith(
      nodes: [
        for (final n in source.nodes)
          n.kind == 'seat' ? n.copyWith(locked: true) : n,
      ],
    );
    final snapshot = locked.toJson();
    expect(
      () => resizeNode(locked, id, 300, 200, handle: 'w'),
      throwsStateError,
    );
    expect(locked.toJson(), snapshot);
  });
  test('unobstructed edge reflow reuses a settled immutable document', () {
    final original = tableLayout(
      shape: 'rect',
      count: 8,
      width: 420,
      height: 120,
      x: 400,
      y: 300,
    );
    final id = original.nodes.first.id;
    final settled = reflowTablesAtCanvasEdges(original, {id});
    expect(
      identical(reflowTablesAtCanvasEdges(settled, {id}), settled),
      isTrue,
    );
    expect(layoutCollisions(settled), isEmpty);
  });
  test('west resize stops at canvas without moving the opposite edge', () {
    final before = tableLayout(
      shape: 'rect',
      width: 420,
      height: 120,
      x: 230,
      y: 300,
      count: 8,
    );
    final id = before.nodes.first.id;
    final after = drag(before, id, 600, 'w');
    final table = after.nodes.firstWhere((n) => n.id == id);
    expect(table.x + table.width / 2, closeTo(440, .002));
    expect(nodeBounds(after, table)['x'], greaterThanOrEqualTo(-.002));
    expect(layoutCollisions(after), isEmpty);
    expect(
      after.nodes.map((n) => n.id).toSet(),
      before.nodes.map((n) => n.id).toSet(),
    );
  });
  for (final handle in ['w', 'e']) {
    test('$handle shrink keeps the opposite edge fixed', () {
      final before = tableLayout(
        shape: 'rect',
        width: 420,
        height: 120,
        x: 400,
        y: 300,
        count: 8,
      );
      final id = before.nodes.first.id;
      final after = drag(before, id, 300, handle);
      final table = after.nodes.firstWhere((n) => n.id == id);
      final sign = handle == 'w' ? -1 : 1;
      expect(
        table.x - table.width * sign / 2,
        closeTo(400 - 420 * sign / 2, .002),
      );
      expect(layoutCollisions(after), isEmpty);
    });
  }
}
