# Editing and serialization

`SeatLayoutEditor` edits the same controller used by `SeatLayout` and
`SeatPicker`. It can resize the grid and paint the states supplied through
`states`.

```dart
SeatLayoutEditor<BasicSeat>(
  controller: controller,
  states: const [
    SeatState.available,
    SeatState.blocked,
    SeatState.empty,
  ],
  createItem: (row, column, state) => BasicSeat(
    seatId: '$row:$column',
    seatRow: row,
    seatColumn: column,
    seatState: state,
  ),
  onChanged: saveDraft,
)
```

Use your application's stable ID generator when coordinates are not permanent.
Shrinking is refused when it would clip an occupied cell. Remove or move those
cells first.

## Save the built-in model

```dart
final document = SeatLayoutDocument(
  rows: controller.rows,
  columns: controller.columns,
  seats: controller.cells
      .map((cell) => cell.item)
      .whereType<BasicSeat>()
      .toList(),
  background: controller.background,
);

final encoded = jsonEncode(document.toJson());
final restored = SeatLayoutDocument.fromJson(
  jsonDecode(encoded) as Map<String, Object?>,
);
```

`schemaVersion` protects the portable document format against incompatible
changes. The current reader accepts version 1. When using your own
`SeatLayoutItem`, serialize that domain model directly and call `loadLayout`
after restoring it.

Call `updateSeat` for durable model changes. `updateVisualState` intentionally
changes only the rendered cell and is primarily useful for optimistic UI.
