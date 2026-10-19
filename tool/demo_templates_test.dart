import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

void main() {
  test(
    'all package templates validate with fresh identities and exact capacity',
    () {
      expect(VenueLayoutTemplates.all.length, 14);
      for (final template in VenueLayoutTemplates.all) {
        final a = template.create(), b = template.create();
        expect(validateDocument(a), isEmpty, reason: template.id);
        expect(
          a.nodes.where((n) => n.kind == 'seat').length,
          template.seatCount,
          reason: template.id,
        );
        expect(
          a.nodes
              .where((n) => n.kind == 'capacityArea')
              .fold<int>(
                0,
                (sum, n) => sum + (n.properties['capacity'] as int),
              ),
          template.standingCapacity,
        );
        expect(
          a.nodes
              .map((n) => n.id)
              .toSet()
              .intersection(b.nodes.map((n) => n.id).toSet()),
          isEmpty,
        );
        expect(jsonEncode(a.toJson()), isNot(contains('price')));
        final clone = cloneLayout(a);
        expect(
          validateDocument(clone),
          isEmpty,
          reason: 'clone ${template.id}',
        );
        expect(
          clone.nodes
              .map((n) => n.id)
              .toSet()
              .intersection(a.nodes.map((n) => n.id).toSet()),
          isEmpty,
        );
      }
    },
  );
}
