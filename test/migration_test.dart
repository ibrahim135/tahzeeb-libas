import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tahzeeb_libas/data/database/app_database.dart';

import 'generated/schema.dart';

void main() {
  final verifier = SchemaVerifier(GeneratedHelper());
  test('new database matches committed v1 schema including indexes', () async {
    final db = AppDatabase(NativeDatabase.memory());
    try {
      await verifier.migrateAndValidate(db, 1);
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    } finally {
      await db.close();
    }
  });
  test(
    'opening existing v1 schema requires no destructive migration',
    () async {
      final schema = await verifier.schemaAt(1);
      final connection = schema.newConnection();
      final db = AppDatabase(connection);
      try {
        await verifier.migrateAndValidate(db, 1);
        expect(
          (await db.customSelect('PRAGMA foreign_keys').getSingle()).read<int>(
            'foreign_keys',
          ),
          1,
        );
      } finally {
        await db.close();
        schema.close();
      }
    },
  );
}
