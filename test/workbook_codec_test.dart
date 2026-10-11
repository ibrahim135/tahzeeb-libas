import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tahzeeb_libas/features/transfer/data/workbook_codec.dart';
import 'package:tahzeeb_libas/features/transfer/domain/workbook.dart';
import 'package:xml/xml.dart';

WorkbookData smallWorkbook() => WorkbookData({
  for (final name in workbookColumns.keys) name: [],
  'Customers': [
    WorkbookRow('Customers', 2, {
      'id': '11111111-1111-4111-8111-111111111111',
      'name': 'Example Customer',
      'mobile': '0012345678',
      'alternate_mobile': null,
      'address': 'मुंबई\nShop 1',
      'notes': '=HYPERLINK("untrusted", "literal text")\n+ - @',
      'created_at': '2025-01-01T00:00:00.000Z',
      'updated_at': '2025-01-01T00:00:00.000Z',
    }),
  ],
  'Metadata': [
    for (final entry in {
      'workbook_schema_version': '1',
      'source_database_schema_version': '1',
      'exported_at': '2025-01-01T00:00:00.000Z',
      'currency': 'INR',
      'measurement_unit': 'inches',
      'next_bill_number': '1',
    }.entries)
      WorkbookRow('Metadata', 2, {'key': entry.key, 'value': entry.value}),
  ],
});

Uint8List rewriteCustomerXml(Uint8List bytes, void Function(XmlDocument) edit) {
  final source = ZipDecoder().decodeBytes(bytes, verify: true);
  final output = Archive();
  for (final file in source) {
    var content = file.content as List<int>;
    if (file.name.startsWith('xl/worksheets/') &&
        utf8.decode(content).contains('r="H2"')) {
      final doc = XmlDocument.parse(utf8.decode(content));
      edit(doc);
      content = utf8.encode(doc.toXmlString());
    }
    output.addFile(ArchiveFile(file.name, content.length, content));
  }
  return Uint8List.fromList(ZipEncoder().encode(output)!);
}

XmlElement cell(XmlDocument doc, String ref) => doc.descendants
    .whereType<XmlElement>()
    .firstWhere((e) => e.name.local == 'c' && e.getAttribute('r') == ref);

void main() {
  final codec = WorkbookCodec();
  late WorkbookData data;
  late Uint8List bytes;
  setUp(() {
    data = smallWorkbook();
    bytes = codec.encode(data);
  });

  test('exported text preserves leading zeroes, Unicode, multiline and formula-like notes', () {
    final workbook = Excel.decodeBytes(bytes);
    expect(
      workbook['Customers'].cell(CellIndex.indexByString('C2')).value,
      isA<TextCellValue>(),
    );
    expect(
      workbook['Customers'].cell(CellIndex.indexByString('F2')).value,
      isA<TextCellValue>(),
    );
    final decoded = codec.decode(bytes);
    expect(decoded.issues, isEmpty);
    expect(
      decoded.rows('Customers').single.canonical,
      data.rows('Customers').single.canonical,
    );
  });

  test('formula cells produce specific sheet, row and field diagnostics', () {
    final workbook = Excel.decodeBytes(bytes);
    workbook['Customers'].cell(CellIndex.indexByString('F2')).value =
        const FormulaCellValue('SUM(1,2)');
    final decoded = codec.decode(Uint8List.fromList(workbook.encode()!));
    expect(
      decoded.issues.any(
        (e) =>
            e.sheet == 'Customers' &&
            e.row == 2 &&
            e.field == 'notes' &&
            e.message.contains('Formulas'),
      ),
      isTrue,
    );
  });

  test('explicit empty optional text stays distinct from an absent cell', () {
    final row = data.rows('Customers').single;
    final empty = WorkbookData({
      ...data.tables,
      'Customers': [
        WorkbookRow('Customers', 2, {
          ...row.values,
          'notes': '',
          'address': null,
          'alternate_mobile': '',
        }),
      ],
    });
    final decoded = codec.decode(codec.encode(empty));
    expect(decoded.issues, isEmpty);
    expect(decoded.rows('Customers').single.values['notes'], '');
    expect(decoded.rows('Customers').single.values['alternate_mobile'], '');
    expect(decoded.rows('Customers').single.values['address'], isNull);
    expect(
      decoded.rows('Customers').single.canonical,
      empty.rows('Customers').single.canonical,
    );
  });

  test('formulas with cached shared strings are rejected instead of accepted as text', () {
    final edited = rewriteCustomerXml(bytes, (doc) {
      final name = cell(doc, 'B2');
      expect(name.getAttribute('t'), 's');
      name.children.add(
        XmlElement(XmlName('f'), [], [
          XmlText('HYPERLINK("untrusted", "cached")'),
        ]),
      );
    });
    final decoded = codec.decode(edited);
    expect(
      decoded.issues.any(
        (e) =>
            e.sheet == 'Customers' &&
            e.row == 2 &&
            e.field == 'name' &&
            e.message.contains('Formulas'),
      ),
      isTrue,
    );
  });

  test(
    'columns can be reordered without changing canonical persisted fields',
    () {
      final workbook = Excel.decodeBytes(bytes);
      final sheet = workbook['Customers'];
      for (final row in [1, 2]) {
        final first = sheet.cell(CellIndex.indexByString('A$row')).value;
        final last = sheet.cell(CellIndex.indexByString('H$row')).value;
        sheet.cell(CellIndex.indexByString('A$row')).value = last;
        sheet.cell(CellIndex.indexByString('H$row')).value = first;
      }
      final decoded = codec.decode(Uint8List.fromList(workbook.encode()!));
      expect(decoded.issues, isEmpty);
      expect(
        decoded.rows('Customers').single.canonical,
        data.rows('Customers').single.canonical,
      );
    },
  );

  test('numeric phones, date cells and floating-point money are rejected', () {
    final workbook = Excel.decodeBytes(bytes);
    workbook['Customers'].cell(CellIndex.indexByString('C2')).value =
        const IntCellValue(12345678);
    workbook['Customers'].cell(CellIndex.indexByString('G2')).value =
        const DateCellValue(year: 2025, month: 1, day: 1);
    workbook['Orders'].appendRow([
      TextCellValue('22222222-2222-4222-8222-222222222222'),
      TextCellValue('001'),
      TextCellValue('11111111-1111-4111-8111-111111111111'),
      TextCellValue('2025-01-01'),
      TextCellValue('2025-01-10'),
      TextCellValue('new'),
      const DoubleCellValue(2.5),
      null,
      TextCellValue('2025-01-01T00:00:00Z'),
      TextCellValue('2025-01-01T00:00:00Z'),
    ]);
    final decoded = codec.decode(Uint8List.fromList(workbook.encode()!));
    expect(
      decoded.issues.map((e) => e.field),
      containsAll(['mobile', 'created_at', 'discount_paise']),
    );
  });

  test(
    'missing sheets, extra sheets and duplicate headers are actionable errors',
    () {
      final workbook = Excel.decodeBytes(bytes);
      workbook.delete('Measurements');
      workbook['Unexpected'].appendRow([TextCellValue('unknown')]);
      workbook['Customers'].cell(CellIndex.indexByString('H1')).value =
          TextCellValue('id');
      final decoded = codec.decode(Uint8List.fromList(workbook.encode()!));
      expect(
        decoded.issues.map((e) => e.sheet),
        containsAll(['Measurements', 'Unexpected', 'Customers']),
      );
    },
  );

  test('corrupt and oversized files return safe diagnostics without parsing raw contents', () {
    expect(codec.decode(Uint8List.fromList([1, 2, 3])).issues, isNotEmpty);
    expect(codec.decode(Uint8List(workbookMaxBytes + 1)).issues, isNotEmpty);
    final corrupt = Uint8List.fromList(bytes)..[0] = 0;
    expect(codec.decode(corrupt).issues, isNotEmpty);
  });

  test('sparse out-of-range rows and columns are rejected before Excel allocates them', () {
    final sparse = rewriteCustomerXml(bytes, (doc) {
      final row = doc.descendants.whereType<XmlElement>().firstWhere(
        (e) => e.name.local == 'row' && e.getAttribute('r') == '2',
      );
      row.setAttribute('r', '999999');
    });
    expect(codec.decode(sparse).issues, isNotEmpty);
    final columns = rewriteCustomerXml(
      bytes,
      (doc) => cell(doc, 'B2').setAttribute('r', 'ZZ2'),
    );
    expect(codec.decode(columns).issues, isNotEmpty);
  });

  test(
    'expanded archive limits reject honest and forged small-size ZIP bombs',
    () {
      final archive = ZipDecoder().decodeBytes(bytes);
      final bomb = Uint8List(workbookMaxEntryBytes + 1024);
      archive.addFile(ArchiveFile('bomb.bin', bomb.length, bomb));
      final encoded = Uint8List.fromList(ZipEncoder().encode(archive)!);
      expect(encoded.length, lessThan(workbookMaxBytes));
      expect(codec.decode(encoded).issues, isNotEmpty);
      // Lie in the central directory; streaming inflation must still stop.
      final forged = Uint8List.fromList(encoded);
      final view = ByteData.sublistView(forged);
      for (var i = 0; i < forged.length - 46; i++) {
        if (view.getUint32(i, Endian.little) != 0x02014b50) continue;
        final length = view.getUint16(i + 28, Endian.little);
        if (i + 46 + length > forged.length) continue;
        if (utf8.decode(
              forged.sublist(i + 46, i + 46 + length),
              allowMalformed: true,
            ) ==
            'bomb.bin') {
          view.setUint32(i + 24, 4, Endian.little);
        }
      }
      expect(codec.decode(forged).issues, isNotEmpty);
    },
  );

  test(
    'DOCTYPE declarations are rejected and oversized cell text cannot export',
    () {
      final archive = ZipDecoder().decodeBytes(bytes);
      final payload = utf8.encode(
        '<!DOCTYPE worksheet [<!ENTITY x "value">]><worksheet/>',
      );
      archive.addFile(ArchiveFile('extra.xml', payload.length, payload));
      expect(
        codec.decode(Uint8List.fromList(ZipEncoder().encode(archive)!)).issues,
        isNotEmpty,
      );
      final original = data.rows('Customers').single;
      final long = WorkbookData({
        ...data.tables,
        'Customers': [
          WorkbookRow('Customers', 2, {
            ...original.values,
            'notes': 'x' * 32768,
          }),
        ],
      });
      expect(() => codec.encode(long), throwsFormatException);
    },
  );
}
