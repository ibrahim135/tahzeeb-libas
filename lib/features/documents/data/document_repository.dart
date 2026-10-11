import '../../../data/database/app_database.dart';
import '../../orders/data/drift_tailoring_repository.dart';
import '../../settings/data/settings_repository.dart';
import '../domain/document.dart';

final class DocumentRepository {
  final AppDatabase database;
  DocumentRepository(this.database);
  Future<BillDocumentSnapshot> load(String orderId) =>
      database.transaction(() async {
        final records = DriftTailoringRepository(database);
        final order = await records.getOrder(orderId);
        if (order == null) {
          throw const FormatException('The saved bill was not found.');
        }
        final customer = await records.getCustomer(order.customerId);
        if (customer == null) {
          throw const FormatException('The bill customer was not found.');
        }
        final shop = await SettingsRepository(database).get();
        return BillDocumentSnapshot(
          order,
          customer,
          shop,
          DateTime.now().toUtc(),
        );
      });
}
