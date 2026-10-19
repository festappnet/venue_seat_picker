import 'dart:convert';
import 'package:flutter/services.dart';

/// Optional licensed local fixtures for examples and standalone consumers.
/// Production hosts supply their own catalog/resources through the same seam.
Future<Map<String, dynamic>> loadLayoutFixtureResources() async =>
    jsonDecode(
          await rootBundle.loadString(
            'packages/venue_seat_picker/assets/layout_fonts/fixtures.json',
          ),
        )
        as Map<String, dynamic>;

abstract class LayoutFontProvider {
  List<Map<String, dynamic>> get catalog;
  Future<Map<String, dynamic>> resolve(String fontId);
}

abstract class LayoutAssetProvider {
  Future<Map<String, dynamic>> resolve(String assetRef);
}

/// A stale resolve must never replace a user's more recent choice.
class LayoutFontResolver {
  int _generation = 0;
  Future<bool> select(
    String id,
    LayoutFontProvider provider,
    void Function(Map<String, dynamic>) commit,
  ) async {
    final generation = ++_generation;
    final resource = await provider.resolve(id);
    if (generation != _generation) return false;
    if (resource['id'] != id ||
        resource['glyphs'] is! Map ||
        resource['hash'] is! String) {
      throw const FormatException('Invalid font resource');
    }
    commit(resource);
    return true;
  }

  void cancel() {
    _generation++;
  }
}
