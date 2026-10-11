import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/document.dart';

final class DocumentFonts {
  final Uint8List regular, bold;
  const DocumentFonts(this.regular, this.bold);
  static Future<DocumentFonts> load() async {
    final regular = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
    final bold = await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
    return DocumentFonts(
      Uint8List.sublistView(regular),
      Uint8List.sublistView(bold),
    );
  }
}

final class DocumentPdf {
  final DocumentFonts fonts;
  const DocumentPdf(this.fonts);
  Future<Uint8List> build(DocumentContent content, {bool shopCopy = false}) =>
      compute(_render, (content, fonts, shopCopy));
}

Future<Uint8List> _render(
  (DocumentContent, DocumentFonts, bool) request,
) async {
  final (content, fonts, shopCopy) = request;
  final regular = pw.Font.ttf(ByteData.sublistView(fonts.regular));
  final bold = pw.Font.ttf(ByteData.sublistView(fonts.bold));
  final pdf = pw.Document(
    theme: pw.ThemeData.withFont(
      base: regular,
      bold: bold,
      italic: regular,
      boldItalic: bold,
    ),
    title: content.kind.label,
    author: 'Tahzeeb Libas',
    creator: 'Tahzeeb Libas',
  );
  final parsedRegular = regular.getFont(pw.Context(document: pdf.document));
  final parsedBold = bold.getFont(pw.Context(document: pdf.document));
  final texts = [
    content.kind.label,
    content.billNumber,
    shopCopy ? 'Shop copy' : content.kind.copyLabel,
    ...content.blocks.map((b) => b.text),
  ];
  for (final text in texts) {
    for (final rune in text.runes) {
      if (rune == 10 || rune == 13 || rune == 9) continue;
      if (!parsedRegular.isRuneSupported(rune) ||
          !parsedBold.isRuneSupported(rune)) {
        throw const FormatException(
          'PDF text contains characters unsupported by the bundled English font. Edit the relevant text before generating a document.',
        );
      }
    }
  }
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      // Large orders may legitimately exceed the library's 20-page default.
      // Exceeding this safety bound fails generation; it never returns a partial PDF.
      maxPages: 2000,
      header: (context) {
        if (context.pageNumber > 2000) {
          throw const FormatException(
            'PDF exceeds 2,000 pages. Shorten the notes before generating it.',
          );
        }
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              '${content.kind.label} - ${shopCopy ? 'Shop copy' : content.kind.copyLabel}',
              style: pw.TextStyle(font: bold, fontSize: 14),
            ),
            if (context.pageNumber > 1)
              pw.Text(
                'Bill: ${content.billNumber}',
                style: const pw.TextStyle(fontSize: 10),
              ),
            pw.Divider(),
          ],
        );
      },
      footer: (context) => pw.Column(
        children: [
          pw.Divider(),
          pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 9),
          ),
        ],
      ),
      // Text is a SpanningWidget, placed directly in MultiPage. Avoid wrapping
      // long descriptions/notes in unbreakable Cards, Rows or Tables.
      build: (_) => [
        for (final block in content.blocks) ...[
          if (block.heading) ...[
            pw.NewPage(freeSpace: 40),
            pw.SizedBox(height: 7),
          ],
          pw.Text(
            overflow: pw.TextOverflow.span,
            block.text
                .replaceAll('\r\n', '\n')
                .replaceAll('\r', '\n')
                .replaceAll('\t', '    '),
            style: pw.TextStyle(
              font: block.heading ? bold : regular,
              fontSize: block.heading ? 12 : 10,
              lineSpacing: 1.5,
            ),
          ),
          pw.SizedBox(height: 2),
        ],
      ],
    ),
  );
  return pdf.save();
}
