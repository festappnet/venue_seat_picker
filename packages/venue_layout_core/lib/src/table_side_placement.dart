import 'model.dart';
import 'geometry.dart';
import 'table_seating.dart';

const tableSeatSides = ['top', 'right', 'bottom', 'left'];

bool supportsTableSeatSides(LayoutNode table) =>
    table.kind == 'table' &&
    !isBarNode(table) &&
    const [
      null,
      'rect',
      'rectangle',
      'roundedRect',
    ].contains(table.properties['shape']);

/// Native imports may keep the desk and its chairs as siblings in one group.
LayoutNode? tableForSeat(VenueLayoutDocument document, LayoutNode seat) {
  final nodes = {for (final n in document.nodes) n.id: n};
  final parent = nodes[seat.parentId];
  if (parent?.kind == 'table') return parent;
  if (parent?.kind != 'group' || parent?.properties['assembly'] != null)
    return null;
  final desks = document.nodes
      .where((n) => n.parentId == parent!.id && n.kind == 'table')
      .toList();
  return desks.length == 1 ? desks.single : null;
}

String? tableSideForSeat(VenueLayoutDocument document, LayoutNode seat) {
  final table = tableForSeat(document, seat);
  if (table == null || !supportsTableSeatSides(table)) return null;
  final anchor = document.attachments
      .where((a) => a['seatId'] == seat.id && a['targetId'] == table.id)
      .firstOrNull;
  if (tableSeatSides.contains(anchor?['edge']))
    return anchor!['edge'] as String;
  final local = multiplyMatrix(
    inverseMatrix(worldMatrix(document, table)),
    worldMatrix(document, seat),
  );
  return local[4].abs() / table.width > local[5].abs() / table.height
      ? (local[4] < 0 ? 'left' : 'right')
      : (local[5] < 0 ? 'top' : 'bottom');
}

VenueLayoutDocument _attachNativeChairs(
  VenueLayoutDocument document,
  LayoutNode seat,
) {
  final table = tableForSeat(document, seat);
  if (table == null || seat.parentId == table.id) return document;
  final peers = document.nodes
      .where((n) => n.kind == 'seat' && n.parentId == seat.parentId)
      .toList();
  final inverse = inverseMatrix(worldMatrix(document, table));
  final replacements = <String, LayoutNode>{};
  final anchors = <String, Map<String, dynamic>>{};
  for (final chair in peers) {
    final matrix = multiplyMatrix(inverse, worldMatrix(document, chair));
    final side = tableSideForSeat(document, chair)!;
    final horizontal = side == 'top' || side == 'bottom';
    final position = horizontal ? matrix[4] : matrix[5];
    final length = horizontal ? table.width : table.height;
    final gap =
        (horizontal
            ? matrix[5].abs() - table.height / 2
            : matrix[4].abs() - table.width / 2) -
        chair.height / 2;
    replacements[chair.id] = chair.copyWith(
      parentId: table.id,
      x: matrix[4],
      y: matrix[5],
      rotation: chair.rotation - table.rotation,
    );
    final old = document.attachments
        .where((a) => a['seatId'] == chair.id)
        .firstOrNull;
    anchors[chair.id] = {
      ...?old,
      'seatId': chair.id,
      'targetId': table.id,
      'kind': 'edge',
      'edge': side,
      't': (position / length + .5).clamp(0, 1),
      'gap': gap.clamp(0, double.maxFinite),
      'x': matrix[4],
      'y': matrix[5],
      'rotation': chair.rotation - table.rotation,
    };
  }
  return document.copyWith(
    nodes: [for (final n in document.nodes) replacements[n.id] ?? n],
    attachments: [
      for (final a in document.attachments)
        if (!anchors.containsKey(a['seatId'])) a,
      ...anchors.values,
    ],
  );
}

/// Side preferences use edge attachments marked manual, without marking the
/// chair freely positioned. Free manual chairs retain both manual flags.
VenueLayoutDocument moveTableSeatToSide(
  VenueLayoutDocument document,
  String seatId,
  String side,
) {
  if (!tableSeatSides.contains(side)) throw ArgumentError('Invalid table side');
  if (tableSideForSeat(
        document,
        document.nodes.firstWhere((n) => n.id == seatId),
      ) ==
      side)
    return document;
  document = _attachNativeChairs(
    document,
    document.nodes.firstWhere((n) => n.id == seatId),
  );
  final seat = document.nodes.firstWhere((n) => n.id == seatId);
  final table = document.nodes.firstWhere((n) => n.id == seat.parentId);
  if (seat.kind != 'seat' || !supportsTableSeatSides(table))
    throw ArgumentError('Select a chair at a rectangular table');
  final anchors = {for (final a in document.attachments) a['seatId']: a};
  final old = anchors[seatId];
  if (old == null ||
      old['targetId'] != table.id ||
      !tableSeatSides.contains(old['edge']))
    throw StateError('Chair has no table side');
  if (old['edge'] == side) return document;
  final affected = {old['edge'], side};
  final ids = {
    for (final n in document.nodes)
      if (n.parentId == table.id &&
          n.kind == 'seat' &&
          (n.id == seatId ||
              (affected.contains(anchors[n.id]?['edge']) &&
                  n.properties['manual'] != true)))
        n.id,
  };
  final byId = {for (final n in document.nodes) n.id: n};
  for (final id in {...ids, table.id}) {
    LayoutNode? node = byId[id];
    while (node != null) {
      if (node.locked) throw StateError('Locked object ${node.id}');
      node = byId[node.parentId];
    }
  }
  final staged = document.copyWith(
    nodes: [
      for (final n in document.nodes)
        if (n.id == seatId)
          n.copyWith(properties: {...n.properties, 'manual': false})
        else
          n,
    ],
    attachments: [
      for (final a in document.attachments)
        if (ids.contains(a['seatId']))
          {...a, 'manual': true, if (a['seatId'] == seatId) 'edge': side}
        else
          a,
    ],
  );
  return reflowPreferredTableSides(staged, table.id);
}

/// Recompute authored side rows before ordinary table reflow. Their anchors
/// remain fixed for the automatic allocator, while free manual chairs stay put.
VenueLayoutDocument reflowPreferredTableSides(
  VenueLayoutDocument document,
  String tableId,
) {
  final table = document.nodes.firstWhere((n) => n.id == tableId);
  if (!supportsTableSeatSides(table)) return document;
  final anchors = {for (final a in document.attachments) a['seatId']: a};
  final chairs = document.nodes
      .where((n) => n.parentId == tableId && n.kind == 'seat')
      .toList();
  final rules = TableSeating.fromDocument(document, table);
  final replacements = <String, LayoutNode>{};
  final updated = <String, Map<String, dynamic>>{};
  for (final side in tableSeatSides) {
    final row =
        chairs
            .where(
              (n) =>
                  n.properties['manual'] != true &&
                  anchors[n.id]?['manual'] == true &&
                  anchors[n.id]?['edge'] == side,
            )
            .toList()
          ..sort(
            (a, b) => ((anchors[a.id]?['t'] as num?) ?? 0).compareTo(
              (anchors[b.id]?['t'] as num?) ?? 0,
            ),
          );
    if (row.isEmpty) continue;
    final horizontal = side == 'top' || side == 'bottom';
    final length = horizontal ? table.width : table.height;
    final largestWidth = row
        .map((n) => n.width)
        .reduce((a, b) => a > b ? a : b);
    if (row.length * largestWidth + (row.length - 1) * rules.spacing >
        length - 2 * rules.edgePadding + 1e-7) {
      throw StateError('Not enough room on the selected table side');
    }
    for (var i = 0; i < row.length; i++) {
      final seat = row[i], t = (i + .5) / row.length;
      final gap = (anchors[seat.id]?['gap'] as num?)?.toDouble() ?? rules.gap;
      final offset = seat.height / 2 + gap;
      final x = horizontal
          ? (t - .5) * table.width
          : (side == 'left' ? -1 : 1) * (table.width / 2 + offset);
      final y = !horizontal
          ? (t - .5) * table.height
          : (side == 'top' ? -1 : 1) * (table.height / 2 + offset);
      final rotation = <String, double>{
        'top': 180,
        'right': 270,
        'bottom': 0,
        'left': 90,
      }[side]!;
      final next = seat.copyWith(
        x: quantize(x),
        y: quantize(y),
        rotation: seat.properties['manualRotation'] == true
            ? seat.rotation
            : rotation,
      );
      if (seat.locked &&
          (next.x != seat.x ||
              next.y != seat.y ||
              next.rotation != seat.rotation))
        throw StateError('Locked object ${seat.id}');
      replacements[seat.id] = next;
      updated[seat.id] = {
        ...anchors[seat.id]!,
        'kind': 'edge',
        'edge': side,
        't': t,
        'x': next.x,
        'y': next.y,
        'rotation': next.rotation,
        'gap': gap,
      };
    }
  }
  if (replacements.isEmpty) return document;
  final result = document.copyWith(
    nodes: [for (final n in document.nodes) replacements[n.id] ?? n],
    attachments: [
      for (final a in document.attachments) updated[a['seatId']] ?? a,
    ],
  );
  final matrices = worldMatrices(result);
  final physical = result.nodes
      .where(
        (n) =>
            n.kind == 'seat' ||
            n.kind == 'table' ||
            n.properties['obstacle'] == true,
      )
      .toList();
  for (final seat in replacements.values) {
    final hull = worldHull(seat, matrices[seat.id]!);
    if (hull.any(
      (p) =>
          p[0] < (result.canvas['x'] as num) - 1e-7 ||
          p[1] < (result.canvas['y'] as num) - 1e-7 ||
          p[0] >
              (result.canvas['x'] as num) +
                  (result.canvas['width'] as num) +
                  1e-7 ||
          p[1] >
              (result.canvas['y'] as num) +
                  (result.canvas['height'] as num) +
                  1e-7,
    ))
      throw StateError('Chair is outside the canvas');
    for (final other in physical) {
      if (other.id != seat.id &&
          polygonsOverlap(hull, worldHull(other, matrices[other.id]!)))
        throw StateError('Not enough room on the selected table side');
    }
  }
  return result;
}
