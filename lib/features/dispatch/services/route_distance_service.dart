import 'dart:math' as math;

import '../models/route_job.dart';

class RouteDistanceService {
  const RouteDistanceService();

  double distanceKm(RoutePoint a, RoutePoint b) {
    const earth = 6371.0;
    double rad(double value) => value * math.pi / 180;
    final dLat = rad(b.latitude - a.latitude);
    final dLon = rad(b.longitude - a.longitude);
    final lat1 = rad(a.latitude);
    final lat2 = rad(b.latitude);
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) * math.cos(lat2) *
            math.sin(dLon / 2) * math.sin(dLon / 2);
    final safe = h.clamp(0.0, 1.0).toDouble();
    return earth * 2 * math.atan2(math.sqrt(safe), math.sqrt(1 - safe));
  }

  double routeKm(List<RouteJob> orderedJobs) {
    if (orderedJobs.length < 2) return 0;
    var total = 0.0;
    RoutePoint? previous;
    for (final job in orderedJobs) {
      final point = job.point;
      if (point == null) continue;
      if (previous != null) total += distanceKm(previous, point);
      previous = point;
    }
    return total;
  }

  int estimatedDriveMinutes(double straightLineKm) {
    // Şehir içi yol ağı kuş uçuşu mesafeden uzundur. 1.30 yol katsayısı ve
    // ortalama 32 km/s hız, API yanıtı yokken güvenli bir önizleme verir.
    final roadKm = straightLineKm * 1.30;
    return ((roadKm / 32.0) * 60).round();
  }
}
