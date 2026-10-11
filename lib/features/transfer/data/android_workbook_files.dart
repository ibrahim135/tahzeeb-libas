import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../../../shared/platform/system_files.dart';
import '../application/workbook_transfer.dart';
import '../domain/workbook.dart';

const workbookMimeType =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

/// Uses Android's system document picker/save dialog and share sheet.
/// No broad storage permission or network operation is needed.
final class AndroidWorkbookFiles implements WorkbookFiles {
  @override
  Future<Uint8List?> pick() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      dialogTitle: 'Choose a Tahzeeb Libas workbook',
    );
    if (file == null) {
      return null;
    }
    if (file.extension?.toLowerCase() != 'xlsx') {
      throw const FormatException('Choose an .xlsx workbook.');
    }
    final length = await file.length();
    if (length != null && length > workbookMaxBytes) {
      throw const FormatException('Workbook exceeds the 8 MiB file limit.');
    }
    final result = BytesBuilder(copy: false);
    var count = 0;
    // Unknown provider lengths still receive the same hard streaming limit.
    await for (final bytes in file.readAsByteStream()) {
      count += bytes.length;
      if (count > workbookMaxBytes) {
        throw const FormatException('Workbook exceeds the 8 MiB file limit.');
      }
      result.add(bytes);
    }
    return result.takeBytes();
  }

  @override
  Future<bool> save(Uint8List bytes, String fileName) => SystemFiles.save(
    bytes,
    fileName,
    mimeType: workbookMimeType,
    title: 'Save Excel workbook',
  );
  @override
  Future<bool> share(Uint8List bytes, String fileName) => SystemFiles.share(
    bytes,
    fileName,
    mimeType: workbookMimeType,
    title: 'Tahzeeb Libas Excel workbook',
    cacheDirectory: 'workbook_shares',
  );
}
