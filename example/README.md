# venue_seat_picker example

[Open the live interactive demo](https://festappnet.github.io/venue_seat_picker/)

This runnable application demonstrates:

- optimistic asynchronous selection with a pending indicator;
- a six-seat selection limit;
- zooming and panning around a compact theatre where individual seats remain
  easy to inspect;
- available, held, booked, checked-in and blocked statuses;
- switching the same venue into edit mode;
- painting, erasing and resizing the grid.

The example includes both the customer-facing picker and the staff-facing
editor. Its bundled fixture is a deliberately small, fictional theatre so the
seat states and editing interactions stay legible on phones and in the
repository demo.

Run it from this directory:

```console
flutter run
```

For web:

```console
flutter run -d chrome
```

Every push to the repository's `main` branch rebuilds and publishes the web
version to GitHub Pages.

The artificial 350 ms delay represents a backend reservation request. Replace
it with your application's atomic hold/release operation.
