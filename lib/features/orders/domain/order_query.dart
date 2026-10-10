import '../../../core/value_objects.dart';
import 'records.dart';

enum OrderSort {
  newest('Newest first'),
  oldest('Oldest first'),
  deliveryAsc('Delivery date ↑'),
  deliveryDesc('Delivery date ↓'),
  balanceAsc('Balance ↑'),
  balanceDesc('Balance ↓'),
  totalAsc('Order total ↑'),
  totalDesc('Order total ↓'),
  bill('Bill number');

  final String label;
  const OrderSort(this.label);
}

final class OrderQuery {
  final String search;
  final String? customerId;
  final BusinessDate? orderFrom, orderTo, deliveryFrom, deliveryTo;
  final PaymentStatus? paymentStatus;
  final OrderStatus? status;
  final bool balanceOnly;
  final OrderSort sort;
  final int limit;
  bool get hasFilters =>
      orderFrom != null ||
      orderTo != null ||
      deliveryFrom != null ||
      deliveryTo != null ||
      paymentStatus != null ||
      status != null ||
      balanceOnly;
  OrderQuery({
    this.search = '',
    this.customerId,
    this.orderFrom,
    this.orderTo,
    this.deliveryFrom,
    this.deliveryTo,
    this.paymentStatus,
    this.status,
    this.balanceOnly = false,
    this.sort = OrderSort.newest,
    this.limit = 100,
  }) {
    if (limit < 1 || limit > 10000) throw ArgumentError('Invalid list limit.');
    if ((orderFrom != null &&
            orderTo != null &&
            orderFrom!.compareTo(orderTo!) > 0) ||
        (deliveryFrom != null &&
            deliveryTo != null &&
            deliveryFrom!.compareTo(deliveryTo!) > 0)) {
      throw ArgumentError('Date range start must not follow its end.');
    }
  }
}

final class OrderSummary {
  final String id, billNumber, customerId, customerName, garments;
  final String? mobile;
  final BusinessDate orderDate, deliveryDate;
  final OrderStatus status;
  final int totalPaise, paidPaise;
  OrderSummary({
    required this.id,
    required this.billNumber,
    required this.customerId,
    required this.customerName,
    this.mobile,
    required this.garments,
    required this.orderDate,
    required this.deliveryDate,
    required this.status,
    required this.totalPaise,
    required this.paidPaise,
  });
  int get balancePaise => totalPaise - paidPaise;
  PaymentStatus get paymentStatus => balancePaise == 0
      ? PaymentStatus.paid
      : paidPaise == 0
      ? PaymentStatus.pending
      : PaymentStatus.partiallyPaid;
}

final class EditConflict implements Exception {
  const EditConflict();
}
