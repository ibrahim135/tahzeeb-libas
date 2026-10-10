import 'package:flutter_test/flutter_test.dart';
import 'package:tahzeeb_libas/core/value_objects.dart';
import 'package:tahzeeb_libas/features/orders/domain/catalog.dart';
import 'package:tahzeeb_libas/features/orders/domain/records.dart';

import 'fixtures.dart';

void main() {
  test('Money parsing is exact and rejects unsupported amounts', () {
    expect(Money.parse('123.45').paise, 12345);
    expect(Money.parse('0.01').paise, 1);
    expect(Money.parse('1.1').decimal, '1.10');
    for (final bad in ['-1', '1.234', 'NaN', '1e5', '1,000', '']) {
      expect(() => Money.parse(bad), throwsFormatException);
    }
    expect(() => Money(Money.maxPaise + 1), throwsArgumentError);
    expect(
      () => item(quantity: 10000, price: Money.maxPaise),
      throwsArgumentError,
    );
  });
  test('Business dates reject rollover and timezone ambiguity', () {
    expect(BusinessDate.parse('2024-02-29').display, '29/02/2024');
    for (final bad in [
      '2025-02-29',
      '2025-13-01',
      '01/01/2025',
      '2025-01-01T00:00:00Z',
    ]) {
      expect(() => BusinessDate.parse(bad), throwsFormatException);
    }
  });
  test('Catalog retains stable IDs and validates variants', () {
    expect(GarmentType.values.map((g) => g.name).toSet().length, 11);
    expect(GarmentType.jothpuri.label, 'Jothpuri');
    expect(GarmentType.payjama.label, 'Payjama');
    expect(
      GarmentType.suit.defaultConfiguration,
      MeasurementConfiguration.both,
    );
    expect(
      GarmentType.joota.defaultConfiguration,
      MeasurementConfiguration.none,
    );
    expect(
      () => GarmentType.suit.validateVariant('three_piece'),
      returnsNormally,
    );
    expect(() => GarmentType.suit.validateVariant(null), throwsArgumentError);
    expect(
      () => GarmentType.shirt.validateVariant('three_piece'),
      throwsArgumentError,
    );
  });
  test(
    'Snapshots copy inputs, canonicalize decimals and constrain sections',
    () {
      final input = {'upper_length': '030.100', 'upper_hips': '42'};
      final snapshot = MeasurementSnapshot(
        MeasurementConfiguration.upper,
        input,
      );
      input['upper_length'] = '10';
      expect(snapshot.values['upper_length'], '30.1');
      expect(
        () => snapshot.values['upper_length'] = '20',
        throwsUnsupportedError,
      );
      expect(
        () => MeasurementSnapshot(MeasurementConfiguration.lower, {
          'upper_hips': '42',
        }),
        throwsArgumentError,
      );
      expect(
        () => MeasurementSnapshot(MeasurementConfiguration.none, {}),
        returnsNormally,
      );
      expect(
        () => MeasurementSnapshot(MeasurementConfiguration.both, {
          'upper_hips': '42',
          'lower_hips': '40',
        }),
        returnsNormally,
      );
      for (final bad in ['0', '-2', '10.1234', '']) {
        expect(
          () => MeasurementSnapshot(MeasurementConfiguration.upper, {
            'upper_length': bad,
          }),
          throwsFormatException,
        );
      }
    },
  );
  test('Totals derive from exact charges and active payments', () {
    final c = customer();
    final partial = order(
      c.id,
      items: [item(), item(quantity: 1, price: 15000)],
      payments: [payment()],
    );
    expect(partial.subtotalPaise, 35050);
    expect(partial.totalPaise, 35000);
    expect(partial.paidPaise, 5000);
    expect(partial.balancePaise, 30000);
    expect(partial.paymentStatus, PaymentStatus.partiallyPaid);
    expect(order(c.id).paymentStatus, PaymentStatus.pending);
    expect(
      order(c.id, payments: [payment(amount: 20000)]).paymentStatus,
      PaymentStatus.paid,
    );
    expect(
      order(c.id, items: [item(price: 0)], discount: 0).paymentStatus,
      PaymentStatus.paid,
    );
    expect(
      () => order(c.id, payments: [payment(amount: 20001)]),
      throwsArgumentError,
    );
    expect(() => order(c.id, discount: 20051), throwsArgumentError);
  });
  test(
    'Basic invariants reject empty orders, duplicate IDs and zero payments',
    () {
      final c = customer();
      final garment = item();
      expect(customer(phone: null).mobile, isNull);
      expect(phoneSearch('+91 001 234'), '91001234');
      expect(() => customer(name: '  '), throwsArgumentError);
      expect(() => order(c.id, items: []), throwsArgumentError);
      expect(() => order(c.id, items: [garment, garment]), throwsArgumentError);
      expect(() => payment(amount: 0), throwsArgumentError);
    },
  );
}
