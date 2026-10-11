import '../../../core/display_formats.dart';
import '../../orders/domain/catalog.dart';
import '../../orders/domain/records.dart';
import '../../settings/domain/shop_settings.dart';

enum DocumentKind {
  receipt('Payment receipt', 'Customer copy'),
  warehouse('Warehouse measurement slip', 'Warehouse copy');

  final String label, copyLabel;
  const DocumentKind(this.label, this.copyLabel);
}

/// The rendering contract is immutable text, projected before layout. Warehouse
/// projection never passes financial records or private customer/shop notes.
final class DocumentContent {
  final DocumentKind kind;
  final String billNumber;
  final List<DocumentBlock> blocks;
  DocumentContent(this.kind, this.billNumber, Iterable<DocumentBlock> blocks)
    : blocks = List.unmodifiable(blocks);
}

final class DocumentBlock {
  final String text;
  final bool heading;
  const DocumentBlock(this.text, {this.heading = false});
}

final class BillDocumentSnapshot {
  final OrderRecord order;
  final CustomerRecord customer;
  final ShopSettingsRecord shop;
  final DateTime capturedAt;
  const BillDocumentSnapshot(
    this.order,
    this.customer,
    this.shop,
    this.capturedAt,
  );

  DocumentContent content(DocumentKind kind) {
    final blocks = <DocumentBlock>[];
    void line(String? value, {bool heading = false}) {
      if (value != null && value.trim().isNotEmpty) {
        blocks.add(DocumentBlock(value, heading: heading));
      }
    }

    line(shop.name, heading: true);
    line(shop.address);
    line(shop.contact == null ? null : 'Contact: ${shop.contact}');
    line('Bill: ${order.billNumber}', heading: true);
    line('Customer: ${customer.name}');
    line(customer.mobile == null ? null : 'Phone: ${customer.mobile}');
    line('Delivery: ${order.deliveryDate.display}');
    line('Delivery status: ${orderStatusLabel(order.status)}');
    if (kind == DocumentKind.receipt) {
      line('Order date: ${order.orderDate.display}');
      line(customer.address);
    }
    for (var i = 0; i < order.items.length; i++) {
      final item = order.items[i];
      line(
        '${i + 1}. ${item.type.label}${item.variant == null ? '' : ' / ${item.type.variants[item.variant]}'} - Quantity: ${item.quantity}',
        heading: true,
      );
      line(item.description);
      if (kind == DocumentKind.receipt) {
        line(
          'Rate: ${inr(item.unitPrice.paise)}     Amount: ${inr(item.totalPaise)}',
        );
      } else {
        if (item.measurements.configuration == MeasurementConfiguration.none) {
          line(
            'No standard body measurements. See size/details and fitting instructions.',
          );
        }
        for (final (title, fields, enabled) in [
          (
            'Upper body',
            upperFields,
            {MeasurementConfiguration.upper, MeasurementConfiguration.both},
          ),
          (
            'Lower body',
            lowerFields,
            {MeasurementConfiguration.lower, MeasurementConfiguration.both},
          ),
        ]) {
          if (!enabled.contains(item.measurements.configuration)) continue;
          line('$title - inches', heading: true);
          var entered = false;
          for (final key in fields) {
            final value = item.measurements.values[key];
            if (value == null) continue;
            entered = true;
            final label = key.split('_').last;
            line('${label[0].toUpperCase()}${label.substring(1)}: $value');
          }
          if (!entered) line('No measurements entered.');
        }
        line('Fitting instructions', heading: true);
        line(item.fittingNotes ?? 'No fitting notes.');
      }
    }
    if (kind == DocumentKind.receipt) {
      line('Payment summary', heading: true);
      line('Subtotal: ${inr(order.subtotalPaise)}');
      line('Discount: ${inr(order.discount.paise)}');
      line('Order total: ${inr(order.totalPaise)}');
      line('Received: ${inr(order.paidPaise)}');
      line('Balance: ${inr(order.balancePaise)}', heading: true);
      line('Payment status: ${paymentStatusLabel(order.paymentStatus)}');
      line('Payments received', heading: true);
      final active = order.payments.where((p) => p.voidedAt == null);
      if (active.isEmpty) line('No payments received.');
      for (final p in active) {
        line(
          '${p.date.display} - ${inr(p.amount.paise)}${p.method == null ? '' : ' - ${p.method}'}',
        );
      }
      line('Corrected/voided entries are excluded from received amounts.');
      if (order.notes != null) {
        line('Order notes', heading: true);
        line(order.notes);
      }
      if (shop.receiptNotes != null) {
        line('Shop notes', heading: true);
        line(shop.receiptNotes);
      }
    }
    return DocumentContent(kind, order.billNumber, blocks);
  }
}
