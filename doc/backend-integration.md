# Backend integration

The package owns interaction state, not reservation authority. Your backend
must remain the source of truth and atomically reject a seat that another user
already holds.

## Optimistic reservation

`onSelectionRequest` runs after the picker shows the requested state. Return
`true` only when the backend has accepted the operation:

```dart
Future<bool> reserveSeat(SeatCell<MySeat> cell, bool selected) async {
  try {
    if (selected) {
      await reservations.hold(cell.item!.seatId);
    } else {
      await reservations.release(cell.item!.seatId);
    }
    return true;
  } on SeatAlreadyHeldException {
    return false; // The picker restores the previous visual state.
  }
}
```

Thrown errors also roll back. Use `onSelectionError` to report them or show a
message. Duplicate taps on the same cell are ignored while its request is
pending.

## Real-time updates

Apply server events to the canonical item and controller:

```dart
void applyRemoteState(Object seatId, SeatState state) {
  for (final cell in controller.cells) {
    if (cell.item?.seatId == seatId) {
      controller.updateSeat(cell, state);
      return;
    }
  }
}
```

Translate backend status names at your data boundary instead of coupling
transport details to the widget.

## Recommended server contract

Send a stable seat ID, the requested operation, event or performance ID, and a
reservation version/token. Treat success as authoritative, make release
idempotent, and broadcast committed state changes to all connected clients.
Pricing, authentication, authorization and expiry remain application concerns.
