import 'dart:convert';
import 'dart:io';
import 'package:venue_layout_core/venue_layout_core.dart';

void main(List<String> args) {
  const group = '10000000-0000-4000-8000-000000000001',
      seat = '10000000-0000-4000-8000-000000000002',
      text = '10000000-0000-4000-8000-000000000003';
  final d = VenueLayoutDocument(
    nodes: [
      LayoutNode(
        id: '10000000-0000-4000-8000-000000000004',
        kind: 'shape',
        x: 450,
        y: 340,
        width: 160,
        height: 80,
        rotation: 17,
        properties: {
          'shape': 'ellipse',
          'fill': '#00000000',
          'stroke': '#E11D48FF',
          'strokeWidth': 3,
          'dash': [12, 8],
        },
      ),
      LayoutNode(id: group, kind: 'group', x: 300, y: 250, rotation: 37),
      LayoutNode(
        id: seat,
        kind: 'seat',
        parentId: group,
        x: 90,
        y: 10,
        rotation: 22,
        label: '12',
      ),
      LayoutNode(
        id: text,
        kind: 'text',
        x: 200,
        y: 120,
        width: 400,
        height: 100,
        properties: {
          'text': 'Příliš žluťoučký kůň',
          'fontId': 'fixture:serif',
          'bold': true,
          'italic': true,
          'align': 'center',
        },
      ),
    ],
  );
  final resources = Map<String, dynamic>.from(
    jsonDecode(
      File('../../assets/layout_fonts/fixtures.json').readAsStringSync(),
    ),
  );
  final m = worldMatrix(d, d.nodes[2]);
  final output = {
    'document': d.toJson(),
    'resources': resources,
    'presentation': {
      seat: {'selected': true, 'pending': true},
    },
    'hitPoint': [m[4], m[5]],
    'expectedHit': hitTest(d, m[4], m[5]),
    'scene': compileScene(
      d,
      resources: resources,
      presentation: {
        seat: {'selected': true, 'pending': true},
      },
    ),
    'interpolated': interpolateLayout(
      d,
      transformNodes(d, {group}, dx: 120, rotation: 50),
      .4,
    ).toJson(),
  };
  if (args.isEmpty) {
    stdout.write(jsonEncode(output));
  } else {
    File(args.first).writeAsStringSync(jsonEncode(output));
  }
}
