import '../../../core/value_objects.dart';
import 'catalog.dart';

enum OrderStatus {
  newOrder('new'),
  inProgress('in_progress'),
  ready('ready'),
  delivered('delivered'),
  cancelled('cancelled');

  final String id;
  const OrderStatus(this.id);
  static OrderStatus fromId(String id) => values.firstWhere((s) => s.id == id);
}

enum PaymentStatus { pending, partiallyPaid, paid }

final class CustomerRecord {
  final String id, name;
  final String? mobile, alternateMobile, address, notes;
  final DateTime createdAt, updatedAt;
  CustomerRecord({
    required this.id,
    required String name,
    this.mobile,
    this.alternateMobile,
    this.address,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  }) : name = name.trim() {
    requireId(id);
    if (this.name.isEmpty) throw ArgumentError('Customer name is required.');
    validateTimestamps(createdAt, updatedAt);
  }
}

final class GarmentItem {
  final String id;
  final GarmentType type;
  final String? variant, description, fittingNotes;
  final int quantity;
  final Money unitPrice;
  final MeasurementSnapshot measurements;
  final DateTime createdAt, updatedAt;
  GarmentItem({
    required this.id,
    required this.type,
    this.variant,
    required this.quantity,
    required this.unitPrice,
    this.description,
    required this.measurements,
    this.fittingNotes,
    required this.createdAt,
    required this.updatedAt,
  }) {
    requireId(id);
    type.validateVariant(variant);
    if (quantity < 1 || quantity > 10000) {
      throw ArgumentError('Quantity must be 1–10000.');
    }
    Money(quantity * unitPrice.paise);
    validateTimestamps(createdAt, updatedAt);
  }
  int get totalPaise => quantity * unitPrice.paise;
}

final class PaymentRecord {
  final String id;
  final Money amount;
  final BusinessDate date;
  final String? method, notes, voidReason, replacesPaymentId;
  final DateTime createdAt, updatedAt;
  final DateTime? voidedAt;
  PaymentRecord({
    required this.id,
    required this.amount,
    required this.date,
    this.method,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    this.voidedAt,
    this.voidReason,
    this.replacesPaymentId,
  }) {
    requireId(id);
    if (amount.paise == 0) throw ArgumentError('Payment must be positive.');
    validateTimestamps(createdAt, updatedAt);
    if ((voidedAt == null) != (voidReason == null) ||
        (voidReason != null && voidReason!.trim().isEmpty)) {
      throw ArgumentError('Voiding requires a reason and timestamp.');
    }
    if (voidedAt != null &&
        (!voidedAt!.isUtc || voidedAt!.isBefore(createdAt))) {
      throw ArgumentError('Invalid correction timestamp.');
    }
    if (replacesPaymentId != null) requireId(replacesPaymentId!);
  }
}

final class OrderRecord {
  final String id, billNumber, customerId;
  final BusinessDate orderDate, deliveryDate;
  final OrderStatus status;
  final Money discount;
  final String? notes;
  final DateTime createdAt, updatedAt;
  final List<GarmentItem> items;
  final List<PaymentRecord> payments;
  OrderRecord({
    required this.id,
    required String billNumber,
    required this.customerId,
    required this.orderDate,
    required this.deliveryDate,
    this.status = OrderStatus.newOrder,
    required this.discount,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    required List<GarmentItem> items,
    List<PaymentRecord> payments = const [],
  }) : billNumber = billNumber.trim(),
       items = List.unmodifiable(items),
       payments = List.unmodifiable(payments) {
    requireId(id);
    requireId(customerId);
    billKey(this.billNumber);
    validateTimestamps(createdAt, updatedAt);
    if (orderDate.compareTo(deliveryDate) > 0) {
      throw ArgumentError('Delivery precedes order.');
    }
    if (items.isEmpty || items.length > 1000) {
      throw ArgumentError('An order needs 1–1000 garments.');
    }
    if (items.map((e) => e.id).toSet().length != items.length ||
        payments.map((e) => e.id).toSet().length != payments.length) {
      throw ArgumentError('Duplicate item or payment ID.');
    }
    Money(subtotalPaise);
    if (discount.paise > subtotalPaise) {
      throw ArgumentError('Discount exceeds subtotal.');
    }
    if (paidPaise > totalPaise) {
      throw ArgumentError(
        'Received payments exceed the order total. Correct any mistaken payment before reducing charges.',
      );
    }
    for (final payment in payments) {
      if (payment.date.compareTo(orderDate) < 0 ||
          payment.date.compareTo(BusinessDate.today()) > 0) {
        throw ArgumentError(
          'Payment date must be between order date and today.',
        );
      }
      if (payment.replacesPaymentId != null &&
          !payments.any(
            (p) => p.id == payment.replacesPaymentId && p.voidedAt != null,
          )) {
        throw ArgumentError(
          'Replacement must refer to a voided payment in this order.',
        );
      }
    }
  }
  OrderRecord withPayments(List<PaymentRecord> next, DateTime updated) =>
      OrderRecord(
        id: id,
        billNumber: billNumber,
        customerId: customerId,
        orderDate: orderDate,
        deliveryDate: deliveryDate,
        status: status,
        discount: discount,
        notes: notes,
        createdAt: createdAt,
        updatedAt: updated,
        items: items,
        payments: next,
      );
  int get subtotalPaise => items.fold(0, (sum, item) => sum + item.totalPaise);
  int get totalPaise => subtotalPaise - discount.paise;
  int get paidPaise => payments
      .where((p) => p.voidedAt == null)
      .fold(0, (sum, p) => sum + p.amount.paise);
  int get balancePaise => totalPaise - paidPaise;
  PaymentStatus get paymentStatus => balancePaise == 0
      ? PaymentStatus.paid
      : paidPaise == 0
      ? PaymentStatus.pending
      : PaymentStatus.partiallyPaid;
}

void validateTimestamps(DateTime created, DateTime updated) {
  if (!created.isUtc || !updated.isUtc || updated.isBefore(created)) {
    throw ArgumentError('Timestamps must be UTC and chronological.');
  }
}
