import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

void main() {
  test(
    'painting lattice starts at the gesture origin and retains whole modules',
    () {
      final brush = GridSurfaceBrush(originX: 237, originY: 319);
      brush.paint(287, 369);
      final first = brush.node(id: newLayoutId());
      expect(first.x, 287);
      expect(first.y, 369);
      expect(first.width, tableSurfaceModuleSize);
      brush.paint(487, 369);
      expect(brush.cellCount, 3);
      expect(brush.node(id: first.id).width, tableSurfaceModuleSize * 3);
    },
  );
  test(
    'custom surface family radius changes the canonical outline and corner hits',
    () {
      final brush = GridSurfaceBrush();
      brush.paint(350, 350);
      final node = brush.node(id: newLayoutId());
      final base = VenueLayoutDocument(nodes: [node]);
      List path(VenueLayoutDocument d) =>
          (compileScene(d)['items'] as List).singleWhere(
                (i) => i['id'] == node.id,
              )['path']
              as List;
      final wood = withLayoutMaterialFamily(base, 'wood');
      final lounge = withLayoutMaterialFamily(base, 'lounge');
      expect(path(wood), isNot(equals(path(lounge))));
      expect(path(lounge).where((c) => c[0] == 'Q'), hasLength(4));
      expect(hitTest(wood, 303, 303), node.id);
      expect(hitTest(lounge, 303, 303), isNull);
      expect(hitTest(lounge, 350, 350), node.id);
      expect(lounge.nodes.single.toJson(), node.toJson());
      final square = lounge.copyWith(
        appearance: {
          ...lounge.appearance,
          'table': {...lounge.appearance['table'] as Map, 'cornerRadius': 0},
        },
      );
      expect(path(square).where((c) => c[0] == 'Q'), isEmpty);
      expect(hitTest(square, 301, 301), node.id);
    },
  );
  test(
    'rounded concave surface and holes remain finite under oversized radius',
    () {
      final brush = GridSurfaceBrush(step: barSurfaceModuleSize);
      for (final point in [
        [330, 330],
        [510, 330],
        [510, 510],
        [330, 510],
        [330, 330],
      ]) {
        brush.paint(point[0].toDouble(), point[1].toDouble());
      }
      final node = brush.node(id: newLayoutId(), bar: true);
      final d = VenueLayoutDocument(
        nodes: [node],
        appearance: {
          'table': {'cornerRadius': 200},
        },
      );
      final path =
          (compileScene(d)['items'] as List).singleWhere(
                (i) => i['id'] == node.id,
              )['path']
              as List;
      expect(path.where((c) => c[0] == 'Z'), hasLength(2));
      expect(
        path
            .expand((c) => (c as List).skip(1))
            .every((v) => (v as num).isFinite),
        true,
      );
      expect(hitTest(d, 420, 420), isNull);
      expect(validateDocument(d), isEmpty);
      expect(barSurfaceModuleSize, lessThan(tableSurfaceModuleSize));
    },
  );
  for (final polygon in [false, true]) {
    test(
      'moving ${polygon ? 'custom' : 'rectangular'} table relocates its chairs around a neighbour',
      () {
        final brush = GridSurfaceBrush(originX: 300, originY: 300);
        brush.paint(350, 350);
        brush.paint(550, 350);
        brush.paint(450, 350);
        brush.paint(450, 450);
        final root = brush.node(id: newLayoutId());
        final before = polygon
            ? reflowTable(VenueLayoutDocument(nodes: [root]), root.id, 6)
            : tableLayout(
                shape: 'rect',
                count: 6,
                x: 400,
                y: 400,
                width: 240,
                height: 140,
              );
        final table = before.nodes.firstWhere((n) => n.kind == 'table');
        final seat = before.nodes.firstWhere((n) => n.kind == 'seat');
        final seatMatrix = worldMatrix(before, seat);
        final obstacle = LayoutNode(
          id: newLayoutId(),
          kind: 'seat',
          x: seatMatrix[4] + 600,
          y: seatMatrix[5],
          width: 40,
          height: 40,
        );
        final document = before.copyWith(nodes: [...before.nodes, obstacle]);
        final moved = moveLayoutWithinCanvas(document, {table.id}, dx: 600);
        expect(
          moved.nodes.firstWhere((n) => n.id == table.id).x,
          table.x + 600,
        );
        expect(moved.nodes.map((n) => n.id), document.nodes.map((n) => n.id));
        expect(layoutCollisions(moved), isEmpty);
        expect(moved.nodes.last.toJson(), obstacle.toJson());
        expect(
          moved.attachments.map((a) => a['seatId']),
          before.attachments.map((a) => a['seatId']),
        );
        expect(validateDocument(moved), isEmpty);
      },
    );
  }
  test('blocked perimeter rejects the move without losing seats', () {
    final before = tableLayout(shape: 'rect', count: 6, x: 300, y: 300);
    final table = before.nodes.first;
    final obstacle = LayoutNode(
      id: newLayoutId(),
      kind: 'table',
      x: 1800,
      y: 300,
      width: 500,
      height: 500,
    );
    final document = before.copyWith(nodes: [...before.nodes, obstacle]);
    expect(
      moveLayoutWithinCanvas(document, {table.id}, dx: 1500).toJson(),
      document.toJson(),
    );
  });
  for (final family in ['wood', 'lounge', 'transit']) {
    for (final bar in [false, true]) {
      test(
        'custom ${bar ? 'bar' : 'table'} follows $family material without changing geometry',
        () {
          final brush = GridSurfaceBrush();
          brush.paint(350, 350);
          brush.paint(650, 350);
          brush.paint(650, 650);
          brush.paint(350, 650);
          brush.paint(350, 350);
          final node = brush.node(id: newLayoutId(), bar: bar);
          final styled = withLayoutMaterialFamily(
            VenueLayoutDocument(nodes: [node]),
            family,
          );
          final detail = (compileScene(styled)['items'] as List).singleWhere(
            (i) => i['id'] == '${node.id}:table-style',
          );
          expect(detail['path'], isNotEmpty);
          for (final command in detail['path'] as List) {
            if (command.length >= 3) {
              final x = (command[1] as num).toDouble(),
                  y = (command[2] as num).toDouble();
              expect(hitTest(styled, node.x + x, node.y + y), node.id);
            }
          }
          expect(styled.nodes.single.toJson(), node.toJson());
          expect(validateDocument(styled), isEmpty);
        },
      );
    }
  }
}
