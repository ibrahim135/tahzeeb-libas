import '../../../core/value_objects.dart';
import '../../orders/domain/catalog.dart';
import '../../orders/domain/records.dart';
import 'workbook.dart';

/// Validates portable fields and complete order aggregates before persistence.
List<WorkbookIssue> validateWorkbook(
  WorkbookData data,
  Set<String> localCustomerIds,
) {
  final errors = [...data.issues];
  void error(WorkbookRow row, String field, String message) =>
      errors.add(WorkbookIssue(row.sheet, row.line, field, message));
  final maps = <String, Map<String, WorkbookRow>>{};
  for (final entry in workbookColumns.entries) {
    final rows = data.rows(entry.key);
    final seen = <String>{};
    final byKey = <String, WorkbookRow>{};
    maps[entry.key] = byKey;
    if (!data.tables.containsKey(entry.key)) {
      errors.add(
        WorkbookIssue(entry.key, 1, 'sheet', 'Required sheet is missing.'),
      );
    }
    if (rows.length > workbookMaxRows) {
      errors.add(WorkbookIssue(entry.key, 1, 'sheet', 'Too many rows.'));
    }
    for (final row in rows) {
      final before = errors.length;
      for (final field in entry.value) {
        final value = row.values[field];
        if (value == null && workbookOptionalColumns.contains(field)) continue;
        final isInt =
            workbookIntegerColumns.contains(field) ||
            (row.sheet == 'ShopSettings' && field == 'id');
        if (isInt
            ? value is! int
            : value is! String ||
                  (value.isEmpty && !workbookOptionalColumns.contains(field)) ||
                  value.length > 32767) {
          error(
            row,
            field,
            isInt ? 'A whole number is required.' : 'A text value is required.',
          );
          continue;
        }
        try {
          if (row.sheet != 'Metadata') {
            if (field == 'id' && row.sheet == 'ShopSettings') {
              if (value != 1) throw const FormatException();
            } else if (field == 'id' || field.endsWith('_id')) {
              requireId(value as String);
            }
            if (field.endsWith('_at')) workbookTimestamp(value as String);
            if (field.endsWith('_date')) BusinessDate.parse(value as String);
            if (field.endsWith('_paise')) Money(value as int);
            if (field == 'amount_paise' && value == 0) {
              throw const FormatException();
            }
            if (field == 'quantity' && ((value as int) < 1 || value > 10000)) {
              throw const FormatException();
            }
            if (field == 'position' && ((value as int) < 0 || value > 999)) {
              throw const FormatException();
            }
            if (field == 'status') OrderStatus.fromId(value as String);
            if (field == 'garment_type') {
              GarmentType.values.byName(value as String);
            }
            if (field == 'measurement_config') {
              MeasurementConfiguration.values.byName(value as String);
            }
            if (field == 'measurement_unit' && value != 'inches') {
              throw const FormatException();
            }
          }
        } catch (_) {
          error(row, field, _fieldHint(field));
        }
      }
      if (errors.length != before) continue;
      if (!seen.add(row.key)) {
        error(row, 'id/key', 'Duplicate key within this sheet.');
      }
      byKey[row.key] = row;
    }
  }
  if (data.tables.values.fold(0, (n, rows) => n + rows.length) >
      workbookMaxTotalRows) {
    errors.add(
      const WorkbookIssue('Workbook', 1, 'rows', 'Too many total rows.'),
    );
  }
  final metadata = maps['Metadata']!;
  const requiredMetadata = {
    'workbook_schema_version',
    'source_database_schema_version',
    'exported_at',
    'currency',
    'measurement_unit',
    'next_bill_number',
  };
  for (final key in requiredMetadata) {
    final row = metadata[key];
    if (row == null) {
      errors.add(
        WorkbookIssue('Metadata', 1, key, 'Required metadata is missing.'),
      );
      continue;
    }
    try {
      final value = row.text('value');
      switch (key) {
        case 'workbook_schema_version':
        case 'source_database_schema_version':
          if (value != '1') throw const FormatException();
        case 'currency':
          if (value != 'INR') throw const FormatException();
        case 'measurement_unit':
          if (value != 'inches') throw const FormatException();
        case 'next_bill_number':
          if (!RegExp(r'^\d{1,13}$').hasMatch(value) ||
              int.parse(value) < 1 ||
              int.parse(value) > 1000000000000) {
            throw const FormatException();
          }
        case 'exported_at':
          workbookTimestamp(value);
      }
    } catch (_) {
      error(
        row,
        'value',
        'Unsupported or invalid $key. Use schema v1, database v1, INR, inches, UTC export time and a positive bill counter up to 1000000000000.',
      );
    }
  }
  for (final row in metadata.values.where(
    (r) => !requiredMetadata.contains(r.key),
  )) {
    error(row, 'key', 'Unknown metadata key.');
  }
  if (data.rows('ShopSettings').length > 1) {
    errors.add(
      const WorkbookIssue(
        'ShopSettings',
        2,
        'id',
        'Only one singleton row is allowed.',
      ),
    );
  }

  final customers = maps['Customers']!;
  final orders = maps['Orders']!;
  final items = maps['OrderItems']!;
  final payments = maps['Payments']!;
  for (final row in customers.values) {
    try {
      CustomerRecord(
        id: row.text('id'),
        name: row.text('name'),
        createdAt: workbookTimestamp(row.text('created_at')),
        updatedAt: workbookTimestamp(row.text('updated_at')),
      );
    } catch (_) {
      error(
        row,
        'record',
        'Customer name is required and updated_at must not precede created_at.',
      );
    }
  }
  final measurementsByItem = <String, List<WorkbookRow>>{};
  for (final row in maps['Measurements']!.values) {
    if (!items.containsKey(row.text('item_id'))) {
      error(
        row,
        'item_id',
        'Reference must identify an OrderItems row in this workbook.',
      );
    }
    measurementsByItem.putIfAbsent(row.text('item_id'), () => []).add(row);
  }
  final modelItems = <String, GarmentItem>{};
  final itemsByOrder = <String, List<WorkbookRow>>{};
  for (final row in items.values) {
    if (!orders.containsKey(row.text('order_id'))) {
      error(
        row,
        'order_id',
        'Reference must identify an Orders row in this workbook. Existing bills cannot be extended by import.',
      );
    }
    itemsByOrder.putIfAbsent(row.text('order_id'), () => []).add(row);
    final config = MeasurementConfiguration.values.byName(
      row.text('measurement_config'),
    );
    final measurements = measurementsByItem[row.key] ?? [];
    for (final measurement in measurements) {
      try {
        MeasurementSnapshot(config, {
          measurement.text('field_key'): measurement.text('value_decimal'),
        });
      } catch (_) {
        error(
          measurement,
          'value_decimal/field_key',
          'Use a positive decimal in inches with at most three decimal places and a field in the item’s enabled section.',
        );
      }
    }
    try {
      modelItems[row.key] = GarmentItem(
        id: row.key,
        type: GarmentType.values.byName(row.text('garment_type')),
        variant: row.optional('variant'),
        quantity: row.integer('quantity'),
        unitPrice: Money(row.integer('unit_price_paise')),
        description: row.optional('description'),
        measurements: MeasurementSnapshot(config, {
          for (final m in measurements)
            m.text('field_key'): m.text('value_decimal'),
        }),
        fittingNotes: row.optional('fitting_notes'),
        createdAt: workbookTimestamp(row.text('created_at')),
        updatedAt: workbookTimestamp(row.text('updated_at')),
      );
    } catch (_) {
      error(
        row,
        'record',
        'Check garment variant, enabled measurements, quantity × rate limit and chronological timestamps.',
      );
    }
  }
  final modelPayments = <String, PaymentRecord>{};
  final paymentsByOrder = <String, List<WorkbookRow>>{};
  for (final row in payments.values) {
    final parent = orders[row.text('order_id')];
    if (parent == null) {
      error(
        row,
        'order_id',
        'Reference must identify an Orders row in this workbook.',
      );
    }
    paymentsByOrder.putIfAbsent(row.text('order_id'), () => []).add(row);
    try {
      final payment = PaymentRecord(
        id: row.key,
        amount: Money(row.integer('amount_paise')),
        date: BusinessDate.parse(row.text('payment_date')),
        method: row.optional('method'),
        notes: row.optional('notes'),
        createdAt: workbookTimestamp(row.text('created_at')),
        updatedAt: workbookTimestamp(row.text('updated_at')),
        voidedAt: row.optional('voided_at') == null
            ? null
            : workbookTimestamp(row.text('voided_at')),
        voidReason: row.optional('void_reason'),
        replacesPaymentId: row.optional('replaces_payment_id'),
      );
      if (payment.date.compareTo(BusinessDate.today()) > 0 ||
          (parent != null &&
              payment.date.compareTo(
                    BusinessDate.parse(parent.text('order_date')),
                  ) <
                  0)) {
        error(
          row,
          'payment_date',
          'Payment date must be between its order date and today.',
        );
      }
      final replacement = row.optional('replaces_payment_id');
      if (replacement != null &&
          (payments[replacement]?.optional('voided_at') == null ||
              payments[replacement]?.text('order_id') != row.text('order_id') ||
              replacement == row.key)) {
        error(
          row,
          'replaces_payment_id',
          'Replacement must identify a different voided payment in the same workbook order.',
        );
      }
      modelPayments[row.key] = payment;
    } catch (_) {
      error(
        row,
        'record',
        'Check positive amount, paired void reason/time and chronological UTC timestamps.',
      );
    }
  }
  final bills = <String>{};
  final replaced = <String>{};
  final checkedChains = <String>{};
  for (final row in payments.values) {
    final originalId = row.optional('replaces_payment_id');
    if (originalId != null && !replaced.add(originalId)) {
      error(
        row,
        'replaces_payment_id',
        'A corrected payment can have only one replacement.',
      );
    }
    final path = <String>{};
    var cursor = row.key;
    while (!checkedChains.contains(cursor) && payments.containsKey(cursor)) {
      if (!path.add(cursor)) {
        error(
          row,
          'replaces_payment_id',
          'Correction references must not form a cycle.',
        );
        break;
      }
      final parent = payments[cursor]!.optional('replaces_payment_id');
      if (parent == null) break;
      cursor = parent;
    }
    checkedChains.addAll(path);
  }
  for (final row in orders.values) {
    if (!customers.containsKey(row.text('customer_id')) &&
        !localCustomerIds.contains(row.text('customer_id'))) {
      error(row, 'customer_id', 'Customer must exist locally or in Customers.');
    }
    try {
      if (!bills.add(billKey(row.text('bill_number')))) {
        error(
          row,
          'bill_number',
          'Duplicate normalized bill number in the workbook.',
        );
      }
      final children = itemsByOrder[row.key] ?? [];
      children.sort(
        (a, b) => a.integer('position').compareTo(b.integer('position')),
      );
      for (var position = 0; position < children.length; position++) {
        if (children[position].integer('position') != position) {
          error(
            children[position],
            'position',
            'Positions must be unique and consecutive, starting at 0 within each order.',
          );
        }
      }
      OrderRecord(
        id: row.key,
        billNumber: row.text('bill_number'),
        customerId: row.text('customer_id'),
        orderDate: BusinessDate.parse(row.text('order_date')),
        deliveryDate: BusinessDate.parse(row.text('delivery_date')),
        status: OrderStatus.fromId(row.text('status')),
        discount: Money(row.integer('discount_paise')),
        notes: row.optional('notes'),
        createdAt: workbookTimestamp(row.text('created_at')),
        updatedAt: workbookTimestamp(row.text('updated_at')),
        items: [
          for (final child in children)
            if (modelItems.containsKey(child.key)) modelItems[child.key]!,
        ],
        payments: [
          for (final p in paymentsByOrder[row.key] ?? <WorkbookRow>[])
            if (modelPayments.containsKey(p.key)) modelPayments[p.key]!,
        ],
      );
    } catch (_) {
      error(
        row,
        'record',
        'Check bill, dates/timestamps, at least one garment, subtotal/discount bounds and active payments not exceeding total.',
      );
    }
  }
  return errors;
}

DateTime workbookTimestamp(String text) {
  final match = RegExp(
    r'^(\d{4}-\d{2}-\d{2})T(\d{2}):(\d{2}):(\d{2})(\.\d{1,6})?Z$',
  ).firstMatch(text);
  if (match == null) throw const FormatException('UTC timestamp required.');
  BusinessDate.parse(match[1]!);
  if (int.parse(match[2]!) > 23 ||
      int.parse(match[3]!) > 59 ||
      int.parse(match[4]!) > 59) {
    throw const FormatException('Invalid time.');
  }
  return DateTime.parse(text);
}

String _fieldHint(String field) {
  if (field.endsWith('_at')) {
    return 'Use a valid UTC ISO timestamp ending in Z (year 1900–9999).';
  }
  if (field.endsWith('_date')) {
    return 'Use a valid date as YYYY-MM-DD (year 1900–9999).';
  }
  if (field.endsWith('_id') || field == 'id') {
    return 'Use a valid UUID; ShopSettings id must be 1.';
  }
  if (field.endsWith('_paise')) {
    return 'Use nonnegative integer paise up to 100000000000; payments must be positive.';
  }
  if (field == 'quantity') return 'Quantity must be 1–10000.';
  if (field == 'position') {
    return 'Position must be 0–999, consecutive within each order.';
  }
  return 'Use a supported stable identifier from the workbook schema.';
}
