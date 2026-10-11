import 'dart:convert';

import '../../../core/value_objects.dart';
import 'workbook.dart';
import 'workbook_validation.dart';

const businessSheets = [
  'Customers',
  'Orders',
  'OrderItems',
  'Measurements',
  'Payments',
  'ShopSettings',
];

final class WorkbookImportPolicy {
  ImportPreview evaluate(WorkbookData workbook, WorkbookData local) {
    final localMaps = {
      for (final name in businessSheets)
        name: {for (final row in local.rows(name)) row.key: row},
    };
    final errors = validateWorkbook(
      workbook,
      localMaps['Customers']!.keys.toSet(),
    );
    final newCounts = <String, int>{};
    final existingCounts = <String, int>{};
    // Malformed typed rows cannot enter canonical comparison/reference logic.
    if (errors.isNotEmpty) {
      return ImportPreview(
        workbook: workbook,
        errors: errors,
        duplicateWarnings: [],
        newCounts: _safeCounts(workbook, localMaps, existing: false),
        existingCounts: _safeCounts(workbook, localMaps, existing: true),
        settingsDiffer: false,
        reviewSignature: _signature(local),
      );
    }
    final bills = {
      for (final row in local.rows('Orders'))
        billKey(row.text('bill_number')): row.key,
    };
    var settingsDiffer = false;
    for (final name in businessSheets) {
      var added = 0;
      var existing = 0;
      for (final row in workbook.rows(name)) {
        final previous = localMaps[name]![row.key];
        if (previous != null) {
          existing++;
          if (previous.canonical != row.canonical) {
            if (name == 'ShopSettings') {
              settingsDiffer = true;
            } else {
              errors.add(
                WorkbookIssue(
                  name,
                  row.line,
                  'id',
                  'Existing ID has different persisted content. Import is add-only; resolve this record before retrying.',
                ),
              );
            }
          }
        } else {
          added++;
          if (name == 'Orders' &&
              bills.containsKey(billKey(row.text('bill_number')))) {
            errors.add(
              WorkbookIssue(
                name,
                row.line,
                'bill_number',
                'Bill number already belongs to a different local order.',
              ),
            );
          }
        }
      }
      newCounts[name] = added;
      existingCounts[name] = existing;
    }
    // A supplied existing order is a complete aggregate. Missing or added
    // children must never silently erase history or augment an existing bill.
    final incomingAggregates = _aggregates(workbook);
    final localAggregates = _aggregates(local);
    for (final row in workbook.rows('Orders')) {
      if (!localMaps['Orders']!.containsKey(row.key)) continue;
      if (incomingAggregates[row.key] != localAggregates[row.key]) {
        errors.add(
          WorkbookIssue(
            'Orders',
            row.line,
            'items/payments/measurements',
            'Existing bill differs in its complete garment, measurement or payment history. Include all original rows unchanged.',
          ),
        );
      }
    }
    final duplicates = _duplicates(workbook, local);
    return ImportPreview(
      workbook: workbook,
      errors: errors,
      duplicateWarnings: duplicates,
      newCounts: newCounts,
      existingCounts: existingCounts,
      settingsDiffer: settingsDiffer,
      currentShopSettings: local.rows('ShopSettings').firstOrNull,
      reviewSignature: _signature(local),
    );
  }

  Map<String, int> _safeCounts(
    WorkbookData workbook,
    Map<String, Map<String, WorkbookRow>> localMaps, {
    required bool existing,
  }) => {
    for (final name in businessSheets)
      name: workbook.rows(name).where((row) {
        try {
          return localMaps[name]!.containsKey(row.key) == existing;
        } catch (_) {
          return false;
        }
      }).length,
  };

  String _signature(WorkbookData local) => jsonEncode([
    for (final name in businessSheets)
      [name, ...(local.rows(name).map((r) => r.canonical).toList()..sort())],
    local.metadata['next_bill_number'],
  ]);

  Map<String, String> _aggregates(WorkbookData data) {
    final groups = <String, List<List<String>>>{};
    final itemOrders = <String, String>{};
    List<List<String>> group(String id) =>
        groups.putIfAbsent(id, () => [[], [], []]);
    for (final row in data.rows('OrderItems')) {
      itemOrders[row.key] = row.text('order_id');
      group(row.text('order_id'))[0].add(row.canonical);
    }
    for (final row in data.rows('Measurements')) {
      final orderId = itemOrders[row.text('item_id')];
      if (orderId != null) group(orderId)[1].add(row.canonical);
    }
    for (final row in data.rows('Payments')) {
      group(row.text('order_id'))[2].add(row.canonical);
    }
    return {
      for (final entry in groups.entries)
        entry.key: jsonEncode([for (final rows in entry.value) rows..sort()]),
    };
  }

  List<WorkbookIssue> _duplicates(WorkbookData workbook, WorkbookData local) {
    final warnings = <WorkbookIssue>[];
    final localIds = local.rows('Customers').map((r) => r.key).toSet();
    final candidates = <String, Set<String>>{};
    Iterable<String> keys(WorkbookRow row) sync* {
      final name = normalizeName(row.text('name'));
      yield 'name:$name';
      final first = name.split(' ').first;
      if (first.length >= 3) yield 'first:$first';
      for (final field in ['mobile', 'alternate_mobile']) {
        final phone = phoneSearch(row.optional(field));
        if (phone != null) yield 'phone:$phone';
      }
    }

    for (final row in [
      ...local.rows('Customers'),
      ...workbook.rows('Customers'),
    ]) {
      for (final key in keys(row)) {
        candidates.putIfAbsent(key, () => {}).add(row.key);
      }
    }
    for (final row
        in workbook.rows('Customers').where((r) => !localIds.contains(r.key))) {
      if (keys(row).any((key) => candidates[key]!.any((id) => id != row.key))) {
        warnings.add(
          WorkbookIssue(
            'Customers',
            row.line,
            'name/phone',
            'Similar name or matching phone found. Review this row and confirm it represents a separate customer.',
          ),
        );
      }
    }
    return warnings;
  }
}
