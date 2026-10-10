import 'package:flutter/material.dart';

import '../../../core/value_objects.dart';
import '../../../shared/presentation/common.dart';
import '../domain/order_query.dart';
import '../domain/records.dart';

class OrderFilters extends StatefulWidget {
  final OrderQuery initial;
  const OrderFilters({super.key, required this.initial});
  @override
  State<OrderFilters> createState() => _OrderFiltersState();
}

class _OrderFiltersState extends State<OrderFilters> {
  BusinessDate? orderFrom, orderTo, deliveryFrom, deliveryTo;
  PaymentStatus? payment;
  OrderStatus? status;
  late bool balanceOnly;
  late OrderSort sort;
  String? error;
  @override
  void initState() {
    super.initState();
    final q = widget.initial;
    orderFrom = q.orderFrom;
    orderTo = q.orderTo;
    deliveryFrom = q.deliveryFrom;
    deliveryTo = q.deliveryTo;
    payment = q.paymentStatus;
    status = q.status;
    balanceOnly = q.balanceOnly;
    sort = q.sort;
  }

  Widget date(
    String label,
    BusinessDate? value,
    ValueChanged<BusinessDate?> changed,
  ) => Row(
    children: [
      Expanded(
        child: value == null
            ? OutlinedButton(
                onPressed: () => pick(changed),
                child: Text('$label: Any'),
              )
            : DateInput(label: label, date: value, onChanged: changed),
      ),
      if (value != null)
        IconButton(
          tooltip: 'Clear $label',
          onPressed: () => changed(null),
          icon: const Icon(Icons.clear),
        ),
    ],
  );
  Future<void> pick(ValueChanged<BusinessDate?> changed) async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(9999, 12, 31),
    );
    if (date != null && mounted) {
      changed(
        BusinessDate.parse(
          '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Filters and sorting')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (error != null) ErrorNotice(error!),
        date('Order from', orderFrom, (v) => setState(() => orderFrom = v)),
        date('Order to', orderTo, (v) => setState(() => orderTo = v)),
        date(
          'Delivery from',
          deliveryFrom,
          (v) => setState(() => deliveryFrom = v),
        ),
        date('Delivery to', deliveryTo, (v) => setState(() => deliveryTo = v)),
        const SizedBox(height: 12),
        DropdownButtonFormField<PaymentStatus>(
          isExpanded: true,
          initialValue: payment,
          decoration: inputLabel('Payment status'),
          items: [
            const DropdownMenuItem(value: null, child: Text('Any')),
            ...PaymentStatus.values.map(
              (s) => DropdownMenuItem(
                value: s,
                child: Text(paymentStatusLabel(s)),
              ),
            ),
          ],
          onChanged: (v) => setState(() => payment = v),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<OrderStatus>(
          isExpanded: true,
          initialValue: status,
          decoration: inputLabel('Delivery status'),
          items: [
            const DropdownMenuItem(value: null, child: Text('Any')),
            ...OrderStatus.values.map(
              (s) =>
                  DropdownMenuItem(value: s, child: Text(orderStatusLabel(s))),
            ),
          ],
          onChanged: (v) => setState(() => status = v),
        ),
        SwitchListTile(
          title: const Text('Balance greater than zero'),
          value: balanceOnly,
          onChanged: (v) => setState(() => balanceOnly = v),
        ),
        DropdownButtonFormField<OrderSort>(
          isExpanded: true,
          initialValue: sort,
          decoration: inputLabel('Sort by'),
          items: OrderSort.values
              .map((s) => DropdownMenuItem(value: s, child: Text(s.label)))
              .toList(),
          onChanged: (v) {
            if (v != null) setState(() => sort = v);
          },
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () {
            try {
              Navigator.pop(
                context,
                OrderQuery(
                  search: widget.initial.search,
                  customerId: widget.initial.customerId,
                  orderFrom: orderFrom,
                  orderTo: orderTo,
                  deliveryFrom: deliveryFrom,
                  deliveryTo: deliveryTo,
                  paymentStatus: payment,
                  status: status,
                  balanceOnly: balanceOnly,
                  sort: sort,
                ),
              );
            } catch (e) {
              setState(() => error = friendlyError(e));
            }
          },
          child: const Text('Apply'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(
            context,
            OrderQuery(
              search: widget.initial.search,
              customerId: widget.initial.customerId,
            ),
          ),
          child: const Text('Reset filters'),
        ),
      ],
    ),
  );
}
