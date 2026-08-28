import 'package:flutter/material.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Venue seat picker',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
    home: const ExamplePage(),
  );
}

class ExamplePage extends StatefulWidget {
  const ExamplePage({super.key});

  @override
  State<ExamplePage> createState() => _ExamplePageState();
}

class _ExamplePageState extends State<ExamplePage> {
  late final SeatLayoutController<BasicSeat> controller;
  bool editing = false;
  int selectedCount = 0;

  @override
  void initState() {
    super.initState();
    controller = SeatLayoutController<BasicSeat>()
      ..loadLayout(
        rows: 8,
        columns: 12,
        items: [
          for (var row = 1; row < 7; row++)
            for (var column = 1; column < 11; column++)
              if (column != 5 && column != 6)
                BasicSeat(
                  seatId: '$row:$column',
                  seatRow: row,
                  seatColumn: column,
                  seatLabel: '${String.fromCharCode(64 + row)}$column',
                  seatState: switch ((row, column)) {
                    (3, 3) => SeatState.ordered,
                    (2, 9) => SeatState.blocked,
                    (5, 8) => SeatState.used,
                    _ => SeatState.available,
                  },
                ),
        ],
      );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Venue seat picker'),
      actions: [
        if (!editing)
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Chip(label: Text('$selectedCount / 4 selected')),
          ),
        Row(
          children: [
            const Text('Edit'),
            Switch(
              value: editing,
              onChanged: (value) => setState(() => editing = value),
            ),
          ],
        ),
      ],
    ),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Expanded(
            child: editing
                ? SeatLayoutEditor<BasicSeat>(
                    controller: controller,
                    createItem: (row, column, state) => BasicSeat(
                      seatId: '$row:$column',
                      seatRow: row,
                      seatColumn: column,
                      seatState: state,
                      seatLabel: '${String.fromCharCode(64 + row)}$column',
                    ),
                  )
                : SeatPicker<BasicSeat>(
                    controller: controller,
                    maxSelection: 4,
                    onSelectionRequest: (cell, selected) async {
                      await Future<void>.delayed(
                        const Duration(milliseconds: 250),
                      );
                      return true;
                    },
                    onSelectionChanged: (selection) =>
                        setState(() => selectedCount = selection.length),
                    onLimitReached: () =>
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Select at most four seats.'),
                          ),
                        ),
                  ),
          ),
          if (!editing) const _Legend(),
        ],
      ),
    ),
  );
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Wrap(
      alignment: WrapAlignment.center,
      spacing: 20,
      runSpacing: 8,
      children: const [
        _LegendItem('Available', SeatState.available),
        _LegendItem('Selected', SeatState.selectedByMe),
        _LegendItem('Ordered', SeatState.ordered),
        _LegendItem('Used', SeatState.used),
        _LegendItem('Blocked', SeatState.blocked),
      ],
    ),
  );
}

class _LegendItem extends StatelessWidget {
  const _LegendItem(this.label, this.state);

  final String label;
  final SeatState state;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SeatTile(state: state, size: 28),
      const SizedBox(width: 4),
      Text(label),
    ],
  );
}
