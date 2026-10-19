import 'package:venue_layout_core/venue_layout_core.dart';
import 'reference_hall_seating.dart';
import 'scout_balcony_reference_data.dart';

/// Scout ball on 6 February 2026: original hall, balcony and all 249 seats.
/// The source's group 22 is seating without a drawn table, retained as such.
VenueLayoutDocument scoutBalconyHall() {
  final hall = newLayoutId(), balcony = newLayoutId();
  final nodes = <LayoutNode>[
    LayoutNode(id: hall, kind: 'group', label: 'Sál'),
    LayoutNode(id: balcony, kind: 'group', label: 'Balkón'),
  ];
  final attachments = <Map<String, dynamic>>[];
  void rect(
    String root,
    double x,
    double y,
    double w,
    double h,
    String fill, {
    String stroke = '#172C51FF',
    int z = -40,
  }) {
    nodes.add(
      LayoutNode(
        id: newLayoutId(),
        kind: 'shape',
        parentId: root,
        x: x + w / 2,
        y: y + h / 2,
        width: w,
        height: h,
        z: z,
        properties: {
          'shape': 'rect',
          'fill': fill,
          'stroke': stroke,
          'strokeWidth': 3.52,
          'cornerRadius': 0,
          'role': 'decoration',
          'appearanceOverrides': [
            'fill',
            'stroke',
            'strokeWidth',
            'cornerRadius',
          ],
        },
      ),
    );
  }

  void label(
    String root,
    String value,
    double x,
    double y,
    double w,
    double size, {
    double rotation = 0,
  }) {
    nodes.add(
      LayoutNode(
        id: newLayoutId(),
        kind: 'text',
        parentId: root,
        x: x,
        y: y,
        width: w,
        height: size * 1.3,
        rotation: rotation,
        label: value,
        properties: {
          'text': value,
          'size': size,
          'align': 'center',
          'bold': true,
          'color': '#000000FF',
          'role': 'decoration',
          'appearanceOverrides': ['color'],
        },
      ),
    );
  }

  // Original SVG normalized to the source's 28 x 52 seat lattice.
  const sx = 2800 / 3653, sy = 5200 / 6761;
  rect(hall, .499836 * sx, .499836 * sy, 3638 * sx, 5457 * sy, '#F2F2F2FF');
  rect(balcony, .499836 * sx, 5457.5 * sy, 3638 * sx, 1299 * sy, '#DEEBF7FF');
  for (var i = 0; i < 16; i++) {
    rect(
      balcony,
      3308.5 * sx,
      (5458.5 + i * 54.9) * sy,
      325 * sx,
      55 * sy,
      '#D9D9D9FF',
      stroke: '#BFBFBFFF',
      z: -30,
    );
  }
  label(hall, 'Pódium', 1820 * sx, 190 * sy, 1200 * sx, 125);
  label(hall, 'Bar', 280 * sx, 5275 * sy, 500 * sx, 127);
  label(hall, 'Vstup', 3380 * sx, 5275 * sy, 500 * sx, 127);
  label(balcony, 'Balkón', 1820 * sx, 6500 * sy, 1200 * sx, 125);
  label(
    balcony,
    'Schodiště',
    3470 * sx,
    5895 * sy,
    850 * sy,
    113,
    rotation: 270,
  );
  final tables = <int, LayoutNode>{};
  for (final r in scoutBalconyTables) {
    final vertical = r.$5 - r.$3 > r.$4 - r.$2;
    final table = LayoutNode(
      id: newLayoutId(),
      kind: 'table',
      parentId: r.$1 >= 16 ? balcony : hall,
      x: (r.$2 + r.$4) / 2,
      y: (r.$3 + r.$5) / 2,
      width: vertical ? r.$5 - r.$3 : r.$4 - r.$2,
      height: vertical ? r.$4 - r.$2 : r.$5 - r.$3,
      rotation: vertical ? 270 : 0,
      label: 'Stůl ${r.$1}',
      properties: {
        'seatWidth': 77.5,
        'seatHeight': 77.5,
        'seatGap': 11.25,
        'seatSpacing': 22.5,
        'seatEdgePadding': 0,
        'shape': 'rect',
        'size': 98,
        'labelOrientation': 'object',
        'lineHeight': 1,
        'bold': true,
      },
    );
    nodes.add(table);
    tables[r.$1] = table;
  }
  addReferenceHallSeats(
    nodes: nodes,
    attachments: attachments,
    tables: tables,
    seats: scoutBalconySeats.where((s) => s.$1 != 22).toList(),
  );
  final extra = newLayoutId();
  nodes.add(LayoutNode(id: extra, kind: 'group', parentId: hall, label: '22'));
  for (final s in scoutBalconySeats.where((s) => s.$1 == 22)) {
    nodes.add(
      LayoutNode(
        id: newLayoutId(),
        kind: 'seat',
        parentId: extra,
        x: (s.$3 + .5) * 100,
        y: (s.$4 + .5) * 100,
        width: referenceHallSeatSize,
        height: referenceHallSeatSize,
        label: s.$2,
        properties: {'symbol': 'chair', 'manual': true},
      ),
    );
  }
  final document = VenueLayoutDocument(
    canvas: {
      'x': 0,
      'y': 0,
      'width': 2800,
      'height': 5200,
      'fill': '#FFFFFFFF',
      'floorStyle': 'plain',
    },
    nodes: nodes,
    attachments: attachments,
    sections: [
      {'id': newLayoutId(), 'title': 'Sál', 'rootId': hall},
      {'id': newLayoutId(), 'title': 'Balkón', 'rootId': balcony},
    ],
    appearance: {
      'table': {
        'objectStyle': 'simple',
        'fill': '#D0D5C9FF',
        'stroke': '#666666FF',
        'strokeWidth': 3.61,
        'cornerRadius': 15,
        'color': '#000000FF',
      },
      'seat': referenceHallSeatAppearance,
      'text': {'color': '#000000FF'},
    },
  );
  return document;
}
