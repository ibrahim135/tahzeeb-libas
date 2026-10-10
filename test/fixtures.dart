import 'package:tahzeeb_libas/core/value_objects.dart';
import 'package:tahzeeb_libas/features/orders/domain/catalog.dart';
import 'package:tahzeeb_libas/features/orders/domain/records.dart';
import 'package:uuid/uuid.dart';

final created = DateTime.utc(2025, 1, 1);
String id() => const Uuid().v4();
CustomerRecord customer({
  String? customerId,
  String name = 'Test Customer',
  String? phone = '0012345678',
}) => CustomerRecord(
  id: customerId ?? id(),
  name: name,
  mobile: phone,
  alternateMobile: '+91 0000000000',
  address: 'Test address',
  notes: 'Test notes',
  createdAt: created,
  updatedAt: created,
);
GarmentItem item({
  String? itemId,
  GarmentType type = GarmentType.shirt,
  MeasurementSnapshot? snapshot,
  int quantity = 2,
  int price = 10025,
}) => GarmentItem(
  id: itemId ?? id(),
  type: type,
  quantity: quantity,
  unitPrice: Money(price),
  description: 'Special cut',
  measurements:
      snapshot ??
      MeasurementSnapshot(MeasurementConfiguration.upper, {
        'upper_length': '30.125',
        'upper_hips': '42',
      }),
  fittingNotes: 'Loose fitting\nAdjust cuffs',
  createdAt: created,
  updatedAt: created,
);
PaymentRecord payment({int amount = 5000}) => PaymentRecord(
  id: id(),
  amount: Money(amount),
  date: BusinessDate.parse('2025-01-01'),
  method: 'Cash',
  notes: 'Advance',
  createdAt: created,
  updatedAt: created,
);
OrderRecord order(
  String customerId, {
  String? orderId,
  String bill = '0007',
  List<GarmentItem>? items,
  List<PaymentRecord>? payments,
  int discount = 50,
}) => OrderRecord(
  id: orderId ?? id(),
  billNumber: bill,
  customerId: customerId,
  orderDate: BusinessDate.parse('2025-01-01'),
  deliveryDate: BusinessDate.parse('2025-01-10'),
  discount: Money(discount),
  notes: 'Historic bill',
  createdAt: created,
  updatedAt: created,
  items: items ?? [item()],
  payments: payments ?? [],
);
