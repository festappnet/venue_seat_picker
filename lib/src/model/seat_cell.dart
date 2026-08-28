import 'seat_layout_item.dart';
import 'seat_state.dart';

/// Runtime cell state, including temporary interaction highlights.
class SeatCell<T extends SeatLayoutItem> {
  SeatCell({
    required this.row,
    required this.column,
    required this.size,
    required this.state,
    this.item,
  });

  final int row;
  final int column;
  final double size;
  T? item;
  SeatState state;
  bool isSwapHighlighted = false;
  bool isGroupHighlighted = false;
  bool isTooltipHighlighted = false;

  @override
  bool operator ==(Object other) =>
      other is SeatCell<T> && other.row == row && other.column == column;

  @override
  int get hashCode => Object.hash(row, column);
}
