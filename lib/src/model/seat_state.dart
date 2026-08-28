/// Visual and interaction state of a cell in a venue layout.
enum SeatState {
  /// No seat occupies this cell.
  empty,

  /// The seat can be selected.
  available,

  /// The seat is selected by another visitor.
  selected,

  /// The seat is selected by the current visitor.
  selectedByMe,

  /// The seat has been ordered and cannot be selected.
  ordered,

  /// The ticket associated with this seat has already been used.
  used,

  /// The cell is intentionally blocked or decorative.
  blocked;

  String get wireName => switch (this) {
        SeatState.selectedByMe => 'selected_by_me',
        SeatState.blocked => 'blocked',
        _ => name,
      };

  static SeatState fromWireName(String value) => switch (value) {
        'selected_by_me' => SeatState.selectedByMe,
        'black' || 'blocked' => SeatState.blocked,
        'available' => SeatState.available,
        'selected' => SeatState.selected,
        'ordered' => SeatState.ordered,
        'used' => SeatState.used,
        'empty' => SeatState.empty,
        _ => throw FormatException('Unknown seat state: $value'),
      };
}
