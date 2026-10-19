import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';

void main() {
  testWidgets(
    'imported table group selects at the tabletop and has handles around its contents',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final group = newLayoutId(), table = newLayoutId(), chair = newLayoutId();
      final doc = VenueLayoutDocument(
        nodes: [
          LayoutNode(
            id: group,
            kind: 'group',
            label: 'Table group',
            width: 1,
            height: 1,
          ),
          LayoutNode(
            id: table,
            parentId: group,
            kind: 'table',
            x: 1000,
            y: 700,
            width: 180,
            height: 100,
          ),
          LayoutNode(
            id: chair,
            parentId: group,
            kind: 'seat',
            x: 1000,
            y: 590,
            width: 40,
            height: 40,
          ),
        ],
      );
      final c = VenueLayoutController(doc);
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VenueLayoutEditor(controller: c, showGallery: false),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final f = find.byWidgetPredicate(
        (w) => w is LayoutSceneSurface && w.onTap != null,
      );
      final r = tester.getRect(f),
          scale = math.min((r.width - 32) / 2400, (r.height - 32) / 1600);
      final origin =
          r.topLeft +
          Offset((r.width - 2400 * scale) / 2, (r.height - 1600 * scale) / 2);
      await tester.tapAt(origin + Offset(1000 * scale, 700 * scale));
      await tester.pumpAndSettle();
      expect(c.selection, {group});
      final bounds = selectionBounds(c.document, {group});
      final expected =
          origin +
          Offset(
            (bounds['x']! + bounds['width']!) * scale,
            (bounds['y']! + bounds['height']!) * scale,
          );
      final actual = tester.getCenter(find.byTooltip('Resize handle'));
      expect(
        (actual - expected).distance,
        lessThan(1),
        reason:
            'Group handles must follow the visible table and chairs, not the dummy group origin',
      );
      final before = c.document;
      final gesture = await tester.startGesture(actual);
      await gesture.moveBy(const Offset(25, 25));
      await gesture.moveBy(const Offset(40, 30));
      await tester.pump();
      expect(c.error, isNull);
      expect(
        c.document.nodes.firstWhere((n) => n.id == table).width,
        greaterThan(180),
        reason: 'Resize must affect visible geometry',
      );
      expect(
        c.document.nodes.map((n) => n.id).toSet(),
        before.nodes.map((n) => n.id).toSet(),
      );
      expect(c.document.nodes.firstWhere((n) => n.id == chair).parentId, group);
      await gesture.up();
      await tester.pumpAndSettle();
      final resized = c.document;
      final tabletop = resized.nodes.firstWhere((n) => n.id == table);
      final groupNode = resized.nodes.firstWhere((n) => n.id == group);
      final center =
          origin +
          Offset(
            (groupNode.x + tabletop.x) * scale,
            (groupNode.y + tabletop.y) * scale,
          );
      final move = await tester.startGesture(center);
      await move.moveBy(const Offset(25, 25));
      await move.moveBy(const Offset(35, 20));
      await tester.pump();
      expect(
        c.document.nodes.firstWhere((n) => n.id == group).x,
        greaterThan(groupNode.x),
        reason: 'Dragging updates before mouse-up',
      );
      await move.up();
      await tester.pumpAndSettle();
      expect(c.error, isNull);
    },
  );
}
