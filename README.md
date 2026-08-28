# venue_seat_picker

Interactive venue seat maps for Flutter: a zoomable viewer, optimistic
reservation picker and grid editor behind one consistent model seam.

Built for and used in production by [Festapp](https://festapp.net), including
the live application at [live.festapp.net](https://live.festapp.net).

![Mobile selection and venue editing demo](https://raw.githubusercontent.com/festappnet/venue_seat_picker/main/doc/demo.gif)

[Watch the higher-quality mobile WebM demo](https://github.com/festappnet/venue_seat_picker/raw/main/doc/demo.webm)

| Customer picker | Venue editor |
| --- | --- |
| ![Selecting seats on a venue floor plan](https://raw.githubusercontent.com/festappnet/venue_seat_picker/main/doc/picker.png) | ![Editing seats on the same venue floor plan](https://raw.githubusercontent.com/festappnet/venue_seat_picker/main/doc/editor.png) |

The picker and editor operate on the same controller and venue document, so an
application can offer customer selection and staff editing without maintaining
two layout implementations. The media above uses an anonymized venue plan
adapted from Festapp's production deployment at
[vstupenky.online](https://vstupenky.online).

## Features

- Zoom, pan and automatic fit-to-viewport.
- Optimistic async selection with rollback and duplicate-tap protection.
- Selection limits, pending indicators and custom eligibility rules.
- Grid editor with immutable create/update delegates.
- Custom seat builders, tooltips, colors and SVG/image backdrops.
- Versioned JSON through `VenueSeat` and `VenueSeatDocument`.
- Read-only `SeatAdapter`; the package never mutates your domain objects.
- Android, iOS, Linux, macOS, web and Windows support.

## Quick start

```yaml
dependencies:
  venue_seat_picker: ^0.1.0
```

```dart
final seats = [
  const VenueSeat(id: 'A1', position: SeatPosition(0, 0), label: 'A1'),
  const VenueSeat(id: 'A2', position: SeatPosition(0, 1), label: 'A2'),
];

final controller = VenueSeatController<VenueSeat, Object>(
  adapter: venueSeatAdapter,
)..loadPlan(rows: 4, columns: 8, seats: seats);

VenueSeatPicker<VenueSeat, Object>(
  controller: controller,
  maxSelectedSeats: 4,
  onSelectionRequested: (request) async {
    return request.selected
        ? reservations.hold(request.seatId)
        : reservations.release(request.seatId);
  },
  onSelectionChanged: (selectedIds) {
    debugPrint('$selectedIds');
  },
)
```

Create the controller in `State.initState` and dispose it with its owning
widget. The runnable [example application](example/) demonstrates selection,
pending state, zoom, a detailed SVG floor plan, status rendering and live
layout editing.

## Use an existing domain model

Map it through a read-only adapter. Pricing, authorization, persistence and
reservation locking remain in your application.

```dart
final adapter = SeatAdapter<MySeat, int>(
  idOf: (seat) => seat.id,
  positionOf: (seat) => SeatPosition(seat.row, seat.column),
  statusOf: (seat) => switch (seat.status) {
    MyStatus.free => SeatStatus.available,
    MyStatus.held => SeatStatus.held,
    MyStatus.sold => SeatStatus.booked,
  },
  labelOf: (seat) => seat.label,
  groupOf: (seat) => seat.sectionId,
);

final controller = VenueSeatController<MySeat, int>(adapter: adapter)
  ..loadPlan(rows: venue.rows, columns: venue.columns, seats: venue.seats);
```

Current-user selection is an optimistic UI overlay, not a `SeatStatus`. This
keeps the package from writing transient state into your authoritative model.

## Editor

```dart
VenueSeatEditor<VenueSeat, Object>(
  controller: controller,
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

## Guides

- [Getting started](doc/getting-started.md)
- [Backend integration](doc/backend-integration.md)
- [Editing and JSON](doc/editing-and-serialization.md)
- [Theming and custom rendering](doc/theming.md)

## Contract

- Rows, columns and seat size must be positive.
- Seat IDs and positions must be unique and inside the venue grid.
- Missing positions are empty slots, not a seat status.
- Shrinking refuses to clip occupied slots.
- Only `available` seats can be selected; selected seats can be released.
- A rejected or failed request restores the previous optimistic selection.

Flutter 3.32+ and Dart 3.8+ are supported. The package intentionally has no
backend or state-management dependency.

See [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md), and the
[issue tracker](https://github.com/festappnet/venue_seat_picker/issues).

Licensed under the MIT License.
