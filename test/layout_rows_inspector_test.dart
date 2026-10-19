import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

void main() {
  testWidgets(
    'row and column controls retain curved seat identities and create atomic history',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final original = rowLayout(
        rows: 2,
        seatsPerRow: 4,
        arc: 3,
        spacing: 100,
        rowSpacing: 110,
        seating: const TableSeating(width: 77.5, height: 77.5),
        x: 300,
        y: 200,
      );
      final root = original.nodes.firstWhere((n) => n.parentId == null);
      final c = VenueLayoutController(original)..select({root.id});
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VenueLayoutEditor(controller: c, showGallery: false),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Number of rows'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Seats per row'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Curvature'), findsOneWidget);
      final slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChangeStart!(3);
      slider.onChanged!(6);
      slider.onChangeEnd!(6);
      await tester.pumpAndSettle();
      expect(rowLayoutParameters(c.document, root.id)['arc'], 6);
      c.undo();
      await tester.pumpAndSettle();
      expect(c.document.toJson(), original.toJson());
      expect(c.canUndo, false);
      await tester.tap(find.byTooltip('Add row'));
      await tester.pumpAndSettle();
      expect(c.document.nodes.where((n) => n.kind == 'seat'), hasLength(12));
      expect(rowLayoutParameters(c.document, root.id)['arc'], 3);
      expect(
        c.document.nodes
            .where((n) => n.kind == 'seat')
            .every((n) => n.width == 77.5 && n.height == 77.5),
        isTrue,
      );
      for (final seat in original.nodes.where((n) => n.kind == 'seat')) {
        expect(c.document.nodes.any((n) => n.id == seat.id), true);
      }
      c.undo();
      await tester.pumpAndSettle();
      expect(c.document.toJson(), original.toJson());
      final columnField = find.widgetWithText(TextField, 'Seats per row');
      await tester.enterText(columnField, '5');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(c.document.nodes.where((n) => n.kind == 'seat'), hasLength(10));
      expect(rowLayoutParameters(c.document, root.id)['arc'], 3);
      expect(c.document.nodes.firstWhere((n) => n.id == root.id).x, root.x);
      expect(validateDocument(c.document), isEmpty);
      c.undo();
      expect(c.document.toJson(), original.toJson());
    },
  );

  testWidgets('row count cannot be fractional or remove the last row', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final original = rowLayout(rows: 1, seatsPerRow: 4, arc: 3, x: 300, y: 200);
    final c = VenueLayoutController(original)
      ..select({original.nodes.first.id});
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VenueLayoutEditor(controller: c, showGallery: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final remove = tester.widget<IconButton>(
      find.byWidgetPredicate(
        (w) => w is IconButton && w.tooltip == 'Remove row',
      ),
    );
    expect(remove.onPressed, isNull);
    await tester.enterText(
      find.widgetWithText(TextField, 'Number of rows'),
      '1.5',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(c.document.toJson(), original.toJson());
    expect(c.canUndo, false);
  });
}
