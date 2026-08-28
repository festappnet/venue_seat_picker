import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  late final VenueSeatController<VenueSeat, Object> controller;
  bool editing = Uri.base.queryParameters['mode'] == 'editor';
  bool loading = true;
  int nextCustomSeatId = 1000;
  Set<Object> selectedSeatIds = {};

  @override
  void initState() {
    super.initState();
    controller = VenueSeatController<VenueSeat, Object>(
      adapter: venueSeatAdapter,
    );
    _loadVenue();
  }

  Future<void> _loadVenue() async {
    final values =
        jsonDecode(await rootBundle.loadString('assets/venue.json'))
            as Map<String, Object?>;
    final backdrop = await rootBundle.loadString('assets/venue_floor_plan.svg');
    final seats = (values['seats']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .map(VenueSeat.fromJson);
    controller.loadPlan(
      rows: values['rows']! as int,
      columns: values['columns']! as int,
      seats: seats,
      backdrop: SvgVenueBackdrop(backdrop),
    );
    if (mounted) setState(() => loading = false);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Scaffold(
      appBar: AppBar(
        title: Text(compact ? 'Seat map' : 'Venue seat picker'),
        actions: [
          if (!editing)
            Padding(
              padding: EdgeInsets.only(right: compact ? 4 : 12),
              child: Chip(
                avatar: const Icon(Icons.event_seat, size: 18),
                label: Text(
                  compact
                      ? '${selectedSeatIds.length} / 4'
                      : '${selectedSeatIds.length} / 4 selected',
                ),
              ),
            ),
          if (compact)
            IconButton(
              tooltip: editing ? 'Open picker' : 'Open editor',
              onPressed: () => setState(() => editing = !editing),
              icon: Icon(editing ? Icons.event_seat : Icons.edit_outlined),
            )
          else ...[
            const Text('Edit'),
            Switch(
              value: editing,
              onChanged: (value) => setState(() => editing = value),
            ),
          ],
          const SizedBox(width: 4),
        ],
      ),
      body: Padding(
        padding: compact
            ? const EdgeInsets.fromLTRB(8, 8, 8, 12)
            : const EdgeInsets.fromLTRB(24, 12, 24, 20),
        child: Column(
          children: [
            Text(
              editing
                  ? 'Choose a tool, then tap seats to edit the plan.'
                  : compact
                  ? 'Tap a seat to select it. Pinch to zoom.'
                  : 'Click available seats to select them. Scroll to zoom.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : editing
                  ? VenueSeatEditor<VenueSeat, Object>(
                      controller: controller,
                      editing: SeatEditingDelegate<VenueSeat>(
                        create: (position, status) => VenueSeat(
                          id: 'custom-${nextCustomSeatId++}',
                          position: position,
                          status: status,
                          label: 'New ${position.row}:${position.column}',
                        ),
                        withStatus: (seat, status) =>
                            seat.copyWith(status: status),
                      ),
                    )
                  : VenueSeatPicker<VenueSeat, Object>(
                      controller: controller,
                      maxSelectedSeats: 4,
                      onSelectionRequested: (request) async {
                        await Future<void>.delayed(
                          const Duration(milliseconds: 350),
                        );
                        return true;
                      },
                      onSelectionChanged: (selection) =>
                          setState(() => selectedSeatIds = selection),
                      onSelectionLimitReached: () =>
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'You can select at most four seats.',
                              ),
                            ),
                          ),
                    ),
            ),
            if (!editing && !loading) const _Legend(),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Wrap(
      alignment: WrapAlignment.center,
      spacing: 18,
      runSpacing: 8,
      children: const [
        _LegendItem('Available', SeatStatus.available),
        _LegendItem('Selected', SeatStatus.available, selected: true),
        _LegendItem('Held', SeatStatus.held),
        _LegendItem('Booked', SeatStatus.booked),
        _LegendItem('Checked in', SeatStatus.checkedIn),
        _LegendItem('Blocked', SeatStatus.blocked),
      ],
    ),
  );
}

class _LegendItem extends StatelessWidget {
  const _LegendItem(this.label, this.status, {this.selected = false});

  final String label;
  final SeatStatus status;
  final bool selected;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      VenueSeatMarker(status: status, selected: selected, size: 28),
      const SizedBox(width: 4),
      Text(label),
    ],
  );
}
