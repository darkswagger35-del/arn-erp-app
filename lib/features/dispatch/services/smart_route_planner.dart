import 'dart:math' as math;

import '../models/route_job.dart';
import '../models/technician_route_plan.dart';
import 'appointment_constraint_service.dart';
import 'route_distance_service.dart';

class SmartRoutePlanner {
  SmartRoutePlanner({
    RouteDistanceService? distanceService,
    AppointmentConstraintService? appointmentService,
  })  : distanceService = distanceService ?? const RouteDistanceService(),
        appointmentService = appointmentService ??
            AppointmentConstraintService(
              distanceService ?? const RouteDistanceService(),
            );

  final RouteDistanceService distanceService;
  final AppointmentConstraintService appointmentService;

  List<TechnicianRoutePlan> buildPlan({
    required List<RouteJob> jobs,
    required List<String> technicianIds,
  }) {
    if (jobs.isEmpty || technicianIds.isEmpty) return const [];
    final count = math.min(jobs.length, technicianIds.length);
    final techs = technicianIds.take(count).toList(growable: false);

    final groups = _naturalClusters(jobs, count);
    _repairSingletonClusters(groups, jobs.length);
    _improveByRelocation(groups);

    final result = <TechnicianRoutePlan>[];
    for (var i = 0; i < groups.length; i++) {
      final ordered = orderRoute(groups[i]);
      final km = distanceService.routeKm(ordered);
      final appointmentPenalty = appointmentService.routePenalty(ordered);
      const loadPenalty = 0.0;
      result.add(
        TechnicianRoutePlan(
          technicianId: techs[i],
          jobIds: ordered.map((e) => e.id).toList(growable: false),
          estimatedKm: km * 1.30,
          estimatedDriveMinutes: distanceService.estimatedDriveMinutes(km),
          score: km + appointmentPenalty + loadPenalty,
        ),
      );
    }
    return result;
  }

  List<RouteJob> orderRoute(List<RouteJob> jobs) {
    if (jobs.length < 2) return List<RouteJob>.from(jobs);
    final located = jobs.where((j) => j.point != null).toList();
    final missing = jobs.where((j) => j.point == null).toList();
    if (located.isEmpty) {
      return List<RouteJob>.from(jobs)
        ..sort((a, b) => _timeSort(a, b));
    }

    // Birkaç farklı başlangıç adayını deneyip randevu + mesafe puanı en düşük
    // olan sırayı seçiyoruz. Bu, "ilk noktayı yanlış seçip zikzak" sorununu azaltır.
    List<RouteJob>? best;
    var bestScore = double.infinity;
    final starts = _startCandidates(located);
    for (final start in starts) {
      final candidate = _nearestNeighbor(located, start);
      final improved = _twoOpt(candidate);
      final score = _sequenceScore(improved);
      if (score < bestScore) {
        bestScore = score;
        best = improved;
      }
    }
    final ordered = best ?? located;
    missing.sort(_timeSort);
    return <RouteJob>[...ordered, ...missing];
  }

  List<List<RouteJob>> _naturalClusters(List<RouteJob> jobs, int count) {
    final located = jobs.where((j) => j.point != null).toList(growable: false);
    final missing = jobs.where((j) => j.point == null).toList(growable: false);
    if (located.isEmpty) return _fallbackGroups(jobs, count);
    if (count == 1) return [List<RouteJob>.from(jobs)];

    // ROOT/rota öncelikli doğal kümelendirme.
    // İş sayısını eşitlemiyoruz. Farthest-first ile birbirinden uzak rota
    // merkezleri seçilir, ardından k-medoids ile her iş en yakın gerçek
    // coğrafi kümeye yerleşir. Böylece Buca/Konak içindeki bir iş sırf sayı
    // dengesi için Bornova/Bayraklı rotasına taşınmaz.
    final k = math.min(count, located.length);

    // İzmir'de saha operasyonu doğrusal/koridor bazlı çalışıyor. Sadece
    // koordinat medoidleri merkez ilçelerde (Konak-Karşıyaka-Bayraklı gibi)
    // birbirine çok yakın olduğundan kuzey ve güney rotalarını çaprazlayabiliyor.
    // Bilinen İzmir ulaşım koridorlarını birincil bölücü olarak kullanıyoruz;
    // koridor içindeki sıra ve mesafe hesabı yine gerçek koordinatlarla yapılır.
    final corridorGroups = _corridorClusters(located, k);
    if (corridorGroups != null) {
      for (final job in missing) {
        _addMissingToBestCorridor(corridorGroups, job);
      }
      return corridorGroups;
    }

    final medoids = <RouteJob>[];

    // İlk merkez: tüm işlere toplam mesafesi en düşük olan gerçek medoid.
    medoids.add(_medoid(located));
    while (medoids.length < k) {
      RouteJob? next;
      var bestSeparation = -1.0;
      for (final candidate in located) {
        if (medoids.any((m) => m.id == candidate.id)) continue;
        var nearest = double.infinity;
        for (final m in medoids) {
          nearest = math.min(
            nearest,
            distanceService.distanceKm(candidate.point!, m.point!),
          );
        }
        if (nearest > bestSeparation) {
          bestSeparation = nearest;
          next = candidate;
        }
      }
      if (next == null) break;
      medoids.add(next);
    }

    var groups = List.generate(medoids.length, (_) => <RouteJob>[]);
    for (var iteration = 0; iteration < 20; iteration++) {
      groups = List.generate(medoids.length, (_) => <RouteJob>[]);
      for (final job in located) {
        var bestIndex = 0;
        var bestKm = double.infinity;
        for (var i = 0; i < medoids.length; i++) {
          final km = distanceService.distanceKm(job.point!, medoids[i].point!);
          if (km < bestKm) {
            bestKm = km;
            bestIndex = i;
          }
        }
        groups[bestIndex].add(job);
      }

      // Her teknikeri kullanabilmek için boş küme oluşursa, en geniş kümeye
      // en uzak noktayı yeni merkez yap. Burada da iş sayısı hedeflenmez.
      for (var empty = 0; empty < groups.length; empty++) {
        if (groups[empty].isNotEmpty) continue;
        final donor = _widestGroupIndex(groups);
        if (donor < 0 || groups[donor].length < 2) continue;
        final donorMedoid = _medoid(groups[donor]);
        RouteJob farthest = groups[donor].first;
        var farthestKm = -1.0;
        for (final candidate in groups[donor]) {
          final km = distanceService.distanceKm(candidate.point!, donorMedoid.point!);
          if (km > farthestKm) {
            farthestKm = km;
            farthest = candidate;
          }
        }
        medoids[empty] = farthest;
      }

      var changed = false;
      for (var i = 0; i < groups.length; i++) {
        if (groups[i].isEmpty) continue;
        final nextMedoid = _medoid(groups[i]);
        if (nextMedoid.id != medoids[i].id) {
          medoids[i] = nextMedoid;
          changed = true;
        }
      }
      if (!changed) break;
    }

    // Koordinatı bulunamayan çok eski kayıtlar yalnız fallback olarak eklenir.
    // Önce aynı ilçe içeren kümeyi, yoksa toplam rota maliyetini en az artıran
    // kümeyi seçeriz.
    for (final job in missing) {
      var target = -1;
      final district = job.district.trim().toLowerCase();
      for (var i = 0; i < groups.length; i++) {
        if (groups[i].any((x) => x.district.trim().toLowerCase() == district)) {
          target = i;
          break;
        }
      }
      if (target < 0) {
        var bestDelta = double.infinity;
        for (var i = 0; i < groups.length; i++) {
          final delta = _groupScore([...groups[i], job]) - _groupScore(groups[i]);
          if (delta < bestDelta) {
            bestDelta = delta;
            target = i;
          }
        }
      }
      groups[target < 0 ? 0 : target].add(job);
    }
    return groups;
  }

  List<List<RouteJob>>? _corridorClusters(List<RouteJob> jobs, int k) {
    if (k != 3 || jobs.length < 6) return null;
    final recognized = jobs.where((j) => _corridorKey(j) != null).toList();
    if (recognized.length < (jobs.length * 0.70).ceil()) return null;

    final grouped = <String, List<RouteJob>>{};
    for (final job in recognized) {
      grouped.putIfAbsent(_corridorKey(job)!, () => <RouteJob>[]).add(job);
    }
    if (grouped.length != 3) return null;

    // Tanınmayan İzmir ilçelerini / yakın çevreyi en az rota artışı yaratan
    // koridora ekle. İş adedi hiçbir şekilde karar ölçütü değildir.
    final result = grouped.values.map(List<RouteJob>.from).toList(growable: false);
    for (final job in jobs.where((j) => _corridorKey(j) == null)) {
      var best = 0;
      var bestDelta = double.infinity;
      for (var i = 0; i < result.length; i++) {
        final delta = _groupScore([...result[i], job]) - _groupScore(result[i]);
        if (delta < bestDelta) {
          bestDelta = delta;
          best = i;
        }
      }
      result[best].add(job);
    }
    return result;
  }

  void _addMissingToBestCorridor(List<List<RouteJob>> groups, RouteJob job) {
    final corridor = _corridorKey(job);
    if (corridor != null) {
      for (final group in groups) {
        if (group.any((x) => _corridorKey(x) == corridor)) {
          group.add(job);
          return;
        }
      }
    }
    var best = 0;
    var bestDelta = double.infinity;
    for (var i = 0; i < groups.length; i++) {
      final delta = _groupScore([...groups[i], job]) - _groupScore(groups[i]);
      if (delta < bestDelta) {
        bestDelta = delta;
        best = i;
      }
    }
    groups[best].add(job);
  }

  String? _corridorKey(RouteJob job) {
    final city = _normalize(job.city);
    if (city != 'izmir') return null;
    final district = _normalize(job.district);

    // Batı hattı: sahil boyunca tek ileri/geri rota.
    if ({'urla', 'guzelbahce', 'narlidere', 'balcova'}.contains(district)) {
      return 'izmir_west';
    }
    // Kuzey / kuzeydoğu hattı.
    if ({'karsiyaka', 'bayrakli', 'bornova', 'cigli'}.contains(district)) {
      return 'izmir_north';
    }
    // Merkez / güney hattı.
    if ({'konak', 'karabaglar', 'buca', 'gaziemir'}.contains(district)) {
      return 'izmir_central_south';
    }
    return null;
  }

  String _normalize(String value) {
    return value
        .trim()
        .replaceAll('İ', 'I')
        .replaceAll('Ş', 'S')
        .replaceAll('Ğ', 'G')
        .replaceAll('Ü', 'U')
        .replaceAll('Ö', 'O')
        .replaceAll('Ç', 'C')
        .toLowerCase()
        .replaceAll('ı', 'i')
        .replaceAll('ş', 's')
        .replaceAll('ğ', 'g')
        .replaceAll('ü', 'u')
        .replaceAll('ö', 'o')
        .replaceAll('ç', 'c')
        .replaceAll('\u0307', '');
  }

  (List<RouteJob>, List<RouteJob>)? _splitByLargestMstEdge(List<RouteJob> group) {
    final located = group.where((j) => j.point != null).toList();
    if (located.length < 2) return null;
    final n = located.length;
    final parent = List<int>.generate(n, (i) => i);
    int find(int x) {
      while (parent[x] != x) {
        parent[x] = parent[parent[x]];
        x = parent[x];
      }
      return x;
    }
    void unite(int a, int b) {
      final ra = find(a), rb = find(b);
      if (ra != rb) parent[rb] = ra;
    }
    final edges = <_RouteEdge>[];
    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        edges.add(_RouteEdge(
          a: i,
          b: j,
          km: distanceService.distanceKm(located[i].point!, located[j].point!),
        ));
      }
    }
    edges.sort((a, b) => a.km.compareTo(b.km));
    final mst = <_RouteEdge>[];
    for (final e in edges) {
      if (find(e.a) == find(e.b)) continue;
      unite(e.a, e.b);
      mst.add(e);
      if (mst.length == n - 1) break;
    }
    if (mst.isEmpty) return null;
    final cut = mst.reduce((a, b) => a.km >= b.km ? a : b);

    final cp = List<int>.generate(n, (i) => i);
    int cf(int x) {
      while (cp[x] != x) {
        cp[x] = cp[cp[x]];
        x = cp[x];
      }
      return x;
    }
    void cu(int a, int b) {
      final ra = cf(a), rb = cf(b);
      if (ra != rb) cp[rb] = ra;
    }
    for (final e in mst) {
      if (e.key != cut.key) cu(e.a, e.b);
    }
    final firstRoot = cf(0);
    final a = <RouteJob>[];
    final b = <RouteJob>[];
    for (var i = 0; i < n; i++) {
      (cf(i) == firstRoot ? a : b).add(located[i]);
    }
    final noPoint = group.where((j) => j.point == null).toList();
    for (final job in noPoint) {
      (a.length <= b.length ? a : b).add(job);
    }
    if (a.isEmpty || b.isEmpty) return null;
    return (a, b);
  }

  void _repairSingletonClusters(List<List<RouteJob>> groups, int totalJobs) {
    if (groups.length < 3 || totalJobs < 8) return;
    for (var singletonIndex = 0; singletonIndex < groups.length; singletonIndex++) {
      if (groups[singletonIndex].length != 1) continue;
      final lone = groups[singletonIndex].single;
      if (lone.point == null) continue;

      var nearestIndex = -1;
      var nearestKm = double.infinity;
      for (var i = 0; i < groups.length; i++) {
        if (i == singletonIndex || groups[i].isEmpty) continue;
        final medoid = _medoid(groups[i]);
        if (medoid.point == null) continue;
        final km = distanceService.distanceKm(lone.point!, medoid.point!);
        if (km < nearestKm) {
          nearestKm = km;
          nearestIndex = i;
        }
      }
      if (nearestIndex < 0) continue;

      // Tek uzak iş bir teknikeri tek başına kapatmasın. En yakın doğal rotaya
      // eklenir; boşalan tekniker için en geniş coğrafi havuz ikiye ayrılır.
      groups[nearestIndex].add(lone);
      groups[singletonIndex].clear();

      final donorIndex = _largestGroupIndex(groups);
      if (donorIndex < 0 || groups[donorIndex].length < 4) continue;
      final donor = List<RouteJob>.from(groups[donorIndex]);
      final located = donor.where((e) => e.point != null).toList();
      if (located.length < 4) continue;

      RouteJob seedA = located.first;
      RouteJob seedB = located.last;
      var farthest = -1.0;
      for (var a = 0; a < located.length; a++) {
        for (var b = a + 1; b < located.length; b++) {
          final km = distanceService.distanceKm(located[a].point!, located[b].point!);
          if (km > farthest) {
            farthest = km;
            seedA = located[a];
            seedB = located[b];
          }
        }
      }

      final first = <RouteJob>[];
      final second = <RouteJob>[];
      for (final job in donor) {
        if (job.point == null) {
          (first.length <= second.length ? first : second).add(job);
          continue;
        }
        final aKm = distanceService.distanceKm(job.point!, seedA.point!);
        final bKm = distanceService.distanceKm(job.point!, seedB.point!);
        (aKm <= bKm ? first : second).add(job);
      }
      if (first.isNotEmpty && second.isNotEmpty) {
        groups[donorIndex]
          ..clear()
          ..addAll(first);
        groups[singletonIndex].addAll(second);
      }
    }
  }

  void _improveByRelocation(List<List<RouteJob>> groups) {
    if (groups.length < 2) return;

    // ROOT her seyin onunde. Is sayisi icin hicbir ceza yok.
    // 1) Tekli tasima: toplam rota km + randevu cezasini dusuren her hamle kabul.
    // 2) Swap: iki rota arasinda birer isi degistirerek yerel minimumdan cik.
    for (var pass = 0; pass < 12; pass++) {
      var improved = false;

      for (var from = 0; from < groups.length; from++) {
        if (groups[from].length <= 1) continue; // tekniker tamamen bosalmasin
        final snapshot = List<RouteJob>.from(groups[from]);
        for (final job in snapshot) {
          var bestTo = -1;
          var bestGain = 0.0;
          for (var to = 0; to < groups.length; to++) {
            if (to == from) continue;
            final jobCorridor = _corridorKey(job);
            final targetCorridors = groups[to]
                .map(_corridorKey)
                .whereType<String>()
                .toSet();
            if (jobCorridor != null &&
                targetCorridors.isNotEmpty &&
                !targetCorridors.contains(jobCorridor)) {
              continue;
            }
            final oldScore = _groupScore(groups[from]) + _groupScore(groups[to]);
            final fromCandidate = List<RouteJob>.from(groups[from])..remove(job);
            final toCandidate = List<RouteJob>.from(groups[to])..add(job);
            final newScore = _groupScore(fromCandidate) + _groupScore(toCandidate);
            final gain = oldScore - newScore;
            if (gain > bestGain + 0.05) {
              bestGain = gain;
              bestTo = to;
            }
          }
          if (bestTo >= 0) {
            groups[from].remove(job);
            groups[bestTo].add(job);
            improved = true;
          }
        }
      }

      // Pairwise swap: ozellikle ayni koridordan kopmus tek isi geri toplar.
      var swapDone = false;
      for (var a = 0; a < groups.length && !swapDone; a++) {
        for (var b = a + 1; b < groups.length && !swapDone; b++) {
          final oldScore = _groupScore(groups[a]) + _groupScore(groups[b]);
          for (final ja in List<RouteJob>.from(groups[a])) {
            for (final jb in List<RouteJob>.from(groups[b])) {
              final caKey = _corridorKey(ja);
              final cbKey = _corridorKey(jb);
              if (caKey != null && cbKey != null && caKey != cbKey) continue;
              final ca = List<RouteJob>.from(groups[a])
                ..remove(ja)
                ..add(jb);
              final cb = List<RouteJob>.from(groups[b])
                ..remove(jb)
                ..add(ja);
              final newScore = _groupScore(ca) + _groupScore(cb);
              if (newScore + 0.05 < oldScore) {
                groups[a]
                  ..remove(ja)
                  ..add(jb);
                groups[b]
                  ..remove(jb)
                  ..add(ja);
                improved = true;
                swapDone = true;
                break;
              }
            }
            if (swapDone) break;
          }
        }
      }

      if (!improved) break;
    }
  }

  double _groupScore(List<RouteJob> group) {
    if (group.isEmpty) return 0;
    final ordered = orderRoute(group);
    final routeKm = distanceService.routeKm(ordered);
    final appointment = appointmentService.routePenalty(ordered);

    // İş sayısı için SIFIR ceza. Bunun yerine rotanın coğrafi bütünlüğünü
    // ölçüyoruz. Açık bir rota bazen Buca -> Konak -> Karşıyaka gibi uzun bir
    // koridoru olduğundan ucuz gösterebilir. Medoid yayılımı ve çap cezası,
    // farklı koridorlardan tek işi sırf matematiksel zincir kısa diye aynı
    // teknisyene eklemeyi engeller.
    final compactness = _compactnessKm(group);
    final diameter = _diameterKm(group);
    return routeKm + (compactness * 0.85) + (diameter * 0.35) + appointment;
  }

  double _compactnessKm(List<RouteJob> group) {
    final located = group.where((j) => j.point != null).toList(growable: false);
    if (located.length < 2) return 0;
    final center = _medoid(located);
    var total = 0.0;
    for (final job in located) {
      if (job.id == center.id) continue;
      total += distanceService.distanceKm(center.point!, job.point!);
    }
    return total;
  }

  double _diameterKm(List<RouteJob> group) {
    final located = group.where((j) => j.point != null).toList(growable: false);
    var maxKm = 0.0;
    for (var i = 0; i < located.length; i++) {
      for (var j = i + 1; j < located.length; j++) {
        maxKm = math.max(
          maxKm,
          distanceService.distanceKm(located[i].point!, located[j].point!),
        );
      }
    }
    return maxKm;
  }

  double _sequenceScore(List<RouteJob> ordered) {
    return distanceService.routeKm(ordered) +
        appointmentService.routePenalty(ordered);
  }

  List<RouteJob> _nearestNeighbor(List<RouteJob> jobs, RouteJob start) {
    final remaining = List<RouteJob>.from(jobs)..remove(start);
    final result = <RouteJob>[start];
    while (remaining.isNotEmpty) {
      final current = result.last;
      var bestIndex = 0;
      var best = double.infinity;
      for (var i = 0; i < remaining.length; i++) {
        final candidate = remaining[i];
        var score = distanceService.distanceKm(current.point!, candidate.point!);
        if (candidate.hasFixedTime) {
          // Yakın saatli işe doğru hafif çekim; uzak randevu rotanın tamamını bozmaz.
          score *= 0.90;
        }
        if (score < best) {
          best = score;
          bestIndex = i;
        }
      }
      result.add(remaining.removeAt(bestIndex));
    }
    return result;
  }

  List<RouteJob> _twoOpt(List<RouteJob> source) {
    if (source.length < 4) return source;
    var best = List<RouteJob>.from(source);
    var bestScore = _sequenceScore(best);
    for (var pass = 0; pass < 3; pass++) {
      var changed = false;
      for (var i = 1; i < best.length - 2; i++) {
        for (var k = i + 1; k < best.length - 1; k++) {
          final candidate = <RouteJob>[
            ...best.take(i),
            ...best.sublist(i, k + 1).reversed,
            ...best.skip(k + 1),
          ];
          final score = _sequenceScore(candidate);
          if (score + 0.05 < bestScore) {
            best = candidate;
            bestScore = score;
            changed = true;
          }
        }
      }
      if (!changed) break;
    }
    return best;
  }

  List<RouteJob> _startCandidates(List<RouteJob> jobs) {
    if (jobs.length <= 5) return jobs;
    final central = _mostCentral(jobs);
    RouteJob? west;
    RouteJob? east;
    RouteJob? north;
    RouteJob? south;
    for (final job in jobs) {
      west = west == null || job.point!.longitude < west.point!.longitude ? job : west;
      east = east == null || job.point!.longitude > east.point!.longitude ? job : east;
      north = north == null || job.point!.latitude > north.point!.latitude ? job : north;
      south = south == null || job.point!.latitude < south.point!.latitude ? job : south;
    }
    return <RouteJob>{central, west!, east!, north!, south!}.toList();
  }

  RouteJob _mostCentral(List<RouteJob> jobs) => _medoid(jobs);

  RouteJob _medoid(List<RouteJob> group) {
    if (group.length == 1) return group.first;
    RouteJob best = group.first;
    var bestTotal = double.infinity;
    for (final candidate in group) {
      if (candidate.point == null) continue;
      var total = 0.0;
      for (final other in group) {
        if (other.point == null || identical(candidate, other)) continue;
        total += distanceService.distanceKm(candidate.point!, other.point!);
      }
      if (total < bestTotal) {
        bestTotal = total;
        best = candidate;
      }
    }
    return best;
  }

  List<List<RouteJob>> _fallbackGroups(List<RouteJob> jobs, int count) {
    final groups = List.generate(count, (_) => <RouteJob>[]);
    for (final job in jobs) {
      groups[_smallestGroupIndex(groups)].add(job);
    }
    return groups;
  }

  int _widestGroupIndex(List<List<RouteJob>> groups) {
    var best = -1;
    var bestDiameter = -1.0;
    for (var i = 0; i < groups.length; i++) {
      if (groups[i].length < 2) continue;
      final diameter = _diameterKm(groups[i]);
      if (diameter > bestDiameter) {
        bestDiameter = diameter;
        best = i;
      }
    }
    return best;
  }

  int _largestGroupIndex(List<List<RouteJob>> groups) {
    if (groups.isEmpty) return -1;
    var index = 0;
    for (var i = 1; i < groups.length; i++) {
      if (groups[i].length > groups[index].length) index = i;
    }
    return index;
  }

  int _smallestGroupIndex(List<List<RouteJob>> groups) {
    var index = 0;
    for (var i = 1; i < groups.length; i++) {
      if (groups[i].length < groups[index].length) index = i;
    }
    return index;
  }

  int _timeSort(RouteJob a, RouteJob b) {
    final ad = a.plannedDate?.toLocal();
    final bd = b.plannedDate?.toLocal();
    if (ad == null && bd == null) return a.customerName.compareTo(b.customerName);
    if (ad == null) return 1;
    if (bd == null) return -1;
    return ad.compareTo(bd);
  }
}


class _RouteEdge {
  const _RouteEdge({required this.a, required this.b, required this.km});
  final int a;
  final int b;
  final double km;
  String get key => a < b ? '$a:$b' : '$b:$a';
}
