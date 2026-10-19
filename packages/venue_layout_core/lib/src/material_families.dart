import 'model.dart';
import 'minimal_appearance.dart';
export 'minimal_appearance.dart';

/// One material definition shared by templates, previews and authoring UI.
const layoutMaterialFamilies = <String, Map<String, dynamic>>{
  'minimal': {
    'construction': 'simple',
    'seatStyle': 'plain',
    'floorStyle': 'plain',
    'radius': 0.0,
    'seatRadius': 8.0,
    'strokeWidth': 1.0,
    'seatStrokeWidth': 0.0,
  },
  'round': {
    'construction': 'simple',
    'seatStyle': 'round',
    'floorStyle': 'plain',
    'radius': 6.0,
    'strokeWidth': 1.0,
    'seatStrokeWidth': 1.0,
  },
  'simple': {
    'seatStyle': 'plain',
    'floorStyle': 'tile',
    'radius': 6.0,
    'strokeWidth': 1.0,
  },
  'wood': {
    'seatStyle': 'wood',
    'floorStyle': 'wood',
    'radius': 4.0,
    'strokeWidth': 1.2,
  },
  'lounge': {
    'seatStyle': 'upholstered',
    'floorStyle': 'carpet',
    'radius': 18.0,
    'strokeWidth': 1.2,
  },
  'hall': {
    'construction': 'wood',
    'seatStyle': 'wood',
    'floorStyle': 'plain',
    'radius': 14.0,
    'strokeWidth': 2.2,
  },
  'banquet': {
    'construction': 'wood',
    'seatStyle': 'banquet',
    'floorStyle': 'plain',
    'radius': 10.0,
    'strokeWidth': 1.8,
  },
  'transit': {
    'seatStyle': 'transit',
    'floorStyle': 'plain',
    'radius': 8.0,
    'strokeWidth': 1.2,
  },
};
Map<String, Map<String, dynamic>> layoutMaterialAppearance(String family) {
  final style = layoutMaterialFamilies[family];
  if (style == null) throw ArgumentError('Unknown material family');
  return {
    for (final kind in layoutAppearanceKinds)
      kind: {
        'objectStyle': family,
        'opacity': 1,
        if (kind != 'text') ...{
          'strokeWidth': kind == 'seat'
              ? style['seatStrokeWidth'] ?? style['strokeWidth']
              : style['strokeWidth'],
          'cornerRadius': kind == 'seat'
              ? style['seatRadius'] ?? style['radius']
              : style['radius'],
        },
        if (kind == 'seat') 'seatStyle': style['seatStyle'],
      },
  };
}

VenueLayoutDocument withLayoutMaterialFamily(
  VenueLayoutDocument document,
  String family,
) => document.copyWith(
  canvas: {
    ...document.canvas,
    'floorStyle':
        layoutMaterialFamilies[family]?['floorStyle'] ??
        (throw ArgumentError('Unknown material family')),
  },
  appearance: {
    ...document.appearance,
    for (final e in layoutMaterialAppearance(family).entries)
      e.key: {...?document.appearance[e.key] as Map?, ...e.value},
  },
);

VenueLayoutDocument withLayoutMinimalStyle(VenueLayoutDocument document) =>
    document.copyWith(
      canvas: {...document.canvas, 'fill': '#FFFFFFFF', 'floorStyle': 'plain'},
      appearance: {
        ...document.appearance,
        for (final e in layoutMinimalAppearance.entries)
          e.key: {...?document.appearance[e.key] as Map?, ...e.value},
      },
    );
