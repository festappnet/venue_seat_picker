# Editing and serialization

`VenueSeatEditor` edits the same controller used by `VenueSeatViewer` and
`VenueSeatPicker`. It resizes the grid, paints authoritative statuses and
removes seats through immutable model operations.

```dart
VenueSeatEditor<VenueSeat, Object>(
  controller: controller,
  statuses: const [SeatStatus.available, SeatStatus.blocked],
  editing: SeatEditingDelegate(
    create: (position, status) => VenueSeat(
      id: '${position.row}:${position.column}',
      position: position,
      status: status,
    ),
    withStatus: (seat, status) => seat.copyWith(status: status),
  ),
  onChanged: saveDraft,
)
```

Use a stable ID generator if coordinates can change. Shrinking is refused when
it would clip an occupied slot.

## Save the built-in model

```dart
final document = VenueSeatDocument(
  rows: controller.rows,
  columns: controller.columns,
  seats: controller.seats.cast<VenueSeat>(),
  backdrop: controller.backdrop,
);

final encoded = jsonEncode(document.toJson());
final restored = VenueSeatDocument.fromJson(
  jsonDecode(encoded) as Map<String, Object?>,
);
```

`schemaVersion` protects the portable format against incompatible changes. For
a custom model, persist your own domain objects and load them through their
`SeatAdapter`.

## Object table surface edits

Changing an object table surface outline returns its unlocked chairs to automatic
position and rotation. Seat identities and reservation protection remain intact;
locked chairs retain their world positions and may prevent a conflicting edit.
Ordinary seat-count changes keep manually positioned chairs in place.
