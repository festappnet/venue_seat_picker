import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

void main() {
  test('authored plan labels remain visible at whole-plan fit', () {
    final resources =
        jsonDecode(
              File(
                '../../assets/layout_fonts/fixtures.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final nodes = [
      LayoutNode(
        id: newLayoutId(),
        kind: 'text',
        x: 200,
        y: 200,
        width: 400,
        height: 60,
        properties: {'text': 'Stage', 'size': 24},
      ),
      LayoutNode(
        id: newLayoutId(),
        kind: 'table',
        x: 600,
        y: 400,
        width: 190,
        height: 110,
        label: '21',
      ),
    ];
    final scene = compileScene(
      VenueLayoutDocument(nodes: nodes),
      resources: resources,
    );
    final visible = cullScene(scene, {
      'x': 0,
      'y': 0,
      'width': 2400,
      'height': 1800,
    }, zoom: .2);
    expect(
      visible
          .where((item) => item['kind'] == 'glyphs')
          .map((item) => item['label']),
      containsAll(['Stage', '21']),
    );
  });
  test(
    'table labels default to screen orientation; source labels can follow the object',
    () {
      final resources =
          jsonDecode(
                File(
                  '../../assets/layout_fonts/fixtures.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final node = LayoutNode(
        id: newLayoutId(),
        kind: 'table',
        x: 300,
        y: 400,
        width: 700,
        height: 100,
        rotation: 270,
        label: 'Stůl 16',
        properties: {'shape': 'rect', 'size': 60},
      );
      final plain = VenueLayoutDocument(nodes: [node]);
      final doc = plain.copyWith(
        nodes: [
          node.copyWith(
            properties: {...node.properties, 'labelOrientation': 'object'},
          ),
        ],
      );
      expect(validateDocument(doc), isEmpty);
      expect(VenueLayoutDocument.fromJson(doc.toJson()).toJson(), doc.toJson());
      Map label(VenueLayoutDocument d) =>
          (compileScene(d, resources: resources)['items'] as List).firstWhere(
                (item) => item['id'] == '${node.id}:text',
              )
              as Map;
      expect(label(plain)['matrix'], [1, 0, 0, 1, 300, 400]);
      expect(label(doc)['matrix'], worldMatrix(doc, doc.nodes.single));
      expect(
        compileSceneNodes(doc, {node.id}, resources: resources)['items'],
        (compileScene(doc, resources: resources)['items'] as List)
            .where((i) => i['id'] == node.id || i['nodeId'] == node.id)
            .toList(),
      );
      final bad = doc.copyWith(
        nodes: [
          node.copyWith(
            properties: {...node.properties, 'labelOrientation': 'random'},
          ),
        ],
      );
      expect(
        validateDocument(
          bad,
        ).any((i) => i.reason == 'invalid_label_orientation'),
        isTrue,
      );
    },
  );
}
