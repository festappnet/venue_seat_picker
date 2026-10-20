import 'dart:convert';
import 'dart:js_interop';
import 'package:venue_layout_core/venue_layout_core.dart' as core;

@JS('VenueLayoutKernel')
external set _kernel(JSObject value);

@JSExport()
class VenueLayoutKernel {
  int get protocol => core.layoutProtocol;
  int get documentVersion => core.canonicalDocumentVersion;
  int get resourceProtocol => core.canonicalTextResourceProtocol;
  final _documents = <String, core.VenueLayoutDocument>{};
  final _resources = <String, Map<String, dynamic>>{};
  final _indices = <String, core.LayoutSpatialIndex>{};
  core.VenueLayoutDocument _document(String json) {
    if (_documents.containsKey(json)) return _documents[json]!;
    if (_documents.length >= 3) {
      final key = _documents.keys.first;
      _documents.remove(key);
      _indices.remove(key);
    }
    return _documents[json] = core.VenueLayoutDocument.fromJson(
      Map<String, dynamic>.from(jsonDecode(json)),
    );
  }

  Map<String, dynamic> _resource(String json) {
    if (_resources.containsKey(json)) return _resources[json]!;
    if (_resources.length >= 2) _resources.remove(_resources.keys.first);
    final parsed = Map<String, dynamic>.from(jsonDecode(json)),
        issues = core.validateLayoutResources(parsed);
    if (issues.isNotEmpty) {
      throw FormatException(issues.map((i) => i.toString()).join('; '));
    }
    return _resources[json] = core.freeze(parsed) as Map<String, dynamic>;
  }

  String decode(String json) => jsonEncode(_document(json).toJson());
  String validate(String json) {
    try {
      return jsonEncode(
        core.validateDocument(_document(json)).map((i) => i.toJson()).toList(),
      );
    } catch (e) {
      return jsonEncode([
        {'reason': e.toString(), 'path': 'document'},
      ]);
    }
  }

  String validateResources(String json) {
    try {
      return jsonEncode(
        core
            .validateLayoutResources(
              Map<String, dynamic>.from(jsonDecode(json)),
            )
            .map((i) => i.toJson())
            .toList(),
      );
    } catch (e) {
      return jsonEncode([
        {'reason': e.toString(), 'path': 'resources'},
      ]);
    }
  }

  String compileScene(
    String json,
    String resourcesJson,
    String presentationJson,
  ) => jsonEncode(
    core.compileScene(
      _document(json),
      resources: _resource(resourcesJson),
      presentation: Map<String, dynamic>.from(jsonDecode(presentationJson)),
    ),
  );
  String compileSceneNodes(
    String json,
    String idsJson,
    String resourcesJson,
    String presentationJson,
  ) => jsonEncode(
    core.compileSceneNodes(
      _document(json),
      (jsonDecode(idsJson) as List).cast<String>().toSet(),
      resources: _resource(resourcesJson),
      presentation: Map<String, dynamic>.from(jsonDecode(presentationJson)),
    ),
  );
  String? hitTest(String json, double x, double y) =>
      (_indices[json] ??= core.LayoutSpatialIndex(
        _document(json),
      )).hitTest(x, y);
  String? nearestNode(String json, String id, String direction) =>
      core.nearestNode(_document(json), id, direction);
  String interpolate(String fromJson, String toJson, double t) => jsonEncode(
    core.interpolateLayout(_document(fromJson), _document(toJson), t).toJson(),
  );
}

void main() {
  _kernel = createJSInteropWrapper(VenueLayoutKernel());
}
