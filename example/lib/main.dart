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
    darkTheme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.indigo,
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    ),
    themeMode: ThemeMode.system,
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
  bool closeUp = false;
  bool hasEditedVenue = false;
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
          IconButton(
            tooltip: closeUp ? 'Fit entire venue' : 'Zoom in on seats',
            onPressed: loading ? null : _toggleCloseUp,
            icon: Icon(closeUp ? Icons.zoom_out_map : Icons.zoom_in),
          ),
          if (compact)
            IconButton(
              tooltip: editing ? 'Open picker' : 'Open editor',
              onPressed: () => _setEditing(!editing),
              icon: Icon(editing ? Icons.event_seat : Icons.edit_outlined),
            )
          else ...[
            const Text('Edit'),
            Switch(
              value: editing,
              onChanged: _setEditing,
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
            _DemoStepBanner(
              step: editing
                  ? 4
                  : hasEditedVenue
                  ? 5
                  : selectedSeatIds.isEmpty
                  ? 1
                  : selectedSeatIds.length < 3
                  ? 2
                  : 3,
              message: editing
                  ? 'Choose a tool, then paint or erase seats.'
                  : hasEditedVenue
                  ? 'Picker and editor share the updated plan.'
                  : selectedSeatIds.isEmpty
                  ? compact
                        ? 'Select an available seat. Pinch to zoom.'
                        : 'Select an available seat. Scroll to zoom.'
                  : selectedSeatIds.length < 3
                  ? 'Review each selected seat before continuing.'
                  : 'Open the editor to modify this same plan.',
            ),
            const SizedBox(height: 8),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : editing
                  ? VenueSeatEditor<VenueSeat, Object>(
                      controller: controller,
                      config: VenueSeatViewConfig.fromTheme(context),
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
                      onChanged: () => setState(() => hasEditedVenue = true),
                    )
                  : VenueSeatPicker<VenueSeat, Object>(
                      controller: controller,
                      config: VenueSeatViewConfig.fromTheme(context),
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

  void _toggleCloseUp() {
    if (closeUp) {
      controller.fitToViewport();
    } else {
      controller.transformationController.value = Matrix4.copy(
        controller.transformationController.value,
      )..scaleByDouble(1.45, 1.45, 1, 1);
    }
    setState(() => closeUp = !closeUp);
  }

  void _setEditing(bool value) {
    if (closeUp) controller.fitToViewport();
    setState(() {
      editing = value;
      closeUp = false;
    });
  }
}

class _DemoStepBanner extends StatelessWidget {
  const _DemoStepBanner({required this.step, required this.message});

  final int step;
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      '$step  $message',
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
      textAlign: TextAlign.center,
    ),
  );
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
