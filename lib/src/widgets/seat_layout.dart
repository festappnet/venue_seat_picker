import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../controller/seat_layout_controller.dart';
import '../model/seat_cell.dart';
import '../model/seat_layout_background.dart';
import '../model/seat_layout_item.dart';
import 'seat_layout_theme.dart';
import 'seat_tile.dart';

typedef SeatCellBuilder<T extends SeatLayoutItem> = Widget Function(
  BuildContext context,
  SeatCell<T> cell,
);

class SeatLayout<T extends SeatLayoutItem> extends StatefulWidget {
  const SeatLayout({
    super.key,
    required this.controller,
    this.onSeatTap,
    this.editorMode = false,
    this.shouldShowTooltipOnTap,
    this.tooltipBuilder,
    this.seatBuilder,
    this.config = const SeatLayoutConfig(),
  });

  final SeatLayoutController<T> controller;
  final ValueChanged<SeatCell<T>>? onSeatTap;
  final bool editorMode;
  final bool Function(SeatCell<T> cell)? shouldShowTooltipOnTap;
  final String Function(BuildContext context, SeatCell<T> cell)? tooltipBuilder;
  final SeatCellBuilder<T>? seatBuilder;
  final SeatLayoutConfig config;

  @override
  State<SeatLayout<T>> createState() => _SeatLayoutState<T>();
}

class _SeatLayoutState<T extends SeatLayoutItem> extends State<SeatLayout<T>> {
  final GlobalKey _layoutKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    widget.controller
      ..attachLayoutKey(_layoutKey)
      ..addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant SeatLayout<T> oldWidget) {
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
    final width = controller.columns * controller.cellSize;
    final height = controller.rows * controller.cellSize;
    return Container(
      key: _layoutKey,
      child: AnimatedOpacity(
        opacity: controller.isLayoutReady ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: InteractiveViewer(
          minScale: controller.minScale.clamp(0.01, widget.config.maxScale),
          maxScale: widget.config.maxScale,
          boundaryMargin: const EdgeInsets.all(double.infinity),
          constrained: false,
          transformationController: controller.transformationController,
          child: RepaintBoundary(
            child: SizedBox(
              width: width,
              height: height,
              child: Stack(
                children: [
                  Positioned.fill(child: _background(width, height)),
                  for (final cell in controller.cells)
                    if (cell.item != null || widget.editorMode)
                      Positioned(
                        left: cell.column * cell.size,
                        top: cell.row * cell.size,
                        child: _SeatTapTarget(
                          onTap: () => _tap(cell),
                          child: _seat(context, cell),
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

  Widget _background(double width, double height) {
    final background = widget.controller.background;
    Widget? child;
    if (background case SvgSeatLayoutBackground(:final source)) {
      child = SvgPicture.string(source,
          width: width, height: height, fit: BoxFit.cover);
    } else if (background case NetworkSeatLayoutBackground(:final source)) {
      child = source.toLowerCase().endsWith('.svg')
          ? SvgPicture.network(source,
              width: width, height: height, fit: BoxFit.cover)
          : Image.network(source,
              width: width, height: height, fit: BoxFit.cover);
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

  Widget _seat(BuildContext context, SeatCell<T> cell) {
    final seat = widget.seatBuilder?.call(context, cell) ??
        SeatTile(
          state: cell.state,
          size: cell.size,
          isSwapHighlighted: cell.isSwapHighlighted,
          isGroupHighlighted: cell.isGroupHighlighted,
          isTooltipHighlighted: cell.isTooltipHighlighted,
          theme: widget.config.theme,
        );
    final tooltip =
        widget.tooltipBuilder?.call(context, cell) ?? cell.item?.seatLabel;
    return tooltip == null || tooltip.isEmpty
        ? seat
        : Tooltip(
            message: tooltip,
            triggerMode: widget.shouldShowTooltipOnTap?.call(cell) == true
                ? TooltipTriggerMode.tap
                : TooltipTriggerMode.longPress,
            child: seat,
          );
  }

  void _tap(SeatCell<T> cell) {
    if (widget.shouldShowTooltipOnTap?.call(cell) == true) {
      widget.controller.showTooltipFor(cell.isTooltipHighlighted ? null : cell);
      return;
    }
    widget.onSeatTap?.call(cell);
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
