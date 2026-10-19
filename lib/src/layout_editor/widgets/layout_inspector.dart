import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:venue_seat_picker/editor_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'layout_scene_surface.dart';
import 'layout_style.dart';
import 'layout_global_style.dart';
import 'layout_floor_style.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

class LayoutInspector extends StatefulWidget {
  const LayoutInspector({
    super.key,
    required this.controller,
    required this.cornerPivot,
    required this.onPivotChanged,
    this.hostBuilder,
    this.canvasSelected = false,
    this.onImportBackground,
    this.onClearSelection,
    this.onCopyStyle,
    this.onPasteStyle,
    this.readOnlyLabelNodeIds = const {},
  });
  final VenueLayoutController controller;
  final Set<String> readOnlyLabelNodeIds;
  final bool cornerPivot;
  final bool canvasSelected;
  final Future<void> Function()? onImportBackground;
  final VoidCallback? onCopyStyle, onPasteStyle, onClearSelection;
  final ValueChanged<bool> onPivotChanged;
  final Widget Function(BuildContext, LayoutNode)? hostBuilder;
  @override
  State<LayoutInspector> createState() => _LayoutInspectorState();
}

class _LayoutInspectorState extends State<LayoutInspector> {
  VenueLayoutController get c => widget.controller;
  String _search = '';
  String? _selectionContext;
  String? _error;
  int _shapeControlRevision = 0;
  Map<String, LayoutNode> _nodesById = {};
  VenueLayoutDocument? _indexedDocument, _layerDocument;
  List<LayoutNode> _orderedLayers = const [], _filteredLayers = const [];
  String? _layerSearch;
  bool _layersExpanded = false;
  Widget? _layerRows;
  Set<String> _layerSelection = const {};

  // Layer rows depend on tree/order/name/lock metadata, not live coordinates or
  // appearance. Geometry previews can retain the same subtree of widgets.
  bool _sameLayerMetadata(
    VenueLayoutDocument before,
    VenueLayoutDocument after,
  ) {
    if (before.nodes.length != after.nodes.length) return false;
    for (var i = 0; i < before.nodes.length; i++) {
      final a = before.nodes[i], b = after.nodes[i];
      if (a.id != b.id ||
          a.parentId != b.parentId ||
          a.z != b.z ||
          a.kind != b.kind ||
          a.label != b.label ||
          a.locked != b.locked) {
        return false;
      }
    }
    return true;
  }

  List<LayoutNode> _layers() {
    final document = c.document;
    if (!identical(document, _layerDocument)) {
      if (_layerDocument == null ||
          !_sameLayerMetadata(_layerDocument!, document)) {
        _orderedLayers = orderedNodes(document);
        _layerSearch = null;
      }
      _layerDocument = document;
    }
    final search = _search.toLowerCase();
    if (_layerSearch != search) {
      _filteredLayers = search.isEmpty
          ? _orderedLayers
          : _orderedLayers
                .where(
                  (n) => '${n.label} ${n.kind}'.toLowerCase().contains(search),
                )
                .toList();
      _layerSearch = search;
      _layerRows = null;
    }
    return _filteredLayers;
  }

  Widget _rows(List<LayoutNode> layers, Set<String> selection) {
    if (_layerRows != null && setEquals(_layerSelection, selection)) {
      return _layerRows!;
    }
    _layerSelection = selection;
    int depth(LayoutNode node) {
      var result = 0;
      var parent = node.parentId;
      final seen = <String>{};
      while (parent != null && seen.add(parent)) {
        result++;
        parent = _nodesById[parent]?.parentId;
      }
      return result;
    }

    return _layerRows = Column(
      children: [
        for (final n in layers.take(200))
          ListTile(
            contentPadding: EdgeInsets.only(left: depth(n) * 12.0),
            leading: Icon(
              n.kind == 'group' ? Icons.folder_outlined : Icons.layers_outlined,
              size: 16,
            ),
            dense: true,
            selected: selection.contains(n.id),
            title: LayoutText(
              n.label.isEmpty ? n.kind : n.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: LayoutText(n.kind),
            trailing: n.locked ? const Icon(Icons.lock_outline) : null,
            onTap: () => c.select({n.id}),
            onLongPress: () => c.select({...c.selection, n.id}),
          ),
        if (layers.length > 200)
          LayoutText(
            '${layers.length - 200} more objects. Refine search to find them.',
          ),
      ],
    );
  }

  void _run(VoidCallback action) {
    try {
      action();
      if (mounted) setState(() => _error = null);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  String _nodeFill(LayoutNode node) =>
      '${effectiveNodeProperties(c.document, node)['fill'] ?? switch (node.kind) {
            'seat' => _nodesById[node.parentId]?.properties['furniture'] == 'couch' ? '#F8FAFCFF' : '#DCFCE7FF',
            'table' => '#E2E8F0FF',
            'capacityArea' => '#DBEAFEFF',
            _ => '#F1F5F9FF',
          }}';

  List<String> _collectUsedColors() {
    final colors = <String>{};
    void add(dynamic value) {
      if (value is String &&
          RegExp(r'^#[0-9a-fA-F]{8}$').hasMatch(value) &&
          value.substring(7).toUpperCase() != '00') {
        colors.add(value.substring(1, 7).toUpperCase());
      }
    }

    add(c.document.canvas['fill']);
    for (final node in c.document.nodes) {
      add(_nodeFill(node));
      for (final key in ['fill', 'stroke', 'color']) {
        add(effectiveNodeProperties(c.document, node)[key]);
      }
    }
    return colors.toList();
  }

  Widget _seatAppearance(LayoutNode root) {
    final descendants = layoutSubtree(c.document, {root.id});
    final seats = c.document.nodes
        .where((n) => n.kind == 'seat' && descendants.contains(n.id))
        .toList();
    if (seats.isEmpty) return const SizedBox.shrink();
    final seatIds = seats.map((n) => n.id).toSet();
    return _field('Seat fill #RRGGBBAA', _nodeFill(seats.first), (value) {
      c.apply(
        c.document.copyWith(
          nodes: [
            for (final n in c.document.nodes)
              if (seatIds.contains(n.id))
                n.copyWith(
                  properties: localAppearanceProperties(n, {'fill': value}),
                )
              else
                n,
          ],
        ),
        label: 'Seat color',
      );
    });
  }

  Widget _field(
    String label,
    String value,
    ValueChanged<String> save, {
    bool multiline = false,
    bool numeric = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: _PropertyField(
      key: ValueKey(label),
      label: label,
      value: value,
      enabled: !(c.readOnly || c.saving),
      multiline: multiline,
      numeric: numeric,
      save: (v) => _run(() => save(v)),
      usedColors: _collectUsedColors,
      paletteImage:
          (c.resources['images'] as Map?)?[c.document.background?['assetRef']]
              as ui.Image?,
    ),
  );
  Widget _number(String label, num value, ValueChanged<double> save) => _field(
    label,
    value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), ''),
    (v) {
      final parsed = double.tryParse(v);
      if (parsed == null || !parsed.isFinite) {
        throw const FormatException('Enter a valid number.');
      }
      save(parsed);
    },
    numeric: true,
  );
  void _resizeDimension(LayoutNode node, double value, {required bool width}) {
    final keepRound =
        node.kind == 'table' &&
        const [
          'round',
          'circle',
          'ellipse',
          'oval',
        ].contains(node.properties['shape']) &&
        !HardwareKeyboard.instance.isShiftPressed;
    c.resizeObject(
      node.id,
      width
          ? value
          : keepRound
          ? value * node.width / node.height
          : node.width,
      !width
          ? value
          : keepRound
          ? value * node.height / node.width
          : node.height,
    );
  }

  void _property(LayoutNode n, String key, dynamic value) => c.updateNode(
    n.copyWith(properties: localAppearanceProperties(n, {key: value})),
  );
  Future<void> _preview(
    String title,
    VenueLayoutDocument Function(Map<String, double>) generate,
    Map<String, double> initial, {
    String? detail,
  }) async {
    final values = Map<String, double>.of(initial);
    c.beginGesture();
    String? error;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: LayoutText(title),
          content: SizedBox(
            width: 340,
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (detail != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: LayoutText(detail),
                    ),
                  for (final key in values.keys)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: EditorNumberScroll(
                        step: key == 'Opacity' ? .05 : 1,
                        min: key == 'Opacity' ? 0 : null,
                        max: key == 'Opacity' ? 1 : null,
                        child: TextFormField(
                          initialValue: values[key].toString(),
                          decoration: InputDecoration(
                            labelText: VenueLayoutStrings.text(context, key),
                            border: const OutlineInputBorder(),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          onChanged: (text) {
                            final value = double.tryParse(text);
                            if (value == null || !value.isFinite) {
                              update(() => error = 'Enter a valid $key.');
                              return;
                            }
                            values[key] = value;
                            try {
                              c.preview(generate(values));
                              update(() => error = c.error);
                            } catch (e) {
                              update(() => error = '$e');
                            }
                          },
                        ),
                      ),
                    ),
                  if (error != null)
                    LayoutText(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const LayoutText('Cancel'),
            ),
            FilledButton(
              onPressed: error == null
                  ? () => Navigator.pop(context, true)
                  : null,
              child: const LayoutText('Apply'),
            ),
          ],
        ),
      ),
    );
    if (accepted == true) {
      c.commitGesture();
    } else {
      c.cancelGesture();
    }
  }

  void _updateRows(LayoutNode node, String key, double value) {
    final parameters = rowLayoutParameters(c.document, node.id);
    if (const {'rows', 'seatsPerRow', 'blocks'}.contains(key) &&
        (value != value.roundToDouble() || value < 1)) {
      throw FormatException(
        VenueLayoutStrings.text(context, 'Enter a positive whole number.'),
      );
    }
    final values = <String, num>{...parameters, key: value};
    final generated = rowLayout(
      rows: values['rows']!.toInt(),
      seatsPerRow: values['seatsPerRow']!.toInt(),
      blocks: values['blocks']!.toInt(),
      arc: values['arc']!.toDouble(),
      spacing: values['spacing']!.toDouble(),
      rowSpacing: values['rowSpacing']!.toDouble(),
      aisle: values['aisle']!.toDouble(),
      seating: documentSeating(
        c.document.copyWith(
          nodes: c.document.nodes.where((n) => n.parentId == node.id).toList(),
        ),
      ),
    );
    c.apply(
      reconcileAssembly(c.document, node.id, generated),
      label: 'Adjust rows',
    );
  }

  Widget _rowControls(LayoutNode node) {
    final values = rowLayoutParameters(c.document, node.id);
    final enabled = !(c.readOnly || c.saving || node.locked);
    Widget count(String label, String key) {
      final value = values[key]!.toInt();
      final noun = const {
        'rows': 'row',
        'seatsPerRow': 'column',
        'blocks': 'block',
      }[key]!;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _number(label, value, (v) => _updateRows(node, key, v)),
          ),
          IconButton(
            tooltip: VenueLayoutStrings.text(context, 'Remove $noun'),
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: !enabled || value <= 1
                ? null
                : () => _run(
                    () => _updateRows(node, key, (value - 1).toDouble()),
                  ),
          ),
          IconButton(
            tooltip: VenueLayoutStrings.text(context, 'Add $noun'),
            icon: const Icon(Icons.add_circle_outline),
            onPressed: !enabled
                ? null
                : () => _run(
                    () => _updateRows(node, key, (value + 1).toDouble()),
                  ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        count('Number of rows', 'rows'),
        count('Seats per row', 'seatsPerRow'),
        _number(
          'Curvature',
          values['arc']!,
          (v) => _updateRows(node, 'arc', v),
        ),
        Slider(
          semanticFormatterCallback: (value) => value.toStringAsFixed(1),
          value: values['arc']!.toDouble(),
          min: -math.max(12.0, values['arc']!.abs().toDouble()),
          max: math.max(12.0, values['arc']!.abs().toDouble()),
          divisions: 96,
          label: values['arc']!.toStringAsFixed(1),
          onChangeStart: !enabled ? null : (_) => c.beginGesture(),
          onChanged: !enabled
              ? null
              : (value) => _run(() => _updateRows(node, 'arc', value)),
          onChangeEnd: !enabled
              ? null
              : (_) {
                  if (c.error == null) {
                    c.commitGesture();
                  } else {
                    final error = c.error;
                    c.cancelGesture();
                    c.error = error;
                  }
                },
        ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const LayoutText('Row arrangement'),
          children: [
            _number(
              'Seat spacing',
              values['spacing']!,
              (v) => _updateRows(node, 'spacing', v),
            ),
            _number(
              'Row spacing',
              values['rowSpacing']!,
              (v) => _updateRows(node, 'rowSpacing', v),
            ),
            count('Blocks', 'blocks'),
            _number(
              'Aisle width',
              values['aisle']!,
              (v) => _updateRows(node, 'aisle', v),
            ),
          ],
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _outlineStyle(LayoutNode n, Map<String, dynamic> p) =>
      DropdownButtonFormField<String>(
        initialValue: (p['dash'] is List && (p['dash'] as List).isNotEmpty)
            ? ((p['dash'] as List).first == 2 ? 'Dotted' : 'Dashed')
            : 'Solid',
        decoration: InputDecoration(
          labelText: VenueLayoutStrings.text(context, 'Outline style'),
        ),
        items: [
          for (final value in ['Solid', 'Dashed', 'Dotted'])
            DropdownMenuItem(value: value, child: LayoutText(value)),
        ],
        onChanged: (c.readOnly || c.saving)
            ? null
            : (value) => _property(
                n,
                'dash',
                value == 'Dashed'
                    ? [12, 8]
                    : value == 'Dotted'
                    ? [2, 6]
                    : <int>[],
              ),
      );

  Widget _countControl(
    String label,
    int value,
    ValueChanged<int> save, {
    int min = 0,
    int max = 30,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      LayoutText(label, style: Theme.of(context).textTheme.labelLarge),
      Row(
        children: [
          IconButton(
            tooltip: VenueLayoutStrings.text(context, 'Remove one'),
            onPressed: c.readOnly || c.saving || value <= min
                ? null
                : () => _run(() => save(value - 1)),
            icon: const Icon(Icons.remove_circle_outline),
          ),
          Expanded(child: Text('$value', textAlign: TextAlign.center)),
          IconButton(
            tooltip: VenueLayoutStrings.text(context, 'Add one'),
            onPressed: c.readOnly || c.saving || value >= max
                ? null
                : () => _run(() => save(value + 1)),
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
      const SizedBox(height: 8),
    ],
  );

  Widget _transportControls(LayoutNode n) {
    final p = n.properties;
    void bus({
      int? rows,
      int? left,
      int? right,
      int? rear,
      int? decks,
      int? upperRows,
      int? upperRear,
    }) => c.apply(
      localizeLayoutDefaultLabels(
        updateBusLayout(
          c.document,
          n.id,
          rows: rows,
          left: left,
          right: right,
          rear: rear,
          decks: decks,
          upperRows: upperRows,
          upperRear: upperRear,
          protectedSeatIds: c.protectedSeatIds?.call() ?? const {},
        ),
        (text) => VenueLayoutStrings.text(context, text),
      ),
      label: 'Adjust assembly',
    );
    void coupe({int? compartments, int? seats}) => c.apply(
      localizeLayoutDefaultLabels(
        updateCompartmentLayout(
          c.document,
          n.id,
          compartments: compartments,
          seats: seats,
          protectedSeatIds: c.protectedSeatIds?.call() ?? const {},
        ),
        (text) => VenueLayoutStrings.text(context, text),
      ),
      label: 'Adjust assembly',
    );
    final enabled = !c.readOnly && !c.saving;
    if (p['assembly'] == 'compartments') {
      return Column(
        children: [
          _countControl(
            'Compartments',
            (p['compartments'] as num? ?? 4).toInt(),
            (v) => coupe(compartments: v),
            min: 1,
            max: 12,
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 16),
            child: DropdownButtonFormField<int>(
              key: ValueKey('coupe-seats-${p['seats']}'),
              initialValue: (p['seats'] as num? ?? 6).toInt(),
              decoration: InputDecoration(
                labelText: VenueLayoutStrings.text(
                  context,
                  'Seats per compartment',
                ),
              ),
              items: [
                for (final count in [4, 6, 8])
                  DropdownMenuItem(value: count, child: Text('$count')),
              ],
              onChanged: enabled ? (v) => _run(() => coupe(seats: v)) : null,
            ),
          ),
        ],
      );
    }
    final decks = (p['decks'] as num? ?? 1).toInt();
    final layout = '${p['left'] ?? 2}+${p['right'] ?? 2}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const LayoutText('Decks'),
        const SizedBox(height: 8),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 1, label: Text('1')),
            ButtonSegment(value: 2, label: Text('2')),
          ],
          selected: {decks},
          onSelectionChanged: enabled
              ? (v) => _run(() => bus(decks: v.single))
              : null,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 16),
          child: DropdownButtonFormField<String>(
            key: ValueKey('bus-seat-layout-$layout'),
            initialValue: layout,
            decoration: InputDecoration(
              labelText: VenueLayoutStrings.text(context, 'Seat layout'),
            ),
            items: [
              for (final value in {'1+1', '1+2', '2+2', '2+3', layout})
                DropdownMenuItem(
                  value: value,
                  child: Text(value.replaceAll('+', ' + ')),
                ),
            ],
            onChanged: enabled
                ? (v) => _run(() {
                    final parts = v!.split('+');
                    bus(left: int.parse(parts[0]), right: int.parse(parts[1]));
                  })
                : null,
          ),
        ),
        _countControl(
          decks == 2 ? 'Rows on lower deck' : 'Rows',
          (p['rows'] as num? ?? 10).toInt(),
          (v) => bus(rows: v),
          min: 1,
        ),
        _countControl(
          decks == 2 ? 'Rear seats on lower deck' : 'Rear seats',
          (p['rear'] as num? ?? 5).toInt(),
          (v) => bus(rear: v),
          max: 6,
        ),
        if (decks == 2) ...[
          _countControl(
            'Rows on upper deck',
            (p['upperRows'] as num? ?? p['rows'] as num? ?? 10).toInt(),
            (v) => bus(upperRows: v),
            min: 1,
          ),
          _countControl(
            'Rear seats on upper deck',
            (p['upperRear'] as num? ?? p['rear'] as num? ?? 5).toInt(),
            (v) => bus(upperRear: v),
            max: 6,
          ),
        ],
      ],
    );
  }

  Widget _couchControls(LayoutNode node) {
    final count = couchSeatCount(c.document, node.id);
    final enabled = !(c.readOnly || c.saving);
    return Row(
      children: [
        Expanded(
          child: _number('Seats on couch', count, (value) {
            if (value != value.roundToDouble() || value < 1) {
              throw const FormatException(
                'Enter a whole seat count of at least one.',
              );
            }
            c.setSeatCount(node.id, value.toInt());
          }),
        ),
        IconButton(
          tooltip: VenueLayoutStrings.text(context, 'Remove one seat'),
          onPressed: enabled && count > 1
              ? () => c.setSeatCount(node.id, count - 1)
              : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        IconButton(
          tooltip: VenueLayoutStrings.text(context, 'Add one seat'),
          onPressed: enabled ? () => c.setSeatCount(node.id, count + 1) : null,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }

  String _typeTitle(LayoutNode node) => isZigzagNode(node)
      ? 'Zigzag'
      : isBarNode(node)
      ? 'Bar'
      : node.properties['furniture'] == 'stool' ||
            isBarNode(_nodesById[node.parentId] ?? node)
      ? 'Bar stool'
      : isCouchNode(node)
      ? 'Couch'
      : node.properties['assembly'] == 'rows'
      ? 'Seat rows'
      : node.kind == 'shape'
      ? const {
              'line': 'Line',
              'polyline': 'Polyline',
              'arrow': 'Arrow',
              'polygon': 'Polygon',
              'rect': 'Rectangle',
              'rectangle': 'Rectangle',
              'roundedRect': 'Rectangle',
              'ellipse': 'Ellipse',
              'circle': 'Ellipse',
              'round': 'Ellipse',
              'oval': 'Ellipse',
            }[node.properties['shape']] ??
            'Shape'
      : const {
              'table': 'Table',
              'seat': 'Chair',
              'text': 'Text',
              'capacityArea': 'Standing',
              'group': 'Object group',
              'shape': 'Shape',
            }[node.kind] ??
            node.kind;

  String _tableShape(LayoutNode node) => node.properties['shape'] == 'polygon'
      ? 'polygon'
      : const [
          'round',
          'circle',
          'ellipse',
          'oval',
        ].contains(node.properties['shape'])
      ? 'round'
      : 'rectangle';

  void _changeTableShape(LayoutNode node, String shape) {
    if (shape == _tableShape(node)) return;
    final before = c.document;
    final seats = before.nodes
        .where((n) => n.kind == 'seat' && n.parentId == node.id)
        .map((n) => n.id)
        .toSet();
    final properties = Map<String, dynamic>.from(node.properties)
      ..remove('points')
      ..remove('holes');
    properties['shape'] = shape == 'rectangle' ? 'roundedRect' : shape;
    if (shape == 'polygon') {
      final hull = localHull(node);
      // A round surface needs a manageable number of editable corners.
      properties['points'] = hull.length == 64
          ? [for (var i = 0; i < hull.length; i += 8) hull[i]]
          : hull;
    }
    final diameter = math.max(node.width, node.height);
    final nextNode = node.copyWith(
      width: shape == 'round' ? diameter : node.width,
      height: shape == 'round' ? diameter : node.height,
      properties: properties,
    );
    if (tableCapacity(nextNode) < seats.length) {
      throw StateError(
        'The selected shape cannot fit the existing chairs. Increase the table size first.',
      );
    }
    final next = reflowTable(
      before.copyWith(
        nodes: [for (final n in before.nodes) n.id == node.id ? nextNode : n],
      ),
      node.id,
      seats.length,
      protectedSeatIds: c.protectedSeatIds?.call() ?? const {},
    );
    final retained = next.nodes
        .where((n) => n.kind == 'seat' && n.parentId == node.id)
        .map((n) => n.id)
        .toSet();
    if (!setEquals(seats, retained)) {
      throw StateError(
        'The selected shape cannot fit the existing chairs. Increase the table size first.',
      );
    }
    c.apply(next, label: 'Change table shape');
  }

  Widget _tableShapeControls(LayoutNode node) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey(
            'table-shape-${node.id}-${_tableShape(node)}-$_shapeControlRevision',
          ),
          initialValue: !isBarNode(node) && _tableShape(node) == 'polygon'
              ? null
              : _tableShape(node),
          hint: !isBarNode(node) && _tableShape(node) == 'polygon'
              ? const LayoutText('Current outline')
              : null,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: VenueLayoutStrings.text(
              context,
              isBarNode(node) ? 'Surface shape' : 'Table shape',
            ),
            border: const OutlineInputBorder(),
            helperText: !isBarNode(node) && _tableShape(node) == 'polygon'
                ? VenueLayoutStrings.text(
                    context,
                    'The current outline is preserved until you choose a new shape.',
                  )
                : null,
            helperMaxLines: 3,
          ),
          items: [
            for (final entry in {
              'rectangle': 'Rectangle',
              if (!isBarNode(node)) 'round': 'Round',
              if (isBarNode(node)) 'polygon': 'Custom outline',
            }.entries)
              DropdownMenuItem(
                value: entry.key,
                child: LayoutText(entry.value),
              ),
          ],
          onChanged: c.readOnly || c.saving || node.locked
              ? null
              : (shape) {
                  if (shape != null) {
                    _shapeControlRevision++;
                    _run(() => _changeTableShape(node, shape));
                  }
                },
        ),
        if (isBarNode(node) && _tableShape(node) == 'polygon')
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LayoutText(
              'Pull an edge handle to extend the surface. Drag corners to reshape it.',
            ),
          ),
      ],
    ),
  );

  Widget _node(LayoutNode n) {
    final facingRotation = tableSeatFacingRotation(n, _nodesById[n.parentId]);
    final p = effectiveNodeProperties(c.document, n);
    final openPath = const ['line', 'polyline', 'arrow'].contains(p['shape']);
    final styleIds = layoutSubtree(c.document, {n.id});
    final followsPlan = c.document.nodes
        .where((node) => styleIds.contains(node.id))
        .every(
          (node) =>
              ((node.properties['appearanceOverrides'] as List?) ?? const [])
                  .isEmpty,
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutText(
          n.kind == 'table'
              ? isBarNode(n)
                    ? 'Bar'
                    : 'Table and seats'
              : p['assembly'] == 'rows'
              ? 'Seat rows'
              : isZigzagNode(n)
              ? 'Zigzag'
              : openPath
              ? {
                  'line': 'Line',
                  'polyline': 'Polyline',
                  'arrow': 'Arrow',
                }[p['shape']]!
              : _typeTitle(n),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        if (!widget.readOnlyLabelNodeIds.contains(n.id))
          _field('Name', n.label, (v) => c.updateNode(n.copyWith(label: v))),
        if (n.kind == 'table' &&
            c.document.nodes.any(
              (seat) => seat.kind == 'seat' && seat.parentId == n.id,
            ))
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: LayoutText(
              'Chairs move with the table. Resize handles change the tabletop.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        if (n.kind == 'table' && !isBarNode(n))
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const LayoutText('Chair layout'),
            childrenPadding: const EdgeInsets.only(top: 12, bottom: 8),
            children: [
              for (final entry in const {
                'width': 'Chair width',
                'height': 'Chair depth',
                'gap': 'Distance from table',
                'spacing': 'Space between chairs',
              }.entries)
                Builder(
                  builder: (context) {
                    final current = TableSeating.fromDocument(c.document, n);
                    final values = {
                      'width': current.width,
                      'height': current.height,
                      'gap': current.gap,
                      'spacing': current.spacing,
                    };
                    return _number(entry.value, values[entry.key]!, (value) {
                      final next = {...values, entry.key: value};
                      c.setTableSeating(
                        n.id,
                        TableSeating(
                          width: next['width']!,
                          height: next['height']!,
                          gap: next['gap']!,
                          spacing: next['spacing']!,
                          edgePadding: current.edgePadding,
                        ),
                      );
                    });
                  },
                ),
            ],
          ),
        if (p['assembly'] == 'rows') _rowControls(n),
        if (isCouchNode(n)) _couchControls(n),
        if (isZigzagNode(n)) ...[
          Row(
            children: [
              Expanded(
                child: _number('Number of teeth', p['zigzagTeeth'] as num, (v) {
                  if (v != v.roundToDouble() || v < 1 || v > 255) {
                    throw const FormatException(
                      'Enter a whole number from 1 to 255.',
                    );
                  }
                  c.apply(
                    updateZigzag(c.document, n.id, teeth: v.toInt()),
                    label: 'Adjust zigzag',
                  );
                }),
              ),
              IconButton(
                tooltip: VenueLayoutStrings.text(context, 'Remove one tooth'),
                onPressed:
                    !(c.readOnly || c.saving) && (p['zigzagTeeth'] as num) > 1
                    ? () => _run(
                        () => c.apply(
                          updateZigzag(
                            c.document,
                            n.id,
                            teeth: (p['zigzagTeeth'] as num).toInt() - 1,
                          ),
                          label: 'Adjust zigzag',
                        ),
                      )
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              IconButton(
                tooltip: VenueLayoutStrings.text(context, 'Add one tooth'),
                onPressed:
                    !(c.readOnly || c.saving) && (p['zigzagTeeth'] as num) < 255
                    ? () => _run(
                        () => c.apply(
                          updateZigzag(
                            c.document,
                            n.id,
                            teeth: (p['zigzagTeeth'] as num).toInt() + 1,
                          ),
                          label: 'Adjust zigzag',
                        ),
                      )
                    : null,
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          _number(
            'Zigzag height',
            (p['zigzagAmplitude'] as num) * 2,
            (v) => c.apply(
              updateZigzag(c.document, n.id, amplitude: v / 2),
              label: 'Adjust zigzag',
            ),
          ),
        ],
        if (['bus', 'compartments'].contains(p['assembly']))
          _transportControls(n),
        if (n.kind == 'seat' && n.parentId != null)
          TextButton(
            onPressed: (c.readOnly || c.saving)
                ? null
                : () => _run(
                    () => c.apply(
                      detachSeat(c.document, n.id),
                      label: 'Detach seat',
                    ),
                  ),
            child: const LayoutText('Detach from assembly'),
          ),

        if (n.kind == 'table') _tableShapeControls(n),
        if (n.kind == 'shape' && p['shape'] == 'polygon')
          OutlinedButton(
            onPressed: c.readOnly || c.saving
                ? null
                : () => _run(
                    () => c.apply(
                      surfaceFromPolygon(c.document, n.id, bar: true),
                      label: 'Create surface',
                    ),
                  ),
            child: const LayoutText('Use as bar'),
          ),
        if (n.kind == 'table' && !isBarNode(n)) ...[
          Builder(
            builder: (context) {
              final count = c.document.nodes
                  .where((x) => x.parentId == n.id && x.kind == 'seat')
                  .length;
              return Column(
                children: [
                  LayoutText('$count seats · maximum ${tableCapacity(n)}'),
                  Wrap(
                    alignment: WrapAlignment.center,
                    children: [
                      IconButton(
                        tooltip: VenueLayoutStrings.text(
                          context,
                          'Remove one seat',
                        ),
                        onPressed: !(c.readOnly || c.saving) && count > 0
                            ? () => _run(() => c.setSeatCount(n.id, count - 1))
                            : null,
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      IconButton(
                        tooltip: VenueLayoutStrings.text(
                          context,
                          'Add one seat',
                        ),
                        onPressed:
                            !(c.readOnly || c.saving) &&
                                count < tableCapacity(n)
                            ? () => _run(() => c.setSeatCount(n.id, count + 1))
                            : null,
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
        if (n.kind == 'text') ...[
          _field(
            'Text',
            '${p['text'] ?? n.label}',
            (v) => _property(n, 'text', v),
            multiline: true,
          ),
          EditorFontPicker(
            value: p['fontId'] as String?,
            label: 'Font',
            enabled: !(c.readOnly || c.saving),
            translate: (text) => VenueLayoutStrings.text(context, text),
            options: [
              for (final entry in (c.resources['fonts'] as Map? ?? {}).entries)
                EditorFontOption(
                  id: '${entry.key}',
                  family: '${entry.value['family'] ?? 'Font'}',
                ),
            ],
            onSelected: (id) async {
              final properties = Map<String, dynamic>.from(n.properties);
              if (id == null) {
                properties.remove('fontId');
              } else {
                properties['fontId'] = id;
              }
              c.updateNode(n.copyWith(properties: properties));
            },
          ),
          const SizedBox(height: 12),
          _number(
            'Font size',
            p['size'] as num? ?? 24,
            (v) => _property(n, 'size', v),
          ),
          _number(
            'Line height',
            p['lineHeight'] as num? ?? 1.2,
            (v) => _property(n, 'lineHeight', v),
          ),
          Wrap(
            spacing: 8,
            children: [
              FilterChip(
                label: const LayoutText('Bold'),
                selected: p['bold'] == true,
                onSelected: (c.readOnly || c.saving)
                    ? null
                    : (v) => _property(n, 'bold', v),
              ),
              FilterChip(
                label: const LayoutText('Italic'),
                selected: p['italic'] == true,
                onSelected: (c.readOnly || c.saving)
                    ? null
                    : (v) => _property(n, 'italic', v),
              ),
            ],
          ),
          DropdownButtonFormField<String>(
            initialValue: '${p['align'] ?? 'left'}',
            decoration: InputDecoration(
              labelText: VenueLayoutStrings.text(context, 'Text alignment'),
            ),
            items: [
              for (final v in ['left', 'center', 'right'])
                DropdownMenuItem(value: v, child: LayoutText(v)),
            ],
            onChanged: (c.readOnly || c.saving)
                ? null
                : (v) => _property(n, 'align', v),
          ),
          const SizedBox(height: 12),
        ],
        if (n.kind == 'capacityArea')
          _number(
            'Standing capacity',
            p['capacity'] as num? ?? 0,
            (v) => _property(n, 'capacity', v.toInt()),
          ),
        if (openPath) ...[
          _field(
            'Outline #RRGGBBAA',
            '${p['stroke'] ?? '#334155FF'}',
            (v) => _property(n, 'stroke', v),
          ),
          _number(
            'Outline width',
            p['strokeWidth'] as num? ?? 1,
            (v) => _property(n, 'strokeWidth', v),
          ),
          _outlineStyle(n, p),
        ],
        ExpansionTile(
          key: ValueKey('geometry-${n.id}'),
          title: const LayoutText('Geometry'),
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(top: 8),
          children: [
            _number('Position X', n.x, (v) => c.updateNode(n.copyWith(x: v))),
            _number('Position Y', n.y, (v) => c.updateNode(n.copyWith(y: v))),
            if (p['assembly'] != 'rows') ...[
              const SizedBox(height: 12),
              if (n.kind != 'group')
                _number(
                  'Width',
                  n.width,
                  (v) => _resizeDimension(n, v, width: true),
                ),
              if (n.kind != 'group')
                _number(
                  'Height',
                  n.height,
                  (v) => _resizeDimension(n, v, width: false),
                ),
            ],
            _number(
              'Rotation °',
              facingRotation,
              (v) => c.rotateSelection(
                v - facingRotation,
                cornerPivot: widget.cornerPivot,
              ),
            ),
            Wrap(
              children: [
                IconButton(
                  tooltip: VenueLayoutStrings.text(
                    context,
                    'Rotate left 90 degrees',
                  ),
                  onPressed: (c.readOnly || c.saving)
                      ? null
                      : () => c.rotateSelection(
                          -90,
                          cornerPivot: widget.cornerPivot,
                        ),
                  icon: const Icon(Icons.rotate_left),
                ),
                IconButton(
                  tooltip: VenueLayoutStrings.text(
                    context,
                    'Rotate right 90 degrees',
                  ),
                  onPressed: (c.readOnly || c.saving)
                      ? null
                      : () => c.rotateSelection(
                          90,
                          cornerPivot: widget.cornerPivot,
                        ),
                  icon: const Icon(Icons.rotate_right),
                ),
                TextButton(
                  onPressed: (c.readOnly || c.saving)
                      ? null
                      : () => c.rotateSelection(-facingRotation),
                  child: const LayoutText('Reset angle'),
                ),
              ],
            ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const LayoutText('Lock object'),
          value: n.locked,
          onChanged: (c.readOnly || c.saving)
              ? null
              : (v) => c.updateNode(n.copyWith(locked: v)),
        ),
        ExpansionTile(
          key: ValueKey('local-appearance-${n.id}'),
          tilePadding: EdgeInsets.zero,
          title: const LayoutText('Object appearance'),
          subtitle: LayoutText(
            followsPlan ? 'Follows plan style' : 'Local appearance overrides',
          ),
          children: [
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: LayoutText(
                    'Style',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: VenueLayoutStrings.text(context, 'Copy style'),
                  onPressed: widget.onCopyStyle,
                  icon: const Icon(Icons.content_copy, size: 18),
                ),
                IconButton(
                  tooltip: VenueLayoutStrings.text(context, 'Paste style'),
                  onPressed: widget.onPasteStyle,
                  icon: const Icon(Icons.content_paste, size: 18),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const LayoutText('Use plan style'),
              subtitle: LayoutText(
                followsPlan
                    ? 'Follows plan style'
                    : 'Local appearance overrides',
              ),
              value: followsPlan,
              onChanged: c.readOnly || c.saving
                  ? null
                  : (value) => c.apply(
                      followPlanAppearance(c.document, {n.id}, value),
                      label: 'Use plan style',
                    ),
            ),
            LayoutStylePresets(controller: c),
            const SizedBox(height: 12),
            if (n.kind == 'table' || n.kind == 'group' || isCouchNode(n))
              _seatAppearance(n),
            if (p['assembly'] != 'rows') ...[
              if (!openPath && n.kind != 'group')
                _field(
                  n.kind == 'text' ? 'Text color #RRGGBBAA' : 'Fill #RRGGBBAA',
                  n.kind == 'text'
                      ? '${p['color'] ?? '#202830FF'}'
                      : _nodeFill(n),
                  (v) {
                    if (!RegExp(r'^#[0-9a-fA-F]{8}$').hasMatch(v)) {
                      throw const FormatException(
                        'Use #RRGGBBAA including opacity.',
                      );
                    }
                    _property(n, n.kind == 'text' ? 'color' : 'fill', v);
                  },
                ),
            ],
          ],
        ),
        ExpansionTile(
          title: const LayoutText('Advanced object properties'),
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(top: 8),
          children: [
            if (n.kind == 'shape')
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const LayoutText('Blocks seat placement'),
                value: p['obstacle'] == true,
                onChanged: (c.readOnly || c.saving)
                    ? null
                    : (v) => _property(n, 'obstacle', v),
              ),
            if (!openPath) _outlineStyle(n, p),
            const SizedBox(height: 12),
            if (!openPath)
              _field(
                'Outline #RRGGBBAA',
                '${p['stroke'] ?? '#334155FF'}',
                (v) => _property(n, 'stroke', v),
              ),
            _number(
              'Opacity',
              p['opacity'] as num? ?? 1,
              (v) => _property(n, 'opacity', v),
            ),
            if (n.kind == 'shape' && !openPath)
              _number(
                'Corner radius',
                p['cornerRadius'] as num? ??
                    (n.kind == 'table' || p['shape'] == 'roundedRect' ? 6 : 0),
                (v) => _property(n, 'cornerRadius', v),
              ),
            if (!openPath)
              _number(
                'Outline width',
                p['strokeWidth'] as num? ?? 1,
                (v) => _property(n, 'strokeWidth', v),
              ),
            if (p['points'] != null && (n.kind != 'table' || isBarNode(n)))
              _field(
                'Vertices [[x,y], ...]',
                jsonEncode(p['points']),
                (v) => _property(n, 'points', jsonDecode(v)),
                multiline: true,
              ),
          ],
        ),
        if (widget.hostBuilder != null) widget.hostBuilder!(context, n),
      ],
    );
  }

  Future<void> _backgroundSource() async {
    final assets = c.resources['assets'] as Map? ?? const {};
    if (assets.isEmpty) {
      setState(
        () => _error =
            'No background images loaded. Use your host image import first.',
      );
      return;
    }
    final ref = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const LayoutText('Choose background image'),
        children: [
          for (final key in assets.keys)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, '$key'),
              child: LayoutText('$key'),
            ),
        ],
      ),
    );
    if (ref == null || !mounted) return;
    final asset = assets[ref] as Map;
    final before = c.document;
    var mode = 'Keep layout and canvas';
    VenueLayoutDocument candidate() {
      var draft = before;
      if (mode == 'Match image aspect ratio') {
        final ratio = (asset['width'] as num) / (asset['height'] as num);
        final width = (before.canvas['width'] as num).toDouble();
        final height = (before.canvas['height'] as num).toDouble();
        final targetWidth = width > height * ratio ? width : height * ratio;
        draft = resizeCanvas(before, targetWidth, targetWidth / ratio);
      }
      final b = backgroundPlacement(
        (asset['width'] as num).toDouble(),
        (asset['height'] as num).toDouble(),
        draft.canvas,
      );
      if (mode == 'Keep background registration' && before.background != null) {
        final old = before.background!;
        b.addAll({
          'x': old['x'],
          'y': old['y'],
          'rotation': old['rotation'],
          'scale':
              (old['scale'] as num? ?? 1) *
              (old['width'] as num? ?? asset['width']) /
              (asset['width'] as num),
        });
      }
      return draft.copyWith(
        background: {
          ...b,
          'assetRef': ref,
          if (asset['sha256'] != null) 'hash': asset['sha256'],
        },
      );
    }

    final apply = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const LayoutText('Replace background'),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButton<String>(
                  isExpanded: true,
                  value: mode,
                  items: [
                    for (final value in [
                      'Keep layout and canvas',
                      'Keep background registration',
                      'Match image aspect ratio',
                    ])
                      DropdownMenuItem(value: value, child: LayoutText(value)),
                  ],
                  onChanged: (v) => update(() => mode = v!),
                ),
                const LayoutText(
                  'Image crop resets. Seats keep their positions. Matching the image ratio expands the canvas without clipping objects.',
                ),
                SizedBox(
                  height: 260,
                  child: VenueLayoutViewer(
                    key: ValueKey(mode),
                    document: candidate(),
                    resources: c.resources,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const LayoutText('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const LayoutText('Use image'),
            ),
          ],
        ),
      ),
    );
    if (apply == true) {
      c.apply(candidate(), label: 'Replace background');
    }
  }

  Future<void> _registerBackground() async {
    final base = c.document, background = c.document.background!;
    final source = <List<double>>[], target = <List<double>>[];
    Map<String, dynamic>? registered;
    String? error;
    final width = (background['width'] as num).toDouble(),
        height = (background['height'] as num).toDouble();
    final sourceDoc = VenueLayoutDocument.empty().copyWith(
      canvas: {
        'x': 0,
        'y': 0,
        'width': width < 64 ? 64 : width,
        'height': height < 64 ? 64 : height,
        'fill': '#FFFFFFFF',
      },
      background: {
        ...background,
        'x': width / 2,
        'y': height / 2,
        'rotation': 0,
        'scale': 1,
        'crop': {'x': 0, 'y': 0, 'width': 1, 'height': 1},
      },
    );
    final apply = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) {
          void pick(List<List<double>> list, Offset point) => update(() {
            if (list.length == 2) list.clear();
            list.add([point.dx, point.dy]);
            registered = null;
            error = null;
            if (source.length == 2 && target.length == 2) {
              try {
                registered = registerBackground(
                  background,
                  source[0],
                  source[1],
                  target[0],
                  target[1],
                );
              } catch (e) {
                error = '$e';
              }
            }
          });
          return AlertDialog(
            title: const LayoutText('Align background with two points'),
            content: SizedBox(
              width: 620,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LayoutText(
                      '1. Tap two recognizable points on the source image (${source.length}/2).',
                    ),
                    SizedBox(
                      height: 190,
                      child: LayoutSceneSurface(
                        document: sourceDoc,
                        resources: c.resources,
                        onTap: (p) => pick(source, p),
                      ),
                    ),
                    LayoutText(
                      '2. Tap the matching plan positions in the same order (${target.length}/2).',
                    ),
                    SizedBox(
                      height: 190,
                      child: LayoutSceneSurface(
                        document: registered == null
                            ? base
                            : base.copyWith(background: registered),
                        resources: c.resources,
                        onTap: (p) => pick(target, p),
                      ),
                    ),
                    if (registered != null)
                      const LayoutText(
                        'Preview aligned. Seats have not moved. Tap again to restart a point pair.',
                      ),
                    if (error != null) LayoutText(error!),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const LayoutText('Cancel'),
              ),
              FilledButton(
                onPressed: registered == null
                    ? null
                    : () => Navigator.pop(context, true),
                child: const LayoutText('Apply alignment'),
              ),
            ],
          );
        },
      ),
    );
    if (apply == true && registered != null) {
      c.apply(
        base.copyWith(background: registered),
        label: 'Register background',
      );
    }
  }

  Widget _backgroundControls() {
    final b = c.document.background;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.onImportBackground != null)
          OutlinedButton.icon(
            onPressed: (c.readOnly || c.saving)
                ? null
                : () async {
                    try {
                      await widget.onImportBackground!();
                    } catch (e) {
                      if (mounted) setState(() => _error = '$e');
                    }
                  },
            icon: const Icon(Icons.upload_file_outlined),
            label: const LayoutText('Upload background image'),
          ),
        if ((c.resources['assets'] as Map? ?? const {}).isNotEmpty)
          OutlinedButton(
            onPressed: (c.readOnly || c.saving) ? null : _backgroundSource,
            child: LayoutText(b == null ? 'Choose image' : 'Replace image'),
          ),
        if (b != null) ...[
          OutlinedButton(
            onPressed: (c.readOnly || c.saving) ? null : _registerBackground,
            child: const LayoutText('Align using two points'),
          ),
          Wrap(
            children: [
              for (final mode in ['contain', 'fill'])
                TextButton(
                  onPressed: (c.readOnly || c.saving)
                      ? null
                      : () => _run(
                          () => c.apply(
                            c.document.copyWith(
                              background: {
                                ...b,
                                ...backgroundPlacement(
                                  (b['width'] as num).toDouble(),
                                  (b['height'] as num).toDouble(),
                                  c.document.canvas,
                                  fit: mode,
                                ),
                              },
                            ),
                            label: 'Place background',
                          ),
                        ),
                  child: LayoutText(
                    mode == 'contain' ? 'Fit whole image' : 'Fill canvas',
                  ),
                ),
            ],
          ),
          OutlinedButton(
            onPressed: (c.readOnly || c.saving)
                ? null
                : () {
                    final base = c.document;
                    _preview(
                      'Transform background',
                      (v) => base.copyWith(
                        background: {
                          ...b,
                          'x': v['X'],
                          'y': v['Y'],
                          'scale': v['Scale'],
                          'rotation': v['Rotation'],
                          'opacity': v['Opacity'],
                        },
                      ),
                      {
                        'X': (b['x'] as num? ?? 0).toDouble(),
                        'Y': (b['y'] as num? ?? 0).toDouble(),
                        'Scale': (b['scale'] as num? ?? 1).toDouble(),
                        'Rotation': (b['rotation'] as num? ?? 0).toDouble(),
                        'Opacity': (b['opacity'] as num? ?? 1).toDouble(),
                      },
                    );
                  },
            child: const LayoutText('Transform image'),
          ),
          OutlinedButton(
            onPressed: (c.readOnly || c.saving)
                ? null
                : () {
                    final base = c.document;
                    final crop = b['crop'] as Map? ?? const {};
                    _preview(
                      'Crop image',
                      (v) => base.copyWith(
                        background: {
                          ...b,
                          'crop': {
                            'x': v['Left'],
                            'y': v['Top'],
                            'width': v['Width'],
                            'height': v['Height'],
                          },
                        },
                      ),
                      {
                        'Left': (crop['x'] as num? ?? 0).toDouble(),
                        'Top': (crop['y'] as num? ?? 0).toDouble(),
                        'Width': (crop['width'] as num? ?? 1).toDouble(),
                        'Height': (crop['height'] as num? ?? 1).toDouble(),
                      },
                      detail:
                          'Normalized image coordinates, from 0 to 1. Original pixels are retained.',
                    );
                  },
            child: const LayoutText('Crop image'),
          ),
          TextButton(
            onPressed: (c.readOnly || c.saving)
                ? null
                : () => c.apply(
                    c.document.copyWith(clearBackground: true),
                    label: 'Remove background',
                  ),
            child: const LayoutText('Remove image'),
          ),
        ],
      ],
    );
  }

  Widget _canvas() => ExpansionTile(
    key: ValueKey('canvas-${widget.canvasSelected}'),
    initiallyExpanded: widget.canvasSelected,
    tilePadding: EdgeInsets.zero,
    title: const LayoutText('Canvas'),
    children: [
      const SizedBox(height: 12),
      if (widget.canvasSelected) ...[
        _number(
          'Width',
          c.document.canvas['width'] as num,
          (value) => c.apply(
            resizeCanvas(
              c.document,
              value,
              (c.document.canvas['height'] as num).toDouble(),
            ),
            label: 'Canvas width',
          ),
        ),
        _number(
          'Height',
          c.document.canvas['height'] as num,
          (value) => c.apply(
            resizeCanvas(
              c.document,
              (c.document.canvas['width'] as num).toDouble(),
              value,
            ),
            label: 'Canvas height',
          ),
        ),
      ],
      if (!widget.canvasSelected)
        OutlinedButton(
          onPressed: (c.readOnly || c.saving)
              ? null
              : () {
                  final base = c.document;
                  _preview(
                    'Canvas size',
                    (v) => resizeCanvas(base, v['Width']!, v['Height']!),
                    {
                      'Width': (base.canvas['width'] as num).toDouble(),
                      'Height': (base.canvas['height'] as num).toDouble(),
                    },
                    detail:
                        'Objects keep their positions. A smaller canvas cannot hide seats.',
                  );
                },
          child: const LayoutText('Set canvas size'),
        ),
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LayoutText(
          'Objects stay in place. To move an object that fills the canvas, increase Width or Height first.',
        ),
      ),
      TextButton(
        onPressed: (c.readOnly || c.saving)
            ? null
            : () => _run(
                () => c.apply(
                  fitCanvas(c.document),
                  label: 'Fit canvas to content',
                ),
              ),
        child: const LayoutText('Fit canvas to content'),
      ),
      const SizedBox(height: 8),
      _canvasColor(),
      LayoutFloorStyleField(controller: c),
      const LayoutText('Schematic size. No physical measurements required.'),
      const SizedBox(height: 8),
      _backgroundControls(),
    ],
  );
  Widget _canvasColor() => _field(
    'Background #RRGGBBAA',
    '${c.document.canvas['fill'] ?? '#FFFFFFFF'}',
    (v) => c.apply(
      c.document.copyWith(canvas: {...c.document.canvas, 'fill': v}),
      label: 'Canvas color',
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (!identical(_indexedDocument, c.document)) {
      _indexedDocument = c.document;
      _nodesById = {for (final node in c.document.nodes) node.id: node};
    }
    final selection = c.selection;
    final selected = c.document.nodes
        .where((n) => selection.contains(n.id))
        .toList();
    final ids = selected.map((node) => node.id).toList()..sort();
    final selectionContext = '${widget.canvasSelected}:${ids.join(',')}';
    if (_selectionContext != selectionContext) {
      _selectionContext = selectionContext;
      _error = null;
      _search = '';
    }
    final layers = _layersExpanded ? _layers() : const <LayoutNode>[];

    Widget layerAction(
      String label,
      IconData icon, {
      int? direction,
      bool? toFront,
    }) => IconButton(
      tooltip: VenueLayoutStrings.text(context, label),
      icon: Icon(icon, size: 19),
      onPressed: c.readOnly || c.saving || selection.isEmpty
          ? null
          : () => _run(
              () => c.apply(
                direction == null
                    ? moveLayoutLayers(
                        c.document,
                        c.selection,
                        toFront: toFront!,
                      )
                    : reorderLayoutLayers(
                        c.document,
                        c.selection,
                        direction: direction,
                      ),
                label: label,
              ),
            ),
    );
    return Material(
      color: layoutPanelColor(context),
      child: SingleChildScrollView(
        key: ValueKey('inspector-context-$selectionContext'),
        primary: false,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: LayoutText(
                    selected.length == 1
                        ? (selected.single.label.isEmpty
                              ? _typeTitle(selected.single)
                              : selected.single.label)
                        : selected.length > 1
                        ? '${selected.length} objects selected. Individual values vary.'
                        : widget.canvasSelected
                        ? 'Canvas'
                        : 'Properties',
                    key: const ValueKey('inspector-heading'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (selected.isNotEmpty || widget.canvasSelected)
                  IconButton(
                    key: const ValueKey('clear-layout-selection'),
                    tooltip: VenueLayoutStrings.text(
                      context,
                      'Clear selection',
                    ),
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: widget.onClearSelection ?? () => c.select({}),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Semantics(
                  liveRegion: true,
                  child: LayoutText(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
            if (selected.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: LayoutText(
                  widget.canvasSelected
                      ? 'Canvas selected. Drag an edge or corner to resize. Escape exits.'
                      : 'Select an object on the plan or in Layers to edit it.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (selected.length == 1)
              KeyedSubtree(
                key: ValueKey(selected.first.id),
                child: _node(selected.first),
              ),
            if (selected.length > 1)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const LayoutText('Object appearance'),
                children: [
                  LayoutText(
                    'Style',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  LayoutStylePresets(controller: c),
                  const SizedBox(height: 12),
                  _field('Selected fill #RRGGBBAA', _nodeFill(selected.first), (
                    value,
                  ) {
                    final targets = <String>{};
                    for (final root in selected.where((n) => !n.locked)) {
                      targets.addAll(
                        root.kind == 'group'
                            ? layoutSubtree(c.document, {root.id})
                            : {root.id},
                      );
                    }
                    c.apply(
                      c.document.copyWith(
                        nodes: [
                          for (final n in c.document.nodes)
                            if (targets.contains(n.id) &&
                                !n.locked &&
                                n.kind != 'group')
                              n.copyWith(
                                properties: localAppearanceProperties(n, {
                                  n.kind == 'text' ? 'color' : 'fill': value,
                                }),
                              )
                            else
                              n,
                        ],
                      ),
                      label: 'Change selected colors',
                    );
                  }),
                ],
              ),
            if (selected.isNotEmpty) const Divider(height: 24),
            if (selected.isNotEmpty)
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: (c.readOnly || c.saving)
                        ? null
                        : c.duplicateSelection,
                    child: const LayoutText('Duplicate'),
                  ),
                  TextButton(
                    onPressed: (c.readOnly || c.saving)
                        ? null
                        : c.deleteSelection,
                    child: const LayoutText('Delete'),
                  ),
                  if (selected.length > 1)
                    TextButton(
                      onPressed: (c.readOnly || c.saving)
                          ? null
                          : () => _run(
                              () => c.apply(
                                groupNodes(c.document, c.selection),
                                label: 'Group',
                              ),
                            ),
                      child: const LayoutText('Group'),
                    ),
                  if (selected.any(
                    (node) =>
                        node.kind == 'group' &&
                        node.properties['assembly'] == null,
                  ))
                    TextButton(
                      onPressed: (c.readOnly || c.saving)
                          ? null
                          : () => _run(
                              () => c.apply(
                                ungroupNodes(c.document, c.selection),
                                label: 'Ungroup',
                              ),
                            ),
                      child: const LayoutText('Ungroup'),
                    ),
                ],
              ),
            if (selected.length > 1)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const LayoutText('Align and distribute'),
                children: [
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final entry in {
                        'left': 'Align left',
                        'centerX': 'Center horizontally',
                        'right': 'Align right',
                        'top': 'Align top',
                        'centerY': 'Center vertically',
                        'bottom': 'Align bottom',
                      }.entries)
                        TextButton(
                          onPressed: (c.readOnly || c.saving)
                              ? null
                              : () => _run(
                                  () => c.apply(
                                    alignNodes(
                                      c.document,
                                      c.selection,
                                      entry.key,
                                    ),
                                    label: entry.value,
                                  ),
                                ),
                          child: LayoutText(entry.value),
                        ),
                      TextButton(
                        onPressed:
                            (c.readOnly || c.saving) || selected.length < 3
                            ? null
                            : () => _run(
                                () => c.apply(
                                  distributeNodes(
                                    c.document,
                                    c.selection,
                                    horizontal: true,
                                  ),
                                  label: 'Distribute horizontally',
                                ),
                              ),
                        child: const LayoutText('Distribute horizontally'),
                      ),
                      TextButton(
                        onPressed:
                            (c.readOnly || c.saving) || selected.length < 3
                            ? null
                            : () => _run(
                                () => c.apply(
                                  distributeNodes(
                                    c.document,
                                    c.selection,
                                    horizontal: false,
                                  ),
                                  label: 'Distribute vertically',
                                ),
                              ),
                        child: const LayoutText('Distribute vertically'),
                      ),
                    ],
                  ),
                ],
              ),
            const Divider(height: 24),
            if (selected.isEmpty) ...[
              OutlinedButton.icon(
                onPressed: c.readOnly || c.saving
                    ? null
                    : () => showLayoutGlobalStyleDialog(context, c),
                icon: const Icon(Icons.palette_outlined),
                label: const LayoutText('Plan style'),
              ),
              const SizedBox(height: 12),
              _canvas(),
            ],
            ExpansionTile(
              title: const LayoutText('Layers'),
              initiallyExpanded: _layersExpanded,
              onExpansionChanged: (value) =>
                  setState(() => _layersExpanded = value),
              tilePadding: EdgeInsets.zero,
              children: [
                if (_layersExpanded) ...[
                  Row(
                    children: [
                      layerAction(
                        'Bring to front',
                        Icons.vertical_align_top,
                        toFront: true,
                      ),
                      layerAction(
                        'Bring forward',
                        Icons.arrow_upward,
                        direction: 1,
                      ),
                      layerAction(
                        'Send backward',
                        Icons.arrow_downward,
                        direction: -1,
                      ),
                      layerAction(
                        'Send to back',
                        Icons.vertical_align_bottom,
                        toFront: false,
                      ),
                    ],
                  ),
                  TextField(
                    decoration: InputDecoration(
                      labelText: VenueLayoutStrings.text(
                        context,
                        'Find object',
                      ),
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (v) => setState(() => _search = v),
                  ),
                  _rows(layers, selection),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PropertyField extends StatefulWidget {
  const _PropertyField({
    super.key,
    required this.label,
    required this.value,
    required this.enabled,
    required this.multiline,
    this.numeric = false,
    required this.save,
    this.usedColors,
    this.paletteImage,
  });
  final List<String> Function()? usedColors;
  final ui.Image? paletteImage;
  final String label, value;
  final bool enabled, multiline, numeric;
  final ValueChanged<String> save;
  @override
  State<_PropertyField> createState() => _PropertyFieldState();
}

class _PropertyFieldState extends State<_PropertyField> {
  late final _text = TextEditingController(text: widget.value);
  final _focus = FocusNode();
  String? _submittedThisFrame;
  @override
  void initState() {
    super.initState();
    _focus.onKeyEvent = (_, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape) {
        _text.text = widget.value;
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
    _focus.addListener(_focusChanged);
  }

  void _focusChanged() {
    if (!_focus.hasFocus && widget.enabled && _text.text != widget.value) {
      if (_text.value.composing.isValid && !_text.value.composing.isCollapsed) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_focus.hasFocus) _save();
        });
      } else {
        _save();
      }
    }
  }

  @override
  void didUpdateWidget(_PropertyField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value &&
        (!_focus.hasFocus || _text.text == oldWidget.value)) {
      _text.text = widget.value;
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_focusChanged);
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _save() {
    if (!widget.enabled ||
        (_text.value.composing.isValid && !_text.value.composing.isCollapsed)) {
      return;
    }
    final value = _text.text;
    if (value == widget.value || value == _submittedThisFrame) return;
    // Blur and the suffix button can both submit before the model rebuilds.
    // Release next frame even after rejection so the same edit can be retried.
    _submittedThisFrame = value;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _submittedThisFrame == value) _submittedThisFrame = null;
    });
    widget.save(value);
  }

  Future<void> _chooseColor() async {
    EditorColorValue initial;
    try {
      initial = EditorColorValue.fromRgba(_text.text);
    } on FormatException {
      initial = EditorColorValue.fromRgba(widget.value);
    }
    final usedColors = widget.usedColors?.call() ?? const <String>[];
    final result = await showDialog<EditorColorResult>(
      context: context,
      builder: (_) => EditorColorDialog(
        value: initial,
        usedColors: usedColors,
        image: widget.paletteImage,
        translate: (text) => VenueLayoutStrings.text(context, text),
      ),
    );
    if (result == null || !mounted) return;
    _text.text = result.primary.rgba;
    _save();
  }

  @override
  Widget build(BuildContext context) => EditorNumberScroll(
    enabled: widget.enabled && widget.numeric,
    min:
        const [
          'Position X',
          'Position Y',
          'Rotation °',
          'Curvature',
        ].contains(widget.label)
        ? null
        : widget.label == 'Line height'
        ? .8
        : const [
            'Width',
            'Height',
            'Chair width',
            'Chair depth',
            'Font size',
            'Number of teeth',
            'Number of rows',
            'Seats per row',
            'Blocks',
            'Seats on couch',
          ].contains(widget.label)
        ? 1
        : 0,
    max: widget.label == 'Opacity'
        ? 1
        : widget.label == 'Line height'
        ? 3
        : widget.label == 'Number of teeth'
        ? 255
        : null,
    step: widget.label == 'Opacity'
        ? .05
        : widget.label == 'Line height'
        ? .1
        : 1,
    onChanged: _save,
    child: TextField(
      controller: _text,
      focusNode: _focus,
      enabled: widget.enabled,
      minLines: widget.multiline ? 2 : 1,
      maxLines: widget.multiline ? 6 : 1,
      decoration: InputDecoration(
        labelText: VenueLayoutStrings.text(context, widget.label),
        border: const OutlineInputBorder(),
        isDense: true,
        prefixIcon: widget.label.contains('#RRGGBBAA')
            ? IconButton(
                tooltip: VenueLayoutStrings.text(context, 'Choose color'),
                onPressed: widget.enabled ? _chooseColor : null,
                icon: EditorColorSwatch(
                  value: EditorColorValue.fromRgba(widget.value),
                ),
              )
            : null,
        suffixIcon: IconButton(
          tooltip: VenueLayoutStrings.text(context, 'Apply ${widget.label}'),
          onPressed: widget.enabled ? _save : null,
          icon: const Icon(Icons.check),
        ),
      ),
      onTapOutside: (_) {
        if (_text.value.composing.isValid) {
          _text.value = _text.value.copyWith(composing: TextRange.empty);
        }
        _save();
        _focus.unfocus();
      },
      onSubmitted: (_) => _save(),
    ),
  );
}
