import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../shared/presentation/common.dart';
import '../domain/shop_settings.dart';

class ShopEditor extends ConsumerStatefulWidget {
  final ShopSettingsRecord initial;
  const ShopEditor({super.key, required this.initial});
  @override
  ConsumerState<ShopEditor> createState() => _ShopEditorState();
}

class _ShopEditorState extends ConsumerState<ShopEditor> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.initial.name);
  late final address = TextEditingController(text: widget.initial.address);
  late final contact = TextEditingController(text: widget.initial.contact);
  late final notes = TextEditingController(text: widget.initial.receiptNotes);
  bool dirty = false, busy = false;
  String? error;
  @override
  void dispose() {
    for (final c in [name, address, contact, notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref
          .read(settingsRepositoryProvider)
          .save(
            ShopSettingsRecord(
              name: name.text,
              address: optionalText(address.text),
              contact: optionalText(contact.text),
              receiptNotes: optionalText(notes.text),
              updatedAt: widget.initial.updatedAt,
            ),
            expectedUpdatedAt: widget.initial.updatedAt,
          );
      if (!mounted) return;
      setState(() {
        busy = false;
        dirty = false;
      });
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = friendlyError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => DraftGuard(
    dirty: dirty,
    busy: busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Shop details')),
      body: Form(
        key: form,
        onChanged: () => setState(() => dirty = true),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextFormField(
              controller: name,
              enabled: !busy,
              decoration: inputLabel('Shop name'),
              validator: (v) =>
                  v!.trim().isEmpty ? 'Enter the shop name.' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: address,
              enabled: !busy,
              decoration: inputLabel('Shop address (optional)'),
              minLines: 2,
              maxLines: 5,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: contact,
              enabled: !busy,
              decoration: inputLabel('Contact (optional)'),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: notes,
              enabled: !busy,
              decoration: inputLabel('Customer receipt notes (optional)'),
              minLines: 3,
              maxLines: 8,
            ),
            const SizedBox(height: 12),
            const Text(
              'Receipt notes appear on payment receipts only. Changes apply to newly generated PDFs.',
            ),
            if (error != null) ErrorNotice(error!),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: busy ? null : save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save shop details'),
            ),
            if (busy) const LinearProgressIndicator(),
          ],
        ),
      ),
    ),
  );
}
