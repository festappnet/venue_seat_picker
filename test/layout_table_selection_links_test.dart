import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_table_selection.dart';

void main() {
  test(
    'only connected seats get short boundary links, including rotated and round tables',
    () {
      for (final shape in ['rect', 'circle']) {
        var doc = tableLayout(
          shape: shape,
          count: 6,
          x: 400,
          y: 400,
          width: 200,
          height: shape == 'circle' ? 200 : 120,
        );
        final table = doc.nodes.firstWhere((n) => n.kind == 'table');
        doc = doc.copyWith(
          nodes: [
            for (final n in doc.nodes)
              n.id == table.id ? n.copyWith(rotation: 37) : n,
            LayoutNode(id: newLayoutId(), kind: 'seat', x: 400, y: 200),
          ],
        );
        final before = doc.toJson(), links = tableSeatLinks(doc, {table.id});
        expect(links, hasLength(6));
        expect(
          links.map((l) => l.seatId).toSet(),
          doc.nodes
              .where((n) => n.parentId == table.id)
              .map((n) => n.id)
              .toSet(),
        );
        for (final link in links) {
          final p = transformPoint(
            inverseMatrix(worldMatrix(doc, doc.nodes.first)),
            link.tablePoint.dx,
            link.tablePoint.dy,
          );
          if (shape == 'rect') {
            expect(
              (p[0].abs() - 100).abs() < .001 || (p[1].abs() - 60).abs() < .001,
              isTrue,
            );
          } else {
            expect(Offset(p[0], p[1]).distance, closeTo(100, .2));
          }
          expect((link.seatPoint - link.tablePoint).distance, lessThan(45));
        }
        expect(tableSeatLinks(doc, {doc.nodes.last.id}), isEmpty);
        expect(tableSeatLinks(doc, {}), isEmpty);
        expect(doc.toJson(), before);
      }
    },
  );
  testWidgets(
    'linked chair highlights leave selection and all eight handles on the tabletop',
    (tester) async {
      final doc = tableLayout(
        shape: 'rect',
        count: 6,
        x: 400,
        y: 300,
        width: 200,
        height: 120,
      );
      final table = doc.nodes.firstWhere((n) => n.kind == 'table');
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 900,
            height: 700,
            child: LayoutSceneSurface(
              document: doc,
              selected: {table.id},
              onHandleStart: (_, _) {},
              animate: false,
            ),
          ),
        ),
      );
      final painter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<LayoutScenePainter>()
          .single;
      expect(painter.selected, {table.id});
      expect(painter.seatLinks, hasLength(6));
      final bounds = boundsOfPoints(painter.selectionHulls.single);
      expect(bounds, {'x': 300.0, 'y': 240.0, 'width': 200.0, 'height': 120.0});
      for (final direction in [
        '',
        ' n',
        ' e',
        ' s',
        ' w',
        ' nw',
        ' ne',
        ' sw',
      ]) {
        expect(find.byTooltip('Resize$direction handle'), findsOneWidget);
      }
      expect(find.byTooltip('Rotate handle'), findsOneWidget);
    },
  );
}
