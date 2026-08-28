# venue_seat_picker example

This runnable application demonstrates:

- optimistic asynchronous selection with a pending indicator;
- a four-seat selection limit;
- zooming and panning;
- available, held, booked, checked-in and blocked statuses;
- switching the same venue into edit mode;
- painting, erasing and resizing the grid.

The example includes both the customer-facing picker and the staff-facing
editor. Its bundled venue fixture is adapted from a real Festapp deployment at
[vstupenky.online](https://vstupenky.online); customer data, order data,
database identifiers and credentials are not included.

Run it from this directory:

```console
flutter run
```

For web:

```console
flutter run -d chrome
```

The artificial 350 ms delay represents a backend reservation request. Replace
it with your application's atomic hold/release operation.
