import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../shared/presentation/common.dart';
import '../domain/order_query.dart';
import 'order_details.dart';
import 'order_editor.dart';
import 'order_filters.dart';

class OrderList extends ConsumerStatefulWidget {
  final String? customerId;
  const OrderList({super.key, this.customerId});
  @override
  ConsumerState<OrderList> createState() => _OrderListState();
}

class _OrderListState extends ConsumerState<OrderList> {
  late OrderQuery query;
  @override
  void initState() {
    super.initState();
    query = OrderQuery(customerId: widget.customerId);
  }

  OrderQuery copyQuery({String? search, int? limit}) => OrderQuery(
    search: search ?? query.search,
    customerId: query.customerId,
    orderFrom: query.orderFrom,
    orderTo: query.orderTo,
    deliveryFrom: query.deliveryFrom,
    deliveryTo: query.deliveryTo,
    paymentStatus: query.paymentStatus,
    status: query.status,
    balanceOnly: query.balanceOnly,
    sort: query.sort,
    limit: limit ?? 100,
  );
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          children: [
            TextField(
              key: const Key('orderSearch'),
              decoration: inputLabel('Search bill, customer or phone'),
              onChanged: (s) => setState(() => query = copyQuery(search: s)),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('newOrder'),
                    onPressed: () async {
                      final id = await Navigator.push<String>(
                        context,
                        MaterialPageRoute(builder: (_) => const OrderEditor()),
                      );
                      if (id != null && context.mounted) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => OrderDetails(id: id),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Add order'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final next = await Navigator.push<OrderQuery>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => OrderFilters(initial: query),
                      ),
                    );
                    if (next != null && mounted) setState(() => query = next);
                  },
                  icon: const Icon(Icons.filter_list),
                  label: Text(query.hasFilters ? 'Filters •' : 'Filters'),
                ),
              ],
            ),
          ],
        ),
      ),
      Expanded(
        child: ref
            .watch(ordersProvider(query))
            .when(
              data: (orders) => orders.isEmpty
                  ? Center(
                      child: Text(
                        query.search.isNotEmpty || query.hasFilters
                            ? 'No orders match this search or filters.'
                            : 'No orders saved yet.',
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                      itemCount: orders.length + 1,
                      itemBuilder: (context, index) {
                        if (index == orders.length) {
                          return orders.length < query.limit
                              ? const SizedBox.shrink()
                              : Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: query.limit < 10000
                                      ? OutlinedButton(
                                          onPressed: () => setState(
                                            () => query = copyQuery(
                                              limit: query.limit + 100,
                                            ),
                                          ),
                                          child: const Text('Load more orders'),
                                        )
                                      : const Text(
                                          'Showing 10000 orders. Narrow the search or date range.',
                                        ),
                                );
                        }
                        return OrderCard(order: orders[index]);
                      },
                    ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorNotice(
                friendlyError(e),
                onRetry: () => ref.invalidate(ordersProvider(query)),
              ),
            ),
      ),
    ],
  );
}

class OrderCard extends StatelessWidget {
  final OrderSummary order;
  const OrderCard({super.key, required this.order});
  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => OrderDetails(id: order.id)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${order.customerName} · Bill ${order.billNumber}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (order.mobile != null) Text(order.mobile!),
            Text(order.garments),
            const SizedBox(height: 6),
            Text(
              'Order ${order.orderDate.display} · Delivery ${order.deliveryDate.display}',
            ),
            Wrap(
              spacing: 12,
              children: [
                Text(paymentStatusLabel(order.paymentStatus)),
                Text('Balance ${inr(order.balancePaise)}'),
                Text(orderStatusLabel(order.status)),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
