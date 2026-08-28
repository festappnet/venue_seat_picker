import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    final demoMode = Uri.base.queryParameters['demo'] == 'true';
    return MaterialApp(
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
      themeMode: demoMode ? ThemeMode.light : ThemeMode.system,
      home: const ExamplePage(),
    );
  }
}

class ExamplePage extends StatefulWidget {
  const ExamplePage({super.key});

  @override
  State<ExamplePage> createState() => _ExamplePageState();
}

class _ExamplePageState extends State<ExamplePage> {
  static const selectionLimit = 6;
  static const demoSelectionTarget = 5;
  static const maxBackdropBytes = 8 * 1024 * 1024;

  late final VenueSeatController<VenueSeat, Object> controller;
  late final String svgBackdropSource;
  _BackdropKind backdropKind = _BackdropKind.sampleSvg;
  bool editing = Uri.base.queryParameters['mode'] == 'editor';
  bool closeUp = false;
  bool hasInspectedSeats = false;
  bool hasEditedVenue = false;
  bool loading = true;
  int editCount = 0;
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
    svgBackdropSource = await rootBundle.loadString(
      'assets/venue_floor_plan.svg',
    );
    final seats = (values['seats']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .map(VenueSeat.fromJson);
    controller.loadPlan(
      rows: values['rows']! as int,
      columns: values['columns']! as int,
      seats: seats,
      backdrop: SvgVenueBackdrop(svgBackdropSource),
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
                      ? '${selectedSeatIds.length} / $selectionLimit'
                      : '${selectedSeatIds.length} / $selectionLimit selected',
                ),
              ),
            ),
          PopupMenuButton<_BackdropAction>(
            tooltip: 'Change venue background',
            enabled: !loading,
            onSelected: _handleBackdropAction,
            icon: Icon(switch (backdropKind) {
              _BackdropKind.sampleSvg => Icons.draw_outlined,
              _BackdropKind.customSvg => Icons.code,
              _BackdropKind.customImage => Icons.image_outlined,
              _BackdropKind.none => Icons.hide_image_outlined,
            }),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _BackdropAction.uploadSvg,
                child: _BackdropMenuItem(
                  icon: Icons.upload_file,
                  label: 'Choose your SVG…',
                ),
              ),
              PopupMenuItem(
                value: _BackdropAction.uploadImage,
                child: _BackdropMenuItem(
                  icon: Icons.add_photo_alternate_outlined,
                  label: 'Choose your PNG or JPG…',
                ),
              ),
              PopupMenuItem(
                value: _BackdropAction.restoreSample,
                child: _BackdropMenuItem(
                  icon: Icons.refresh,
                  label: 'Restore sample SVG',
                ),
              ),
              PopupMenuItem(
                value: _BackdropAction.remove,
                child: _BackdropMenuItem(
                  icon: Icons.hide_image_outlined,
                  label: 'Remove background',
                ),
              ),
            ],
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
            Switch(value: editing, onChanged: _setEditing),
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
                  : closeUp
                  ? 2
                  : selectedSeatIds.length < demoSelectionTarget
                  ? 1
                  : hasInspectedSeats
                  ? 3
                  : 2,
              message: editing
                  ? editCount < 3
                        ? 'Change three seats to blocked.'
                        : editCount < 5
                        ? 'Erase two seats from the plan.'
                        : editCount < 8
                        ? 'Add three new available seats.'
                        : 'Review the edits, then return to the picker.'
                  : hasEditedVenue
                  ? 'Picker and editor share the updated plan.'
                  : closeUp
                  ? 'Inspect individual seat states up close.'
                  : selectedSeatIds.length < demoSelectionTarget
                  ? 'Select five available seats '
                        '(${selectedSeatIds.length} / $demoSelectionTarget).'
                  : hasInspectedSeats
                  ? 'Open the editor to modify this same plan.'
                  : 'Zoom in and inspect the selected seats.',
            ),
            const SizedBox(height: 8),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : editing
                  ? VenueSeatEditor<VenueSeat, Object>(
                      controller: controller,
                      config: _viewConfig(context),
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
                      onChanged: () => setState(() {
                        hasEditedVenue = true;
                        editCount++;
                      }),
                    )
                  : VenueSeatPicker<VenueSeat, Object>(
                      controller: controller,
                      config: _viewConfig(context),
                      maxSelectedSeats: selectionLimit,
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
                                'You can select at most six seats.',
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
    setState(() {
      if (closeUp) hasInspectedSeats = true;
      closeUp = !closeUp;
    });
  }

  VenueSeatViewConfig _viewConfig(BuildContext context) =>
      VenueSeatViewConfig.fromTheme(
        context,
        boundaryMargin: const EdgeInsets.all(48),
      );

  Future<void> _handleBackdropAction(_BackdropAction action) async {
    switch (action) {
      case _BackdropAction.uploadSvg:
        await _chooseSvgBackdrop();
        return;
      case _BackdropAction.uploadImage:
        await _chooseImageBackdrop();
        return;
      case _BackdropAction.restoreSample:
        controller.setBackdrop(SvgVenueBackdrop(svgBackdropSource));
        setState(() => backdropKind = _BackdropKind.sampleSvg);
        return;
      case _BackdropAction.remove:
        controller.setBackdrop(null);
        setState(() => backdropKind = _BackdropKind.none);
        return;
    }
  }

  Future<void> _chooseSvgBackdrop() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'SVG', extensions: ['svg']),
      ],
    );
    if (file == null) return;
    try {
      final bytes = await _readBackdropBytes(file);
      final source = utf8.decode(bytes);
      if (!RegExp(r'<svg(?:\s|>)', caseSensitive: false).hasMatch(source)) {
        throw const FormatException('Missing SVG root');
      }
      if (!mounted) return;
      controller.setBackdrop(SvgVenueBackdrop(source));
      setState(() => backdropKind = _BackdropKind.customSvg);
      _showBackdropMessage('Your SVG background is active.');
    } on Object {
      if (mounted) _showBackdropError('Choose a valid SVG under 8 MB.');
    }
  }

  Future<void> _chooseImageBackdrop() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Images', extensions: ['png', 'jpg', 'jpeg']),
      ],
    );
    if (file == null) return;
    try {
      final bytes = await _readBackdropBytes(file);
      final extension = file.name.split('.').last.toLowerCase();
      if (!_matchesImageSignature(bytes, extension)) {
        throw const FormatException('Image signature does not match');
      }
      final mimeType = extension == 'png' ? 'image/png' : 'image/jpeg';
      if (!mounted) return;
      controller.setBackdrop(MemoryVenueBackdrop(bytes, mimeType: mimeType));
      setState(() => backdropKind = _BackdropKind.customImage);
      _showBackdropMessage('Your image background is active.');
    } on Object {
      if (mounted) _showBackdropError('Choose a valid PNG or JPG under 8 MB.');
    }
  }

  Future<Uint8List> _readBackdropBytes(XFile file) async {
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty || bytes.length > maxBackdropBytes) {
      throw const FormatException('Invalid backdrop size');
    }
    return bytes;
  }

  bool _matchesImageSignature(Uint8List bytes, String extension) {
    if (extension == 'png') {
      const signature = [137, 80, 78, 71, 13, 10, 26, 10];
      if (bytes.length < signature.length) return false;
      for (var index = 0; index < signature.length; index++) {
        if (bytes[index] != signature[index]) return false;
      }
      return true;
    }
    return bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff;
  }

  void _showBackdropMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  void _showBackdropError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  void _setEditing(bool value) {
    if (closeUp) controller.fitToViewport();
    setState(() {
      editing = value;
      closeUp = false;
    });
  }
}

enum _BackdropAction { uploadSvg, uploadImage, restoreSample, remove }

enum _BackdropKind { sampleSvg, customSvg, customImage, none }

class _BackdropMenuItem extends StatelessWidget {
  const _BackdropMenuItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [Icon(icon, size: 20), const SizedBox(width: 12), Text(label)],
  );
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
