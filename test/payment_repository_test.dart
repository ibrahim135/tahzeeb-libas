import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tahzeeb_libas/core/value_objects.dart';
import 'package:tahzeeb_libas/data/database/app_database.dart';
import 'package:tahzeeb_libas/features/orders/application/order_draft.dart';
import 'package:tahzeeb_libas/features/orders/data/drift_tailoring_repository.dart';
import 'package:tahzeeb_libas/features/orders/domain/order_query.dart';
import 'package:tahzeeb_libas/features/orders/domain/records.dart';

import 'fixtures.dart';

PaymentRecord receipt({
  int amount = 5000,
  String date = '2025-01-02',
  String? paymentId,
}) => PaymentRecord(
  id: paymentId ?? id(),
  amount: Money(amount),
  date: BusinessDate.parse(date),
  method: 'UPI',
  notes: 'Historic received\nSecond line',
  createdAt: created,
  updatedAt: created,
);

void main() {
  late AppDatabase db;
  late DriftTailoringRepository repo;
  late CustomerRecord c;
  late OrderRecord o;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = DriftTailoringRepository(db);
    c = customer();
    // Two garments, exact decimal rates and a fixed discount: net ₹250.25.
    o = order(
      c.id,
      items: [item(quantity: 2, price: 10025), item(quantity: 1, price: 5025)],
      discount: 50,
    );
    await repo.createOrder(o, newCustomer: c);
  });
  tearDown(() => db.close());

  test(
    'additional dated payments give exact partial and fully paid balances',
    () async {
      final first = receipt(amount: 5025);
      await repo.addPayment(o.id, first);
      var saved = (await repo.getOrder(o.id))!;
      expect(saved.totalPaise, 25025);
      expect(saved.paidPaise, 5025);
      expect(saved.balancePaise, 20000);
      expect(saved.paymentStatus, PaymentStatus.partiallyPaid);
      expect(saved.payments.single.date.iso, '2025-01-02');
      expect(saved.payments.single.notes, first.notes);
      expect(saved.updatedAt.isAfter(o.updatedAt), isTrue);
      await repo.addPayment(o.id, receipt(amount: 20000, date: '2025-01-03'));
      saved = (await repo.getOrder(o.id))!;
      expect(saved.paymentStatus, PaymentStatus.paid);
      expect(saved.balancePaise, 0);
      expect(saved.payments, hasLength(2));
      expect(
        saved.items.first.measurements.values,
        o.items.first.measurements.values,
      );
    },
  );

  test('overpayments, duplicate IDs and invalid historical dates write nothing', () async {
    await expectLater(
      repo.addPayment(o.id, receipt(amount: 25026)),
      throwsArgumentError,
    );
    await expectLater(
      repo.addPayment(o.id, receipt(date: '2024-12-31')),
      throwsArgumentError,
    );
    final tomorrow = DateTime.now().add(const Duration(days: 2));
    final future =
        '${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}';
    await expectLater(
      repo.addPayment(o.id, receipt(date: future)),
      throwsArgumentError,
    );
    expect((await repo.getOrder(o.id))!.payments, isEmpty);
    expect((await repo.getOrder(o.id))!.updatedAt, o.updatedAt);
    final p = receipt();
    await repo.addPayment(o.id, p);
    await expectLater(repo.addPayment(o.id, p), throwsArgumentError);
    expect((await repo.getOrder(o.id))!.paidPaise, 5000);
    expect(() => receipt(amount: 0), throwsArgumentError);
    expect(() => receipt(amount: -1), throwsArgumentError);
  });

  test(
    'overlapping payment requests cannot overpay the current ledger',
    () async {
      final outcomes = await Future.wait([
        for (var i = 0; i < 2; i++)
          repo
              .addPayment(o.id, receipt(amount: 15000))
              .then<Object?>((_) => null, onError: (Object e) => e),
      ]);
      expect(outcomes.where((v) => v == null), hasLength(1));
      expect(outcomes.whereType<ArgumentError>(), hasLength(1));
      final saved = (await repo.getOrder(o.id))!;
      expect(saved.payments, hasLength(1));
      expect(saved.balancePaise, 10025);
    },
  );

  test(
    'replace preserves the original and links the exact dated replacement',
    () async {
      final p = receipt(amount: 5025);
      await repo.addPayment(o.id, p);
      final replacement = receipt(amount: 3025, date: '2025-01-01');
      await repo.correctPayment(
        o.id,
        p.id,
        expectedUpdatedAt: p.updatedAt,
        reason: ' Wrong amount entered ',
        replacement: replacement,
      );
      final saved = (await repo.getOrder(o.id))!;
      final original = saved.payments.firstWhere((v) => v.id == p.id);
      final active = saved.payments.firstWhere((v) => v.id == replacement.id);
      expect(original.amount.paise, p.amount.paise);
      expect(original.date.iso, p.date.iso);
      expect(original.method, p.method);
      expect(original.notes, p.notes);
      expect(original.createdAt, p.createdAt);
      expect(original.voidReason, 'Wrong amount entered');
      expect(original.voidedAt, original.updatedAt);
      expect(active.replacesPaymentId, p.id);
      expect(active.date.iso, '2025-01-01');
      expect(saved.paidPaise, 3025);
      expect(saved.balancePaise, 22000);
      expect(saved.payments, hasLength(2));
    },
  );

  test('void and further corrections retain the chain without changing delivery status', () async {
    final original = receipt();
    final delivered = OrderRecord(
      id: o.id,
      billNumber: o.billNumber,
      customerId: c.id,
      orderDate: o.orderDate,
      deliveryDate: o.deliveryDate,
      status: OrderStatus.delivered,
      discount: o.discount,
      createdAt: o.createdAt,
      updatedAt: o.updatedAt.add(const Duration(seconds: 1)),
      items: o.items,
    );
    await repo.updateOrder(delivered, expectedUpdatedAt: o.updatedAt);
    await repo.addPayment(o.id, original);
    final received = (await repo.getOrder(o.id))!;
    expect(received.status, OrderStatus.delivered);
    expect(received.paidPaise, 5000);
    final cancelled = OrderDraft(original: received, customer: c)
      ..status = OrderStatus.cancelled;
    await repo.updateOrder(
      cancelled.build(
        bill: received.billNumber,
        discount: received.discount.decimal,
        notes: '',
      ),
      expectedUpdatedAt: received.updatedAt,
    );
    expect((await repo.getOrder(o.id))!.paidPaise, 5000);
    final next = receipt(amount: 6000);
    await repo.correctPayment(
      o.id,
      original.id,
      expectedUpdatedAt: original.updatedAt,
      reason: 'Amount correction',
      replacement: next,
    );
    await repo.correctPayment(
      o.id,
      next.id,
      expectedUpdatedAt: next.updatedAt,
      reason: 'Duplicate entry',
    );
    final saved = (await repo.getOrder(o.id))!;
    expect(saved.paidPaise, 0);
    expect(saved.balancePaise, saved.totalPaise);
    expect(saved.paymentStatus, PaymentStatus.pending);
    expect(saved.status, OrderStatus.cancelled);
    expect(saved.payments.every((p) => p.voidedAt != null), isTrue);
    expect(
      saved.payments.firstWhere((p) => p.id == next.id).replacesPaymentId,
      original.id,
    );
  });

  test(
    'invalid corrections do not alter the original or other payments',
    () async {
      final p = receipt(amount: 5000);
      await repo.addPayment(o.id, p);
      await repo.addPayment(o.id, receipt(amount: 10000));
      final before = (await repo.getOrder(o.id))!;
      await expectLater(
        repo.correctPayment(
          o.id,
          p.id,
          expectedUpdatedAt: p.updatedAt,
          reason: '',
          replacement: receipt(),
        ),
        throwsArgumentError,
      );
      await expectLater(
        repo.correctPayment(
          o.id,
          p.id,
          expectedUpdatedAt: p.updatedAt,
          reason: 'Mistake',
          replacement: receipt(amount: 15026),
        ),
        throwsArgumentError,
      );
      await expectLater(
        repo.correctPayment(
          o.id,
          p.id,
          expectedUpdatedAt: p.updatedAt,
          reason: 'Mistake',
          replacement: receipt(date: '2024-01-01'),
        ),
        throwsArgumentError,
      );
      await expectLater(
        repo.correctPayment(
          o.id,
          p.id,
          expectedUpdatedAt: p.updatedAt.add(const Duration(seconds: 1)),
          reason: 'Stale',
        ),
        throwsA(isA<EditConflict>()),
      );
      final saved = (await repo.getOrder(o.id))!;
      expect(saved.updatedAt, before.updatedAt);
      expect(saved.paidPaise, 15000);
      expect(saved.payments.every((v) => v.voidedAt == null), isTrue);
      await repo.correctPayment(
        o.id,
        p.id,
        expectedUpdatedAt: p.updatedAt,
        reason: 'Mistake',
      );
      await expectLater(
        repo.correctPayment(
          o.id,
          p.id,
          expectedUpdatedAt: p.updatedAt,
          reason: 'Again',
        ),
        throwsA(isA<EditConflict>()),
      );
    },
  );

  test(
    'late replacement insert failure rolls back voiding and order timestamp',
    () async {
      final p = receipt();
      await repo.addPayment(o.id, p);
      final other = order(c.id, bill: '8', payments: [receipt()]);
      await repo.createOrder(other);
      final before = (await repo.getOrder(o.id))!;
      final collision = receipt(
        paymentId: other.payments.single.id,
        amount: 3000,
      );
      await expectLater(
        repo.correctPayment(
          o.id,
          p.id,
          expectedUpdatedAt: p.updatedAt,
          reason: 'Wrong entry',
          replacement: collision,
        ),
        throwsA(isA<SqliteException>()),
      );
      final saved = (await repo.getOrder(o.id))!;
      expect(saved.updatedAt, before.updatedAt);
      expect(saved.payments.single.voidedAt, isNull);
      expect(saved.payments.single.voidReason, isNull);
      expect(saved.paidPaise, p.amount.paise);
      expect((await repo.getOrder(other.id))!.paidPaise, other.paidPaise);
    },
  );

  test(
    'payment order references and correction-only payloads are enforced',
    () async {
      await expectLater(repo.addPayment(id(), receipt()), throwsArgumentError);
      final p = receipt();
      await repo.addPayment(o.id, p);
      final other = order(c.id, bill: '8');
      await repo.createOrder(other);
      await expectLater(
        repo.correctPayment(
          other.id,
          p.id,
          expectedUpdatedAt: p.updatedAt,
          reason: 'Different bill',
        ),
        throwsArgumentError,
      );
      final forged = PaymentRecord(
        id: id(),
        amount: Money(100),
        date: p.date,
        createdAt: created,
        updatedAt: created,
        voidedAt: created,
        voidReason: 'Bypass',
      );
      await expectLater(repo.addPayment(o.id, forged), throwsArgumentError);
      final linked = PaymentRecord(
        id: id(),
        amount: Money(100),
        date: p.date,
        createdAt: created,
        updatedAt: created,
        replacesPaymentId: p.id,
      );
      await expectLater(repo.addPayment(o.id, linked), throwsArgumentError);
      expect((await repo.getOrder(o.id))!.payments, hasLength(1));
    },
  );

  test('payment writes invalidate stale order edits and reject total below received', () async {
    final oldDraft = OrderDraft(original: o, customer: c);
    await repo.addPayment(o.id, receipt(amount: 20000));
    await expectLater(
      repo.updateOrder(
        oldDraft.build(
          bill: o.billNumber,
          discount: o.discount.decimal,
          notes: '',
        ),
        expectedUpdatedAt: o.updatedAt,
      ),
      throwsA(isA<EditConflict>()),
    );
    final current = (await repo.getOrder(o.id))!;
    final edit = OrderDraft(original: current, customer: c);
    expect(
      () => edit.build(bill: o.billNumber, discount: '200', notes: ''),
      throwsArgumentError,
    );
    expect((await repo.getOrder(o.id))!.totalPaise, o.totalPaise);
    // Voiding the erroneous payment permits a subsequent legitimate price edit.
    final p = current.payments.single;
    await repo.correctPayment(
      o.id,
      p.id,
      expectedUpdatedAt: p.updatedAt,
      reason: 'Entered on wrong bill',
    );
    final fresh = (await repo.getOrder(o.id))!;
    final corrected = OrderDraft(
      original: fresh,
      customer: c,
    ).build(bill: o.billNumber, discount: '200', notes: '');
    await repo.updateOrder(corrected, expectedUpdatedAt: fresh.updatedAt);
    expect((await repo.getOrder(o.id))!.paidPaise, 0);
  });

  test('payment filters and summaries react to additions and voids', () async {
    final paid = repo.watchOrders(
      OrderQuery(paymentStatus: PaymentStatus.paid),
    );
    expect(await paid.first, isEmpty);
    final added = paid.firstWhere((list) => list.isNotEmpty);
    final p = receipt(amount: o.totalPaise);
    await repo.addPayment(o.id, p);
    expect((await added).single.balancePaise, 0);
    final removed = paid.firstWhere((list) => list.isEmpty);
    await repo.correctPayment(
      o.id,
      p.id,
      expectedUpdatedAt: p.updatedAt,
      reason: 'Not actually received',
    );
    expect(await removed, isEmpty);
    expect(
      (await repo
              .watchOrders(OrderQuery(paymentStatus: PaymentStatus.pending))
              .first)
          .single
          .id,
      o.id,
    );
  });

  test(
    'zero-total orders stay paid and cannot receive a positive payment',
    () async {
      final free = order(
        c.id,
        bill: 'FREE',
        items: [item(price: 0)],
        discount: 0,
      );
      await repo.createOrder(free);
      expect((await repo.getOrder(free.id))!.paymentStatus, PaymentStatus.paid);
      await expectLater(
        repo.addPayment(free.id, receipt(amount: 1)),
        throwsArgumentError,
      );
      expect((await repo.getOrder(free.id))!.payments, isEmpty);
    },
  );

  test(
    'failed order with advance rolls back new customer and ledger together',
    () async {
      final other = customer();
      final draft = OrderDraft(customer: other)..isNewCustomer = true;
      draft.garments.single.rate = '100';
      final duplicate = draft.build(
        bill: o.billNumber,
        discount: '0',
        notes: '',
        advance: '50',
      );
      await expectLater(
        repo.createOrder(duplicate, newCustomer: other),
        throwsA(isA<SqliteException>()),
      );
      expect(await repo.getCustomer(other.id), isNull);
      expect(await repo.getOrder(duplicate.id), isNull);
      expect(await db.select(db.payments).get(), isEmpty);
      expect(await repo.suggestBillNumber(), '8');
    },
  );

  test(
    'correction history survives file-backed close and reopen on schema v1',
    () async {
      await db.close();
      final directory = await Directory.systemTemp.createTemp(
        'payment_restart_',
      );
      AppDatabase? persistent;
      try {
        final file = File('${directory.path}/shop.sqlite');
        persistent = AppDatabase.openFile(file);
        var savedRepo = DriftTailoringRepository(persistent);
        await savedRepo.createOrder(o, newCustomer: c);
        final original = receipt(amount: 7000);
        final replacement = receipt(amount: 5025);
        await savedRepo.addPayment(o.id, original);
        await savedRepo.correctPayment(
          o.id,
          original.id,
          expectedUpdatedAt: original.updatedAt,
          reason: 'Corrected historic receipt',
          replacement: replacement,
        );
        await persistent.close();
        persistent = AppDatabase.openFile(file);
        savedRepo = DriftTailoringRepository(persistent);
        final saved = (await savedRepo.getOrder(o.id))!;
        expect(saved.payments, hasLength(2));
        expect(saved.paidPaise, 5025);
        expect(
          saved.payments.firstWhere((p) => p.id == original.id).voidReason,
          'Corrected historic receipt',
        );
        expect(
          saved.payments
              .firstWhere((p) => p.id == replacement.id)
              .replacesPaymentId,
          original.id,
        );
        expect(persistent.schemaVersion, 1);
        expect(
          await persistent.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
      } finally {
        await persistent?.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
