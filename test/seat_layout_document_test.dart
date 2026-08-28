import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

void main() {
  test('round trips the versioned JSON document', () {
    final document = SeatLayoutDocument(
      rows: 2,
      columns: 3,
      background: const SvgSeatLayoutBackground('<svg></svg>'),
      seats: [
        BasicSeat(
          seatId: 'A1',
          seatRow: 0,
          seatColumn: 1,
          seatState: SeatState.selectedByMe,
          seatLabel: 'A1',
          metadata: const {'priceBand': 'gold'},
        ),
      ],
    );

    final decoded = SeatLayoutDocument.fromJson(document.toJson());
    expect(decoded.schemaVersion, 1);
    expect(decoded.rows, 2);
    expect(decoded.seats.single.seatState, SeatState.selectedByMe);
    expect(decoded.seats.single.metadata['priceBand'], 'gold');
    expect(decoded.background?.source, '<svg></svg>');
  });

  test('accepts the legacy black wire state as blocked', () {
    expect(SeatState.fromWireName('black'), SeatState.blocked);
  });
}
