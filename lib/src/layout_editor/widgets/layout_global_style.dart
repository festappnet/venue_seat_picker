import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:venue_layout_core/venue_layout_core.dart';
import 'package:venue_seat_picker/editor_ui.dart';
import '../venue_layout_controller.dart';
import 'layout_strings.dart';
import 'layout_style.dart';
import 'layout_appearance_preview.dart';
import 'layout_appearance_families.dart';
import 'layout_floor_style.dart';

Future<void> showLayoutGlobalStyleDialog(
  BuildContext context,
  VenueLayoutController controller, {
  Widget Function(BuildContext, String)? globalFontPickerBuilder,
}) => showDialog<void>(
  context: context,
  builder: (_) => _GlobalStyleDialog(
    controller: controller,
    globalFontPickerBuilder: globalFontPickerBuilder,
  ),
);

const _scopes = {
  'table': 'Tables',
  'seat': 'Chairs',
  'shape': 'Shapes',
  'furniture': 'Couches',
  'capacityArea': 'Standing areas',
  'text': 'Text',
};

class _GlobalStyleDialog extends StatefulWidget {
  const _GlobalStyleDialog({
    required this.controller,
    this.globalFontPickerBuilder,
  });
  final Widget Function(BuildContext, String)? globalFontPickerBuilder;
  final VenueLayoutController controller;
  @override
  State<_GlobalStyleDialog> createState() => _GlobalStyleDialogState();
}

class _GlobalStyleDialogState extends State<_GlobalStyleDialog> {
  VenueLayoutController get c => widget.controller;
  String _kind = 'table';
  bool _showAppearance = false;
  String? _error;
  final _seatingDraft = <String, double>{};
  final _appearanceDraft = <String, double>{};
  int _previewChairs = 6;
  late final _samples = {
    for (final kind in _scopes.keys)
      kind: LayoutNode(id: newLayoutId(), kind: kind),
  };
  bool get _enabled => !c.readOnly && !c.saving;
  String tr(String value) => VenueLayoutStrings.text(context, value);

  void _apply(Map<String, dynamic> patch) {
    if (!_enabled) return;
    try {
      c.apply(
        setLayoutAppearance(c.document, _kind, patch),
        label: 'Plan style',
      );
      if (mounted) {
        setState(() {
          _appearanceDraft.clear();
          _error = c.error;
        });
      }
    } catch (_) {
      setState(() {
        _appearanceDraft.clear();
        _error = 'Unable to apply plan style. Check the values.';
      });
    }
  }

  void _tableSeating(String key, double value) {
    if (!_enabled) return;
    try {
      c.apply(
        configurePlanTableSeating(
          c.document,
          width: key == 'seatWidth' || key == 'seatSize' ? value : null,
          height: key == 'seatHeight' || key == 'seatSize' ? value : null,
          gap: key == 'seatGap' ? value : null,
          spacing: key == 'seatSpacing' ? value : null,
          edgePadding: key == 'seatEdgePadding' ? value : null,
        ),
        label: 'Adjust chair layout',
      );
      setState(() {
        _seatingDraft.clear();
        _error = c.error;
      });
    } catch (_) {
      setState(() {
        _seatingDraft.clear();
        _error =
            'Unable to change chair layout. Reduce the values or free up space around the tables.';
      });
    }
  }

  Widget _chairControl(
    String key,
    String label, {
    required double value,
    required double defaultValue,
  }) {
    final size = const {'seatWidth', 'seatHeight', 'seatSize'}.contains(key);
    return _GlobalStyleNumber(
      key: ValueKey('plan-table-${key == 'seatGap' ? 'seat-gap' : key}'),
      label: label,
      value: value,
      min: size ? 1 : 0,
      max: 1000000,
      sliderMax: size ? 120 : 80,
      defaultValue: defaultValue,
      enabled: _enabled,
      preview: (value) => setState(() {
        if (key == 'seatSize') {
          _seatingDraft['seatWidth'] = value;
          _seatingDraft['seatHeight'] = value;
        } else {
          _seatingDraft[key] = value;
        }
      }),
      save: (value) => _tableSeating(key, value),
    );
  }

  double _appearanceDefault(String property) {
    final family =
        (c.document.appearance[_kind] as Map?)?['objectStyle'] ?? 'simple';
    final defaults = layoutMaterialAppearance(
      layoutMaterialFamilies.containsKey(family) ? family as String : 'simple',
    )[_kind]!;
    return (defaults[property] as num? ?? (property == 'cornerRadius' ? 0 : 1))
        .toDouble();
  }

  void _preset(LayoutAppearance style) {
    if (!_enabled) return;
    try {
      final next = c.document.copyWith(
        appearance: {
          ...c.document.appearance,
          for (final kind in _scopes.keys)
            kind: {
              ...?c.document.appearance[kind] as Map?,
              ...kind == 'seat' ? style.seats ?? style.object : style.object,
            },
        },
        canvas: style.canvasFill == null
            ? c.document.canvas
            : {...c.document.canvas, 'fill': style.canvasFill},
      );
      c.apply(next, label: 'Plan style');
      setState(() => _error = c.error);
    } catch (_) {
      setState(() => _error = 'Unable to apply plan style. Check the values.');
    }
  }

  Future<void> _color(String key, String label, String value) async {
    final colors = <String>{
      (c.document.canvas['fill'] as String? ?? '#FFFFFFFF').substring(1, 7),
    };
    final nodesById = {for (final node in c.document.nodes) node.id: node};
    for (final node in [...c.document.nodes, ..._samples.values]) {
      final properties = {
        'fill': layoutNodeFill(c.document, node, nodesById: nodesById),
        'stroke': '#475569FF',
        'color': '#202830FF',
        ...effectiveNodeProperties(c.document, node),
      };
      for (final property in ['fill', 'stroke', 'color']) {
        final color = properties[property];
        if (color is String && RegExp(r'^#[0-9a-fA-F]{8}$').hasMatch(color)) {
          colors.add(color.substring(1, 7).toUpperCase());
        }
      }
    }
    final kind = _kind;
    final result = await showDialog<EditorColorResult>(
      context: context,
      builder: (_) => EditorColorDialog(
        title: tr(label),
        value: EditorColorValue.fromRgba(value),
        usedColors: colors.toList(),
        image:
            (c.resources['images'] as Map?)?[c.document.background?['assetRef']]
                as ui.Image?,
        enableOpacity: true,
        translate: tr,
      ),
    );
    if (mounted && result != null && _enabled && kind == _kind) {
      if (key == 'canvasFill') {
        c.apply(
          c.document.copyWith(
            canvas: {...c.document.canvas, 'fill': result.primary.rgba},
          ),
          label: 'Canvas color',
        );
      } else {
        _apply({key: result.primary.rgba});
      }
    }
  }

  Widget _colorField(String key, String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: OutlinedButton(
      onPressed: _enabled ? () => _color(key, label, value) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            EditorColorSwatch(value: EditorColorValue.fromRgba(value)),
            const SizedBox(width: 12),
            Expanded(child: LayoutText(label)),
            const Icon(Icons.edit_outlined, size: 18),
          ],
        ),
      ),
    ),
  );

  Widget _scopeSelector() => DropdownButtonFormField<String>(
    initialValue: _kind,
    decoration: InputDecoration(
      labelText: tr('Object type'),
      border: const OutlineInputBorder(),
    ),
    items: [
      for (final entry in _scopes.entries)
        DropdownMenuItem(value: entry.key, child: LayoutText(entry.value)),
    ],
    onChanged: _enabled
        ? (value) => setState(() {
            _kind = value!;
            _appearanceDraft.clear();
            _error = null;
          })
        : null,
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final properties = {
        ...c.document.defaultTextStyle,
        ...effectiveNodeProperties(c.document, _samples[_kind]!),
        ..._appearanceDraft,
      };
      final seating = documentSeating(c.document);
      return AlertDialog(
        title: const LayoutText('Plan style'),
        scrollable: true,
        content: SizedBox(
          width: 420,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const LayoutText(
                'Styles apply to existing and new objects. Local overrides are preserved.',
              ),
              const SizedBox(height: 16),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.palette_outlined),
                    label: LayoutText('Colors'),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.chair_outlined),
                    label: LayoutText('Appearance'),
                  ),
                ],
                selected: {_showAppearance},
                onSelectionChanged: (values) async {
                  FocusManager.instance.primaryFocus?.unfocus();
                  await Future<void>.delayed(Duration.zero);
                  if (mounted) setState(() => _showAppearance = values.single);
                },
              ),
              const SizedBox(height: 16),
              if (!_showAppearance) ...[
                const LayoutText('Color palette'),
                const SizedBox(height: 8),
                LayoutStylePresets(
                  controller: c,
                  onApply: _preset,
                  colorsOnly: true,
                ),
                const SizedBox(height: 16),
                _colorField(
                  'canvasFill',
                  'Canvas color',
                  c.document.canvas['fill'] as String? ?? '#FFFFFFFF',
                ),
                const SizedBox(height: 8),
              ],
              if (!_showAppearance) ...[
                _scopeSelector(),
                const SizedBox(height: 16),
              ],
              if (!_showAppearance) ...[
                _colorField(
                  _kind == 'text' ? 'color' : 'fill',
                  _kind == 'text' ? 'Text color' : 'Fill color',
                  '${properties[_kind == 'text' ? 'color' : 'fill'] ?? (_kind == 'text' ? '#202830FF' : layoutNodeFill(c.document, _samples[_kind]!))}',
                ),
                _colorField(
                  'stroke',
                  'Outline color',
                  '${properties['stroke'] ?? '#475569FF'}',
                ),
              ],
              if (_showAppearance) ...[
                LayoutAppearanceFamilies(
                  controller: c,
                  onApply: (family) {
                    c.apply(
                      withAppearanceFamily(c.document, family),
                      label: 'Plan style',
                    );
                    setState(() => _error = c.error);
                  },
                ),
                ExpansionTile(
                  key: const ValueKey('plan-chair-layout'),
                  tilePadding: EdgeInsets.zero,
                  title: const LayoutText('Chair layout'),
                  childrenPadding: const EdgeInsets.only(top: 8),
                  children: [
                    LayoutAppearancePreview(
                      controller: c,
                      kind: 'table',
                      height: 160,
                      chairCount: _previewChairs,
                      appearance: {'table': _seatingDraft},
                    ),
                    Row(
                      children: [
                        const Expanded(child: LayoutText('Chairs in preview')),
                        IconButton(
                          tooltip: tr('Fewer chairs'),
                          onPressed: _previewChairs > 1
                              ? () => setState(() => _previewChairs--)
                              : null,
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        Text('$_previewChairs'),
                        IconButton(
                          tooltip: tr('More chairs'),
                          onPressed: _previewChairs < 24
                              ? () => setState(() => _previewChairs++)
                              : null,
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ],
                    ),
                    const LayoutText(
                      'Only changes the preview. The table stays the same size.',
                    ),
                    const SizedBox(height: 16),
                    _chairControl(
                      'seatSize',
                      'Chair size',
                      value:
                          _seatingDraft['seatWidth'] ??
                          (seating.width > seating.height
                              ? seating.width
                              : seating.height),
                      defaultValue: const TableSeating().width,
                    ),
                    _chairControl(
                      'seatGap',
                      'Distance from table',
                      value: _seatingDraft['seatGap'] ?? seating.gap,
                      defaultValue: const TableSeating().gap,
                    ),
                    ExpansionTile(
                      key: const ValueKey('advanced-chair-settings'),
                      tilePadding: EdgeInsets.zero,
                      title: const LayoutText('Advanced chair settings'),
                      children: [
                        for (final entry in const {
                          'seatWidth': 'Chair width',
                          'seatHeight': 'Chair depth',
                          'seatSpacing': 'Space between chairs',
                          'seatEdgePadding': 'Distance from table corners',
                        }.entries)
                          _chairControl(
                            entry.key,
                            entry.value,
                            value:
                                _seatingDraft[entry.key] ??
                                seating.properties[entry.key] as double,
                            defaultValue:
                                const TableSeating().properties[entry.key]
                                    as double,
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const LayoutText(
                      'Applies to existing and new tables. Manual chair positions and locked assemblies stay unchanged.',
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const LayoutText('Fine-tune appearance'),
                  childrenPadding: const EdgeInsets.only(top: 8),
                  children: [
                    LayoutFloorStyleField(controller: c),
                    const SizedBox(height: 8),
                    _scopeSelector(),
                    const SizedBox(height: 16),

                    LayoutAppearancePreview(
                      key: const ValueKey('global-appearance-preview'),
                      controller: c,
                      kind: _kind,
                      appearance: {_kind: _appearanceDraft},
                    ),
                    const SizedBox(height: 16),
                    if (const {
                      'table',
                      'shape',
                      'capacityArea',
                      'text',
                    }.contains(_kind)) ...[
                      widget.globalFontPickerBuilder?.call(context, _kind) ??
                          EditorFontPicker(
                            value: properties['fontId'] as String?,
                            label: 'Font',
                            enabled: _enabled,
                            translate: tr,
                            options: [
                              for (final entry
                                  in (c.resources['fonts'] as Map? ?? {})
                                      .entries)
                                EditorFontOption(
                                  id: '${entry.key}',
                                  family: '${entry.value['family'] ?? 'Font'}',
                                ),
                            ],
                            onSelected: (id) async {
                              if (id != null) {
                                _apply({'fontId': id});
                                return;
                              }
                              _apply({'fontId': null});
                            },
                          ),
                      const SizedBox(height: 12),
                      _GlobalStyleNumber(
                        key: ValueKey('$_kind-font-size'),
                        label: 'Font size',
                        value: (properties['size'] as num? ?? 24).toDouble(),
                        min: layoutLimits['fontSizeMin']!.toDouble(),
                        max: layoutLimits['fontSizeMax']!.toDouble(),
                        sliderMax: 96,
                        step: 1,
                        enabled: _enabled,
                        preview: (value) =>
                            setState(() => _appearanceDraft['size'] = value),
                        save: (value) => _apply({'size': value}),
                      ),
                      Row(
                        children: [
                          for (final entry in const [
                            ('bold', 'Bold', Icons.format_bold),
                            ('italic', 'Italic', Icons.format_italic),
                          ])
                            IconButton.filledTonal(
                              tooltip: tr(entry.$2),
                              isSelected: properties[entry.$1] == true,
                              icon: Icon(entry.$3),
                              onPressed: _enabled
                                  ? () => _apply({
                                      entry.$1: properties[entry.$1] != true,
                                    })
                                  : null,
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_kind == 'seat') ...[
                      Row(
                        children: [
                          for (final entry in const {
                            'plain': 'Simple',
                            'round': 'Round seating',
                            'wood': 'Wooden',
                            'upholstered': 'Upholstered',
                            'transit': 'Transport',
                            'banquet': 'Banquet',
                          }.entries)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                ),
                                child: OutlinedButton(
                                  key: ValueKey(
                                    'chair-appearance-${entry.key}',
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.all(6),
                                    side: BorderSide(
                                      color:
                                          (properties['seatStyle'] ??
                                                  'plain') ==
                                              entry.key
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.primary
                                          : Theme.of(
                                              context,
                                            ).colorScheme.outlineVariant,
                                      width:
                                          (properties['seatStyle'] ??
                                                  'plain') ==
                                              entry.key
                                          ? 2
                                          : 1,
                                    ),
                                  ),
                                  onPressed: _enabled
                                      ? () => _apply({'seatStyle': entry.key})
                                      : null,
                                  child: Column(
                                    children: [
                                      LayoutAppearancePreview(
                                        controller: c,
                                        kind: 'seat',
                                        seatStyle: entry.key,
                                        height: 52,
                                      ),
                                      const SizedBox(height: 6),
                                      LayoutText(
                                        entry.value,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.labelSmall,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                    for (final property in [
                      'strokeWidth',
                      if (_kind != 'text') 'cornerRadius',
                      'opacity',
                    ])
                      _GlobalStyleNumber(
                        key: ValueKey('$_kind-$property'),
                        label: property == 'strokeWidth'
                            ? 'Stroke width'
                            : property == 'cornerRadius'
                            ? 'Corner radius'
                            : 'Opacity',
                        value:
                            (properties[property] as num? ??
                                    _appearanceDefault(property))
                                .toDouble(),
                        max: property == 'opacity' ? 1 : 1e9,
                        sliderMax: property == 'opacity'
                            ? 1
                            : property == 'strokeWidth'
                            ? 12
                            : 60,
                        step: property == 'opacity'
                            ? .01
                            : property == 'strokeWidth'
                            ? .1
                            : 1,
                        defaultValue: _appearanceDefault(property),
                        preview: (value) =>
                            setState(() => _appearanceDraft[property] = value),
                        enabled: _enabled,
                        save: (value) => _apply({property: value}),
                      ),
                  ],
                ),
              ],
              if (_error != null)
                Semantics(
                  liveRegion: true,
                  child: LayoutText(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              FocusManager.instance.primaryFocus?.unfocus();
              await Future<void>.delayed(Duration.zero);
              if (context.mounted) Navigator.pop(context);
            },
            child: const LayoutText('Done'),
          ),
        ],
      );
    },
  );
}

class _GlobalStyleNumber extends StatefulWidget {
  const _GlobalStyleNumber({
    super.key,
    required this.label,
    required this.value,
    required this.max,
    required this.enabled,
    required this.save,
    this.min = 0,
    this.sliderMax,
    this.preview,
    this.defaultValue,
    this.step = 1,
  });
  final String label;
  final double value, max, min, step;
  final double? sliderMax, defaultValue;
  final ValueChanged<double>? preview;
  final bool enabled;
  final ValueChanged<double> save;
  @override
  State<_GlobalStyleNumber> createState() => _GlobalStyleNumberState();
}

class _GlobalStyleNumberState extends State<_GlobalStyleNumber> {
  late final _text = TextEditingController(text: _display(widget.value));
  bool _edited = false;
  String _display(double value) => widget.step >= 1
      ? value.round().toString()
      : value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  late final _focus = FocusNode()..addListener(_blur);
  String? _error;
  double? _submitted;
  double _snap(double value) => double.parse(
    ((value / widget.step).round() * widget.step).toStringAsFixed(6),
  );
  String get _sliderLabel => widget.value.toStringAsFixed(
    widget.step < .1
        ? 2
        : widget.step < 1
        ? 1
        : 0,
  );
  void _blur() {
    if (!_focus.hasFocus) _commit();
  }

  void _commit() {
    if (!widget.enabled || !_edited) return;
    final parsed = double.tryParse(_text.text.replaceAll(',', '.'));
    if (parsed == null ||
        !parsed.isFinite ||
        parsed < widget.min ||
        parsed > widget.max) {
      if (mounted) {
        setState(
          () => _error = widget.max == 1
              ? 'Enter a number from 0 to 1.'
              : widget.min > 0
              ? 'Enter a number of at least 1.'
              : 'Enter a non-negative number.',
        );
      }
      return;
    }
    if (mounted) setState(() => _error = null);
    final value = _snap(parsed);
    _edited = false;
    _text.text = _display(value);
    if (value != widget.value && value != _submitted) {
      _submitted = value;
      widget.save(value);
    }
  }

  @override
  void didUpdateWidget(_GlobalStyleNumber oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _text.text = _display(widget.value);
      _edited = false;
      _submitted = null;
      _error = null;
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_blur);
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final field = EditorNumberScroll(
      enabled: widget.enabled && widget.label != 'Font size',
      min: widget.min,
      max: widget.max,
      step: widget.step,
      onChanged: () {
        _edited = true;
        _commit();
      },
      child: TextField(
        controller: _text,
        focusNode: _focus,
        enabled: widget.enabled,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: widget.sliderMax == null
              ? VenueLayoutStrings.text(context, widget.label)
              : null,
          errorText: _error == null
              ? null
              : VenueLayoutStrings.text(context, _error!),
          suffixIcon: IconButton(
            tooltip: VenueLayoutStrings.text(context, 'Apply'),
            onPressed: widget.enabled ? _commit : null,
            icon: const Icon(Icons.check, size: 18),
          ),
        ),
        onChanged: (_) {
          _edited = true;
          _submitted = null;
          if (_error != null) setState(() => _error = null);
        },
        onSubmitted: (_) => _commit(),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: widget.sliderMax == null
          ? field
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutText(widget.label),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Tooltip(
                        message: VenueLayoutStrings.text(
                          context,
                          'Double-click to reset',
                        ),
                        child: GestureDetector(
                          onDoubleTap:
                              widget.enabled && widget.defaultValue != null
                              ? () => widget.save(widget.defaultValue!)
                              : null,
                          child: Slider(
                            min: widget.min,
                            max: widget.value > widget.sliderMax!
                                ? widget.value
                                : widget.sliderMax!,
                            value: widget.value.clamp(widget.min, widget.max),
                            label: _sliderLabel,
                            semanticFormatterCallback: (value) =>
                                '${VenueLayoutStrings.text(context, widget.label)}: $_sliderLabel',
                            onChangeStart: widget.enabled
                                ? (_) => FocusManager.instance.primaryFocus
                                      ?.unfocus()
                                : null,
                            onChanged: widget.enabled
                                ? (value) => widget.preview?.call(_snap(value))
                                : null,
                            onChangeEnd: widget.enabled
                                ? (value) => widget.save(_snap(value))
                                : null,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 120,
                      child: Semantics(
                        label: VenueLayoutStrings.text(context, widget.label),
                        child: field,
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
