import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

Map<String, dynamic> item(
  VenueLayoutDocument d,
  String id, {
  Map<String, dynamic> presentation = const {},
  Map<String, dynamic> resources = const {},
}) =>
    (compileScene(d, presentation: presentation, resources: resources)['items']
            as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((i) => i['id'] == id);

void main() {
  test('occupied marker can be hidden without changing status or pending feedback', () {
    final d = tableLayout(shape: 'rect', count: 2);
    final seat = d.nodes.firstWhere((n) => n.kind == 'seat');
    List states(Map<String, dynamic> state) =>
        (compileScene(d, presentation: {seat.id: state})['items'] as List)
            .where((item) => item['id'] == '${seat.id}:state').toList();
    expect(states({'status': 'occupied'}), hasLength(1));
    expect(states({'status': 'occupied', 'stateMarker': 'none'}), isEmpty);
    expect(states({'status': 'occupied', 'stateMarker': 'none', 'pending': true}), hasLength(1));
    expect(item(d, seat.id, presentation: {seat.id: {
      'status': 'occupied', 'stateMarker': 'none', 'fill': '#412673FF',
    }})['fill'], '#412673FF');
  });
  test(
    'optional appearance is immutable and no-style documents stay sparse',
    () {
      final d = tableLayout(shape: 'rect', count: 2);
      final before = d.toJson();
      expect(before.containsKey('appearance'), isFalse);
      expect(VenueLayoutDocument.fromJson(before).toJson(), before);
      final input = <String, dynamic>{
        'table': <String, dynamic>{'fill': '#123456FF'},
      };
      final themed = d.copyWith(appearance: input);
      (input['table'] as Map)['fill'] = '#000000FF';
      expect(themed.appearance['table']['fill'], '#123456FF');
      expect(
        () => themed.appearance['table']['fill'] = '#000000FF',
        throwsUnsupportedError,
      );
      expect(
        VenueLayoutDocument.fromJson(themed.toJson()).toJson(),
        themed.toJson(),
      );
      expect(themed.nodes.first.id, d.nodes.first.id);
      expect(themed.canvas, d.canvas);
    },
  );
  test(
    'global patch replaces existing factory styles and applies to future nodes',
    () {
      var d = couchLayout();
      final before = d.nodes.first;
      d = setLayoutAppearance(d, 'furniture', {
        'fill': '#123456FF',
        'strokeWidth': 4,
        'cornerRadius': 18,
        'opacity': 0.6,
      });
      d = setLayoutAppearance(d, 'furniture', {'stroke': '#AABBCCFF'});
      expect(effectiveNodeProperties(d, before)['fill'], '#123456FF');
      expect(before.properties['fill'], '#DED4F0FF');
      final scene = item(d, before.id);
      expect(scene['fill'], '#123456FF');
      expect(scene['stroke'], '#AABBCCFF');
      expect(scene['strokeWidth'], 4);
      expect(scene['opacity'], 0.6);
      final next = couchLayout(x: 800).nodes.first;
      final added = d.copyWith(nodes: [...d.nodes, next]);
      expect(item(added, next.id)['fill'], '#123456FF');
      expect(added.nodes.first.properties, before.properties);
    },
  );
  test('local override captures effective values and releases inheritance', () {
    var d = tableLayout(shape: 'rect', count: 2);
    final id = d.nodes.first.id;
    d = setLayoutAppearance(d, 'table', {
      'fill': '#123456FF',
      'strokeWidth': 3,
    });
    d = setNodeAppearanceOverride(d, [id], ['fill']);
    expect(d.nodes.first.properties['fill'], '#123456FF');
    d = setLayoutAppearance(d, 'table', {
      'fill': '#ABCDEF88',
      'strokeWidth': 7,
    });
    expect(item(d, id)['fill'], '#123456FF');
    expect(item(d, id)['strokeWidth'], 7);
    d = setNodeAppearanceOverride(d, [id], ['fill'], enabled: false);
    expect(item(d, id)['fill'], '#ABCDEF88');
    expect(
      d.nodes.first.properties.containsKey('appearanceOverrides'),
      isFalse,
    );
  });
  test('corner paths affect tables seats and partial scene identically', () {
    var d = tableLayout(shape: 'rect', count: 2);
    final table = d.nodes.first,
        seat = d.nodes.firstWhere((n) => n.kind == 'seat');
    for (final kind in ['table', 'seat']) {
      d = setLayoutAppearance(d, kind, {
        'cornerRadius': 0,
        'fill': '#123456FF',
      });
    }
    for (final n in [table, seat]) {
      final square = item(d, n.id);
      expect((square['path'] as List).any((c) => c.first == 'Q'), isFalse);
      final rounded = setLayoutAppearance(d, n.kind, {'cornerRadius': 12});
      expect(
        (item(rounded, n.id)['path'] as List).any((c) => c.first == 'Q'),
        isTrue,
      );
      final full = compileScene(rounded)['items'] as List;
      final partial = compileSceneNodes(rounded, {n.id})['items'] as List;
      expect(
        partial,
        full.where((i) => i['id'] == n.id || i['nodeId'] == n.id).toList(),
      );
    }
  });
  test('open geometry stays transparent while polygons inherit fill', () {
    final nodes = [
      for (final shape in ['line', 'polyline', 'arrow', 'polygon'])
        shapeFromPoints(shape, [
          [0, 0],
          [100, 0],
          [100, 80],
        ]),
    ];
    final d = setLayoutAppearance(VenueLayoutDocument(nodes: nodes), 'shape', {
      'fill': '#AABBCCFF',
      'strokeWidth': 5,
    });
    for (final n in nodes) {
      expect(
        item(d, n.id)['fill'],
        n.properties['shape'] == 'polygon' ? '#AABBCCFF' : '#00000000',
      );
      expect(item(d, n.id)['strokeWidth'], 5);
      if (n.properties['shape'] != 'polygon') {
        expect(
          item(
            d,
            n.id,
            presentation: {
              n.id: {'selected': true},
            },
          )['fill'],
          '#00000000',
        );
      }
    }
  });
  test('presentation states win over inherited and local fill', () {
    final d = setLayoutAppearance(couchLayout(), 'seat', {'fill': '#ABCDEF88'});
    final seat = d.nodes.firstWhere((n) => n.kind == 'seat');
    expect(item(d, seat.id)['fill'], '#ABCDEF88');
    expect(
      item(
        d,
        seat.id,
        presentation: {
          seat.id: {'selected': true},
        },
      )['fill'],
      '#267329FF',
    );
    expect(
      item(
        d,
        seat.id,
        presentation: {
          seat.id: {'status': 'occupied'},
        },
      )['fill'],
      '#94A3B8FF',
    );
    expect(
      item(
        d,
        seat.id,
        presentation: {
          seat.id: {'fill': '#112233FF', 'selected': true},
        },
      )['fill'],
      '#112233FF',
    );
  });
  test(
    'text color opacity and stroke resolve without changing font authority',
    () {
      final fonts = Map<String, dynamic>.from(
        jsonDecode(
          File('../../assets/layout_fonts/fixtures.json').readAsStringSync(),
        ),
      );
      final n = LayoutNode(
        id: newLayoutId(),
        kind: 'text',
        width: 180,
        height: 100,
        properties: {'text': 'A', 'color': '#000000FF'},
      );
      final d = setLayoutAppearance(VenueLayoutDocument(nodes: [n]), 'text', {
        'color': '#ABCDEF88',
        'opacity': 0.5,
        'stroke': '#123456FF',
        'strokeWidth': 2,
      });
      final glyph = item(d, '${n.id}:text', resources: fonts);
      expect(glyph['fill'], '#ABCDEF88');
      expect(glyph['opacity'], 0.5);
      expect(glyph['stroke'], '#123456FF');
      expect(glyph['strokeWidth'], 2);
      expect(d.defaultTextStyle['fontId'], 'fixture:sans');
    },
  );
  test(
    'appearance rejects unknown kinds keys unsafe values and malformed overrides',
    () {
      final d = tableLayout(shape: 'rect', count: 2), id = d.nodes.first.id;
      expect(
        () => setLayoutAppearance(d, 'group', {'fill': '#123456FF'}),
        throwsArgumentError,
      );
      for (final patch in [
        {'price': 12},
        {'fill': 'red'},
        {'strokeWidth': -1},
        {'cornerRadius': double.infinity},
        {'opacity': 1.1},
        {'strokeWidth': 1e10},
        {'fontId': 'unapproved'},
      ]) {
        expect(
          () => setLayoutAppearance(d, 'table', patch),
          throwsA(isA<InvalidLayoutDocument>()),
        );
      }
      for (final overrides in [
        1,
        ['fill', 'fill'],
        ['price'],
        [1],
      ]) {
        final malformed = d.copyWith(
          nodes: [
            for (final n in d.nodes)
              n.id == id
                  ? n.copyWith(
                      properties: {
                        ...n.properties,
                        'appearanceOverrides': overrides,
                      },
                    )
                  : n,
          ],
        );
        expect(validateDocument(malformed), isNotEmpty);
      }
      final json = d.toJson();
      json['appearance'] = [];
      expect(
        () => VenueLayoutDocument.fromJson(json),
        throwsA(isA<InvalidLayoutDocument>()),
      );
      expect(
        () => setNodeAppearanceOverride(d, [id], ['size']),
        throwsArgumentError,
      );
    },
  );
  test(
    'local editing respects locks while global style leaves node data intact',
    () {
      final d = tableLayout(shape: 'rect', count: 2), n = d.nodes.first;
      final locked = d.copyWith(
        nodes: [
          for (final node in d.nodes)
            node.id == n.id ? node.copyWith(locked: true) : node,
        ],
      );
      expect(
        () => setNodeAppearanceOverride(locked, [n.id], ['fill']),
        throwsStateError,
      );
      final themed = setLayoutAppearance(locked, 'table', {
        'fill': '#123456FF',
      });
      expect(
        themed.nodes.map((n) => n.toJson()),
        locked.nodes.map((n) => n.toJson()),
      );
      expect(item(themed, n.id)['fill'], '#123456FF');
    },
  );
}
