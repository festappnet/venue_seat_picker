## 0.2.0

### Breaking changes and migration

- The new `VenueLayout*` object API is not a drop-in replacement for the
  `VenueSeat*` grid API. Adopting it requires updating your document, controller
  and widget integration.
- `VenueLayoutDocument` JSON is incompatible with `VenueSeatDocument` JSON,
  even though both use schema version 1. Store the formats separately or provide
  an explicit application-owned conversion; changing the schema number alone
  does not convert a plan. No automatic migration is provided.
- Existing `VenueSeat*` grid APIs remain supported. Updating the dependency alone
  does not require migrating an existing grid integration. See the
  [migration guide](doc/blueprint-v2/MIGRATION.md) before adopting object layouts.

### Added

- Add a backend-independent object layout document, controller and shared Dart/JS scene runtime alongside the existing grid API.
- Add an editor, viewer, async picker, public nine-template library and licensed local resource fixtures.
- Add standalone Flutter/JS demos, local export/import/autosave, reproducible kit tooling and explicit simulated host boundaries.
- Document schema 1 as a separate contract from VenueSeatDocument. Existing grid consumers remain supported; no automatic migration is performed.

## 0.1.2

- Keep zoomed plans visible by default in the viewer, picker and editor, center
  small plans, and update pan bounds when the viewport changes. Explicit infinite
  boundary margins retain unrestricted panning.
- Added in-memory image backdrops for local file previews and configurable pan
  boundaries.

## 0.1.1

- Removed visual grid lines from empty editor slots while keeping them tappable.
- Added native light and dark surface support through the host `ThemeData`.
- Improved the mobile demo with explanatory action captions.

## 0.1.0

- Initial release with `VenueSeatViewer`, `VenueSeatPicker` and
  `VenueSeatEditor`.
- Added a read-only `SeatAdapter`, immutable `VenueSeat` model, optimistic
  selection overlay, versioned JSON, custom rendering, theming, and tests.
- Extracted from and used in production by Festapp.
