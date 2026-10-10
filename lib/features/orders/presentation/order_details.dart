import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../shared/presentation/common.dart';
import '../domain/catalog.dart';
import 'order_editor.dart';

class OrderDetails extends ConsumerWidget {
  final String id;
  const OrderDetails({super.key, required this.id});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(orderProvider(id))
      .when(
        loading: () => Scaffold(
          appBar: AppBar(title: const Text('Order')),
          body: const Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Scaffold(
          appBar: AppBar(title: const Text('Order')),
          body: ErrorNotice(
            friendlyError(e),
            onRetry: () => ref.invalidate(orderProvider(id)),
          ),
        ),
        data: (order) {
          if (order == null) {
            return Scaffold(
              appBar: AppBar(title: const Text('Order')),
              body: const Center(child: Text('Order not found.')),
            );
          }
          final customer = ref.watch(customerProvider(order.customerId));
          return DefaultTabController(
            length: 2,
            child: Scaffold(
              appBar: AppBar(
                title: Text('Bill ${order.billNumber}'),
                actions: [
                  IconButton(
                    tooltip: 'Edit order',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => OrderEditor(
                            initial: order,
                            customer: customer.asData?.value,
                          ),
                        ),
                      );
                      if (context.mounted) ref.invalidate(orderProvider(id));
                    },
                  ),
                ],
                bottom: const TabBar(
                  tabs: [
                    Tab(text: 'PAYMENT'),
                    Tab(text: 'MEASUREMENTS'),
                  ],
                ),
              ),
              body: TabBarView(
                children: [
                  ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      customer.when(
                        data: (c) => Text(
                          c == null
                              ? 'Customer unavailable'
                              : '${c.name}\n${c.mobile ?? 'No phone'}',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        loading: () => const LinearProgressIndicator(),
                        error: (e, _) => ErrorNotice(friendlyError(e)),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Order: ${order.orderDate.display}\nDelivery: ${order.deliveryDate.display}\n${orderStatusLabel(order.status)}',
                      ),
                      const Divider(),
                      for (final item in order.items)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            '${item.type.label}${item.variant == null ? '' : ' · ${item.type.variants[item.variant]}'} × ${item.quantity}',
                          ),
                          subtitle: Text(
                            '${item.description ?? ''}\nRate ${inr(item.unitPrice.paise)}',
                          ),
                          trailing: Text(inr(item.totalPaise)),
                        ),
                      const Divider(),
                      Text(
                        'Subtotal: ${inr(order.subtotalPaise)}\nDiscount: ${inr(order.discount.paise)}\nTotal: ${inr(order.totalPaise)}\nReceived: ${inr(order.paidPaise)}\nBalance: ${inr(order.balancePaise)}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      Text(paymentStatusLabel(order.paymentStatus)),
                      if (order.notes != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(order.notes!),
                        ),
                    ],
                  ),
                  ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      for (final item in order.items)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  '${item.type.label} × ${item.quantity}',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                if (item.description != null)
                                  Text(item.description!),
                                for (final section in [
                                  upperFields,
                                  lowerFields,
                                ])
                                  if (section.any(
                                    item.measurements.values.containsKey,
                                  )) ...[
                                    const SizedBox(height: 12),
                                    Text(
                                      section == upperFields
                                          ? 'Upper body · inches'
                                          : 'Lower body · inches',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                    for (final field in section)
                                      if (item.measurements.values.containsKey(
                                        field,
                                      ))
                                        Text(
                                          '${field.split('_').last}: ${item.measurements.values[field]}',
                                        ),
                                  ],
                                if (item.measurements.values.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 12),
                                    child: Text('No measurements entered.'),
                                  ),
                                const SizedBox(height: 12),
                                Text(
                                  'Fitting instructions',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                Text(item.fittingNotes ?? 'No fitting notes.'),
                                TextButton.icon(
                                  onPressed: () async {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => OrderEditor(
                                          initial: order,
                                          customer: customer.asData?.value,
                                        ),
                                      ),
                                    );
                                    if (context.mounted) {
                                      ref.invalidate(orderProvider(id));
                                    }
                                  },
                                  icon: const Icon(Icons.edit_outlined),
                                  label: const Text('Edit measurements'),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
}
