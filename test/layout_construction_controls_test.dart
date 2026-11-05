import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/canonical_appearance_panel.dart';

void main() {
  for (final kind in ['shape', 'capacityArea', 'table', 'seat', 'furniture']) {
    testWidgets('$kind shows only applicable construction controls', (
      tester,
    ) async {
      final node = LayoutNode(
        id: newLayoutId(),
        kind: kind,
        properties: kind == 'shape'
            ? {'shape': 'rect'}
            : kind == 'furniture'
            ? {'furniture': 'couch'}
            : {},
      );
      final doc = kind == 'table'
          ? tableLayout(shape: 'rect', count: 4)
          : VenueLayoutDocument(nodes: [node]);
      final target = doc.nodes.firstWhere((n) => n.kind == kind);
      final controller = VenueLayoutController(doc);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CanonicalAppearancePanel(
                controller: controller,
                nodeId: target.id,
              ),
            ),
          ),
        ),
      );
      expect(
        find.text('Material'),
        ['table', 'seat', 'furniture'].contains(kind)
            ? findsOneWidget
            : findsNothing,
      );
      expect(find.text('Fill color'), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showCanonicalAppearanceDialog(
                  context,
                  controller,
                  nodeId: target.id,
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(
        find.text('Style family'),
        ['table', 'seat', 'furniture'].contains(kind)
            ? findsOneWidget
            : findsNothing,
      );
      expect(find.text('Color palette'), findsOneWidget);
    });
  }
}
