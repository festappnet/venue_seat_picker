import 'package:flutter/material.dart';

import '../model/seat_status.dart';

/// Visual tokens used by the default venue seat renderer.
@immutable
class VenueSeatThemeData {
  const VenueSeatThemeData({
    this.available = const Color(0xff2e7d32),
    this.selected = const Color(0xff2e7d32),
    this.held = const Color(0x42000000),
    this.booked = const Color(0x1f000000),
    this.checkedIn = const Color(0xff1976d2),
    this.blocked = const Color(0xdd000000),
    this.selectionBorder = Colors.orange,
    this.highlightBorder,
    this.checkColor = Colors.white,
    this.bookedMarkColor = Colors.black,
  });

  final Color available;
  final Color selected;
  final Color held;
  final Color booked;
  final Color checkedIn;
  final Color blocked;
  final Color selectionBorder;
  final Color? highlightBorder;
  final Color checkColor;
  final Color bookedMarkColor;

  Color colorFor(SeatStatus status) => switch (status) {
    SeatStatus.available => available,
    SeatStatus.held => held,
    SeatStatus.booked => booked,
    SeatStatus.checkedIn => checkedIn,
    SeatStatus.blocked => blocked,
  };
}

/// Shared viewport and surface configuration for venue seat widgets.
@immutable
class VenueSeatViewConfig {
  const VenueSeatViewConfig({
    this.maxScale = 5,
    this.backgroundColor = Colors.white,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.theme = const VenueSeatThemeData(),
  }) : assert(maxScale > 0);

  final double maxScale;
  final Color backgroundColor;
  final BorderRadius borderRadius;
  final VenueSeatThemeData theme;
}
