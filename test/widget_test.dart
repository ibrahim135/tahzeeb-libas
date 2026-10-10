import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tahzeeb_libas/app/app.dart';
import 'package:tahzeeb_libas/app/providers.dart';
import 'package:tahzeeb_libas/data/database/app_database.dart';

void main() {
  testWidgets('navigation shell opens real database streams on a small phone', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const TahzeebApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No orders saved yet.'), findsOneWidget);
    await tester.tap(find.text('Customers'));
    await tester.pumpAndSettle();
    expect(find.text('No customers saved yet.'), findsOneWidget);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Offline storage'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
