import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tahzeeb_libas/app/app.dart';
import 'package:tahzeeb_libas/app/providers.dart';
import 'package:tahzeeb_libas/data/database/app_database.dart';
import 'package:tahzeeb_libas/features/customers/presentation/customer_editor.dart';
import 'package:tahzeeb_libas/features/orders/application/order_draft.dart';
import 'package:tahzeeb_libas/features/orders/data/drift_tailoring_repository.dart';
import 'package:tahzeeb_libas/features/orders/domain/catalog.dart';
import 'package:tahzeeb_libas/features/orders/presentation/garment_editor.dart';

import 'fixtures.dart';

import 'package:tahzeeb_libas/features/orders/domain/order_query.dart';

Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find
        .descendant(
          of: find.byType(ListView).last,
          matching: find.byType(Scrollable),
        )
        .first,
    maxScrolls: 60,
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'complete order atomically saves a new customer and optional measurements',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      tester.view.physicalSize = const Size(360, 800);
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
      await tester.tap(find.byKey(const Key('newOrder')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New customer'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('customerName')), 'Aisha');
      await tester.enterText(
        find.byKey(const Key('customerPhone')),
        '0012345678',
      );
      await reveal(tester, find.byKey(const Key('saveCustomer')));
      await tester.tap(find.byKey(const Key('saveCustomer')));
      await tester.pumpAndSettle();
      expect(await db.select(db.customers).get(), isEmpty);
      final rate = find.byWidgetPredicate(
        (w) =>
            w is TextFormField &&
            w.key is ValueKey<String> &&
            (w.key as ValueKey<String>).value.endsWith(':rate'),
      );
      await reveal(tester, rate);
      await tester.enterText(rate, '1250.50');
      final length = find.byWidgetPredicate(
        (w) =>
            w is TextFormField &&
            w.key is ValueKey<String> &&
            (w.key as ValueKey<String>).value.endsWith(':upper_length'),
      );
      await reveal(tester, length);
      await tester.enterText(length, '30.125');
      await reveal(tester, find.byKey(const Key('saveOrder')));
      await tester.tap(find.byKey(const Key('saveOrder')));
      await tester.pumpAndSettle();
      expect(find.text('Bill 1'), findsOneWidget);
      final repo = DriftTailoringRepository(db);
      final summaries = (await tester.runAsync(
        () => repo.watchOrders(OrderQuery()).first,
      ))!;
      final saved = (await repo.getOrder(summaries.single.id))!;
      expect(saved.totalPaise, 125050);
      expect(saved.items.single.measurements.values, {
        'upper_length': '30.125',
      });
      expect((await repo.getCustomer(saved.customerId))!.mobile, '0012345678');
      await tester.tap(find.byTooltip('Edit order'));
      await tester.pumpAndSettle();
      await reveal(tester, rate);
      await tester.enterText(rate, '1300.75');
      await reveal(tester, find.byKey(const Key('addGarment')));
      await tester.tap(find.byKey(const Key('addGarment')));
      await tester.pumpAndSettle();
      final secondRate = find.byWidgetPredicate(
        (w) =>
            w is TextFormField &&
            w.key is ValueKey<String> &&
            (w.key as ValueKey<String>).value.endsWith(':rate') &&
            !(w.key as ValueKey<String>).value.startsWith(
              saved.items.single.id,
            ),
      );
      await reveal(tester, secondRate);
      await tester.enterText(secondRate, '500.25');
      await reveal(tester, find.byKey(const Key('saveOrder')));
      await tester.tap(find.byKey(const Key('saveOrder')));
      await tester.pumpAndSettle();
      final edited = (await repo.getOrder(saved.id))!;
      expect(edited.totalPaise, 180100);
      expect(edited.items, hasLength(2));
      expect(edited.items.first.measurements.values['upper_length'], '30.125');
      expect(edited.items.last.measurements.values, isEmpty);
      expect(edited.items.first.id, saved.items.single.id);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'back protects unsaved customer input and discard changes no records',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CustomerEditor()),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('customerName')), 'Unsaved');
      await tester.pump();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Discard unsaved changes?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.text('Unsaved'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(await db.select(db.customers).get(), isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'duplicate customer preview permits reuse without creating another record',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = DriftTailoringRepository(db);
      final c = customer(name: 'Ravi');
      await repo.saveCustomer(c);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CustomerEditor()),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('customerName')), 'Ravi');
      await reveal(tester, find.byKey(const Key('saveCustomer')));
      await tester.tap(find.byKey(const Key('saveCustomer')));
      await tester.pumpAndSettle();
      expect(find.text('Possible existing customer'), findsOneWidget);
      await tester.tap(find.widgetWithText(ListTile, 'Ravi'));
      await tester.pumpAndSettle();
      expect(
        (await tester.runAsync(() => repo.watchCustomers().first))!.length,
        1,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'disabling populated measurement section requires explicit confirmation',
    (tester) async {
      final draft = GarmentDraft.empty();
      draft.measurements['upper_length'] = '30';
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              body: Form(
                child: ListView(
                  children: [
                    GarmentEditor(
                      draft: draft,
                      number: 1,
                      changed: () => setState(() {}),
                      remove: () {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      final config = find.byType(
        DropdownButtonFormField<MeasurementConfiguration>,
      );
      await reveal(tester, config);
      await tester.tap(config);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lower body').last);
      await tester.pumpAndSettle();
      expect(find.text('Clear disabled measurements?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(draft.configuration, MeasurementConfiguration.upper);
      expect(draft.measurements['upper_length'], '30');
      await reveal(tester, config);
      await tester.tap(config);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lower body').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear section'));
      await tester.pumpAndSettle();
      expect(draft.configuration, MeasurementConfiguration.lower);
      expect(draft.measurements, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
