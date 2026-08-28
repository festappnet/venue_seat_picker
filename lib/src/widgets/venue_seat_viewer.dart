import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../controller/venue_seat_controller.dart';
import '../model/seat_slot.dart';
import '../model/venue_backdrop.dart';
import 'venue_seat_marker.dart';
import 'venue_seat_style.dart';

typedef VenueSeatBuilder<T, Id extends Object> =
    Widget Function(BuildContext context, SeatSlot<T, Id> slot);

/// Zoomable and pannable venue seat map.
class VenueSeatViewer<T, Id extends Object> extends StatefulWidget {
  const VenueSeatViewer({
    super.key,
    required this.controller,
    this.onSeatPressed,
    this.editorMode = false,
    this.shouldShowTooltipOnTap,
    this.tooltipBuilder,
    this.seatBuilder,
    this.config = const VenueSeatViewConfig(),
  });

  final VenueSeatController<T, Id> controller;
  final ValueChanged<SeatSlot<T, Id>>? onSeatPressed;
  final bool editorMode;
  final bool Function(SeatSlot<T, Id> slot)? shouldShowTooltipOnTap;
  final String Function(BuildContext context, SeatSlot<T, Id> slot)?
  tooltipBuilder;
  final VenueSeatBuilder<T, Id>? seatBuilder;
  final VenueSeatViewConfig config;

  @override
  State<VenueSeatViewer<T, Id>> createState() => _VenueSeatViewerState<T, Id>();
}

class _VenueSeatViewerState<T, Id extends Object>
    extends State<VenueSeatViewer<T, Id>> {
  final GlobalKey _layoutKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    widget.controller
      ..attachLayoutKey(_layoutKey)
      ..addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant VenueSeatViewer<T, Id> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller
        ..attachLayoutKey(_layoutKey)
        ..addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final width = controller.columns * controller.seatSize;
    final height = controller.rows * controller.seatSize;
    return Container(
      key: _layoutKey,
      child: AnimatedOpacity(
        opacity: controller.isLayoutReady ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: InteractiveViewer(
          minScale: controller.minScale.clamp(0.01, widget.config.maxScale),
          maxScale: widget.config.maxScale,
          boundaryMargin: widget.config.boundaryMargin,
          constrained: false,
          transformationController: controller.transformationController,
          child: RepaintBoundary(
            child: SizedBox(
              width: width,
              height: height,
              child: Stack(
                children: [
                  Positioned.fill(child: _backdrop(width, height)),
                  for (final slot in controller.slots)
                    if (slot.seat != null || widget.editorMode)
                      Positioned(
                        left: slot.column * slot.size,
                        top: slot.row * slot.size,
                        child: _SeatTapTarget(
                          onTap: () => _tap(slot),
                          child: _seat(context, slot),
                        ),
                      ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _backdrop(double width, double height) {
    final backdrop = widget.controller.backdrop;
    Widget? child;
    if (backdrop case SvgVenueBackdrop(:final source)) {
      child = SvgPicture.string(
        source,
        width: width,
        height: height,
        fit: BoxFit.cover,
      );
    } else if (backdrop case NetworkVenueBackdrop(:final source)) {
      child = source.toLowerCase().endsWith('.svg')
          ? SvgPicture.network(
              source,
              width: width,
              height: height,
              fit: BoxFit.cover,
            )
          : Image.network(
              source,
              width: width,
              height: height,
              fit: BoxFit.cover,
            );
    } else if (backdrop case MemoryVenueBackdrop(:final bytes)) {
      child = Image.memory(
        bytes,
        width: width,
        height: height,
        fit: BoxFit.cover,
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => widget.controller.showTooltipFor(null),
      child: ClipRRect(
        borderRadius: widget.config.borderRadius,
        child: ColoredBox(color: widget.config.backgroundColor, child: child),
      ),
    );
  }

  Widget _seat(BuildContext context, SeatSlot<T, Id> slot) {
    final seat =
        widget.seatBuilder?.call(context, slot) ??
        VenueSeatMarker(
          status: slot.status,
          selected: slot.isSelected,
          pending: slot.isPending,
          size: slot.size,
          isSwapHighlighted: slot.isSwapHighlighted,
          isGroupHighlighted: slot.isGroupHighlighted,
          isTooltipHighlighted: slot.isTooltipHighlighted,
          theme: widget.config.theme,
        );
    final tooltip = widget.tooltipBuilder?.call(context, slot) ?? slot.label;
    return tooltip == null || tooltip.isEmpty
        ? seat
        : Tooltip(
            message: tooltip,
            triggerMode: widget.shouldShowTooltipOnTap?.call(slot) == true
                ? TooltipTriggerMode.tap
                : TooltipTriggerMode.longPress,
            child: seat,
          );
  }

  void _tap(SeatSlot<T, Id> slot) {
    if (widget.shouldShowTooltipOnTap?.call(slot) == true) {
      widget.controller.showTooltipFor(slot.isTooltipHighlighted ? null : slot);
      return;
    }
    widget.onSeatPressed?.call(slot);
  }
}

class _SeatTapTarget extends StatelessWidget {
  const _SeatTapTarget({required this.onTap, required this.child});
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: InkResponse(
      onTap: onTap,
      containedInkWell: true,
      highlightShape: BoxShape.rectangle,
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      child: child,
    ),
  );
}
