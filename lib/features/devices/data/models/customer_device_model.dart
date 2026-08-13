const Object _unset = Object();

T? _valueOr<T>(Object? value, T? current) {
  if (identical(value, _unset)) {
    return current;
  }
  return value as T?;
}

String _formatDateOnly(DateTime? value) {
  if (value == null) {
    return '';
  }
  final utcValue = value.toUtc();
  final year = utcValue.year.toString().padLeft(4, '0');
  final month = utcValue.month.toString().padLeft(2, '0');
  final day = utcValue.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

DateTime? _parseDateTime(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is DateTime) {
    return value;
  }
  return DateTime.tryParse(value.toString());
}

String? _normalizeNullableText(Object? value) {
  if (value == null) {
    return null;
  }
  final normalized = value.toString().trim();
  return normalized.isEmpty ? null : normalized;
}

enum DeviceType {
  reverseOsmosis,
  underCounter,
  counterTop,
  industrial,
  softener,
  other;

  static DeviceType fromValue(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'under_counter':
        return DeviceType.underCounter;
      case 'counter_top':
        return DeviceType.counterTop;
      case 'industrial':
        return DeviceType.industrial;
      case 'softener':
        return DeviceType.softener;
      case 'other':
        return DeviceType.other;
      case 'reverse_osmosis':
      default:
        return DeviceType.reverseOsmosis;
    }
  }

  String get value {
    switch (this) {
      case DeviceType.reverseOsmosis:
        return 'reverse_osmosis';
      case DeviceType.underCounter:
        return 'under_counter';
      case DeviceType.counterTop:
        return 'counter_top';
      case DeviceType.industrial:
        return 'industrial';
      case DeviceType.softener:
        return 'softener';
      case DeviceType.other:
        return 'other';
    }
  }

  String get label {
    switch (this) {
      case DeviceType.reverseOsmosis:
        return 'Ters Ozmoz';
      case DeviceType.underCounter:
        return 'Tezgâh Altı';
      case DeviceType.counterTop:
        return 'Tezgâh Üstü';
      case DeviceType.industrial:
        return 'Endüstriyel';
      case DeviceType.softener:
        return 'Su Yumuşatma';
      case DeviceType.other:
        return 'Diğer';
    }
  }
}

enum PumpType {
  pumped,
  nonPumped,
  unknown;

  static PumpType fromValue(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'non_pumped':
        return PumpType.nonPumped;
      case 'unknown':
        return PumpType.unknown;
      case 'pumped':
      default:
        return PumpType.pumped;
    }
  }

  String get value {
    switch (this) {
      case PumpType.pumped:
        return 'pumped';
      case PumpType.nonPumped:
        return 'non_pumped';
      case PumpType.unknown:
        return 'unknown';
    }
  }

  String get label {
    switch (this) {
      case PumpType.pumped:
        return 'Pompalı';
      case PumpType.nonPumped:
        return 'Pompasız';
      case PumpType.unknown:
        return 'Belirtilmemiş';
    }
  }
}

class CustomerDeviceModel {
  const CustomerDeviceModel({
    this.id,
    this.companyId,
    this.customerId,
    this.customerName,
    this.customerPhone,
    this.customerAddress,
    this.brand,
    this.model,
    required this.deviceType,
    required this.pumpType,
    this.serialNumber,
    this.qrCode,
    this.membraneType,
    this.installationDate,
    this.lastMaintenanceDate,
    this.nextMaintenanceDate,
    this.description,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
  });

  final String? id;
  final String? companyId;
  final String? customerId;
  final String? customerName;
  final String? customerPhone;
  final String? customerAddress;
  final String? brand;
  final String? model;
  final DeviceType deviceType;
  final PumpType pumpType;
  final String? serialNumber;
  final String? qrCode;
  final String? membraneType;
  final DateTime? installationDate;
  final DateTime? lastMaintenanceDate;
  final DateTime? nextMaintenanceDate;
  final String? description;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  String get deviceTypeLabel => deviceType.label;

  String get pumpTypeLabel => pumpType.label;

  factory CustomerDeviceModel.fromMap(Map<String, dynamic> map) {
    return CustomerDeviceModel(
      id: map['id']?.toString(),
      companyId: map['company_id']?.toString(),
      customerId: map['customer_id']?.toString(),
      customerName: _normalizeNullableText(
        map['customer_name'] ??
            (map['customer'] is Map
                ? (map['customer'] as Map)['full_name']
                : null),
      ),
      customerPhone: _normalizeNullableText(
        map['customer_phone'] ??
            (map['customer'] is Map ? (map['customer'] as Map)['phone'] : null),
      ),
      customerAddress: _normalizeNullableText(
        map['customer_address'] ??
            (map['customer'] is Map
                ? (map['customer'] as Map)['address']
                : null),
      ),
      brand: _normalizeNullableText(map['brand']),
      model: _normalizeNullableText(map['model']),
      deviceType: DeviceType.fromValue(map['device_type']?.toString()),
      pumpType: PumpType.fromValue(map['pump_type']?.toString()),
      serialNumber: _normalizeNullableText(map['serial_number']),
      qrCode: _normalizeNullableText(map['qr_code']),
      membraneType: _normalizeNullableText(map['membrane_type']),
      installationDate: _parseDateTime(map['installation_date']),
      lastMaintenanceDate: _parseDateTime(map['last_maintenance_date']),
      nextMaintenanceDate: _parseDateTime(map['next_maintenance_date']),
      description: _normalizeNullableText(map['description']),
      isActive: map['is_active'] as bool? ?? true,
      createdAt: _parseDateTime(map['created_at']),
      updatedAt: _parseDateTime(map['updated_at']),
      deletedAt: _parseDateTime(map['deleted_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'company_id': companyId,
      'customer_id': customerId,
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'customer_address': customerAddress,
      'brand': brand,
      'model': model,
      'device_type': deviceType.value,
      'pump_type': pumpType.value,
      'serial_number': serialNumber,
      'qr_code': qrCode,
      'membrane_type': membraneType,
      'installation_date': installationDate == null
          ? null
          : _formatDateOnly(installationDate),
      'last_maintenance_date': lastMaintenanceDate == null
          ? null
          : _formatDateOnly(lastMaintenanceDate),
      'next_maintenance_date': nextMaintenanceDate == null
          ? null
          : _formatDateOnly(nextMaintenanceDate),
      'description': description,
      'is_active': isActive,
      'created_at': createdAt?.toUtc().toIso8601String(),
      'updated_at': updatedAt?.toUtc().toIso8601String(),
      'deleted_at': deletedAt?.toUtc().toIso8601String(),
    };
  }

  CustomerDeviceModel copyWith({
    Object? id = _unset,
    Object? companyId = _unset,
    Object? customerId = _unset,
    Object? customerName = _unset,
    Object? customerPhone = _unset,
    Object? customerAddress = _unset,
    Object? brand = _unset,
    Object? model = _unset,
    Object? deviceType = _unset,
    Object? pumpType = _unset,
    Object? serialNumber = _unset,
    Object? qrCode = _unset,
    Object? membraneType = _unset,
    Object? installationDate = _unset,
    Object? lastMaintenanceDate = _unset,
    Object? nextMaintenanceDate = _unset,
    Object? description = _unset,
    Object? isActive = _unset,
    Object? createdAt = _unset,
    Object? updatedAt = _unset,
    Object? deletedAt = _unset,
  }) {
    return CustomerDeviceModel(
      id: _valueOr<String?>(id, this.id),
      companyId: _valueOr<String?>(companyId, this.companyId),
      customerId: _valueOr<String?>(customerId, this.customerId),
      customerName: _valueOr<String?>(customerName, this.customerName),
      customerPhone: _valueOr<String?>(customerPhone, this.customerPhone),
      customerAddress: _valueOr<String?>(customerAddress, this.customerAddress),
      brand: _valueOr<String?>(brand, this.brand),
      model: _valueOr<String?>(model, this.model),
      deviceType: _valueOr<DeviceType>(deviceType, this.deviceType)!,
      pumpType: _valueOr<PumpType>(pumpType, this.pumpType)!,
      serialNumber: _valueOr<String?>(serialNumber, this.serialNumber),
      qrCode: _valueOr<String?>(qrCode, this.qrCode),
      membraneType: _valueOr<String?>(membraneType, this.membraneType),
      installationDate: _valueOr<DateTime?>(
        installationDate,
        this.installationDate,
      ),
      lastMaintenanceDate: _valueOr<DateTime?>(
        lastMaintenanceDate,
        this.lastMaintenanceDate,
      ),
      nextMaintenanceDate: _valueOr<DateTime?>(
        nextMaintenanceDate,
        this.nextMaintenanceDate,
      ),
      description: _valueOr<String?>(description, this.description),
      isActive: _valueOr<bool>(isActive, this.isActive)!,
      createdAt: _valueOr<DateTime?>(createdAt, this.createdAt),
      updatedAt: _valueOr<DateTime?>(updatedAt, this.updatedAt),
      deletedAt: _valueOr<DateTime?>(deletedAt, this.deletedAt),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is CustomerDeviceModel &&
        other.id == id &&
        other.companyId == companyId &&
        other.customerId == customerId &&
        other.customerName == customerName &&
        other.customerPhone == customerPhone &&
        other.customerAddress == customerAddress &&
        other.brand == brand &&
        other.model == model &&
        other.deviceType == deviceType &&
        other.pumpType == pumpType &&
        other.serialNumber == serialNumber &&
        other.qrCode == qrCode &&
        other.membraneType == membraneType &&
        other.installationDate == installationDate &&
        other.lastMaintenanceDate == lastMaintenanceDate &&
        other.nextMaintenanceDate == nextMaintenanceDate &&
        other.description == description &&
        other.isActive == isActive &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt &&
        other.deletedAt == deletedAt;
  }

  @override
  int get hashCode => Object.hash(
    id,
    companyId,
    customerId,
    customerName,
    customerPhone,
    customerAddress,
    brand,
    model,
    deviceType,
    pumpType,
    serialNumber,
    qrCode,
    membraneType,
    installationDate,
    lastMaintenanceDate,
    nextMaintenanceDate,
    description,
    isActive,
    createdAt,
    updatedAt,
  );
}

class DevicePage {
  const DevicePage({required this.items, required this.hasMore});

  final List<CustomerDeviceModel> items;
  final bool hasMore;
}
