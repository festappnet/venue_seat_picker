import 'package:venue_layout_core/venue_layout_core.dart';
import 'scout_reference_data.dart';
import 'reference_hall_seating.dart';

/// Original scout hall: exact seat registration on the 32 x 32 lattice and
/// native editable furniture traced from the original 3000 x 3000 floorplan.
VenueLayoutDocument scoutHall() {
  final root = newLayoutId();
  final nodes = <LayoutNode>[LayoutNode(id: root, kind: 'group', label: 'Sál')];
  final attachments = <Map<String, dynamic>>[];
  void text(String value, double x, double y, double width, double size) {
    nodes.add(
      LayoutNode(
        id: newLayoutId(),
        kind: 'text',
        parentId: root,
        x: x,
        y: y,
        width: width,
        height: size * 1.2,
        label: value,
        properties: {
          'text': value,
          'align': 'center',
          'size': size,
          'lineHeight': 1,
          'bold': false,
          'color': '#000000FF',
          'role': 'decoration',
          'appearanceOverrides': ['color'],
        },
      ),
    );
  }

  void line(List<List<double>> points, {double stroke = 5}) {
    nodes.add(
      shapeFromPoints(
        'polyline',
        points,
        properties: {
          'fill': '#00000000',
          'stroke': '#000000FF',
          'strokeWidth': stroke,
          'role': 'decoration',
          'appearanceOverrides': ['fill', 'stroke', 'strokeWidth'],
        },
      ).copyWith(parentId: root),
    );
  }

  for (final r in scoutArchitecture) {
    final column = r.$1.startsWith('column');
    final room = r.$1 == 'room',
        stage = r.$1 == 'stage',
        entry = r.$1 == 'entry';
    final x = (r.$2 + r.$4) / 2, y = (r.$3 + r.$5) / 2;
    nodes.add(
      LayoutNode(
        id: newLayoutId(),
        kind: 'shape',
        parentId: root,
        x: x,
        y: y,
        width: r.$4 - r.$2,
        height: r.$5 - r.$3,
        z: room ? -40 : -30,
        label: '',
        properties: {
          'shape': 'rect',
          'fill': room
              ? '#FFFFFFFF'
              : column
              ? '#8DA5FFFF'
              : '#E6E6E6FF',
          'stroke': '#000000FF',
          'strokeWidth': 5,
          'cornerRadius': 0,
          'role': column ? 'obstacle' : 'decoration',
          'appearanceOverrides': [
            'fill',
            'stroke',
            'strokeWidth',
            'cornerRadius',
          ],
        },
      ),
    );
    if (stage) text('Pódium', x, y, r.$4 - r.$2 - 60, 100);
    if (entry) text('vstup', x, y, 190, 44);
    if (column) {
      line([
        [r.$2, r.$3],
        [r.$4, r.$5],
      ]);
      line([
        [r.$2, r.$5],
        [r.$4, r.$3],
      ]);
      text('sloup', x, r.$3 - 30, 240, 42);
    }
  }
  text('Taneční parket', 1460, 1250, 1600, 136);
  final tables = <int, LayoutNode>{};
  for (final r in scoutTables) {
    final table = LayoutNode(
      id: newLayoutId(),
      kind: 'table',
      parentId: root,
      x: (r.$2 + r.$4) / 2,
      y: (r.$3 + r.$5) / 2,
      width: r.$4 - r.$2,
      height: r.$5 - r.$3,
      label: '${r.$1}',
      properties: {
        'seatWidth': 77.5,
        'seatHeight': 77.5,
        'seatGap': 11.25,
        'seatSpacing': 22.5,
        'seatEdgePadding': 0,
        'shape': 'rect',
        'size': 70,
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
    seats: scoutSeats,
  );
  final document = VenueLayoutDocument(
    canvas: {
      'x': 0,
      'y': 0,
      'width': 3200,
      'height': 3200,
      'fill': '#FFFFFFFF',
      'floorStyle': 'plain',
    },
    nodes: nodes,
    attachments: attachments,
    sections: [
      {'id': newLayoutId(), 'title': 'Sál', 'rootId': root},
    ],
    appearance: {
      'table': {
        'objectStyle': 'simple',
        'fill': '#FFFFFFFF',
        'stroke': '#000000FF',
        'strokeWidth': 5,
        'cornerRadius': 0,
        'color': '#000000FF',
      },
      'seat': referenceHallSeatAppearance,
      'text': {'color': '#000000FF'},
    },
  );
  return document;
}
