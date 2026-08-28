import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

void main() {
  testWidgets('rolls an optimistic selection back when rejected',
      (tester) async {
    final seat = BasicSeat(seatId: 'A1', seatRow: 0, seatColumn: 0);
    final controller = SeatLayoutController<BasicSeat>()
      ..loadLayout(rows: 1, columns: 1, items: [seat]);
    final request = Completer<bool>();
    final selections = <List<SeatCell<BasicSeat>>>[];

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 200,
          height: 200,
          child: SeatPicker<BasicSeat>(
            controller: controller,
            onSelectionRequest: (cell, selected) => request.future,
            onSelectionChanged: (value) => selections.add(value),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(SeatTile));
    await tester.pump();
    expect(controller.cellAt(0, 0)?.state, SeatState.selectedByMe);
    expect(seat.seatState, SeatState.available);

    request.complete(false);
    await tester.pump();
    expect(controller.cellAt(0, 0)?.state, SeatState.available);
    expect(selections.last, isEmpty);
    controller.dispose();
  });

  testWidgets('enforces the selection limit without calling the backend',
      (tester) async {
    final seats = [
      BasicSeat(
        seatId: 'A1',
        seatRow: 0,
        seatColumn: 0,
        seatState: SeatState.selectedByMe,
      ),
      BasicSeat(seatId: 'A2', seatRow: 0, seatColumn: 1),
    ];
    final controller = SeatLayoutController<BasicSeat>()
      ..loadLayout(rows: 1, columns: 2, items: seats);
    var requests = 0;
    var limits = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 300,
          height: 200,
          child: SeatPicker<BasicSeat>(
            controller: controller,
            maxSelection: 1,
            onSelectionRequest: (cell, selected) async {
              requests++;
              return true;
            },
            onLimitReached: () => limits++,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(SeatTile).last);
    await tester.pump();
    expect(requests, 0);
    expect(limits, 1);
    controller.dispose();
  });

  testWidgets('rolls back and reports a thrown reservation error',
      (tester) async {
    final seat = BasicSeat(seatId: 'A1', seatRow: 0, seatColumn: 0);
    final controller = SeatLayoutController<BasicSeat>()
      ..loadLayout(rows: 1, columns: 1, items: [seat]);
    Object? reported;

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 200,
          height: 200,
          child: SeatPicker<BasicSeat>(
            controller: controller,
            onSelectionRequest: (cell, selected) async =>
                throw StateError('reservation failed'),
            onSelectionError: (error, stackTrace) => reported = error,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(SeatTile));
    await tester.pump();

    expect(reported, isA<StateError>());
    expect(controller.cellAt(0, 0)?.state, SeatState.available);
    controller.dispose();
  });

  testWidgets('long press opens the tooltip without selecting', (tester) async {
    final seat = BasicSeat(
      seatId: 'A1',
      seatRow: 0,
      seatColumn: 0,
      seatLabel: 'Front row',
    );
    final controller = SeatLayoutController<BasicSeat>()
      ..loadLayout(rows: 1, columns: 1, items: [seat]);
    var requests = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 200,
          height: 200,
          child: SeatPicker<BasicSeat>(
            controller: controller,
            onSelectionRequest: (cell, selected) async {
              requests++;
              return true;
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.longPress(find.byType(SeatTile));
    await tester.pump();

    expect(find.text('Front row'), findsOneWidget);
    expect(requests, 0);
    expect(seat.seatState, SeatState.available);
    controller.dispose();
  });

  testWidgets('settles a pending request after the picker unmounts',
      (tester) async {
    final seat = BasicSeat(seatId: 'A1', seatRow: 0, seatColumn: 0);
    final controller = SeatLayoutController<BasicSeat>()
      ..loadLayout(rows: 1, columns: 1, items: [seat]);
    final request = Completer<bool>();

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 200,
          height: 200,
          child: SeatPicker<BasicSeat>(
            controller: controller,
            onSelectionRequest: (cell, selected) => request.future,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(SeatTile));
    await tester.pump();
    expect(controller.cellAt(0, 0)?.state, SeatState.selectedByMe);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    request.complete(false);
    await tester.pump();

    expect(controller.cellAt(0, 0)?.state, SeatState.available);
    expect(seat.seatState, SeatState.available);
    controller.dispose();
  });

  testWidgets('ignores duplicate taps while a request is pending',
      (tester) async {
    final seat = BasicSeat(seatId: 'A1', seatRow: 0, seatColumn: 0);
    final controller = SeatLayoutController<BasicSeat>()
      ..loadLayout(rows: 1, columns: 1, items: [seat]);
    final request = Completer<bool>();
    var requests = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 200,
          height: 200,
          child: SeatPicker<BasicSeat>(
            controller: controller,
            onSelectionRequest: (cell, selected) {
              requests++;
              return request.future;
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(SeatTile));
    await tester.tap(find.byType(SeatTile));
    await tester.pump();

    expect(requests, 1);
    request.complete(true);
    await tester.pump();
    controller.dispose();
  });
}
