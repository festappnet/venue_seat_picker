import 'package:flutter/material.dart';
import 'package:venue_layout_core/venue_layout_core.dart';
import '../venue_layout_controller.dart';
import 'layout_appearance_preview.dart';
import 'layout_strings.dart';

/// Shape/material families are independent of the plan's color palette.
class LayoutAppearanceFamily {
  const LayoutAppearanceFamily(this.id, this.title, this.description);
  final String id, title, description;
  Map<String, dynamic> get material => layoutMaterialFamilies[id]!;
  String get floorStyle => material['floorStyle'] as String;
  String get seatStyle => material['seatStyle'] as String;
  Map<String, Map<String, dynamic>> get patches => layoutMaterialAppearance(id);
}

const layoutAppearanceFamilies = [
  LayoutAppearanceFamily(
    'minimal',
    'Minimal',
    'Original seat markers and simple table outlines.',
  ),
  LayoutAppearanceFamily(
    'wood',
    'Timber',
    'Wooden frames, shaped seats and crafted tables.',
  ),
  LayoutAppearanceFamily(
    'lounge',
    'Lounge',
    'Soft armchairs, padded seating and rounded furniture.',
  ),
  LayoutAppearanceFamily(
    'round',
    'Round seating',
    'Circular seat markers and simple table outlines.',
  ),
  LayoutAppearanceFamily(
    'banquet',
    'Banquet hall',
    'Tapered banquet chairs, bowed backs and timber tables.',
  ),
  LayoutAppearanceFamily(
    'transit',
    'Transport',
    'Contoured seats, headrests and armrests.',
  ),
];

/// One immutable snapshot, one history command. Controller validation remains
/// the authority; no repeated full-document validation for individual kinds.
VenueLayoutDocument withAppearanceFamily(
  VenueLayoutDocument document,
  LayoutAppearanceFamily family, {
  bool? roundSeats,
}) {
  final next = withLayoutMaterialFamily(document, family.id);
  final current = (document.appearance['seat'] as Map?)?['seatStyle'];
  if (family.id != 'lounge' ||
      !(roundSeats ?? const ['round', 'roundUpholstered'].contains(current))) {
    return next;
  }
  return setLayoutAppearance(next, 'seat', {'seatStyle': 'roundUpholstered'});
}

class LayoutAppearanceFamilies extends StatelessWidget {
  const LayoutAppearanceFamilies({
    super.key,
    required this.controller,
    required this.onApply,
  });
  final VenueLayoutController controller;
  final ValueChanged<LayoutAppearanceFamily> onApply;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final family in layoutAppearanceFamilies)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Builder(
            builder: (context) {
              final roundLounge =
                  (controller.document.appearance['seat']
                      as Map?)?['seatStyle'] ==
                  'roundUpholstered';
              final selected =
                  layoutAppearanceKinds.every(
                    (kind) =>
                        ((controller.document.appearance[kind]
                                as Map?)?['objectStyle'] ??
                            'simple') ==
                        family.id,
                  ) &&
                  ((controller.document.appearance['seat']
                              as Map?)?['seatStyle'] ??
                          'plain') ==
                      (family.id == 'lounge' && roundLounge
                          ? 'roundUpholstered'
                          : family.seatStyle);
              return Semantics(
                selected: selected,
                child: OutlinedButton(
                  key: ValueKey('appearance-family-${family.id}'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.all(10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    side: BorderSide(
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outlineVariant,
                      width: selected ? 2 : 1,
                    ),
                  ),
                  onPressed: controller.readOnly || controller.saving
                      ? null
                      : () => onApply(family),
                  child: Row(
                    children: [
                      LayoutAppearancePreview(
                        controller: controller,
                        kind: family.id == 'transit'
                            ? 'transport'
                            : 'collection',
                        appearance: {
                          ...family.patches,
                          if (family.id == 'lounge' && roundLounge)
                            'seat': {
                              ...family.patches['seat']!,
                              'seatStyle': 'roundUpholstered',
                            },
                        },
                        floorStyle: family.floorStyle,
                        width: 170,
                        height: 100,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: LayoutText(
                                    family.title,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ),
                                if (selected)
                                  Icon(
                                    Icons.check_circle,
                                    size: 18,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            LayoutText(
                              family.description,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            if (family.id == 'lounge') ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                children: [
                                  for (final round in [false, true])
                                    ChoiceChip(
                                      key: ValueKey('lounge-seat-$round'),
                                      label: LayoutText(
                                        round ? 'Round' : 'Soft corners',
                                      ),
                                      selected:
                                          selected && round == roundLounge,
                                      onSelected:
                                          controller.readOnly ||
                                              controller.saving
                                          ? null
                                          : (_) => controller.apply(
                                              withAppearanceFamily(
                                                controller.document,
                                                family,
                                                roundSeats: round,
                                              ),
                                              label: 'Plan style',
                                            ),
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
    ],
  );
}
