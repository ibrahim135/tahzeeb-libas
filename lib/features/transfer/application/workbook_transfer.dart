import 'dart:isolate';
import 'dart:typed_data';

import '../data/workbook_codec.dart';
import '../domain/workbook.dart';

abstract interface class WorkbookFiles {
  Future<Uint8List?> pick();
  Future<bool> save(Uint8List bytes, String fileName);
  Future<bool> share(Uint8List bytes, String fileName);
}

final class WorkbookTransfer {
  final WorkbookRepository repository;
  final WorkbookFiles files;
  WorkbookTransfer(this.repository, this.files);

  Future<Uint8List> export() async =>
      encodeWorkbook(await repository.snapshot());
  Future<Uint8List> template() async {
    final snapshot = await repository.snapshot();
    final blank = WorkbookData({
      for (final name in workbookColumns.keys)
        name: name == 'Metadata'
            ? snapshot
                  .rows(name)
                  .map(
                    (r) => r.text('key') == 'next_bill_number'
                        ? WorkbookRow(name, r.line, {
                            'key': 'next_bill_number',
                            'value': '1',
                          })
                        : r,
                  )
                  .toList()
            : [],
    });
    return encodeWorkbook(blank, template: true);
  }

  Future<ImportPreview?> pickAndPreview() async {
    final bytes = await files.pick();
    if (bytes == null) return null;
    final data = await Isolate.run(() => WorkbookCodec().decode(bytes));
    return repository.preview(data);
  }
}

Future<Uint8List> encodeWorkbook(WorkbookData data, {bool template = false}) =>
    Isolate.run(() => WorkbookCodec().encode(data, template: template));
