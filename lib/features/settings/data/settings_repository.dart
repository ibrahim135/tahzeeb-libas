import 'package:drift/drift.dart';

import '../../../data/database/app_database.dart';
import '../../orders/domain/order_query.dart';
import '../domain/shop_settings.dart';

final class SettingsRepository {
  final AppDatabase database;
  SettingsRepository(this.database);
  ShopSettingsRecord _map(ShopSettingsRow row) => ShopSettingsRecord(
    name: row.name,
    address: row.address,
    contact: row.contact,
    receiptNotes: row.receiptNotes,
    updatedAt: DateTime.parse(row.updatedAt),
  );
  Future<ShopSettingsRecord> get() async =>
      _map(await database.select(database.shopSettings).getSingle());
  Stream<ShopSettingsRecord> watch() =>
      database.select(database.shopSettings).watchSingle().map(_map);
  Future<void> save(
    ShopSettingsRecord settings, {
    required DateTime expectedUpdatedAt,
  }) => database.transaction(() async {
    final current = await get();
    if (current.updatedAt != expectedUpdatedAt) throw EditConflict();
    final now = DateTime.now().toUtc();
    final timestamp = now.isAfter(current.updatedAt)
        ? now
        : current.updatedAt.add(const Duration(microseconds: 1));
    await database
        .update(database.shopSettings)
        .write(
          ShopSettingsCompanion(
            name: Value(settings.name.trim()),
            address: Value(settings.address),
            contact: Value(settings.contact),
            receiptNotes: Value(settings.receiptNotes),
            updatedAt: Value(timestamp.toIso8601String()),
          ),
        );
  });
}
