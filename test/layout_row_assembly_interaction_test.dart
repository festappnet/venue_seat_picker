import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';

void main() {
  testWidgets('row gaps select immediately and full row resize is one undo', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final original = rowLayout(rows: 3, seatsPerRow: 5, arc: 3, x: 400, y: 300);
    final root = original.nodes.firstWhere((n) => n.parentId == null);
    final controller = VenueLayoutController(original);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VenueLayoutEditor(controller: controller, showGallery: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    LayoutSceneSurface surface() => tester.widget<LayoutSceneSurface>(
      find.byWidgetPredicate(
        (w) => w is LayoutSceneSurface && w.onViewportScaleChanged != null,
      ),
    );
    // Midpoint between columns and rows, away from the placeholder group's 40x40 hull.
    final gap = Offset(root.x + 28, root.y + 33.5);
    expect(hitTest(original, gap.dx, gap.dy, tolerance: 8), isNull);
    surface().onSelectDown!(gap);
    expect(controller.selection, {root.id});
    expect(controller.document, same(original));
    expect(controller.canUndo, false);
    await tester.pump();
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Tooltip &&
            (w.message?.startsWith('Resize') ?? false) &&
            (w.message?.endsWith('handle') ?? false),
      ),
      findsNWidgets(8),
    );
    final bounds = rowAssemblyBounds(original, root.id);
    final corner = Offset(
      root.x + bounds['x']! + bounds['width']!,
      root.y + bounds['y']! + bounds['height']!,
    );
    surface().onHandleStart!('Resize se', corner);
    surface().onDragUpdate!(corner + const Offset(100, 60));
    surface().onDragEnd!();
    final changed = rowAssemblyBounds(controller.document, root.id);
    expect(changed['width'], greaterThan(bounds['width']! + 90));
    expect(changed['height'], greaterThan(bounds['height']! + 50));
    expect(controller.document.canvas, original.canvas);
    for (final seat in original.nodes.where((n) => n.kind == 'seat')) {
      final next = controller.document.nodes.firstWhere((n) => n.id == seat.id);
      expect(next.width, seat.width);
      expect(next.height, seat.height);
    }
    expect(validateDocument(controller.document), isEmpty);
    controller.undo();
    expect(controller.document.toJson(), original.toJson());
    expect(controller.canUndo, false);
  });

  test(
    'selecting the same IDs does not emit redundant rebuild notifications',
    () {
      final doc = rowLayout(rows: 2, seatsPerRow: 5);
      final controller = VenueLayoutController(doc);
      addTearDown(controller.dispose);
      var notifications = 0;
      controller.addListener(() => notifications++);
      controller.select({doc.nodes.first.id});
      controller.select({doc.nodes.first.id});
      controller.select({'missing'});
      controller.select({});
      expect(notifications, 2);
    },
  );
}
