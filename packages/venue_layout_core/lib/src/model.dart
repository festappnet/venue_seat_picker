import 'dart:convert';
import 'dart:math';

const layoutProtocol = 1;
const layoutLimits = <String, num>{
  'maxNodes': layoutMaxNodes,
  'maxSeats': layoutMaxSeats,
  'maxDepth': layoutMaxDepth,
  'maxBytes': layoutMaxBytes,
  'geometryAbsMax': 1000000000,
  'glyphMinLogicalPixels': 6,
  'canvasMin': 64,
  'canvasMax': 1000000,
  'textMaxCodePoints': 4096,
  'fontSizeMin': 1,
  'fontSizeMax': 4096,
  'lineHeightMin': 0.8,
  'lineHeightMax': 3,
  'verticesMin': 2,
  'polygonVerticesMin': 3,
  'verticesMax': 512,
  'presetsMax': 100,
  'presetNodesMax': 2000,
  'cropMin': 0,
  'cropMax': 1,
  'opacityMin': 0,
  'opacityMax': 1,
  'historyCommandsMax': 100,
  'historyBytesMax': 32 * 1024 * 1024,
  'fitCandidatesMax': 100000,
  'fitBatchMicroseconds': 8000,
  'coordinateQuantum': 1024,
};
const layoutMaxNodes = 25000;
const layoutMaxSeats = 20000;
const layoutMaxDepth = 16;
const layoutMaxBytes = 8 * 1024 * 1024;
double quantize(num value) =>
    (value * layoutLimits['coordinateQuantum']!).round() /
    layoutLimits['coordinateQuantum']!;
final _random = Random.secure();
String newLayoutId() {
  final b = List<int>.generate(16, (_) => _random.nextInt(256));
  b[6] = (b[6] & 15) | 64;
  b[8] = (b[8] & 63) | 128;
  final s = b.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
}

dynamic freeze(dynamic value) {
  final active = Set<Object>.identity();
  var entries = 0;
  dynamic copy(dynamic v, int depth) {
    if (depth > 64 || ++entries > 1000000)
      throw const FormatException('JSON nesting or value count limit exceeded');
    if (v == null || v is String || v is bool || v is num) return v;
    if (v is! Map && v is! List)
      throw const FormatException('Only JSON values are supported');
    if (!active.add(v as Object))
      throw const FormatException('Cyclic JSON value');
    dynamic result;
    if (v is Map) {
      if (v.keys.any((k) => k is! String))
        throw const FormatException('JSON keys must be strings');
      result = Map<String, dynamic>.unmodifiable(
        v.map((k, x) => MapEntry(k as String, copy(x, depth + 1))),
      );
    } else {
      result = List<dynamic>.unmodifiable(
        (v as List).map((x) => copy(x, depth + 1)),
      );
    }
    active.remove(v);
    return result;
  }

  return copy(value, 0);
}

Map<String, dynamic> frozenMap(Map<String, dynamic> v) =>
    freeze(v) as Map<String, dynamic>;

class InvalidLayoutDocument implements Exception {
  final List<LayoutIssue> issues;
  final Map<String, dynamic> original;
  InvalidLayoutDocument(List<LayoutIssue> issues, Map<String, dynamic> original)
    : issues = List.unmodifiable(issues),
      original = frozenMap(original);
  @override
  String toString() =>
      'Invalid layout: ${issues.map((i) => i.toString()).join('; ')}';
}

class UnsupportedLayoutSchema implements Exception {
  final Map<String, dynamic> original;
  UnsupportedLayoutSchema(this.original);
  @override
  String toString() => 'Unsupported layout schema ${original['schemaVersion']}';
}

class LayoutIssue {
  final String reason, path;
  final String? nodeId;
  const LayoutIssue(this.reason, this.path, [this.nodeId]);
  Map<String, dynamic> toJson() => {
    'reason': reason,
    'path': path,
    if (nodeId != null) 'nodeId': nodeId,
  };
  @override
  String toString() => '$path: $reason';
}

class LayoutNode {
  final String id, kind, label;
  final String? parentId;
  final double x, y, rotation, width, height;
  final int z;
  final bool locked;
  final Map<String, dynamic> properties;
  LayoutNode({
    required this.id,
    required this.kind,
    this.parentId,
    this.x = 0,
    this.y = 0,
    this.rotation = 0,
    this.width = 40,
    this.height = 40,
    this.z = 0,
    this.locked = false,
    this.label = '',
    Map<String, dynamic> properties = const {},
  }) : properties = frozenMap(properties);
  factory LayoutNode.fromJson(Map<String, dynamic> j) {
    final decodeIssues = _nodeDecodeIssues(j);
    if (decodeIssues.isNotEmpty) throw InvalidLayoutDocument(decodeIssues, j);
    final t = j['transform'] as Map;
    final props = Map<String, dynamic>.from(j)
      ..removeWhere(
        (k, v) => const [
          'id',
          'kind',
          'parentId',
          'transform',
          'x',
          'y',
          'rotation',
          'width',
          'height',
          'z',
          'locked',
          'label',
          'x',
          'y',
          'rotation',
        ].contains(k),
      );
    return LayoutNode(
      id: j['id'] as String,
      kind: j['kind'] as String,
      parentId: j['parentId'] as String?,
      x: (t['x'] as num? ?? 0).toDouble(),
      y: (t['y'] as num? ?? 0).toDouble(),
      rotation: (t['rotation'] as num? ?? 0).toDouble(),
      width: (j['width'] as num? ?? 40).toDouble(),
      height: (j['height'] as num? ?? 40).toDouble(),
      z: j['z'] as int? ?? 0,
      locked: j['locked'] as bool? ?? false,
      label: j['label'] as String? ?? '',
      properties: props,
    );
  }
  LayoutNode copyWith({
    String? kind,
    String? parentId,
    bool clearParent = false,
    double? x,
    double? y,
    double? rotation,
    double? width,
    double? height,
    String? label,
    bool? locked,
    Map<String, dynamic>? properties,
    int? z,
  }) => LayoutNode(
    id: id,
    kind: kind ?? this.kind,
    parentId: clearParent ? null : parentId ?? this.parentId,
    x: x ?? this.x,
    y: y ?? this.y,
    rotation: rotation ?? this.rotation,
    width: width ?? this.width,
    height: height ?? this.height,
    z: z ?? this.z,
    locked: locked ?? this.locked,
    label: label ?? this.label,
    properties: properties ?? this.properties,
  );
  Map<String, dynamic> toJson() => {
    ...properties,
    if (properties['appearanceOverrides'] is List)
      'appearanceOverrides': (List<String>.from(
        properties['appearanceOverrides'],
      )..sort()),
    'id': id,
    'kind': kind,
    if (parentId != null) 'parentId': parentId,
    'transform': {
      'x': quantize(x),
      'y': quantize(y),
      'rotation': quantize(rotation),
    },
    'width': quantize(width),
    'height': quantize(height),
    if (z != 0) 'z': z,
    if (locked) 'locked': true,
    if (label.isNotEmpty) 'label': label,
  };
}

class VenueLayoutDocument {
  final List<LayoutNode> nodes;
  final Map<String, dynamic> canvas, defaultTextStyle, appearance;
  final List<Map<String, dynamic>> sections,
      selectionUnits,
      attachments,
      presets,
      generators;
  final Map<String, dynamic>? background;
  final int symbolSetVersion;
  VenueLayoutDocument({
    List<LayoutNode> nodes = const [],
    Map<String, dynamic> canvas = const {
      'x': 0,
      'y': 0,
      'width': 2400,
      'height': 1600,
      'fill': '#FFFFFFFF',
    },
    Map<String, dynamic> defaultTextStyle = const {
      'fontId': 'fixture:sans',
      'size': 24,
      'color': '#222222FF',
    },
    Map<String, dynamic> appearance = const {},
    List<Map<String, dynamic>> sections = const [],
    List<Map<String, dynamic>> selectionUnits = const [],
    List<Map<String, dynamic>> attachments = const [],
    List<Map<String, dynamic>> presets = const [],
    List<Map<String, dynamic>> generators = const [],
    Map<String, dynamic>? background,
    this.symbolSetVersion = 1,
  }) : nodes = List.unmodifiable(nodes),
       canvas = frozenMap(canvas),
       defaultTextStyle = frozenMap(defaultTextStyle),
       appearance = frozenMap(appearance),
       sections = _maps(sections),
       // Unit kinds were optional in v1; all consumers already interpret an
       // omitted kind atomically. Normalize that legacy spelling at the model
       // boundary so reservation guards share the same explicit semantics.
       selectionUnits = _maps([
         for (final unit in selectionUnits)
           {...unit, 'kind': unit['kind'] ?? 'atomic'},
       ]),
       attachments = _maps(attachments),
       presets = _maps(presets),
       generators = _maps(generators),
       background = background == null ? null : frozenMap(background);
  static List<Map<String, dynamic>> _maps(List<Map<String, dynamic>> l) =>
      List.unmodifiable(l.map(frozenMap));
  factory VenueLayoutDocument.empty() => VenueLayoutDocument();
  factory VenueLayoutDocument.fromJson(Map<String, dynamic> j) {
    if (j['schemaVersion'] != 1) throw UnsupportedLayoutSchema(frozenMap(j));
    final decodeIssues = _documentDecodeIssues(j);
    if (decodeIssues.isNotEmpty) throw InvalidLayoutDocument(decodeIssues, j);
    List<Map<String, dynamic>> maps(String k) => (j[k] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final decoded = VenueLayoutDocument(
      nodes: (j['nodes'] as List? ?? [])
          .map((e) => LayoutNode.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      canvas: Map<String, dynamic>.from(j['canvas'] as Map),
      defaultTextStyle: Map<String, dynamic>.from(
        j['defaultTextStyle'] as Map? ?? {},
      ),
      appearance: Map<String, dynamic>.from(j['appearance'] as Map? ?? {}),
      sections: maps('sections'),
      selectionUnits: maps('selectionUnits'),
      attachments: maps('attachments'),
      presets: maps('presets'),
      generators: maps('generators'),
      background: j['background'] == null
          ? null
          : Map<String, dynamic>.from(j['background']),
      symbolSetVersion: j['symbolSetVersion'] as int? ?? 1,
    );
    final issues = validateDocument(decoded);
    if (issues.isNotEmpty) throw InvalidLayoutDocument(issues, j);
    return decoded;
  }
  VenueLayoutDocument copyWith({
    List<LayoutNode>? nodes,
    Map<String, dynamic>? canvas,
    Map<String, dynamic>? defaultTextStyle,
    Map<String, dynamic>? appearance,
    List<Map<String, dynamic>>? sections,
    List<Map<String, dynamic>>? selectionUnits,
    List<Map<String, dynamic>>? attachments,
    List<Map<String, dynamic>>? presets,
    List<Map<String, dynamic>>? generators,
    Map<String, dynamic>? background,
    bool clearBackground = false,
  }) => VenueLayoutDocument(
    nodes: nodes ?? this.nodes,
    canvas: canvas ?? this.canvas,
    defaultTextStyle: defaultTextStyle ?? this.defaultTextStyle,
    appearance: appearance ?? this.appearance,
    sections: sections ?? this.sections,
    selectionUnits: selectionUnits ?? this.selectionUnits,
    attachments: attachments ?? this.attachments,
    presets: presets ?? this.presets,
    generators: generators ?? this.generators,
    background: clearBackground ? null : background ?? this.background,
    symbolSetVersion: symbolSetVersion,
  );
  Map<String, dynamic> toJson() {
    final issues = validateDocument(this);
    if (issues.isNotEmpty)
      throw InvalidLayoutDocument(issues, {
        'schemaVersion': 1,
        'nodes': nodes.map((n) => {'id': n.id, 'kind': n.kind}).toList(),
      });
    return _toJsonUnchecked();
  }

  Map<String, dynamic> _toJsonUnchecked({bool includeNodes = true}) =>
      _canonicalMap({
        'schemaVersion': 1,
        'symbolSetVersion': symbolSetVersion,
        'canvas': canvas,
        'defaultTextStyle': defaultTextStyle,
        if (appearance.isNotEmpty) 'appearance': appearance,
        'nodes':
            ((includeNodes ? nodes.toList() : <LayoutNode>[])
                  ..sort((a, b) => a.id.compareTo(b.id)))
                .map((n) => n.toJson())
                .toList(),
        'sections': _sortedRecords(sections),
        'selectionUnits': _sortedRecords(
          selectionUnits
              .map(
                (u) => {
                  ...u,
                  if (u['nodeIds'] is List)
                    'nodeIds': (List<dynamic>.from(u['nodeIds'])
                      ..sort((a, b) => a.toString().compareTo(b.toString()))),
                },
              )
              .toList(),
        ),
        'attachments': _sortedRecords(attachments, key: 'seatId'),
        'generators': _sortedRecords(generators),
        'background': background,
        'presets': _sortedRecords(
          presets
              .map(
                (p) => {
                  ...p,
                  'document': VenueLayoutDocument.fromJson(
                    Map<String, dynamic>.from(p['document']),
                  ).toJson(),
                },
              )
              .toList(),
        ),
      });
}

final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
);
final layoutColorPattern = RegExp(r'^#[0-9a-fA-F]{8}$');
// Layout nodes are deeply immutable. Weak keys avoid retaining old drafts;
// canvas-only snapshots can reuse the exact encoded byte count of each node.
final _encodedNodeBytes = Expando<int>();
int _documentPayloadBytes(VenueLayoutDocument document) {
  final envelope = document._toJsonUnchecked(includeNodes: false);
  var bytes = utf8.encode(jsonEncode(envelope)).length;
  for (final node in document.nodes) {
    bytes += _encodedNodeBytes[node] ??= utf8
        .encode(jsonEncode(node.toJson()))
        .length;
  }
  // The empty nodes array already contributes its brackets to the envelope.
  return bytes + (document.nodes.isEmpty ? 0 : document.nodes.length - 1);
}

final _validationCache = Expando<List<LayoutIssue>>();
List<LayoutIssue> validateDocument(VenueLayoutDocument d) =>
    _validationCache[d] ??= List<LayoutIssue>.unmodifiable(
      _validateDocumentUncached(d),
    );
List<LayoutIssue> _validateDocumentUncached(VenueLayoutDocument d) {
  final out = <LayoutIssue>[];
  void issue(String r, String p, [String? id]) =>
      out.add(LayoutIssue(r, p, id));
  final index = <String, LayoutNode>{};
  if (d.nodes.length > layoutMaxNodes) issue('node_limit', 'nodes');
  if (d.nodes.where((n) => n.kind == 'seat').length > layoutMaxSeats)
    issue('seat_limit', 'nodes');
  for (final k in ['x', 'y', 'width', 'height']) {
    final v = d.canvas[k];
    if (v is! num ||
        !v.isFinite ||
        (k == 'width' || k == 'height') &&
            (v < layoutLimits['canvasMin']! || v > layoutLimits['canvasMax']!))
      issue('invalid_canvas', 'canvas.$k');
  }
  if (!layoutColorPattern.hasMatch('${d.canvas['fill']}'))
    issue('invalid_color', 'canvas.fill');
  for (final n in d.nodes) {
    if (!_uuid.hasMatch(n.id)) issue('invalid_uuid', 'nodes.id', n.id);
    if (index.containsKey(n.id)) issue('duplicate_id', 'nodes.id', n.id);
    index[n.id] = n;
    if (!const [
      'group',
      'table',
      'seat',
      'furniture',
      'capacityArea',
      'shape',
      'text',
    ].contains(n.kind))
      issue('unknown_kind', 'nodes.kind', n.id);
    if ([n.x, n.y, n.rotation, n.width, n.height].any((v) => !v.isFinite) ||
        n.width <= 0 ||
        n.height <= 0)
      issue('invalid_geometry', 'nodes.transform', n.id);
    final p = n.properties;
    if (p.keys.any(
      (k) => const [
        'id',
        'kind',
        'parentId',
        'transform',
        'width',
        'height',
        'z',
        'locked',
        'label',
      ].contains(k),
    ))
      issue('reserved_property', 'nodes.properties', n.id);
    if (p['shape'] != null &&
        !const [
          'rect',
          'rectangle',
          'roundedRect',
          'ellipse',
          'oval',
          'circle',
          'round',
          'polygon',
          'polyline',
          'line',
          'arrow',
        ].contains(p['shape']))
      issue('invalid_shape', 'nodes.shape', n.id);
    if (p['strokeWidth'] != null &&
        (p['strokeWidth'] is! num ||
            !(p['strokeWidth'] as num).isFinite ||
            (p['strokeWidth'] as num) < 0))
      issue('invalid_stroke', 'nodes.strokeWidth', n.id);
    if (p['arrowHeadLength'] != null &&
        (p['arrowHeadLength'] is! num ||
            !(p['arrowHeadLength'] as num).isFinite ||
            (p['arrowHeadLength'] as num) <= 0))
      issue('invalid_arrow_head_length', 'nodes.arrowHeadLength', n.id);
    if (p['dash'] != null &&
        (p['dash'] is! List ||
            (p['dash'] as List).any((v) => v is! num || !v.isFinite || v <= 0)))
      issue('invalid_dash', 'nodes.dash', n.id);
    if (p['labelOrientation'] != null &&
        !const ['screen', 'object'].contains(p['labelOrientation']))
      issue('invalid_label_orientation', 'nodes.labelOrientation', n.id);
    if (p['align'] != null &&
        !const ['left', 'center', 'right'].contains(p['align']))
      issue('invalid_alignment', 'nodes.align', n.id);

    for (final k in ['fill', 'stroke', 'color']) {
      if (p[k] != null && !layoutColorPattern.hasMatch('${p[k]}'))
        issue('invalid_color', 'nodes.$k', n.id);
    }
    if (p['opacity'] != null &&
        (p['opacity'] is! num ||
            (p['opacity'] as num) < 0 ||
            (p['opacity'] as num) > 1))
      issue('invalid_opacity', 'nodes.opacity', n.id);
    if (n.kind == 'text') {
      if ('${p['text'] ?? ''}'.runes.length >
          layoutLimits['textMaxCodePoints']!)
        issue('text_limit', 'nodes.text', n.id);
      final size = p['size'] ?? d.defaultTextStyle['size'] ?? 24,
          lh = p['lineHeight'] ?? 1.2;
      if (size is! num || !size.isFinite || size < 1 || size > 4096)
        issue('font_size', 'nodes.size', n.id);
      if (lh is! num || !lh.isFinite || lh < 0.8 || lh > 3)
        issue('line_height', 'nodes.lineHeight', n.id);
    }
    if (p.containsKey('pathPattern') ||
        p.containsKey('zigzagTeeth') ||
        p.containsKey('zigzagAmplitude')) {
      final teeth = p['zigzagTeeth'],
          amplitude = p['zigzagAmplitude'],
          vertices = p['points'];
      if (p['pathPattern'] != 'zigzag' ||
          n.kind != 'shape' ||
          p['shape'] != 'polyline' ||
          teeth is! int ||
          teeth < 1 ||
          2 * teeth + 2 > layoutLimits['verticesMax']! ||
          amplitude is! num ||
          !amplitude.isFinite ||
          amplitude <= 0 ||
          amplitude > layoutLimits['geometryAbsMax']! ||
          vertices is! List ||
          vertices.length != 2 * teeth + 2) {
        issue('invalid_zigzag', 'nodes.pathPattern', n.id);
      } else if (vertices.every(
        (v) =>
            v is List &&
            v.length == 2 &&
            v.every((c) => c is num && c.isFinite),
      )) {
        final a = vertices.first as List, b = vertices.last as List;
        final dx = (b[0] as num) - (a[0] as num),
            dy = (b[1] as num) - (a[1] as num);
        final length = sqrt(dx * dx + dy * dy);
        var regular = length >= 0.001;
        if (regular) {
          for (var i = 0; i < 2 * teeth; i++) {
            final t = (i + 0.5) / (2 * teeth),
                offset = i.isEven ? amplitude : -amplitude,
                point = vertices[i + 1] as List;
            if (((point[0] as num) - (a[0] + dx * t - dy / length * offset))
                        .abs() >
                    0.002 ||
                ((point[1] as num) - (a[1] + dy * t + dx / length * offset))
                        .abs() >
                    0.002) {
              regular = false;
              break;
            }
          }
        }
        if (!regular) issue('invalid_zigzag_geometry', 'nodes.points', n.id);
      }
    }
    final points = p['points'];
    if (points != null) {
      if (points is! List ||
          points.length > layoutLimits['verticesMax']! ||
          points.length < (p['shape'] == 'polygon' ? 3 : 2))
        issue('invalid_vertices', 'nodes.points', n.id);
      else if (points.any(
        (v) =>
            v is! List ||
            v.length != 2 ||
            v.any((x) => x is! num || !x.isFinite),
      ))
        issue('invalid_vertices', 'nodes.points', n.id);
      else if (p['shape'] == 'polygon' && polygonSelfIntersects(points))
        issue('self_intersection', 'nodes.points', n.id);
    }
  }
  for (final n in d.nodes) {
    var p = n;
    final seen = <String>{n.id};
    var depth = 1;
    while (p.parentId != null) {
      final parent = index[p.parentId];
      if (parent == null) {
        issue('missing_parent', 'nodes.parentId', n.id);
        break;
      }
      if (!seen.add(parent.id)) {
        issue('parent_cycle', 'nodes.parentId', n.id);
        break;
      }
      if (++depth > layoutMaxDepth) {
        issue('depth_limit', 'nodes.parentId', n.id);
        break;
      }
      p = parent;
    }
  }
  final members = <String>{};
  final unitIds = <String>{};
  for (final u in d.selectionUnits) {
    if (!_uuid.hasMatch('${u['id']}') || !unitIds.add('${u['id']}'))
      issue('invalid_unit_id', 'selectionUnits');
    final ids = u['nodeIds'];
    if (ids is! List || ids.isEmpty) {
      issue('empty_unit', 'selectionUnits');
      continue;
    }
    for (final id in ids) {
      if (index[id]?.kind != 'seat')
        issue('invalid_member', 'selectionUnits', id.toString());
      if (!members.add(id.toString()))
        issue('duplicate_membership', 'selectionUnits', id.toString());
    }
  }
  for (final a in d.attachments) {
    if (index[a['seatId']]?.kind != 'seat' ||
        index[a['targetId']] == null ||
        index[a['seatId']]?.parentId != a['targetId'])
      issue('invalid_attachment', 'attachments');
  }
  for (final s in d.sections) {
    if (index[s['rootId']]?.kind != 'group')
      issue('invalid_section_root', 'sections');
  }
  if (d.presets.length > layoutLimits['presetsMax']!)
    issue('preset_limit', 'presets');
  for (final p in d.presets) {
    final nodes = (p['document'] as Map?)?['nodes'] ?? p['nodes'];
    if (nodes is List && nodes.length > layoutLimits['presetNodesMax']!)
      issue('preset_node_limit', 'presets');
  }
  if (d.background case final Map<String, dynamic> b) {
    final opacity = b['opacity'] ?? 1;
    if (opacity is! num || !opacity.isFinite || opacity < 0 || opacity > 1)
      issue('invalid_opacity', 'background.opacity');
    final c = b['crop'];
    if (c is Map) {
      final x = c['x'] ?? 0,
          y = c['y'] ?? 0,
          w = c['width'] ?? 1,
          h = c['height'] ?? 1;
      if ([x, y, w, h].any((v) => v is! num || !v.isFinite) ||
          x < 0 ||
          y < 0 ||
          w <= 0 ||
          h <= 0 ||
          x + w > 1 ||
          y + h > 1)
        issue('invalid_crop', 'background.crop');
    }
  }
  _validateExtras(d, index, out);
  try {
    if (out.every(
          (i) => !const [
            'nonfinite_number',
            'invalid_geometry',
            'non_json_value',
          ].contains(i.reason),
        ) &&
        _documentPayloadBytes(d) > layoutMaxBytes)
      issue('payload_limit', 'document');
  } catch (_) {
    issue('non_json_value', 'document');
  }
  return out;
}

bool polygonSelfIntersects(List points) {
  double cross(List a, List b, List c) =>
      ((b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]))
          .toDouble();
  for (var i = 0; i < points.length; i++) {
    final a = points[i] as List, b = points[(i + 1) % points.length] as List;
    for (var j = i + 1; j < points.length; j++) {
      if (j == i + 1 || i == 0 && j == points.length - 1) continue;
      final c = points[j] as List, e = points[(j + 1) % points.length] as List;
      if (cross(a, b, c) * cross(a, b, e) <= 0 &&
          cross(c, e, a) * cross(c, e, b) <= 0) {
        final overlap =
            max(min(a[0], b[0]), min(c[0], e[0])) <=
                min(max(a[0], b[0]), max(c[0], e[0])) &&
            max(min(a[1], b[1]), min(c[1], e[1])) <=
                min(max(a[1], b[1]), max(c[1], e[1]));
        if (overlap) return true;
      }
    }
  }
  return false;
}

Map<String, dynamic> _canonicalMap(Map<String, dynamic> input) {
  dynamic canonical(dynamic v) {
    if (v is Map) {
      final keys = v.keys.cast<String>().toList()..sort();
      return <String, dynamic>{for (final k in keys) k: canonical(v[k])};
    }
    if (v is List) return v.map(canonical).toList();
    return v;
  }

  return canonical(input) as Map<String, dynamic>;
}

List<Map<String, dynamic>> _sortedRecords(
  List<Map<String, dynamic>> records, {
  String key = 'id',
}) => records.map((r) => _canonicalMap(r)).toList()
  ..sort((a, b) {
    final order = (a['order'] as num? ?? 0).compareTo(b['order'] as num? ?? 0);
    return order != 0 ? order : '${a[key]}'.compareTo('${b[key]}');
  });
const _geometryKeys = {
  'shape',
  'arrowHeadLength',
  'cornerRadius',
  'appearanceOverrides',
  'seatStyle',
  'seatWidth',
  'seatHeight',
  'seatGap',
  'seatSpacing',
  'seatEdgePadding',
  'objectStyle',
  'fill',
  'stroke',
  'strokeWidth',
  'strokeStyle',
  'dash',
  'opacity',
  'points',
  'holes',
  'pathPattern',
  'zigzagTeeth',
  'zigzagAmplitude',
  'text',
  'fontId',
  'labelOrientation',
  'fontStyle',
  'size',
  'color',
  'align',
  'lineHeight',
  'bold',
  'italic',
  'symbol',
  'role',
  'obstacle',
  'manual',
  'manualRotation',
  'slot',
  'assembly',
  'rows',
  'seatsPerRow',
  'blocks',
  'aisle',
  'spacing',
  'rowSpacing',
  'arc',
  'left',
  'right',
  'rear',
  'decks',
  'upperRows',
  'upperRear',
  'deck',
  'compartments',
  'seats',
  'capacity',
  'furniture',
  'guestSide',
};
const _nodeKinds = {
  'group',
  'table',
  'seat',
  'furniture',
  'capacityArea',
  'shape',
  'text',
};
const _documentKeys = {
  'appearance',
  'schemaVersion',
  'symbolSetVersion',
  'canvas',
  'defaultTextStyle',
  'nodes',
  'sections',
  'selectionUnits',
  'attachments',
  'generators',
  'background',
  'presets',
};
final _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');
const _privateKeys = {
  'spot',
  'spotid',
  'product',
  'productid',
  'price',
  'unitprice',
  'currency',
  'orderid',
  'ticket',
  'ticketid',
  'secret',
  'secretid',
  'token',
  'accesstoken',
  'refreshtoken',
  'customer',
  'customerid',
  'email',
  'payment',
  'paymentid',
  'reservation',
  'reservationid',
  'hold',
  'holdid',
  'selected',
  'pending',
  'status',
  'camera',
  'viewport',
};
bool _finite(dynamic v) => v is num && v.isFinite;
List<LayoutIssue> _jsonIssues(
  dynamic value, {
  String path = 'document',
  bool business = false,
}) {
  final issues = <LayoutIssue>[], active = Set<Object>.identity();
  var count = 0;
  void walk(dynamic v, String p, int depth) {
    if (depth > 64 || ++count > 1000000) {
      if (issues.length < 100) issues.add(LayoutIssue('json_nesting_limit', p));
      return;
    }
    if (v == null || v is bool || v is String) return;
    if (v is num) {
      if (!v.isFinite)
        issues.add(LayoutIssue('nonfinite_number', p));
      else if (v.abs() > 8796093022207)
        issues.add(LayoutIssue('unsafe_number', p));
      return;
    }
    if (v is! Map && v is! List) {
      issues.add(LayoutIssue('non_json_value', p));
      return;
    }
    if (!active.add(v as Object)) {
      issues.add(LayoutIssue('json_cycle', p));
      return;
    }
    if (v is Map) {
      for (final e in v.entries) {
        if (e.key is! String) {
          issues.add(LayoutIssue('non_string_key', p));
          continue;
        }
        final k = e.key as String;
        if (business &&
            _privateKeys.contains(
              k.toLowerCase().replaceAll(RegExp(r'[_-]'), ''),
            ))
          issues.add(LayoutIssue('host_data_forbidden', '$p.$k'));
        walk(e.value, '$p.$k', depth + 1);
      }
    } else {
      for (var i = 0; i < (v as List).length; i++) {
        walk(v[i], '$p[$i]', depth + 1);
      }
    }
    active.remove(v);
  }

  walk(value, path, 0);
  return issues;
}

List<LayoutIssue> _nodeDecodeIssues(Map<String, dynamic> j) {
  final issues = <LayoutIssue>[];
  void add(String r, String k) =>
      issues.add(LayoutIssue(r, k, j['id'] is String ? j['id'] : null));
  if (j['id'] is! String || !_uuid.hasMatch(j['id'])) add('invalid_uuid', 'id');
  if (j['kind'] is! String || !_nodeKinds.contains(j['kind']))
    add('unknown_kind', 'kind');
  if (j.containsKey('parentId') &&
      j['parentId'] != null &&
      (j['parentId'] is! String || !_uuid.hasMatch(j['parentId'])))
    add('invalid_parent_id', 'parentId');
  final t = j['transform'];
  if (t is! Map) {
    add('missing_transform', 'transform');
  } else {
    for (final k in ['x', 'y', 'rotation']) {
      if (!_finite(t[k])) add('invalid_transform', 'transform.$k');
    }
    if (t.keys.any((k) => !const ['x', 'y', 'rotation'].contains(k)))
      add('unknown_transform_field', 'transform');
  }
  for (final k in ['width', 'height']) {
    if (!_finite(j[k]) || j[k] <= 0) add('invalid_dimension', k);
  }
  if (j.containsKey('z') && j['z'] is! int) add('invalid_z', 'z');
  if (j.containsKey('locked') && j['locked'] is! bool)
    add('invalid_locked', 'locked');
  if (j.containsKey('label') && j['label'] is! String)
    add('invalid_label', 'label');
  if (j.keys.any((k) => const ['x', 'y', 'rotation'].contains(k)))
    add('flat_transform_forbidden', 'transform');
  return issues;
}

List<LayoutIssue> _documentDecodeIssues(Map<String, dynamic> j) {
  final issues = _jsonIssues(j, business: true);
  void add(String r, String p) => issues.add(LayoutIssue(r, p));
  if (j.keys.any((k) => !_documentKeys.contains(k)))
    add('unknown_document_field', 'document');
  if (j['symbolSetVersion'] != 1)
    add('unsupported_symbols', 'symbolSetVersion');
  if (j.containsKey('appearance') && j['appearance'] is! Map) {
    add('invalid_appearance', 'appearance');
  }
  if (j['canvas'] is! Map) add('missing_canvas', 'canvas');
  if (j['defaultTextStyle'] is! Map)
    add('missing_text_style', 'defaultTextStyle');
  if (j['nodes'] is! List) {
    add('missing_nodes', 'nodes');
  } else {
    for (var i = 0; i < (j['nodes'] as List).length; i++) {
      final node = j['nodes'][i];
      if (node is! Map) {
        add('invalid_node', 'nodes[$i]');
      } else {
        issues.addAll(
          _nodeDecodeIssues(
            Map<String, dynamic>.from(node),
          ).map((e) => LayoutIssue(e.reason, 'nodes[$i].${e.path}', e.nodeId)),
        );
      }
    }
  }
  for (final k in [
    'sections',
    'selectionUnits',
    'attachments',
    'generators',
    'presets',
  ]) {
    if (j.containsKey(k) &&
        (j[k] is! List || (j[k] as List).any((v) => v is! Map)))
      add('invalid_collection', k);
  }
  if (j['background'] != null && j['background'] is! Map)
    add('invalid_background', 'background');
  if (issues.isEmpty && utf8.encode(jsonEncode(j)).length > layoutMaxBytes)
    add('payload_limit', 'document');
  return issues;
}

void _validateExtras(
  VenueLayoutDocument d,
  Map<String, LayoutNode> nodes,
  List<LayoutIssue> out,
) {
  void issue(String r, String p, [String? id]) =>
      out.add(LayoutIssue(r, p, id));
  void fields(Map<String, dynamic> values, Set<String> allowed, String path) {
    for (final key in values.keys) {
      if (!allowed.contains(key)) issue('unknown_field', '$path.$key');
    }
  }

  for (final entry in d.appearance.entries) {
    final path = 'appearance.${entry.key}';
    if (!layoutAppearanceKinds.contains(entry.key)) {
      issue('unknown_appearance_kind', path);
    }
    if (entry.value is! Map) {
      issue('invalid_appearance', path);
      continue;
    }
    final styles = Map<String, dynamic>.from(entry.value as Map);
    for (final style in styles.entries) {
      if (!layoutAppearanceKeys.contains(style.key) ||
          (layoutSeatingDefaultKeys.contains(style.key) &&
              entry.key != 'table')) {
        issue('unknown_appearance_property', '$path.${style.key}');
      } else if (style.key == 'objectStyle') {
        if (!layoutObjectStyles.contains(style.value)) {
          issue('invalid_object_style', '$path.objectStyle');
        }
      } else if (style.key == 'seatStyle') {
        if (!layoutSeatStyles.contains(style.value)) {
          issue('invalid_seat_style', '$path.seatStyle');
        }
      } else if (const {'fill', 'stroke', 'color'}.contains(style.key)) {
        if (style.value is! String ||
            !layoutColorPattern.hasMatch(style.value)) {
          issue('invalid_color', '$path.${style.key}');
        }
      } else if (!_finite(style.value) ||
          style.value <
              (const {'seatWidth', 'seatHeight'}.contains(style.key) ? 1 : 0) ||
          style.value >
              (style.key == 'opacity'
                  ? 1
                  : layoutSeatingDefaultKeys.contains(style.key)
                  ? 1000000
                  : layoutLimits['geometryAbsMax']!)) {
        issue('invalid_appearance_value', '$path.${style.key}');
      }
    }
  }
  fields(d.canvas, const {
    'x',
    'y',
    'width',
    'height',
    'fill',
    'floorStyle',
  }, 'canvas');
  if (d.canvas.containsKey('floorStyle') &&
      !layoutFloorStyles.contains(d.canvas['floorStyle'])) {
    issue('invalid_floor_style', 'canvas.floorStyle');
  }
  fields(d.defaultTextStyle, const {
    'fontId',
    'size',
    'color',
    'align',
    'lineHeight',
    'bold',
    'italic',
    'fontStyle',
  }, 'defaultTextStyle');
  if (d.defaultTextStyle['fontStyle'] != null &&
      !const ['normal', 'italic'].contains(d.defaultTextStyle['fontStyle']))
    issue('invalid_font_style', 'defaultTextStyle.fontStyle');
  if (d.background != null) {
    fields(d.background!, const {
      'assetRef',
      'hash',
      'x',
      'y',
      'rotation',
      'width',
      'height',
      'scale',
      'opacity',
      'crop',
    }, 'background');
    if (d.background!['crop'] is Map)
      fields(Map<String, dynamic>.from(d.background!['crop']), const {
        'x',
        'y',
        'width',
        'height',
      }, 'background.crop');
  }
  final allIds = <String>{...nodes.keys};
  void identity(dynamic id, String path) {
    if (id is! String || !_uuid.hasMatch(id)) {
      issue('invalid_uuid', path);
      return;
    }
    if (!allIds.add(id)) issue('duplicate_identity', path, id);
  }

  bool polygon(dynamic points, String path) {
    if (points is! List ||
        points.length < 3 ||
        points.length > layoutLimits['verticesMax']! ||
        points.any(
          (v) => v is! List || v.length != 2 || v.any((x) => !_finite(x)),
        )) {
      issue('invalid_vertices', path);
      return false;
    }
    if (polygonSelfIntersects(points)) {
      issue('self_intersection', path);
      return false;
    }
    var area = 0.0;
    for (var i = 0; i < points.length; i++) {
      final a = points[i] as List, b = points[(i + 1) % points.length] as List;
      area += (a[0] as num) * (b[1] as num) - (a[1] as num) * (b[0] as num);
    }
    if (area.abs() < 1e-9) {
      issue('degenerate_polygon', path);
      return false;
    }
    return true;
  }

  for (final entry in d.canvas.entries) {
    if (const ['x', 'y', 'width', 'height'].contains(entry.key) &&
        _finite(entry.value) &&
        (entry.value as num).abs() > layoutLimits['geometryAbsMax']!)
      issue('coordinate_range', 'canvas.${entry.key}');
  }
  if (d.symbolSetVersion != 1) issue('unsupported_symbols', 'symbolSetVersion');
  out.addAll(
    _jsonIssues({
      'canvas': d.canvas,
      'defaultTextStyle': d.defaultTextStyle,
      'appearance': d.appearance,
      'sections': d.sections,
      'selectionUnits': d.selectionUnits,
      'attachments': d.attachments,
      'generators': d.generators,
      'background': d.background,
      'presets': d.presets,
      'nodeProperties': [for (final n in d.nodes) n.properties],
    }, business: true),
  );
  final style = d.defaultTextStyle;
  if (style['fontId'] is! String || (style['fontId'] as String).isEmpty)
    issue('invalid_font_id', 'defaultTextStyle.fontId');
  if (!_finite(style['size']) ||
      style['size'] < layoutLimits['fontSizeMin']! ||
      style['size'] > layoutLimits['fontSizeMax']!)
    issue('font_size', 'defaultTextStyle.size');
  if (style['color'] is! String || !layoutColorPattern.hasMatch(style['color']))
    issue('invalid_color', 'defaultTextStyle.color');
  if (style['lineHeight'] != null &&
      (!_finite(style['lineHeight']) ||
          style['lineHeight'] < layoutLimits['lineHeightMin']! ||
          style['lineHeight'] > layoutLimits['lineHeightMax']!))
    issue('line_height', 'defaultTextStyle.lineHeight');
  if (style['align'] != null &&
      !const ['left', 'center', 'right'].contains(style['align']))
    issue('invalid_alignment', 'defaultTextStyle.align');
  for (final k in ['bold', 'italic']) {
    if (style[k] != null && style[k] is! bool)
      issue('invalid_boolean', 'defaultTextStyle.$k');
  }
  for (final n in d.nodes) {
    final p = n.properties;
    if (p.containsKey('deck') &&
        (p['deck'] is! int || p['deck'] < 0 || p['deck'] > 1)) {
      issue('invalid_deck', 'nodes.deck', n.id);
    }
    if (p.containsKey('decks') &&
        (p['decks'] is! int || p['decks'] < 1 || p['decks'] > 2)) {
      issue('invalid_decks', 'nodes.decks', n.id);
    }
    if (p['assembly'] == 'bus' && p.containsKey('decks')) {
      for (final key in [
        'rows',
        'left',
        'right',
        'rear',
        'upperRows',
        'upperRear',
      ]) {
        if (p[key] is! int || p[key] < 0 || p[key] > layoutMaxSeats)
          issue('invalid_transport_count', 'nodes.$key', n.id);
      }
      if (p['left'] is int &&
          p['right'] is int &&
          (p['left'] > 3 || p['right'] > 3 || p['left'] + p['right'] == 0)) {
        issue('invalid_bus_blocks', 'nodes.left', n.id);
      }
      for (final key in ['rear', 'upperRear']) {
        if (p[key] is int && p[key] > 6)
          issue('invalid_transport_count', 'nodes.$key', n.id);
      }
    }
    if (p['assembly'] == 'compartments' &&
        (p.containsKey('compartments') || p.containsKey('seats'))) {
      if (p['compartments'] is! int ||
          p['compartments'] < 1 ||
          p['compartments'] > layoutMaxSeats ||
          p['seats'] is! int ||
          p['seats'] < 2 ||
          p['seats'] > 12) {
        issue('invalid_transport_count', 'nodes.compartments', n.id);
      }
    }
    if (p.containsKey('guestSide') &&
        (!isBarNode(n) || !barGuestSides.contains(p['guestSide']))) {
      issue('invalid_bar_guest_side', 'nodes.guestSide', n.id);
    }
    if (p['furniture'] == 'bar' &&
        (n.kind != 'table' ||
            !barGuestSides.contains(p['guestSide']) ||
            !const [
              'rect',
              'rectangle',
              'roundedRect',
              'polygon',
            ].contains(p['shape']))) {
      issue('invalid_bar', 'nodes.furniture', n.id);
    }
    if (p['furniture'] == 'stool' && n.kind != 'seat') {
      issue('invalid_stool', 'nodes.furniture', n.id);
    }
    final barParent = nodes[n.parentId];
    if (n.kind == 'seat' && barParent != null && isBarNode(barParent)) {
      final side = barParent.properties['guestSide'];
      final guest = switch (side) {
        'top' => n.y <= -barParent.height / 2,
        'bottom' => n.y >= barParent.height / 2,
        'left' => n.x <= -barParent.width / 2,
        'right' => n.x >= barParent.width / 2,
        _ => false,
      };
      if (!guest) issue('bar_stool_wrong_side', 'nodes.parentId', n.id);
    }
    if (p.containsKey('objectStyle') &&
        !layoutObjectStyles.contains(p['objectStyle'])) {
      issue('invalid_object_style', 'nodes.objectStyle', n.id);
    }
    if (p.containsKey('seatStyle') &&
        !layoutSeatStyles.contains(p['seatStyle'])) {
      issue('invalid_seat_style', 'nodes.seatStyle', n.id);
    }
    if (p.containsKey('appearanceOverrides')) {
      final overrides = p['appearanceOverrides'];
      if (overrides is! List ||
          overrides.any(
            (key) => key is! String || !layoutAppearanceKeys.contains(key),
          ) ||
          overrides.toSet().length != overrides.length) {
        issue(
          'invalid_appearance_overrides',
          'nodes.appearanceOverrides',
          n.id,
        );
      }
    }
    for (final key in p.keys) {
      if (!_geometryKeys.contains(key))
        issue('unknown_geometry_property', 'nodes.$key', n.id);
    }
    if ([
      n.x,
      n.y,
      n.rotation,
      n.width,
      n.height,
    ].any((v) => v.isFinite && v.abs() > layoutLimits['geometryAbsMax']!))
      issue('coordinate_range', 'nodes.geometry', n.id);
    if (p['points'] is List &&
        (p['points'] as List).any(
          (p) =>
              p is List &&
              p.any(
                (v) =>
                    _finite(v) &&
                    (v as num).abs() > layoutLimits['geometryAbsMax']!,
              ),
        ))
      issue('coordinate_range', 'nodes.points', n.id);
    if (p['symbol'] != null &&
        !const [
          'chair',
          'bench',
          'sofa',
          'wheelchair',
          'driver',
        ].contains(p['symbol']))
      issue('unknown_symbol', 'nodes.symbol', n.id);
    if (n.parentId != null && !_uuid.hasMatch(n.parentId!))
      issue('invalid_parent_id', 'nodes.parentId', n.id);
    if (n.parentId != null &&
        nodes[n.parentId] != null &&
        !const [
          'group',
          'table',
          'furniture',
        ].contains(nodes[n.parentId]!.kind))
      issue('invalid_parent_kind', 'nodes.parentId', n.id);
    if (p['text'] != null && p['text'] is! String)
      issue('invalid_text', 'nodes.text', n.id);
    if (n.kind == 'text' && p['text'] == null)
      issue('missing_text', 'nodes.text', n.id);
    if (p['fontId'] != null &&
        (p['fontId'] is! String || (p['fontId'] as String).isEmpty))
      issue('invalid_font_id', 'nodes.fontId', n.id);
    for (final key in [
      'bold',
      'italic',
      'manual',
      'manualRotation',
      'obstacle',
    ]) {
      if (p[key] != null && p[key] is! bool)
        issue('invalid_boolean', 'nodes.$key', n.id);
    }
    for (final key in ['size', 'lineHeight']) {
      if (p[key] != null &&
          (!_finite(p[key]) ||
              p[key] <
                  (key == 'size'
                      ? layoutLimits['fontSizeMin']!
                      : layoutLimits['lineHeightMin']!) ||
              p[key] >
                  (key == 'size'
                      ? layoutLimits['fontSizeMax']!
                      : layoutLimits['lineHeightMax']!)))
        issue(key == 'size' ? 'font_size' : 'line_height', 'nodes.$key', n.id);
    }
    for (final key in [
      'seatWidth',
      'seatHeight',
      'seatGap',
      'seatSpacing',
      'seatEdgePadding',
    ]) {
      if (p[key] != null &&
          (!_finite(p[key]) ||
              p[key] < (key == 'seatWidth' || key == 'seatHeight' ? 1 : 0) ||
              p[key] > 1000000))
        issue('invalid_table_seating', 'nodes.$key', n.id);
    }
    if (p['cornerRadius'] != null &&
        (!_finite(p['cornerRadius']) || p['cornerRadius'] < 0))
      issue('invalid_radius', 'nodes.cornerRadius', n.id);
    if (p['labelOrientation'] != null &&
        !const ['screen', 'object'].contains(p['labelOrientation']))
      issue('invalid_label_orientation', 'nodes.labelOrientation', n.id);
    if (p['fontStyle'] != null &&
        !const ['normal', 'italic'].contains(p['fontStyle']))
      issue('invalid_font_style', 'nodes.fontStyle', n.id);
    if (p['capacity'] != null && (p['capacity'] is! int || p['capacity'] < 0))
      issue('invalid_capacity', 'nodes.capacity', n.id);
    if (p['strokeStyle'] != null &&
        !const ['solid', 'dashed', 'dotted'].contains(p['strokeStyle']))
      issue('invalid_stroke_style', 'nodes.strokeStyle', n.id);
    if (p.containsKey('holes')) {
      final holes = p['holes'];
      if (p['shape'] != 'polygon' || holes is! List || holes.length > 128) {
        issue('invalid_holes', 'nodes.holes', n.id);
      } else {
        var vertices = p['points'] is List ? (p['points'] as List).length : 0;
        final validHoles = <List<List<double>>>[];
        for (final hole in holes) {
          if (polygon(hole, 'nodes.${n.id}.holes')) {
            final ring = (hole as List)
                .map(
                  (p) => (p as List).map((n) => (n as num).toDouble()).toList(),
                )
                .toList();
            vertices += ring.length;
            validHoles.add(ring);
          }
        }
        if (vertices > layoutLimits['verticesMax']!)
          issue('vertex_limit', 'nodes.holes', n.id);
        else if (p['points'] is List &&
            polygon(p['points'], 'nodes.${n.id}.points')) {
          final outer = (p['points'] as List)
              .map(
                (p) => (p as List).map((n) => (n as num).toDouble()).toList(),
              )
              .toList();
          for (var i = 0; i < validHoles.length; i++) {
            final h = validHoles[i];
            if (polygonRingArea(h) * polygonRingArea(outer) >= 0 ||
                !h.every((p) => polygonRingContains(outer, p[0], p[1])) ||
                polygonRingsTouch(outer, h))
              issue('invalid_hole', 'nodes.holes', n.id);
            for (var j = 0; j < i; j++) {
              final other = validHoles[j];
              if (polygonRingsTouch(h, other) ||
                  polygonRingContains(h, other[0][0], other[0][1]) ||
                  polygonRingContains(other, h[0][0], h[0][1]))
                issue('overlapping_holes', 'nodes.holes', n.id);
            }
          }
        }
      }
    }
    if (p['shape'] == 'polygon' && p['points'] == null)
      issue('missing_vertices', 'nodes.points', n.id);
    if (p['shape'] == 'polygon' &&
        p['points'] is List &&
        polygon(p['points'], 'nodes.${n.id}.points')) {}
  }
  for (final u in d.selectionUnits) {
    identity(u['id'], 'selectionUnits.id');
    if (u.keys.any(
      (k) => !const ['id', 'nodeIds', 'kind', 'label'].contains(k),
    ))
      issue('unknown_selection_unit_field', 'selectionUnits');
    if (u['kind'] != 'atomic')
      issue('invalid_selection_unit_kind', 'selectionUnits.kind');
  }
  final seats = <String>{};
  for (final a in d.attachments) {
    if (a.keys.any(
      (k) => !const [
        'id',
        'seatId',
        'targetId',
        'kind',
        'edge',
        't',
        'gap',
        'x',
        'y',
        'rotation',
        'manual',
        'offset',
      ].contains(k),
    ))
      issue('unknown_attachment_field', 'attachments');
    if (a['id'] != null) identity(a['id'], 'attachments.id');
    if (a['seatId'] is! String || !seats.add('${a['seatId']}'))
      issue('duplicate_attachment', 'attachments.seatId');
    if (nodes[a['targetId']]?.kind != 'table')
      issue('invalid_attachment_target', 'attachments.targetId');
    if (!const ['edge', 'perimeter'].contains(a['kind']))
      issue('invalid_attachment_kind', 'attachments.kind');
    if (!_finite(a['t']) || a['t'] < 0 || a['t'] > 1)
      issue('invalid_attachment_t', 'attachments.t');
    if (!_finite(a['gap']) || a['gap'] < 0)
      issue('invalid_attachment_gap', 'attachments.gap');
    if (a['kind'] == 'edge' &&
        !const ['top', 'right', 'bottom', 'left'].contains(a['edge']))
      issue('invalid_attachment_edge', 'attachments.edge');
  }
  final sectionRoots = <String>{};
  for (final s in d.sections) {
    identity(s['id'], 'sections.id');
    if (s['title'] is! String || (s['title'] as String).isEmpty)
      issue('invalid_section_title', 'sections.title');
    if (!sectionRoots.add('${s['rootId']}'))
      issue('duplicate_section_root', 'sections.rootId');
    if (s.keys.any(
      (k) => !const [
        'id',
        'title',
        'rootId',
        'levelId',
        'outline',
        'order',
      ].contains(k),
    ))
      issue('unknown_section_field', 'sections');
    if (s['outline'] != null) polygon(s['outline'], 'sections.outline');
    if (s['order'] != null && s['order'] is! int)
      issue('invalid_order', 'sections.order');
    if (s['levelId'] != null && s['levelId'] is! String)
      issue('invalid_level', 'sections.levelId');
  }
  final assemblyRoots = <String>{};
  for (final g in d.generators) {
    identity(g['id'], 'generators.id');
    fields(g, const {
      'id',
      'kind',
      'rootId',
      'assemblyId',
      'nodeIds',
      'parameters',
      'version',
    }, 'generators');
    if (g.containsKey('rootId') &&
        g.containsKey('assemblyId') &&
        g['rootId'] != g['assemblyId'])
      issue('conflicting_generator_root', 'generators.rootId');
    if (g['version'] != null && g['version'] != 1)
      issue('unsupported_generator_version', 'generators.version');
    final params = g['parameters'];
    if (params != null) {
      if (params is! Map) {
        issue('invalid_generator_parameters', 'generators.parameters');
      } else {
        fields(Map<String, dynamic>.from(params), const {
          'rows',
          'seatsPerRow',
          'blocks',
          'aisle',
          'spacing',
          'rowSpacing',
          'x',
          'y',
          'arc',
          'left',
          'right',
          'rear',
          'compartments',
          'seats',
          'shape',
          'count',
          'width',
          'height',
          'gap',
        }, 'generators.parameters');
        for (final e in params.entries) {
          if (e.key == 'shape') {
            if (!const [
              'rect',
              'rectangle',
              'roundedRect',
              'ellipse',
              'oval',
              'circle',
              'round',
            ].contains(e.value))
              issue('invalid_shape', 'generators.parameters.shape');
          } else if (!_finite(e.value) ||
              (e.value as num).abs() > layoutLimits['geometryAbsMax']!) {
            issue(
              'invalid_generator_parameter',
              'generators.parameters.${e.key}',
            );
          } else if (const [
                'rows',
                'seatsPerRow',
                'blocks',
                'left',
                'right',
                'rear',
                'compartments',
                'seats',
                'count',
              ].contains(e.key) &&
              (e.value is! int || e.value < 0)) {
            issue('invalid_generator_count', 'generators.parameters.${e.key}');
          } else if (const [
                'spacing',
                'rowSpacing',
                'width',
                'height',
              ].contains(e.key) &&
              e.value <= 0) {
            issue(
              'invalid_generator_parameter',
              'generators.parameters.${e.key}',
            );
          }
        }
      }
    }
    final root = g['rootId'] ?? g['assemblyId'];
    if (root is! String ||
        nodes[root]?.kind != (g['kind'] == 'table' ? 'table' : 'group') ||
        !assemblyRoots.add(root))
      issue('invalid_generator_root', 'generators.rootId');
    if (!const [
      'rows',
      'row',
      'arc',
      'bus',
      'compartments',
      'table',
    ].contains(g['kind']))
      issue('invalid_generator_kind', 'generators.kind');
    if (g['nodeIds'] is List &&
        (g['nodeIds'] as List).toSet().length != (g['nodeIds'] as List).length)
      issue('duplicate_generator_member', 'generators.nodeIds');
    if (g['nodeIds'] != null &&
        (g['nodeIds'] is! List ||
            (g['nodeIds'] as List).any(
              (id) => id is! String || !nodes.containsKey(id),
            )))
      issue('invalid_generator_nodes', 'generators.nodeIds');
  }
  for (final p in d.presets) {
    identity(p['id'], 'presets.id');
    if (p.keys.any(
      (k) => !const [
        'id',
        'title',
        'description',
        'document',
        'version',
      ].contains(k),
    ))
      issue('unknown_preset_field', 'presets');
    if (p['title'] is! String || (p['title'] as String).isEmpty)
      issue('invalid_preset_title', 'presets.title');
    final fragment = p['document'];
    if (fragment is! Map<String, dynamic>) {
      issue('invalid_preset_document', 'presets.document');
      continue;
    }
    if (fragment['presets'] is List &&
        (fragment['presets'] as List).isNotEmpty) {
      issue('nested_preset_forbidden', 'presets.document.presets');
      continue;
    }
    try {
      VenueLayoutDocument.fromJson(fragment);
    } on InvalidLayoutDocument catch (e) {
      out.addAll(
        e.issues.map(
          (i) =>
              LayoutIssue(i.reason, 'presets.${p['id']}.${i.path}', i.nodeId),
        ),
      );
    } catch (_) {
      issue('invalid_preset_document', 'presets.document');
    }
  }
  if (d.background case final Map<String, dynamic> b) {
    for (final key in ['x', 'y', 'rotation', 'width', 'height', 'scale']) {
      if (!_finite(b[key]) ||
          const ['width', 'height', 'scale'].contains(key) && b[key] <= 0)
        issue('invalid_background_transform', 'background.$key');
    }
    final ref = b['assetRef'];
    if (ref is! String ||
        !RegExp(r'^[A-Za-z0-9][A-Za-z0-9:._-]{0,255}$').hasMatch(ref) ||
        ref.contains('..'))
      issue('invalid_asset_ref', 'background.assetRef');
    final hash =
        b['hash'] ??
        (ref is String && ref.startsWith('image:') ? ref.substring(6) : null);
    if (hash is! String || !_sha256Pattern.hasMatch(hash))
      issue('invalid_asset_hash', 'background.hash');
    if (b['crop'] is! Map) {
      issue('invalid_crop', 'background.crop');
    } else {
      for (final k in ['x', 'y', 'width', 'height']) {
        if (!_finite(b['crop'][k])) issue('invalid_crop', 'background.crop.$k');
      }
    }
    for (final k in ['x', 'y', 'rotation', 'width', 'height', 'scale']) {
      if (_finite(b[k]) &&
          (b[k] as num).abs() > layoutLimits['geometryAbsMax']!)
        issue('coordinate_range', 'background.$k');
    }
  }
}

/// Validate font outline snapshots at import/provider boundaries, never per frame.
List<LayoutIssue> validateLayoutResources(Map<String, dynamic> resources) {
  final serializable = Map<String, dynamic>.from(resources)..remove('images');
  final out = _jsonIssues(serializable, path: 'resources');
  void issue(String r, String p) => out.add(LayoutIssue(r, p));
  if (resources.isEmpty) return out;
  if (resources['protocol'] != 1)
    issue('unsupported_resource_protocol', 'resources.protocol');
  final fonts = resources['fonts'];
  if (fonts == null) return out;
  if (fonts is! Map) {
    issue('invalid_fonts', 'resources.fonts');
    return out;
  }
  for (final entry in fonts.entries) {
    final id = entry.key, font = entry.value, path = 'resources.fonts.$id';
    if (id is! String || id.isEmpty || id.length > 256 || font is! Map) {
      issue('invalid_font', path);
      continue;
    }
    if (font['id'] != id) issue('font_id_mismatch', '$path.id');
    if (font['hash'] is! String || !_sha256Pattern.hasMatch(font['hash']))
      issue('invalid_font_hash', '$path.hash');
    if (!_finite(font['unitsPerEm']) ||
        font['unitsPerEm'] <= 0 ||
        font['unitsPerEm'] > 1000000)
      issue('invalid_font_metrics', '$path.unitsPerEm');
    if (!_finite(font['ascent']) ||
        font['ascent'] <= 0 ||
        !_finite(font['descent']) ||
        font['descent'] > 0)
      issue('invalid_font_metrics', path);
    final glyphs = font['glyphs'];
    if (glyphs is! Map || glyphs.length > 65536) {
      issue('invalid_glyph_map', '$path.glyphs');
      continue;
    }
    for (final glyphEntry in glyphs.entries) {
      final char = glyphEntry.key,
          glyph = glyphEntry.value,
          gpath = '$path.glyphs.$char';
      if (char is! String || char.runes.length != 1 || glyph is! Map) {
        issue('invalid_glyph', gpath);
        continue;
      }
      if (!_finite(glyph['advance']) || glyph['advance'] < 0)
        issue('invalid_advance', '$gpath.advance');
      final commands = glyph['path'];
      if (commands is! List || commands.length > 65536) {
        issue('invalid_glyph_path', '$gpath.path');
        continue;
      }
      var open = false;
      for (var i = 0; i < commands.length; i++) {
        final c = commands[i];
        if (c is! List || c.isEmpty || c.first is! String) {
          issue('invalid_path_command', '$gpath.path[$i]');
          continue;
        }
        final arity = const {'M': 3, 'L': 3, 'C': 7, 'Q': 5, 'Z': 1}[c.first];
        if (arity == null ||
            c.length != arity ||
            c
                .skip(1)
                .any(
                  (v) =>
                      !_finite(v) ||
                      (v as num).abs() > layoutLimits['geometryAbsMax']!,
                )) {
          issue('invalid_path_command', '$gpath.path[$i]');
          continue;
        }
        if (c.first == 'M') {
          open = true;
        } else if (!open) {
          issue('path_missing_move', '$gpath.path[$i]');
        }
        if (c.first == 'Z') open = false;
      }
    }
  }
  return out;
}

const layoutAppearanceKinds = <String>{
  'table',
  'seat',
  'furniture',
  'shape',
  'capacityArea',
  'text',
};
const layoutSeatStyles = <String>{
  'roundUpholstered',
  'round',
  'plain',
  'wood',
  'upholstered',
  'transit',
  'banquet',
};
const layoutObjectStyles = <String>{
  'round',
  'simple',
  'minimal',
  'wood',
  'lounge',
  'transit',
  'hall',
  'banquet',
};

/// Physical authoring defaults; never override an existing table's geometry.
const layoutSeatingDefaultKeys = <String>{
  'seatWidth',
  'seatHeight',
  'seatGap',
  'seatSpacing',
  'seatEdgePadding',
};

const layoutAppearanceKeys = <String>{
  ...layoutSeatingDefaultKeys,
  'objectStyle',
  'seatStyle',
  'fill',
  'stroke',
  'strokeWidth',
  'cornerRadius',
  'opacity',
  'color',
};

/// Document styles replace factory defaults unless a property is explicitly
/// marked local. Geometry and host presentation state are never merged here.
Map<String, dynamic> effectiveNodeProperties(
  VenueLayoutDocument document,
  LayoutNode node,
) {
  final global = document.appearance[node.kind];
  final open = const [
    'line',
    'polyline',
    'arrow',
  ].contains(node.properties['shape']);
  if ((global is! Map || global.isEmpty) && !open) return node.properties;
  final result = <String, dynamic>{
    ...node.properties,
    if (global is Map) ...Map<String, dynamic>.from(global),
  };
  // Authoring defaults are materialized by configurePlanTableSeating. Local
  // physical profiles remain authoritative, including locked assemblies.
  if (node.kind == 'table') {
    for (final key in layoutSeatingDefaultKeys) {
      if (node.properties.containsKey(key)) {
        result[key] = node.properties[key];
      } else {
        result.remove(key);
      }
    }
  }
  for (final key
      in node.properties['appearanceOverrides'] as List? ?? const []) {
    if (node.properties.containsKey(key))
      result[key as String] = node.properties[key];
  }
  // Open divider geometry has no surface, regardless of the shared shape fill.
  if (const ['line', 'polyline', 'arrow'].contains(result['shape'])) {
    result['fill'] = '#00000000';
  }
  return frozenMap(result);
}

/// Structural comparison for validated immutable nodes. Unchanged nodes are an
/// identity check; coordinate comparisons retain canonical serialization's
/// quantization and appearance override order has no semantic significance.
bool sameLayoutNode(LayoutNode a, LayoutNode b) {
  if (identical(a, b)) return true;
  if (a.id != b.id ||
      a.kind != b.kind ||
      a.parentId != b.parentId ||
      a.label != b.label ||
      a.z != b.z ||
      a.locked != b.locked ||
      quantize(a.x) != quantize(b.x) ||
      quantize(a.y) != quantize(b.y) ||
      quantize(a.rotation) != quantize(b.rotation) ||
      quantize(a.width) != quantize(b.width) ||
      quantize(a.height) != quantize(b.height))
    return false;
  if (identical(a.properties, b.properties)) return true;
  if (a.properties.length != b.properties.length) return false;
  for (final entry in a.properties.entries) {
    if (!b.properties.containsKey(entry.key)) return false;
    final other = b.properties[entry.key];
    if (entry.key == 'appearanceOverrides' &&
        entry.value is List &&
        other is List) {
      final keys = (entry.value as List).toSet();
      if (keys.length != other.length || !keys.containsAll(other)) return false;
    } else if (!sameLayoutValue(entry.value, other))
      return false;
  }
  return true;
}

/// Fast comparison of validated immutable snapshots. Pointer updates usually
/// replace only a few nodes, so no JSON or full property graph is allocated.
/// Rare record/list reorderings retain the canonical serializer as the oracle.
bool sameLayoutDocument(VenueLayoutDocument a, VenueLayoutDocument b) {
  if (identical(a, b)) return true;
  if (a.symbolSetVersion != b.symbolSetVersion ||
      a.nodes.length != b.nodes.length)
    return false;
  for (var i = 0; i < a.nodes.length; i++) {
    if (a.nodes[i].id != b.nodes[i].id) {
      return jsonEncode(a.toJson()) == jsonEncode(b.toJson());
    }
    if (!sameLayoutNode(a.nodes[i], b.nodes[i])) return false;
  }
  if (!sameLayoutValue(a.canvas, b.canvas) ||
      !sameLayoutValue(a.defaultTextStyle, b.defaultTextStyle) ||
      !sameLayoutValue(a.appearance, b.appearance) ||
      !sameLayoutValue(a.background, b.background))
    return false;
  if (sameLayoutValue(a.sections, b.sections) &&
      sameLayoutValue(a.selectionUnits, b.selectionUnits) &&
      sameLayoutValue(a.attachments, b.attachments) &&
      sameLayoutValue(a.generators, b.generators) &&
      sameLayoutValue(a.presets, b.presets))
    return true;
  return jsonEncode(a.toJson()) == jsonEncode(b.toJson());
}

/// Deep JSON-value equality without serialization; maps ignore key order,
/// lists preserve order and equal numeric values compare equally.
bool sameLayoutValue(dynamic a, dynamic b) {
  if (identical(a, b) || a == b) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !sameLayoutValue(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!sameLayoutValue(a[i], b[i])) return false;
    }
    return true;
  }
  return false;
}

const barGuestSides = <String>{'top', 'right', 'bottom', 'left'};
bool isBarNode(LayoutNode node) =>
    node.kind == 'table' && node.properties['furniture'] == 'bar';
bool isStoolNode(LayoutNode node, {LayoutNode? parent}) =>
    node.kind == 'seat' &&
    (node.properties['furniture'] == 'stool' ||
        parent != null && isBarNode(parent));

const layoutFloorStyles = <String>{'plain', 'wood', 'tile', 'carpet'};

/// Ring geometry shared by authoring validation and spatial hit testing.
double polygonRingArea(List<List<double>> ring) {
  var area = 0.0;
  for (var i = 0; i < ring.length; i++) {
    final a = ring[i], b = ring[(i + 1) % ring.length];
    area += a[0] * b[1] - b[0] * a[1];
  }
  return area / 2;
}

bool polygonRingContains(List<List<double>> points, double x, double y) {
  var inside = false;
  for (var i = 0, j = points.length - 1; i < points.length; j = i++) {
    final a = points[i], b = points[j];
    if ((a[1] > y) != (b[1] > y) &&
        x < (b[0] - a[0]) * (y - a[1]) / (b[1] - a[1]) + a[0])
      inside = !inside;
  }
  return inside;
}

bool polygonRingsTouch(List<List<double>> a, List<List<double>> b) {
  double cross(List<double> a, List<double> b, List<double> c) =>
      (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]);
  for (var i = 0; i < a.length; i++)
    for (var j = 0; j < b.length; j++) {
      final p = a[i],
          q = a[(i + 1) % a.length],
          r = b[j],
          s = b[(j + 1) % b.length];
      if (max(p[0], q[0]) < min(r[0], s[0]) ||
          max(r[0], s[0]) < min(p[0], q[0]) ||
          max(p[1], q[1]) < min(r[1], s[1]) ||
          max(r[1], s[1]) < min(p[1], q[1]))
        continue;
      if (cross(p, q, r) * cross(p, q, s) <= 0 &&
          cross(r, s, p) * cross(r, s, q) <= 0)
        return true;
    }
  return false;
}
