# Theming and custom rendering

`VenueSeatThemeData` follows Flutter's `ThemeData` naming convention. Pass it
inside `VenueSeatViewConfig` to any viewer, picker or editor:

```dart
const config = VenueSeatViewConfig(
  maxScale: 8,
  backgroundColor: Color(0xfff7f7fb),
  borderRadius: BorderRadius.all(Radius.circular(20)),
  theme: VenueSeatThemeData(
    available: Color(0xff00695c),
    selected: Color(0xff4527a0),
    blocked: Color(0xff263238),
    selectionBorder: Color(0xffffb300),
  ),
);
```

## Custom markers and tooltips

```dart
VenueSeatPicker<MySeat, int>(
  controller: controller,
  config: config,
  tooltipBuilder: (context, slot) =>
      '${slot.label} · ${slot.seat!.priceLabel}',
  seatBuilder: (context, slot) => DecoratedBox(
    decoration: BoxDecoration(
      color: slot.isSelected
          ? config.theme.selected
          : config.theme.colorFor(slot.status!),
      shape: BoxShape.circle,
    ),
    child: Center(child: Text(slot.seat!.shortLabel)),
  ),
)
```

Custom builders receive `SeatSlot`, including selected, pending and highlight
flags. Preserve a sufficiently large tap target and avoid relying on color
alone.

## Backdrops

Use `SvgVenueBackdrop` for inline SVG or `NetworkVenueBackdrop` for an HTTPS
image/SVG URL:

```dart
controller.setBackdrop(VenueBackdrop.parse(source));
```

Remote loading follows the platform's network and CORS rules.
