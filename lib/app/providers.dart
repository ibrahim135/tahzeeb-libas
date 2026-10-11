import '../features/settings/data/settings_repository.dart';
import '../features/settings/domain/shop_settings.dart';
import '../features/documents/data/document_repository.dart';
import '../features/documents/application/document_pdf.dart';
import '../features/documents/application/document_actions.dart';

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/app_database.dart';
import '../features/orders/data/drift_tailoring_repository.dart';
import '../features/orders/domain/records.dart';
import '../features/orders/domain/order_query.dart';
import '../features/orders/domain/repository.dart';
import '../features/transfer/application/workbook_transfer.dart';
import '../features/transfer/data/android_workbook_files.dart';
import '../features/transfer/data/drift_workbook_repository.dart';
import '../features/transfer/domain/workbook.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase.production();
  ref.onDispose(() => unawaited(database.close()));
  return database;
});
final repositoryProvider = Provider<TailoringRepository>(
  (ref) => DriftTailoringRepository(ref.watch(databaseProvider)),
);
final customersProvider = StreamProvider<List<CustomerRecord>>(
  (ref) => ref.watch(repositoryProvider).watchCustomers(),
);
final orderCountProvider = StreamProvider<int>(
  (ref) => ref.watch(repositoryProvider).watchOrderCount(),
);

final searchedCustomersProvider =
    StreamProvider.family<List<CustomerRecord>, String>(
      (ref, search) =>
          ref.watch(repositoryProvider).watchCustomers(search: search),
    );
final ordersProvider = StreamProvider.family<List<OrderSummary>, OrderQuery>(
  (ref, query) => ref.watch(repositoryProvider).watchOrders(query),
);
final orderProvider = FutureProvider.autoDispose.family<OrderRecord?, String>(
  (ref, id) => ref.watch(repositoryProvider).getOrder(id),
);
final customerProvider = FutureProvider.autoDispose
    .family<CustomerRecord?, String>(
      (ref, id) => ref.watch(repositoryProvider).getCustomer(id),
    );

final workbookRepositoryProvider = Provider<WorkbookRepository>(
  (ref) => DriftWorkbookRepository(ref.watch(databaseProvider)),
);
final workbookFilesProvider = Provider<WorkbookFiles>(
  (ref) => AndroidWorkbookFiles(),
);
final workbookTransferProvider = Provider<WorkbookTransfer>(
  (ref) => WorkbookTransfer(
    ref.watch(workbookRepositoryProvider),
    ref.watch(workbookFilesProvider),
  ),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(databaseProvider)),
);
final shopSettingsProvider = StreamProvider<ShopSettingsRecord>(
  (ref) => ref.watch(settingsRepositoryProvider).watch(),
);
final documentRepositoryProvider = Provider<DocumentRepository>(
  (ref) => DocumentRepository(ref.watch(databaseProvider)),
);
final documentPdfProvider = FutureProvider<DocumentPdf>(
  (ref) async => DocumentPdf(await DocumentFonts.load()),
);
final documentActionsProvider = Provider<DocumentActions>(
  (ref) => AndroidDocumentActions(),
);
