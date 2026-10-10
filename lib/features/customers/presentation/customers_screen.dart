import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../shared/presentation/common.dart';
import '../../orders/domain/order_query.dart';
import '../../orders/domain/records.dart';
import '../../orders/presentation/order_editor.dart';
import '../../orders/presentation/order_list.dart';
import 'customer_editor.dart';

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});
  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  String search = '';
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('customerSearch'),
              decoration: inputLabel('Search customer name or phone'),
              onChanged: (s) => setState(() => search = s),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const Key('newCustomer'),
              onPressed: () async {
                final c = await Navigator.push<CustomerRecord>(
                  context,
                  MaterialPageRoute(builder: (_) => const CustomerEditor()),
                );
                if (c != null && context.mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CustomerDetails(id: c.id),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.person_add_outlined),
              label: const Text('Add customer'),
            ),
          ],
        ),
      ),
      Expanded(
        child: ref
            .watch(searchedCustomersProvider(search))
            .when(
              data: (customers) => customers.isEmpty
                  ? Center(
                      child: Text(
                        search.isEmpty
                            ? 'No customers saved yet.'
                            : 'No matching customers.',
                      ),
                    )
                  : ListView.builder(
                      itemCount: customers.length,
                      itemBuilder: (context, i) => ListTile(
                        title: Text(customers[i].name),
                        subtitle: Text(customers[i].mobile ?? 'No phone'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                CustomerDetails(id: customers[i].id),
                          ),
                        ),
                      ),
                    ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorNotice(
                friendlyError(e),
                onRetry: () =>
                    ref.invalidate(searchedCustomersProvider(search)),
              ),
            ),
      ),
    ],
  );
}

class CustomerDetails extends ConsumerStatefulWidget {
  final String id;
  const CustomerDetails({super.key, required this.id});
  @override
  ConsumerState<CustomerDetails> createState() => _CustomerDetailsState();
}

class _CustomerDetailsState extends ConsumerState<CustomerDetails> {
  late OrderQuery query;
  @override
  void initState() {
    super.initState();
    query = OrderQuery(customerId: widget.id);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Customer history')),
    body: ref
        .watch(customerProvider(widget.id))
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorNotice(
            friendlyError(e),
            onRetry: () => ref.invalidate(customerProvider(widget.id)),
          ),
          data: (c) {
            if (c == null) {
              return const Center(child: Text('Customer not found.'));
            }
            final orders = ref.watch(ordersProvider(query));
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(c.name, style: Theme.of(context).textTheme.headlineSmall),
                Text(c.mobile ?? 'No phone'),
                if (c.alternateMobile != null)
                  Text('Alternate: ${c.alternateMobile}'),
                if (c.address != null) Text(c.address!),
                if (c.notes != null) Text(c.notes!),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CustomerEditor(initial: c),
                          ),
                        );
                        if (mounted) {
                          ref.invalidate(customerProvider(widget.id));
                        }
                      },
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit customer'),
                    ),
                    FilledButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => OrderEditor(customer: c),
                        ),
                      ),
                      icon: const Icon(Icons.add),
                      label: const Text('Add order'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  'Order history',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                orders.when(
                  data: (list) => Column(
                    children: [
                      if (list.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(20),
                          child: Text('No previous orders.'),
                        ),
                      for (final o in list) OrderCard(order: o),
                      if (list.length == query.limit && query.limit < 10000)
                        OutlinedButton(
                          onPressed: () => setState(
                            () => query = OrderQuery(
                              customerId: widget.id,
                              limit: query.limit + 100,
                            ),
                          ),
                          child: const Text('Load more orders'),
                        ),
                    ],
                  ),
                  loading: () => const CircularProgressIndicator(),
                  error: (e, _) => ErrorNotice(friendlyError(e)),
                ),
              ],
            );
          },
        ),
  );
}
