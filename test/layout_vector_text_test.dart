import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';

void main() {
  testWidgets(
    'view text paints saved glyph outlines without installing a font and stays editable',
    (tester) async {
      const fontId = 'test:never-installed-vector-font';
      final resources = <String, dynamic>{
        'protocol': 1,
        'fonts': {
          fontId: {
            'id': fontId,
            'hash': 'a' * 64,
            'family': 'Never Installed Font',
            'unitsPerEm': 1000,
            'ascent': 800,
            'descent': -200,
            'glyphs': {
              'A': {
                'advance': 800,
                'path': [
                  ['M', 0, 0],
                  ['L', 800, 0],
                  ['L', 0, 800],
                  ['Z'],
                ],
              },
              'B': {
                'advance': 800,
                'path': [
                  ['M', 0, 0],
                  ['L', 800, 0],
                  ['L', 800, 800],
                  ['L', 0, 800],
                  ['Z'],
                ],
              },
            },
          },
        },
      };
      final node = LayoutNode(
        id: newLayoutId(),
        kind: 'table',
        label: 'A',
        x: 50,
        y: 50,
        width: 90,
        height: 90,
        properties: {
          'fontId': fontId,
          'size': 20,
          'fill': '#FFFFFFFF',
          'strokeWidth': 0,
        },
      );
      final c = VenueLayoutController(
        VenueLayoutDocument(
          nodes: [node],
          canvas: {
            'x': 0,
            'y': 0,
            'width': 100,
            'height': 100,
            'fill': '#FFFFFFFF',
          },
        ),
        resources: resources,
      );
      addTearDown(c.dispose);
      Map<String, dynamic> scene() =>
          compileScene(c.document, resources: c.resources);
      final before = scene();
      expect(before['issues'], isEmpty);
      final glyph =
          (before['items'] as List).singleWhere(
                (item) => item['kind'] == 'glyphs',
              )
              as Map;
      expect(glyph['path'], isNotEmpty);
      expect(glyph.containsKey('fontFamily'), isFalse);
      expect(
        (before['items'] as List).any((item) => item['kind'] == 'text'),
        isFalse,
      );
      // The only available font data is this triangle path, never TTF/OTF bytes.
      final recorder = ui.PictureRecorder();
      LayoutScenePainter(
        scene: before,
        resources: c.resources,
        selected: const {},
        scale: 1,
        offset: Offset.zero,
        canvasColor: Colors.white,
        selectionColor: Colors.blue,
      ).paint(Canvas(recorder), const Size(100, 100));
      final image = (await tester.runAsync(
        () => recorder.endRecording().toImage(100, 100),
      ))!;
      final pixels = (await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
      ))!.buffer.asUint8List();
      final ink = [
        for (var i = 0; i < pixels.length; i += 4)
          if (pixels[i] < 100 && pixels[i + 1] < 100 && pixels[i + 2] < 100) i,
      ];
      expect(ink.length, greaterThan(50));
      image.dispose();
      c.updateNode(
        node.copyWith(label: 'B', properties: {...node.properties, 'size': 30}),
      );
      final after = scene();
      expect(after['issues'], isEmpty);
      final changed =
          (after['items'] as List).singleWhere(
                (item) => item['kind'] == 'glyphs',
              )
              as Map;
      expect(changed['path'], isNot(equals(glyph['path'])));
      expect(c.document.nodes.single.label, 'B');
      expect(c.document.nodes.single.properties['fontId'], fontId);
      c.undo();
      expect(c.document.nodes.single.label, 'A');
      expect(scene()['items'], before['items']);
    },
  );
}
