import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:venue_layout_core/venue_layout_core.dart';
import '../venue_layout_controller.dart';
import 'layout_scene_surface.dart';
import 'layout_strings.dart';

/// A small specimen rendered through the real scene compiler, independent of
/// the plan's size, selection and reservation state.
class LayoutAppearancePreview extends StatefulWidget {
  const LayoutAppearancePreview({
    super.key,
    required this.controller,
    required this.kind,
    this.seatStyle,
    this.appearance = const {},
    this.width,
    this.floorStyle,
    this.height = 112,
    this.chairCount,
  });
  final VenueLayoutController controller;
  final String kind;
  final String? seatStyle;
  final Map<String, Map<String, dynamic>> appearance;
  final double? width;
  final String? floorStyle;
  final double height;

  /// Optional capacity simulation on a fixed 260 x 150 sample table.
  final int? chairCount;
  @override
  State<LayoutAppearancePreview> createState() => _PreviewState();
}

class _PreviewState extends State<LayoutAppearancePreview> {
  static final _specimens = <String, VenueLayoutDocument>{};
  String? _signature;
  Map<String, dynamic>? _resources;
  late Map<String, dynamic> _scene;
  late Rect _frame;
  int _fittedChairs = 0;

  VenueLayoutDocument _specimen(String kind) =>
      _specimens.putIfAbsent(kind, () {
        if (kind == 'transport') return busLayout(rows: 3, rear: 5, x: 0, y: 0);
        if (kind == 'collection') {
          final table = tableLayout(
            shape: 'roundedRect',
            x: 0,
            y: 0,
            width: 140,
            height: 85,
            count: 4,
          );
          final couch = couchLayout(
            x: 215,
            y: 45,
            width: 130,
            height: 85,
            count: 2,
          );
          return table.copyWith(
            nodes: [
              ...table.nodes,
              ...couch.nodes,
              LayoutNode(
                id: newLayoutId(),
                kind: 'seat',
                x: 215,
                y: -70,
                width: 68,
                height: 68,
              ),
            ],
            selectionUnits: couch.selectionUnits,
          );
        }
        if (kind == 'table') return tableLayout(shape: 'roundedRect');
        if (kind == 'furniture') return couchLayout(count: 3);
        return VenueLayoutDocument(
          nodes: [
            LayoutNode(
              id: newLayoutId(),
              kind: kind,
              label: kind == 'text' ? 'Aa' : '',
              width: kind == 'seat' ? 38 : 150,
              height: kind == 'seat' ? 38 : 70,
              properties: kind == 'shape' ? {'shape': 'rectangle'} : const {},
            ),
          ],
        );
      });

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final signature = jsonEncode([
      widget.kind,
      widget.chairCount,
      if (widget.chairCount != null) documentSeating(c.document).properties,
      widget.seatStyle,
      widget.appearance,
      widget.floorStyle,
      c.document.canvas['floorStyle'],
      c.document.appearance,
      c.document.canvas['fill'],
      c.document.defaultTextStyle,
    ]);
    if (_signature != signature || !identical(_resources, c.resources)) {
      final base = widget.chairCount == null
          ? _specimen(widget.kind)
          : _specimens.putIfAbsent(
              'chair-simulation',
              () => tableLayout(
                shape: 'roundedRect',
                width: 260,
                height: 150,
                count: 0,
                x: 0,
                y: 0,
              ),
            );
      final appearance = <String, dynamic>{...c.document.appearance};
      for (final entry in widget.appearance.entries) {
        appearance[entry.key] = {
          ...?appearance[entry.key] as Map?,
          ...entry.value,
        };
      }
      if (widget.seatStyle != null) {
        appearance['seat'] = {
          ...?appearance['seat'] as Map?,
          'seatStyle': widget.seatStyle,
        };
      }
      var doc = base.copyWith(
        appearance: appearance,
        defaultTextStyle: c.document.defaultTextStyle,
        nodes: [
          for (final n in base.nodes)
            n.copyWith(label: widget.kind == 'text' ? 'Aa' : ''),
        ],
      );
      final profile = appearance['table'] as Map? ?? const {};
      if (widget.chairCount != null) {
        final defaults = documentSeating(c.document);
        doc = configurePlanTableSeating(
          doc,
          width: (profile['seatWidth'] as num?)?.toDouble() ?? defaults.width,
          height:
              (profile['seatHeight'] as num?)?.toDouble() ?? defaults.height,
          gap: (profile['seatGap'] as num?)?.toDouble() ?? defaults.gap,
          spacing:
              (profile['seatSpacing'] as num?)?.toDouble() ?? defaults.spacing,
          edgePadding:
              (profile['seatEdgePadding'] as num?)?.toDouble() ??
              defaults.edgePadding,
          constrainToCanvas: false,
        );
        final table = doc.nodes.single;
        _fittedChairs = math.min(
          widget.chairCount!.clamp(0, 24),
          tableCapacity(table),
        );
        // Capacity is an upper bound. Deep seats can exhaust collision-free
        // slots sooner; show the largest real arrangement, never fake overlaps.
        while (_fittedChairs > 0) {
          try {
            doc = reflowTable(doc, table.id, _fittedChairs);
            break;
          } on ArgumentError {
            _fittedChairs--;
          } on StateError {
            _fittedChairs--;
          }
        }
      } else if (layoutSeatingDefaultKeys.any(profile.containsKey)) {
        final replacements = <String, LayoutNode>{};
        for (final table in doc.nodes.where(
          (node) => node.kind == 'table' && !isBarNode(node),
        )) {
          // Keep the specimen usable even when a draft is too large for the
          // real table. The actual plan still validates its physical fit.
          final seating = TableSeating.fromTable(table).copyWith(
            width: (profile['seatWidth'] as num?)?.toDouble(),
            spacing: (profile['seatSpacing'] as num?)?.toDouble(),
            edgePadding: (profile['seatEdgePadding'] as num?)?.toDouble(),
          );
          final sampleTable = table.copyWith(
            width: math.max(
              table.width,
              2 * seating.pitch + 2 * seating.edgePadding + 1,
            ),
            height: math.max(
              table.height,
              seating.pitch + 2 * seating.edgePadding + 1,
            ),
          );
          final members = [
            sampleTable,
            ...doc.nodes.where((node) => node.parentId == table.id),
          ];
          final sample = VenueLayoutDocument(
            nodes: members,
            attachments: [
              for (final attachment in doc.attachments)
                if (attachment['targetId'] == table.id) attachment,
            ],
          );
          final configured = configurePlanTableSeating(
            sample,
            width: (profile['seatWidth'] as num?)?.toDouble(),
            height: (profile['seatHeight'] as num?)?.toDouble(),
            gap: (profile['seatGap'] as num?)?.toDouble(),
            spacing: (profile['seatSpacing'] as num?)?.toDouble(),
            edgePadding: (profile['seatEdgePadding'] as num?)?.toDouble(),
            constrainToCanvas: false,
          );
          replacements.addEntries(
            configured.nodes.map((node) => MapEntry(node.id, node)),
          );
        }
        doc = doc.copyWith(
          nodes: [for (final node in doc.nodes) replacements[node.id] ?? node],
        );
      }
      final bounds = selectionBounds(doc, doc.nodes.map((n) => n.id).toSet());
      _frame = Rect.fromLTWH(
        bounds['x']!,
        bounds['y']!,
        bounds['width']!,
        bounds['height']!,
      ).inflate(16);
      _scene = compileScene(
        doc.copyWith(
          canvas: {
            'x': _frame.left,
            'y': _frame.top,
            'width': _frame.width,
            'height': _frame.height,
            'fill': c.document.canvas['fill'] ?? '#FFFFFFFF',
            'floorStyle':
                widget.floorStyle ?? c.document.canvas['floorStyle'] ?? 'plain',
          },
        ),
        resources: c.resources,
      );
      _resources = c.resources;
      _signature = signature;
    }
    final width =
        widget.width ?? (widget.kind == 'seat' ? widget.height : 240.0);
    final scale = math.min(width / _frame.width, widget.height / _frame.height);
    final preview = Semantics(
      label: VenueLayoutStrings.text(context, 'Live preview'),
      image: true,
      child: SizedBox(
        height: widget.height,
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CustomPaint(
                size: Size(width, widget.height),
                painter: LayoutScenePainter(
                  scene: _scene,
                  resources: c.resources,
                  selected: const {},
                  scale: scale,
                  offset: Offset(
                    (width - _frame.width * scale) / 2 - _frame.left * scale,
                    (widget.height - _frame.height * scale) / 2 -
                        _frame.top * scale,
                  ),
                  canvasColor: Colors.transparent,
                  selectionColor: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (widget.chairCount == null || _fittedChairs >= widget.chairCount!) {
      return preview;
    }
    return Column(
      children: [
        preview,
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('$_fittedChairs / ${widget.chairCount}'),
            const SizedBox(width: 8),
            const Flexible(
              child: LayoutText(
                'The table is full. Reduce the chair size or spacing.',
              ),
            ),
          ],
        ),
      ],
    );
  }
}
