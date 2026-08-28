import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

void main() {
  testWidgets('empty editor slots remain invisible', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: VenueSeatMarker(status: null)),
    );

    final decorated = tester.widgetList<Container>(find.byType(Container)).last;
    final decoration = decorated.decoration! as BoxDecoration;

    expect(decoration.color, Colors.transparent);
    expect(decoration.border, isNull);
  });

  testWidgets('venue surface follows light and dark host themes', (
    tester,
  ) async {
    final controller = VenueSeatController<VenueSeat, Object>(
      adapter: venueSeatAdapter,
    )..loadPlan(rows: 1, columns: 1, seats: const []);

    Future<void> expectSurfaceFor(Brightness brightness) async {
      final scheme = ColorScheme.fromSeed(
        seedColor: Colors.indigo,
        brightness: brightness,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(colorScheme: scheme),
          home: SizedBox(
            width: 100,
            height: 100,
            child: Builder(
              builder: (context) => VenueSeatViewer<VenueSeat, Object>(
                controller: controller,
                config: VenueSeatViewConfig.fromTheme(context),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final colors = tester
          .widgetList<ColoredBox>(find.byType(ColoredBox))
          .map((box) => box.color);
      expect(colors, contains(scheme.surface));
    }

    await expectSurfaceFor(Brightness.light);
    await expectSurfaceFor(Brightness.dark);
    controller.dispose();
  });
}
