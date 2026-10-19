import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';

void main() {
  for (final bar in [false, true]) {
    for (final wrapped in [false, true]) {
      testWidgets(
        '${bar ? 'bar' : 'table'} ${wrapped ? 'wrapper' : 'direct'} diagonal edge drag remains orthogonal',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(1440, 1000));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          var document = bar
              ? barLayout(count: 0, x: 600, y: 400, width: 300, height: 120)
              : tableLayout(
                  shape: 'rect',
                  count: 4,
                  x: 600,
                  y: 400,
                  width: 300,
                  height: 200,
                );
          final originalTable = document.nodes.firstWhere(
            (n) => n.kind == 'table',
          );
          final wrapper = LayoutNode(id: newLayoutId(), kind: 'group');
          final table = originalTable.copyWith(
            parentId: wrapped ? wrapper.id : null,
            rotation: 25,
            properties: {
              ...originalTable.properties,
              'shape': 'polygon',
              'points': surfacePresetPoints('rectangle', 300, bar ? 120 : 200),
            },
          );
          document = document.copyWith(
            nodes: [
              if (wrapped) wrapper,
              for (final n in document.nodes) n.id == table.id ? table : n,
            ],
          );
          final c = VenueLayoutController(document)
            ..select({wrapped ? wrapper.id : table.id});
          addTearDown(c.dispose);
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: VenueLayoutEditor(controller: c, showGallery: false),
              ),
            ),
          );
          await tester.pumpAndSettle();
          LayoutSceneSurface surface() => tester.widget<LayoutSceneSurface>(
            find.byWidgetPredicate(
              (w) => w is LayoutSceneSurface && w.onDrop != null,
            ),
          );
          final hull = localHull(table);
          final a = hull[1], b = hull[2];
          final midpoint = Offset((a[0] + b[0]) / 2, (a[1] + b[1]) / 2);
          Offset world(Offset local) {
            final p = transformPoint(
              worldMatrix(document, table),
              local.dx,
              local.dy,
            );
            return Offset(p[0], p[1]);
          }

          // Both coordinates change: only the outward normal should affect shape.
          surface().onHandleStart!('Extend edge 1 cell 0', world(midpoint));
          surface().onDragUpdate!(world(midpoint + Offset(bar ? 60 : 100, 35)));
          surface().onDragEnd!();
          await tester.pump();
          expect(c.error, isNull);
          expect(c.selection, {wrapped ? wrapper.id : table.id});
          final changed = c.document.nodes.firstWhere((n) => n.id == table.id);
          expect(changed.width, table.width + (bar ? 60 : 100));
          final points = localHull(changed);
          for (var i = 0; i < points.length; i++) {
            final p = points[i], q = points[(i + 1) % points.length];
            expect(
              (p[0] - q[0]).abs() < .001 || (p[1] - q[1]).abs() < .001,
              isTrue,
            );
          }
          final seats = c.document.nodes
              .where((n) => n.kind == 'seat')
              .toList();
          final priorSeats = document.nodes
              .where((n) => n.kind == 'seat')
              .toList();
          expect(
            seats.map((n) => n.id).toSet(),
            priorSeats.map((n) => n.id).toSet(),
          );
          for (final seat in seats) {
            final prior = priorSeats.firstWhere((n) => n.id == seat.id);
            expect(seat.width, prior.width);
            expect(seat.height, prior.height);
          }
          expect(validateDocument(c.document), isEmpty);
          c.undo();
          expect(c.document.toJson(), document.toJson());
          expect(c.canUndo, isFalse);
          await tester.pump();
          surface().onHandleStart!('Extend edge 1 cell 0', world(midpoint));
          surface().onDragUpdate!(
            world(midpoint + Offset(bar ? -60 : -100, 35)),
          );
          surface().onDragEnd!();
          await tester.pump();
          expect(c.error, isNull);
          final inset = localHull(
            c.document.nodes.firstWhere((n) => n.id == table.id),
          );
          expect(inset.length, greaterThan(hull.length));
          for (var i = 0; i < inset.length; i++) {
            final p = inset[i], q = inset[(i + 1) % inset.length];
            expect(
              (p[0] - q[0]).abs() < .001 || (p[1] - q[1]).abs() < .001,
              isTrue,
            );
          }
          c.undo();
          expect(c.document.toJson(), document.toJson());
        },
      );
    }
  }
}
