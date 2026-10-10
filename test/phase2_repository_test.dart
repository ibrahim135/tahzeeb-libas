import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tahzeeb_libas/core/value_objects.dart';
import 'package:tahzeeb_libas/data/database/app_database.dart';
import 'package:tahzeeb_libas/features/orders/application/order_draft.dart';
import 'package:tahzeeb_libas/features/orders/data/drift_tailoring_repository.dart';
import 'package:tahzeeb_libas/features/orders/domain/order_query.dart';
import 'package:tahzeeb_libas/features/orders/domain/records.dart';

import 'fixtures.dart';

OrderRecord edit(
  OrderRecord original, {
  List<GarmentItem>? items,
  String? bill,
  String? customerId,
  OrderStatus? status,
  BusinessDate? date,
  int? discount,
  DateTime? updated,
}) => OrderRecord(
  id: original.id,
  billNumber: bill ?? original.billNumber,
  customerId: customerId ?? original.customerId,
  orderDate: date ?? original.orderDate,
  deliveryDate: original.deliveryDate,
  status: status ?? original.status,
  discount: Money(discount ?? original.discount.paise),
  notes: 'Edited notes',
  createdAt: original.createdAt,
  updatedAt: updated ?? original.updatedAt.add(const Duration(seconds: 1)),
  items: items ?? original.items,
  // Deliberately omit supplied payments. Persistence must enforce its own ledger.
);
void main() {
  late AppDatabase db;
  late DriftTailoringRepository repo;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = DriftTailoringRepository(db);
  });
  tearDown(() async => db.close());
  test(
    'edits preserve the ledger and cannot lower total below actual received',
    () async {
      final c = customer();
      final o = order(c.id, payments: [payment(amount: 5000)]);
      await repo.createOrder(o, newCustomer: c);
      await expectLater(
        repo.updateOrder(
          edit(o, items: [item(price: 1)], discount: 0),
          expectedUpdatedAt: o.updatedAt,
        ),
        throwsArgumentError,
      );
      expect((await repo.getOrder(o.id))!.balancePaise, o.balancePaise);
      await repo.updateOrder(
        edit(o, bill: 'Historic-9', status: OrderStatus.delivered),
        expectedUpdatedAt: o.updatedAt,
      );
      final after = (await repo.getOrder(o.id))!;
      expect(after.payments.single.id, o.payments.single.id);
      expect(after.paidPaise, 5000);
      expect(after.status, OrderStatus.delivered);
      expect(after.paymentStatus, PaymentStatus.partiallyPaid);
    },
  );
  test(
    'stale order and customer editors cannot overwrite newer values',
    () async {
      final c = customer();
      final o = order(c.id);
      await repo.createOrder(o, newCustomer: c);
      await repo.updateOrder(
        edit(o, bill: '9'),
        expectedUpdatedAt: o.updatedAt,
      );
      await expectLater(
        repo.updateOrder(edit(o, bill: '10'), expectedUpdatedAt: o.updatedAt),
        throwsA(isA<EditConflict>()),
      );
      final changed = CustomerRecord(
        id: c.id,
        name: 'Changed',
        mobile: c.mobile,
        createdAt: c.createdAt,
        updatedAt: c.updatedAt.add(const Duration(seconds: 1)),
      );
      await repo.saveCustomer(changed, expectedUpdatedAt: c.updatedAt);
      await expectLater(
        repo.saveCustomer(c, expectedUpdatedAt: c.updatedAt),
        throwsA(isA<EditConflict>()),
      );
    },
  );
  test('editing into occupied bill rolls back new customer and preserves snapshots', () async {
    final c = customer();
    final o = order(c.id);
    await repo.createOrder(o, newCustomer: c);
    await repo.createOrder(order(c.id, bill: 'Occupied'));
    final other = customer();
    await expectLater(
      repo.updateOrder(
        edit(o, bill: 'occupied', customerId: other.id, items: [item()]),
        expectedUpdatedAt: o.updatedAt,
        newCustomer: other,
      ),
      throwsA(isA<SqliteException>()),
    );
    expect(await repo.getCustomer(other.id), isNull);
    final after = (await repo.getOrder(o.id))!;
    expect(after.items.single.id, o.items.single.id);
    expect(after.customerId, c.id);
  });
  test('measurement edits replace only the target order snapshot', () async {
    final c = customer();
    final a = order(c.id);
    final b = order(c.id, bill: '8');
    await repo.createOrder(a, newCustomer: c);
    await repo.createOrder(b);
    final draft = GarmentDraft.fromItem(a.items.single);
    draft.measurements['upper_length'] = '39.5';
    await repo.updateOrder(
      edit(
        a,
        items: [draft.build(a.updatedAt.add(const Duration(seconds: 1)))],
      ),
      expectedUpdatedAt: a.updatedAt,
    );
    expect(
      (await repo.getOrder(a.id))!
          .items
          .single
          .measurements
          .values['upper_length'],
      '39.5',
    );
    expect(
      (await repo.getOrder(b.id))!
          .items
          .single
          .measurements
          .values['upper_length'],
      '30.125',
    );
    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
  });
  test('duplicate warnings match names and either phone without enforcing uniqueness', () async {
    final c = customer(name: 'Ravi Kumar', phone: '001 234');
    await repo.saveCustomer(c);
    expect(
      (await repo.potentialDuplicates(customer(name: 'Ravi', phone: null)))
          .single
          .id,
      c.id,
    );
    expect(
      (await repo.potentialDuplicates(customer(name: 'Other', phone: '001234')))
          .single
          .id,
      c.id,
    );
    expect(
      (await repo.potentialDuplicates(
        customer(name: 'Other', phone: '910000000000'),
      )).single.id,
      c.id,
    );
    await repo.saveCustomer(customer(name: 'Ravi Kumar', phone: null));
    expect((await repo.watchCustomers(search: 'ravi').first).length, 2);
    expect((await repo.watchCustomers(search: '001234').first).single.id, c.id);
    expect((await repo.watchCustomers(search: 'Other2').first), isEmpty);
    expect((await repo.watchCustomers(search: '%').first), isEmpty);
  });
  test(
    'summaries search bill/name/either phone and aggregate multiple rows once',
    () async {
      final c = customer(name: 'Zara', phone: '001 234');
      final o = order(
        c.id,
        bill: 'H-001',
        items: [item(), item(price: 15000, quantity: 1)],
        payments: [payment(), payment(amount: 7000)],
      );
      await repo.createOrder(o, newCustomer: c);
      for (final search in ['h-001', 'zARa', '001234', '910000000000']) {
        final list = await repo.watchOrders(OrderQuery(search: search)).first;
        expect(list.single.id, o.id);
        expect(list.single.totalPaise, 35000);
        expect(list.single.paidPaise, 12000);
        expect(list.single.garments, 'Shirt × 2, Shirt × 1');
      }
      expect(await repo.watchOrders(OrderQuery(search: '%')).first, isEmpty);
      expect(
        await repo.watchOrders(OrderQuery(search: 'Zara9')).first,
        isEmpty,
      );
    },
  );
  test(
    'all payment filters, date boundaries and independent delivery status',
    () async {
      final c = customer();
      await repo.saveCustomer(c);
      final pending = order(c.id, bill: 'P');
      final partial = order(c.id, bill: 'R', payments: [payment()]);
      final paid = order(c.id, bill: 'S', payments: [payment(amount: 20000)]);
      final free = order(c.id, bill: 'F', items: [item(price: 0)], discount: 0);
      for (final o in [pending, partial, paid, free]) {
        await repo.createOrder(o);
      }
      Future<List<OrderSummary>> find(OrderQuery q) =>
          repo.watchOrders(q).first;
      expect(
        (await find(OrderQuery(paymentStatus: PaymentStatus.pending)))
            .map((o) => o.id),
        [pending.id],
      );
      expect(
        (await find(OrderQuery(paymentStatus: PaymentStatus.partiallyPaid)))
            .map((o) => o.id),
        [partial.id],
      );
      expect(
        (await find(OrderQuery(paymentStatus: PaymentStatus.paid)))
            .map((o) => o.id)
            .toSet(),
        {paid.id, free.id},
      );
      expect((await find(OrderQuery(balanceOnly: true))).length, 2);
      expect(
        (await find(
          OrderQuery(
            orderFrom: BusinessDate.parse('2025-01-01'),
            orderTo: BusinessDate.parse('2025-01-01'),
            deliveryFrom: BusinessDate.parse('2025-01-10'),
            deliveryTo: BusinessDate.parse('2025-01-10'),
          ),
        )).length,
        4,
      );
      expect(
        await find(OrderQuery(deliveryFrom: BusinessDate.parse('2025-01-11'))),
        isEmpty,
      );
      await repo.updateOrder(
        edit(partial, status: OrderStatus.ready),
        expectedUpdatedAt: partial.updatedAt,
      );
      expect(
        (await find(
          OrderQuery(
            status: OrderStatus.ready,
            paymentStatus: PaymentStatus.partiallyPaid,
          ),
        )).single.id,
        partial.id,
      );
    },
  );
  test(
    'every sorting mode is deterministic and limits/history are respected',
    () async {
      final c = customer();
      await repo.saveCustomer(c);
      final a = order(c.id, bill: 'A', items: [item(price: 1000)], discount: 0);
      final b = OrderRecord(
        id: id(),
        billNumber: 'B',
        customerId: c.id,
        orderDate: BusinessDate.parse('2025-01-02'),
        deliveryDate: BusinessDate.parse('2025-01-12'),
        discount: Money(0),
        createdAt: created.add(const Duration(days: 1)),
        updatedAt: created.add(const Duration(days: 1)),
        items: [item(price: 2000)],
      );
      await repo.createOrder(a);
      await repo.createOrder(b);
      for (final sort in OrderSort.values) {
        final rows = await repo.watchOrders(OrderQuery(sort: sort)).first;
        final descending = [
          OrderSort.newest,
          OrderSort.deliveryDesc,
          OrderSort.balanceDesc,
          OrderSort.totalDesc,
        ].contains(sort);
        expect(
          rows.map((r) => r.billNumber).toList(),
          descending ? ['B', 'A'] : ['A', 'B'],
        );
      }
      expect(
        (await repo.watchOrders(OrderQuery(customerId: c.id, limit: 1)).first)
            .length,
        1,
      );
      expect(
        await repo.watchOrders(OrderQuery(customerId: id())).first,
        isEmpty,
      );
      final tied = order(
        c.id,
        bill: 'C',
        items: [item(price: 1000)],
        discount: 0,
      );
      await repo.createOrder(tied);
      final ties =
          (await repo.watchOrders(OrderQuery(sort: OrderSort.totalAsc)).first)
              .take(2)
              .map((r) => r.id)
              .toList();
      expect(ties, [a.id, tied.id]..sort());
      expect(
        () => OrderQuery(
          orderFrom: BusinessDate.parse('2025-02-01'),
          orderTo: BusinessDate.parse('2025-01-01'),
        ),
        throwsArgumentError,
      );
    },
  );
  test('watch query refreshes after customer and order edits', () async {
    final c = customer();
    final o = order(c.id);
    await repo.createOrder(o, newCustomer: c);
    final iterator = StreamIterator(repo.watchOrders(OrderQuery()));
    expect(await iterator.moveNext(), isTrue);
    final changed = CustomerRecord(
      id: c.id,
      name: 'New Name',
      createdAt: c.createdAt,
      updatedAt: c.updatedAt.add(const Duration(seconds: 1)),
    );
    await repo.saveCustomer(changed);
    expect(await iterator.moveNext(), isTrue);
    expect(iterator.current.single.customerName, 'New Name');
    await iterator.cancel();
  });
}
