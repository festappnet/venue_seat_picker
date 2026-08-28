# Getting started

`venue_seat_picker` separates layout state from rendering. Your widget owns a
`SeatLayoutController`, loads seats into it, and chooses whether to render a
viewer, picker or editor.

## 1. Add the package

```yaml
dependencies:
  venue_seat_picker: ^0.1.0
```

## 2. Own the controller

Create and dispose the controller with the widget that owns the layout:

```dart
late final SeatLayoutController<BasicSeat> controller;

@override
void initState() {
  super.initState();
  controller = SeatLayoutController<BasicSeat>()
    ..loadLayout(
      rows: 20,
      columns: 30,
      items: seats,
      cellSize: 44,
    );
}

@override
void dispose() {
  controller.dispose();
  super.dispose();
}
```

Coordinates are zero-based. Each occupied coordinate must be unique and inside
the declared dimensions. Missing coordinates render as empty space.

## 3. Render a picker

```dart
SeatPicker<BasicSeat>(
  controller: controller,
  maxSelection: 6,
  onSelectionRequest: reserveSeat,
  onSelectionChanged: (cells) {
    setState(() => selectedIds = {
      for (final cell in cells) cell.item!.seatId,
    });
  },
  onLimitReached: showSelectionLimit,
  onSelectionError: reportSelectionError,
)
```

Only `available` and `selectedByMe` cells toggle by default. Use `isSelectable`
for application rules such as price-zone access. The picker applies the visual
change immediately while `onSelectionRequest` runs, then commits or rolls it
back from the returned boolean.

## Choosing a model

Use `BasicSeat` when its versioned JSON shape fits your application. If you
already have a domain model, implement `SeatLayoutItem`; the picker will keep
using your object instances and does not require a data conversion layer.

See the repository [example](../example/) for a complete runnable application
and [backend integration](backend-integration.md) for concurrent reservations.
