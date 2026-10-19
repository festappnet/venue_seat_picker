import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_inspector.dart';

void main() {
  for (final native in [false, true]) {
    testWidgets(
      'two chair side transfers redistribute rows, persist on resize and undo native=$native',
      (tester) async {
        var original = tableLayout(
          shape: 'roundedRect',
          width: 500,
          height: 100,
          count: 10,
        );
        final table = original.nodes.firstWhere((n) => n.kind == 'table');
        final right =
            original.attachments.firstWhere(
                  (a) => a['edge'] == 'right',
                )['seatId']
                as String;
        final left =
            original.attachments.firstWhere(
                  (a) => a['edge'] == 'left',
                )['seatId']
                as String;
        final ids = original.nodes
            .where((n) => n.kind == 'seat')
            .map((n) => n.id)
            .toSet();
        if (native) {
          final group = LayoutNode(
            id: newLayoutId(),
            kind: 'group',
            x: table.x,
            y: table.y,
            width: table.width,
            height: table.height,
            label: 'Native table',
          );
          original = original.copyWith(
            nodes: [
              group,
              for (final node in original.nodes)
                node.id == table.id
                    ? node.copyWith(parentId: group.id, x: 0, y: 0)
                    : node.copyWith(parentId: group.id),
            ],
            attachments: [],
          );
        }
        final c = VenueLayoutController(original, protectedSeatIds: () => ids)
          ..select({right});
        addTearDown(c.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 340,
                child: ListenableBuilder(
                  listenable: c,
                  builder: (_, _) => LayoutInspector(
                    controller: c,
                    cornerPivot: false,
                    onPivotChanged: (_) {},
                  ),
                ),
              ),
            ),
          ),
        );
        Future<void> move(String id, String label) async {
          c.select({id});
          await tester.pumpAndSettle();
          final control = find.byType(DropdownButtonFormField<String>).first;
          await tester.ensureVisible(control);
          await tester.tap(control);
          await tester.pumpAndSettle();
          await tester.tap(find.text(label).last);
          await tester.pumpAndSettle();
        }

        await move(right, 'Top side');
        await move(left, 'Bottom side');
        String side(String id) =>
            c.document.attachments.firstWhere((a) => a['seatId'] == id)['edge']
                as String;
        expect(side(right), 'top');
        expect(side(left), 'bottom');
        expect(
          c.document.nodes
              .where((n) => n.kind == 'seat')
              .map((n) => n.id)
              .toSet(),
          ids,
        );
        for (final edge in ['top', 'bottom']) {
          final rowIds = c.document.attachments
              .where((a) => a['edge'] == edge)
              .map((a) => a['seatId'])
              .toSet();
          final xs =
              c.document.nodes
                  .where((n) => rowIds.contains(n.id))
                  .map((n) => n.x)
                  .toList()
                ..sort();
          expect(xs.length, 5);
          for (var i = 2; i < xs.length; i++)
            expect(xs[i] - xs[i - 1], closeTo(xs[1] - xs[0], .01));
        }
        c.select({table.id});
        c.resizeObject(table.id, 600, 150);
        await tester.pumpAndSettle();
        expect(side(right), 'top');
        expect(side(left), 'bottom');
        expect(c.document.nodes.firstWhere((n) => n.id == right).y, -107);
        expect(c.document.nodes.firstWhere((n) => n.id == left).y, 107);
        c.undo();
        c.undo();
        c.undo();
        expect(c.document, same(original));
        expect(tester.takeException(), isNull);
      },
    );
  }

  test(
    'overfull destination and locked source reject without removing chairs',
    () {
      final doc = tableLayout(
        shape: 'roundedRect',
        width: 500,
        height: 100,
        count: 10,
      );
      final seat =
          doc.attachments.firstWhere((a) => a['edge'] == 'top')['seatId']
              as String;
      expect(() => moveTableSeatToSide(doc, seat, 'right'), throwsStateError);
      final locked = doc.copyWith(
        nodes: [
          for (final n in doc.nodes)
            n.id == seat ? n.copyWith(locked: true) : n,
        ],
      );
      expect(
        () => moveTableSeatToSide(locked, seat, 'bottom'),
        throwsStateError,
      );
      expect(doc.nodes.where((n) => n.kind == 'seat').length, 10);
    },
  );

  test(
    'free manual chair keeps its position during side preference resize',
    () {
      final doc = tableLayout(
        shape: 'roundedRect',
        width: 500,
        height: 100,
        count: 10,
      );
      final right =
          doc.attachments.firstWhere((a) => a['edge'] == 'right')['seatId']
              as String;
      final freeId =
          doc.attachments.firstWhere((a) => a['edge'] == 'left')['seatId']
              as String;
      final free = doc.nodes
          .firstWhere((n) => n.id == freeId)
          .copyWith(x: -320, y: 100, properties: {'manual': true});
      final staged = doc.copyWith(
        nodes: [for (final n in doc.nodes) n.id == freeId ? free : n],
        attachments: [
          for (final a in doc.attachments)
            a['seatId'] == freeId ? {...a, 'manual': true} : a,
        ],
      );
      final moved = moveTableSeatToSide(staged, right, 'top');
      final table = moved.nodes.firstWhere((n) => n.kind == 'table');
      final resized = resizeNode(moved, table.id, 550, 130);
      expect(
        resized.nodes.firstWhere((n) => n.id == freeId).toJson(),
        free.toJson(),
      );
    },
  );
}
