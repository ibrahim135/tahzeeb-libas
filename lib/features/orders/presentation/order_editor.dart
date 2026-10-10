import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../shared/presentation/common.dart';
import '../../customers/presentation/customer_editor.dart';
import '../../customers/presentation/customer_picker.dart';
import '../application/order_draft.dart';
import '../domain/order_query.dart';
import '../domain/records.dart';
import 'garment_editor.dart';

class OrderEditor extends ConsumerStatefulWidget {
  final OrderRecord? initial;
  final CustomerRecord? customer;
  const OrderEditor({super.key, this.initial, this.customer});
  @override
  ConsumerState<OrderEditor> createState() => _OrderEditorState();
}

class _OrderEditorState extends ConsumerState<OrderEditor> {
  final form = GlobalKey<FormState>();
  late final OrderDraft draft;
  late final TextEditingController bill, discount, notes;
  bool dirty = false, busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    draft = OrderDraft(original: widget.initial, customer: widget.customer);
    bill = TextEditingController(text: widget.initial?.billNumber);
    discount = TextEditingController(
      text: widget.initial?.discount.decimal ?? '0.00',
    );
    notes = TextEditingController(text: widget.initial?.notes);
    initialize();
  }

  Future<void> initialize() async {
    try {
      final repo = ref.read(repositoryProvider);
      if (draft.original == null) {
        final next = await repo.suggestBillNumber();
        if (mounted && bill.text.isEmpty) bill.text = next;
      } else if (draft.customer == null) {
        final customer = await repo.getCustomer(draft.original!.customerId);
        if (mounted) setState(() => draft.customer = customer);
      }
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    }
  }

  @override
  void dispose() {
    bill.dispose();
    discount.dispose();
    notes.dispose();
    super.dispose();
  }

  void changed() {
    if (mounted) setState(() => dirty = true);
  }

  Future<void> chooseCustomer(bool create) async {
    final c = await Navigator.push<CustomerRecord>(
      context,
      MaterialPageRoute(
        builder: (_) => create
            ? const CustomerEditor(persist: false)
            : const CustomerPicker(),
      ),
    );
    if (c == null || !mounted) return;
    try {
      final existing = await ref.read(repositoryProvider).getCustomer(c.id);
      if (!mounted) return;
      setState(() {
        draft.customer = c;
        draft.isNewCustomer = existing == null;
        dirty = true;
      });
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    }
  }

  Future<void> copyMeasurements(GarmentDraft garment) async {
    try {
      final repo = ref.read(repositoryProvider);
      final orders =
          (await repo
                  .watchOrders(
                    OrderQuery(customerId: draft.customer!.id, limit: 1000),
                  )
                  .first)
              .where((o) => o.id != draft.id)
              .toList();
      if (!mounted) return;
      final chosen = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Choose previous order'),
          children: [
            if (orders.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('No previous orders.'),
              ),
            for (final o in orders)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, o.id),
                child: Text(
                  'Bill ${o.billNumber} · ${o.orderDate.display}\n${o.garments}',
                ),
              ),
          ],
        ),
      );
      if (chosen == null) return;
      final order = await repo.getOrder(chosen);
      if (!mounted || order == null) return;
      final candidates = order.items
          .where((i) => i.type == garment.type)
          .toList();
      final source = await showDialog<GarmentItem>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text('Choose ${garment.type.label} measurements'),
          children: [
            if (candidates.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('This order has no matching garment type.'),
              ),
            for (var i = 0; i < candidates.length; i++)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, candidates[i]),
                child: Text(
                  '${garment.type.label} ${i + 1} · ${candidates[i].description ?? 'Measurements'}',
                ),
              ),
          ],
        ),
      );
      if (source == null || !mounted) return;
      if (garment.measurements.values.any((v) => v.trim().isNotEmpty) ||
          garment.fittingNotes.trim().isNotEmpty) {
        if (!await confirm(
          context,
          'Replace draft measurements?',
          'The selected measurements and fitting notes will replace this garment’s draft values.',
          action: 'Replace',
        )) {
          return;
        }
      }
      if (!mounted) return;
      garment.copyMeasurements(source);
      changed();
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    }
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final order = draft.build(
        bill: bill.text,
        discount: discount.text,
        notes: notes.text,
      );
      final repo = ref.read(repositoryProvider);
      if (draft.original == null) {
        await repo.createOrder(
          order,
          newCustomer: draft.isNewCustomer ? draft.customer : null,
        );
      } else {
        await repo.updateOrder(
          order,
          expectedUpdatedAt: draft.original!.updatedAt,
          newCustomer: draft.isNewCustomer ? draft.customer : null,
        );
      }
      ref.invalidate(orderProvider(order.id));
      if (mounted) Navigator.pop(context, order.id);
    } catch (e) {
      if (mounted) {
        setState(() => error = friendlyError(e));
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error!)));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String totals;
    try {
      totals = 'Order total: ${inr(draft.netTotal(discount.text))}';
    } catch (_) {
      totals =
          'Enter valid quantities, prices and discount to calculate total.';
    }
    return DraftGuard(
      dirty: dirty,
      busy: busy,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.initial == null ? 'New order' : 'Edit order'),
        ),
        body: AbsorbPointer(
          absorbing: busy,
          child: Form(
            key: form,
            onChanged: changed,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (error != null) ErrorNotice(error!),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          draft.customer?.name ?? 'Choose a customer',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (draft.customer?.mobile != null)
                          Text(draft.customer!.mobile!),
                        Wrap(
                          spacing: 8,
                          children: [
                            OutlinedButton(
                              onPressed: () => chooseCustomer(false),
                              child: const Text('Existing customer'),
                            ),
                            OutlinedButton(
                              onPressed: () => chooseCustomer(true),
                              child: const Text('New customer'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('billNumber'),
                  controller: bill,
                  decoration: inputLabel('Bill number'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty || v.trim().length > 64
                      ? 'Enter a unique bill number (up to 64 characters)'
                      : null,
                ),
                DateInput(
                  label: 'Order date',
                  date: draft.orderDate,
                  onChanged: (date) {
                    draft.orderDate = date;
                    changed();
                  },
                ),
                DateInput(
                  label: 'Delivery date',
                  date: draft.deliveryDate,
                  onChanged: (date) {
                    draft.deliveryDate = date;
                    changed();
                  },
                ),
                DropdownButtonFormField<OrderStatus>(
                  isExpanded: true,
                  initialValue: draft.status,
                  decoration: inputLabel('Delivery status'),
                  items: OrderStatus.values
                      .map(
                        (s) => DropdownMenuItem(
                          value: s,
                          child: Text(orderStatusLabel(s)),
                        ),
                      )
                      .toList(),
                  onChanged: (s) {
                    if (s != null) {
                      draft.status = s;
                      changed();
                    }
                  },
                ),
                const SizedBox(height: 16),
                for (var i = 0; i < draft.garments.length; i++)
                  GarmentEditor(
                    key: ValueKey(draft.garments[i].id),
                    draft: draft.garments[i],
                    number: i + 1,
                    changed: changed,
                    remove: () async {
                      final garment = draft.garments[i];
                      if (await confirm(
                        context,
                        'Remove garment?',
                        'Remove this garment and its draft measurements?',
                        action: 'Remove',
                      )) {
                        if (mounted) {
                          draft.garments.remove(garment);
                          changed();
                        }
                      }
                    },
                    copyPrevious: draft.customer == null
                        ? null
                        : () => copyMeasurements(draft.garments[i]),
                  ),
                OutlinedButton.icon(
                  key: const Key('addGarment'),
                  onPressed: () {
                    draft.garments.add(GarmentDraft.empty());
                    changed();
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Add garment'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('discount'),
                  controller: discount,
                  decoration: inputLabel('Discount (₹)'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => changed(),
                ),
                const SizedBox(height: 12),
                Text(totals, style: Theme.of(context).textTheme.titleMedium),
                if (draft.original != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Already received: ${inr(draft.original!.paidPaise)}. Payment records are preserved.',
                    ),
                  ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: notes,
                  decoration: inputLabel('General order notes'),
                  minLines: 3,
                  maxLines: 6,
                ),
                const SizedBox(height: 20),
                FilledButton(
                  key: const Key('saveOrder'),
                  onPressed: busy ? null : save,
                  child: Text(busy ? 'Saving…' : 'Save order'),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
