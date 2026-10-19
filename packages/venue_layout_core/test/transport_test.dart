import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

List<LayoutNode> seats(VenueLayoutDocument d) =>
    d.nodes.where((n) => n.kind == 'seat').toList();
Map<String, LayoutNode> slots(VenueLayoutDocument d) => {
  for (final n in seats(d)) '${n.properties['slot']}': n,
};
void main() {
  test(
    'bus materializes inventory and meaningful body, doors, driver and windows',
    () {
      final d = busLayout(), root = d.nodes.first;
      expect(seats(d).length, 45);
      expect(d.selectionUnits, isEmpty);
      expect(validateDocument(d), isEmpty);
      expect(layoutCollisions(d), isEmpty);
      expect(
        d.nodes.skip(1).every((n) => n.parentId == root.id && !n.locked),
        isTrue,
      );
      final decorations = d.nodes.where(
        (n) => n.properties['role'] == 'decoration',
      );
      for (final key in [
        'body',
        'windshield',
        'driver-seat',
        'steering',
        'door-0',
        'door-1',
        'window-left-0',
        'aisle-left',
      ]) {
        expect(
          decorations.any((n) => n.properties['slot'] == 'decor:deck:0:$key'),
          isTrue,
          reason: key,
        );
      }
      final seat = seats(d).first, index = LayoutSpatialIndex(d);
      expect(index.hitTest(root.x + seat.x, root.y + seat.y), seat.id);
      expect(index.hitTest(root.x + 160, root.y + 300), root.id);
      expect(VenueLayoutDocument.fromJson(d.toJson()).toJson(), d.toJson());
    },
  );
  test(
    'double deck uses independent counts and same physical deck envelope',
    () {
      final d = busLayout(rows: 7, upperRows: 11, decks: 2);
      expect(seats(d).where((n) => n.properties['deck'] == 0).length, 33);
      expect(seats(d).where((n) => n.properties['deck'] == 1).length, 49);
      final bodies = d.nodes
          .where((n) => '${n.properties['slot']}'.endsWith(':body'))
          .toList();
      expect(bodies.length, 2);
      expect(bodies.first.width, bodies.last.width);
      expect(bodies.first.height, bodies.last.height);
      expect(bodies.last.x, greaterThan(bodies.first.x + bodies.first.width));
      expect(busLayoutParameters(d, d.nodes.first.id)['upperRows'], 11);
      expect(validateDocument(d), isEmpty);
      expect(layoutCollisions(d), isEmpty);
    },
  );
  test(
    'updates retain side-stable IDs, manual pose, labels, style and canvas',
    () {
      final original = busLayout(rows: 3, decks: 2, upperRows: 4),
          root = original.nodes.first;
      final first = seats(original).first;
      final d = original.copyWith(
        nodes: [
          for (final n in original.nodes)
            if (n.id == first.id)
              n.copyWith(
                x: n.x + 4,
                properties: {
                  ...n.properties,
                  'manual': true,
                  'fill': '#123456FF',
                },
              )
            else
              n,
        ],
      );
      final grown = updateBusLayout(d, root.id, rows: 5, upperRows: 6);
      for (final entry in slots(d).entries)
        expect(slots(grown)[entry.key]?.id, entry.value.id);
      expect(grown.nodes.firstWhere((n) => n.id == first.id).x, first.x + 4);
      expect(
        grown.nodes.firstWhere((n) => n.id == first.id).properties['fill'],
        '#123456FF',
      );
      expect(
        seats(grown).map((n) => n.label).toSet().length,
        seats(grown).length,
      );
      final smaller = updateBusLayout(grown, root.id, left: 1);
      expect(
        slots(smaller)['deck:0:row:0:right:0']!.id,
        slots(d)['deck:0:row:0:right:0']!.id,
      );
      expect(smaller.canvas, d.canvas);
    },
  );
  test(
    'protected, manual or locked seats reject destructive changes atomically',
    () {
      final d = busLayout(rows: 3, decks: 2, upperRows: 4),
          root = d.nodes.first;
      final upper = seats(d).firstWhere((n) => n.properties['deck'] == 1);
      expect(
        () =>
            updateBusLayout(d, root.id, decks: 1, protectedSeatIds: {upper.id}),
        throwsA(isA<TransportLayoutRejected>()),
      );
      final last = slots(d)['deck:0:row:2:left:0']!;
      final manual = d.copyWith(
        nodes: [
          for (final n in d.nodes)
            if (n.id == last.id)
              n.copyWith(properties: {...n.properties, 'manual': true})
            else
              n,
        ],
      );
      expect(
        () => updateBusLayout(manual, root.id, rows: 2),
        throwsA(isA<TransportLayoutRejected>()),
      );
      final locked = d.copyWith(
        nodes: [
          for (final n in d.nodes)
            if (n.id == last.id) n.copyWith(locked: true) else n,
        ],
      );
      expect(() => updateBusLayout(locked, root.id, rows: 5), throwsStateError);
      expect(seats(d).length, 38);
    },
  );
  test(
    'compartments are actual facing rows with corridor and stable side slots',
    () {
      final d = compartmentLayout(), root = d.nodes.first;
      expect(seats(d).length, 24);
      expect(validateDocument(d), isEmpty);
      expect(layoutCollisions(d), isEmpty);
      final grown = updateCompartmentLayout(
        d,
        root.id,
        compartments: 5,
        seats: 8,
      );
      expect(seats(grown).length, 40);
      for (final entry in slots(d).entries) {
        expect(slots(grown)[entry.key]?.id, entry.value.id);
        expect(slots(grown)[entry.key]?.rotation, entry.value.rotation);
      }
      expect(
        () => updateCompartmentLayout(
          grown,
          root.id,
          compartments: 4,
          protectedSeatIds: {slots(grown)['comp:4:row:0:seat:0']!.id},
        ),
        throwsA(isA<TransportLayoutRejected>()),
      );
    },
  );
  test('legacy bus slots migrate without replacing reservation identities', () {
    final root = LayoutNode(
      id: newLayoutId(),
      kind: 'group',
      properties: {'assembly': 'bus'},
    );
    final d = VenueLayoutDocument(
      nodes: [
        root,
        for (var r = 0; r < 2; r++)
          for (var s = 0; s < 4; s++)
            LayoutNode(
              id: newLayoutId(),
              kind: 'seat',
              parentId: root.id,
              x: s * 56.0 + (s >= 2 ? 80 : 0),
              y: r * 64.0,
              width: 40,
              height: 40,
              label: '${r * 4 + s + 1}',
              properties: {'slot': '$r:$s'},
            ),
      ],
    );
    final next = updateBusLayout(d, root.id, rows: 3);
    expect(slots(next)['deck:0:row:1:right:0']!.id, slots(d)['1:2']!.id);
    expect(seats(next).length, 12);
  });
  test(
    'canonical full and partial transport scenes agree with validated fonts',
    () {
      final resources =
          jsonDecode(
                File(
                  '../../assets/layout_fonts/fixtures.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      for (final d in [busLayout(decks: 2), compartmentLayout()]) {
        final scene = compileScene(d, resources: resources);
        expect(scene['issues'], isEmpty);
        final ids = d.nodes.take(12).map((n) => n.id).toSet();
        expect(
          compileSceneNodes(d, ids, resources: resources)['items'],
          (scene['items'] as List)
              .where((i) => ids.contains(i['nodeId'] ?? i['id']))
              .toList(),
        );
      }
    },
  );
  test(
    'invalid transport metadata and counts fail strictly, generic decoration survives',
    () {
      expect(() => busLayout(decks: 3), throwsRangeError);
      expect(() => busLayout(left: 4), throwsRangeError);
      expect(() => busLayout(rear: 7), throwsRangeError);
      expect(() => compartmentLayout(seats: 13), throwsRangeError);
      final d = busLayout(), root = d.nodes.first;
      expect(
        validateDocument(
          d.copyWith(
            nodes: [
              root.copyWith(properties: {...root.properties, 'upperRear': 7}),
              ...d.nodes.skip(1),
            ],
          ),
        ),
        isNotEmpty,
      );
      expect(
        validateDocument(
          VenueLayoutDocument(
            nodes: [
              LayoutNode(
                id: newLayoutId(),
                kind: 'shape',
                properties: {'role': 'decoration'},
              ),
            ],
          ),
        ),
        isEmpty,
      );
    },
  );
}
