import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tahzeeb_libas/data/database/app_database.dart';
import 'package:tahzeeb_libas/features/settings/data/settings_repository.dart';
import 'package:tahzeeb_libas/features/settings/domain/shop_settings.dart';
import 'package:tahzeeb_libas/features/documents/data/document_repository.dart';
import 'package:tahzeeb_libas/features/orders/data/drift_tailoring_repository.dart';
import 'package:tahzeeb_libas/features/orders/domain/order_query.dart';
import 'package:tahzeeb_libas/features/transfer/data/drift_workbook_repository.dart';

import 'fixtures.dart' as f;

void main() {
  late AppDatabase db;
  late SettingsRepository settings;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    settings = SettingsRepository(db);
  });
  tearDown(() => db.close());
  test(
    'settings updates are reactive and stale editors cannot overwrite them',
    () async {
      final initial = await settings.get();
      final changed = settings.watch().firstWhere((s) => s.name == 'New shop');
      await settings.save(
        ShopSettingsRecord(
          name: ' New shop ',
          address: 'Line 1\nLine 2',
          contact: '001234',
          receiptNotes: 'Thank you',
          updatedAt: initial.updatedAt,
        ),
        expectedUpdatedAt: initial.updatedAt,
      );
      final saved = await changed;
      expect(saved.updatedAt.isAfter(initial.updatedAt), isTrue);
      expect(saved.address, 'Line 1\nLine 2');
      expect(saved.contact, '001234');
      await expectLater(
        settings.save(initial, expectedUpdatedAt: initial.updatedAt),
        throwsA(isA<EditConflict>()),
      );
      expect((await settings.get()).name, 'New shop');
      expect(
        () => ShopSettingsRecord(name: ' ', updatedAt: f.created),
        throwsArgumentError,
      );
    },
  );
  test('document snapshot is fresh, consistent, and remains immutable after payment', () async {
    final orders = DriftTailoringRepository(db);
    final c = f.customer();
    final o = f.order(c.id);
    await orders.createOrder(o, newCustomer: c);
    final docs = DocumentRepository(db);
    final before = await docs.load(o.id);
    await orders.addPayment(o.id, f.payment());
    final after = await docs.load(o.id);
    expect(before.order.paidPaise, 0);
    expect(after.order.paidPaise, 5000);
    expect(after.customer.id, c.id);
    expect(after.shop.name, (await settings.get()).name);
    await expectLater(docs.load(f.id()), throwsFormatException);
  });
  test(
    'settings editing invalidates already prepared Excel import previews',
    () async {
      final books = DriftWorkbookRepository(db);
      final workbook = await books.snapshot();
      final preview = await books.preview(workbook);
      final initial = await settings.get();
      await settings.save(
        ShopSettingsRecord(name: 'Changed shop', updatedAt: initial.updatedAt),
        expectedUpdatedAt: initial.updatedAt,
      );
      await expectLater(books.commit(preview), throwsStateError);
      expect((await settings.get()).name, 'Changed shop');
    },
  );
  test(
    'shop details survive restart and remain fully included in Excel backup',
    () async {
      // Close the setUp database before another connection is created.
      await db.close();
      final dir = await Directory.systemTemp.createTemp('tahzeeb_settings_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/records.sqlite');
      db = AppDatabase.openFile(file);
      settings = SettingsRepository(db);
      final initial = await settings.get();
      await settings.save(
        ShopSettingsRecord(
          name: 'Offline shop',
          address: 'Shop address',
          contact: '0012300',
          receiptNotes: 'Receipt only',
          updatedAt: initial.updatedAt,
        ),
        expectedUpdatedAt: initial.updatedAt,
      );
      final expected = await settings.get();
      await db.close();
      db = AppDatabase.openFile(file);
      settings = SettingsRepository(db);
      final saved = await settings.get();
      expect(saved.name, expected.name);
      expect(saved.address, expected.address);
      expect(saved.contact, expected.contact);
      expect(saved.receiptNotes, expected.receiptNotes);
      expect(saved.updatedAt, expected.updatedAt);
      final export = await DriftWorkbookRepository(db).snapshot();
      final row = export.rows('ShopSettings').single.values;
      expect(row['name'], saved.name);
      expect(row['receipt_notes'], saved.receiptNotes);
      expect(row['updated_at'], saved.updatedAt.toIso8601String());
    },
  );
}
