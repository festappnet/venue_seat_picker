import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

void main() {
  test('recommended templates let new tables inherit majority typography', () {
    for (final template in VenueLayoutTemplates.recommended) {
      final document = template.create();
      final tables = document.nodes.where((n) => n.kind == 'table').toList();
      if (tables.isEmpty) continue;
      final inherited = resolveNodeAppearance(
        document,
        tableLayout(shape: 'round', count: 6).nodes.first,
      ).label;
      final matches = tables.where((node) {
        final label = resolveNodeAppearance(document, node).label;
        return label['size'] == inherited['size'] &&
            label['fontFamilyId'] == inherited['fontFamilyId'] &&
            label['weight'] == inherited['weight'] &&
            label['italic'] == inherited['italic'];
      });
      expect(
        matches.length,
        greaterThan(tables.length / 2),
        reason: template.id,
      );
    }
  });

  test(
    'majority defaults preserve custom tables and unrelated text exactly',
    () {
      final nodes = [
        for (final size in [33.0, 33.0, 33.0, 41.0, 24.0])
          LayoutNode(
            id: newLayoutId(),
            kind: 'table',
            surface: const {'type': 'rect'},
            style: {
              'label': {'size': size},
            },
            label: 'Table',
          ),
        LayoutNode(
          id: newLayoutId(),
          kind: 'text',
          properties: const {'text': 'Entrance'},
        ),
      ];
      // Three of five tables share the majority; the two exceptions stay custom.
      final before = VenueLayoutDocument(schemaVersion: 2, nodes: nodes);
      final template = LayoutTemplate('test', 'Test', '', 0, 0, () => before);
      final after = template.create();
      for (final node in before.nodes) {
        final updated = after.nodes.singleWhere((n) => n.id == node.id);
        expect(
          resolveNodeAppearance(after, updated).label,
          resolveNodeAppearance(before, node).label,
        );
        final oldWire = node.toJson()..remove('style');
        final newWire = updated.toJson()..remove('style');
        expect(newWire, oldWire);
      }
      expect(
        resolveNodeAppearance(
          after,
          LayoutNode(id: newLayoutId(), kind: 'table'),
        ).label['size'],
        33,
      );
      expect(
        after.nodes
            .where((n) => n.kind == 'table' && n.style['label'] != null)
            .length,
        2,
      );
    },
  );
}
