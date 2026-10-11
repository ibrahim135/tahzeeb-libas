import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/customers/presentation/customers_screen.dart';
import '../features/orders/presentation/order_list.dart';
import '../features/settings/presentation/settings_screen.dart';

class TahzeebApp extends StatelessWidget {
  const TahzeebApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Tahzeeb Libas',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff28594d)),
    ),
    home: const ShopShell(),
  );
}

class ShopShell extends ConsumerStatefulWidget {
  const ShopShell({super.key});
  @override
  ConsumerState<ShopShell> createState() => _ShopShellState();
}

class _ShopShellState extends ConsumerState<ShopShell> {
  int selected = 0;
  @override
  Widget build(BuildContext context) {
    final title = ['Orders', 'Customers', 'Settings'][selected];
    return Scaffold(
      appBar: AppBar(title: Text('Tahzeeb Libas · $title')),
      body: SafeArea(
        child: IndexedStack(
          index: selected,
          children: const [OrderList(), CustomersScreen(), SettingsScreen()],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selected,
        onDestinationSelected: (index) => setState(() => selected = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            label: 'Orders',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            label: 'Customers',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
