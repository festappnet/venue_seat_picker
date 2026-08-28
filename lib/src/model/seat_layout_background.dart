sealed class SeatLayoutBackground {
  const SeatLayoutBackground();

  factory SeatLayoutBackground.parse(String source) {
    final trimmed = source.trim();
    if (trimmed.startsWith('<svg')) return SvgSeatLayoutBackground(trimmed);
    return NetworkSeatLayoutBackground(trimmed);
  }

  String get source;
}

class SvgSeatLayoutBackground extends SeatLayoutBackground {
  const SvgSeatLayoutBackground(this.source);
  @override
  final String source;
}

class NetworkSeatLayoutBackground extends SeatLayoutBackground {
  const NetworkSeatLayoutBackground(this.source);
  @override
  final String source;
}
