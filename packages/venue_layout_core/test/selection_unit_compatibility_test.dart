import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

void main() {
  for (final explicitNull in [false, true]) {
    test(
      'v1 ${explicitNull ? 'null' : 'omitted'} unit kind canonicalizes to atomic',
      () {
        final a = LayoutNode(id: newLayoutId(), kind: 'seat', x: 200, y: 200),
            b = LayoutNode(id: newLayoutId(), kind: 'seat', x: 260, y: 200);
        final source = <String, dynamic>{
          'id': newLayoutId(),
          'nodeIds': [a.id, b.id],
          if (explicitNull) 'kind': null,
        };
        final document = VenueLayoutDocument(
          nodes: [a, b],
          selectionUnits: [source],
        );
        expect(document.selectionUnits.single['kind'], 'atomic');
        expect(source.containsKey('kind'), explicitNull);
        expect(validateDocument(document), isEmpty);
        final json = document.toJson();
        final encodedUnit = (json['selectionUnits'] as List).single as Map;
        if (explicitNull) {
          encodedUnit['kind'] = null;
        } else {
          encodedUnit.remove('kind');
        }
        final imported = VenueLayoutDocument.fromJson(json);
        expect(imported.selectionUnits.single['kind'], 'atomic');
        expect(
          (imported.toJson()['selectionUnits'] as List).single['kind'],
          'atomic',
        );
        expect(imported.copyWith().selectionUnits.single['kind'], 'atomic');
        expect(cloneLayout(imported).selectionUnits.single['kind'], 'atomic');
        expect(
          () => imported.selectionUnits.single['kind'] = 'partial',
          throwsUnsupportedError,
        );
      },
    );
  }
  test(
    'explicit unknown unit kind remains a typed rejection with original payload',
    () {
      final seat = LayoutNode(id: newLayoutId(), kind: 'seat');
      final document = VenueLayoutDocument(
        nodes: [seat],
        selectionUnits: [
          {
            'id': newLayoutId(),
            'nodeIds': [seat.id],
            'kind': 'partial',
          },
        ],
      );
      expect(
        validateDocument(
          document,
        ).any((i) => i.reason == 'invalid_selection_unit_kind'),
        isTrue,
      );
      final json = VenueLayoutDocument(nodes: [seat]).toJson();
      json['selectionUnits'] = [
        {
          'id': newLayoutId(),
          'nodeIds': [seat.id],
          'kind': 'partial',
        },
      ];
      expect(
        () => VenueLayoutDocument.fromJson(json),
        throwsA(
          isA<InvalidLayoutDocument>().having(
            (e) => (e.original['selectionUnits'] as List).single['kind'],
            'original kind',
            'partial',
          ),
        ),
      );
    },
  );
}
