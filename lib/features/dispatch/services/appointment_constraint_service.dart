import '../models/route_job.dart';
import 'route_distance_service.dart';

class AppointmentConstraintService {
  const AppointmentConstraintService(this.distanceService);

  final RouteDistanceService distanceService;

  static const int dayStartMinute = 8 * 60;
  static const int serviceDurationMinute = 45;

  /// Saatli bir işi atamak/rotaya eklemek için ceza puanı üretir.
  /// Gecikme, normal kilometreden çok daha pahalıdır; böylece randevu korunur
  /// fakat tek uzak randevu tüm coğrafi kümeyi ele geçirmez.
  double routePenalty(List<RouteJob> orderedJobs) {
    if (orderedJobs.isEmpty) return 0;
    var minute = dayStartMinute;
    var penalty = 0.0;
    RouteJob? previous;

    for (final job in orderedJobs) {
      if (previous?.point != null && job.point != null) {
        final km = distanceService.distanceKm(previous!.point!, job.point!);
        minute += distanceService.estimatedDriveMinutes(km);
      }

      final appointment = job.appointmentMinute;
      if (appointment != null) {
        if (minute > appointment) {
          final late = minute - appointment;
          penalty += late * 5.0; // gecikme en ağır ceza
        } else {
          // Çok erken varış da rotada boş bekleme yaratır, fakat gecikmeden hafif.
          final wait = appointment - minute;
          if (wait > 45) penalty += (wait - 45) * 0.15;
          minute = appointment;
        }
      }

      minute += serviceDurationMinute;
      previous = job;
    }
    return penalty;
  }
}
