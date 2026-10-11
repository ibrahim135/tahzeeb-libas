import 'dart:isolate';
import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../../../core/value_objects.dart';
import '../../../data/database/app_database.dart';
import '../domain/workbook.dart';
import '../domain/import_policy.dart';

final class DriftWorkbookRepository implements WorkbookRepository {
  final AppDatabase db;
  DriftWorkbookRepository(this.db);

  Map<String, TableInfo<Table, DataClass>> get _tables => {
    'Customers': db.customers,
    'Orders': db.orders,
    'OrderItems': db.orderItems,
    'Measurements': db.measurements,
    'Payments': db.payments,
    'ShopSettings': db.shopSettings,
  };

  @override
  Future<WorkbookData> snapshot() => db.transaction(_snapshot);

  Future<WorkbookData> _snapshot() async {
    final data = <String, List<WorkbookRow>>{};
    for (final entry in _tables.entries) {
      final columns = workbookColumns[entry.key]!;
      final records = await db
          .customSelect(
            'SELECT ${columns.join(', ')} FROM ${entry.value.actualTableName}',
          )
          .get();
      final rows = [
        for (final record in records)
          WorkbookRow(entry.key, 2, {
            for (final field in columns) field: record.data[field],
          }),
      ];
      rows.sort((a, b) => a.key.compareTo(b.key));
      data[entry.key] = [
        for (var i = 0; i < rows.length; i++)
          WorkbookRow(entry.key, i + 2, rows[i].values),
      ];
    }
    final state = await db.select(db.appState).getSingle();
    final metadata = {
      'workbook_schema_version': '$workbookVersion',
      'source_database_schema_version': '${db.schemaVersion}',
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'currency': 'INR',
      'measurement_unit': 'inches',
      'next_bill_number': '${state.nextBillNumber}',
    };
    data['Metadata'] = [
      for (var i = 0; i < metadata.length; i++)
        WorkbookRow('Metadata', i + 2, {
          'key': metadata.keys.elementAt(i),
          'value': metadata.values.elementAt(i),
        }),
    ];
    return WorkbookData(data);
  }

  @override
  Future<ImportPreview> preview(WorkbookData workbook) =>
      db.transaction(() async => _evaluate(workbook, await _snapshot()));

  Future<ImportPreview> _evaluate(WorkbookData workbook, WorkbookData local) =>
      Isolate.run(() => WorkbookImportPolicy().evaluate(workbook, local));

  @override
  Future<ImportResult> commit(
    ImportPreview preview, {
    bool acceptSimilarCustomers = false,
    bool replaceShopSettings = false,
  }) => db.transaction(() async {
    final local = await _snapshot();
    final checked = await _evaluate(preview.workbook, local);
    if (!checked.valid) {
      throw StateError(
        'Import contains invalid or conflicting records. No data was changed.',
      );
    }
    if (checked.reviewSignature != preview.reviewSignature) {
      throw StateError(
        'Local records changed after preview. Cancel and preview the file again. No data was changed.',
      );
    }
    if (checked.duplicateWarnings.isNotEmpty && !acceptSimilarCustomers) {
      throw StateError('Review similar customers before importing.');
    }
    if (checked.settingsDiffer && !replaceShopSettings) {
      throw StateError(
        'Confirm replacement of the shop details before importing.',
      );
    }
    final localMaps = {
      for (final name in _tables.keys)
        name: {for (final row in local.rows(name)) row.key: row},
    };
    for (final name in [
      'Customers',
      'Orders',
      'OrderItems',
      'Measurements',
      'Payments',
    ]) {
      for (final row in preview.workbook.rows(name)) {
        if (localMaps[name]!.containsKey(row.key)) continue;
        final values = Map<String, Object?>.of(row.values);
        if (name == 'Customers') {
          values['normalized_name'] = normalizeName(row.text('name'));
          values['mobile_search'] = phoneSearch(row.optional('mobile'));
          values['alternate_mobile_search'] = phoneSearch(
            row.optional('alternate_mobile'),
          );
        }
        if (name == 'Orders') {
          values['bill_key'] = billKey(row.text('bill_number'));
        }
        if (name == 'Payments') values['replaces_payment_id'] = null;
        final table = _tables[name]!;
        await db.customInsert(
          'INSERT INTO ${table.actualTableName} (${values.keys.join(', ')}) VALUES (${List.filled(values.length, '?').join(', ')})',
          variables: values.values.map(_variable).toList(),
          updates: {table},
        );
      }
    }
    for (final row in preview.workbook.rows('Payments')) {
      if (localMaps['Payments']!.containsKey(row.key) ||
          row.optional('replaces_payment_id') == null) {
        continue;
      }
      await db.customUpdate(
        'UPDATE payments SET replaces_payment_id = ? WHERE id = ?',
        variables: [
          Variable(row.text('replaces_payment_id')),
          Variable(row.key),
        ],
        updates: {db.payments},
      );
    }
    if (checked.settingsDiffer) {
      final row = preview.workbook.rows('ShopSettings').single;
      final fields = workbookColumns['ShopSettings']!
          .where((f) => f != 'id')
          .toList();
      await db.customUpdate(
        'UPDATE shop_settings SET ${fields.map((f) => '$f = ?').join(', ')} WHERE id = 1',
        variables: [for (final field in fields) _variable(row.values[field])],
        updates: {db.shopSettings},
      );
    }
    final state = await db.select(db.appState).getSingle();
    var counter = math.max(
      state.nextBillNumber,
      int.parse(preview.workbook.metadata['next_bill_number']!),
    );
    final bills = await db.select(db.orders).get();
    for (final order in bills) {
      final number = int.tryParse(order.billNumber);
      if (number != null && number >= counter && number < 1000000000000) {
        counter = number + 1;
      }
    }
    final occupied = bills.map((o) => o.billKey).toSet();
    while (occupied.contains('$counter') && counter < 1000000000000) {
      counter++;
    }
    final counterUpdated = counter != state.nextBillNumber;
    if (counterUpdated) {
      await db
          .update(db.appState)
          .write(AppStateCompanion(nextBillNumber: Value(counter)));
    }
    return ImportResult(
      checked.newRecords,
      settingsUpdated: checked.settingsDiffer,
      counterUpdated: counterUpdated,
    );
  });

  Variable _variable(Object? value) =>
      value is int ? Variable<int>(value) : Variable<String>(value as String?);
}
