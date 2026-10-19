import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';

void main() {
  testWidgets(
    'new scout table follows a drag across the dance floor without rollback',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final c = VenueLayoutController(
        VenueLayoutTemplates.create('scout-ball-182'),
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VenueLayoutEditor(controller: c, showGallery: false),
          ),
        ),
      );
      LayoutSceneSurface surface() => tester.widget<LayoutSceneSurface>(
        find.byWidgetPredicate(
          (w) => w is LayoutSceneSurface && w.onDrop != null,
        ),
      );
      surface().onDrop!('Table', const Offset(1600, 1600));
      await tester.pump();
      final table = c.document.nodes.singleWhere(
        (n) => c.selection.contains(n.id),
      );
      final inserted = c.document;
      surface().onDragStart!(Offset(table.x, table.y));
      for (var i = 1; i <= 12; i++) {
        surface().onDragUpdate!(Offset(table.x + i * 12, table.y + i * 10));
        expect(c.error, isNull, reason: 'drag frame $i');
        await tester.pump();
      }
      final preview = c.document.nodes.singleWhere((n) => n.id == table.id);
      surface().onDragEnd!();
      await tester.pump();
      final moved = c.document.nodes.singleWhere((n) => n.id == table.id);
      expect(moved.x, preview.x);
      expect(moved.y, preview.y);
      expect(moved.x, greaterThan(table.x + 100));
      expect(moved.y, greaterThan(table.y + 80));
      c.undo();
      expect(c.document.toJson(), inserted.toJson());
    },
  );

  testWidgets(
    'blocked table drag retains its last valid preview rather than jumping to its origin',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final table = tableLayout(shape: 'rect', x: 500, y: 500);
      final root = table.nodes.firstWhere((n) => n.kind == 'table');
      final document = table.copyWith(
        nodes: [
          ...table.nodes,
          LayoutNode(
            id: newLayoutId(),
            kind: 'table',
            x: 1100,
            y: 500,
            width: 500,
            height: 600,
          ),
        ],
      );
      final c = VenueLayoutController(document)..select({root.id});
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VenueLayoutEditor(controller: c, showGallery: false),
          ),
        ),
      );
      LayoutSceneSurface surface() => tester.widget<LayoutSceneSurface>(
        find.byWidgetPredicate(
          (w) => w is LayoutSceneSurface && w.onDrop != null,
        ),
      );
      surface().onDragStart!(const Offset(500, 500));
      surface().onDragUpdate!(const Offset(600, 500));
      await tester.pump();
      final lastValid = c.document.nodes.singleWhere((n) => n.id == root.id);
      expect(lastValid.x, greaterThan(550));
      surface().onDragUpdate!(const Offset(1100, 500));
      await tester.pump();
      expect(
        c.document.nodes.singleWhere((n) => n.id == root.id).x,
        lastValid.x,
      );
      surface().onDragEnd!();
      await tester.pump();
      expect(
        c.document.nodes.singleWhere((n) => n.id == root.id).x,
        lastValid.x,
      );
      c.undo();
      expect(c.document.toJson(), document.toJson());
    },
  );

  testWidgets(
    'fast drag starts at the pointer-down position even after leaving a small object',
    (tester) async {
      Offset? down, start;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                height: 400,
                child: LayoutSceneSurface(
                  document: VenueLayoutDocument.empty(),
                  pan: false,
                  onSelectDown: (point) => down = point,
                  onDragStart: (point) => start = point,
                  onDragUpdate: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(LayoutSceneSurface)),
        kind: PointerDeviceKind.mouse,
      );
      // Recognition may arrive only after the cursor left the pressed item.
      final detector = tester.widget<GestureDetector>(
        find.byWidgetPredicate(
          (w) => w is GestureDetector && w.onScaleStart != null,
        ),
      );
      detector.onScaleStart!(
        ScaleStartDetails(
          focalPoint:
              tester.getCenter(find.byType(LayoutSceneSurface)) +
              const Offset(80, 20),
          pointerCount: 1,
        ),
      );
      await gesture.up();
      expect(start, down);
    },
  );

  test(
    'large source couch cannot compress its cushions below document chair size',
    () {
      final couch = couchLayout(width: 187, height: 113.5);
      final root = couch.nodes.first;
      final resized = resizeCouchBody(couch, root.id, 40, 40);
      for (final seat in resized.nodes.where((n) => n.kind == 'seat')) {
        expect(seat.width, greaterThanOrEqualTo(77.5));
        expect(seat.height, greaterThanOrEqualTo(77.5));
      }
    },
  );
}
