import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/auth/app_role.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/widgets/management_shell.dart';
import '../data/technician_location_repository.dart';

class TechnicianLocationsScreen extends ConsumerStatefulWidget {
  const TechnicianLocationsScreen({super.key});

  @override
  ConsumerState<TechnicianLocationsScreen> createState() =>
      _TechnicianLocationsScreenState();
}

class _TechnicianLocationsScreenState
    extends ConsumerState<TechnicianLocationsScreen> {
  static const LatLng _izmirCenter = LatLng(38.4237, 27.1428);
  static const Color _teal = Color(0xFF0FB7C4);
  static const Color _ink = Color(0xFF10263E);
  static const Color _muted = Color(0xFF6D7C91);
  static const Color _border = Color(0xFFDDE5EE);

  final MapController _mapController = MapController();
  Timer? _timer;
  List<TechnicianLocationSnapshot> _rows = const [];
  List<TechnicianLocationHistoryPoint> _history = const [];
  String? _selectedTechnicianId;
  bool _loading = true;
  bool _historyLoading = false;
  Object? _error;
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _refresh(fit: true);
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _refresh();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _refresh({bool fit = false}) async {
    try {
      final rows = await ref
          .read(technicianLocationRepositoryProvider)
          .getCurrentTechnicians();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
        _error = null;
        if (_selectedTechnicianId != null &&
            !rows.any((row) => row.technicianId == _selectedTechnicianId)) {
          _selectedTechnicianId = null;
          _history = const [];
        }
      });
      if (fit) _fitAllSoon();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  TechnicianLocationSnapshot? get _selected {
    final id = _selectedTechnicianId;
    if (id == null) return null;
    for (final row in _rows) {
      if (row.technicianId == id) return row;
    }
    return null;
  }

  Future<void> _openYandex(double lat, double lon) async {
    final native = Uri.parse(
      'yandexmaps://maps.yandex.com/?pt=$lon,$lat&z=17&l=map',
    );
    if (await canLaunchUrl(native)) {
      await launchUrl(native, mode: LaunchMode.externalApplication);
      return;
    }
    final web = Uri.parse(
      'https://yandex.com.tr/maps/?pt=$lon,$lat&z=17&l=map',
    );
    await launchUrl(
      web,
      mode: LaunchMode.platformDefault,
      webOnlyWindowName: '_blank',
    );
  }

  void _fitAllSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _fitAll());
  }

  void _fitAll() {
    if (!_mapReady) return;
    final points = _rows
        .where((row) => row.hasLocation)
        .map((row) => LatLng(row.latitude!, row.longitude!))
        .toList(growable: false);
    if (points.isEmpty) {
      _safeMove(_izmirCenter, 10.5);
      return;
    }
    if (points.length == 1) {
      _safeMove(points.first, 14.5);
      return;
    }
    try {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: const EdgeInsets.all(70),
          maxZoom: 14.5,
        ),
      );
    } catch (_) {}
  }

  void _safeMove(LatLng point, double zoom) {
    if (!_mapReady) return;
    try {
      _mapController.move(point, zoom);
    } catch (_) {}
  }

  void _selectTechnician(TechnicianLocationSnapshot row) {
    setState(() {
      _selectedTechnicianId = row.technicianId;
      _history = const [];
    });
    if (row.hasLocation) {
      _safeMove(LatLng(row.latitude!, row.longitude!), 15.5);
    }
  }

  Future<void> _showTodayTrack(TechnicianLocationSnapshot row) async {
    setState(() {
      _selectedTechnicianId = row.technicianId;
      _historyLoading = true;
      _history = const [];
    });
    try {
      final points = await ref
          .read(technicianLocationRepositoryProvider)
          .getHistory(technicianId: row.technicianId, day: DateTime.now());
      if (!mounted) return;
      final sorted = points.toList(growable: false)
        ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
      setState(() {
        _history = sorted;
        _historyLoading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_mapReady) return;
        final latLngs = sorted
            .map((p) => LatLng(p.latitude, p.longitude))
            .toList(growable: true);
        if (row.hasLocation) {
          latLngs.add(LatLng(row.latitude!, row.longitude!));
        }
        if (latLngs.isEmpty) return;
        if (latLngs.length == 1) {
          _safeMove(latLngs.first, 15.5);
          return;
        }
        try {
          _mapController.fitCamera(
            CameraFit.bounds(
              bounds: LatLngBounds.fromPoints(latLngs),
              padding: const EdgeInsets.all(70),
              maxZoom: 16,
            ),
          );
        } catch (_) {}
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _historyLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Konum geçmişi yüklenemedi: $error')),
      );
    }
  }

  void _clearTrack() {
    setState(() => _history = const []);
    _fitAllSoon();
  }

  _LocationStatus _statusOf(TechnicianLocationSnapshot row) {
    if (!row.hasLocation || !row.isSharing || row.recordedAt == null) {
      return _LocationStatus.offline;
    }
    final age = DateTime.now().difference(row.recordedAt!.toLocal()).abs();
    if (age <= const Duration(minutes: 3)) return _LocationStatus.live;
    if (age <= const Duration(minutes: 10)) return _LocationStatus.delayed;
    return _LocationStatus.offline;
  }

  String _ageText(DateTime? value) {
    if (value == null) return 'Konum yok';
    final diff = DateTime.now().difference(value.toLocal()).abs();
    if (diff.inSeconds < 45) return 'Az önce';
    if (diff.inMinutes < 60) return '${diff.inMinutes} dk önce';
    if (diff.inHours < 24) return '${diff.inHours} sa önce';
    return DateFormat('dd.MM HH:mm').format(value.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final authRole = ref.watch(authControllerProvider).role;
    final shellRole = authRole == AppRole.admin ? AppRole.admin : AppRole.manager;

    return ManagementShell(
      role: shellRole,
      title: 'Tekniker Konumları',
      subtitle: 'Canlı saha görünümü • 30 sn otomatik yenileme',
      actions: [
        IconButton(
          tooltip: 'Tüm teknikerleri göster',
          onPressed: _fitAll,
          icon: const Icon(Icons.center_focus_strong_rounded),
        ),
        IconButton(
          tooltip: 'Yenile',
          onPressed: () => _refresh(),
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _rows.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _rows.isEmpty) {
      final missing = _error is TechnicianLocationSchemaMissingException;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      missing ? Icons.storage_rounded : Icons.error_outline_rounded,
                      size: 44,
                      color: missing ? _teal : Colors.redAccent,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      missing
                          ? 'Tekniker konum veritabanı kurulmamış.'
                          : 'Tekniker konumları yüklenemedi.',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$_error',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: _muted),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: () => _refresh(fit: true),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Tekrar Dene'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final live = _rows.where((r) => _statusOf(r) == _LocationStatus.live).length;
    final delayed =
        _rows.where((r) => _statusOf(r) == _LocationStatus.delayed).length;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _SummaryBar(
            live: live,
            delayed: delayed,
            total: _rows.length,
            selected: _selected,
            historyVisible: _history.isNotEmpty,
            historyLoading: _historyLoading,
            onClearHistory: _clearTrack,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 900;
                final map = _buildMap();
                final list = _buildTechnicianList();
                if (!wide) {
                  return Column(
                    children: [
                      Expanded(flex: 3, child: map),
                      const SizedBox(height: 10),
                      Expanded(flex: 2, child: list),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 7, child: map),
                    const SizedBox(width: 12),
                    SizedBox(width: 350, child: list),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMap() {
    final markers = _rows
        .where((row) => row.hasLocation)
        .map((row) {
          final status = _statusOf(row);
          final selected = row.technicianId == _selectedTechnicianId;
          return Marker(
            point: LatLng(row.latitude!, row.longitude!),
            width: 176,
            height: 68,
            child: GestureDetector(
              onTap: () => _selectTechnician(row),
              child: _TechnicianMapMarker(
                name: row.technicianName,
                ageText: _ageText(row.recordedAt),
                color: status.color,
                selected: selected,
              ),
            ),
          );
        })
        .toList(growable: false);

    final historyPoints = _history
        .map((row) => LatLng(row.latitude, row.longitude))
        .toList(growable: false);

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: DecoratedBox(
        decoration: const BoxDecoration(color: Colors.white),
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _izmirCenter,
                initialZoom: 10.5,
                minZoom: 4,
                maxZoom: 19,
                onMapReady: () {
                  _mapReady = true;
                  _fitAllSoon();
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.motus.service',
                ),
                if (historyPoints.length >= 2)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: historyPoints,
                        strokeWidth: 5,
                        color: _teal,
                      ),
                    ],
                  ),
                MarkerLayer(markers: markers),
              ],
            ),
            Positioned(
              left: 12,
              top: 12,
              child: _MapLegend(),
            ),
            if (_historyLoading)
              const Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(
                    color: Color(0x22FFFFFF),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
              ),
            Positioned(
              right: 10,
              bottom: 8,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                  child: Text(
                    '© OpenStreetMap',
                    style: TextStyle(fontSize: 10, color: _muted),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTechnicianList() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 15, 16, 10),
            child: Text(
              'Teknikerler',
              style: TextStyle(
                color: _ink,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _rows.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('Aktif tekniker bulunamadı.'),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(10),
                    itemCount: _rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final row = _rows[index];
                      return _TechnicianSideCard(
                        row: row,
                        status: _statusOf(row),
                        ageText: _ageText(row.recordedAt),
                        selected: row.technicianId == _selectedTechnicianId,
                        onSelect: () => _selectTechnician(row),
                        onYandex: row.hasLocation
                            ? () => _openYandex(row.latitude!, row.longitude!)
                            : null,
                        onHistory: row.hasLocation
                            ? () => _showTodayTrack(row)
                            : null,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

enum _LocationStatus { live, delayed, offline }

extension on _LocationStatus {
  Color get color => switch (this) {
        _LocationStatus.live => const Color(0xFF19A463),
        _LocationStatus.delayed => const Color(0xFFE99A20),
        _LocationStatus.offline => const Color(0xFF9AA7B6),
      };

  String get label => switch (this) {
        _LocationStatus.live => 'Canlı',
        _LocationStatus.delayed => 'Gecikmeli',
        _LocationStatus.offline => 'Kapalı / eski',
      };
}

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({
    required this.live,
    required this.delayed,
    required this.total,
    required this.selected,
    required this.historyVisible,
    required this.historyLoading,
    required this.onClearHistory,
  });

  final int live;
  final int delayed;
  final int total;
  final TechnicianLocationSnapshot? selected;
  final bool historyVisible;
  final bool historyLoading;
  final VoidCallback onClearHistory;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDDE5EE)),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _StatusPill(
            icon: Icons.location_on_rounded,
            text: '$live canlı',
            color: const Color(0xFF19A463),
          ),
          _StatusPill(
            icon: Icons.schedule_rounded,
            text: '$delayed gecikmeli',
            color: const Color(0xFFE99A20),
          ),
          _StatusPill(
            icon: Icons.people_alt_rounded,
            text: '$total tekniker',
            color: const Color(0xFF718096),
          ),
          if (selected != null) ...[
            const SizedBox(width: 4),
            Text(
              'Seçili: ${selected!.technicianName}',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: Color(0xFF10263E),
              ),
            ),
          ],
          if (historyLoading)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          if (historyVisible)
            TextButton.icon(
              onPressed: onClearHistory,
              icon: const Icon(Icons.route_rounded, size: 18),
              label: const Text('Güzergâhı Kapat'),
            ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(color: color, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _MapLegend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(color: Color(0x22000000), blurRadius: 10),
        ],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _LegendDot(color: Color(0xFF19A463), text: 'Canlı'),
          SizedBox(width: 10),
          _LegendDot(color: Color(0xFFE99A20), text: '3–10 dk'),
          SizedBox(width: 10),
          _LegendDot(color: Color(0xFF9AA7B6), text: 'Eski/Kapalı'),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.text});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _TechnicianMapMarker extends StatelessWidget {
  const _TechnicianMapMarker({
    required this.name,
    required this.ageText,
    required this.color,
    required this.selected,
  });

  final String name;
  final String ageText;
  final Color color;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? color : const Color(0xFFD6DFE8), width: selected ? 2 : 1),
          boxShadow: const [
            BoxShadow(color: Color(0x33000000), blurRadius: 9, offset: Offset(0, 3)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: color,
              child: const Icon(Icons.person_rounded, size: 19, color: Colors.white),
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFF10263E)),
                  ),
                  Text(
                    ageText,
                    maxLines: 1,
                    style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TechnicianSideCard extends StatelessWidget {
  const _TechnicianSideCard({
    required this.row,
    required this.status,
    required this.ageText,
    required this.selected,
    required this.onSelect,
    required this.onYandex,
    required this.onHistory,
  });

  final TechnicianLocationSnapshot row;
  final _LocationStatus status;
  final String ageText;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback? onYandex;
  final VoidCallback? onHistory;

  @override
  Widget build(BuildContext context) {
    final color = status.color;
    return Material(
      color: selected ? const Color(0xFFEAF9FA) : const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? const Color(0xFF0FB7C4) : const Color(0xFFE3E9F0),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: color.withValues(alpha: 0.13),
                    child: Icon(Icons.person_pin_circle_rounded, color: color),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row.technicianName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF10263E),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          row.hasLocation ? '$ageText • ${status.label}' : 'Henüz konum paylaşmadı',
                          style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (row.hasLocation) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onHistory,
                        icon: const Icon(Icons.route_rounded, size: 17),
                        label: const Text('Bugünkü Hareket'),
                      ),
                    ),
                    const SizedBox(width: 7),
                    IconButton.outlined(
                      tooltip: 'Yandex’te aç',
                      onPressed: onYandex,
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
