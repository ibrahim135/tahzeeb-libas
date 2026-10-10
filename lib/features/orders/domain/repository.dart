import 'records.dart';
import 'order_query.dart';

abstract interface class TailoringRepository {
  Future<void> saveCustomer(
    CustomerRecord customer, {
    DateTime? expectedUpdatedAt,
  });
  Future<CustomerRecord?> getCustomer(String id);
  Stream<List<CustomerRecord>> watchCustomers({String search = ''});
  Future<List<CustomerRecord>> potentialDuplicates(CustomerRecord customer);
  Future<void> updateOrder(
    OrderRecord order, {
    required DateTime expectedUpdatedAt,
    CustomerRecord? newCustomer,
  });
  Stream<List<OrderSummary>> watchOrders(OrderQuery query);
  Future<void> createOrder(OrderRecord order, {CustomerRecord? newCustomer});
  Future<OrderRecord?> getOrder(String id);
  Stream<int> watchOrderCount();
  Future<String> suggestBillNumber();
}
