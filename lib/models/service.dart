class Service {
  final String id;

  // Hangi müşteri
  final String customerId;

  // Hangi cihaz
  final String deviceId;

  // Servisi yapan tekniker
  final String technicianId;

  // Servis tarihi
  final DateTime serviceDate;

  // Yapılan işlemler
  final List<String> operations;

  // Kullanılan ürünler
  final List<String> usedProducts;

  // Tahsilat
  final double totalPrice;
  final double paidAmount;

  // Notlar
  final String? note;

  // Durum
  final String status;

  const Service({
    required this.id,
    required this.customerId,
    required this.deviceId,
    required this.technicianId,
    required this.serviceDate,
    required this.operations,
    required this.usedProducts,
    required this.totalPrice,
    required this.paidAmount,
    this.note,
    required this.status,
  });
}
