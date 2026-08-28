# venue_seat_picker

Interactive, editable venue seat layouts for Flutter. The package provides one
model seam for a zoomable viewer, an optimistic reservation picker, and a grid
editor. It works with the built-in JSON model or an application's existing
domain model.

Built for and used in production by [Festapp](https://festapp.net), including
the live application at [live.festapp.net](https://live.festapp.net).

![Picker selection and layout editing demo](https://raw.githubusercontent.com/festappnet/venue_seat_picker/main/doc/demo.gif)

[Watch the higher-quality WebM demo](https://github.com/festappnet/venue_seat_picker/raw/main/doc/demo.webm)

## Features

- Zoom and pan with automatic fit-to-viewport.
- Selection limits and optimistic async reservation with automatic rollback.
- Grid editor with paintable available, blocked and empty cells.
- Custom seat builders, tooltips, colors and background SVG/images.
- Versioned JSON documents through `BasicSeat` and `SeatLayoutDocument`.
- Generic `SeatLayoutItem` interface; no backend or state-management dependency.
- Android, iOS, Linux, macOS, web and Windows support.

## Quick start

Add the dependency:

```yaml
dependencies:
  venue_seat_picker: ^0.1.0
```

Create a controller, load a layout, and pass it to `SeatPicker`:

```dart
final seats = [
  BasicSeat(seatId: 'A1', seatRow: 0, seatColumn: 0, seatLabel: 'A1'),
  BasicSeat(seatId: 'A2', seatRow: 0, seatColumn: 1, seatLabel: 'A2'),
];

final controller = SeatLayoutController<BasicSeat>()
  ..loadLayout(rows: 4, columns: 8, items: seats);

SeatPicker<BasicSeat>(
  controller: controller,
  maxSelection: 4,
  onSelectionRequest: (cell, selected) async {
    // Reserve or release cell.item!.seatId in your backend.
    return true; // false rolls the optimistic visual change back.
  },
  onSelectionChanged: (selection) {
    print(selection.map((cell) => cell.item!.seatId));
  },
)
```

Create the controller in `State.initState` and dispose it with its owning
widget. The runnable [example application](example/) demonstrates selection,
the state legend, zoom and pan, and switching the same layout into edit mode.

## Use an existing domain model

Implement the small `SeatLayoutItem` interface. Pricing, authorization,
persistence and reservation locking remain in your application.

```dart
class VenueSeat implements SeatLayoutItem {
  VenueSeat(this.id, this.row, this.column, this.status);

  final int id;
  final int row;
  final int column;
  SeatState status;

  @override Object get seatId => id;
  @override int get seatRow => row;
  @override int get seatColumn => column;
  @override SeatState get seatState => status;
  @override set seatState(SeatState value) => status = value;
  @override String get seatLabel => 'Seat $id';
  @override Object? get seatGroupId => null;
}
```

## Editor

`SeatLayoutEditor` edits the same controller used by the viewer and picker.
The host supplies a factory so newly painted cells use its canonical model.

```dart
SeatLayoutEditor<BasicSeat>(
  controller: controller,
  createItem: (row, column, state) => BasicSeat(
    seatId: '$row:$column',
    seatRow: row,
    seatColumn: column,
    seatState: state,
  ),
  onChanged: saveDraft,
)
```

See `example/` for a runnable editor and picker.

## Guides

- [Getting started](doc/getting-started.md) — lifecycle, selection and errors.
- [Backend integration](doc/backend-integration.md) — optimistic reservations,
  rollback and real-time updates.
- [Editing and JSON](doc/editing-and-serialization.md) — layout authoring and
  persistence.
- [Theming and custom rendering](doc/theming.md) — colors, backgrounds,
  tooltips and custom seats.

The public API also has generated Dart documentation. Run `dart doc` locally or
open the API reference linked from pub.dev after release.

## Contract

- Rows, columns and cell size must be positive.
- Seat coordinates must be unique and inside the document dimensions.
- `setDimensions` refuses to clip occupied cells.
- `updateVisualState` is temporary; `updateSeat` also writes the host model.
- Async selection is optimistic and rejects duplicate taps while pending.

## Platform and SDK support

The package supports Android, iOS, Linux, macOS, web and Windows on Flutter
3.32 or newer and Dart 3.8 or newer. It intentionally has no backend or
state-management dependency.

## Contributing and support

Bug reports and feature requests belong in the
[issue tracker](https://github.com/festappnet/venue_seat_picker/issues). See
[CONTRIBUTING.md](CONTRIBUTING.md) for local checks and [SECURITY.md](SECURITY.md)
for private vulnerability reporting.

Licensed under the MIT License.
