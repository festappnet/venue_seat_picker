import 'package:flutter/material.dart';

import '../model/seat_state.dart';

@immutable
class SeatLayoutTheme {
  const SeatLayoutTheme({
    this.available = const Color(0xff2e7d32),
    this.selectedByMe = const Color(0xff2e7d32),
    this.selected = const Color(0x42000000),
    this.ordered = const Color(0x1f000000),
    this.used = const Color(0xff1976d2),
    this.blocked = const Color(0xdd000000),
    this.empty = Colors.transparent,
    this.selectionBorder = Colors.orange,
    this.highlightBorder,
    this.checkColor = Colors.white,
    this.orderedMarkColor = Colors.black,
  });

  final Color available;
  final Color selectedByMe;
  final Color selected;
  final Color ordered;
  final Color used;
  final Color blocked;
  final Color empty;
  final Color selectionBorder;
  final Color? highlightBorder;
  final Color checkColor;
  final Color orderedMarkColor;

  Color colorFor(SeatState state) => switch (state) {
        SeatState.available => available,
        SeatState.selectedByMe => selectedByMe,
        SeatState.selected => selected,
        SeatState.ordered => ordered,
        SeatState.used => used,
        SeatState.blocked => blocked,
        SeatState.empty => empty,
      };
}

class SeatLayoutConfig {
  const SeatLayoutConfig({
    this.maxScale = 5,
    this.backgroundColor = Colors.white,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.theme = const SeatLayoutTheme(),
  }) : assert(maxScale > 0);

  final double maxScale;
  final Color backgroundColor;
  final BorderRadius borderRadius;
  final SeatLayoutTheme theme;
}
