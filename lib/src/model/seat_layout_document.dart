import 'basic_seat.dart';
import 'seat_layout_background.dart';

/// Portable JSON document used by the built-in editor and example application.
class SeatLayoutDocument {
  const SeatLayoutDocument({
    required this.rows,
    required this.columns,
    required this.seats,
    this.background,
    this.schemaVersion = 1,
  });

  final int schemaVersion;
  final int rows;
  final int columns;
  final List<BasicSeat> seats;
  final SeatLayoutBackground? background;

  factory SeatLayoutDocument.fromJson(Map<String, Object?> json) {
    final version = json['schemaVersion'] as int? ?? 1;
    if (version != 1) {
      throw FormatException('Unsupported seat layout schema version: $version');
    }
    return SeatLayoutDocument(
      schemaVersion: version,
      rows: json['rows']! as int,
      columns: json['columns']! as int,
      seats: (json['seats']! as List)
          .cast<Map>()
          .map((value) => BasicSeat.fromJson(value.cast<String, Object?>()))
          .toList(),
      background: switch (json['background']) {
        final String source when source.isNotEmpty =>
          SeatLayoutBackground.parse(source),
        _ => null,
      },
    );
  }

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'rows': rows,
        'columns': columns,
        'seats': seats.map((seat) => seat.toJson()).toList(),
        if (background != null) 'background': background!.source,
      };
}
