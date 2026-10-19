import 'package:venue_layout_core/venue_layout_core.dart';

/// Retains canonical scene items across immutable document snapshots. Geometry
/// and presentation updates share one patch path; structural/global edits use
/// the full compiler. This cache owns only derived rendering data.
class LayoutSceneCache {
  VenueLayoutDocument? _document;
  Map<String, dynamic>? _resources, _presentation, _scene;
  Map<String, LayoutNode> _nodes = {};
  Map<String, List<String>> _children = {};

  Map<String, dynamic> update(
    VenueLayoutDocument document, {
    Map<String, dynamic> resources = const {},
    Map<String, dynamic> presentation = const {},
  }) {
    if (identical(_document, document) &&
        identical(_resources, resources) &&
        identical(_presentation, presentation)) {
      return _scene!;
    }
    final previous = _document;
    final documentChanged = !identical(previous, document);
    final nextNodes = documentChanged
        ? {for (final node in document.nodes) node.id: node}
        : _nodes;
    var full =
        previous == null ||
        (_scene?['issues'] as List? ?? const []).isNotEmpty ||
        !identical(_resources, resources) ||
        (documentChanged &&
            (previous.symbolSetVersion != document.symbolSetVersion ||
                !sameLayoutValue(previous.canvas, document.canvas) ||
                !sameLayoutValue(previous.background, document.background) ||
                !sameLayoutValue(previous.appearance, document.appearance) ||
                !sameLayoutValue(
                  previous.defaultTextStyle,
                  document.defaultTextStyle,
                ) ||
                !sameLayoutValue(
                  previous.selectionUnits,
                  document.selectionUnits,
                ) ||
                _nodes.length != nextNodes.length));
    final affected = <String>{};
    if (!full && documentChanged) {
      for (final node in document.nodes) {
        final old = _nodes[node.id];
        if (old == null ||
            old.kind != node.kind ||
            old.parentId != node.parentId ||
            old.z != node.z) {
          full = true;
          break;
        }
        if (!sameLayoutNode(old, node)) affected.add(node.id);
      }
      // Compiler validation is memoized per immutable snapshot. Invalid input
      // must replace the entire scene, never leave old valid items visible.
      if (validateDocument(document).isNotEmpty) full = true;
      if (!full) {
        final queue = affected.toList();
        for (var i = 0; i < queue.length; i++) {
          for (final id in _children[queue[i]] ?? const <String>[]) {
            if (affected.add(id)) queue.add(id);
          }
        }
      }
    }
    if (!full && !identical(_presentation, presentation)) {
      for (final id in {...?_presentation?.keys, ...presentation.keys}) {
        if (!sameLayoutValue(_presentation?[id], presentation[id])) {
          affected.add(id);
        }
      }
    }
    if (full) {
      _scene = compileScene(
        document,
        resources: resources,
        presentation: presentation,
      );
      _children = {};
      for (final node in document.nodes) {
        if (node.parentId != null) {
          (_children[node.parentId!] ??= []).add(node.id);
        }
      }
    } else if (affected.isNotEmpty) {
      final patch = compileSceneNodes(
        document,
        affected,
        resources: resources,
        presentation: presentation,
      );
      final replacements = <String, List<dynamic>>{};
      for (final item in patch['items'] as List) {
        (replacements['${item['nodeId'] ?? item['id']}'] ??= []).add(item);
      }
      final inserted = <String>{};
      final items = <dynamic>[];
      for (final item in _scene!['items'] as List) {
        final id = '${item['nodeId'] ?? item['id']}';
        if (affected.contains(id)) {
          if (inserted.add(id)) items.addAll(replacements[id] ?? const []);
        } else {
          items.add(item);
        }
      }
      // An item may become visible after previously compiling to no paths.
      // Sort only this uncommon case, using canonical compiler paint ranks.
      var added = false;
      for (final entry in replacements.entries) {
        if (!inserted.contains(entry.key)) {
          items.addAll(entry.value);
          added = true;
        }
      }
      if (added) {
        items.sort((dynamic a, dynamic b) {
          final ar = a['paintOrder'] as List? ?? const [-1, 0];
          final br = b['paintOrder'] as List? ?? const [-1, 0];
          final rank = (ar[0] as num).compareTo(br[0] as num);
          return rank != 0 ? rank : (ar[1] as num).compareTo(br[1] as num);
        });
      }
      _scene = {
        ..._scene!,
        'canvas': document.canvas,
        'items': items,
        'issues': [
          ...(_scene!['issues'] as List).where(
            (dynamic i) => !affected.contains(i['nodeId']),
          ),
          ...patch['issues'] as List,
        ],
      };
    }
    if (!full && (_scene!['issues'] as List).isNotEmpty) {
      _scene = compileScene(
        document,
        resources: resources,
        presentation: presentation,
      );
    }
    _document = document;
    _nodes = nextNodes;
    _resources = resources;
    _presentation = presentation;
    return _scene!;
  }
}
