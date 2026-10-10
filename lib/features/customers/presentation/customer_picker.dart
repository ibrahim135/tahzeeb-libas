import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../shared/presentation/common.dart';
import '../../orders/domain/records.dart';

class CustomerPicker extends ConsumerStatefulWidget {
  const CustomerPicker({super.key});
  @override
  ConsumerState<CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends ConsumerState<CustomerPicker> {
  String search = '';
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Select customer')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            decoration: inputLabel('Search name or phone'),
            onChanged: (value) => setState(() => search = value),
          ),
        ),
        Expanded(
          child: ref
              .watch(searchedCustomersProvider(search))
              .when(
                data: (customers) => customers.isEmpty
                    ? const Center(child: Text('No matching customers.'))
                    : ListView.builder(
                        itemCount: customers.length,
                        itemBuilder: (context, index) => ListTile(
                          title: Text(customers[index].name),
                          subtitle: Text(customers[index].mobile ?? 'No phone'),
                          onTap: () => Navigator.pop<CustomerRecord>(
                            context,
                            customers[index],
                          ),
                        ),
                      ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => ErrorNotice(friendlyError(e)),
              ),
        ),
      ],
    ),
  );
}
