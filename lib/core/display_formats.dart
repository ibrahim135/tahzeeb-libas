import 'package:intl/intl.dart';

import '../features/orders/domain/records.dart';

String inr(int paise) =>
    '₹${NumberFormat.decimalPattern('en_IN').format(paise ~/ 100)}.${(paise % 100).toString().padLeft(2, '0')}';
String orderStatusLabel(OrderStatus status) => switch (status) {
  OrderStatus.newOrder => 'New',
  OrderStatus.inProgress => 'In progress',
  OrderStatus.ready => 'Ready',
  OrderStatus.delivered => 'Delivered',
  OrderStatus.cancelled => 'Cancelled',
};
String paymentStatusLabel(PaymentStatus status) => switch (status) {
  PaymentStatus.pending => 'Pending',
  PaymentStatus.partiallyPaid => 'Partially paid',
  PaymentStatus.paid => 'Paid',
};
