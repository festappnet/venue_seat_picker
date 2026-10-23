import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

void main() {
  for (final manualOnNode in [false, true]) {
    test(
      'reshape resets manual chair poses (node flag: $manualOnNode) and preserves reservations',
      () {
        final original = tableLayout(
          shape: 'ellipse',
          count: 6,
          width: 500,
          height: 360,
        );
        final table = original.nodes.firstWhere((n) => n.kind == 'table');
        final chair = original.nodes.firstWhere((n) => n.kind == 'seat');
        final before = original.copyWith(
          nodes: [
            for (final n in original.nodes)
              n.id == chair.id
                  ? n.copyWith(
                      x: 250,
                      y: 180,
                      rotation: 37,
                      properties: {
                        ...n.properties,
                        if (manualOnNode) 'manual': true,
                        'manualRotation': true,
                        'fill': '#123456FF',
                      },
                    )
                  : n,
          ],
          attachments: [
            for (final a in original.attachments)
              a['seatId'] == chair.id ? {...a, 'manual': true} : a,
          ],
        );
        final snapshot = before.toJson();
        expect(layoutCollisions(before), isEmpty);
        final reserved = before.nodes
            .where((n) => n.kind == 'seat')
            .map((n) => n.id)
            .toSet();
        final after = reshapeTableSurface(
          before,
          table.id,
          'rectangle',
          protectedSeatIds: reserved,
        );
        final moved = after.nodes.firstWhere((n) => n.id == chair.id);
        expect(
          after.nodes.map((n) => n.id).toSet(),
          before.nodes.map((n) => n.id).toSet(),
        );
        expect(moved.properties['manual'], isNot(true));
        expect(moved.properties['manualRotation'], isNot(true));
        expect(moved.properties['fill'], '#123456FF');
        expect(moved.label, chair.label);
        expect([moved.x, moved.y, moved.rotation], isNot([250, 180, 37]));
        expect(after.attachments.every((a) => a['manual'] != true), isTrue);
        expect(validateDocument(after), isEmpty);
        expect(layoutCollisions(after), isEmpty);
        expect(before.toJson(), snapshot);
        expect(layoutCollisions(reflowTable(after, table.id, 6)), isEmpty);

        final locked = before.copyWith(
          nodes: [
            for (final n in before.nodes)
              n.id == chair.id ? n.copyWith(locked: true) : n,
          ],
        );
        final lockedSnapshot = locked.toJson();
        expect(
          () => reshapeTableSurface(locked, table.id, 'rectangle'),
          throwsStateError,
        );
        expect(locked.toJson(), lockedSnapshot);
      },
    );
  }
  test(
    'new bars are editable seatless surfaces; legacy explicit stools remain readable',
    () {
      final d = barLayout();
      expect(d.nodes.length, 1);
      expect(isBarNode(d.nodes.single), true);
      expect(d.nodes.single.properties['shape'], 'polygon');
      expect(validateDocument(d), isEmpty);
      expect(VenueLayoutDocument.fromJson(d.toJson()).toJson(), d.toJson());
      expect(
        barLayout(count: 4).nodes.where((n) => n.kind == 'seat').length,
        4,
      );
    },
  );
  test(
    'centerline sketch builds an actual concave U surface, not a bounding rectangle',
    () {
      final node = sketchSurface(
        [
          [200, 500],
          [200, 200],
          [600, 200],
          [600, 500],
        ],
        breadth: 80,
        bar: true,
      );
      final d = VenueLayoutDocument(nodes: [node]);
      expect(validateDocument(d), isEmpty);
      expect(hitTest(d, 200, 400), node.id);
      expect(hitTest(d, 400, 200), node.id);
      expect(hitTest(d, 400, 400), isNull);
      expect(
        () => sketchSurface([
          [0, 0],
          [100, 0],
          [0, 0],
        ]),
        throwsStateError,
      );
    },
  );
  test(
    'pulling a surface edge creates a wing and preserves the original identity',
    () {
      final d = barLayout(), n = d.nodes.single;
      final changed = extendTableSurface(d, n.id, 1, n.width / 2 + 130, 0);
      expect(changed.nodes.single.id, n.id);
      expect(changed.nodes.single.width, n.width + 130);
      expect((changed.nodes.single.properties['points'] as List).length, 8);
      expect(validateDocument(changed), isEmpty);
      expect(d.nodes.single.width, 280);
    },
  );
  test(
    'concave table seating stays outside the surface and never overlaps',
    () {
      final d = tableLayout(
        shape: 'rect',
        count: 6,
        width: 500,
        height: 360,
        x: 700,
        y: 500,
      );
      for (final shape in ['L', 'U']) {
        final next = reshapeTableSurface(d, d.nodes.first.id, shape);
        expect(validateDocument(next), isEmpty);
        expect(layoutCollisions(next), isEmpty);
        expect(
          next.nodes.where((n) => n.kind == 'seat').map((n) => n.id).toSet(),
          d.nodes.where((n) => n.kind == 'seat').map((n) => n.id).toSet(),
        );
        final root = next.nodes.firstWhere((n) => n.kind == 'table');
        final expanded = extendTableSurface(
          next,
          root.id,
          0,
          0,
          -root.height / 2 - 100,
        );
        expect(validateDocument(expanded), isEmpty);
        expect(layoutCollisions(expanded), isEmpty);
      }
    },
  );
  test(
    'surface edits never remove protected reservations or change immutable input',
    () {
      var d = tableLayout(shape: 'rect', count: 6, width: 500, height: 360);
      d = reshapeTableSurface(d, d.nodes.first.id, 'rectangle');
      final before = d.toJson(), id = d.nodes.first.id;
      final reserved = d.nodes
          .where((n) => n.kind == 'seat')
          .map((n) => n.id)
          .toSet();
      expect(
        () => resizeNode(d, id, 20, 20, protectedSeatIds: reserved),
        throwsA(isA<TableResizeRejected>()),
      );
      expect(d.toJson(), before);
    },
  );
  test(
    'transport material has a different silhouette and preserves selection states',
    () {
      final d = withLayoutMaterialFamily(busLayout(rows: 2), 'transit');
      expect(validateDocument(d), isEmpty);
      final seat = d.nodes.firstWhere((n) => n.kind == 'seat');
      final scene = compileScene(
        d,
        presentation: {
          seat.id: {'selected': true},
        },
      );
      final item = (scene['items'] as List).firstWhere(
        (i) => i['id'] == seat.id,
      );
      expect(item['fill'], '#267329FF');
      expect(
        (scene['items'] as List).any((i) => i['id'] == '${seat.id}:seat-style'),
        true,
      );
      expect(
        d.nodes.where(
          (n) => '${n.properties['slot']}'.contains('travel-direction'),
        ),
        isNotEmpty,
      );
    },
  );
}
