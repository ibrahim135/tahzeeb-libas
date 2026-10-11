import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:xml/xml.dart';

import '../domain/workbook.dart';

/// Pure file work; application code runs these methods in a worker isolate.
final class WorkbookCodec {
  Uint8List encode(WorkbookData data, {bool template = false}) {
    final excel = Excel.createExcel();
    for (final entry in workbookColumns.entries) {
      final sheet = excel[entry.key];
      sheet.appendRow(entry.value.map(TextCellValue.new).toList());
      final rows = data.rows(entry.key);
      if (rows.length > workbookMaxRows) {
        throw const FormatException('Too many rows for a supported workbook.');
      }
      for (final row in rows) {
        sheet.appendRow([
          for (final field in entry.value) _cell(row.values[field]),
        ]);
      }
    }
    excel.delete('Sheet1');
    if (template) _examples(excel);
    excel.setDefaultSheet(template ? 'Examples' : 'Orders');
    final encoded = Uint8List.fromList(excel.encode()!);
    // The same resource limits apply to exports and imports.
    _boundedArchive(encoded);
    return encoded;
  }

  CellValue? _cell(Object? value) {
    if (value == null) return null;
    if (value is int) return IntCellValue(value);
    final text = value as String;
    if (text.length > 32767) {
      throw const FormatException(
        'A cell exceeds Excel’s 32767-character limit. Shorten long notes before exporting.',
      );
    }
    // Even =, +, -, @ prefixes remain literal text, never FormulaCellValue.
    return TextCellValue(text);
  }

  WorkbookData decode(Uint8List bytes) {
    final issues = <WorkbookIssue>[];
    final tables = <String, List<WorkbookRow>>{};
    try {
      final archive = _boundedArchive(bytes);
      final excel = Excel.decodeBytes(ZipEncoder().encode(archive)!);
      for (final name in excel.tables.keys) {
        if (!workbookColumns.containsKey(name) && name != 'Examples') {
          issues.add(
            WorkbookIssue(
              name,
              1,
              'sheet',
              'Unexpected sheet. Use the current template.',
            ),
          );
        }
      }
      for (final entry in workbookColumns.entries) {
        final sheet = excel.tables[entry.key];
        if (sheet == null || sheet.rows.isEmpty) {
          issues.add(
            WorkbookIssue(
              entry.key,
              1,
              'sheet',
              'Required sheet or header is missing.',
            ),
          );
          continue;
        }
        final rows = sheet.rows;
        final headers = rows.first.map((cell) => cell?.value).toList();
        final names = [
          for (final cell in headers)
            cell is TextCellValue ? cell.toString() : '',
        ];
        if (names.length != entry.value.length ||
            names.toSet().length != names.length ||
            !entry.value.every(names.contains)) {
          issues.add(
            WorkbookIssue(
              entry.key,
              1,
              'header',
              'Headers must contain exactly: ${entry.value.join(', ')}.',
            ),
          );
          continue;
        }
        final records = <WorkbookRow>[];
        for (var index = 1; index < rows.length; index++) {
          final cells = rows[index];
          if (cells.every(
            (cell) =>
                cell?.value == null ||
                (cell!.value is TextCellValue && cell.value.toString().isEmpty),
          )) {
            continue;
          }
          final values = <String, Object?>{};
          final before = issues.length;
          for (var col = 0; col < names.length; col++) {
            final field = names[col];
            final value = col < cells.length ? cells[col]?.value : null;
            final optional = workbookOptionalColumns.contains(field);
            final isInt =
                workbookIntegerColumns.contains(field) ||
                (entry.key == 'ShopSettings' && field == 'id');
            if (value is FormulaCellValue) {
              issues.add(
                WorkbookIssue(
                  entry.key,
                  index + 1,
                  field,
                  'Formulas are not allowed. Enter a literal value.',
                ),
              );
            } else if (value == null ||
                (value is TextCellValue &&
                    value.toString().isEmpty &&
                    !optional)) {
              values[field] = null;
              if (!optional) {
                issues.add(
                  WorkbookIssue(
                    entry.key,
                    index + 1,
                    field,
                    'Required value is missing.',
                  ),
                );
              }
            } else if (isInt) {
              final number = value is IntCellValue
                  ? value.value
                  : value is TextCellValue &&
                        RegExp(r'^\d{1,13}$').hasMatch(value.toString())
                  ? int.tryParse(value.toString())
                  : null;
              if (number == null) {
                issues.add(
                  WorkbookIssue(
                    entry.key,
                    index + 1,
                    field,
                    'Enter a whole number, without formulas or decimal fractions.',
                  ),
                );
              } else {
                values[field] = number;
              }
            } else if (value is TextCellValue &&
                value.toString().length <= 32767) {
              values[field] = value.toString();
            } else {
              issues.add(
                WorkbookIssue(
                  entry.key,
                  index + 1,
                  field,
                  'Use a text cell. Dates use ISO text; IDs, phones and bills must retain leading zeroes.',
                ),
              );
            }
          }
          if (issues.length == before) {
            records.add(WorkbookRow(entry.key, index + 1, values));
          }
        }
        tables[entry.key] = records;
      }
    } catch (_) {
      // Do not expose parser exceptions containing untrusted personal data.
      issues.add(
        const WorkbookIssue(
          'Workbook',
          1,
          'file',
          'Cannot read this workbook. Use an unencrypted .xlsx within the documented size and row limits.',
        ),
      );
    }
    return WorkbookData(tables, issues: issues);
  }

  /// Inspect the directory before decompression. Stream each deflated member
  /// into a bounded sink, including archives that lie about expanded sizes.
  /// Repack validated bytes as STORE so Excel never inflates untrusted input.
  Archive _boundedArchive(Uint8List bytes) {
    if (bytes.length < 22 || bytes.length > workbookMaxBytes) {
      throw const FormatException('File size limit.');
    }
    final view = ByteData.sublistView(bytes);
    var end = -1;
    for (var i = bytes.length - 22; i >= 0 && i >= bytes.length - 65557; i--) {
      if (view.getUint32(i, Endian.little) == 0x06054b50 &&
          i + 22 + view.getUint16(i + 20, Endian.little) == bytes.length) {
        end = i;
        break;
      }
    }
    if (end < 0 ||
        view.getUint16(end + 4, Endian.little) != 0 ||
        view.getUint16(end + 6, Endian.little) != 0 ||
        view.getUint16(end + 10, Endian.little) > 128 ||
        view.getUint32(end + 12, Endian.little) > 65536) {
      throw const FormatException('Unsupported ZIP directory.');
    }
    final directory = ZipDirectory.read(InputStream(bytes));
    if (directory.fileHeaders.length !=
            directory.totalCentralDirectoryEntries ||
        directory.fileHeaders.length > 128) {
      throw const FormatException('Invalid archive directory.');
    }
    final archive = Archive();
    var expanded = 0;
    var totalRows = 0;
    var sheets = 0;
    final names = <String>{};
    for (final header in directory.fileHeaders) {
      if (!names.add(header.filename) ||
          (header.generalPurposeBitFlag & 1) != 0 ||
          (header.uncompressedSize ?? workbookMaxEntryBytes + 1) >
              workbookMaxEntryBytes ||
          !{0, 8}.contains(header.compressionMethod) ||
          header.file!.compressionMethod != header.compressionMethod ||
          header.filename.contains('vbaProject') ||
          header.filename.contains('externalLinks')) {
        throw const FormatException('Unsupported archive member.');
      }
      final raw = header.file!.rawContent!.toUint8List();
      final sink = _BoundedBytes(
        workbookMaxEntryBytes < workbookMaxExpandedBytes - expanded
            ? workbookMaxEntryBytes
            : workbookMaxExpandedBytes - expanded,
      );
      if (header.compressionMethod == 8) {
        final conversion = io.ZLibDecoder(raw: true)
            .startChunkedConversion(sink);
        for (var offset = 0; offset < raw.length; offset += 1024) {
          conversion.add(
            Uint8List.sublistView(
              raw,
              offset,
              offset + 1024 < raw.length ? offset + 1024 : raw.length,
            ),
          );
        }
        conversion.close();
      } else {
        sink.add(raw);
        sink.close();
      }
      var content = sink.bytes.takeBytes();
      expanded += content.length;
      if (content.length != header.uncompressedSize ||
          getCrc32(content) != header.crc32) {
        throw const FormatException('Archive checksum or length mismatch.');
      }
      if (header.filename.endsWith('.xml')) {
        final text = utf8.decode(content);
        if (text.contains('<!DOCTYPE') || text.contains('<!ENTITY')) {
          throw const FormatException('XML declarations are not supported.');
        }
        if (header.filename.startsWith('xl/worksheets/')) {
          sheets++;
          final doc = XmlDocument.parse(text);
          final rows = doc.descendants
              .whereType<XmlElement>()
              .where((e) => e.name.local == 'row')
              .toList();
          totalRows += rows.length;
          if (sheets > 8 ||
              rows.length > workbookMaxRows + 1 ||
              totalRows > workbookMaxTotalRows + 8) {
            throw const FormatException('Workbook row limit.');
          }
          final seenRows = <int>{};
          var markedFormula = false;
          for (final row in rows) {
            final number = int.tryParse(row.getAttribute('r') ?? '');
            if (number == null ||
                number < 1 ||
                number > workbookMaxRows + 1 ||
                !seenRows.add(number)) {
              throw const FormatException('Invalid row position.');
            }
            final seenCells = <String>{};
            for (final cell in row.childElements.where(
              (e) => e.name.local == 'c',
            )) {
              final formula = cell.childElements
                  .where((e) => e.name.local == 'f')
                  .firstOrNull;
              if (formula != null) {
                // Excel can otherwise mistake a formula with a cached shared
                // string for text. Mark all formulas for row-specific rejection.
                final literal = formula.innerText;
                cell.children.remove(formula);
                cell.children.add(
                  XmlElement(XmlName('f'), [], [XmlText(literal)]),
                );
                cell.setAttribute('t', 'n');
                markedFormula = true;
              }
              final ref = cell.getAttribute('r') ?? '';
              final match = RegExp(r'^([A-Z]{1,2})(\d+)$').firstMatch(ref);
              if (match == null ||
                  int.parse(match[2]!) != number ||
                  !seenCells.add(ref)) {
                throw const FormatException('Invalid cell position.');
              }
              var col = 0;
              for (final char in match[1]!.codeUnits) {
                col = col * 26 + char - 64;
              }
              if (col > 32) {
                throw const FormatException('Workbook column limit.');
              }
            }
          }
          if (markedFormula) {
            content = Uint8List.fromList(utf8.encode(doc.toXmlString()));
          }
        }
      }
      archive.addFile(
        ArchiveFile(header.filename, content.length, content)..compress = false,
      );
    }
    if (totalRows - sheets > workbookMaxTotalRows) {
      throw const FormatException('Workbook total row limit.');
    }
    if (!names.contains('xl/workbook.xml') ||
        !names.contains('[Content_Types].xml')) {
      throw const FormatException('Not an XLSX workbook.');
    }
    return archive;
  }

  void _examples(Excel excel) {
    final sheet = excel['Examples'];
    sheet.appendRow([
      TextCellValue(
        'READ FIRST — examples are guidance only and never imported.',
      ),
    ]);
    sheet.appendRow([
      TextCellValue(
        'Copy related rows into the matching data sheets. Use fresh UUIDs for each new customer, order, garment and payment.',
      ),
    ]);
    sheet.appendRow([
      TextCellValue(
        'Format IDs, phone numbers, bills, measurements, dates and timestamps as Text. Money is integer paise: 10000 = INR 100.00.',
      ),
    ]);
    sheet.appendRow([
      TextCellValue(
        'Dates: YYYY-MM-DD. Timestamps: YYYY-MM-DDTHH:mm:ss.sssZ. Every measurement is optional. No formulas.',
      ),
    ]);
    sheet.appendRow([
      TextCellValue(
        'Leave ShopSettings blank to retain current shop details. A populated changed row requires confirmation.',
      ),
    ]);
    final examples = <String, List<Object?>>{
      'Customers': [
        '11111111-1111-4111-8111-111111111111',
        'Example Customer',
        '0012345678',
        null,
        null,
        'Replace example details',
        '2025-01-01T00:00:00.000Z',
        '2025-01-01T00:00:00.000Z',
      ],
      'Orders': [
        '22222222-2222-4222-8222-222222222222',
        'EXAMPLE-001',
        '11111111-1111-4111-8111-111111111111',
        '2025-01-01',
        '2025-01-10',
        'new',
        0,
        null,
        '2025-01-01T00:00:00.000Z',
        '2025-01-01T00:00:00.000Z',
      ],
      'OrderItems': [
        '33333333-3333-4333-8333-333333333333',
        '22222222-2222-4222-8222-222222222222',
        0,
        'shirt',
        null,
        1,
        100000,
        'Special cut',
        'upper',
        'inches',
        'Loose fitting\nAdjust cuffs',
        '2025-01-01T00:00:00.000Z',
        '2025-01-01T00:00:00.000Z',
      ],
      'Measurements': [
        '33333333-3333-4333-8333-333333333333',
        'upper_length',
        '30.125',
      ],
      'Payments': [
        '44444444-4444-4444-8444-444444444444',
        '22222222-2222-4222-8222-222222222222',
        25000,
        '2025-01-01',
        'Cash',
        'Advance',
        '2025-01-01T00:00:00.000Z',
        '2025-01-01T00:00:00.000Z',
        null,
        null,
        null,
      ],
    };
    for (final entry in examples.entries) {
      sheet.appendRow([TextCellValue(entry.key)]);
      sheet.appendRow(
        workbookColumns[entry.key]!.map(TextCellValue.new).toList(),
      );
      sheet.appendRow(entry.value.map(_cell).toList());
      sheet.appendRow([]);
    }
    sheet.appendRow([
      TextCellValue(
        'Types: sherwani, suit, jothpuri, sadri, pant, shirt, kurta, payjama, thobe, joota, pagdi. Sherwani variants: sherwani/three_piece. Suit: two_piece/three_piece/four_piece. Others leave variant blank.',
      ),
    ]);
    sheet.appendRow([
      TextCellValue(
        'Configurations: upper/lower/both/none. Statuses: new/in_progress/ready/delivered/cancelled. See docs/WORKBOOK_SCHEMA.md for every field and limit.',
      ),
    ]);
  }
}

final class _BoundedBytes implements Sink<List<int>> {
  final int limit;
  final BytesBuilder bytes = BytesBuilder(copy: false);
  int count = 0;
  _BoundedBytes(this.limit);
  @override
  void add(List<int> data) {
    count += data.length;
    if (count > limit) throw const FormatException('Expanded archive limit.');
    bytes.add(data);
  }

  @override
  void close() {}
}
