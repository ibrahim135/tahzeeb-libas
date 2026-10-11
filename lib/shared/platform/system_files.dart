import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

/// System save/share integrations, without broad storage permissions.
final class SystemFiles {
  static Future<bool> save(
    Uint8List bytes,
    String fileName, {
    required String mimeType,
    required String title,
  }) async =>
      await FilePicker.saveFile(
        fileName: fileName,
        bytes: bytes,
        mimeType: mimeType,
        dialogTitle: title,
      ) !=
      null;

  static Future<bool> share(
    Uint8List bytes,
    String fileName, {
    required String mimeType,
    required String title,
    required String cacheDirectory,
  }) async {
    if (p.basename(fileName) != fileName) {
      throw ArgumentError('Invalid file name.');
    }
    final directory = Directory(
      p.join((await getTemporaryDirectory()).path, cacheDirectory),
    );
    await directory.create(recursive: true);
    final expiry = DateTime.now().subtract(const Duration(days: 7));
    await for (final entity in directory.list()) {
      if (entity is Directory &&
          (await entity.stat()).modified.isBefore(expiry)) {
        await entity.delete(recursive: true);
      }
    }
    // Retain recent files while receiving apps read them. These are not backups.
    final folder = Directory(p.join(directory.path, const Uuid().v4()));
    await folder.create();
    final file = File(p.join(folder.path, fileName));
    await file.writeAsBytes(bytes, flush: true);
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: mimeType)],
        title: title,
      ),
    );
    return result.status != ShareResultStatus.dismissed;
  }
}
