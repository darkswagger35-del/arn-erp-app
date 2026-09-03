import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/app_role.dart';
import '../../../core/widgets/management_shell.dart';
import '../data/secretary_crm_provider.dart';

class SecretaryPerformanceScreen extends ConsumerWidget {
  const SecretaryPerformanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countsFuture = ref
        .read(secretaryCrmRepositoryProvider)
        .counts()
        .timeout(const Duration(seconds: 12));
    final perfFuture = ref
        .read(secretaryCrmRepositoryProvider)
        .todayServicePerformance()
        .timeout(const Duration(seconds: 12));
    return ManagementShell(
      role: AppRole.secretary,
      title: 'Raporlar • Performansım',
      subtitle: 'Kendi başvuru, takip ve gerçekleşen servis performansınızı görün.',
      child: FutureBuilder(
        future: Future.wait([countsFuture, perfFuture]),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(
              child: Text(
                'Performans verileri zamanında yüklenemedi.\nSol menüden tekrar açarak yeniden deneyin.',
                textAlign: TextAlign.center,
              ),
            );
          }
          final counts = snapshot.data![0] as dynamic;
          final perf = snapshot.data![1] as Map<String, num>;
          final cards = <(String, String, IconData, Color)>[
            ('Yeni Başvuru', '${counts.newCount}', Icons.person_add_alt_1_rounded, const Color(0xFF2979FF)),
            ('Takipte', '${counts.trackingCount}', Icons.schedule_rounded, const Color(0xFFF59E0B)),
            ('Bugün Alınan İş', '${counts.wonToday}', Icons.handshake_outlined, const Color(0xFF7C5CE7)),
            ('Bugün Tamamlanan', '${perf['completed'] ?? 0}', Icons.check_circle_outline_rounded, const Color(0xFF18A866)),
            ('Kapanan Takip', '${counts.closedCount}', Icons.cancel_outlined, const Color(0xFFE75454)),
            ('Gerçekleşen Ciro', '${(perf['revenue'] ?? 0).toStringAsFixed(0)} TL', Icons.trending_up_rounded, const Color(0xFF0AAEC0)),
          ];
          return GridView.count(
            padding: const EdgeInsets.all(24),
            crossAxisCount: MediaQuery.sizeOf(context).width < 850 ? 2 : 3,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: 2.1,
            children: cards.map((c) => Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE1E8F0))),
              child: Row(children: [CircleAvatar(radius: 25, backgroundColor: c.$4.withOpacity(.12), child: Icon(c.$3, color: c.$4)), const SizedBox(width: 13), Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Text(c.$1, style: const TextStyle(color: Color(0xFF6D7C91), fontWeight: FontWeight.w700)), Text(c.$2, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900, color: Color(0xFF0B1F35)))])]),
            )).toList(growable: false),
          );
        },
      ),
    );
  }
}
