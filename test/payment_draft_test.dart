import 'package:flutter_test/flutter_test.dart';
import 'package:tahzeeb_libas/core/value_objects.dart';
import 'package:tahzeeb_libas/features/orders/application/order_draft.dart';
import 'package:tahzeeb_libas/features/payments/application/payment_draft.dart';

import 'fixtures.dart';

void main() {
  test('optional advance accepts blank and zero; received payments require positive exact paise', () {
    expect(PaymentDraft.optionalAmount(' ').paise, 0);
    expect(PaymentDraft.optionalAmount('0.00').paise, 0);
    final draft = PaymentDraft(
      date: BusinessDate.today(),
      amount: '100.25',
      method: ' Cash ',
      notes: ' Original note ',
    );
    final saved = draft.build();
    expect(saved.amount.paise, 10025);
    expect(saved.id, draft.id);
    expect(saved.method, 'Cash');
    expect(saved.notes, 'Original note');
    draft.amount = '0';
    expect(draft.build, throwsArgumentError);
    draft.amount = '-1';
    expect(draft.build, throwsFormatException);
    draft.amount = '1.999';
    expect(draft.build, throwsFormatException);
  });

  test(
    'historic advance is an ordinary dated payment inside the complete order',
    () {
      final draft = OrderDraft(customer: customer());
      draft.orderDate = BusinessDate.parse('2025-01-01');
      draft.deliveryDate = BusinessDate.parse('2025-01-10');
      draft.garments.single.rate = '100.25';
      draft.garments.single.quantity = '2';
      final o = draft.build(
        bill: '0001',
        discount: '0.50',
        notes: '',
        advance: '50.25',
        advanceDate: BusinessDate.parse('2025-01-02'),
        advanceMethod: 'UPI',
        advanceNotes: 'Historic advance',
      );
      expect(o.totalPaise, 20000);
      expect(o.paidPaise, 5025);
      expect(o.balancePaise, 14975);
      expect(o.payments.single.date.iso, '2025-01-02');
      expect(o.payments.single.notes, 'Historic advance');
      expect(o.payments.single.createdAt, o.createdAt);
      expect(
        () => draft.build(bill: '1', discount: '0', notes: '', advance: '201'),
        throwsArgumentError,
      );
      expect(
        () => draft.build(
          bill: '1',
          discount: '0',
          notes: '',
          advance: '1',
          advanceDate: BusinessDate.parse('2024-12-31'),
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'blank advance creates no zero payment; order edit preserves the ledger',
    () {
      final c = customer();
      final draft = OrderDraft(customer: c);
      expect(
        draft.build(bill: '1', discount: '0', notes: '').payments,
        isEmpty,
      );
      final initial = order(c.id, payments: [payment()]);
      final edit = OrderDraft(original: initial, customer: c);
      expect(
        edit
            .build(
              bill: initial.billNumber,
              discount: initial.discount.decimal,
              notes: '',
            )
            .payments
            .single
            .id,
        initial.payments.single.id,
      );
      expect(
        () => edit.build(
          bill: initial.billNumber,
          discount: '0',
          notes: '',
          advance: '1',
        ),
        throwsArgumentError,
      );
    },
  );
}
