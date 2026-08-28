# Theming and custom rendering

Pass `SeatLayoutConfig` to any layout widget to control zoom, surface styling
and state colors:

```dart
const config = SeatLayoutConfig(
  maxScale: 8,
  backgroundColor: Color(0xfff7f7fb),
  borderRadius: BorderRadius.all(Radius.circular(20)),
  theme: SeatLayoutTheme(
    available: Color(0xff00695c),
    selectedByMe: Color(0xff4527a0),
    blocked: Color(0xff263238),
    selectionBorder: Color(0xffffb300),
  ),
);
```

## Custom seats and tooltips

```dart
SeatPicker<MySeat>(
  controller: controller,
  config: config,
  tooltipBuilder: (context, cell) =>
      '${cell.item!.seatLabel} · ${cell.item!.priceLabel}',
  seatBuilder: (context, cell) => DecoratedBox(
    decoration: BoxDecoration(
      color: config.theme.colorFor(cell.state),
      shape: BoxShape.circle,
    ),
    child: Center(child: Text(cell.item!.shortLabel)),
  ),
)
```

Custom builders receive the complete `SeatCell`, including visual highlight
flags. Preserve a sufficiently large tap target for touch and keep state
distinctions accessible without relying on color alone.

## Backgrounds

Use `SvgSeatLayoutBackground` for inline SVG, or
`NetworkSeatLayoutBackground` for an HTTPS image/SVG URL. The convenience
factory detects inline SVG automatically:

```dart
controller.setBackground(SeatLayoutBackground.parse(backgroundSource));
```

Remote asset loading follows the platform's normal network and CORS rules. For
offline use, load an asset yourself and pass its SVG source as an inline
background, or render the asset in a custom surrounding widget.
