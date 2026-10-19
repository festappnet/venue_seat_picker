import 'model.dart';

/// Physical seating rules, independent of colors and material families.
class TableSeating {
  const TableSeating({
    this.width = 40,
    this.height = 40,
    this.gap = 12,
    this.spacing = 12,
    this.edgePadding = 12,
  });
  final double width, height, gap, spacing, edgePadding;
  double get pitch => width + spacing;
  double get offset => height / 2 + gap;
  TableSeating withGap(double value) => copyWith(gap: value);
  TableSeating copyWith({
    double? width,
    double? height,
    double? gap,
    double? spacing,
    double? edgePadding,
  }) => TableSeating(
    width: width ?? this.width,
    height: height ?? this.height,
    gap: gap ?? this.gap,
    spacing: spacing ?? this.spacing,
    edgePadding: edgePadding ?? this.edgePadding,
  );
  factory TableSeating.fromTable(LayoutNode table) => TableSeating(
    width: (table.properties['seatWidth'] as num? ?? 40).toDouble(),
    height: (table.properties['seatHeight'] as num? ?? 40).toDouble(),
    gap: (table.properties['seatGap'] as num? ?? 12).toDouble(),
    spacing: (table.properties['seatSpacing'] as num? ?? 12).toDouble(),
    edgePadding: (table.properties['seatEdgePadding'] as num? ?? 12).toDouble(),
  );
  factory TableSeating.fromDocument(
    VenueLayoutDocument doc,
    LayoutNode table, {
    String? excludeSeatId,
  }) {
    final peers = doc.nodes
        .where(
          (n) =>
              n.kind == 'seat' &&
              n.parentId == table.id &&
              n.id != excludeSeatId,
        )
        .toList();
    final base = TableSeating.fromTable(table);
    if (peers.isEmpty) return base;
    final sizes = <String, (int, LayoutNode)>{};
    for (final seat in peers) {
      final key = '${seat.width}:${seat.height}';
      sizes[key] = ((sizes[key]?.$1 ?? 0) + 1, seat);
    }
    final dominant = sizes.values.reduce((a, b) => a.$1 >= b.$1 ? a : b).$2;
    final gaps =
        doc.attachments
            .where(
              (a) =>
                  a['targetId'] == table.id &&
                  a['seatId'] != excludeSeatId &&
                  a['gap'] is num,
            )
            .map((a) => (a['gap'] as num).toDouble())
            .toList()
          ..sort();
    return TableSeating(
      width: table.properties.containsKey('seatWidth')
          ? base.width
          : dominant.width,
      height: table.properties.containsKey('seatHeight')
          ? base.height
          : dominant.height,
      gap: table.properties.containsKey('seatGap') || gaps.isEmpty
          ? base.gap
          : gaps[gaps.length ~/ 2],
      spacing: base.spacing,
      edgePadding: base.edgePadding,
    );
  }
  Map<String, dynamic> get properties => {
    'seatWidth': width,
    'seatHeight': height,
    'seatGap': gap,
    'seatSpacing': spacing,
    'seatEdgePadding': edgePadding,
  };
}

/// Palette chairs match the prevailing physical size in the current document.
TableSeating documentSeating(VenueLayoutDocument doc) {
  final seats = doc.nodes
      .where((n) => n.kind == 'seat' && n.properties['furniture'] != 'cushion')
      .toList();
  final style = doc.appearance['table'] as Map? ?? const {};
  TableSeating defaults(TableSeating value) => value.copyWith(
    width: (style['seatWidth'] as num?)?.toDouble(),
    height: (style['seatHeight'] as num?)?.toDouble(),
    gap: (style['seatGap'] as num?)?.toDouble(),
    spacing: (style['seatSpacing'] as num?)?.toDouble(),
    edgePadding: (style['seatEdgePadding'] as num?)?.toDouble(),
  );
  if (seats.isEmpty) return defaults(const TableSeating());
  final counts = <String, (int, LayoutNode)>{};
  for (final seat in seats) {
    final key = '${seat.width}:${seat.height}';
    counts[key] = ((counts[key]?.$1 ?? 0) + 1, seat);
  }
  final seat = counts.values.reduce((a, b) => a.$1 >= b.$1 ? a : b).$2;
  final parent = doc.nodes
      .where((n) => n.id == seat.parentId && n.kind == 'table')
      .firstOrNull;
  return defaults(
    parent == null
        ? TableSeating(width: seat.width, height: seat.height)
        : TableSeating.fromDocument(doc, parent),
  );
}
