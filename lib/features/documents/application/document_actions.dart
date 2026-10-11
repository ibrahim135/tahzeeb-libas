import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../../../shared/platform/system_files.dart';

abstract interface class DocumentActions {
  Future<bool> save(Uint8List bytes, String fileName);
  Future<bool> share(Uint8List bytes, String fileName);
  Future<bool> print(Uint8List bytes, String fileName);
}

final class AndroidDocumentActions implements DocumentActions {
  @override
  Future<bool> save(Uint8List bytes, String fileName) => SystemFiles.save(
    bytes,
    fileName,
    mimeType: 'application/pdf',
    title: 'Save PDF',
  );
  @override
  Future<bool> share(Uint8List bytes, String fileName) => SystemFiles.share(
    bytes,
    fileName,
    mimeType: 'application/pdf',
    title: 'Tahzeeb Libas document',
    cacheDirectory: 'pdf_shares',
  );
  @override
  Future<bool> print(Uint8List bytes, String fileName) => Printing.layoutPdf(
    onLayout: (_) async => bytes,
    name: fileName,
    format: PdfPageFormat.a4,
    dynamicLayout: false,
  );
}
