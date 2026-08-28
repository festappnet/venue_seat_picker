import 'package:flutter/material.dart';

import '../model/seat_state.dart';
import 'seat_layout_theme.dart';

class SeatTile extends StatelessWidget {
  const SeatTile({
    super.key,
    required this.state,
    this.size = 40,
    this.isSwapHighlighted = false,
    this.isGroupHighlighted = false,
    this.isTooltipHighlighted = false,
    this.theme = const SeatLayoutTheme(),
  });

  final SeatState state;
  final double size;
  final bool isSwapHighlighted;
  final bool isGroupHighlighted;
  final bool isTooltipHighlighted;
  final SeatLayoutTheme theme;

  @override
  Widget build(BuildContext context) {
    final visible = state != SeatState.empty ||
        isSwapHighlighted ||
        isGroupHighlighted ||
        isTooltipHighlighted;
    final border = isSwapHighlighted
        ? Border.all(color: theme.selectionBorder, width: 2)
        : isGroupHighlighted || isTooltipHighlighted
            ? Border.all(
                color: theme.highlightBorder ??
                    Theme.of(context).colorScheme.primary,
                width: 2,
              )
            : null;
    return SizedBox.square(
      dimension: size,
      child: Container(
        margin: visible
            ? EdgeInsets.all(state == SeatState.selectedByMe ? .8 : 2.5)
            : null,
        decoration: BoxDecoration(
          color: theme.colorFor(state),
          borderRadius: visible ? BorderRadius.circular(2.5) : null,
          border: border,
        ),
        child: switch (state) {
          SeatState.selectedByMe =>
            Icon(Icons.check, size: size * .7, color: theme.checkColor),
          SeatState.ordered =>
            CustomPaint(painter: _CrossPainter(theme.orderedMarkColor)),
          _ => null,
        },
      ),
    );
  }
}

class _CrossPainter extends CustomPainter {
  const _CrossPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = size.shortestSide * .28;
    final paint = Paint()
      ..color = color
      ..strokeWidth = .8;
    canvas
      ..drawLine(Offset(inset, inset),
          Offset(size.width - inset, size.height - inset), paint)
      ..drawLine(Offset(size.width - inset, inset),
          Offset(inset, size.height - inset), paint);
  }

  @override
  bool shouldRepaint(covariant _CrossPainter oldDelegate) =>
      oldDelegate.color != color;
}
