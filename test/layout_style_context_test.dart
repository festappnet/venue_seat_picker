import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_style.dart';

void main() {
  test(
    'styles preserve geometry, IDs, zigzag metadata and locked descendants',
    () {
      final table = LayoutNode(
        id: newLayoutId(),
        kind: 'table',
        x: 400,
        y: 400,
        width: 190,
        height: 110,
        label: 'VIP',
      );
      final seat = LayoutNode(
        id: newLayoutId(),
        parentId: table.id,
        kind: 'seat',
        x: 0,
        y: -90,
        width: 40,
        height: 40,
      );
      final locked = LayoutNode(
        id: newLayoutId(),
        kind: 'seat',
        parentId: table.id,
        x: 60,
        y: -90,
        width: 40,
        height: 40,
        locked: true,
      );
      final zigzag = zigzagLine(700, 300, 1100, 300);
      final doc = VenueLayoutDocument.empty().copyWith(
        nodes: [table, seat, locked, zigzag],
      );
      final result = applyLayoutAppearance(doc, {
        table.id,
        zigzag.id,
      }, layoutAppearancePresets['Warm']!);
      expect(result.nodes.map((n) => n.id), doc.nodes.map((n) => n.id));
      expect(result.nodes[0].label, table.label);
      expect(result.nodes[0].width, table.width);
      expect(result.nodes[0].x, table.x);
      expect(result.nodes[1].properties['fill'], '#D9B788FF');
      expect(result.nodes[2].toJson(), locked.toJson());
      expect(result.nodes[3].properties['points'], zigzag.properties['points']);
      expect(result.nodes[3].properties['zigzagTeeth'], 8);
      expect(result.nodes[3].properties['fill'], '#00000000');
      final copied = captureLayoutAppearance(result, table.id);
      expect(copied.object['fill'], '#F0E4D2FF');
      expect(copied.seats!['fill'], '#D9B788FF');
    },
  );

  test(
    'local appearance exceptions survive global edits until inheritance is restored',
    () {
      final node = LayoutNode(
        id: newLayoutId(),
        kind: 'table',
        x: 400,
        y: 300,
        width: 190,
        height: 110,
      );
      var doc = setLayoutAppearance(
        VenueLayoutDocument.empty().copyWith(nodes: [node]),
        'table',
        {'fill': '#112233FF', 'strokeWidth': 3, 'cornerRadius': 12},
      );
      expect(effectiveNodeProperties(doc, node)['fill'], '#112233FF');
      doc = applyLayoutAppearance(doc, {
        node.id,
      }, const LayoutAppearance({'fill': '#ABCDEF80'}));
      doc = setLayoutAppearance(doc, 'table', {
        'fill': '#556677FF',
        'strokeWidth': 5,
      });
      expect(
        effectiveNodeProperties(doc, doc.nodes.single)['fill'],
        '#ABCDEF80',
      );
      expect(effectiveNodeProperties(doc, doc.nodes.single)['strokeWidth'], 5);
      doc = followPlanAppearance(doc, {node.id}, true);
      expect(
        effectiveNodeProperties(doc, doc.nodes.single)['fill'],
        '#556677FF',
      );
      final restored = VenueLayoutDocument.fromJson(doc.toJson());
      expect(restored.appearance, doc.appearance);
      expect(restored.nodes.single.x, node.x);
      expect(restored.nodes.single.id, node.id);
      final future = LayoutNode(
        id: newLayoutId(),
        kind: 'table',
        x: 900,
        y: 300,
      );
      expect(effectiveNodeProperties(restored, future)['fill'], '#556677FF');
    },
  );

  Future<void> open(WidgetTester tester, VenueLayoutController c) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VenueLayoutEditor(controller: c, showGallery: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder canvas() => find.byWidgetPredicate(
    (w) => w is LayoutSceneSurface && w.onContextMenu != null,
  );

  testWidgets(
    'secondary click opens style menu; preset and copied style are undoable',
    (tester) async {
      final a = LayoutNode(
        id: newLayoutId(),
        kind: 'table',
        x: 1200,
        y: 800,
        width: 190,
        height: 110,
      );
      final b = LayoutNode(
        id: newLayoutId(),
        kind: 'table',
        x: 1600,
        y: 800,
        width: 190,
        height: 110,
      );
      final c = VenueLayoutController(
        VenueLayoutDocument.empty().copyWith(nodes: [a, b]),
      );
      await open(tester, c);
      final mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await mouse.down(tester.getCenter(canvas()));
      await mouse.up();
      await tester.pumpAndSettle();
      expect(c.selection, {a.id});
      expect(
        find.widgetWithText(PopupMenuItem<String>, 'Style'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(PopupMenuItem<String>, 'Style'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byKey(const ValueKey('layout-style-Warm')),
        ),
      );
      await tester.pump();
      expect(c.document.nodes.first.properties['fill'], '#F0E4D2FF');
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Object appearance'));
      await tester.tap(find.text('Object appearance'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Copy style'));
      await tester.tap(find.byTooltip('Copy style'));
      await tester.pump();
      c.select({b.id});
      await tester.pump();
      await tester.ensureVisible(find.text('Object appearance'));
      await tester.tap(find.text('Object appearance'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Paste style'));
      await tester.tap(find.byTooltip('Paste style'));
      await tester.pump();
      expect(c.document.nodes.last.properties['fill'], '#F0E4D2FF');
      expect(c.document.nodes.last.x, b.x);
      c.undo();
      expect(c.document.nodes.last.toJson(), b.toJson());
      c.undo();
      expect(c.document.nodes.first.toJson(), a.toJson());
    },
  );

  testWidgets('touch long press exposes same menu without moving object', (
    tester,
  ) async {
    final node = LayoutNode(
      id: newLayoutId(),
      kind: 'table',
      x: 1200,
      y: 800,
      width: 190,
      height: 110,
    );
    final original = VenueLayoutDocument.empty().copyWith(nodes: [node]);
    final c = VenueLayoutController(original);
    await open(tester, c);
    await tester.longPressAt(tester.getCenter(canvas()));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(PopupMenuItem<String>, 'Style'), findsOneWidget);
    expect(c.document.toJson(), original.toJson());
    expect(c.canUndo, isFalse);
  });
}
