import 'package:flutter/material.dart';

import '../../../core/value_objects.dart';
import '../../../shared/presentation/common.dart';
import '../application/order_draft.dart';
import '../domain/catalog.dart';

class GarmentEditor extends StatelessWidget {
  final GarmentDraft draft;
  final int number;
  final VoidCallback changed, remove;
  final Future<void> Function()? copyPrevious;
  const GarmentEditor({
    super.key,
    required this.draft,
    required this.number,
    required this.changed,
    required this.remove,
    this.copyPrevious,
  });
  Future<void> changeConfiguration(
    BuildContext context,
    MeasurementConfiguration next, {
    GarmentType? newType,
  }) async {
    if (draft.removedFields(next).isNotEmpty &&
        !await confirm(
          context,
          'Clear disabled measurements?',
          'The disabled section contains measurements. Continuing clears those draft values.',
          action: 'Clear section',
        )) {
      if (!context.mounted) return;
      draft.revision++;
      changed();
      return;
    }
    if (!context.mounted) return;
    draft.setConfiguration(next);
    if (newType != null) {
      draft.type = newType;
      draft.variant = newType.variants.keys.firstOrNull;
    }
    changed();
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Garment $number',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'Remove garment',
                onPressed: remove,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          DropdownButtonFormField<GarmentType>(
            key: ValueKey('${draft.id}:${draft.revision}:type'),
            initialValue: draft.type,
            isExpanded: true,
            decoration: inputLabel('Garment type'),
            items: GarmentType.values
                .map(
                  (type) =>
                      DropdownMenuItem(value: type, child: Text(type.label)),
                )
                .toList(),
            onChanged: (type) {
              if (type != null) {
                changeConfiguration(
                  context,
                  type.defaultConfiguration,
                  newType: type,
                );
              }
            },
          ),
          if (draft.type.variants.isNotEmpty) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              isExpanded: true,
              key: ValueKey('${draft.id}:${draft.revision}:variant'),
              initialValue: draft.variant,
              decoration: inputLabel('Variant'),
              items: draft.type.variants.entries
                  .map(
                    (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                  )
                  .toList(),
              onChanged: (v) {
                draft.variant = v;
                changed();
              },
            ),
          ],
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey('${draft.id}:quantity'),
                  initialValue: draft.quantity,
                  decoration: inputLabel('Quantity'),
                  keyboardType: TextInputType.number,
                  onChanged: (v) {
                    draft.quantity = v;
                    changed();
                  },
                  validator: (v) {
                    final n = int.tryParse(v ?? '');
                    return n == null || n < 1 || n > 10000
                        ? 'Whole number 1–10000'
                        : null;
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  key: ValueKey('${draft.id}:rate'),
                  initialValue: draft.rate,
                  decoration: inputLabel('Rate (₹)'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (v) {
                    draft.rate = v;
                    changed();
                  },
                  validator: (v) {
                    try {
                      Money.parse(v ?? '');
                      return null;
                    } catch (_) {
                      return 'Valid amount required';
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: draft.description,
            decoration: inputLabel('Cut / description (optional)'),
            maxLines: 2,
            onChanged: (v) {
              draft.description = v;
              changed();
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<MeasurementConfiguration>(
            isExpanded: true,
            key: ValueKey('${draft.id}:${draft.revision}:configuration'),
            initialValue: draft.configuration,
            decoration: inputLabel('Measurement sections'),
            items: const [
              DropdownMenuItem(
                value: MeasurementConfiguration.upper,
                child: Text('Upper body'),
              ),
              DropdownMenuItem(
                value: MeasurementConfiguration.lower,
                child: Text('Lower body'),
              ),
              DropdownMenuItem(
                value: MeasurementConfiguration.both,
                child: Text('Both upper and lower'),
              ),
              DropdownMenuItem(
                value: MeasurementConfiguration.none,
                child: Text('No standard measurements'),
              ),
            ],
            onChanged: (next) {
              if (next != null) changeConfiguration(context, next);
            },
          ),
          if (copyPrevious != null)
            TextButton.icon(
              onPressed: copyPrevious,
              icon: const Icon(Icons.history),
              label: const Text('Copy saved measurements'),
            ),
          if (draft.configuration == MeasurementConfiguration.none)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Enter size or special details in the notes below.'),
            ),
          for (final upper in [true, false])
            if (fieldsFor(draft.configuration)
                .any((f) => f.startsWith(upper ? 'upper_' : 'lower_'))) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  upper
                      ? 'Upper body · inches (optional)'
                      : 'Lower body · inches (optional)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              for (final field in upper ? upperFields : lowerFields)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextFormField(
                    key: ValueKey('${draft.id}:${draft.revision}:$field'),
                    initialValue: draft.measurements[field] ?? '',
                    decoration: inputLabel(
                      field
                          .split('_')
                          .last
                          .replaceFirstMapped(
                            RegExp(r'^.'),
                            (m) => m[0]!.toUpperCase(),
                          ),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (v) {
                      draft.measurements[field] = v;
                      changed();
                    },
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      try {
                        MeasurementSnapshot(draft.configuration, {
                          field: v.trim(),
                        });
                        return null;
                      } catch (_) {
                        return 'Positive inches, up to 3 decimals';
                      }
                    },
                  ),
                ),
            ],
          const SizedBox(height: 8),
          TextFormField(
            key: ValueKey('${draft.id}:${draft.revision}:notes'),
            initialValue: draft.fittingNotes,
            decoration: inputLabel('Fitting / size / stitching notes'),
            minLines: 3,
            maxLines: 6,
            onChanged: (v) {
              draft.fittingNotes = v;
              changed();
            },
          ),
        ],
      ),
    ),
  );
}
