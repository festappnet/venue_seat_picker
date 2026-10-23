import 'dart:convert';
import 'dart:io';

import 'package:venue_layout_core/venue_layout_core.dart';

// VM geometry CPU times, not browser frame times. Keep fixtures/work identical
// when comparing revisions. Static chairs are distant from the moving table.
void main() {
  for (final count in [500, 5000]) {
    final table = tableLayout(
      shape: 'rect',
      count: 8,
      x: 400,
      y: 400,
      width: 420,
      height: 120,
    );
    final base = table.copyWith(
      nodes: [
        ...table.nodes,
        for (var i = 0; i < count; i++)
          LayoutNode(
            id: newLayoutId(),
            kind: 'seat',
            x: 1000.0 + (i % 50) * 24,
            y: 800.0 + (i ~/ 50) * 24,
            width: 20,
            height: 20,
          ),
      ],
      canvas: {...table.canvas, 'width': 3000, 'height': 4000},
    );
    final id = table.nodes.first.id;
    final times = <int>[];
    for (var i = 0; i < 60; i++) {
      final timer = Stopwatch()..start();
      final result = moveLayoutWithinCanvas(
        base,
        {id},
        dx: 20.0 + i % 20,
        dy: 10,
      );
      timer.stop();
      if (identical(result, base)) throw StateError('Unexpected rejected move');
      if (i >= 20) times.add(timer.elapsedMicroseconds);
    }
    times.sort();
    stdout.writeln(
      jsonEncode({
        'staticSeats': count,
        'samples': times.length,
        'medianUs': times[times.length ~/ 2],
        'p95Us': times[(times.length * .95).floor()],
      }),
    );
  }
}
