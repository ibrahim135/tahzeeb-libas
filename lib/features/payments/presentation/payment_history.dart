import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../shared/presentation/common.dart';
import '../../orders/domain/records.dart';

class PaymentHistory extends StatelessWidget {
  final List<PaymentRecord> payments;
  final ValueChanged<PaymentRecord> correct;
  const PaymentHistory({
    super.key,
    required this.payments,
    required this.correct,
  });

  @override
  Widget build(BuildContext context) {
    // Labels are stable within a bill even when the payment date is corrected.
    final recorded = [...payments]
      ..sort((a, b) {
        final time = a.createdAt.compareTo(b.createdAt);
        return time == 0 ? a.id.compareTo(b.id) : time;
      });
    final numbers = {
      for (var i = 0; i < recorded.length; i++) recorded[i].id: i + 1,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Payment history', style: Theme.of(context).textTheme.titleLarge),
        if (payments.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('No payments received yet.'),
          ),
        for (final payment in payments)
          Card(
            key: ValueKey('payment:${payment.id}'),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Payment ${numbers[payment.id]} · ${payment.date.display}',
                  ),
                  Text(
                    inr(payment.amount.paise),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      decoration: payment.voidedAt == null
                          ? null
                          : TextDecoration.lineThrough,
                    ),
                  ),
                  Text(
                    payment.voidedAt == null
                        ? 'Received'
                        : 'Voided · excluded from received',
                  ),
                  if (payment.method != null) Text('Method: ${payment.method}'),
                  if (payment.notes != null) Text(payment.notes!),
                  if (payment.replacesPaymentId != null)
                    Text(
                      'Replaces payment ${numbers[payment.replacesPaymentId]}',
                    ),
                  if (payment.voidedAt != null) ...[
                    Text('Reason: ${payment.voidReason}'),
                    Text(
                      'Corrected: ${DateFormat('dd/MM/yyyy HH:mm').format(payment.voidedAt!.toLocal())}',
                    ),
                  ] else
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        key: ValueKey('correct:${payment.id}'),
                        onPressed: () => correct(payment),
                        icon: const Icon(Icons.edit_note),
                        label: const Text('Correct payment'),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
