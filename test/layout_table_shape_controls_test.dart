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
      expect(find.byTooltip('Add one seat'), findsOneWidget);
      expect(find.byTooltip('Remove one seat'), findsOneWidget);
      for (final entry in {
        'Custom outline': 'polygon',
        'Rectangle': 'roundedRect',
        'Round': 'round',
      }.entries) {
        await choose(tester, entry.key);
        expect(
          controller.document.nodes
              .firstWhere((node) => node.id == table.id)
              .properties['shape'],
          entry.value,
        );
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
