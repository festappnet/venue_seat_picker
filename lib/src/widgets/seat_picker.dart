import 'package:flutter/material.dart';

import '../controller/seat_layout_controller.dart';
import '../model/seat_cell.dart';
import '../model/seat_layout_item.dart';
import '../model/seat_state.dart';
import 'seat_layout.dart';
import 'seat_layout_theme.dart';

typedef SeatSelectionRequest<T extends SeatLayoutItem> = Future<bool> Function(
  SeatCell<T> cell,
  bool selected,
);

class SeatPicker<T extends SeatLayoutItem> extends StatefulWidget {
  const SeatPicker({
    super.key,
    required this.controller,
    this.onSelectionRequest,
    this.onSelectionChanged,
    this.onSelectionError,
    this.onLimitReached,
    this.maxSelection,
    this.isSelectable,
    this.tooltipBuilder,
    this.seatBuilder,
    this.config = const SeatLayoutConfig(),
  });

  final SeatLayoutController<T> controller;
  final SeatSelectionRequest<T>? onSelectionRequest;
  final ValueChanged<List<SeatCell<T>>>? onSelectionChanged;
  final void Function(Object error, StackTrace stackTrace)? onSelectionError;
  final VoidCallback? onLimitReached;
  final int? maxSelection;
  final bool Function(SeatCell<T> cell)? isSelectable;
  final String Function(BuildContext context, SeatCell<T> cell)? tooltipBuilder;
  final SeatCellBuilder<T>? seatBuilder;
  final SeatLayoutConfig config;

  @override
  State<SeatPicker<T>> createState() => _SeatPickerState<T>();
}

class _SeatPickerState<T extends SeatLayoutItem> extends State<SeatPicker<T>> {
  final Set<(int, int)> _pending = {};

  List<SeatCell<T>> get _selected => widget.controller.cells
      .where((cell) => cell.state == SeatState.selectedByMe)
      .toList(growable: false);

  @override
  Widget build(BuildContext context) => SeatLayout<T>(
        controller: widget.controller,
        onSeatTap: _toggle,
        tooltipBuilder: widget.tooltipBuilder,
        seatBuilder: widget.seatBuilder,
        config: widget.config,
      );

  Future<void> _toggle(SeatCell<T> cell) async {
    final controller = widget.controller;
    final onSelectionChanged = widget.onSelectionChanged;
    final onSelectionError = widget.onSelectionError;
    final onSelectionRequest = widget.onSelectionRequest;
    final coordinate = (cell.row, cell.column);
    if (_pending.contains(coordinate)) return;
    if (widget.isSelectable?.call(cell) == false) return;
    final select = cell.state == SeatState.available;
    if (!select && cell.state != SeatState.selectedByMe) return;
    if (select &&
        widget.maxSelection != null &&
        _selected.length >= widget.maxSelection!) {
      widget.onLimitReached?.call();
      return;
    }

    final before = cell.state;
    _pending.add(coordinate);
    controller.updateVisualState(
      cell,
      select ? SeatState.selectedByMe : SeatState.available,
    );
    onSelectionChanged?.call(_selected);

    var accepted = false;
    try {
      accepted =
          await (onSelectionRequest?.call(cell, select) ?? Future.value(true));
    } catch (error, stackTrace) {
      onSelectionError?.call(error, stackTrace);
    }
    if (!controller.isDisposed && accepted) {
      controller.updateSeat(
        cell,
        select ? SeatState.selectedByMe : SeatState.available,
      );
    } else if (!controller.isDisposed) {
      controller.updateVisualState(cell, before);
      if (mounted) onSelectionChanged?.call(_selected);
    }
    _pending.remove(coordinate);
  }
}
