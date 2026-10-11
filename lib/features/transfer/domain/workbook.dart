import 'dart:convert';

/// The portable schema is deliberately independent from SQLite migrations.
const workbookVersion = 1;
const workbookMaxBytes = 8 * 1024 * 1024;
const workbookMaxExpandedBytes = 32 * 1024 * 1024;
const workbookMaxEntryBytes = 8 * 1024 * 1024;
const workbookMaxRows = 20000;
const workbookMaxTotalRows = 100000;

const workbookColumns = <String, List<String>>{
  'Customers': [
    'id',
    'name',
    'mobile',
    'alternate_mobile',
    'address',
    'notes',
    'created_at',
    'updated_at',
  ],
  'Orders': [
    'id',
    'bill_number',
    'customer_id',
    'order_date',
    'delivery_date',
    'status',
    'discount_paise',
    'notes',
    'created_at',
    'updated_at',
  ],
  'OrderItems': [
    'id',
    'order_id',
    'position',
    'garment_type',
    'variant',
    'quantity',
    'unit_price_paise',
    'description',
    'measurement_config',
    'measurement_unit',
    'fitting_notes',
    'created_at',
    'updated_at',
  ],
  'Measurements': ['item_id', 'field_key', 'value_decimal'],
  'Payments': [
    'id',
    'order_id',
    'amount_paise',
    'payment_date',
    'method',
    'notes',
    'created_at',
    'updated_at',
    'voided_at',
    'void_reason',
    'replaces_payment_id',
  ],
  'ShopSettings': [
    'id',
    'name',
    'address',
    'contact',
    'receipt_notes',
    'updated_at',
  ],
  'Metadata': ['key', 'value'],
};
const workbookIntegerColumns = {
  'position',
  'quantity',
  'unit_price_paise',
  'discount_paise',
  'amount_paise',
};
const workbookOptionalColumns = {
  'mobile',
  'alternate_mobile',
  'address',
  'notes',
  'variant',
  'description',
  'fitting_notes',
  'method',
  'voided_at',
  'void_reason',
  'replaces_payment_id',
  'contact',
  'receipt_notes',
};

final class WorkbookIssue {
  final String sheet, field, message;
  final int row;
  const WorkbookIssue(this.sheet, this.row, this.field, this.message);
  @override
  String toString() => '$sheet · row $row · $field: $message';
}

final class WorkbookRow {
  final String sheet;

  /// One-based Excel row, including the header.
  final int line;
  final Map<String, Object?> values;
  WorkbookRow(this.sheet, this.line, Map<String, Object?> values)
    : values = Map.unmodifiable(values);
  String text(String field) => values[field] as String;
  String? optional(String field) => values[field] as String?;
  int integer(String field) => values[field] as int;
  String get key => sheet == 'Measurements'
      ? '${text('item_id')}/${text('field_key')}'
      : sheet == 'Metadata'
      ? text('key')
      : '${values['id']}';
  String get canonical =>
      jsonEncode([for (final field in workbookColumns[sheet]!) values[field]]);
}

final class WorkbookData {
  final Map<String, List<WorkbookRow>> tables;
  final List<WorkbookIssue> issues;
  WorkbookData(
    Map<String, List<WorkbookRow>> tables, {
    List<WorkbookIssue> issues = const [],
  }) : tables = Map.unmodifiable({
         for (final entry in tables.entries)
           entry.key: List<WorkbookRow>.unmodifiable(entry.value),
       }),
       issues = List.unmodifiable(issues);
  List<WorkbookRow> rows(String sheet) => tables[sheet] ?? const [];
  Map<String, String> get metadata => {
    for (final row in rows('Metadata')) row.text('key'): row.text('value'),
  };
}

final class ImportPreview {
  final WorkbookData workbook;
  final List<WorkbookIssue> errors, duplicateWarnings;
  final Map<String, int> newCounts, existingCounts;
  final bool settingsDiffer;
  final WorkbookRow? currentShopSettings;

  /// Captures every reviewed decision; commit checks again against live data.
  final String reviewSignature;
  ImportPreview({
    required this.workbook,
    required List<WorkbookIssue> errors,
    required List<WorkbookIssue> duplicateWarnings,
    required Map<String, int> newCounts,
    required Map<String, int> existingCounts,
    required this.settingsDiffer,
    this.currentShopSettings,
    required this.reviewSignature,
  }) : errors = List.unmodifiable(errors),
       duplicateWarnings = List.unmodifiable(duplicateWarnings),
       newCounts = Map.unmodifiable(newCounts),
       existingCounts = Map.unmodifiable(existingCounts);
  bool get valid => errors.isEmpty;
  int get newRecords => newCounts.values.fold(0, (sum, count) => sum + count);
  int get existingRecords =>
      existingCounts.values.fold(0, (sum, count) => sum + count);
}

final class ImportResult {
  final int addedRecords;
  final bool settingsUpdated, counterUpdated;
  const ImportResult(
    this.addedRecords, {
    required this.settingsUpdated,
    required this.counterUpdated,
  });
}

abstract interface class WorkbookRepository {
  Future<WorkbookData> snapshot();
  Future<ImportPreview> preview(WorkbookData workbook);
  Future<ImportResult> commit(
    ImportPreview preview, {
    bool acceptSimilarCustomers = false,
    bool replaceShopSettings = false,
  });
}
