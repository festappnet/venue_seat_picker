import 'seat_layout_item.dart';
import 'seat_state.dart';

/// Ready-to-use, serializable seat model for applications without a custom one.
class BasicSeat implements SeatLayoutItem {
  @override
  final Object? seatId;
  @override
  final int seatRow;
  @override
  final int seatColumn;
  @override
  SeatState seatState;
  @override
  final String? seatLabel;
  @override
  final Object? seatGroupId;
  final Map<String, Object?> metadata;

  BasicSeat({
    required this.seatId,
    required this.seatRow,
    required this.seatColumn,
    this.seatState = SeatState.available,
    this.seatLabel,
    this.seatGroupId,
    this.metadata = const {},
  });

  factory BasicSeat.fromJson(Map<String, Object?> json) => BasicSeat(
        seatId: json['id'],
        seatRow: json['row']! as int,
        seatColumn: json['column']! as int,
        seatState: SeatState.fromWireName(json['state']! as String),
        seatLabel: json['label'] as String?,
        seatGroupId: json['group'],
        metadata:
            (json['metadata'] as Map?)?.cast<String, Object?>() ?? const {},
      );

  Map<String, Object?> toJson() => {
        'id': seatId,
        'row': seatRow,
        'column': seatColumn,
        'state': seatState.wireName,
        if (seatLabel != null) 'label': seatLabel,
        if (seatGroupId != null) 'group': seatGroupId,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };
}
