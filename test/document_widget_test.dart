import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:printing/src/interface.dart';
import 'package:tahzeeb_libas/app/providers.dart';
import 'package:tahzeeb_libas/data/database/app_database.dart';
import 'package:tahzeeb_libas/features/documents/application/document_actions.dart';
import 'package:tahzeeb_libas/features/documents/domain/document.dart';
import 'package:tahzeeb_libas/features/documents/presentation/document_screen.dart';
import 'package:tahzeeb_libas/features/settings/data/settings_repository.dart';
import 'package:tahzeeb_libas/features/settings/presentation/shop_editor.dart';
import 'package:tahzeeb_libas/features/orders/data/drift_tailoring_repository.dart';

import 'fixtures.dart' as f;
import 'widget_helpers.dart';

class FakePrinting extends PrintingPlatform {
  Uint8List? printed;
  bool? dynamic;
  PdfPageFormat? format;
  @override
  Future<PrintingInfo> info() async =>
      const PrintingInfo(canRaster: true, canPrint: true);
  @override
  Stream<PdfRaster> raster(
    Uint8List document,
    List<int>? pages,
    double dpi,
  ) async* {
    yield PdfRaster(1, 1, Uint8List.fromList([255, 255, 255, 255]));
  }

  @override
  Future<bool> layoutPdf(
    Printer? printer,
    LayoutCallback onLayout,
    String name,
    PdfPageFormat format,
    bool dynamicLayout,
    bool usePrinterSettings,
    OutputType outputType,
    bool forceCustomPrintPaper,
  ) async {
    this.format = format;
    dynamic = dynamicLayout;
    printed = await onLayout(PdfPageFormat.letter);
    return false;
  }

  @override
  Future<List<Printer>> listPrinters() async => [];
  @override
  Future<Printer?> pickPrinter(Rect bounds) async => null;
  @override
  Future<bool> sharePdf(
    Uint8List bytes,
    String filename,
    Rect bounds,
    String? subject,
    String? body,
    List<String>? emails,
  ) async => false;
  @override
  Future<Uint8List> convertHtml(
    String html,
    String? baseUrl,
    PdfPageFormat format,
  ) async => Uint8List(0);
}

class FakeActions implements DocumentActions {
  final calls = <(String, Uint8List, String)>[];
  bool failShare = false;
  @override
  Future<bool> save(Uint8List bytes, String fileName) async {
    calls.add(('save', bytes, fileName));
    return false;
  }

  @override
  Future<bool> share(Uint8List bytes, String fileName) async {
    calls.add(('share', bytes, fileName));
    if (failShare) throw StateError('Private native error');
    return true;
  }

  @override
  Future<bool> print(Uint8List bytes, String fileName) async {
    calls.add(('print', bytes, fileName));
    return true;
  }
}

Future<void> waitForPdf(WidgetTester tester) async {
  for (var i = 0; i < 120; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    final save = find.widgetWithText(FilledButton, 'Save');
    if (save.evaluate().isNotEmpty &&
        tester.widget<FilledButton>(save).onPressed != null) {
      return;
    }
  }
  fail('PDF actions did not become available.');
}

void main() {
  late AppDatabase db;
  late PrintingPlatform original;
  late FakePrinting printing;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    original = PrintingPlatform.instance;
    printing = FakePrinting();
    PrintingPlatform.instance = printing;
  });
  tearDown(() async {
    PrintingPlatform.instance = original;
    await db.close();
  });

  test('Android print callback uses the same frozen A4 PDF and reports cancellation', () async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    expect(await AndroidDocumentActions().print(bytes, 'test.pdf'), isFalse);
    expect(printing.printed, same(bytes));
    expect(printing.dynamic, isFalse);
    expect(printing.format!.width, PdfPageFormat.a4.width);
  });
  testWidgets(
    'compact PDF screen keeps save/share/print on identical bytes and regenerates shop copy',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = f.customer();
      final o = f.order(c.id);
      await tester.runAsync(
        () => DriftTailoringRepository(db).createOrder(o, newCustomer: c),
      );
      final actions = FakeActions();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            documentActionsProvider.overrideWithValue(actions),
          ],
          child: MaterialApp(
            home: DocumentScreen(orderId: o.id, kind: DocumentKind.warehouse),
          ),
        ),
      );
      await waitForPdf(tester);
      for (final name in ['Save', 'Share', 'Print']) {
        await tester.tap(find.widgetWithText(FilledButton, name));
        await tester.pump();
      }
      expect(actions.calls, hasLength(3));
      expect(actions.calls[1].$2, same(actions.calls[0].$2));
      expect(actions.calls[2].$2, same(actions.calls[0].$2));
      expect(actions.calls[0].$3, contains(o.id));
      expect(actions.calls[0].$3, endsWith('_original.pdf'));
      expect(find.text('Print job sent. Check the printer.'), findsOneWidget);
      await tester.tap(find.byType(Switch));
      await waitForPdf(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pump();
      expect(actions.calls.last.$3, endsWith('_shop.pdf'));
      expect(actions.calls.last.$2, isNot(same(actions.calls.first.$2)));
      expect(find.text('Save cancelled.'), findsOneWidget);
      actions.failShare = true;
      await tester.tap(find.widgetWithText(FilledButton, 'Share'));
      await tester.pump();
      expect(find.textContaining('Could not share the PDF.'), findsOneWidget);
      expect(find.textContaining('Private native error'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
  testWidgets(
    'shop editor validates name, guards unsaved back and persists receipt notes',
    (tester) async {
      final repo = SettingsRepository(db);
      final initial = (await tester.runAsync(repo.get))!;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [databaseProvider.overrideWithValue(db)],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => ShopEditor(initial: initial),
                    ),
                  ),
                  child: const Text('Open shop'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open shop'));
      await tester.pumpAndSettle();
      final name = find.widgetWithText(TextFormField, 'Shop name');
      await tester.enterText(name, '');
      await reveal(tester, find.text('Save shop details'));
      await tester.tap(find.text('Save shop details'));
      await tester.pumpAndSettle();
      expect(find.text('Enter the shop name.'), findsOneWidget);
      await tester.enterText(name, 'New shop');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Customer receipt notes (optional)'),
        'Thank you\nCollect on time',
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Discard unsaved changes?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Save shop details'));
      await tester.tap(find.text('Save shop details'));
      await tester.pumpAndSettle();
      final saved = (await tester.runAsync(repo.get))!;
      expect(saved.name, 'New shop');
      expect(saved.receiptNotes, 'Thank you\nCollect on time');
      expect(find.text('Open shop'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
