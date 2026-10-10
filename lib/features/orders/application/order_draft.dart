import 'package:uuid/uuid.dart';

import '../../../core/value_objects.dart';
import '../domain/catalog.dart';
import '../domain/records.dart';

Set<String> fieldsFor(MeasurementConfiguration configuration) =>
    switch (configuration) {
      MeasurementConfiguration.upper => upperFields,
      MeasurementConfiguration.lower => lowerFields,
      MeasurementConfiguration.both => {...upperFields, ...lowerFields},
      MeasurementConfiguration.none => <String>{},
    };

class GarmentDraft {
  final String id;
  final DateTime createdAt;
  GarmentType type;
  String? variant;
  String quantity, rate, description, fittingNotes;
  MeasurementConfiguration configuration;
  final Map<String, String> measurements;
  int revision = 0;
  GarmentDraft._({
    required this.id,
    required this.createdAt,
    required this.type,
    this.variant,
    required this.quantity,
    required this.rate,
    required this.description,
    required this.fittingNotes,
    required this.configuration,
    required this.measurements,
  });
  factory GarmentDraft.empty() => GarmentDraft._(
    id: const Uuid().v4(),
    createdAt: DateTime.now().toUtc(),
    type: GarmentType.shirt,
    quantity: '1',
    rate: '0.00',
    description: '',
    fittingNotes: '',
    configuration: MeasurementConfiguration.upper,
    measurements: {},
  );
  factory GarmentDraft.fromItem(GarmentItem item) => GarmentDraft._(
    id: item.id,
    createdAt: item.createdAt,
    type: item.type,
    variant: item.variant,
    quantity: '${item.quantity}',
    rate: item.unitPrice.decimal,
    description: item.description ?? '',
    fittingNotes: item.fittingNotes ?? '',
    configuration: item.measurements.configuration,
    measurements: Map.of(item.measurements.values),
  );
  Set<String> removedFields(MeasurementConfiguration next) => measurements
      .entries
      .where(
        (e) => e.value.trim().isNotEmpty && !fieldsFor(next).contains(e.key),
      )
      .map((e) => e.key)
      .toSet();
  void setConfiguration(MeasurementConfiguration next) {
    measurements.removeWhere((key, _) => !fieldsFor(next).contains(key));
    configuration = next;
    revision++;
  }

  void copyMeasurements(GarmentItem source) {
    configuration = source.measurements.configuration;
    measurements
      ..clear()
      ..addAll(source.measurements.values);
    fittingNotes = source.fittingNotes ?? '';
    revision++;
  }

  int get totalPaise {
    if (!RegExp(r'^\d+$').hasMatch(quantity.trim())) {
      throw const FormatException('Quantity must be a whole number.');
    }
    final count = int.parse(quantity.trim());
    if (count < 1 || count > 10000) {
      throw ArgumentError('Quantity must be 1–10000.');
    }
    return Money(count * Money.parse(rate).paise).paise;
  }

  GarmentItem build(DateTime now) {
    totalPaise;
    return GarmentItem(
      id: id,
      type: type,
      variant: variant,
      quantity: int.parse(quantity.trim()),
      unitPrice: Money.parse(rate),
      description: description.trim().isEmpty ? null : description.trim(),
      measurements: MeasurementSnapshot(configuration, {
        for (final e in measurements.entries)
          if (e.value.trim().isNotEmpty) e.key: e.value.trim(),
      }),
      fittingNotes: fittingNotes.trim().isEmpty ? null : fittingNotes.trim(),
      createdAt: createdAt,
      updatedAt: now,
    );
  }
}

class OrderDraft {
  final OrderRecord? original;
  final String id;
  final List<GarmentDraft> garments;
  CustomerRecord? customer;
  bool isNewCustomer = false;
  BusinessDate orderDate, deliveryDate;
  OrderStatus status;
  OrderDraft({this.original, this.customer})
    : id = original?.id ?? const Uuid().v4(),
      garments = original == null
          ? [GarmentDraft.empty()]
          : original.items.map(GarmentDraft.fromItem).toList(),
      orderDate = original?.orderDate ?? BusinessDate.today(),
      deliveryDate = original?.deliveryDate ?? BusinessDate.today(),
      status = original?.status ?? OrderStatus.newOrder;
  int netTotal(String discount) {
    final subtotal = Money(
      garments.fold<int>(0, (sum, g) => sum + g.totalPaise),
    ).paise;
    final value = Money.parse(discount).paise;
    if (value > subtotal) throw ArgumentError('Discount exceeds subtotal.');
    return subtotal - value;
  }

  OrderRecord build({
    required String bill,
    required String discount,
    required String notes,
  }) {
    if (customer == null) throw ArgumentError('Select or create a customer.');
    final clock = DateTime.now().toUtc();
    final now = original != null && !clock.isAfter(original!.updatedAt)
        ? original!.updatedAt.add(const Duration(microseconds: 1))
        : clock;
    return OrderRecord(
      id: id,
      billNumber: bill,
      customerId: customer!.id,
      orderDate: orderDate,
      deliveryDate: deliveryDate,
      status: status,
      discount: Money.parse(discount),
      notes: notes.trim().isEmpty ? null : notes.trim(),
      createdAt: original?.createdAt ?? now,
      updatedAt: now,
      items: garments.map((g) => g.build(now)).toList(),
      payments: original?.payments ?? [],
    );
  }
}
