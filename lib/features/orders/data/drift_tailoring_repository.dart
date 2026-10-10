import 'package:drift/drift.dart';

import '../../../core/value_objects.dart';
import '../../../data/database/app_database.dart';
import '../domain/catalog.dart';
import '../domain/records.dart';
import '../domain/repository.dart';
import '../domain/order_query.dart';

final class DriftTailoringRepository implements TailoringRepository {
  final AppDatabase db;
  DriftTailoringRepository(this.db);

  @override
  Future<void> saveCustomer(
    CustomerRecord customer, {
    DateTime? expectedUpdatedAt,
  }) => db.transaction(() async {
    final previous = await getCustomer(customer.id);
    if (expectedUpdatedAt != null && previous?.updatedAt != expectedUpdatedAt) {
      throw const EditConflict();
    }
    if (previous != null &&
        (previous.createdAt != customer.createdAt ||
            customer.updatedAt.isBefore(previous.updatedAt))) {
      throw ArgumentError('Customer history timestamps cannot move backwards.');
    }
    await db.into(db.customers).insertOnConflictUpdate(_customer(customer));
  });

  CustomersCompanion _customer(CustomerRecord c) => CustomersCompanion.insert(
    id: c.id,
    name: c.name,
    normalizedName: normalizeName(c.name),
    mobile: Value(c.mobile),
    mobileSearch: Value(phoneSearch(c.mobile)),
    alternateMobile: Value(c.alternateMobile),
    alternateMobileSearch: Value(phoneSearch(c.alternateMobile)),
    address: Value(c.address),
    notes: Value(c.notes),
    createdAt: c.createdAt.toIso8601String(),
    updatedAt: c.updatedAt.toIso8601String(),
  );
  CustomerRecord _customerRecord(CustomerRow r) => CustomerRecord(
    id: r.id,
    name: r.name,
    mobile: r.mobile,
    alternateMobile: r.alternateMobile,
    address: r.address,
    notes: r.notes,
    createdAt: DateTime.parse(r.createdAt),
    updatedAt: DateTime.parse(r.updatedAt),
  );
  @override
  Future<CustomerRecord?> getCustomer(String id) async {
    final row = await (db.select(
      db.customers,
    )..where((c) => c.id.equals(id))).getSingleOrNull();
    return row == null ? null : _customerRecord(row);
  }

  @override
  Stream<List<CustomerRecord>> watchCustomers({String search = ''}) =>
      (db.select(db.customers)
            ..where((c) {
              final text = normalizeName(search);
              final phone = RegExp(r'^[+0-9 ()-]+$').hasMatch(search)
                  ? phoneSearch(search)
                  : null;
              final escaped = text
                  .replaceAll('\\', '\\\\')
                  .replaceAll('%', '\\%')
                  .replaceAll('_', '\\_');
              final pattern = '%$escaped%';
              final name = c.normalizedName.like(pattern, escapeChar: '\\');
              return phone == null
                  ? name
                  : name |
                        c.mobileSearch.contains(phone) |
                        c.alternateMobileSearch.contains(phone);
            })
            ..orderBy([
              (c) => OrderingTerm.asc(c.normalizedName),
              (c) => OrderingTerm.asc(c.id),
            ]))
          .watch()
          .map((rows) => rows.map(_customerRecord).toList(growable: false));

  @override
  Future<void> createOrder(
    OrderRecord order, {
    CustomerRecord? newCustomer,
  }) => db.transaction(() async {
    if (newCustomer != null) {
      if (newCustomer.id != order.customerId) {
        throw ArgumentError('Order customer mismatch.');
      }
      // Insert only: creating an order must never overwrite an existing customer.
      await db.into(db.customers).insert(_customer(newCustomer));
    }
    await db
        .into(db.orders)
        .insert(
          OrdersCompanion.insert(
            id: order.id,
            billNumber: order.billNumber,
            billKey: billKey(order.billNumber),
            customerId: order.customerId,
            orderDate: order.orderDate.iso,
            deliveryDate: order.deliveryDate.iso,
            status: order.status.id,
            discountPaise: order.discount.paise,
            notes: Value(order.notes),
            createdAt: order.createdAt.toIso8601String(),
            updatedAt: order.updatedAt.toIso8601String(),
          ),
        );
    await _insertItems(order);
    for (final payment in order.payments) {
      await db
          .into(db.payments)
          .insert(
            PaymentsCompanion.insert(
              id: payment.id,
              orderId: order.id,
              amountPaise: payment.amount.paise,
              paymentDate: payment.date.iso,
              method: Value(payment.method),
              notes: Value(payment.notes),
              createdAt: payment.createdAt.toIso8601String(),
              updatedAt: payment.updatedAt.toIso8601String(),
              voidedAt: Value(payment.voidedAt?.toIso8601String()),
              voidReason: Value(payment.voidReason),
            ),
          );
    }
    // Resolve references after all payments exist, independent of list order.
    for (final payment in order.payments.where(
      (p) => p.replacesPaymentId != null,
    )) {
      await (db.update(
        db.payments,
      )..where((p) => p.id.equals(payment.id))).write(
        PaymentsCompanion(replacesPaymentId: Value(payment.replacesPaymentId)),
      );
    }
    final numeric = int.tryParse(order.billNumber);
    final state = await db.select(db.appState).getSingle();
    if (numeric != null &&
        numeric >= state.nextBillNumber &&
        numeric < 1000000000000) {
      await db
          .update(db.appState)
          .write(AppStateCompanion(nextBillNumber: Value(numeric + 1)));
    }
  });

  Future<void> _insertItems(OrderRecord order) async {
    for (var index = 0; index < order.items.length; index++) {
      final item = order.items[index];
      await db
          .into(db.orderItems)
          .insert(
            OrderItemsCompanion.insert(
              id: item.id,
              orderId: order.id,
              position: index,
              garmentType: item.type.name,
              variant: Value(item.variant),
              quantity: item.quantity,
              unitPricePaise: item.unitPrice.paise,
              description: Value(item.description),
              measurementConfig: item.measurements.configuration.name,
              fittingNotes: Value(item.fittingNotes),
              createdAt: item.createdAt.toIso8601String(),
              updatedAt: item.updatedAt.toIso8601String(),
            ),
          );
      for (final measurement in item.measurements.values.entries) {
        await db
            .into(db.measurements)
            .insert(
              MeasurementsCompanion.insert(
                itemId: item.id,
                fieldKey: measurement.key,
                valueDecimal: measurement.value,
              ),
            );
      }
    }
  }

  @override
  Future<OrderRecord?> getOrder(String id) => db.transaction(() async {
    final row = await (db.select(
      db.orders,
    )..where((o) => o.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    final rows =
        await (db.select(db.orderItems)
              ..where((i) => i.orderId.equals(id))
              ..orderBy([(i) => OrderingTerm.asc(i.position)]))
            .get();
    final items = <GarmentItem>[];
    for (final item in rows) {
      final measurements = await (db.select(
        db.measurements,
      )..where((m) => m.itemId.equals(item.id))).get();
      items.add(
        GarmentItem(
          id: item.id,
          type: GarmentType.values.byName(item.garmentType),
          variant: item.variant,
          quantity: item.quantity,
          unitPrice: Money(item.unitPricePaise),
          description: item.description,
          measurements: MeasurementSnapshot(
            MeasurementConfiguration.values.byName(item.measurementConfig),
            {for (final m in measurements) m.fieldKey: m.valueDecimal},
          ),
          fittingNotes: item.fittingNotes,
          createdAt: DateTime.parse(item.createdAt),
          updatedAt: DateTime.parse(item.updatedAt),
        ),
      );
    }
    final payments =
        await (db.select(db.payments)
              ..where((p) => p.orderId.equals(id))
              ..orderBy([
                (p) => OrderingTerm.asc(p.paymentDate),
                (p) => OrderingTerm.asc(p.id),
              ]))
            .get();
    return OrderRecord(
      id: row.id,
      billNumber: row.billNumber,
      customerId: row.customerId,
      orderDate: BusinessDate.parse(row.orderDate),
      deliveryDate: BusinessDate.parse(row.deliveryDate),
      status: OrderStatus.fromId(row.status),
      discount: Money(row.discountPaise),
      notes: row.notes,
      createdAt: DateTime.parse(row.createdAt),
      updatedAt: DateTime.parse(row.updatedAt),
      items: items,
      payments: payments
          .map(
            (p) => PaymentRecord(
              id: p.id,
              amount: Money(p.amountPaise),
              date: BusinessDate.parse(p.paymentDate),
              method: p.method,
              notes: p.notes,
              createdAt: DateTime.parse(p.createdAt),
              updatedAt: DateTime.parse(p.updatedAt),
              voidedAt: p.voidedAt == null ? null : DateTime.parse(p.voidedAt!),
              voidReason: p.voidReason,
              replacesPaymentId: p.replacesPaymentId,
            ),
          )
          .toList(),
    );
  });
  @override
  Stream<int> watchOrderCount() {
    final count = db.orders.id.count();
    return (db.selectOnly(
      db.orders,
    )..addColumns([count])).watchSingle().map((r) => r.read(count)!);
  }

  @override
  Future<String> suggestBillNumber() => db.transaction(() async {
    var next = (await db.select(db.appState).getSingle()).nextBillNumber;
    while (await (db.select(
          db.orders,
        )..where((o) => o.billKey.equals('$next'))).getSingleOrNull() !=
        null) {
      next++;
    }
    if (next >= 1000000000000) {
      throw StateError(
        'Automatic bill number range exhausted. Enter a unique historic bill number.',
      );
    }
    return '$next';
  });
  @override
  Future<List<CustomerRecord>> potentialDuplicates(
    CustomerRecord customer,
  ) async {
    final rows =
        await (db.select(db.customers)..orderBy([
              (c) => OrderingTerm.asc(c.normalizedName),
              (c) => OrderingTerm.asc(c.id),
            ]))
            .get();
    final all = rows.map(_customerRecord);
    final key = normalizeName(customer.name);
    final phones = [
      phoneSearch(customer.mobile),
      phoneSearch(customer.alternateMobile),
    ].whereType<String>().toSet();
    return all.where((other) {
      if (other.id == customer.id) return false;
      final otherName = normalizeName(other.name);
      return otherName == key ||
          (key.length >= 3 &&
              (otherName.contains(key) || key.contains(otherName))) ||
          phones.contains(phoneSearch(other.mobile)) ||
          phones.contains(phoneSearch(other.alternateMobile));
    }).toList();
  }

  @override
  Future<void> updateOrder(
    OrderRecord proposed, {
    required DateTime expectedUpdatedAt,
    CustomerRecord? newCustomer,
  }) => db.transaction(() async {
    final current = await getOrder(proposed.id);
    if (current == null || current.updatedAt != expectedUpdatedAt) {
      throw const EditConflict();
    }
    if (proposed.createdAt != current.createdAt ||
        !proposed.updatedAt.isAfter(current.updatedAt)) {
      throw ArgumentError(
        'Order timestamps must preserve creation and advance on edit.',
      );
    }
    // Rebuild with the actual ledger inside the transaction. A caller cannot erase
    // payments or bypass the below-received guard using a stale/empty payment list.
    final order = OrderRecord(
      id: proposed.id,
      billNumber: proposed.billNumber,
      customerId: proposed.customerId,
      orderDate: proposed.orderDate,
      deliveryDate: proposed.deliveryDate,
      status: proposed.status,
      discount: proposed.discount,
      notes: proposed.notes,
      createdAt: current.createdAt,
      updatedAt: proposed.updatedAt,
      items: proposed.items,
      payments: current.payments,
    );
    if (newCustomer != null) {
      if (newCustomer.id != proposed.customerId) {
        throw ArgumentError('Order customer mismatch.');
      }
      await db.into(db.customers).insert(_customer(newCustomer));
    }
    final existingIds = current.items.map((i) => i.id).toSet();
    for (final item in order.items.where((i) => existingIds.contains(i.id))) {
      final before = current.items.firstWhere((i) => i.id == item.id);
      if (item.createdAt != before.createdAt ||
          item.updatedAt.isBefore(before.updatedAt)) {
        throw ArgumentError('Item history timestamps cannot move backwards.');
      }
    }
    await (db.update(db.orders)..where((o) => o.id.equals(order.id))).write(
      OrdersCompanion(
        billNumber: Value(order.billNumber),
        billKey: Value(billKey(order.billNumber)),
        customerId: Value(order.customerId),
        orderDate: Value(order.orderDate.iso),
        deliveryDate: Value(order.deliveryDate.iso),
        status: Value(order.status.id),
        discountPaise: Value(order.discount.paise),
        notes: Value(order.notes),
        updatedAt: Value(order.updatedAt.toIso8601String()),
      ),
    );
    for (final old in current.items) {
      await (db.delete(
        db.measurements,
      )..where((m) => m.itemId.equals(old.id))).go();
    }
    await (db.delete(
      db.orderItems,
    )..where((i) => i.orderId.equals(order.id))).go();
    await _insertItems(order);
    final numeric = int.tryParse(order.billNumber);
    final state = await db.select(db.appState).getSingle();
    if (numeric != null &&
        numeric >= state.nextBillNumber &&
        numeric < 1000000000000) {
      await db
          .update(db.appState)
          .write(AppStateCompanion(nextBillNumber: Value(numeric + 1)));
    }
  });

  @override
  Stream<List<OrderSummary>> watchOrders(OrderQuery query) {
    final clauses = <String>[];
    final parameters = <Variable>[];
    void condition(String sql, String value) {
      clauses.add(sql);
      parameters.add(Variable(value));
    }

    if (query.customerId != null) {
      condition('customer_id = ?', query.customerId!);
    }
    for (final pair in [
      ('order_date >= ?', query.orderFrom),
      ('order_date <= ?', query.orderTo),
      ('delivery_date >= ?', query.deliveryFrom),
      ('delivery_date <= ?', query.deliveryTo),
    ]) {
      if (pair.$2 != null) condition(pair.$1, pair.$2!.iso);
    }
    if (query.status != null) condition('status = ?', query.status!.id);
    if (query.balanceOnly) clauses.add('total - paid > 0');
    if (query.paymentStatus != null) {
      clauses.add(switch (query.paymentStatus!) {
        PaymentStatus.pending => 'paid = 0 AND total > 0',
        PaymentStatus.partiallyPaid => 'paid > 0 AND paid < total',
        PaymentStatus.paid => 'paid = total',
      });
    }
    final search = normalizeName(query.search);
    if (search.isNotEmpty) {
      final escaped = search
          .replaceAll('\\', '\\\\')
          .replaceAll('%', '\\%')
          .replaceAll('_', '\\_');
      final phone = RegExp(r'^[+0-9 ()-]+$').hasMatch(search)
          ? phoneSearch(search)
          : null;
      clauses.add(
        "(bill_key LIKE ? ESCAPE '\\' OR normalized_name LIKE ? ESCAPE '\\'${phone == null ? '' : ' OR mobile_search LIKE ? OR alternate_mobile_search LIKE ?'})",
      );
      parameters.addAll([Variable('%$escaped%'), Variable('%$escaped%')]);
      if (phone != null) {
        parameters.addAll([Variable('%$phone%'), Variable('%$phone%')]);
      }
    }
    final sort = switch (query.sort) {
      OrderSort.newest => 'order_date DESC, created_at DESC',
      OrderSort.oldest => 'order_date ASC, created_at ASC',
      OrderSort.deliveryAsc => 'delivery_date ASC',
      OrderSort.deliveryDesc => 'delivery_date DESC',
      OrderSort.balanceAsc => '(total - paid) ASC',
      OrderSort.balanceDesc => '(total - paid) DESC',
      OrderSort.totalAsc => 'total ASC',
      OrderSort.totalDesc => 'total DESC',
      OrderSort.bill => 'bill_key ASC',
    };
    final sql =
        '''
WITH summaries AS (
 SELECT o.*, c.name AS customer_name, c.normalized_name, c.mobile, c.mobile_search, c.alternate_mobile_search,
  COALESCE(charges.subtotal, 0) - o.discount_paise AS total, COALESCE(received.paid, 0) AS paid,
  (SELECT group_concat(description, ', ') FROM (SELECT garment_type || ':' || quantity AS description FROM order_items WHERE order_id = o.id ORDER BY position)) AS garments
 FROM orders o JOIN customers c ON c.id = o.customer_id
 LEFT JOIN (SELECT order_id, sum(quantity * unit_price_paise) AS subtotal FROM order_items GROUP BY order_id) charges ON charges.order_id = o.id
 LEFT JOIN (SELECT order_id, sum(amount_paise) AS paid FROM payments WHERE voided_at IS NULL GROUP BY order_id) received ON received.order_id = o.id
)
SELECT * FROM summaries ${clauses.isEmpty ? '' : 'WHERE ${clauses.map((c) => '($c)').join(' AND ')}'}
ORDER BY $sort, id ASC LIMIT ${query.limit}
''';
    return db
        .customSelect(
          sql,
          variables: parameters,
          readsFrom: {db.customers, db.orders, db.orderItems, db.payments},
        )
        .watch()
        .map(
          (rows) => rows
              .map(
                (r) => OrderSummary(
                  id: r.read<String>('id'),
                  billNumber: r.read<String>('bill_number'),
                  customerId: r.read<String>('customer_id'),
                  customerName: r.read<String>('customer_name'),
                  mobile: r.readNullable<String>('mobile'),
                  garments: (r.readNullable<String>('garments') ?? '')
                      .split(', ')
                      .where((s) => s.isNotEmpty)
                      .map((s) {
                        final pair = s.split(':');
                        return '${GarmentType.values.byName(pair[0]).label} × ${pair[1]}';
                      })
                      .join(', '),
                  orderDate: BusinessDate.parse(r.read<String>('order_date')),
                  deliveryDate: BusinessDate.parse(
                    r.read<String>('delivery_date'),
                  ),
                  status: OrderStatus.fromId(r.read<String>('status')),
                  totalPaise: r.read<int>('total'),
                  paidPaise: r.read<int>('paid'),
                ),
              )
              .toList(),
        );
  }
}
