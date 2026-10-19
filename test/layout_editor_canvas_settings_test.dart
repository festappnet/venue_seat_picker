import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_inspector.dart';

void main() {
  testWidgets(
    'canvas settings expand a canvas covered by a full-size rectangle',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final floor = LayoutNode(
        id: newLayoutId(),
        kind: 'shape',
        properties: {'shape': 'rectangle'},
        x: 200,
        y: 200,
        width: 400,
        height: 400,
      );
      final controller = VenueLayoutController(
        VenueLayoutDocument.empty().copyWith(
          canvas: {
            'x': 0,
            'y': 0,
            'width': 400,
            'height': 400,
            'fill': '#FFFFFFFF',
          },
          nodes: [floor],
        ),
      );
      addTearDown(controller.dispose);
      controller.select({floor.id});
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.purple,
            ).copyWith(surface: Colors.purple.shade50),
          ),
          home: Scaffold(
            body: VenueLayoutEditor(
              controller: controller,
              showGallery: false,
              toolbarTrailing: const Text('Host save'),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('edit-canvas')));
      await tester.pumpAndSettle();
      expect(controller.selection, isEmpty);
      expect(
        tester
            .widget<LayoutInspector>(find.byType(LayoutInspector))
            .canvasSelected,
        isTrue,
      );
      final width = find.descendant(
        of: find.byKey(const ValueKey('Width')),
        matching: find.byType(TextField),
      );
      await tester.ensureVisible(width);
      await tester.enterText(width, '600');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(controller.document.canvas['width'], 600);
      expect(controller.document.nodes.single.toJson(), floor.toJson());
      controller.updateNode(floor.copyWith(x: 220));
      expect(controller.document.nodes.single.x, 220);
      controller.undo();
      controller.undo();
      await tester.pumpAndSettle();
      expect(controller.document.canvas['width'], 400);
      final inspector = tester.getRect(find.byType(LayoutInspector));
      expect(
        tester
            .widget<Material>(find.byKey(const ValueKey('layout-palette')))
            .color,
        Colors.white,
      );
      expect(
        tester
            .widget<Material>(
              find
                  .descendant(
                    of: find.byType(LayoutInspector),
                    matching: find.byType(Material),
                  )
                  .first,
            )
            .color,
        Colors.white,
      );
      expect(inspector.top, lessThan(65));
      expect(inspector.height, greaterThan(750));
      expect(tester.takeException(), isNull);
    },
  );
}
