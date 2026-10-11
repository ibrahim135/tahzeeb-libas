import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tahzeeb_libas/app/providers.dart';
import 'package:tahzeeb_libas/data/database/app_database.dart';
import 'package:tahzeeb_libas/features/orders/data/drift_tailoring_repository.dart';
import 'package:tahzeeb_libas/features/orders/domain/order_query.dart';
import 'package:tahzeeb_libas/features/orders/domain/records.dart';
import 'package:tahzeeb_libas/features/orders/presentation/order_details.dart';
import 'package:tahzeeb_libas/features/orders/presentation/order_editor.dart';
import 'package:tahzeeb_libas/features/payments/presentation/payment_editor.dart';

import 'fixtures.dart';
import 'widget_helpers.dart';

Widget host(AppDatabase db, Widget child) => ProviderScope(
  overrides: [databaseProvider.overrideWithValue(db)],
  child: MaterialApp(home: child),
);

void main() {
  testWidgets('new order saves exact advance, method and notes with the bill', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = DriftTailoringRepository(db);
    final c = customer();
    await repo.saveCustomer(c);
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      host(
        db,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => OrderEditor(customer: c)),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final rate = find.byWidgetPredicate(
      (w) =>
          w is TextFormField &&
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.endsWith(':rate'),
    );
    await reveal(tester, rate);
    await tester.enterText(rate, '100.25');
    await reveal(tester, find.byKey(const Key('advanceAmount')));
    await tester.enterText(find.byKey(const Key('advanceAmount')), '20.25');
    await reveal(tester, find.byKey(const Key('advanceMethod')));
    await tester.enterText(find.byKey(const Key('advanceMethod')), 'Cash');
    await reveal(tester, find.byKey(const Key('advanceNotes')));
    await tester.enterText(
      find.byKey(const Key('advanceNotes')),
      'Advance recorded',
    );
    await reveal(tester, find.byKey(const Key('saveOrder')));
    expect(find.textContaining('Balance: ₹80.00'), findsOneWidget);
    await tester.tap(find.byKey(const Key('saveOrder')));
    await tester.pumpAndSettle();
    final list = (await tester.runAsync(
      () => repo.watchOrders(OrderQuery()).first,
    ))!;
    final saved = (await repo.getOrder(list.single.id))!;
    expect(saved.paidPaise, 2025);
    expect(saved.balancePaise, 8000);
    expect(saved.payments.single.method, 'Cash');
    expect(saved.payments.single.notes, 'Advance recorded');
    expect(saved.payments.single.date.iso, saved.orderDate.iso);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'receive, replace and void show the audited history and correct balance',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = DriftTailoringRepository(db);
      final c = customer();
      final o = order(
        c.id,
        items: [item(quantity: 1, price: 10000)],
        discount: 0,
      );
      await repo.createOrder(o, newCustomer: c);
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(host(db, OrderDetails(id: o.id)));
      await tester.pumpAndSettle();
      await reveal(tester, find.byKey(const Key('addPayment')));
      await tester.tap(find.byKey(const Key('addPayment')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('paymentAmount')), '100');
      await tester.enterText(find.byKey(const Key('paymentMethod')), 'UPI');
      await reveal(tester, find.byKey(const Key('savePayment')));
      await tester.tap(find.byKey(const Key('savePayment')));
      await tester.pumpAndSettle();
      var saved = (await repo.getOrder(o.id))!;
      expect(saved.balancePaise, 0);
      await reveal(tester, find.byKey(const Key('addPayment')));
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('addPayment')))
            .onPressed,
        isNull,
      );
      final original = saved.payments.single;
      await reveal(tester, find.byKey(ValueKey('correct:${original.id}')));
      await tester.tap(find.byKey(ValueKey('correct:${original.id}')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('paymentAmount')), '50.25');
      await reveal(tester, find.byKey(const Key('savePayment')));
      await tester.tap(find.byKey(const Key('savePayment')));
      await tester.pumpAndSettle();
      expect(find.text('Enter a correction reason'), findsOneWidget);
      await reveal(tester, find.byKey(const Key('correctionReason')));
      await tester.enterText(
        find.byKey(const Key('correctionReason')),
        'Entered wrong amount',
      );
      await reveal(tester, find.byKey(const Key('savePayment')));
      await tester.tap(find.byKey(const Key('savePayment')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Replace payment'));
      await tester.pumpAndSettle();
      saved = (await repo.getOrder(o.id))!;
      expect(saved.paidPaise, 5025);
      final active = saved.payments.firstWhere((p) => p.voidedAt == null);
      await reveal(tester, find.text('Voided · excluded from received'));
      expect(find.text('Reason: Entered wrong amount'), findsOneWidget);
      expect(find.text('Replaces payment 1'), findsOneWidget);
      await reveal(tester, find.byKey(ValueKey('correct:${active.id}')));
      await tester.tap(find.byKey(ValueKey('correct:${active.id}')));
      await tester.pumpAndSettle();
      await reveal(tester, find.byKey(const Key('correctionReason')));
      await tester.enterText(
        find.byKey(const Key('correctionReason')),
        'Duplicate entry',
      );
      await reveal(tester, find.byKey(const Key('voidPayment')));
      await tester.tap(find.byKey(const Key('voidPayment')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Void payment'));
      await tester.pumpAndSettle();
      saved = (await repo.getOrder(o.id))!;
      expect(saved.paidPaise, 0);
      expect(saved.balancePaise, 10000);
      expect(saved.payments, hasLength(2));
      expect(saved.paymentStatus, PaymentStatus.pending);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'overpayment fails visibly and payment drafts protect back navigation',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = DriftTailoringRepository(db);
      final c = customer();
      final o = order(c.id);
      await repo.createOrder(o, newCustomer: c);
      await tester.pumpWidget(
        host(
          db,
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => PaymentEditor(order: o)),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('paymentAmount')), '1000');
      await reveal(tester, find.byKey(const Key('savePayment')));
      await tester.tap(find.byKey(const Key('savePayment')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Payment exceeds the remaining balance'),
        findsWidgets,
      );
      expect((await repo.getOrder(o.id))!.payments, isEmpty);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Discard unsaved changes?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      await reveal(tester, find.byKey(const Key('paymentAmount')));
      await tester.enterText(find.byKey(const Key('paymentAmount')), '50.25');
      await reveal(tester, find.byKey(const Key('savePayment')));
      await tester.tap(find.byKey(const Key('savePayment')));
      await tester.pumpAndSettle();
      expect((await repo.getOrder(o.id))!.paidPaise, 5025);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
