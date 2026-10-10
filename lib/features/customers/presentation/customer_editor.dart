import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../app/providers.dart';
import '../../../shared/presentation/common.dart';
import '../../orders/domain/records.dart';

class CustomerEditor extends ConsumerStatefulWidget {
  final CustomerRecord? initial;
  final bool persist;
  const CustomerEditor({super.key, this.initial, this.persist = true});
  @override
  ConsumerState<CustomerEditor> createState() => _CustomerEditorState();
}

class _CustomerEditorState extends ConsumerState<CustomerEditor> {
  final form = GlobalKey<FormState>();
  late final TextEditingController name, phone, alternate, address, notes;
  late final String id;
  bool dirty = false, busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    final c = widget.initial;
    id = c?.id ?? const Uuid().v4();
    name = TextEditingController(text: c?.name);
    phone = TextEditingController(text: c?.mobile);
    alternate = TextEditingController(text: c?.alternateMobile);
    address = TextEditingController(text: c?.address);
    notes = TextEditingController(text: c?.notes);
  }

  @override
  void dispose() {
    for (final c in [name, phone, alternate, address, notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final clock = DateTime.now().toUtc();
      final now =
          widget.initial != null && !clock.isAfter(widget.initial!.updatedAt)
          ? widget.initial!.updatedAt.add(const Duration(microseconds: 1))
          : clock;
      final c = CustomerRecord(
        id: id,
        name: name.text,
        mobile: optionalText(phone.text),
        alternateMobile: optionalText(alternate.text),
        address: optionalText(address.text),
        notes: optionalText(notes.text),
        createdAt: widget.initial?.createdAt ?? now,
        updatedAt: now,
      );
      final repo = ref.read(repositoryProvider);
      final matches = await repo.potentialDuplicates(c);
      if (!mounted) return;
      if (matches.isNotEmpty) {
        final result = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Possible existing customer'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children: [
                  Text(
                    widget.initial == null
                        ? 'Review these records before creating a duplicate. Tap a record to reuse it.'
                        : 'These records have similar details. Confirm that you are editing the correct customer.',
                  ),
                  for (final other in matches)
                    ListTile(
                      title: Text(other.name),
                      subtitle: Text(other.mobile ?? 'No phone'),
                      trailing: widget.initial == null
                          ? const Icon(Icons.arrow_forward)
                          : null,
                      onTap: widget.initial == null
                          ? () => Navigator.pop(context, other.id)
                          : null,
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Keep editing'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, 'save'),
                child: Text(
                  widget.initial == null
                      ? 'Create separate customer'
                      : 'Save this customer',
                ),
              ),
            ],
          ),
        );
        if (!mounted || result == null) return;
        if (result != 'save') {
          Navigator.pop(
            context,
            matches.firstWhere((other) => other.id == result),
          );
          return;
        }
      }
      if (widget.persist) {
        await repo.saveCustomer(
          c,
          expectedUpdatedAt: widget.initial?.updatedAt,
        );
        ref.invalidate(customerProvider(c.id));
      }
      if (mounted) Navigator.pop(context, c);
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
  Widget build(BuildContext context) => DraftGuard(
    dirty: dirty,
    busy: busy,
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.initial == null ? 'New customer' : 'Edit customer'),
      ),
      body: AbsorbPointer(
        absorbing: busy,
        child: Form(
          key: form,
          onChanged: () {
            if (!dirty) setState(() => dirty = true);
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (error != null) ErrorNotice(error!),
              TextFormField(
                key: const Key('customerName'),
                controller: name,
                decoration: inputLabel('Customer name'),
                textCapitalization: TextCapitalization.words,
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Enter customer name'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('customerPhone'),
                controller: phone,
                decoration: inputLabel('Mobile number (optional)'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: alternate,
                decoration: inputLabel('Alternate number (optional)'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: address,
                decoration: inputLabel('Address (optional)'),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: notes,
                decoration: inputLabel('Customer notes (optional)'),
                maxLines: 3,
              ),
              const SizedBox(height: 20),
              FilledButton(
                key: const Key('saveCustomer'),
                onPressed: busy ? null : save,
                child: Text(
                  busy
                      ? 'Saving…'
                      : widget.persist
                      ? 'Save customer'
                      : 'Use customer',
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
