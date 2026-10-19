import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';

void main() {
  testWidgets(
    'standing restores host quantity and permits zero without a seat hold',
    (tester) async {
      final id = newLayoutId();
      final document = VenueLayoutDocument(
        nodes: [
          LayoutNode(
            id: id,
            kind: 'capacityArea',
            label: 'Standing',
            x: 100,
            y: 100,
          ),
        ],
      );
      final counts = <int>[];
      final completion = Completer<LayoutSelectionResult>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VenueLayoutPicker(
              document: document,
              capacityPresentation: {
                id: {'available': 5, 'quantity': 3},
              },
              onSelectionRequested: (_, __) async =>
                  throw StateError('Standing is not a seat hold'),
              onQuantityRequested: (_, count) {
                counts.add(count);
                return completion.future;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      tester.widget<LayoutSceneSurface>(find.byType(LayoutSceneSurface)).onTap!(
        const Offset(100, 100),
      );
      await tester.pumpAndSettle();
      expect(find.text('3'), findsOneWidget);
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byTooltip('Remove one'));
        await tester.pump();
      }
      await tester.tap(find.text('Confirm quantity'));
      await tester.pump();
      expect(counts, [0]);
      completion.complete(const LayoutSelectionResult(accepted: true));
      await tester.pumpAndSettle();
      tester.widget<LayoutSceneSurface>(find.byType(LayoutSceneSurface)).onTap!(
        const Offset(100, 100),
      );
      await tester.pumpAndSettle();
      expect(find.text('0'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
