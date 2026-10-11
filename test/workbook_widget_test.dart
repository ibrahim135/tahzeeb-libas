import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tahzeeb_libas/app/providers.dart';
import 'package:tahzeeb_libas/features/transfer/application/workbook_transfer.dart';
import 'package:tahzeeb_libas/features/transfer/domain/workbook.dart';
import 'package:tahzeeb_libas/features/transfer/presentation/export_screen.dart';
import 'package:tahzeeb_libas/features/transfer/presentation/import_preview_screen.dart';

import 'widget_helpers.dart';

final class FakeFiles implements WorkbookFiles {
  int saves = 0, shares = 0;
  String? lastName;
  @override
  Future<Uint8List?> pick() async => null;
  @override
  Future<bool> save(Uint8List bytes, String fileName) async {
    saves++;
    lastName = fileName;
    return saves > 1;
  }

  @override
  Future<bool> share(Uint8List bytes, String fileName) async {
    shares++;
    lastName = fileName;
    return true;
  }
}

final class FakeWorkbookRepository implements WorkbookRepository {
  int commits = 0;
  bool acceptedDuplicates = false, replacedSettings = false;
  Completer<ImportResult>? pending;
  @override
  Future<WorkbookData> snapshot() async => WorkbookData({});
  @override
  Future<ImportPreview> preview(WorkbookData workbook) =>
      throw UnimplementedError(
        'This widget test opens an already prepared preview.',
      );
  @override
  Future<ImportResult> commit(
    ImportPreview preview, {
    bool acceptSimilarCustomers = false,
    bool replaceShopSettings = false,
  }) async {
    commits++;
    acceptedDuplicates = acceptSimilarCustomers;
    replacedSettings = replaceShopSettings;
    return pending?.future ??
        const ImportResult(1, settingsUpdated: true, counterUpdated: false);
  }
}

void main() {
  testWidgets(
    'saved file cancellation permits retry and sharing on a compact screen',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final files = FakeFiles();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [workbookFilesProvider.overrideWithValue(files)],
          child: MaterialApp(
            home: ExportScreen(
              bytes: Uint8List.fromList([1]),
              fileName: 'backup.xlsx',
              template: false,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Save file'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Cancelled.'), findsOneWidget);
      await tester.tap(find.text('Save file'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Workbook saved.'), findsOneWidget);
      await tester.tap(find.text('Share file'));
      await tester.pumpAndSettle();
      expect(files.saves, 2);
      expect(files.shares, 1);
      expect(files.lastName, 'backup.xlsx');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('invalid preview disables apply and cancel makes no commit', (
    tester,
  ) async {
    final repository = FakeWorkbookRepository();
    final preview = ImportPreview(
      workbook: WorkbookData({}),
      errors: [
        const WorkbookIssue(
          'Payments',
          7,
          'amount_paise',
          'Enter a positive whole amount.',
        ),
      ],
      duplicateWarnings: [],
      newCounts: {},
      existingCounts: {},
      settingsDiffer: false,
      reviewSignature: 'review',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [workbookRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => ImportPreviewScreen(preview: preview),
                  ),
                ),
                child: const Text('Open preview'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open preview'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Payments · row 7 · amount_paise'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Apply import'),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Cancel without changes'));
    await tester.pumpAndSettle();
    expect(find.text('Open preview'), findsOneWidget);
    expect(repository.commits, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'duplicates and shop replacement require both reviews and prevent double commit',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = FakeWorkbookRepository()
        ..pending = Completer<ImportResult>();
      final preview = ImportPreview(
        workbook: WorkbookData({
          'Customers': [
            WorkbookRow('Customers', 2, {
              'id': 'customer',
              'name': 'Example customer',
              'mobile': '0012345678',
            }),
          ],
          'ShopSettings': [
            WorkbookRow('ShopSettings', 2, {'id': 1, 'name': 'Imported shop'}),
          ],
        }),
        errors: [],
        duplicateWarnings: [
          const WorkbookIssue(
            'Customers',
            2,
            'name/phone',
            'Review this customer.',
          ),
        ],
        newCounts: {'Customers': 1},
        existingCounts: {'ShopSettings': 1},
        settingsDiffer: true,
        currentShopSettings: WorkbookRow('ShopSettings', 2, {
          'name': 'Current shop',
        }),
        reviewSignature: 'review',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [workbookRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp(home: ImportPreviewScreen(preview: preview)),
        ),
      );
      await reveal(tester, find.text('Apply import'));
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Apply import'),
            )
            .onPressed,
        isNull,
      );
      final customerCheck = find.widgetWithText(
        CheckboxListTile,
        'I reviewed the matching customers. These new rows represent separate customers.',
      );
      await reveal(tester, customerCheck);
      await tester.tap(customerCheck);
      await tester.pumpAndSettle();
      final settingsCheck = find.widgetWithText(
        CheckboxListTile,
        'Replace the current shop details with these imported details.',
      );
      await reveal(tester, settingsCheck);
      await tester.tap(settingsCheck);
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Apply import'));
      await tester.tap(find.text('Apply import'));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Apply import'),
            )
            .onPressed,
        isNull,
      );
      expect(repository.commits, 1);
      expect(repository.acceptedDuplicates, isTrue);
      expect(repository.replacedSettings, isTrue);
      repository.pending!.complete(
        const ImportResult(1, settingsUpdated: true, counterUpdated: false),
      );
      await tester.pumpAndSettle();
      await reveal(tester, find.textContaining('1 records added.'));
      expect(
        find.textContaining('Shop details replaced as confirmed.'),
        findsOneWidget,
      );
      expect(find.text('Apply import'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
