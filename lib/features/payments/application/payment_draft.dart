import 'package:uuid/uuid.dart';

import '../../../core/value_objects.dart';
import '../../orders/domain/records.dart';

/// Form input is parsed into exact paise before it reaches persistence.
class PaymentDraft {
  final String id = const Uuid().v4();
  String amount, method, notes;
  BusinessDate date;
  PaymentDraft({
    required this.date,
    this.amount = '',
    this.method = '',
    this.notes = '',
  });

  static Money optionalAmount(String input) =>
      input.trim().isEmpty ? Money(0) : Money.parse(input);

  PaymentRecord build({DateTime? now}) {
    final value = Money.parse(amount);
    if (value.paise == 0) {
      throw ArgumentError('Payment must be greater than zero.');
    }
    final timestamp = now ?? DateTime.now().toUtc();
    return PaymentRecord(
      id: id,
      amount: value,
      date: date,
      method: method.trim().isEmpty ? null : method.trim(),
      notes: notes.trim().isEmpty ? null : notes.trim(),
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }
}
