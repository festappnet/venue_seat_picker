import 'package:flutter/material.dart';

import '../controller/seat_layout_controller.dart';
import '../model/seat_cell.dart';
import '../model/seat_layout_item.dart';
import '../model/seat_state.dart';
import 'seat_layout.dart';
import 'seat_layout_theme.dart';

typedef SeatItemFactory<T extends SeatLayoutItem> = T Function(
  int row,
  int column,
  SeatState state,
);

/// Self-contained grid editor. Domain-specific persistence stays with the host.
class SeatLayoutEditor<T extends SeatLayoutItem> extends StatefulWidget {
  const SeatLayoutEditor({
    super.key,
    required this.controller,
    required this.createItem,
    this.onChanged,
    this.states = const [
      SeatState.available,
      SeatState.blocked,
      SeatState.empty
    ],
    this.config = const SeatLayoutConfig(),
  }) : assert(states.length > 0);

  final SeatLayoutController<T> controller;
  final SeatItemFactory<T> createItem;
  final VoidCallback? onChanged;
  final List<SeatState> states;
  final SeatLayoutConfig config;

  @override
  State<SeatLayoutEditor<T>> createState() => _SeatLayoutEditorState<T>();
}

class _SeatLayoutEditorState<T extends SeatLayoutItem>
    extends State<SeatLayoutEditor<T>> {
  late SeatState _paintState = widget.states.first;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              IconButton(
                tooltip: 'Remove row',
                onPressed: widget.controller.canResize(
                        widget.controller.rows - 1, widget.controller.columns)
                    ? () => _resize(
                        widget.controller.rows - 1, widget.controller.columns)
                    : null,
                icon: const Icon(Icons.remove),
              ),
              Text('${widget.controller.rows} rows'),
              IconButton(
                tooltip: 'Add row',
                onPressed: () => _resize(
                    widget.controller.rows + 1, widget.controller.columns),
                icon: const Icon(Icons.add),
              ),
              IconButton(
                tooltip: 'Remove column',
                onPressed: widget.controller.canResize(
                        widget.controller.rows, widget.controller.columns - 1)
                    ? () => _resize(
                        widget.controller.rows, widget.controller.columns - 1)
                    : null,
                icon: const Icon(Icons.remove),
              ),
              Text('${widget.controller.columns} columns'),
              IconButton(
                tooltip: 'Add column',
                onPressed: () => _resize(
                    widget.controller.rows, widget.controller.columns + 1),
                icon: const Icon(Icons.add),
              ),
              for (final state in widget.states)
                ChoiceChip(
                  label: Text(state.name),
                  selected: _paintState == state,
                  onSelected: (_) => setState(() => _paintState = state),
                ),
            ],
          ),
          Expanded(
            child: SeatLayout<T>(
              controller: widget.controller,
              editorMode: true,
              config: widget.config,
              onSeatTap: _paint,
            ),
          ),
        ],
      );

  void _resize(int rows, int columns) {
    if (widget.controller.setDimensions(rows, columns)) {
      widget.onChanged?.call();
      setState(() {});
    }
  }

  void _paint(SeatCell<T> cell) {
    if (_paintState == SeatState.empty) {
      widget.controller.removeItem(cell);
    } else if (cell.item == null) {
      widget.controller
          .addItem(widget.createItem(cell.row, cell.column, _paintState));
    } else {
      widget.controller.updateSeat(cell, _paintState);
    }
    widget.onChanged?.call();
    setState(() {});
  }
}
