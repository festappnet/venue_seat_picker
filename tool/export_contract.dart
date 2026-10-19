import 'dart:convert';
import 'dart:io';
import 'package:venue_layout_core/venue_layout_core.dart';

void main() {
  final schemaFile = File('doc/layout-v1.schema.json');
  final schema =
      jsonDecode(schemaFile.readAsStringSync()) as Map<String, dynamic>;
  final properties = schema['properties'] as Map;
  properties['nodes']['maxItems'] = layoutLimits['maxNodes'];
  properties['presets']['maxItems'] = layoutLimits['presetsMax'];
  final selectionUnit = properties['selectionUnits']['items'] as Map;
  selectionUnit['additionalProperties'] = false;
  selectionUnit['properties']['kind'] = {
    'enum': ['atomic', null],
    'default': 'atomic',
    '\$comment':
        'Omitted or null v1 kind is normalized to atomic by the core model.',
  };
  selectionUnit['properties']['label'] = {'type': 'string'};

  for (final side in ['width', 'height']) {
    properties['canvas']['properties'][side]['minimum'] =
        layoutLimits['canvasMin'];
    properties['canvas']['properties'][side]['maximum'] =
        layoutLimits['canvasMax'];
  }
  final bound = layoutLimits['geometryAbsMax']!;
  properties['canvas']['properties']['floorStyle'] = {
    'type': 'string',
    'enum': layoutFloorStyles.toList(),
  };

  schema['\$comment'] =
      'Scalar structural schema. The public core validator additionally enforces identity/reference consistency, closed authoring keys, JSON nesting and resource/host boundaries.';
  final definitions = schema['\$defs'] as Map;
  definitions['appearanceStyle'] = {
    'type': 'object',
    'additionalProperties': false,
    'properties': {
      for (final key in layoutAppearanceKeys)
        key: key == 'objectStyle'
            ? {'type': 'string', 'enum': layoutObjectStyles.toList()}
            : key == 'seatStyle'
            ? {'type': 'string', 'enum': layoutSeatStyles.toList()}
            : const {'fill', 'stroke', 'color'}.contains(key)
            ? {'\$ref': '#/\$defs/color'}
            : {
                'type': 'number',
                'minimum': const {'seatWidth', 'seatHeight'}.contains(key)
                    ? 1
                    : 0,
                'maximum': key == 'opacity'
                    ? 1
                    : layoutSeatingDefaultKeys.contains(key)
                    ? 1000000
                    : bound,
              },
    },
  };
  properties['appearance'] = {
    'type': 'object',
    'additionalProperties': false,
    'properties': {
      for (final kind in layoutAppearanceKinds)
        kind: {'\$ref': '#/\$defs/appearanceStyle'},
    },
  };
  for (final key in ['deck', 'decks', 'upperRows', 'upperRear']) {
    definitions['node']['properties'][key] = {
      'type': 'integer',
      'minimum': key == 'decks' ? 1 : 0,
      'maximum': key == 'deck'
          ? 1
          : key == 'decks'
          ? 2
          : key == 'upperRear'
          ? 6
          : layoutMaxSeats,
    };
  }
  definitions['node']['properties']['guestSide'] = {
    'type': 'string',
    'enum': barGuestSides.toList(),
  };
  definitions['node']['allOf'] = [
    {
      'if': {
        'required': ['furniture'],
        'properties': {
          'furniture': {'const': 'bar'},
        },
      },
      'then': {
        'required': ['guestSide', 'shape'],
        'properties': {
          'kind': {'const': 'table'},
          'shape': {
            'enum': ['rect', 'rectangle', 'roundedRect', 'polygon'],
          },
        },
      },
    },
    {
      'if': {
        'required': ['guestSide'],
      },
      'then': {
        'required': ['furniture'],
        'properties': {
          'furniture': {'const': 'bar'},
        },
      },
    },
  ];
  definitions['node']['properties']['holes'] = {
    'type': 'array',
    'maxItems': 128,
    'items': {
      'type': 'array',
      'minItems': 3,
      'maxItems': 512,
      'items': {
        'type': 'array',
        'minItems': 2,
        'maxItems': 2,
        'items': {'type': 'number'},
      },
    },
  };
  definitions['node']['properties']['objectStyle'] = {
    'type': 'string',
    'enum': layoutObjectStyles.toList(),
  };
  for (final key in [
    'seatWidth',
    'seatHeight',
    'seatGap',
    'seatSpacing',
    'seatEdgePadding',
  ]) {
    definitions['node']['properties'][key] = {
      'type': 'number',
      'minimum': key == 'seatWidth' || key == 'seatHeight' ? 1 : 0,
      'maximum': 1000000,
    };
  }
  definitions['node']['properties']['labelOrientation'] = {
    'type': 'string',
    'enum': ['screen', 'object'],
    'default': 'screen',
  };
  definitions['node']['properties']['seatStyle'] = {
    'type': 'string',
    'enum': layoutSeatStyles.toList(),
  };
  definitions['node']['properties']['appearanceOverrides'] = {
    'type': 'array',
    'uniqueItems': true,
    'maxItems': layoutAppearanceKeys.length,
    'items': {'type': 'string', 'enum': layoutAppearanceKeys.toList()},
  };

  for (final coordinate in ['x', 'y', 'rotation']) {
    definitions['node']['properties']['transform']['properties'][coordinate] = {
      'type': 'number',
      'minimum': -bound,
      'maximum': bound,
    };
  }
  for (final dimension in ['width', 'height']) {
    definitions['node']['properties'][dimension]['maximum'] = bound;
  }
  for (final coordinate in ['x', 'y']) {
    properties['canvas']['properties'][coordinate] = {
      'type': 'number',
      'minimum': -bound,
      'maximum': bound,
    };
  }
  schemaFile.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(schema)}\n',
  );
  Directory('web/dist').createSync(recursive: true);
  File('web/dist/contract.json').writeAsStringSync(
    '${jsonEncode({'protocol': layoutProtocol, 'limits': layoutLimits})}\n',
  );
  stdout.writeln('Contract schema and distribution limits generated from core');
}
