import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

void main() {
  test('builds a complete grid and keeps the host model canonical', () {
    final seat = BasicSeat(
      seatId: 'A1',
      seatRow: 0,
      seatColumn: 0,
    );
    final controller = SeatLayoutController<BasicSeat>()
      ..loadLayout(rows: 2, columns: 3, items: [seat]);

    expect(controller.cells, hasLength(6));
    expect(controller.cellAt(0, 0)?.item, same(seat));
    expect(controller.cellAt(1, 2)?.state, SeatState.empty);

    controller.updateSeat(controller.cellAt(0, 0)!, SeatState.ordered);
    expect(seat.seatState, SeatState.ordered);
    controller.dispose();
  });

  test('temporary visual state does not mutate the host model', () {
    final seat = BasicSeat(
      seatId: 'A1',
      seatRow: 0,
      seatColumn: 0,
    );
    final controller = SeatLayoutController<BasicSeat>()
      ..loadLayout(rows: 1, columns: 1, items: [seat]);
    final cell = controller.cellAt(0, 0)!;

    controller.updateVisualState(cell, SeatState.selectedByMe);
    expect(cell.state, SeatState.selectedByMe);
    expect(seat.seatState, SeatState.available);

    controller.restoreVisualState(cell);
    expect(cell.state, SeatState.available);
    controller.dispose();
  });

  test('rejects duplicate and out-of-range coordinates', () {
    final controller = SeatLayoutController<BasicSeat>();
    BasicSeat seat(String id, int row, int column) => BasicSeat(
          seatId: id,
          seatRow: row,
          seatColumn: column,
        );

    expect(
      () => controller.loadLayout(
        rows: 2,
        columns: 2,
        items: [seat('A', 0, 0), seat('B', 0, 0)],
      ),
      throwsArgumentError,
    );
    expect(
      () => controller.loadLayout(
        rows: 2,
        columns: 2,
        items: [seat('A', 3, 0)],
      ),
      throwsArgumentError,
    );
    controller.dispose();
  });

  test('refuses to resize across an occupied cell', () {
    final controller = SeatLayoutController<BasicSeat>()
      ..loadLayout(
        rows: 3,
        columns: 3,
        items: [
          BasicSeat(seatId: 'C3', seatRow: 2, seatColumn: 2),
        ],
      );

    expect(controller.setDimensions(2, 3), isFalse);
    expect(controller.rows, 3);
    expect(controller.setDimensions(4, 3), isTrue);
    controller.dispose();
  });
}
