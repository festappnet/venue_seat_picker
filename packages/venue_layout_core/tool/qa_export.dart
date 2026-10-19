import 'dart:convert';
import 'dart:io';
import 'package:venue_layout_core/venue_layout_core.dart';

void main(List<String> args) {
  final output = Directory(args.isEmpty ? '/tmp/venue-layout-qa' : args.first)
    ..createSync(recursive: true);
  final root = File.fromUri(Platform.script).parent.parent.parent.parent;
  final resources = Map<String, dynamic>.from(
    jsonDecode(
      File('${root.path}/assets/layout_fonts/fixtures.json').readAsStringSync(),
    ),
  );
  resources['assets'] = {
    'crop-quadrants': {
      'data':
          'iVBORw0KGgoAAAANSUhEUgAAAGQAAABQCAYAAADvCdDvAAAA40lEQVR4nO3RMRGAMADAwMph7syMYpSgBAdFBrneD28gGWvOtYPjPrcw/g5piCFphsQYEmNIjCExhsQYEmNIjCExhsQYEmNIjCExhsQYEmNIjCExhsQYEmNIjCExhsQYEmNIjCExhsQYEmNIjCExhsQYEmNIjCExhsQYEmNIjCExhsSMeb1rB+s5tmBIjCExhsQYEmNIjCExhsQYEmNIjCExhsQYEmNIjCExhsQYEmNIjCExhsQYEmNIjCExhsQYEmNIjCExhsQYEmNIjCExhsQYEmNIjCExhsQYEmNIjCExhsR8IRXr9VHGlAsAAAAASUVORK5CYII=',
      'mime': 'image/png',
      'width': 100,
      'height': 80,
      'size': 284,
    },
  };
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
          'text': 'Příliš žluťoučký kůň\nÁÉÍÓÚ čřž',
          'fontId': 'fixture:serif',
          'size': 24,
          'bold': true,
          'italic': true,
          'align': 'center',
        },
      ),
    ],
  );
  final presentation = <String, dynamic>{
        seat: {'selected': true, 'pending': true},
      },
      m = worldMatrix(d, d.nodes[2]),
      target = transformNodes(d, {group}, dx: 120, rotation: 50);
  final motion = [
    for (final t in [0.0, 1 / 3, 2 / 3, 1.0])
      {
        't': t,
        'document': interpolateLayout(d, target, t).toJson(),
        'scene': compileScene(
          interpolateLayout(d, target, t),
          resources: resources,
          presentation: presentation,
        ),
      },
  ];
  final corpus = <Map<String, dynamic>>[];
  for (final count in [500, 5000, 20000]) {
    var layout = rowLayout(
      rows: (count / 50).ceil(),
      seatsPerRow: 50,
      x: 100,
      y: 100,
    );
    layout = fitCanvas(layout, padding: 40);
    // Semantic deterministic fixture IDs, independent of production UUID allocation.
    final ids = {
      for (var i = 0; i < layout.nodes.length; i++)
        layout.nodes[i].id:
            '20000000-0000-4000-8000-${i.toRadixString(16).padLeft(12, '0')}',
    };
    final json = layout.toJson();
    dynamic remap(dynamic v) => v is String
        ? ids[v] ?? v
        : v is List
        ? v.map(remap).toList()
        : v is Map
        ? v.map((k, v) => MapEntry(k, remap(v)))
        : v;
    layout = VenueLayoutDocument.fromJson(
      Map<String, dynamic>.from(remap(json)),
    );
    final documentJson = jsonEncode(layout.toJson()),
        watch = Stopwatch()..start(),
        scene = compileScene(layout, resources: resources);
    watch.stop();
    final sceneJson = jsonEncode(scene);
    File(
      '${output.path}/corpus-$count.document.json',
    ).writeAsStringSync(documentJson);
    File(
      '${output.path}/corpus-$count.scene.json',
    ).writeAsStringSync(sceneJson);
    corpus.add({
      'count': count,
      'documentFile': 'corpus-$count.document.json',
      'sceneFile': 'corpus-$count.scene.json',
      'sceneMs': watch.elapsedMicroseconds / 1000,
      'bytes': utf8.encode(documentJson).length,
      'sceneBytes': utf8.encode(sceneJson).length,
      'sceneItems': (scene['items'] as List).length,
      'issues': scene['issues'],
    });
  }
  final cropDocument = VenueLayoutDocument(
    canvas: {'x': 0, 'y': 0, 'width': 400, 'height': 300, 'fill': '#FFFFFFFF'},
    background: {
      'assetRef': 'crop-quadrants',
      'hash':
          '623f3779d56f23b2f7498643cec8cb1a7976abd7b0df640903b92616a501fbb9',
      'width': 100,
      'height': 80,
      'x': 200,
      'y': 150,
      'scale': 2,
      'rotation': 0,
      'crop': {'x': .1, 'y': .2, 'width': .6, 'height': .4},
    },
  );
  final report = {
    'protocol': 1,
    'resources': resources,
    'fixtures': [
      {
        'name': 'crop-preserves-registration',
        'document': cropDocument.toJson(),
        'toDocument': cropDocument.toJson(),
        'presentation': <String, dynamic>{},
        'scene': compileScene(cropDocument, resources: resources),
        'hits': <Map<String, dynamic>>[],
        'motion': [
          for (final t in [0.0, 1 / 3, 2 / 3, 1.0])
            {
              't': t,
              'document': cropDocument.toJson(),
              'scene': compileScene(cropDocument, resources: resources),
            },
        ],
      },
      {
        'name': 'rotated-czech-glyphs',
        'document': d.toJson(),
        'toDocument': target.toJson(),
        'presentation': presentation,
        'scene': compileScene(
          d,
          resources: resources,
          presentation: presentation,
        ),
        'hits': [
          {'x': m[4], 'y': m[5], 'id': seat},
          {'x': -100, 'y': -100, 'id': null},
        ],
        'motion': motion,
      },
    ],
    'corpus': corpus,
  };
  File('${output.path}/report.json').writeAsStringSync(jsonEncode(report));
  File(
    '${output.path}/fixture.report.json',
  ).writeAsStringSync(jsonEncode(report));
  stdout.writeln('QA fixtures exported to ${output.path}/report.json');
}
