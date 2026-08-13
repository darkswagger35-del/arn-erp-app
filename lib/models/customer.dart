class Customer {
  final String id;
  final String fullName;
  final String phone;
  final String address;
  final String? note;
  final DateTime createdAt;
  final String createdBy;

  const Customer({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.address,
    this.note,
    required this.createdAt,
    required this.createdBy,
  });
}
