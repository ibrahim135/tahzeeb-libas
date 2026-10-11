import 'dart:typed_data';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:tahzeeb_libas/core/value_objects.dart';
import 'package:tahzeeb_libas/features/documents/application/document_pdf.dart';
import 'package:tahzeeb_libas/features/documents/domain/document.dart';
import 'package:tahzeeb_libas/features/orders/domain/catalog.dart';
import 'package:tahzeeb_libas/features/orders/domain/records.dart';
import 'package:tahzeeb_libas/features/settings/domain/shop_settings.dart';

import 'fixtures.dart' as f;

BillDocumentSnapshot sample({String? longNotes, String? longDescription}) {
  final c = f.customer();
  final voided = PaymentRecord(
    id: f.id(),
    amount: Money(9876),
    date: BusinessDate.parse('2025-01-01'),
    createdAt: f.created,
    updatedAt: DateTime.utc(2025, 1, 2),
    voidedAt: DateTime.utc(2025, 1, 2),
    voidReason: 'Correction',
  );
  final paid = PaymentRecord(
    id: f.id(),
    amount: Money(5025),
    date: BusinessDate.parse('2025-01-02'),
    method: 'Cash',
    notes: 'Private payment note',
    createdAt: DateTime.utc(2025, 1, 2),
    updatedAt: DateTime.utc(2025, 1, 2),
    replacesPaymentId: voided.id,
  );
  final o = f.order(
    c.id,
    items: [
      GarmentItem(
        id: f.id(),
        type: GarmentType.suit,
        variant: 'three_piece',
        quantity: 2,
        unitPrice: Money(12345),
        description: longDescription ?? 'Wedding suit',
        measurements: MeasurementSnapshot(MeasurementConfiguration.both, {
          'upper_length': '30.125',
          'lower_length': '42.75',
          'upper_hips': '40',
          'lower_hips': '41.5',
        }),
        fittingNotes: longNotes ?? 'Loose fitting\nAlter sleeves',
        createdAt: f.created,
        updatedAt: f.created,
      ),
      f.item(
        type: GarmentType.joota,
        snapshot: MeasurementSnapshot(MeasurementConfiguration.none, {}),
      ),
      f.item(
        type: GarmentType.pant,
        snapshot: MeasurementSnapshot(MeasurementConfiguration.lower, {}),
      ),
    ],
    payments: [voided, paid],
    discount: 75,
  );
  return BillDocumentSnapshot(
    o,
    c,
    ShopSettingsRecord(
      name: 'Tahzeeb Libas',
      address: 'Shop address\nSecond line',
      contact: '00123456789',
      receiptNotes: 'Private shop receipt note',
      updatedAt: f.created,
    ),
    f.created,
  );
}

String text(DocumentContent content) =>
    content.blocks.map((b) => b.text).join('\n');
int pages(List<int> bytes) =>
    RegExp(r'/Type\s*/Page\b').allMatches(latin1.decode(bytes)).length;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DocumentFonts fonts;
  setUpAll(() async => fonts = await DocumentFonts.load());
  test(
    'receipt uses exact totals, historical active payments, and variants',
    () {
      final doc = sample();
      final receipt = text(doc.content(DocumentKind.receipt));
      expect(receipt, contains('Suit / 3-piece - Quantity: 2'));
      expect(receipt, contains('Rate: ₹123.45     Amount: ₹246.90'));
      expect(receipt, contains('Subtotal: ₹647.90'));
      expect(receipt, contains('Discount: ₹0.75'));
      expect(receipt, contains('Order total: ₹647.15'));
      expect(receipt, contains('Received: ₹50.25'));
      expect(receipt, contains('Balance: ₹596.90'));
      expect(receipt, contains('02/01/2025 - ₹50.25 - Cash'));
      expect(receipt, contains('Partially paid'));
      expect(receipt, isNot(contains('₹98.76')));
      expect(receipt, contains('Private shop receipt note'));
      expect(receipt, isNot(contains('Private payment note')));
    },
  );
  test('warehouse projection excludes financial and private note fields', () {
    final warehouse = text(sample().content(DocumentKind.warehouse));
    for (final token in [
      '₹',
      '123.45',
      '647.15',
      '50.25',
      '596.90',
      'Historic bill',
      'Private shop receipt note',
      'Private payment note',
      'Test notes',
      'Test address',
      'Discount:',
      'Received:',
      'Balance:',
      'Payment status:',
    ]) {
      expect(warehouse, isNot(contains(token)), reason: token);
    }
    expect(
      warehouse,
      contains('Upper body - inches\nLength: 30.125\nHips: 40'),
    );
    expect(
      warehouse,
      contains('Lower body - inches\nLength: 42.75\nHips: 41.5'),
    );
    expect(warehouse, contains('No standard body measurements.'));
    expect(warehouse, contains('No measurements entered.'));
    expect(warehouse, contains('Loose fitting\nAlter sleeves'));
    expect(warehouse, contains('Bill: 0007'));
    expect(warehouse, contains('Phone: 0012345678'));
  });
  test(
    'receipt pending, paid and zero-total status derive from stored amounts',
    () {
      final c = f.customer(phone: null);
      for (final (price, payments, expected) in [
        (100, <PaymentRecord>[], 'Pending'),
        (100, [f.payment(amount: 100)], 'Paid'),
        (0, <PaymentRecord>[], 'Paid'),
      ]) {
        final snapshot = BillDocumentSnapshot(
          f.order(
            c.id,
            items: [f.item(quantity: 1, price: price)],
            payments: payments,
            discount: 0,
          ),
          c,
          sample().shop,
          f.created,
        );
        final receipt = text(snapshot.content(DocumentKind.receipt));
        expect(receipt, contains('Payment status: $expected'));
        expect(receipt, isNot(contains('Phone:')));
      }
    },
  );
  test('bundled regular and bold fonts support INR', () {
    final document = PdfDocument();
    for (final bytes in [fonts.regular, fonts.bold]) {
      final font = PdfTtfFont(document, ByteData.sublistView(bytes));
      expect(font.isRuneSupported('₹'.runes.single), isTrue);
    }
  });
  test('both A4 PDF formats and shop copies embed fonts and paginate long text', () async {
    final pdf = DocumentPdf(fonts);
    final target = Platform.environment['TAHZEEB_PDF_SAMPLES'];
    if (target != null) await Directory(target).create(recursive: true);
    for (final kind in DocumentKind.values) {
      final bytes = await pdf.build(sample().content(kind));
      final raw = latin1.decode(bytes);
      expect(raw, startsWith('%PDF-'));
      expect(raw, contains('/FontFile2'));
      expect(raw, contains('/ToUnicode'));
      expect(pages(bytes), greaterThanOrEqualTo(1));
      final copyBytes = await pdf.build(sample().content(kind), shopCopy: true);
      expect(copyBytes, isNotEmpty);
      if (target != null) {
        await File('$target/${kind.name}_original.pdf').writeAsBytes(bytes);
        await File('$target/${kind.name}_shop.pdf').writeAsBytes(copyBytes);
      }
    }
    final notes =
        '${List.generate(800, (i) => 'Instruction $i: keep a loose fitting and adjust the cuffs.').join('\n')}\n${'LONGTOKEN' * 200}\nFINAL_WAREHOUSE_INSTRUCTION';
    final longBytes = await pdf.build(
      sample(longNotes: notes).content(DocumentKind.warehouse),
    );
    expect(pages(longBytes), greaterThan(10));
    if (target != null) {
      await File('$target/warehouse_long.pdf').writeAsBytes(longBytes);
    }
    final receiptBytes = await pdf.build(
      sample(longDescription: notes).content(DocumentKind.receipt),
    );
    expect(pages(receiptBytes), greaterThan(10));
  });
  test(
    '160 garments paginate without the default 20-page restriction',
    () async {
      final snapshot = sample();
      final o = f.order(
        snapshot.customer.id,
        items: List.generate(160, (_) => f.item()),
        discount: 0,
      );
      final bytes = await DocumentPdf(fonts).build(
        BillDocumentSnapshot(
          o,
          snapshot.customer,
          snapshot.shop,
          f.created,
        ).content(DocumentKind.warehouse),
      );
      expect(pages(bytes), greaterThan(20));
    },
  );
  test(
    'unsupported text fails clearly rather than silently losing characters',
    () async {
      await expectLater(
        DocumentPdf(fonts).build(
          DocumentContent(DocumentKind.receipt, '1', [
            const DocumentBlock('Unsupported: 中文'),
          ]),
        ),
        throwsFormatException,
      );
    },
  );
}
