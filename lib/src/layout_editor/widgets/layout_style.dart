import 'dart:ui' as ui;
import 'dart:math' as math;
import 'layout_scene_surface.dart';
import 'package:flutter/material.dart';
import 'package:venue_layout_core/venue_layout_core.dart';
import 'package:venue_seat_picker/editor_ui.dart';
import '../venue_layout_controller.dart';
import 'layout_strings.dart';

/// Neutral work panels in light mode, with the host surface retained in dark mode.
Color layoutPanelColor(BuildContext context) {
  final theme = Theme.of(context);
  return theme.brightness == Brightness.light
      ? Colors.white
      : theme.colorScheme.surface;
}

/// Visual properties only: never transfers geometry, labels or seat identities.
class LayoutAppearance {
  const LayoutAppearance(this.object, {this.seats, this.canvasFill});
  final Map<String, dynamic> object;
  final Map<String, dynamic>? seats;
  final String? canvasFill;
}

const layoutAppearancePresets = <String, LayoutAppearance>{
  'Original': LayoutAppearance(
    {
      'fill': '#FFFFFFFF',
      'stroke': '#000000FF',
      'color': '#000000FF',
      'strokeWidth': 1,
      'cornerRadius': 0,
    },
    seats: {
      'fill': '#267329FF',
      'stroke': '#00000000',
      'strokeWidth': 0,
      'cornerRadius': 8,
      'seatStyle': 'plain',
    },
    canvasFill: '#FFFFFFFF',
  ),
  'Neutral': LayoutAppearance(
    {
      'fill': '#E2E8F0FF',
      'color': '#202830FF',
      'stroke': '#475569FF',
      'strokeWidth': 1,
      'cornerRadius': 6,
    },
    seats: {
      'fill': '#DCFCE7FF',
      'stroke': '#475569FF',
      'strokeWidth': 1,
      'cornerRadius': 5,
      'seatStyle': 'plain',
    },
    canvasFill: '#FFFFFFFF',
  ),
  'Warm': LayoutAppearance(
    {
      'fill': '#F0E4D2FF',
      'color': '#5D4431FF',
      'stroke': '#8A6A48FF',
      'strokeWidth': 1,
      'cornerRadius': 14,
    },
    seats: {
      'fill': '#D9B788FF',
      'stroke': '#886342FF',
      'strokeWidth': 1.3,
      'cornerRadius': 8,
      'seatStyle': 'wood',
    },
    canvasFill: '#FFFBF5FF',
  ),
  'Slate': LayoutAppearance(
    {
      'fill': '#CBD5E1FF',
      'color': '#1E293BFF',
      'stroke': '#334155FF',
      'strokeWidth': 1.5,
      'cornerRadius': 2,
    },
    seats: {
      'fill': '#DBEAFEFF',
      'stroke': '#1E40AFFF',
      'strokeWidth': 1.5,
      'cornerRadius': 1,
      'seatStyle': 'upholstered',
    },
    canvasFill: '#F1F5F9FF',
  ),
};

final layoutColorPalettes = <String, LayoutAppearance>{
  for (final entry in layoutAppearancePresets.entries)
    entry.key: LayoutAppearance(
      {
        for (final e in entry.value.object.entries)
          if (const {'fill', 'stroke', 'color'}.contains(e.key)) e.key: e.value,
      },
      seats: {
        for (final e in (entry.value.seats ?? entry.value.object).entries)
          if (const {'fill', 'stroke', 'color'}.contains(e.key)) e.key: e.value,
      },
      canvasFill: entry.value.canvasFill,
    ),
};

String layoutNodeFill(
  VenueLayoutDocument document,
  LayoutNode node, {
  Map<String, LayoutNode>? nodesById,
}) {
  final props = effectiveNodeProperties(document, node);
  if (props['fill'] is String) {
    return props['fill'] as String;
  }
  if (node.kind == 'seat') {
    final parent = nodesById == null
        ? document.nodes.where((n) => n.id == node.parentId).firstOrNull
        : nodesById[node.parentId];
    return parent?.properties['furniture'] == 'couch'
        ? '#F8FAFCFF'
        : '#DCFCE7FF';
  }
  return switch (node.kind) {
    'table' => '#E2E8F0FF',
    'capacityArea' => '#DBEAFEFF',
    _ => '#F1F5F9FF',
  };
}

const _visualKeys = [
  'objectStyle',
  'seatStyle',
  'color',
  'fill',
  'stroke',
  'strokeWidth',
  'opacity',
  'cornerRadius',
  'dash',
];
const _textKeys = [
  'objectStyle',
  'color',
  'fontId',
  'size',
  'bold',
  'italic',
  'align',
  'lineHeight',
  'opacity',
];
LayoutAppearance captureLayoutAppearance(
  VenueLayoutDocument document,
  String id,
) {
  final root = document.nodes.firstWhere((n) => n.id == id);
  Map<String, dynamic> capture(LayoutNode n) => {
    if (n.kind != 'text') ...{
      'fill': layoutNodeFill(document, n),
      'stroke': '#475569FF',
      'strokeWidth': 1,
      'opacity': 1,
      'dash': <int>[],
    },
    'color': document.defaultTextStyle['color'] ?? '#222222FF',
    if (n.kind == 'text') 'opacity': 1,
    for (final key in n.kind == 'text' ? _textKeys : _visualKeys)
      if (effectiveNodeProperties(document, n).containsKey(key))
        key: effectiveNodeProperties(document, n)[key],
  };
  final ids = layoutSubtree(document, {id});
  final seat = document.nodes
      .where((n) => ids.contains(n.id) && n.kind == 'seat' && n.id != id)
      .firstOrNull;
  return LayoutAppearance(
    capture(root),
    seats: seat == null ? null : capture(seat),
  );
}

const _globalVisualKeys = {
  'objectStyle',
  'seatStyle',
  'fill',
  'stroke',
  'strokeWidth',
  'cornerRadius',
  'opacity',
  'color',
};
Map<String, dynamic> localAppearanceProperties(
  LayoutNode node,
  Map<String, dynamic> patch,
) => {
  ...node.properties,
  ...patch,
  if (patch.keys.any(_globalVisualKeys.contains))
    'appearanceOverrides': {
      ...((node.properties['appearanceOverrides'] as List?) ?? const [])
          .cast<String>(),
      ...patch.keys.where(_globalVisualKeys.contains),
    }.toList(),
};

VenueLayoutDocument followPlanAppearance(
  VenueLayoutDocument document,
  Set<String> roots,
  bool follow,
) {
  final targets = layoutSubtree(document, roots);
  final byId = {for (final n in document.nodes) n.id: n};
  bool locked(LayoutNode node) {
    LayoutNode? current = node;
    final seen = <String>{};
    while (current != null && seen.add(current.id)) {
      if (current.locked) return true;
      current = byId[current.parentId];
    }
    return false;
  }

  return document.copyWith(
    nodes: [
      for (final n in document.nodes)
        if (targets.contains(n.id) && n.kind != 'group' && !locked(n))
          n.copyWith(
            properties: follow
                ? ({...n.properties}..remove('appearanceOverrides'))
                : localAppearanceProperties(n, {
                    if (n.kind != 'text') ...{
                      'fill': layoutNodeFill(document, n, nodesById: byId),
                      'stroke': '#475569FF',
                      'strokeWidth': 1,
                      'cornerRadius': n.kind == 'table'
                          ? 6
                          : n.kind == 'seat'
                          ? 5
                          : 0,
                    },
                    'objectStyle': 'simple',
                    'color': document.defaultTextStyle['color'] ?? '#222222FF',
                    if (n.kind == 'seat') 'seatStyle': 'plain',
                    'opacity': 1,
                    for (final e in effectiveNodeProperties(
                      document,
                      n,
                    ).entries)
                      if (_globalVisualKeys.contains(e.key)) e.key: e.value,
                  }),
          )
        else
          n,
    ],
  );
}

VenueLayoutDocument applyLayoutAppearance(
  VenueLayoutDocument document,
  Set<String> ids,
  LayoutAppearance appearance,
) {
  final byId = {for (final n in document.nodes) n.id: n};
  final targets = layoutSubtree(document, ids);
  bool locked(LayoutNode node) {
    LayoutNode? current = node;
    final visited = <String>{};
    while (current != null && visited.add(current.id)) {
      if (current.locked) return true;
      current = byId[current.parentId];
    }
    return false;
  }

  return document.copyWith(
    nodes: [
      for (final node in document.nodes)
        if (targets.contains(node.id) && node.kind != 'group' && !locked(node))
          node.copyWith(
            properties: localAppearanceProperties(node, {
              for (final entry
                  in (node.kind == 'seat' && !ids.contains(node.id)
                          ? appearance.seats ?? appearance.object
                          : appearance.object)
                      .entries)
                if ((node.kind == 'text' ? _textKeys : _visualKeys).contains(
                      entry.key,
                    ) &&
                    // Open paths retain their transparent fill and exact geometry.
                    !(entry.key == 'fill' &&
                        [
                          'line',
                          'arrow',
                          'polyline',
                        ].contains(node.properties['shape'])))
                  entry.key: entry.value,
            }),
          )
        else
          node,
    ],
  );
}

class LayoutStylePresets extends StatelessWidget {
  const LayoutStylePresets({
    super.key,
    required this.controller,
    this.onApply,
    this.colorsOnly = false,
  });
  final VenueLayoutController controller;
  final ValueChanged<LayoutAppearance>? onApply;
  final bool colorsOnly;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    key: const ValueKey('layout-style-presets-scroll'),
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final entry
            in (colorsOnly ? layoutColorPalettes : layoutAppearancePresets)
                .entries)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SizedBox.square(
              dimension: 88,
              child: OutlinedButton(
                key: ValueKey('layout-style-${entry.key}'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.all(8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: controller.readOnly || controller.saving
                    ? null
                    : () => onApply != null
                          ? onApply!(entry.value)
                          : controller.apply(
                              applyLayoutAppearance(
                                controller.document,
                                controller.selection,
                                entry.value,
                              ),
                              label: 'Apply style',
                            ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _LayoutStylePreview(appearance: entry.value),
                    const SizedBox(height: 5),
                    LayoutText(
                      entry.key,
                      style: Theme.of(context).textTheme.labelSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _LayoutStylePreview extends StatelessWidget {
  const _LayoutStylePreview({required this.appearance});
  final LayoutAppearance appearance;
  static final _previews = Expando<Map<String, dynamic>>();
  @override
  Widget build(BuildContext context) {
    final data = _previews[appearance] ??= (() {
      final base = tableLayout(shape: 'roundedRect');
      final bounds = selectionBounds(base, base.nodes.map((n) => n.id).toSet());
      final frame = Rect.fromLTWH(
        bounds['x']!,
        bounds['y']!,
        bounds['width']!,
        bounds['height']!,
      ).inflate(12);
      final doc = base.copyWith(
        nodes: [for (final node in base.nodes) node.copyWith(label: '')],
        canvas: {
          'x': frame.left,
          'y': frame.top,
          'width': frame.width,
          'height': frame.height,
          'fill': appearance.canvasFill ?? '#FFFFFFFF',
        },
        appearance: {
          'table': appearance.object,
          'seat': appearance.seats ?? appearance.object,
        },
      );
      return {'frame': frame, 'scene': compileScene(doc)};
    })();
    final frame = data['frame'] as Rect;
    final scale = math.min(58 / frame.width, 40 / frame.height);
    return CustomPaint(
      size: const Size(58, 40),
      painter: LayoutScenePainter(
        scene: data['scene'] as Map<String, dynamic>,
        resources: const {},
        selected: const {},
        scale: scale,
        offset: Offset(
          (58 - frame.width * scale) / 2 - frame.left * scale,
          (40 - frame.height * scale) / 2 - frame.top * scale,
        ),
        canvasColor: Colors.transparent,
        selectionColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

Future<void> showLayoutStyleDialog(
  BuildContext context,
  VenueLayoutController controller,
) => showDialog<void>(
  context: context,
  builder: (dialogContext) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final selected = controller.document.nodes
          .where((n) => controller.selection.contains(n.id))
          .toList();
      if (selected.isEmpty) return const SizedBox.shrink();
      final root = selected.first;
      final appearance = captureLayoutAppearance(controller.document, root.id);
      final used = <String>{};
      final byId = {
        for (final node in controller.document.nodes) node.id: node,
      };
      for (final node in controller.document.nodes) {
        for (final value in [
          if (node.kind == 'table') '#E2E8F0FF',
          if (node.kind == 'seat')
            byId[node.parentId]?.properties['furniture'] == 'couch'
                ? '#F8FAFCFF'
                : '#DCFCE7FF',
          effectiveNodeProperties(controller.document, node)['fill'],
          effectiveNodeProperties(controller.document, node)['stroke'],
          effectiveNodeProperties(controller.document, node)['color'],
        ]) {
          if (value is String && RegExp(r'^#[0-9a-fA-F]{8}$').hasMatch(value)) {
            used.add(value.substring(1, 7));
          }
        }
      }
      final canvasFill = controller.document.canvas['fill'] as String?;
      if (canvasFill != null) used.add(canvasFill.substring(1, 7));
      Future<void> color(
        String label,
        String value,
        String key, {
        bool seats = false,
      }) async {
        final result = await showDialog<EditorColorResult>(
          context: context,
          builder: (_) => EditorColorDialog(
            value: EditorColorValue.fromRgba(value),
            usedColors: used.toList(),
            image:
                (controller.resources['images']
                        as Map?)?[controller.document.background?['assetRef']]
                    as ui.Image?,
            translate: (text) => VenueLayoutStrings.text(context, text),
          ),
        );
        if (result == null ||
            !context.mounted ||
            controller.readOnly ||
            controller.saving) {
          return;
        }
        final targets = seats
            ? layoutSubtree(controller.document, controller.selection)
                  .where(
                    (id) => controller.document.nodes.any(
                      (n) => n.id == id && n.kind == 'seat',
                    ),
                  )
                  .toSet()
            : controller.selection;
        // Color controls target the object or its chairs independently.
        final next = applyLayoutAppearance(
          controller.document,
          targets,
          LayoutAppearance({
            key: result.primary.rgba,
          }, seats: seats ? null : const {}),
        );
        controller.apply(next, label: label);
      }

      Widget colorButton(
        String label,
        String value,
        String key, {
        bool seats = false,
      }) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: OutlinedButton(
          onPressed: controller.readOnly || controller.saving
              ? null
              : () => color(label, value, key, seats: seats),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                EditorColorSwatch(value: EditorColorValue.fromRgba(value)),
                const SizedBox(width: 10),
                Expanded(child: LayoutText(label)),
              ],
            ),
          ),
        ),
      );
      return AlertDialog(
        title: const LayoutText('Style'),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutStylePresets(controller: controller),
                if (root.kind != 'group' &&
                    ![
                      'line',
                      'polyline',
                      'arrow',
                    ].contains(root.properties['shape']))
                  colorButton(
                    root.kind == 'text' ? 'Text color' : 'Object color',
                    root.kind == 'text'
                        ? '${appearance.object['color'] ?? '#202830FF'}'
                        : layoutNodeFill(controller.document, root),
                    root.kind == 'text' ? 'color' : 'fill',
                  ),
                if (root.kind != 'text')
                  colorButton(
                    'Outline color',
                    '${appearance.object['stroke'] ?? '#475569FF'}',
                    'stroke',
                  ),
                if (appearance.seats != null)
                  colorButton(
                    'Seat color',
                    '${appearance.seats!['fill']}',
                    'fill',
                    seats: true,
                  ),
                const SizedBox(height: 12),
                const LayoutText(
                  'Changes apply immediately. Undo restores the previous style.',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const LayoutText('Done'),
          ),
        ],
      );
    },
  ),
);
