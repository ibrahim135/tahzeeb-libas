// Drift column checks refer to generated column getters, not this DSL getter.
// ignore_for_file: recursive_getters

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

@TableIndex(name: 'customers_name', columns: {#normalizedName})
@TableIndex(name: 'customers_phone', columns: {#mobileSearch})
@TableIndex(name: 'customers_alt_phone', columns: {#alternateMobileSearch})
@DataClassName('CustomerRow')
class Customers extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().check(name.length.isBiggerThanValue(0))();
  TextColumn get normalizedName => text()();
  TextColumn get mobile => text().nullable()();
  TextColumn get mobileSearch => text().nullable()();
  TextColumn get alternateMobile => text().nullable()();
  TextColumn get alternateMobileSearch => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text()();
  @override
  Set<Column> get primaryKey => {id};
}

@TableIndex(name: 'orders_customer', columns: {#customerId})
@TableIndex(name: 'orders_date', columns: {#orderDate})
@TableIndex(name: 'orders_delivery', columns: {#deliveryDate})
@TableIndex(name: 'orders_status', columns: {#status})
@DataClassName('OrderRow')
class Orders extends Table {
  TextColumn get id => text()();
  TextColumn get billNumber =>
      text().check(billNumber.length.isBiggerThanValue(0))();
  TextColumn get billKey => text().unique()();
  TextColumn get customerId => text().references(Customers, #id)();
  TextColumn get orderDate => text()();
  TextColumn get deliveryDate => text()();
  TextColumn get status => text().check(
    status.isIn(['new', 'in_progress', 'ready', 'delivered', 'cancelled']),
  )();
  IntColumn get discountPaise =>
      integer().check(discountPaise.isBiggerOrEqualValue(0))();
  TextColumn get notes => text().nullable()();
  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text()();
  @override
  Set<Column> get primaryKey => {id};
  @override
  List<String> get customConstraints => ['CHECK(delivery_date >= order_date)'];
}

@TableIndex(name: 'items_order', columns: {#orderId})
@DataClassName('ItemRow')
class OrderItems extends Table {
  TextColumn get id => text()();
  TextColumn get orderId => text().references(Orders, #id)();
  IntColumn get position => integer().check(position.isBiggerOrEqualValue(0))();
  TextColumn get garmentType => text().check(
    garmentType.isIn([
      'sherwani',
      'suit',
      'jothpuri',
      'sadri',
      'pant',
      'shirt',
      'kurta',
      'payjama',
      'thobe',
      'joota',
      'pagdi',
    ]),
  )();
  TextColumn get variant => text().nullable()();
  IntColumn get quantity =>
      integer().check(quantity.isBetweenValues(1, 10000))();
  IntColumn get unitPricePaise =>
      integer().check(unitPricePaise.isBetweenValues(0, 100000000000))();
  TextColumn get description => text().nullable()();
  TextColumn get measurementConfig => text().check(
    measurementConfig.isIn(['upper', 'lower', 'both', 'none']),
  )();
  TextColumn get measurementUnit => text()
      .withDefault(const Constant('inches'))
      .check(measurementUnit.equals('inches'))();
  TextColumn get fittingNotes => text().nullable()();
  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text()();
  @override
  Set<Column> get primaryKey => {id};
  @override
  List<Set<Column>> get uniqueKeys => [
    {orderId, position},
  ];
}

@DataClassName('MeasurementRow')
class Measurements extends Table {
  TextColumn get itemId => text().references(OrderItems, #id)();
  TextColumn get fieldKey => text()();
  TextColumn get valueDecimal => text()();
  @override
  Set<Column> get primaryKey => {itemId, fieldKey};
}

@TableIndex(name: 'payments_order', columns: {#orderId})
@DataClassName('PaymentRow')
class Payments extends Table {
  TextColumn get id => text()();
  TextColumn get orderId => text().references(Orders, #id)();
  IntColumn get amountPaise =>
      integer().check(amountPaise.isBetweenValues(1, 100000000000))();
  TextColumn get paymentDate => text()();
  TextColumn get method => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text()();
  TextColumn get voidedAt => text().nullable()();
  TextColumn get voidReason => text().nullable()();
  TextColumn get replacesPaymentId =>
      text().nullable().references(Payments, #id)();
  @override
  Set<Column> get primaryKey => {id};
  @override
  List<String> get customConstraints => [
    'CHECK((voided_at IS NULL AND void_reason IS NULL) OR (voided_at IS NOT NULL AND void_reason IS NOT NULL AND length(trim(void_reason)) > 0))',
  ];
}

@DataClassName('ShopSettingsRow')
class ShopSettings extends Table {
  IntColumn get id => integer().check(id.equals(1))();
  TextColumn get name => text()();
  TextColumn get address => text().nullable()();
  TextColumn get contact => text().nullable()();
  TextColumn get receiptNotes => text().nullable()();
  TextColumn get updatedAt => text()();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('AppStateRow')
class AppState extends Table {
  IntColumn get id => integer().check(id.equals(1))();
  IntColumn get nextBillNumber =>
      integer().check(nextBillNumber.isBiggerThanValue(0))();
  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    Customers,
    Orders,
    OrderItems,
    Measurements,
    Payments,
    ShopSettings,
    AppState,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);
  factory AppDatabase.openFile(File file) =>
      AppDatabase(NativeDatabase.createInBackground(file));
  factory AppDatabase.production() => AppDatabase(
    LazyDatabase(() async {
      final directory = await getApplicationSupportDirectory();
      final file = File(p.join(directory.path, 'tahzeeb_libas.sqlite'));
      return NativeDatabase.createInBackground(file);
    }),
  );
  @override
  int get schemaVersion => 1;
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await into(
        appState,
      ).insert(AppStateCompanion.insert(id: const Value(1), nextBillNumber: 1));
      await into(shopSettings).insert(
        ShopSettingsCompanion.insert(
          id: const Value(1),
          name: 'Tahzeeb Libas',
          updatedAt: DateTime.now().toUtc().toIso8601String(),
        ),
      );
    },
    onUpgrade: (m, from, to) async =>
        throw StateError('No migration path from $from to $to.'),
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement('PRAGMA busy_timeout = 5000');
    },
  );
}
