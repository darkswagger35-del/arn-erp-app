class Device {
  final String id;
  final String customerId;

  // QR
  final String qrCode;

  // Cihaz Bilgileri
  final bool isCompanyDevice; // Bizden alınan mı?
  final String brand;
  final String model;
  final String? serialNumber;

  // Özellikler
  final bool isPump;
  final bool isOpenCase;

  // Tarihler
  final DateTime installDate;
  final DateTime createdAt;

  const Device({
    required this.id,
    required this.customerId,
    required this.qrCode,
    required this.isCompanyDevice,
    required this.brand,
    required this.model,
    this.serialNumber,
    required this.isPump,
    required this.isOpenCase,
    required this.installDate,
    required this.createdAt,
  });
}
