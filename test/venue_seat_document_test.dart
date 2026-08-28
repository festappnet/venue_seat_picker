import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

void main() {
  test('round trips the versioned venue document', () {
    final document = VenueSeatDocument(
      rows: 2,
      columns: 3,
      backdrop: const SvgVenueBackdrop('<svg></svg>'),
      seats: const [
        VenueSeat(
          id: 'A1',
          position: SeatPosition(0, 1),
          status: SeatStatus.booked,
          label: 'A1',
          metadata: {'priceBand': 'gold'},
        ),
      ],
    );

    final decoded = VenueSeatDocument.fromJson(document.toJson());
    expect(decoded.schemaVersion, 1);
    expect(decoded.rows, 2);
    expect(decoded.seats.single.status, SeatStatus.booked);
    expect(decoded.seats.single.metadata['priceBand'], 'gold');
    expect(decoded.backdrop?.source, '<svg></svg>');
  });

  test('rejects unknown status values', () {
    expect(() => SeatStatus.fromWireName('not-a-status'), throwsFormatException);
  });
}
