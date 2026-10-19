import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_global_style.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_style.dart';

void main() {
  test(
    'scoped typography inherits, preserves local and locked labels, resets font and undoes',
    () {
      final table = LayoutNode(
        id: newLayoutId(),
        kind: 'table',
        label: 'A',
        x: 200,
        y: 200,
      );
      final local = LayoutNode(
        id: newLayoutId(),
        kind: 'table',
        label: 'B',
        x: 500,
        y: 200,
        properties: {
          'size': 40.64,
          'appearanceOverrides': ['size'],
        },
      );
      final group = LayoutNode(
        id: newLayoutId(),
        kind: 'group',
        x: 800,
        y: 200,
        locked: true,
      );
      final locked = LayoutNode(
        id: newLayoutId(),
        kind: 'table',
        parentId: group.id,
        label: 'C',
      );
      final doc = VenueLayoutDocument.empty().copyWith(
        nodes: [table, local, group, locked],
      );
      final c = VenueLayoutController(doc);
      addTearDown(c.dispose);
      expect(
        c.apply(
          setLayoutAppearance(doc, 'table', {
            'fontId': 'new-font',
            'size': 36,
            'bold': true,
            'italic': true,
          }),
        ),
        isTrue,
        reason: c.error,
      );
      final values = effectiveNodeProperties(c.document, table);
      expect(values['size'], 36);
      expect(values['bold'], true);
      expect(values['italic'], true);
      expect(values['fontId'], 'new-font');
      expect(effectiveNodeProperties(c.document, local)['size'], 40.64);
      final frozen = c.document.nodes.firstWhere((n) => n.id == locked.id);
      expect(effectiveNodeProperties(c.document, frozen)['size'], 24);
      expect(effectiveNodeProperties(c.document, frozen)['bold'], false);
      final malicious = c.document.copyWith(
        appearance: {
          ...c.document.appearance,
          'table': {'size': 48},
        },
        nodes: [
          for (final n in c.document.nodes)
            n.id == locked.id ? n.copyWith(label: 'Changed') : n,
        ],
      );
      expect(c.apply(malicious), false);
      final maliciousStyle = c.document.copyWith(
        appearance: {
          ...c.document.appearance,
          'table': {'size': 48},
        },
        nodes: [
          for (final n in c.document.nodes)
            n.id == locked.id
                ? n.copyWith(properties: {...n.properties, 'size': 99})
                : n,
        ],
      );
      expect(c.apply(maliciousStyle), false);
      final added = LayoutNode(id: newLayoutId(), kind: 'table');
      expect(effectiveNodeProperties(c.document, added)['size'], 36);
      final reset = setLayoutAppearance(c.document, 'table', {'fontId': null});
      expect((reset.appearance['table'] as Map).containsKey('fontId'), false);
      expect(validateDocument(reset), isEmpty);
      final own = table.copyWith(
        properties: localAppearanceProperties(table, {
          'size': 17,
          'bold': false,
        }),
      );
      expect(effectiveNodeProperties(c.document, own)['size'], 17);
      expect(effectiveNodeProperties(c.document, own)['bold'], false);
      c.undo();
      expect(c.document, same(doc));
      for (final invalid in [
        {'size': 0},
        {'size': 4097},
        {'bold': 1},
        {'fontId': ''},
      ]) {
        expect(
          () => setLayoutAppearance(doc, 'table', invalid),
          throwsA(isA<InvalidLayoutDocument>()),
        );
      }
    },
  );

  testWidgets(
    'table global typography exposes host catalog slider and independent B I',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final table = LayoutNode(
        id: newLayoutId(),
        kind: 'table',
        label: 'A',
        x: 300,
        y: 300,
      );
      final c = VenueLayoutController(
        VenueLayoutDocument.empty().copyWith(nodes: [table]),
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showLayoutGlobalStyleDialog(
                  context,
                  c,
                  globalFontPickerBuilder: (context, kind) =>
                      Text('Catalog $kind'),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Appearance'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Fine-tune appearance'));
      await tester.tap(find.text('Fine-tune appearance'));
      await tester.pumpAndSettle();
      expect(find.text('Catalog table'), findsOneWidget);
      final control = find.byKey(const ValueKey('table-font-size'));
      final sizeInput = find.descendant(
        of: control,
        matching: find.byType(TextField),
      );
      expect(tester.widget<TextField>(sizeInput).controller!.text, '24');
      final slider = find.descendant(
        of: control,
        matching: find.byType(Slider),
      );
      await tester.ensureVisible(slider);
      final before = c.document;
      final gesture = await tester.startGesture(tester.getCenter(slider));
      await gesture.moveBy(const Offset(25, 0));
      await tester.pump();
      expect(c.document, same(before));
      await gesture.up();
      await tester.pumpAndSettle();
      expect((c.document.appearance['table'] as Map)['size'], isNot(24));
      c.undo();
      await tester.pumpAndSettle();
      expect(c.document, same(before));
      expect(c.canUndo, false);
      await tester.ensureVisible(find.byTooltip('Bold'));
      await tester.tap(find.byTooltip('Bold'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Italic'));
      await tester.pumpAndSettle();
      expect((c.document.appearance['table'] as Map)['bold'], true);
      expect((c.document.appearance['table'] as Map)['italic'], true);
      await tester.ensureVisible(sizeInput);
      await tester.enterText(sizeInput, '35,7');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect((c.document.appearance['table'] as Map)['size'], 36);
      expect(tester.widget<TextField>(sizeInput).controller!.text, '36');

      expect(tester.takeException(), isNull);
    },
  );
}
