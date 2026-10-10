import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tahzeeb_libas/data/database/app_database.dart';
import 'package:tahzeeb_libas/features/orders/data/drift_tailoring_repository.dart';
import 'package:tahzeeb_libas/features/orders/domain/catalog.dart';

import 'fixtures.dart';

void main() {
  late AppDatabase db;
  late DriftTailoringRepository repo;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = DriftTailoringRepository(db);
  });
  tearDown(() async => db.close());

  test(
    'fresh schema v1 initializes settings, counter and foreign keys',
    () async {
      expect(await repo.suggestBillNumber(), '1');
      expect(
        (await db.select(db.shopSettings).getSingle()).name,
        'Tahzeeb Libas',
      );
      expect(
        (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
          'user_version',
        ),
        1,
      );
      expect(
        (await db.customSelect('PRAGMA foreign_keys').getSingle()).read<int>(
          'foreign_keys',
        ),
        1,
      );
      await expectLater(
        repo.createOrder(order(id())),
        throwsA(
          isA<SqliteException>().having(
            (e) => e.resultCode,
            'constraint failure',
            19,
          ),
        ),
      );
      expect(await db.select(db.orders).get(), isEmpty);
    },
  );
  test('customer edits preserve phone text and original creation', () async {
    final c = customer();
    await repo.saveCustomer(c);
    expect((await repo.getCustomer(c.id))!.mobile, '0012345678');
    final changed = customer(customerId: c.id, name: 'Changed', phone: null);
    await repo.saveCustomer(changed);
    expect((await repo.getCustomer(c.id))!.name, 'Changed');
    expect((await repo.watchCustomers().first).length, 1);
  });
  test('aggregate preserves item snapshots and dated payment fields', () async {
    final c = customer();
    final o = order(
      c.id,
      items: [
        item(),
        item(
          type: GarmentType.pant,
          snapshot: MeasurementSnapshot(MeasurementConfiguration.lower, {
            'lower_length': '40.5',
            'lower_hips': '42',
          }),
        ),
      ],
      payments: [payment()],
    );
    await repo.createOrder(o, newCustomer: c);
    final restored = (await repo.getOrder(o.id))!;
    expect(restored.items.length, 2);
    expect(
      restored.items[0].measurements.values,
      o.items[0].measurements.values,
    );
    expect(restored.items[1].measurements.values['lower_length'], '40.5');
    expect(restored.items[0].fittingNotes, 'Loose fitting\nAdjust cuffs');
    expect(restored.payments.single.date.iso, '2025-01-01');
    expect(restored.payments.single.notes, 'Advance');
    expect(restored.billNumber, '0007');
    expect(restored.balancePaise, o.balancePaise);
    expect(await repo.suggestBillNumber(), '8');
  });
  test(
    'case insensitive bill uniqueness rolls back newly inserted customer',
    () async {
      final c = customer();
      await repo.createOrder(order(c.id, bill: ' HIST-A '), newCustomer: c);
      final other = customer();
      await expectLater(
        repo.createOrder(order(other.id, bill: 'hist-a'), newCustomer: other),
        throwsA(
          isA<SqliteException>().having(
            (e) => e.resultCode,
            'constraint failure',
            19,
          ),
        ),
      );
      expect(await repo.getCustomer(other.id), isNull);
      expect((await db.select(db.orders).get()).length, 1);
    },
  );
  test('late item collision rolls back order and bill counter', () async {
    final c = customer();
    final garment = item();
    await repo.createOrder(
      order(c.id, bill: '10', items: [garment]),
      newCustomer: c,
    );
    final other = customer();
    await expectLater(
      repo.createOrder(
        order(other.id, bill: '20', items: [garment]),
        newCustomer: other,
      ),
      throwsA(
        isA<SqliteException>().having(
          (e) => e.resultCode,
          'constraint failure',
          19,
        ),
      ),
    );
    expect(await repo.getCustomer(other.id), isNull);
    expect(await repo.suggestBillNumber(), '11');
    expect((await db.select(db.orders).get()).length, 1);
  });
  test('separate orders never share measurement rows', () async {
    final c = customer();
    await repo.saveCustomer(c);
    final first = order(c.id);
    final second = order(c.id, bill: '8');
    await repo.createOrder(first);
    await repo.createOrder(second);
    await (db.update(db.measurements)..where(
          (m) =>
              m.itemId.equals(second.items[0].id) &
              m.fieldKey.equals('upper_length'),
        ))
        .write(const MeasurementsCompanion(valueDecimal: Value('99')));
    expect(
      (await repo.getOrder(first.id))!
          .items
          .single
          .measurements
          .values['upper_length'],
      '30.125',
    );
    expect(
      (await repo.getOrder(second.id))!
          .items
          .single
          .measurements
          .values['upper_length'],
      '99',
    );
  });
  test(
    'actual file persists across closed connections and background isolates',
    () async {
      await db.close();
      final directory = await Directory.systemTemp.createTemp(
        'tailoring_test_',
      );
      AppDatabase? connection;
      try {
        final file = File('${directory.path}/shop.sqlite');
        connection = AppDatabase.openFile(file);
        var persistent = DriftTailoringRepository(connection);
        final c = customer();
        final o = order(c.id, payments: [payment()]);
        await persistent.createOrder(o, newCustomer: c);
        await connection.close();
        connection = null;
        connection = AppDatabase.openFile(file);
        persistent = DriftTailoringRepository(connection);
        expect((await persistent.getCustomer(c.id))!.mobile, c.mobile);
        final restored = (await persistent.getOrder(o.id))!;
        expect(
          restored.items.single.measurements.values,
          o.items.single.measurements.values,
        );
        expect(restored.balancePaise, o.balancePaise);
        expect(await persistent.suggestBillNumber(), '8');
        expect(
          await connection.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
      } finally {
        await connection?.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
