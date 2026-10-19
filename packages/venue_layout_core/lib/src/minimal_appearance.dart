/// Existing V1 visual vocabulary, expressed through ordinary V2 appearance.
const layoutMinimalAppearance = <String, Map<String, dynamic>>{
  'table': {
    'objectStyle': 'minimal',
    'fill': '#FFFFFFFF',
    'stroke': '#000000FF',
    'strokeWidth': 1,
    'cornerRadius': 0,
    'color': '#000000FF',
  },
  'seat': {
    'objectStyle': 'minimal',
    'seatStyle': 'plain',
    'fill': '#267329FF',
    'stroke': '#00000000',
    'strokeWidth': 0,
    'cornerRadius': 8,
  },
  'shape': {'objectStyle': 'minimal', 'strokeWidth': 1, 'cornerRadius': 0},
  'furniture': {
    'objectStyle': 'minimal',
    'fill': '#FFFFFFFF',
    'stroke': '#000000FF',
    'strokeWidth': 1,
    'cornerRadius': 0,
  },
  'capacityArea': {
    'objectStyle': 'minimal',
    'strokeWidth': 1,
    'cornerRadius': 0,
  },
  'text': {'objectStyle': 'minimal', 'color': '#000000FF'},
};
const layoutSelectedSeatFill = '#267329FF';
// V1 normal marker: 40 - 2*(2.5*1.8); selected marker: 40 - 2*.8.
const layoutSelectedSeatScale = 38.4 / 31.0;
