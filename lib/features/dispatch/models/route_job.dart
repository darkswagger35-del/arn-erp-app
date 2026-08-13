class RoutePoint {
  const RoutePoint({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;
}

class RouteJob {
  const RouteJob({
    required this.id,
    required this.customerName,
    required this.city,
    required this.district,
    required this.point,
    this.plannedDate,
  });

  final String id;
  final String customerName;
  final String city;
  final String district;
  final RoutePoint? point;
  final DateTime? plannedDate;

  bool get hasFixedTime {
    final value = plannedDate?.toLocal();
    if (value == null) return false;
    return value.hour != 0 || value.minute != 0;
  }

  int? get appointmentMinute {
    final value = plannedDate?.toLocal();
    if (value == null || !hasFixedTime) return null;
    return value.hour * 60 + value.minute;
  }
}
