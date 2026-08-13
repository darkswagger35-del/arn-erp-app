import '../../data/models/customer_model.dart';

abstract class CustomerRepository {
  Future<CustomerPage> listCustomers({
    int page = 1,
    int pageSize = 25,
    String search = '',
    String phone = '',
    bool? isActive,
    String city = '',
    String district = '',
    DateTime? startDate,
    DateTime? endDate,
  });

  Future<CustomerModel> createCustomer(CustomerModel customer);

  Future<CustomerModel> updateCustomer(CustomerModel customer);

  Future<void> toggleActive(String customerId, bool isActive);

  /// Soft-deletes the customer identified by [customerId] (sets deleted_at).
  /// The customer row is preserved so related records (e.g. devices) are not
  /// broken; it is simply excluded from normal customer queries afterwards.
  Future<void> deleteCustomer(String customerId);

  Future<CustomerModel?> getCustomer(String customerId);
}
