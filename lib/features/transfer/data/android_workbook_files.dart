import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

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
  Future<bool> save(Uint8List bytes, String fileName) async =>
      await FilePicker.saveFile(
        fileName: fileName,
        bytes: bytes,
        mimeType: workbookMimeType,
        dialogTitle: 'Save Excel workbook',
      ) !=
      null;

  @override
  Future<bool> share(Uint8List bytes, String fileName) async {
    final directory = Directory(
      p.join((await getTemporaryDirectory()).path, 'workbook_shares'),
    );
    await directory.create(recursive: true);
    final expiry = DateTime.now().subtract(const Duration(days: 7));
    await for (final entity in directory.list()) {
      if (entity is Directory &&
          (await entity.stat()).modified.isBefore(expiry)) {
        await entity.delete(recursive: true);
      }
    }
    // Retain recent files while receiving apps read them; remove stale copies
    // on the next share. These temporary files are not durable backups.
    final folder = Directory(p.join(directory.path, const Uuid().v4()));
    await folder.create();
    final file = File(p.join(folder.path, fileName));
    await file.writeAsBytes(bytes, flush: true);
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: workbookMimeType)],
        title: 'Tahzeeb Libas Excel workbook',
      ),
    );
    return result.status != ShareResultStatus.dismissed;
  }
}
