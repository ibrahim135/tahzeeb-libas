import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:drift/native.dart';

import '../../core/value_objects.dart';
import '../../features/orders/domain/order_query.dart';
import '../../features/orders/domain/records.dart';

String inr(int paise) =>
    '₹${NumberFormat.decimalPattern('en_IN').format(paise ~/ 100)}.${(paise % 100).toString().padLeft(2, '0')}';
String orderStatusLabel(OrderStatus status) => switch (status) {
  OrderStatus.newOrder => 'New',
  OrderStatus.inProgress => 'In progress',
  OrderStatus.ready => 'Ready',
  OrderStatus.delivered => 'Delivered',
  OrderStatus.cancelled => 'Cancelled',
};
String paymentStatusLabel(PaymentStatus status) => switch (status) {
  PaymentStatus.pending => 'Pending',
  PaymentStatus.partiallyPaid => 'Partially paid',
  PaymentStatus.paid => 'Paid',
};
String friendlyError(Object error) {
  if (error is EditConflict) {
    return 'This record changed while you were editing. Reopen it before saving.';
  }
  if (error is FormatException) return error.message;
  if (error is ArgumentError) return '${error.message}';
  if (error is SqliteException && error.resultCode == 19) {
    return 'Could not save: this bill or record already exists, or a referenced record is missing. Check the bill number and customer.';
  }
  return 'Could not access local records. Please retry. Your saved data has not been reset.';
}

String? optionalText(String value) =>
    value.trim().isEmpty ? null : value.trim();
Future<bool> confirm(
  BuildContext context,
  String title,
  String message, {
  String action = 'Continue',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

class DraftGuard extends StatelessWidget {
  final bool dirty, busy;
  final Widget child;
  const DraftGuard({
    super.key,
    required this.dirty,
    required this.busy,
    required this.child,
  });
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !dirty && !busy,
    onPopInvokedWithResult: (didPop, result) async {
      if (didPop || busy) return;
      final discard = await confirm(
        context,
        'Discard unsaved changes?',
        'Your changes have not been saved.',
        action: 'Discard',
      );
      if (discard && context.mounted) Navigator.of(context).pop();
    },
    child: child,
  );
}

class DateInput extends StatelessWidget {
  final String label;
  final BusinessDate date;
  final ValueChanged<BusinessDate> onChanged;
  const DateInput({
    super.key,
    required this.label,
    required this.date,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: OutlinedButton.icon(
      icon: const Icon(Icons.calendar_month),
      label: Align(
        alignment: Alignment.centerLeft,
        child: Text('$label: ${date.display}'),
      ),
      onPressed: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: DateTime.parse(date.iso),
          firstDate: DateTime(1900),
          lastDate: DateTime(9999, 12, 31),
        );
        if (picked != null && context.mounted) {
          onChanged(
            BusinessDate.parse(DateFormat('yyyy-MM-dd').format(picked)),
          );
        }
      },
    ),
  );
}

class ErrorNotice extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const ErrorNotice(this.message, {super.key, this.onRetry});
  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.errorContainer,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}

InputDecoration inputLabel(String label) =>
    InputDecoration(labelText: label, border: const OutlineInputBorder());
