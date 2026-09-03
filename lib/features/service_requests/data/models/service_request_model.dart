enum ServiceRequestType {
  newInstallation,
  filterChange,
  maintenance,
  fault,
  membrane,
  externalFilter,
  relocation,
  removal,
  other,
}

extension ServiceRequestTypeX on ServiceRequestType {
  String get value {
    switch (this) {
      case ServiceRequestType.newInstallation:
        return 'new_installation';
      case ServiceRequestType.filterChange:
        return 'filter_change';
      case ServiceRequestType.maintenance:
        return 'maintenance';
      case ServiceRequestType.fault:
        return 'fault';
      case ServiceRequestType.membrane:
        return 'membrane';
      case ServiceRequestType.externalFilter:
        return 'external_filter';
      case ServiceRequestType.relocation:
        return 'relocation';
      case ServiceRequestType.removal:
        return 'removal';
      case ServiceRequestType.other:
        return 'other';
    }
  }

  String get label {
    switch (this) {
      case ServiceRequestType.newInstallation:
        return 'Yeni Kurulum';
      case ServiceRequestType.filterChange:
        return 'Filtre Değişimi';
      case ServiceRequestType.maintenance:
        return 'Bakım';
      case ServiceRequestType.fault:
        return 'Arıza';
      case ServiceRequestType.membrane:
        return 'Membran Değişimi';
      case ServiceRequestType.externalFilter:
        return 'Dış Filtre';
      case ServiceRequestType.relocation:
        return 'Taşıma';
      case ServiceRequestType.removal:
        return 'Söküm';
      case ServiceRequestType.other:
        return 'Servis';
    }
  }

  static ServiceRequestType fromValue(String? value) {
    switch (value) {
      case 'new_installation':
        return ServiceRequestType.newInstallation;
      case 'filter_change':
        return ServiceRequestType.filterChange;
      case 'maintenance':
        return ServiceRequestType.maintenance;
      case 'fault':
        return ServiceRequestType.fault;
      case 'membrane':
        return ServiceRequestType.membrane;
      case 'external_filter':
        return ServiceRequestType.externalFilter;
      case 'relocation':
        return ServiceRequestType.relocation;
      case 'removal':
        return ServiceRequestType.removal;
      default:
        return ServiceRequestType.other;
    }
  }
}

enum ServiceRequestStatus {
  pending,
  approved,
  deferred,
  assigned,
  inProgress,
  completed,
  cancelled,
  couldNotComplete,
}

extension ServiceRequestStatusX on ServiceRequestStatus {
  String get value {
    switch (this) {
      case ServiceRequestStatus.pending:
        return 'pending';
      case ServiceRequestStatus.approved:
        return 'approved';
      case ServiceRequestStatus.deferred:
        return 'deferred';
      case ServiceRequestStatus.assigned:
        return 'assigned';
      case ServiceRequestStatus.inProgress:
        return 'in_progress';
      case ServiceRequestStatus.completed:
        return 'completed';
      case ServiceRequestStatus.cancelled:
        return 'cancelled';
      case ServiceRequestStatus.couldNotComplete:
        return 'could_not_complete';
    }
  }

  String get label {
    switch (this) {
      case ServiceRequestStatus.pending:
        return 'Onay Bekliyor';
      case ServiceRequestStatus.approved:
        return 'Atama Bekliyor';
      case ServiceRequestStatus.deferred:
        return 'Sekretere Gönderildi';
      case ServiceRequestStatus.assigned:
        return 'Tekniker Atandı';
      case ServiceRequestStatus.inProgress:
        return 'Devam Ediyor';
      case ServiceRequestStatus.completed:
        return 'Tamamlandı';
      case ServiceRequestStatus.cancelled:
        return 'İptal Edildi';
      case ServiceRequestStatus.couldNotComplete:
        return 'Tamamlanamadı';
    }
  }

  static ServiceRequestStatus fromValue(String? value) {
    switch (value) {
      case 'approved':
        return ServiceRequestStatus.approved;
      case 'deferred':
        return ServiceRequestStatus.deferred;
      case 'assigned':
        return ServiceRequestStatus.assigned;
      case 'in_progress':
        return ServiceRequestStatus.inProgress;
      case 'completed':
        return ServiceRequestStatus.completed;
      case 'cancelled':
        return ServiceRequestStatus.cancelled;
      case 'could_not_complete':
        return ServiceRequestStatus.couldNotComplete;
      default:
        return ServiceRequestStatus.pending;
    }
  }
}


class ServiceRequestItem {
  const ServiceRequestItem({
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
  });

  final String productName;
  final double quantity;
  final double unitPrice;
  final double lineTotal;

  factory ServiceRequestItem.fromMap(Map<String, dynamic> map) {
    return ServiceRequestItem(
      productName: map['product_name']?.toString() ?? '',
      quantity: (map['quantity'] as num?)?.toDouble() ?? 0,
      unitPrice: (map['unit_price'] as num?)?.toDouble() ?? 0,
      lineTotal: (map['line_total'] as num?)?.toDouble() ?? 0,
    );
  }
}

class ServiceRequestModel {
  const ServiceRequestModel({
    this.id,
    required this.customerId,
    required this.serviceType,
    required this.description,
    required this.price,
    required this.status,
    this.plannedDate,
    this.assignedTechnicianId,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
    this.customerName = '',
    this.customerPhone = '',
    this.customerAddress = '',
    this.customerCity = '',
    this.customerDistrict = '',
    this.customerNeighborhood = '',
    this.assignedTechnicianName = '',
    this.plannedProductId,
    this.plannedProductName = '',
    this.plannedQuantity = 0,
    this.plannedUnitPrice = 0,
    this.plannedItems = const <Map<String, dynamic>>[],
    this.completionNote = '',
    this.items = const [],
    this.technicianNameSnapshot = '',
    this.routeOrder,
    this.routePlanDate,
    this.cancellationReason = '',
    this.technicianUnavailableReason = '',
    this.technicianUnavailableNote = '',
    this.cancelledAt,
    this.cancelledByName = '',
    this.reworkRequestedAt,
    this.reworkSecretaryId,
    this.reworkReason = '',
    this.reworkCompletedAt,
    this.replacementServiceRequestId,
    this.serviceFormValues = const <String, dynamic>{},
  });

  final String? id;
  final String customerId;
  final ServiceRequestType serviceType;
  final String description;
  final double price;
  final ServiceRequestStatus status;
  final DateTime? plannedDate;
  final String? assignedTechnicianId;
  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String customerName;
  final String customerPhone;
  final String customerAddress;
  final String customerCity;
  final String customerDistrict;
  final String customerNeighborhood;
  final String assignedTechnicianName;
  final String? plannedProductId;
  final String plannedProductName;
  final double plannedQuantity;
  final double plannedUnitPrice;
  final List<Map<String, dynamic>> plannedItems;
  final String completionNote;
  final List<ServiceRequestItem> items;
  final String technicianNameSnapshot;
  final int? routeOrder;
  final DateTime? routePlanDate;
  final String cancellationReason;
  final String technicianUnavailableReason;
  final String technicianUnavailableNote;
  final DateTime? cancelledAt;
  final String cancelledByName;
  final DateTime? reworkRequestedAt;
  final String? reworkSecretaryId;
  final String reworkReason;
  final DateTime? reworkCompletedAt;
  final String? replacementServiceRequestId;
  final Map<String, dynamic> serviceFormValues;

  bool get isSecretaryRework => reworkRequestedAt != null && reworkCompletedAt == null;

  /// Eski servis kaydı sekretere yeniden planlama için aktarılmış ve yerine
  /// yeni bir servis/taslak oluşturulmuşsa bu kayıt gerçek bir
  /// "Tamamlanamadı" değildir; geçmişteki sekretere aktarım kaydıdır.
  bool get wasSentToSecretary =>
      reworkRequestedAt != null &&
      replacementServiceRequestId?.trim().isNotEmpty == true;

  bool get isSecretaryFlow => isSecretaryRework || wasSentToSecretary;

  ServiceRequestModel copyWith({
    String? id,
    String? customerId,
    ServiceRequestType? serviceType,
    String? description,
    double? price,
    ServiceRequestStatus? status,
    DateTime? plannedDate,
    String? assignedTechnicianId,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? customerName,
    String? customerPhone,
    String? customerAddress,
    String? customerCity,
    String? customerDistrict,
    String? customerNeighborhood,
    String? assignedTechnicianName,
    String? plannedProductId,
    String? plannedProductName,
    double? plannedQuantity,
    double? plannedUnitPrice,
    List<Map<String, dynamic>>? plannedItems,
    String? completionNote,
    List<ServiceRequestItem>? items,
    String? technicianNameSnapshot,
    int? routeOrder,
    DateTime? routePlanDate,
    String? cancellationReason,
    String? technicianUnavailableReason,
    String? technicianUnavailableNote,
    DateTime? cancelledAt,
    String? cancelledByName,
    DateTime? reworkRequestedAt,
    String? reworkSecretaryId,
    String? reworkReason,
    DateTime? reworkCompletedAt,
    String? replacementServiceRequestId,
    Map<String, dynamic>? serviceFormValues,
  }) {
    return ServiceRequestModel(
      id: id ?? this.id,
      customerId: customerId ?? this.customerId,
      serviceType: serviceType ?? this.serviceType,
      description: description ?? this.description,
      price: price ?? this.price,
      status: status ?? this.status,
      plannedDate: plannedDate ?? this.plannedDate,
      assignedTechnicianId: assignedTechnicianId ?? this.assignedTechnicianId,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      customerAddress: customerAddress ?? this.customerAddress,
      customerCity: customerCity ?? this.customerCity,
      customerDistrict: customerDistrict ?? this.customerDistrict,
      customerNeighborhood: customerNeighborhood ?? this.customerNeighborhood,
      assignedTechnicianName:
          assignedTechnicianName ?? this.assignedTechnicianName,
      plannedProductId: plannedProductId ?? this.plannedProductId,
      plannedProductName: plannedProductName ?? this.plannedProductName,
      plannedQuantity: plannedQuantity ?? this.plannedQuantity,
      plannedUnitPrice: plannedUnitPrice ?? this.plannedUnitPrice,
      plannedItems: plannedItems ?? this.plannedItems,
      completionNote: completionNote ?? this.completionNote,
      items: items ?? this.items,
      technicianNameSnapshot:
          technicianNameSnapshot ?? this.technicianNameSnapshot,
      routeOrder: routeOrder ?? this.routeOrder,
      routePlanDate: routePlanDate ?? this.routePlanDate,
      cancellationReason: cancellationReason ?? this.cancellationReason,
      technicianUnavailableReason:
          technicianUnavailableReason ?? this.technicianUnavailableReason,
      technicianUnavailableNote:
          technicianUnavailableNote ?? this.technicianUnavailableNote,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      cancelledByName: cancelledByName ?? this.cancelledByName,
      reworkRequestedAt: reworkRequestedAt ?? this.reworkRequestedAt,
      reworkSecretaryId: reworkSecretaryId ?? this.reworkSecretaryId,
      reworkReason: reworkReason ?? this.reworkReason,
      reworkCompletedAt: reworkCompletedAt ?? this.reworkCompletedAt,
      replacementServiceRequestId: replacementServiceRequestId ?? this.replacementServiceRequestId,
      serviceFormValues: serviceFormValues ?? this.serviceFormValues,
    );
  }

  factory ServiceRequestModel.fromMap(Map<String, dynamic> map) {
    return ServiceRequestModel(
      id: map['id'] as String?,
      customerId: map['customer_id'] as String? ?? '',
      serviceType: ServiceRequestTypeX.fromValue(
        map['service_type'] as String?,
      ),
      description: map['description'] as String? ?? '',
      price: (map['price'] as num?)?.toDouble() ?? 0,
      status: ServiceRequestStatusX.fromValue(map['status'] as String?),
      plannedDate: map['planned_date'] == null
          ? null
          : DateTime.tryParse(map['planned_date'].toString()),
      assignedTechnicianId: map['assigned_technician_id'] as String?,
      createdBy: map['created_by'] as String?,
      createdAt: map['created_at'] == null
          ? null
          : DateTime.tryParse(map['created_at'].toString()),
      updatedAt: map['updated_at'] == null
          ? null
          : DateTime.tryParse(map['updated_at'].toString()),
      plannedProductId: map['planned_product_id'] as String?,
      plannedProductName: map['planned_product_name']?.toString() ?? '',
      plannedQuantity: (map['planned_quantity'] as num?)?.toDouble() ?? 0,
      plannedUnitPrice: (map['planned_unit_price'] as num?)?.toDouble() ?? 0,
      plannedItems: map['planned_items'] is List
          ? (map['planned_items'] as List)
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(growable: false)
          : const <Map<String, dynamic>>[],
      completionNote: map['completion_note']?.toString() ?? '',
      technicianNameSnapshot:
          map['assigned_technician_name_snapshot']?.toString() ?? '',
      routeOrder: (map['route_order'] as num?)?.toInt(),
      routePlanDate: map['route_plan_date'] == null
          ? null
          : DateTime.tryParse(map['route_plan_date'].toString()),
      cancellationReason: map['cancellation_reason']?.toString() ?? '',
      technicianUnavailableReason:
          map['technician_unavailable_reason']?.toString() ?? '',
      technicianUnavailableNote:
          map['technician_unavailable_note']?.toString() ?? '',
      cancelledAt: map['cancelled_at'] == null
          ? null
          : DateTime.tryParse(map['cancelled_at'].toString()),
      cancelledByName: map['cancelled_by_name']?.toString() ?? '',
      reworkRequestedAt: map['rework_requested_at'] == null
          ? null
          : DateTime.tryParse(map['rework_requested_at'].toString()),
      reworkSecretaryId: map['rework_secretary_id']?.toString(),
      reworkReason: map['rework_reason']?.toString() ?? '',
      reworkCompletedAt: map['rework_completed_at'] == null
          ? null
          : DateTime.tryParse(map['rework_completed_at'].toString()),
      replacementServiceRequestId: map['replacement_service_request_id']?.toString(),
      serviceFormValues: map['service_form_values'] is Map
          ? Map<String, dynamic>.from(map['service_form_values'] as Map)
          : const <String, dynamic>{},
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'customer_id': customerId,
      'service_type': serviceType.value,
      'description': description.trim(),
      'price': price,
      'status': status.value,
      'planned_date': plannedDate?.toIso8601String(),
      'assigned_technician_id': assignedTechnicianId,
      'created_by': createdBy,
      'planned_product_id': plannedProductId,
      'planned_product_name': plannedProductName.trim(),
      'planned_quantity': plannedQuantity,
      'planned_unit_price': plannedUnitPrice,
      'planned_items': plannedItems,
      'completion_note': completionNote.trim(),
      'route_order': routeOrder,
      'route_plan_date': routePlanDate == null
          ? null
          : '${routePlanDate!.year.toString().padLeft(4, '0')}-${routePlanDate!.month.toString().padLeft(2, '0')}-${routePlanDate!.day.toString().padLeft(2, '0')}',
    };
  }
}
