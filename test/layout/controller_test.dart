import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

class _Host implements LayoutHistoryParticipant {
  int value = 0;
  @override
  Object capture() => value;
  @override
  void restore(Object? checkpoint) {
    value = checkpoint as int;
  }
}

class _Fonts implements LayoutFontProvider {
  final waits = <String, Completer<Map<String, dynamic>>>{};
  @override
  List<Map<String, dynamic>> get catalog => [];
  @override
  Future<Map<String, dynamic>> resolve(String id) =>
      (waits[id] = Completer()).future;
}

void main() {
  test('gestures keep fixed canvas and cancel restores draft', () {
    final doc = tableLayout(shape: 'roundedRect', count: 6);
    final c = VenueLayoutController(doc);
    final root = doc.nodes.first;
    c.select({root.id});
    c.beginGesture();
    expect(
      c.preview(transformNodes(doc, {root.id}, dx: -900, dy: -700)),
      false,
    );
    expect(c.document.canvas, doc.canvas);
    expect(
      c.placementIssues.any((issue) => issue.code == 'outside_canvas'),
      false,
    );
    c.preview(doc);
    expect(c.document.canvas['x'], doc.canvas['x']);
    expect(c.preview(transformNodes(doc, {root.id}, dx: 3000)), false);
    c.cancelGesture();
    expect(c.document.toJson(), doc.toJson());
    expect(c.canUndo, false);
    c.dispose();
  });
  test('keyboard movement clamps and new oversize/outside changes reject', () {
    final seat = LayoutNode(
      id: newLayoutId(),
      kind: 'seat',
      x: 50,
      y: 50,
      width: 20,
      height: 20,
    );
    final doc = VenueLayoutDocument.empty().copyWith(
      canvas: {
        'x': 0,
        'y': 0,
        'width': 100,
        'height': 100,
        'fill': '#FFFFFFFF',
      },
      nodes: [seat],
    );
    final c = VenueLayoutController(doc)..select({seat.id});
    c.moveSelection(-1000, 1000);
    expect(c.document.nodes.single.x, closeTo(10, .02));
    expect(c.document.nodes.single.y, closeTo(90, .02));
    expect(c.placementIssues, isEmpty);
    final bounded = c.document;
    c.updateNode(c.document.nodes.single.copyWith(width: 200));
    expect(c.document.toJson(), bounded.toJson());
    expect(c.error, contains('inside the canvas'));
    c.insert(VenueLayoutDocument(nodes: [seat.copyWith(x: 500)]));
    expect(c.document.nodes, hasLength(1));
    c.undo();
    expect(c.document.toJson(), doc.toJson());
    c.dispose();
  });
  test('wall reflow and fixed canvas join the same move undo transaction', () {
    final doc = tableLayout(shape: 'roundedRect', count: 6).copyWith(
      canvas: {
        'x': 0,
        'y': 0,
        'width': 800,
        'height': 600,
        'fill': '#FFFFFFFF',
      },
    );
    final table = doc.nodes.firstWhere((n) => n.kind == 'table');
    final seatIds = doc.nodes
        .where((n) => n.kind == 'seat')
        .map((n) => n.id)
        .toSet();
    final c = VenueLayoutController(doc)..select({table.id});
    c.beginGesture();
    expect(c.preview(transformNodes(doc, {table.id}, dx: -300)), true);
    expect(c.document.canvas, doc.canvas);
    expect(
      c.document.nodes.where((n) => n.kind == 'seat').map((n) => n.id).toSet(),
      seatIds,
    );
    expect(
      c.placementIssues.where((issue) => issue.code == 'outside_canvas'),
      isEmpty,
    );
    c.commitGesture();
    c.undo();
    expect(c.document.toJson(), doc.toJson());
    expect(c.canUndo, false);
    c.dispose();
  });
  test(
    'geometry and host draft share undo and baseline; selection is session only',
    () {
      final doc = tableLayout(shape: 'roundedRect', count: 6);
      final c = VenueLayoutController(doc), host = _Host();
      c.addHistoryParticipant(host);
      c.select({doc.nodes.first.id});
      expect(c.dirty, false);
      c.beginGesture();
      host.value = 500;
      c.moveSelection(32, 0);
      c.commitGesture();
      final moved = c.document.toJson();
      expect(c.dirty, true);
      c.undo();
      expect(host.value, 0);
      expect(c.document.toJson(), doc.toJson());
      c.redo();
      expect(host.value, 500);
      expect(c.document.toJson(), moved);
      c.markSaved();
      expect(c.dirty, false);
      expect(c.canUndo, false);
      c.beginGesture();
      host.value = 700;
      c.commitGesture();
      expect(c.dirty, true);
      c.undo();
      expect(host.value, 500);
      c.dispose();
    },
  );
  test(
    'locked descendant blocks whole table command and invalid draft stays intact',
    () {
      var doc = tableLayout(shape: 'roundedRect', count: 6);
      final seat = doc.nodes.firstWhere((n) => n.kind == 'seat');
      doc = doc.copyWith(
        nodes: doc.nodes
            .map((n) => n.id == seat.id ? n.copyWith(locked: true) : n)
            .toList(),
      );
      final c = VenueLayoutController(doc);
      c.select({doc.nodes.first.id});
      c.moveSelection(100, 0);
      expect(c.document.toJson(), doc.toJson());
      expect(c.error, isNotNull);
      expect(c.canUndo, false);
      c.dispose();
    },
  );
  test('late font and resource failure never commit stale result', () async {
    final provider = _Fonts(), resolver = LayoutFontResolver();
    String selected = 'previous';
    final a = resolver.select(
      'A',
      provider,
      (r) => selected = r['id'] as String,
    );
    final b = resolver.select(
      'B',
      provider,
      (r) => selected = r['id'] as String,
    );
    provider.waits['B']!.complete({'id': 'B', 'hash': 'b', 'glyphs': {}});
    expect(await b, true);
    provider.waits['A']!.complete({'id': 'A', 'hash': 'a', 'glyphs': {}});
    expect(await a, false);
    expect(selected, 'B');
    final bad = resolver.select('bad', provider, (r) => selected = 'bad');
    provider.waits['bad']!.completeError(StateError('unavailable'));
    await expectLater(bad, throwsStateError);
    expect(selected, 'B');
  });
  test('all templates are standalone public API with fresh identities', () {
    expect(VenueLayoutTemplates.all.length, 14);
    for (final t in VenueLayoutTemplates.all) {
      final a = t.create(), b = t.create();
      expect(validateDocument(a), isEmpty, reason: t.id);
      expect(a.nodes.where((n) => n.kind == 'seat').length, t.seatCount);
      expect(
        a.nodes
            .map((n) => n.id)
            .toSet()
            .intersection(b.nodes.map((n) => n.id).toSet()),
        isEmpty,
      );
    }
  });
  test('partial deletion never dissolves an indivisible selection unit', () {
    final doc = VenueLayoutTemplates.create('lounge');
    final unit = doc.selectionUnits.first;
    final c = VenueLayoutController(doc);
    c.select({(unit['nodeIds'] as List).first as String});
    c.deleteSelection();
    expect(c.document.toJson(), doc.toJson());
    expect(c.error, contains('entire shared object'));
    c.select((unit['nodeIds'] as List).cast<String>().toSet());
    c.deleteSelection();
    expect(c.document.nodes.length, doc.nodes.length - 2);
    expect(c.document.selectionUnits.length, doc.selectionUnits.length - 1);
    c.undo();
    expect(c.document.toJson(), doc.toJson());
    c.dispose();
  });
  test('recovered autosave retains a separate confirmed baseline', () {
    final baseline = tableLayout(shape: 'roundedRect', count: 6);
    final draft = transformNodes(baseline, {baseline.nodes.first.id}, dx: 100);
    final host = _Host()..value = 500;
    final c = VenueLayoutController(draft)..addHistoryParticipant(host);
    c.setSavedBaseline(baseline, participantCheckpoints: [0]);
    expect(c.document.toJson(), draft.toJson());
    expect(c.dirty, true);
    c.markSaved();
    expect(c.dirty, false);
    c.dispose();
  });
  test(
    'layer rank normalization preserves locked content and logical order',
    () {
      final a = LayoutNode(
        id: newLayoutId(),
        kind: 'shape',
        z: 0,
        x: 100,
        y: 100,
      );
      final locked = LayoutNode(
        id: newLayoutId(),
        kind: 'shape',
        z: 40,
        x: 200,
        y: 100,
        locked: true,
      );
      final other = LayoutNode(
        id: newLayoutId(),
        kind: 'shape',
        z: 80,
        x: 300,
        y: 100,
      );
      final doc = VenueLayoutDocument(nodes: [a, locked, other]);
      final c = VenueLayoutController(doc)..select({a.id});
      final applied = c.apply(reorderNodes(doc, {a.id}, 1));
      expect(applied, true, reason: c.error);
      expect(orderedNodes(c.document).map((n) => n.id), [
        locked.id,
        a.id,
        other.id,
      ]);
      final fixed = c.document.nodes.firstWhere((n) => n.id == locked.id);
      expect({...fixed.toJson(), 'z': 0}, {...locked.toJson(), 'z': 0});
      final before = c.document;
      c.updateNode(fixed.copyWith(z: 999));
      expect(c.document.toJson(), before.toJson());
      expect(c.error, contains('Locked object'));
      c.dispose();
    },
  );
  test(
    'overlapping drafts move continuously; invalid references still reject',
    () {
      final a = LayoutNode(id: newLayoutId(), kind: 'seat', x: 100, y: 100);
      final b = LayoutNode(id: newLayoutId(), kind: 'seat', x: 180, y: 100);
      final doc = VenueLayoutDocument(nodes: [a, b]);
      final c = VenueLayoutController(doc);
      c.select({a.id});
      c.moveSelection(60, 0);
      expect(c.document.nodes.first.x, 160);
      expect(c.error, isNull);
      expect(c.canUndo, true);
      final issues = c.showPlacementWarnings();
      expect(issues.any((issue) => issue.code == 'overlap'), true);
      expect(c.placementWarningIds, containsAll([a.id, b.id]));
      final overlapping = c.document;
      final invalid = doc.copyWith(
        nodes: [
          a.copyWith(parentId: newLayoutId()),
          b,
        ],
      );
      expect(c.apply(invalid), false);
      expect(c.document.toJson(), overlapping.toJson());
      c.undo();
      expect(c.document.toJson(), doc.toJson());
      expect(() => VenueLayoutController(invalid), throwsFormatException);
      c.dispose();
    },
  );
  test(
    'resource snapshots are immutable and failed replacement preserves valid data',
    () {
      final resource = <String, dynamic>{
        'protocol': 1,
        'fonts': {
          'fixture:sans': {
            'id': 'fixture:sans',
            'hash': List.filled(64, 'a').join(),
            'unitsPerEm': 1000,
            'ascent': 800,
            'descent': -200,
            'glyphs': {
              'A': {
                'advance': 500,
                'path': [
                  ['M', 0, 0],
                  ['L', 10, 10],
                ],
              },
            },
          },
        },
      };
      final c = VenueLayoutController(
        VenueLayoutDocument.empty(),
        resources: resource,
      );
      resource['fonts']['fixture:sans']['glyphs']['A']['advance'] = 999;
      expect(
        c.resources['fonts']['fixture:sans']['glyphs']['A']['advance'],
        500,
      );
      final before = c.resources;
      expect(c.setResources({'protocol': 99, 'fonts': {}}), false);
      expect(identical(c.resources, before), true);
      expect(c.error, isNotNull);
      c.dispose();
    },
  );
}
