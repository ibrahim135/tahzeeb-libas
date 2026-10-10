import 'package:flutter_test/flutter_test.dart';
import 'package:tahzeeb_libas/features/orders/application/order_draft.dart';
import 'package:tahzeeb_libas/features/orders/domain/catalog.dart';

import 'fixtures.dart';

void main() {
  test('copying previous measurements keeps independent IDs and snapshots', () {
    final source = item();
    final target = GarmentDraft.empty();
    final targetId = target.id;
    target.copyMeasurements(source);
    target.measurements['upper_length'] = '50';
    expect(target.id, targetId);
    expect(target.id, isNot(source.id));
    expect(source.measurements.values['upper_length'], '30.125');
    expect(target.fittingNotes, source.fittingNotes);
  });
  test('configuration identifies populated sections and clears only disabled fields', () {
    final draft = GarmentDraft.empty();
    draft.measurements.addAll({'upper_length': '30', 'lower_length': '40'});
    expect(draft.removedFields(MeasurementConfiguration.upper), {
      'lower_length',
    });
    draft.setConfiguration(MeasurementConfiguration.upper);
    expect(draft.measurements, {'upper_length': '30'});
    draft.setConfiguration(MeasurementConfiguration.both);
    expect(draft.measurements, {'upper_length': '30'});
  });
  test(
    'complete draft validates dates, customer, garments and exact totals',
    () {
      final draft = OrderDraft();
      expect(
        () => draft.build(bill: '1', discount: '0', notes: ''),
        throwsArgumentError,
      );
      draft.customer = customer();
      draft.garments.single.rate = '100.25';
      draft.garments.single.quantity = '2';
      final order = draft.build(bill: '001', discount: '0.50', notes: 'Note');
      expect(order.totalPaise, 20000);
      expect(order.billNumber, '001');
      expect(() => draft.netTotal('201'), throwsArgumentError);
      draft.garments.clear();
      expect(
        () => draft.build(bill: '1', discount: '0', notes: ''),
        throwsArgumentError,
      );
    },
  );
}
