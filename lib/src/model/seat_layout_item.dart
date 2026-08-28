import 'seat_state.dart';

/// Contract implemented by application-specific seat records.
///
/// Persistence, pricing and reservation authority deliberately remain in the
/// host application. The package owns only layout and interaction behavior.
abstract interface class SeatLayoutItem {
  Object? get seatId;
  int get seatRow;
  int get seatColumn;
  SeatState get seatState;
  set seatState(SeatState value);
  String? get seatLabel;
  Object? get seatGroupId;
}
