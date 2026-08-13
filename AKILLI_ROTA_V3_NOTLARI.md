# MOTUS Akıllı Rota V3

Bu sürümde Akıllı Plan, iş sayısını eşitleme mantığından ayrıldı.

- Ana hedef: toplam sürüş mesafesini ve zikzak rotayı azaltmak.
- Müşteriler koordinatlarına göre doğal kümelere ayrılır (k-medoids / farthest-first başlangıç).
- İş sayısı yalnızca hafif denge cezasıdır; 4-4-5 zorunlu değildir.
- Tek başına uzak bir iş, yeterli iş havuzunda bir teknikeri tek başına kapatmaz.
- Saatli işler rota puanında ağır gecikme cezasına sahiptir; randevu korunur fakat tek randevu bütün kümeyi sürüklemez.
- Her teknikerin ziyaret sırası nearest-neighbor + 2-opt ile ayrıca optimize edilir.
- Önizlemede tekniker başına tahmini yol kilometresi ve tahmini sürüş süresi gösterilir.
- Yönetici önizlemede müşteriyi başka teknikere alırsa etkilenen tekniker rotaları yeniden sıralanır.
- İlçe isimleri planlama kuralı değildir; yalnız koordinatı olmayan kayıtlar için fallback olarak kullanılır.

Yeni modüller:
- lib/features/dispatch/models/route_job.dart
- lib/features/dispatch/models/technician_route_plan.dart
- lib/features/dispatch/services/route_distance_service.dart
- lib/features/dispatch/services/appointment_constraint_service.dart
- lib/features/dispatch/services/smart_route_planner.dart
