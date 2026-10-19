import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/layout_scene_cache.dart';

void main() {
  test(
    'canvas resizing retains object paths and only rebuilds canvas decoration',
    () {
      final doc = tableLayout(shape: 'roundedRect').copyWith(
        canvas: {
          'x': 0,
          'y': 0,
          'width': 2400,
          'height': 1800,
          'fill': '#FFFFFFFF',
          'floorStyle': 'wood',
        },
      );
      final cache = LayoutSceneCache();
      final first = cache.update(doc);
      final items = {
        for (final item in first['items'] as List) item['id']: item,
      };
      final resized = resizeCanvas(doc, 2800, 2100);
      final next = cache.update(resized);
      expect(next, compileScene(resized));
      for (final item in next['items'] as List) {
        if (item['kind'] != 'floor' && item['id'] != 'background') {
          expect(
            item,
            same(items[item['id']]),
            reason:
                'Dragging a canvas edge must not recompile unchanged table/seat paths',
          );
        }
      }
      expect(
        (next['items'] as List).firstWhere((item) => item['kind'] == 'floor'),
        isNot(same(items['canvas:floor'])),
      );
    },
  );

  VenueLayoutDocument fixture() {
    final table = tableLayout(shape: 'roundedRect');
    return table.copyWith(
      nodes: [
        ...table.nodes,
        LayoutNode(id: newLayoutId(), kind: 'shape', x: 1000),
      ],
      appearance: {
        'seat': {'seatStyle': 'wood', 'fill': '#FFEEDDFF'},
      },
    );
  }

  test('geometry patches match full scenes and retain unaffected items', () {
    var document = fixture();
    final table = document.nodes.first;
    final stable = document.nodes.last.id;
    final cache = LayoutSceneCache();
    final first = cache.update(document);
    final item = (first['items'] as List).firstWhere(
      (dynamic i) => (i['nodeId'] ?? i['id']) == stable,
    );
    document = document.copyWith(
      nodes: [
        for (final n in document.nodes)
          if (n.id == table.id) n.copyWith(x: n.x + 45, rotation: 35) else n,
      ],
    );
    final moved = cache.update(document);
    expect(moved, compileScene(document));
    expect(
      (moved['items'] as List).firstWhere(
        (dynamic i) => (i['nodeId'] ?? i['id']) == stable,
      ),
      same(item),
    );
    document = reflowTable(document, table.id, 7);
    expect(cache.update(document), compileScene(document));
  });

  test(
    'presentation and geometry share a patch without losing seat decorations',
    () {
      var document = fixture();
      final cache = LayoutSceneCache();
      final seat = document.nodes.firstWhere((n) => n.kind == 'seat');
      cache.update(document);
      final presentation = <String, dynamic>{
        seat.id: {'selected': true},
      };
      document = document.copyWith(
        nodes: [
          for (final n in document.nodes)
            n.id == seat.id ? n.copyWith(rotation: 45) : n,
        ],
      );
      expect(
        cache.update(document, presentation: presentation),
        compileScene(document, presentation: presentation),
      );
      expect(cache.update(document), compileScene(document));
    },
  );

  test(
    'global, structure, layer and resource changes match full compilation',
    () {
      var document = fixture();
      final cache = LayoutSceneCache();
      cache.update(document);
      final variants = <VenueLayoutDocument>[
        setLayoutAppearance(document, 'seat', {'cornerRadius': 12}),
        document.copyWith(canvas: {...document.canvas, 'fill': '#123456FF'}),
        document.copyWith(
          nodes: [for (final n in document.nodes) n.copyWith(z: n.z + 1)],
        ),
        document.copyWith(
          nodes: document.nodes.take(document.nodes.length - 1).toList(),
        ),
        groupNodes(document, {document.nodes.first.id, document.nodes.last.id}),
      ];
      for (final next in variants) {
        document = next;
        expect(cache.update(document), compileScene(document));
      }
      final resources = <String, dynamic>{};
      expect(
        cache.update(document, resources: resources),
        compileScene(document, resources: resources),
      );
    },
  );

  test(
    'invalid snapshots clear all items and recovery restores full scene',
    () {
      final valid = fixture();
      final cache = LayoutSceneCache();
      cache.update(valid);
      final invalid = valid.copyWith(
        nodes: [...valid.nodes, valid.nodes.first],
      );
      expect(cache.update(invalid), compileScene(invalid));
      expect(cache.update(valid), compileScene(valid));
    },
  );

  test(
    'font issues and newly appearing glyph paths preserve full scene order',
    () {
      final base = fixture();
      final cache = LayoutSceneCache();
      cache.update(base);
      final labeled = base.copyWith(
        nodes: [
          base.nodes.first.copyWith(label: 'Missing font'),
          ...base.nodes.skip(1),
        ],
      );
      expect(cache.update(labeled), compileScene(labeled));
      expect(cache.update(base), compileScene(base));
    },
  );
}
