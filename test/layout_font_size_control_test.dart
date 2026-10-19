import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_font_size_control.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_inspector.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_style.dart';

void main() {
  Future<VenueLayoutController> mount(
    WidgetTester tester,
    double size, {
    bool readOnly = false,
  }) async {
    final node = LayoutNode(
      id: newLayoutId(),
      kind: 'table',
      label: 'VIP',
      x: 300,
      y: 300,
      properties: {'size': size, 'bold': true, 'italic': true},
    );
    final c = VenueLayoutController(
      VenueLayoutDocument.empty().copyWith(nodes: [node]),
    )..readOnly = readOnly;
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: ListenableBuilder(
              listenable: c,
              builder: (_, _) => LayoutFontSizeControl(
                controller: c,
                node: c.document.nodes.single,
                value: (c.document.nodes.single.properties['size'] as num)
                    .toDouble(),
              ),
            ),
          ),
        ),
      ),
    );
    return c;
  }

  testWidgets(
    'imported precise size previews continuously and commits one undo',
    (tester) async {
      final c = await mount(tester, 40.64);
      final before = c.document;
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '41',
      );
      final slider = find.byType(Slider);
      final gesture = await tester.startGesture(tester.getCenter(slider));
      await gesture.moveBy(const Offset(25, 0));
      await tester.pump();
      expect(c.document.nodes.single.properties['size'], isNot(40.64));
      final size = c.document.nodes.single.properties['size'] as num;
      expect(size, size.round());
      expect(c.canUndo, isFalse);
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(c.canUndo, isTrue);
      expect(c.document.nodes.single.properties['bold'], isTrue);
      expect(c.document.nodes.single.properties['italic'], isTrue);
      expect(
        captureLayoutAppearance(
          c.document,
          c.document.nodes.single.id,
        ).object['size'],
        c.document.nodes.single.properties['size'],
      );
      c.undo();
      expect(c.document, same(before));
      expect(c.canUndo, isFalse);
    },
  );
  testWidgets('typed font size rounds to whole units', (tester) async {
    final c = await mount(tester, 24);
    await tester.enterText(find.byType(TextField), '32,8');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(c.document.nodes.single.properties['size'], 33);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '33',
    );
    c.undo();
    expect(c.document.nodes.single.properties['size'], 24);
  });
  testWidgets('cancelled slider restores preview and creates no undo', (
    tester,
  ) async {
    final c = await mount(tester, 40.64), before = c.document;
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(Slider)),
    );
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    await gesture.cancel();
    await tester.pump();
    expect(c.document, same(before));
    expect(c.canUndo, isFalse);
    expect(c.gestureActive, isFalse);
  });
  testWidgets('removing the control cancels an unfinished preview', (
    tester,
  ) async {
    final c = await mount(tester, 24);
    final before = c.document;
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(Slider)),
    );
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(c.document, same(before));
    expect(c.gestureActive, isFalse);
    expect(c.canUndo, isFalse);
    await gesture.cancel();
  });
  testWidgets('unchanged precise input does not round an imported size', (
    tester,
  ) async {
    final c = await mount(tester, 40.640625);
    final before = c.document;
    await tester.tap(find.byType(TextField));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(c.document, same(before));
    expect(c.canUndo, isFalse);
  });
  testWidgets(
    'large imported size remains accessible and read only disables both inputs',
    (tester) async {
      final c = await mount(tester, 512.75, readOnly: true);
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.value, 512.75);
      expect(slider.max, greaterThan(512.75));
      expect(slider.onChanged, isNull);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      expect(c.dirty, isFalse);
    },
  );
  testWidgets('restricted name delegates to host without geometry mutation', (
    tester,
  ) async {
    final node = LayoutNode(
      id: newLayoutId(),
      kind: 'table',
      label: 'Old',
      x: 300,
      y: 300,
    );
    final c = VenueLayoutController(
      VenueLayoutDocument.empty().copyWith(nodes: [node]),
    )..select({node.id});
    addTearDown(c.dispose);
    String? renamed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: LayoutInspector(
              controller: c,
              cornerPivot: false,
              onPivotChanged: (_) {},
              readOnlyLabelNodeIds: {node.id},
              onRenameNode: (n, name) {
                expect(n.id, node.id);
                renamed = name;
              },
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'New');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(renamed, 'New');
    expect(c.document.nodes.single.label, 'Old');
    expect(c.canUndo, isFalse);
  });
  test(
    'table wrapper typography copies to table labels without changing seat typography',
    () {
      final group = LayoutNode(
        id: newLayoutId(),
        kind: 'group',
        x: 300,
        y: 300,
      );
      final source = LayoutNode(
        id: newLayoutId(),
        kind: 'table',
        parentId: group.id,
        label: 'VIP',
        properties: {
          'fontId': 'fixture:sans',
          'size': 40.64,
          'bold': true,
          'italic': true,
        },
      );
      final target = LayoutNode(
        id: newLayoutId(),
        kind: 'table',
        label: 'Other',
        x: 700,
        y: 300,
      );
      final seat = LayoutNode(
        id: newLayoutId(),
        kind: 'seat',
        parentId: target.id,
        y: 100,
        properties: {'size': 12},
      );
      final doc = VenueLayoutDocument.empty().copyWith(
        nodes: [group, source, target, seat],
      );
      final result = applyLayoutAppearance(doc, {
        target.id,
      }, captureLayoutAppearance(doc, group.id));
      final changed = result.nodes.firstWhere((n) => n.id == target.id);
      for (final key in ['fontId', 'size', 'bold', 'italic']) {
        expect(changed.properties[key], source.properties[key]);
      }
      expect(changed.label, target.label);
      expect(changed.x, target.x);
      expect(
        result.nodes.firstWhere((n) => n.id == seat.id).properties['size'],
        12,
      );
      expect(result.defaultTextStyle, doc.defaultTextStyle);
      final normal = applyLayoutAppearance(doc, {
        group.id,
      }, captureLayoutAppearance(doc, target.id));
      final normalTable = normal.nodes.firstWhere((n) => n.id == source.id);
      expect(normalTable.properties['bold'], isFalse);
      expect(normalTable.properties['italic'], isFalse);
      expect(normalTable.properties['size'], doc.defaultTextStyle['size']);
    },
  );
}
