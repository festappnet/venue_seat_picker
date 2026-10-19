import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_inspector.dart';

void main() {
  Future<void> open(
    WidgetTester tester,
    VenueLayoutController controller,
  ) async {
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: ListenableBuilder(
              listenable: controller,
              builder: (_, _) => LayoutInspector(
                controller: controller,
                cornerPivot: false,
                onPivotChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, String label) async {
    final control = find.byType(DropdownButtonFormField<String>).first;
    await tester.ensureVisible(control);
    await tester.tap(control);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'tables and bars can be painted and drawn shapes convert to bars',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final polygon = LayoutNode(
        id: newLayoutId(),
        kind: 'shape',
        width: 200,
        height: 200,
        properties: {
          'shape': 'polygon',
          'points': [
            [-100, -100],
            [100, -100],
            [100, 100],
            [-100, 100],
          ],
        },
      );
      final c = VenueLayoutController(VenueLayoutDocument(nodes: [polygon]))
        ..select({polygon.id});
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VenueLayoutEditor(controller: c, showGallery: false),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Paint table'), findsOneWidget);
      expect(find.text('Paint bar'), findsOneWidget);
      expect(find.text('Use as table'), findsNothing);
      expect(find.text('Use as bar'), findsOneWidget);
      expect(find.text('Table'), findsWidgets);
      expect(find.text('Round table'), findsWidgets);
      expect(c.dirty, isFalse);
    },
  );

  testWidgets(
    'table shapes switch both ways without changing seat identities',
    (tester) async {
      final original = tableLayout(
        shape: 'round',
        width: 200,
        height: 200,
        count: 4,
      );
      final table = original.nodes.firstWhere((node) => node.kind == 'table');
      final seatIds = original.nodes
          .where((node) => node.kind == 'seat')
          .map((node) => node.id)
          .toSet();
      final controller = VenueLayoutController(
        original,
        protectedSeatIds: () => seatIds,
      )..select({table.id});
      await open(tester, controller);
      expect(find.text('Preview count'), findsNothing);
      final shapeControl = tester.widget<DropdownButton<String>>(
        find.byType(DropdownButton<String>).first,
      );
      expect(shapeControl.items!.map((item) => item.value), [
        'rectangle',
        'round',
        'polygon',
      ]);
      final advanced = find.text('Advanced object properties');
      await tester.ensureVisible(advanced);
      await tester.tap(advanced);
      await tester.pumpAndSettle();
      expect(find.text('Rotate around corner'), findsNothing);
      expect(find.text('Physical obstacle'), findsNothing);
      expect(find.text('Blocks seat placement'), findsNothing);
      expect(find.byTooltip('Add one seat'), findsOneWidget);
      expect(find.byTooltip('Remove one seat'), findsOneWidget);
      for (final entry in {
        'Rectangle': 'roundedRect',
        'Custom outline': 'polygon',
        'Round': 'round',
      }.entries) {
        await choose(tester, entry.key);
        expect(
          controller.document.nodes
              .firstWhere((node) => node.id == table.id)
              .properties['shape'],
          entry.value,
        );
        if (entry.value == 'polygon') {
          final points = localHull(
            controller.document.nodes.firstWhere((node) => node.id == table.id),
          );
          expect(points.length, 6);
          for (var i = 0; i < points.length; i++) {
            final a = points[i], b = points[(i + 1) % points.length];
            expect(a[0] == b[0] || a[1] == b[1], isTrue);
          }
        }
        expect(
          controller.document.nodes
              .where((node) => node.kind == 'seat')
              .map((node) => node.id)
              .toSet(),
          seatIds,
        );
        expect(
          controller.document.attachments
              .map((attachment) => attachment['seatId'])
              .toSet(),
          seatIds,
        );
        expect(
          controller.document.nodes
              .where((node) => seatIds.contains(node.id))
              .every((node) => node.parentId == table.id),
          isTrue,
        );
      }
      controller.undo();
      controller.undo();
      controller.undo();
      expect(controller.document, same(original));
    },
  );

  testWidgets(
    'imported table outlines remain intact until a basic shape is chosen',
    (tester) async {
      final base = tableLayout(
        shape: 'roundedRect',
        width: 200,
        height: 200,
        count: 4,
      );
      final table = base.nodes.firstWhere((node) => node.kind == 'table');
      final original = reshapeTableSurface(base, table.id, 'rectangle');
      final seatIds = original.nodes
          .where((node) => node.kind == 'seat')
          .map((node) => node.id)
          .toSet();
      final controller = VenueLayoutController(
        original,
        protectedSeatIds: () => seatIds,
      )..select({table.id});
      await open(tester, controller);
      final control = tester.widget<DropdownButtonFormField<String>>(
        find.byType(DropdownButtonFormField<String>).first,
      );
      expect(control.initialValue, 'polygon');
      expect(
        tester
            .widget<DropdownButton<String>>(
              find.byType(DropdownButton<String>).first,
            )
            .items!
            .map((item) => item.value),
        ['rectangle', 'round', 'polygon'],
      );
      expect(find.text('Custom outline'), findsOneWidget);
      expect(controller.document, same(original));
      expect(controller.canUndo, isFalse);
      await choose(tester, 'Round');
      expect(
        controller.document.nodes
            .firstWhere((node) => node.id == table.id)
            .properties['shape'],
        'round',
      );
      expect(
        controller.document.nodes
            .where((node) => node.kind == 'seat')
            .map((node) => node.id)
            .toSet(),
        seatIds,
      );
      controller.undo();
      expect(controller.document, same(original));
    },
  );

  testWidgets(
    'a smaller-capacity shape cannot silently remove protected seats',
    (tester) async {
      final template = LayoutNode(
        id: newLayoutId(),
        kind: 'table',
        width: 256,
        height: 256,
        properties: {'shape': 'roundedRect'},
      );
      final count = tableCapacity(template);
      expect(
        tableCapacity(template.copyWith(properties: {'shape': 'round'})),
        lessThan(count),
      );
      final original = tableLayout(
        shape: 'roundedRect',
        width: 256,
        height: 256,
        count: count,
        id: template.id,
      );
      final seatIds = original.nodes
          .where((node) => node.kind == 'seat')
          .map((node) => node.id)
          .toSet();
      final controller = VenueLayoutController(
        original,
        protectedSeatIds: () => seatIds,
      )..select({template.id});
      await open(tester, controller);
      await choose(tester, 'Round');
      expect(controller.document, same(original));
      expect(controller.canUndo, isFalse);
      expect(
        find.textContaining(
          'The selected shape cannot fit the existing chairs.',
        ),
        findsOneWidget,
      );
    },
  );
}
