# venue_seat_picker example

This application demonstrates the complete package workflow:

- selecting up to four seats through an asynchronous reservation callback;
- zooming and panning a venue layout;
- rendering available, selected, ordered, used and blocked states;
- switching the same controller into edit mode;
- painting cells and changing the grid dimensions.

Run it from this directory:

```console
flutter run
```

For the web demo used by the repository animation:

```console
flutter run -d chrome
```

The artificial 250 ms delay in `onSelectionRequest` represents a backend
request. Replace it with the reservation operation used by your application.
