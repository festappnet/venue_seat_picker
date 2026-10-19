import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'layout_style.dart';

/// A live preview is one history operation; font sizes use whole units.
class LayoutFontSizeControl extends StatefulWidget {
  const LayoutFontSizeControl({
    super.key,
    required this.controller,
    required this.node,
    required this.value,
  });
  final VenueLayoutController controller;
  final LayoutNode node;
  final double value;
  @override
  State<LayoutFontSizeControl> createState() => _LayoutFontSizeControlState();
}

class _LayoutFontSizeControlState extends State<LayoutFontSizeControl> {
  late final _text = TextEditingController(text: _display(widget.value));
  final _focus = FocusNode();
  VenueLayoutDocument? _baseline, _lastPreview;
  double? _dragMin, _dragMax;
  String? _error;
  bool _cancelled = false;
  bool _edited = false;
  bool get _enabled =>
      !widget.controller.readOnly &&
      !widget.controller.saving &&
      !widget.node.locked;
  String _display(double value) => value.round().toString();
  double get _min => _dragMin ?? math.min(8, widget.value).toDouble();
  double get _max =>
      _dragMax ??
      math.min(
        layoutLimits['fontSizeMax']!.toDouble(),
        math.max(96, widget.value * 1.5),
      );

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
  }

  void _focusChanged() {
    if (!_focus.hasFocus) _submit();
  }

  @override
  void didUpdateWidget(LayoutFontSizeControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _text.text = _display(widget.value);
      _edited = false;
    }
  }

  LayoutNode _sized(LayoutNode node, double value) => node.copyWith(
    properties: localAppearanceProperties(node, {'size': value}),
  );
  void _start(double _) {
    if (!_enabled) return;
    _cancelled = false;
    _dragMin = _min;
    _dragMax = _max;
    _baseline = widget.controller.document;
    _lastPreview = _baseline;
    widget.controller.beginGesture();
  }

  void _change(double value) {
    if (!_enabled || _cancelled) return;
    final rounded = value.roundToDouble();
    final baseline = _baseline;
    if (baseline == null) {
      widget.controller.updateNode(_sized(widget.node, rounded));
    } else {
      widget.controller.preview(
        baseline.copyWith(
          nodes: [
            for (final node in baseline.nodes)
              node.id == widget.node.id ? _sized(node, rounded) : node,
          ],
        ),
      );
      _lastPreview = widget.controller.document;
    }
  }

  void _finish(double _) {
    // Pointer cancellation reaches the parent Listener in the same event; defer
    // committing so cancellation can still restore the preview baseline.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _baseline == null) return;
      _baseline = null;
      _lastPreview = null;
      _dragMin = null;
      _dragMax = null;
      widget.controller.commitGesture();
    });
  }

  void _cancel() {
    if (_baseline == null) return;
    _cancelled = true;
    _baseline = null;
    _lastPreview = null;
    _dragMin = null;
    _dragMax = null;
    widget.controller.cancelGesture();
  }

  void _submit() {
    if (!_enabled || !_edited) return;
    final value = double.tryParse(_text.text.replaceAll(',', '.'));
    if (value == null ||
        !value.isFinite ||
        value < layoutLimits['fontSizeMin']! ||
        value > layoutLimits['fontSizeMax']!) {
      setState(
        () =>
            _error = VenueLayoutStrings.text(context, 'Enter a valid number.'),
      );
      return;
    }
    setState(() => _error = null);
    final rounded = value.roundToDouble();
    _edited = false;
    _text.text = _display(rounded);
    if (rounded != widget.value) {
      widget.controller.updateNode(_sized(widget.node, rounded));
    }
  }

  @override
  void dispose() {
    final c = widget.controller, preview = _lastPreview;
    if (_baseline != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (identical(c.document, preview)) c.cancelGesture();
      });
    }
    _focus.removeListener(_focusChanged);
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    onKeyEvent: (_, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape &&
          _baseline != null) {
        _cancel();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: Row(
      children: [
        Expanded(
          child: Listener(
            onPointerCancel: (_) => _cancel(),
            child: Slider(
              key: const ValueKey('font-size-slider'),
              min: _min,
              max: _max,
              value: widget.value,
              label: _display(widget.value),
              semanticFormatterCallback: (value) =>
                  '${VenueLayoutStrings.text(context, 'Font size')} ${_display(value)}',
              onChangeStart: _enabled ? _start : null,
              onChanged: _enabled ? _change : null,
              onChangeEnd: _enabled ? _finish : null,
            ),
          ),
        ),
        SizedBox(
          width: 96,
          child: TextField(
            controller: _text,
            focusNode: _focus,
            enabled: _enabled,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: VenueLayoutStrings.text(context, 'Font size'),
              errorText: _error,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => _edited = true,
            onSubmitted: (_) => _submit(),
            onTapOutside: (_) {
              _submit();
              _focus.unfocus();
            },
          ),
        ),
      ],
    ),
  );
}
