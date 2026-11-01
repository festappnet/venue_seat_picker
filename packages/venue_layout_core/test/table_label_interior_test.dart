import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

LayoutNode table({double rotation = 0, Map<String, dynamic>? surface}) =>
    LayoutNode(
      id: newLayoutId(),
      kind: 'table',
      x: 400,
      y: 300,
      width: 350,
      height: 234,
      rotation: rotation,
      label: 'Table 1',
      surface:
          surface ??
          const {
            'type': 'grid',
            'moduleSize': 1,
            'outer': [
              [0, 0],
              [350, 0],
              [350, 234],
              [233, 234],
              [233, 117],
              [117, 117],
              [117, 234],
              [0, 234],
            ],
            'holes': [],
          },
    );

void main() {
  test('U-shaped table label and its ink stay on the tabletop', () {
    final n = table();
    final matrix = labelRenderMatrix(
      n,
      {'orientation': 'object'},
      [1, 0, 0, 1, 0, 0],
    );
    // The photographed label is about 90 by 28 units. Its entire ink must
    // sit above the notch rather than straddling the opening at (0,0).
    final rings = nodeOutlineContours(n);
    for (final x in [-45.0, 0.0, 45.0]) {
      for (final y in [-14.0, 0.0, 14.0]) {
        expect(
          pointInPolygon(rings.first, matrix[4] + x, matrix[5] + y),
          isTrue,
        );
      }
    }
  });
  test('hole in a custom tabletop is excluded from the label anchor', () {
    final n = table(
      surface: const {
        'type': 'grid',
        'moduleSize': 1,
        'outer': [
          [0, 0],
          [350, 0],
          [350, 234],
          [0, 234],
        ],
        'holes': [
          [
            [117, 59],
            [233, 59],
            [233, 175],
            [117, 175],
          ],
        ],
      },
    );
    final m = labelRenderMatrix(
      n,
      {'orientation': 'object'},
      [1, 0, 0, 1, 0, 0],
    );
    final rings = nodeOutlineContours(n);
    expect(pointInPolygon(rings.first, m[4], m[5]), isTrue);
    expect(pointInPolygon(rings.last, m[4], m[5]), isFalse);
  });
  test(
    'screen-oriented label follows its interior anchor through rotation',
    () {
      final n = table(rotation: 90);
      final local = labelRenderMatrix(
        n,
        {'orientation': 'object'},
        [1, 0, 0, 1, 0, 0],
      );
      final m = labelRenderMatrix(
        n,
        {'orientation': 'screen'},
        [0, 1, -1, 0, 400, 300],
      );
      expect(m.sublist(0, 4), [1, 0, 0, 1]);
      expect(m[4], closeTo(400 - local[5], .001));
      expect(m[5], closeTo(300 + local[4], .001));
    },
  );
  test('ordinary rectangular table keeps its centered label', () {
    final n = table(surface: const {'type': 'rect'});
    expect(
      labelRenderMatrix(n, {'orientation': 'object'}, [1, 0, 0, 1, 400, 300]),
      [1, 0, 0, 1, 400, 300],
    );
  });
}
