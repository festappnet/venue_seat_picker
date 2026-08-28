import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../model/seat_cell.dart';
import '../model/seat_layout_background.dart';
import '../model/seat_layout_item.dart';
import '../model/seat_state.dart';

class SeatLayoutController<T extends SeatLayoutItem> extends ChangeNotifier {
  SeatLayoutController();

  final TransformationController transformationController =
      TransformationController();
  List<SeatCell<T>> cells = [];
  int rows = 1;
  int columns = 1;
  double cellSize = 40;
  SeatLayoutBackground? background;
  double minScale = 1;
  bool isLayoutReady = false;
  GlobalKey? _layoutKey;
  bool _disposed = false;

  bool get isDisposed => _disposed;

  void attachLayoutKey(GlobalKey key) {
    _layoutKey = key;
    _scheduleFit();
  }

  void loadLayout({
    required int rows,
    required int columns,
    required Iterable<T> items,
    double cellSize = 40,
    SeatLayoutBackground? background,
  }) {
    _validateDimensions(rows, columns, cellSize);
    final byCoordinate = <(int, int), T>{};
    for (final item in items) {
      if (item.seatRow < 0 ||
          item.seatRow >= rows ||
          item.seatColumn < 0 ||
          item.seatColumn >= columns) {
        throw ArgumentError.value(
          item,
          'items',
          'Seat coordinates must be inside the layout',
        );
      }
      final coordinate = (item.seatRow, item.seatColumn);
      if (byCoordinate.containsKey(coordinate)) {
        throw ArgumentError('Duplicate seat coordinate: $coordinate');
      }
      byCoordinate[coordinate] = item;
    }

    this.rows = rows;
    this.columns = columns;
    this.cellSize = cellSize;
    this.background = background;
    cells = [
      for (var row = 0; row < rows; row++)
        for (var column = 0; column < columns; column++)
          SeatCell<T>(
            row: row,
            column: column,
            size: cellSize,
            item: byCoordinate[(row, column)],
            state: byCoordinate[(row, column)]?.seatState ?? SeatState.empty,
          ),
    ];
    if (_layoutKey != null) _scheduleFit();
    notifyListeners();
  }

  bool canResize(int newRows, int newColumns) =>
      newRows > 0 &&
      newColumns > 0 &&
      cells
          .where((cell) => cell.item != null)
          .every((cell) => cell.row < newRows && cell.column < newColumns);

  bool setDimensions(int newRows, int newColumns) {
    if (!canResize(newRows, newColumns)) return false;
    final items = cells.map((cell) => cell.item).whereType<T>().toList();
    loadLayout(
      rows: newRows,
      columns: newColumns,
      items: items,
      cellSize: cellSize,
      background: background,
    );
    return true;
  }

  void setBackground(SeatLayoutBackground? value) {
    background = value;
    notifyListeners();
  }

  SeatCell<T>? cellAt(int row, int column) {
    if (row < 0 || row >= rows || column < 0 || column >= columns) return null;
    return cells[row * columns + column];
  }

  void updateSeat(SeatCell<T> cell, SeatState state) {
    final target = cellAt(cell.row, cell.column);
    if (target == null) return;
    target.state = state;
    target.item?.seatState = state;
    notifyListeners();
  }

  void updateVisualState(SeatCell<T> cell, SeatState state) {
    final target = cellAt(cell.row, cell.column);
    if (target == null) return;
    target.state = state;
    notifyListeners();
  }

  void restoreVisualState(SeatCell<T> cell) =>
      updateVisualState(cell, cell.item?.seatState ?? SeatState.empty);

  void addItem(T item, {bool highlightGroup = false}) {
    final target = cellAt(item.seatRow, item.seatColumn);
    if (target == null) {
      throw ArgumentError.value(item, 'item', 'Seat is outside the layout');
    }
    if (target.item != null && !identical(target.item, item)) {
      throw StateError('Cell (${target.row}, ${target.column}) is occupied');
    }
    target
      ..item = item
      ..state = item.seatState
      ..isGroupHighlighted = highlightGroup;
    notifyListeners();
  }

  T? removeItem(SeatCell<T> cell) {
    final target = cellAt(cell.row, cell.column);
    final removed = target?.item;
    if (target != null) {
      target
        ..item = null
        ..state = SeatState.empty
        ..isGroupHighlighted = false
        ..isSwapHighlighted = false
        ..isTooltipHighlighted = false;
      notifyListeners();
    }
    return removed;
  }

  void setSwapHighlight(SeatCell<T> cell, bool highlighted) {
    final target = cellAt(cell.row, cell.column);
    if (target == null) return;
    target.isSwapHighlighted = highlighted;
    notifyListeners();
  }

  void highlightGroup(Object? groupId) {
    for (final cell in cells) {
      cell.isGroupHighlighted =
          groupId != null && cell.item?.seatGroupId == groupId;
    }
    notifyListeners();
  }

  void showTooltipFor(SeatCell<T>? cell) {
    for (final candidate in cells) {
      candidate.isTooltipHighlighted = candidate == cell;
    }
    notifyListeners();
  }

  void _scheduleFit() {
    if (_disposed) return;
    isLayoutReady = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) fitToViewport();
    });
  }

  void fitToViewport() {
    if (_disposed) return;
    final context = _layoutKey?.currentContext;
    final renderBox = context?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;
    final layoutWidth = columns * cellSize;
    final layoutHeight = rows * cellSize;
    if (layoutWidth <= 0 || layoutHeight <= 0) return;
    minScale = math
        .min(
          renderBox.size.width / layoutWidth,
          renderBox.size.height / layoutHeight,
        )
        .clamp(0.01, 1.0)
        .toDouble();
    final x = (renderBox.size.width - layoutWidth * minScale) / 2;
    final y = (renderBox.size.height - layoutHeight * minScale) / 2;
    transformationController.value = Matrix4.diagonal3Values(
      minScale,
      minScale,
      1,
    )..setTranslationRaw(x, y, 0);
    isLayoutReady = true;
    notifyListeners();
  }

  static void _validateDimensions(int rows, int columns, double cellSize) {
    if (rows <= 0 || columns <= 0) {
      throw ArgumentError('Layout dimensions must be positive');
    }
    if (!cellSize.isFinite || cellSize <= 0) {
      throw ArgumentError.value(cellSize, 'cellSize', 'Must be positive');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    transformationController.dispose();
    super.dispose();
  }
}
