class AuditLog {
  const AuditLog({
    required this.id,
    required this.companyId,
    this.userId,
    required this.action,
    required this.entityType,
    this.entityId,
    this.oldValues,
    this.newValues,
    this.metadata,
    this.createdAt,
  });

  final int id;
  final String companyId;
  final String? userId;
  final String action;
  final String entityType;
  final String? entityId;
  final Map<String, dynamic>? oldValues;
  final Map<String, dynamic>? newValues;
  final Map<String, dynamic>? metadata;
  final DateTime? createdAt;

  factory AuditLog.fromJson(Map<String, dynamic> json) {
    return AuditLog(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      companyId: json['company_id']?.toString() ?? '',
      userId: json['user_id']?.toString(),
      action: json['action']?.toString() ?? '',
      entityType: json['entity_type']?.toString() ?? '',
      entityId: json['entity_id']?.toString(),
      oldValues: _parseJsonMap(json['old_values']),
      newValues: _parseJsonMap(json['new_values']),
      metadata: _parseJsonMap(json['metadata']),
      createdAt: _parseDateTime(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'company_id': companyId,
      'user_id': userId,
      'action': action,
      'entity_type': entityType,
      'entity_id': entityId,
      'old_values': oldValues,
      'new_values': newValues,
      'metadata': metadata,
      'created_at': _formatDateTime(createdAt),
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is AuditLog &&
        other.id == id &&
        other.companyId == companyId &&
        other.userId == userId &&
        other.action == action &&
        other.entityType == entityType &&
        other.entityId == entityId &&
        other.oldValues == oldValues &&
        other.newValues == newValues &&
        other.metadata == metadata &&
        other.createdAt == createdAt;
  }

  @override
  int get hashCode => Object.hash(
    id,
    companyId,
    userId,
    action,
    entityType,
    entityId,
    oldValues,
    newValues,
    metadata,
    createdAt,
  );
}

Map<String, dynamic>? _parseJsonMap(Object? value) {
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return null;
}

DateTime? _parseDateTime(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is DateTime) {
    return value;
  }
  if (value is String) {
    return DateTime.tryParse(value);
  }
  return null;
}

String? _formatDateTime(DateTime? value) {
  return value?.toUtc().toIso8601String();
}
