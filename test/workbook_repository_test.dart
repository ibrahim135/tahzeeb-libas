import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tahzeeb_libas/data/database/app_database.dart';
import 'package:tahzeeb_libas/features/orders/data/drift_tailoring_repository.dart';
import 'package:tahzeeb_libas/features/orders/domain/catalog.dart';
import 'package:tahzeeb_libas/features/orders/domain/records.dart';
import 'package:tahzeeb_libas/features/orders/domain/order_query.dart';
import 'package:tahzeeb_libas/core/value_objects.dart';
import 'package:tahzeeb_libas/features/transfer/application/workbook_transfer.dart';
import 'package:tahzeeb_libas/features/transfer/data/drift_workbook_repository.dart';
import 'package:tahzeeb_libas/features/transfer/data/workbook_codec.dart';
import 'package:tahzeeb_libas/features/transfer/domain/workbook.dart';

import 'fixtures.dart' as f;

WorkbookData changed(
  WorkbookData data,
  String sheet,
  int index,
  Map<String, Object?> changes,
) => WorkbookData({
  ...data.tables,
  sheet: [
    for (var i = 0; i < data.rows(sheet).length; i++)
      i == index
          ? WorkbookRow(sheet, data.rows(sheet)[i].line, {
              ...data.rows(sheet)[i].values,
              ...changes,
            })
          : data.rows(sheet)[i],
  ],
});
WorkbookData without(WorkbookData data, String sheet) =>
    WorkbookData({...data.tables, sheet: []});
List<Object> persisted(WorkbookData data) => [
  for (final name in workbookColumns.keys.where((n) => n != 'Metadata'))
    [name, ...(data.rows(name).map((r) => r.canonical).toList()..sort())],
  data.metadata['next_bill_number']!,
];

final class CancelledFiles implements WorkbookFiles {
  @override
  Future<Uint8List?> pick() async => null;
  @override
  Future<bool> save(Uint8List bytes, String fileName) async => false;
  @override
  Future<bool> share(Uint8List bytes, String fileName) async => false;
}

void main() {
  late AppDatabase db;
  late DriftTailoringRepository orders;
  late DriftWorkbookRepository transfer;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    orders = DriftTailoringRepository(db);
    transfer = DriftWorkbookRepository(db);
  });
  tearDown(() => db.close());

  Future<WorkbookData> seed() async {
    final customer = f.customer(name: '=محمد Test');
    await orders.saveCustomer(customer);
    final original = PaymentRecord(
      id: f.id(),
      amount: Money(5000),
      date: BusinessDate.parse('2025-01-01'),
      method: 'Cash',
      notes: 'Original\nAdvance',
      createdAt: f.created,
      updatedAt: DateTime.utc(2025, 1, 2),
      voidedAt: DateTime.utc(2025, 1, 2),
      voidReason: 'Wrong amount — correction',
    );
    final replacement = PaymentRecord(
      id: f.id(),
      amount: Money(3000),
      date: BusinessDate.parse('2025-01-01'),
      method: 'UPI',
      notes: 'Replacement',
      createdAt: DateTime.utc(2025, 1, 2),
      updatedAt: DateTime.utc(2025, 1, 2),
      replacesPaymentId: original.id,
    );
    final order = f.order(
      customer.id,
      items: [
        f.item(
          snapshot: MeasurementSnapshot(MeasurementConfiguration.both, {
            'upper_length': '30.125',
            'upper_hips': '42',
            'lower_length': '40.5',
            'lower_hips': '43',
          }),
        ),
        f.item(
          type: GarmentType.pagdi,
          snapshot: MeasurementSnapshot(MeasurementConfiguration.none, {}),
          price: 0,
        ),
      ],
      payments: [replacement, f.payment(), original],
    );
    await orders.createOrder(order);
    await db
        .update(db.shopSettings)
        .write(
          ShopSettingsCompanion(
            name: const Value('Example Tailors'),
            address: const Value('Shop 1\nMumbai'),
            contact: const Value('0012345678'),
            receiptNotes: const Value('=literal note\nधन्यवाद'),
            updatedAt: Value(DateTime.utc(2025, 1, 3).toIso8601String()),
          ),
        );
    await db
        .update(db.appState)
        .write(const AppStateCompanion(nextBillNumber: Value(42)));
    return transfer.snapshot();
  }

  Future<void> fresh() async {
    await db.close();
    db = AppDatabase(NativeDatabase.memory());
    orders = DriftTailoringRepository(db);
    transfer = DriftWorkbookRepository(db);
  }

  test('full-field XLSX backup restores every table, voids, exact values and counter', () async {
    final source = await seed();
    final decoded = WorkbookCodec().decode(await encodeWorkbook(source));
    expect(decoded.issues, isEmpty);
    expect(decoded.rows('Customers').single.text('mobile'), '0012345678');
    expect(decoded.rows('Orders').single.text('bill_number'), '0007');
    await fresh();
    final preview = await transfer.preview(decoded);
    expect(preview.errors, isEmpty);
    expect(preview.settingsDiffer, isTrue);
    await expectLater(transfer.commit(preview), throwsStateError);
    final result = await transfer.commit(preview, replaceShopSettings: true);
    expect(
      result.addedRecords,
      11,
    ); // customer + order + 2 items + 4 values + 3 payments
    expect(result.settingsUpdated, isTrue);
    expect(result.counterUpdated, isTrue);
    expect(persisted(await transfer.snapshot()), persisted(source));
    final loaded = await orders.getOrder(source.rows('Orders').single.key);
    expect(loaded!.paidPaise, 8000);
    expect(loaded.payments.where((p) => p.voidedAt != null), hasLength(1));
    expect(
      loaded.items.last.measurements.configuration,
      MeasurementConfiguration.none,
    );
  });

  test(
    'reordered repeated imports are unchanged and make zero writes',
    () async {
      final source = await seed();
      final data = WorkbookData({
        for (final entry in source.tables.entries)
          entry.key: entry.value.reversed.toList(),
      });
      final preview = await transfer.preview(
        WorkbookCodec().decode(WorkbookCodec().encode(data)),
      );
      expect(preview.errors, isEmpty);
      expect(preview.newRecords, 0);
      expect(preview.settingsDiffer, isFalse);
      // Even an UPDATE with unchanged values would fail this trigger.
      await db.customStatement(
        "CREATE TRIGGER forbid_update BEFORE UPDATE ON customers BEGIN SELECT RAISE(ABORT, 'unexpected update'); END",
      );
      final result = await transfer.commit(preview);
      expect(result.addedRecords, 0);
      expect(result.counterUpdated, isFalse);
      expect(persisted(await transfer.snapshot()), persisted(source));
    },
  );

  test(
    'changed stable ID blocks the whole workbook without overwriting',
    () async {
      final source = await seed();
      final preview = await transfer.preview(
        changed(source, 'Customers', 0, {'notes': 'Different notes'}),
      );
      expect(
        preview.errors.any((e) => e.sheet == 'Customers' && e.field == 'id'),
        isTrue,
      );
      await expectLater(
        transfer.commit(preview, replaceShopSettings: true),
        throwsStateError,
      );
      expect(persisted(await transfer.snapshot()), persisted(source));
    },
  );

  test(
    'different order ID with occupied normalized bill number conflicts',
    () async {
      final source = await seed();
      final newId = f.id();
      var data = changed(source, 'Orders', 0, {
        'id': newId,
        'bill_number': ' 0007 ',
      });
      for (final name in ['OrderItems', 'Payments']) {
        for (var i = 0; i < data.rows(name).length; i++) {
          data = changed(data, name, i, {'order_id': newId});
        }
      }
      final preview = await transfer.preview(data);
      expect(
        preview.errors.any(
          (e) => e.sheet == 'Orders' && e.field == 'bill_number',
        ),
        isTrue,
      );
      await expectLater(transfer.commit(preview), throwsStateError);
      expect(persisted(await transfer.snapshot()), persisted(source));
    },
  );

  test('a late SQLite failure rolls back customers, orders, measurements and payments', () async {
    final source = await seed();
    await fresh();
    final before = await transfer.snapshot();
    final preview = await transfer.preview(source);
    expect(preview.valid, isTrue);
    await db.customStatement(
      "CREATE TRIGGER fail_late BEFORE UPDATE ON app_state BEGIN SELECT RAISE(ABORT, 'injected failure'); END",
    );
    await expectLater(
      transfer.commit(preview, replaceShopSettings: true),
      throwsA(anything),
    );
    expect(persisted(await transfer.snapshot()), persisted(before));
    expect(await db.select(db.measurements).get(), isEmpty);
    expect(await db.select(db.payments).get(), isEmpty);
  });

  test(
    'preview and cancelled picker leave every persisted field untouched',
    () async {
      final source = await seed();
      final service = WorkbookTransfer(transfer, CancelledFiles());
      expect(await service.pickAndPreview(), isNull);
      await transfer.preview(source);
      expect(persisted(await transfer.snapshot()), persisted(source));
    },
  );

  test(
    'stale preview is revalidated and rejects commit after local edits',
    () async {
      final source = await seed();
      await fresh();
      final preview = await transfer.preview(source);
      await orders.saveCustomer(f.customer(name: 'Changed during preview'));
      final afterEdit = await transfer.snapshot();
      await expectLater(
        transfer.commit(preview, replaceShopSettings: true),
        throwsStateError,
      );
      expect(persisted(await transfer.snapshot()), persisted(afterEdit));
    },
  );

  test('similar new customers require review but legitimate separate customers can import', () async {
    final source = await seed();
    await fresh();
    await orders.saveCustomer(f.customer(name: '=محمد Test'));
    final preview = await transfer.preview(source);
    expect(preview.errors, isEmpty);
    expect(preview.duplicateWarnings, hasLength(1));
    await expectLater(
      transfer.commit(preview, replaceShopSettings: true),
      throwsStateError,
    );
    await transfer.commit(
      preview,
      replaceShopSettings: true,
      acceptSimilarCustomers: true,
    );
    expect(await db.select(db.customers).get(), hasLength(2));
  });

  test(
    'new orders may reference existing customers absent from the workbook',
    () async {
      final source = await seed();
      final customerRow = source.rows('Customers').single;
      await fresh();
      await orders.saveCustomer(
        f.customer(customerId: customerRow.key, name: customerRow.text('name')),
      );
      final preview = await transfer.preview(without(source, 'Customers'));
      expect(preview.errors, isEmpty);
      await transfer.commit(preview, replaceShopSettings: true);
      expect(await db.select(db.customers).get(), hasLength(1));
      expect(await db.select(db.orders).get(), hasLength(1));
    },
  );

  test('existing orders require complete unchanged payment and measurement history', () async {
    final source = await seed();
    for (final name in ['Payments', 'Measurements']) {
      final preview = await transfer.preview(without(source, name));
      expect(
        preview.errors.any((e) => e.field == 'items/payments/measurements'),
        isTrue,
      );
      await expectLater(transfer.commit(preview), throwsStateError);
    }
    expect(persisted(await transfer.snapshot()), persisted(source));
  });

  test(
    'orphan children cannot extend existing local orders through import',
    () async {
      final source = await seed();
      final preview = await transfer.preview(without(source, 'Orders'));
      expect(
        preview.errors.any(
          (e) => e.sheet == 'OrderItems' && e.field == 'order_id',
        ),
        isTrue,
      );
    },
  );

  test(
    'counter never decreases and advances past imported historic numeric bills',
    () async {
      final source = await seed();
      await fresh();
      await db
          .update(db.appState)
          .write(const AppStateCompanion(nextBillNumber: Value(100)));
      final preview = await transfer.preview(source);
      await transfer.commit(preview, replaceShopSettings: true);
      expect(await orders.suggestBillNumber(), '100');
      await fresh();
      final lowCounter = WorkbookData({
        ...source.tables,
        'Metadata': [
          for (final row in source.rows('Metadata'))
            row.key == 'next_bill_number'
                ? WorkbookRow('Metadata', row.line, {
                    'key': row.key,
                    'value': '1',
                  })
                : row,
        ],
      });
      await transfer.commit(
        await transfer.preview(lowCounter),
        replaceShopSettings: true,
      );
      expect(await orders.suggestBillNumber(), '8');
    },
  );

  test(
    'imported backup persists after closing and reopening the database file',
    () async {
      final source = await seed();
      final directory = await Directory.systemTemp.createTemp(
        'workbook_restart_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/shop.sqlite');
      await db.close();
      db = AppDatabase.openFile(file);
      transfer = DriftWorkbookRepository(db);
      await transfer.commit(
        await transfer.preview(source),
        replaceShopSettings: true,
      );
      await db.close();
      db = AppDatabase.openFile(file);
      transfer = DriftWorkbookRepository(db);
      expect(persisted(await transfer.snapshot()), persisted(source));
      final violations = await db
          .customSelect('PRAGMA foreign_key_check')
          .get();
      expect(violations, isEmpty);
    },
  );

  test(
    'blank template has separate examples and imports zero shop records',
    () async {
      await seed();
      final bytes = await WorkbookTransfer(
        transfer,
        CancelledFiles(),
      ).template();
      final decoded = WorkbookCodec().decode(bytes);
      expect(decoded.issues, isEmpty);
      for (final name in workbookColumns.keys.where((n) => n != 'Metadata')) {
        expect(decoded.rows(name), isEmpty);
      }
      final preview = await transfer.preview(decoded);
      expect(preview.errors, isEmpty);
      expect((await transfer.commit(preview)).addedRecords, 0);
    },
  );

  test('malformed dates, enums, amounts, positions, measurements and references report their rows', () async {
    final source = await seed();
    final cases = <(String, String, Object?)>[
      ('Orders', 'order_date', '2025-02-30'),
      ('Orders', 'status', 'unknown'),
      ('Orders', 'discount_paise', -1),
      ('Orders', 'customer_id', f.id()),
      ('OrderItems', 'garment_type', 'unknown'),
      ('OrderItems', 'position', 7),
      ('OrderItems', 'quantity', 0),
      ('OrderItems', 'unit_price_paise', 0.5),
      ('OrderItems', 'variant', 'bad_variant'),
      ('Measurements', 'value_decimal', '0'),
      ('Measurements', 'field_key', 'length'),
      ('Measurements', 'item_id', f.id()),
      ('Payments', 'amount_paise', 0),
      ('Payments', 'payment_date', '2099-01-01'),
      ('Payments', 'voided_at', '2025-02-30T00:00:00Z'),
      ('Customers', 'updated_at', '2024-12-31T00:00:00Z'),
      ('Customers', 'created_at', '2025-01-01T24:00:00Z'),
    ];
    for (final (sheet, field, value) in cases) {
      final preview = await transfer.preview(
        changed(source, sheet, 0, {field: value}),
      );
      expect(preview.valid, isFalse, reason: '$sheet.$field');
      expect(
        preview.errors.any(
          (e) => e.sheet == sheet && e.row == source.rows(sheet).first.line,
        ),
        isTrue,
        reason: '$sheet.$field',
      );
      await expectLater(transfer.commit(preview), throwsStateError);
    }
    expect(persisted(await transfer.snapshot()), persisted(source));
  });

  test(
    'duplicate keys and unsupported metadata block the complete import',
    () async {
      final source = await seed();
      final duplicate = WorkbookData({
        ...source.tables,
        'Customers': [
          ...source.rows('Customers'),
          WorkbookRow('Customers', 3, source.rows('Customers').first.values),
        ],
      });
      final preview = await transfer.preview(duplicate);
      expect(
        preview.errors.any((e) => e.sheet == 'Customers' && e.row == 3),
        isTrue,
      );
      final versionIndex = source
          .rows('Metadata')
          .indexWhere((r) => r.key == 'workbook_schema_version');
      expect(
        (await transfer.preview(
          changed(source, 'Metadata', versionIndex, {'value': '99'}),
        )).valid,
        isFalse,
      );
    },
  );

  test(
    'atomic import refreshes live order summaries without reopening the screen',
    () async {
      final source = await seed();
      await fresh();
      final iterator = StreamIterator(orders.watchOrders(OrderQuery()));
      try {
        expect(await iterator.moveNext(), isTrue);
        expect(iterator.current, isEmpty);
        final next = iterator.moveNext();
        await transfer.commit(
          await transfer.preview(source),
          replaceShopSettings: true,
        );
        expect(await next, isTrue);
        expect(iterator.current, hasLength(1));
        expect(iterator.current.single.paidPaise, 8000);
      } finally {
        await iterator.cancel();
      }
    },
  );

  test('replacement cycles and multiple replacements for one original are rejected', () async {
    final source = await seed();
    final originalIndex = source
        .rows('Payments')
        .indexWhere((r) => r.optional('voided_at') != null);
    final replacementIndex = source
        .rows('Payments')
        .indexWhere((r) => r.optional('replaces_payment_id') != null);
    final activeIndex = source
        .rows('Payments')
        .indexWhere(
          (r) =>
              r.optional('replaces_payment_id') == null &&
              r.optional('voided_at') == null,
        );
    final original = source.rows('Payments')[originalIndex];
    final replacement = source.rows('Payments')[replacementIndex];
    final repeated = changed(source, 'Payments', activeIndex, {
      'replaces_payment_id': original.key,
    });
    expect(
      (await transfer.preview(repeated)).errors
          .any((e) => e.field == 'replaces_payment_id'),
      isTrue,
    );
    var cyclic = changed(source, 'Payments', originalIndex, {
      'replaces_payment_id': replacement.key,
    });
    cyclic = changed(cyclic, 'Payments', replacementIndex, {
      'voided_at': '2025-01-02T00:00:00.000Z',
      'void_reason': 'Correction',
    });
    expect(
      (await transfer.preview(cyclic)).errors
          .any((e) => e.message.contains('cycle')),
      isTrue,
    );
    expect(persisted(await transfer.snapshot()), persisted(source));
  });
}
