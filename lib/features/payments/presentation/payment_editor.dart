import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/value_objects.dart';
import '../../../shared/presentation/common.dart';
import '../../orders/domain/records.dart';
import '../application/payment_draft.dart';

class PaymentEditor extends ConsumerStatefulWidget {
  final OrderRecord order;
  final PaymentRecord? original;
  const PaymentEditor({super.key, required this.order, this.original});
  @override
  ConsumerState<PaymentEditor> createState() => _PaymentEditorState();
}

class _PaymentEditorState extends ConsumerState<PaymentEditor> {
  final form = GlobalKey<FormState>();
  late final PaymentDraft draft;
  final reason = TextEditingController();
  bool dirty = false, busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    final p = widget.original;
    draft = PaymentDraft(
      date: p?.date ?? BusinessDate.today(),
      amount: p?.amount.decimal ?? '',
      method: p?.method ?? '',
      notes: p?.notes ?? '',
    );
  }

  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  void changed() {
    if (mounted && !dirty) setState(() => dirty = true);
  }

  void showError(Object e) {
    if (!mounted) return;
    setState(() => error = friendlyError(e));
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(error!), showCloseIcon: true));
  }

  Future<void> save({bool voidOnly = false}) async {
    if (busy) return;
    if (voidOnly) {
      if (reason.text.trim().isEmpty) {
        showError(ArgumentError('Enter a reason for the correction.'));
        return;
      }
    } else if (!form.currentState!.validate()) {
      return;
    }
    final original = widget.original;
    if (original != null) {
      final proceed = await confirm(
        context,
        voidOnly ? 'Void recorded payment?' : 'Replace recorded payment?',
        voidOnly
            ? '${inr(original.amount.paise)} will be excluded from received amounts. The original entry and your reason remain in history.'
            : 'The original entry will remain in history and be excluded from received amounts. The replacement becomes the active payment.',
        action: voidOnly ? 'Void payment' : 'Replace payment',
      );
      if (!mounted || !proceed) return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final repo = ref.read(repositoryProvider);
      if (original == null) {
        await repo.addPayment(widget.order.id, draft.build());
      } else {
        await repo.correctPayment(
          widget.order.id,
          original.id,
          expectedUpdatedAt: original.updatedAt,
          reason: reason.text,
          replacement: voidOnly ? null : draft.build(),
        );
      }
      ref.invalidate(orderProvider(widget.order.id));
      if (mounted) {
        Navigator.pop(
          context,
          voidOnly
              ? 'Payment voided'
              : original == null
              ? 'Payment received'
              : 'Payment corrected',
        );
      }
    } catch (e) {
      showError(e);
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
        title: Text(
          widget.original == null ? 'Receive payment' : 'Correct payment',
        ),
      ),
      body: AbsorbPointer(
        absorbing: busy,
        child: Form(
          key: form,
          onChanged: changed,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              Text(
                'Bill ${widget.order.billNumber}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                'Current received: ${inr(widget.order.paidPaise)}\nRemaining balance: ${inr(widget.order.balancePaise)}',
              ),
              if (widget.original != null) ...[
                const SizedBox(height: 12),
                Text(
                  'Original payment: ${inr(widget.original!.amount.paise)} · ${widget.original!.date.display}',
                ),
                const Text(
                  'Use a correction for an entry mistake. No money is refunded by this action.',
                ),
              ],
              const SizedBox(height: 16),
              if (error != null) ErrorNotice(error!),
              TextFormField(
                key: const Key('paymentAmount'),
                initialValue: draft.amount,
                decoration: inputLabel('Amount received (₹)'),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (v) => draft.amount = v,
                validator: (v) {
                  try {
                    if (Money.parse(v ?? '').paise == 0) {
                      return 'Enter an amount greater than zero';
                    }
                    return null;
                  } catch (e) {
                    return friendlyError(e);
                  }
                },
              ),
              DateInput(
                label: 'Payment date',
                date: draft.date,
                onChanged: (v) {
                  setState(() {
                    draft.date = v;
                    dirty = true;
                  });
                },
              ),
              TextFormField(
                key: const Key('paymentMethod'),
                initialValue: draft.method,
                decoration: inputLabel('Method (optional, e.g. Cash / UPI)'),
                onChanged: (v) => draft.method = v,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('paymentNotes'),
                initialValue: draft.notes,
                decoration: inputLabel('Payment notes (optional)'),
                minLines: 2,
                maxLines: 5,
                onChanged: (v) => draft.notes = v,
              ),
              if (widget.original != null) ...[
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('correctionReason'),
                  controller: reason,
                  decoration: inputLabel('Reason for correction (required)'),
                  minLines: 2,
                  maxLines: 5,
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Enter a correction reason'
                      : null,
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                key: const Key('savePayment'),
                onPressed: busy ? null : () => save(),
                child: Text(
                  busy
                      ? 'Saving…'
                      : widget.original == null
                      ? 'Save received payment'
                      : 'Save replacement',
                ),
              ),
              if (widget.original != null) ...[
                const SizedBox(height: 12),
                OutlinedButton(
                  key: const Key('voidPayment'),
                  onPressed: busy ? null : () => save(voidOnly: true),
                  child: const Text('Void without replacement'),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
