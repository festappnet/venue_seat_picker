import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';

void main() {
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

  LayoutSceneSurface surface(WidgetTester tester) =>
      tester.widget<LayoutSceneSurface>(
        find.byWidgetPredicate(
          (w) => w is LayoutSceneSurface && w.onViewportScaleChanged != null,
        ),
      );

  testWidgets(
    'side handle fixes opposite edge at canvas and undo restores all seats',
    (tester) async {
      final original = tableLayout(
        shape: 'rect',
        width: 420,
        height: 120,
        x: 230,
        y: 300,
        count: 8,
      );
      final table = original.nodes.first;
      final c = VenueLayoutController(original)..select({table.id});
      await open(tester, c);
      surface(tester).onHandleStart!('Resize w', const Offset(20, 300));
      surface(tester).onDragUpdate!(const Offset(-160, 300));
      var resized = c.document.nodes.firstWhere((n) => n.id == table.id);
      expect(resized.x + resized.width / 2, closeTo(440, .002));
      expect(resized.width, closeTo(440, .003));
      surface(tester).onDragUpdate!(const Offset(140, 300));
      resized = c.document.nodes.firstWhere((n) => n.id == table.id);
      expect(resized.x + resized.width / 2, closeTo(440, .002));
      expect(resized.width, 300);
      expect(c.error, isNull);
      surface(tester).onDragEnd!();
      c.undo();
      expect(c.document.toJson(), original.toJson());
      expect(c.canUndo, isFalse);
    },
  );

  testWidgets(
    'round resize keeps circle; Shift permits ellipse; free surplus seats undo together',
    (tester) async {
      final original = tableLayout(
        shape: 'ellipse',
        width: 160,
        height: 160,
        count: 8,
      );
      final table = original.nodes.firstWhere((n) => n.kind == 'table');
      final c = VenueLayoutController(original)..select({table.id});
      await open(tester, c);
      final corner = Offset(table.x + 80, table.y + 80);
      surface(tester).onHandleStart!('Resize', corner);
      surface(tester).onDragUpdate!(corner - const Offset(60, 20));
      final resized = c.document.nodes.firstWhere((n) => n.id == table.id);
      expect(resized.width, 100);
      expect(resized.height, 100);
      expect(c.document.nodes.where((n) => n.kind == 'seat'), hasLength(6));
      await tester.pump();
      expect(
        find.text('Seats removed: 2. Undo restores them.'),
        findsOneWidget,
      );
      surface(tester).onDragEnd!();
      c.undo();
      expect(c.document.toJson(), original.toJson());
      expect(c.canUndo, false);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      surface(tester).onHandleStart!('Resize', corner);
      surface(tester).onDragUpdate!(corner + const Offset(40, 10));
      surface(tester).onDragEnd!();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      final ellipse = c.document.nodes.firstWhere((n) => n.id == table.id);
      expect(ellipse.width, 200);
      expect(ellipse.height, 170);
    },
  );

  testWidgets(
    'protected shrink displays clear notice and rolls back without history',
    (tester) async {
      final original = tableLayout(
        shape: 'round',
        width: 160,
        height: 160,
        count: 8,
      );
      final table = original.nodes.firstWhere((n) => n.kind == 'table');
      final protected = original.nodes
          .where((n) => n.kind == 'seat')
          .map((n) => n.id)
          .toSet();
      final c = VenueLayoutController(
        original,
        protectedSeatIds: () => protected,
      )..select({table.id});
      await open(tester, c);
      final corner = Offset(table.x + 80, table.y + 80);
      surface(tester).onHandleStart!('Resize', corner);
      surface(tester).onDragUpdate!(corner - const Offset(60, 20));
      await tester.pump();
      expect(
        find.text('Reserved or blocked seats prevent shrinking this table.'),
        findsOneWidget,
      );
      expect(c.document.toJson(), original.toJson());
      surface(tester).onDragEnd!();
      expect(c.document.toJson(), original.toJson());
      expect(c.canUndo, false);
      expect(
        c.error,
        'Reserved or blocked seats prevent shrinking this table.',
      );
    },
  );

  test('live host protection applies to history and generic removal', () {
    final original = tableLayout(
      shape: 'round',
      width: 160,
      height: 160,
      count: 8,
    );
    final protected = <String>{};
    final c = VenueLayoutController(
      original,
      protectedSeatIds: () => protected,
    );
    addTearDown(c.dispose);
    final extra = LayoutNode(id: newLayoutId(), kind: 'seat', x: 800, y: 600);
    expect(c.apply(original.copyWith(nodes: [...original.nodes, extra])), true);
    protected.add(extra.id);
    c.undo();
    expect(c.document.nodes.any((n) => n.id == extra.id), true);
    expect(c.canUndo, true);
    expect(c.apply(original), false);
    protected.clear();
    c.undo();
    expect(c.document.toJson(), original.toJson());
  });
}
