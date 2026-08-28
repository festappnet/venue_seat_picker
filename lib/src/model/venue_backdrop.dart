/// Optional image rendered behind a venue's seat grid.
sealed class VenueBackdrop {
  const VenueBackdrop();

  factory VenueBackdrop.parse(String source) {
    final trimmed = source.trim();
    if (trimmed.startsWith('<svg')) return SvgVenueBackdrop(trimmed);
    return NetworkVenueBackdrop(trimmed);
  }

  String get source;
}

class SvgVenueBackdrop extends VenueBackdrop {
  const SvgVenueBackdrop(this.source);
  @override
  final String source;
}

class NetworkVenueBackdrop extends VenueBackdrop {
  const NetworkVenueBackdrop(this.source);
  @override
  final String source;
}
