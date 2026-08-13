import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_client_provider.dart';

class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.createdAt,
    required this.isRead,
    this.route,
    this.notificationType,
    this.entityType,
    this.entityId,
  });

  final String id;
  final String title;
  final String message;
  final DateTime createdAt;
  final bool isRead;
  final String? route;
  final String? notificationType;
  final String? entityType;
  final String? entityId;

  String? get serviceRequestId {
    if (entityType == 'service_request' && entityId != null && entityId!.isNotEmpty) {
      return entityId;
    }
    final value = route ?? '';
    final match = RegExp(r'^/technician/jobs/([^/?#]+)').firstMatch(value);
    return match?.group(1);
  }

  factory AppNotification.fromMap(Map<String, dynamic> map) {
    return AppNotification(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? 'Bildirim',
      message: map['message']?.toString() ?? '',
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ??
          DateTime.now(),
      isRead: map['is_read'] == true,
      route: map['route']?.toString(),
      notificationType: map['notification_type']?.toString(),
      entityType: map['entity_type']?.toString(),
      entityId: map['entity_id']?.toString(),
    );
  }
}

class NotificationRepository {
  NotificationRepository(this._client);

  final SupabaseClient _client;

  Future<List<AppNotification>> listMine() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) return const [];

    final rows = await _client
        .from('app_notifications')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(100);

    var items = (rows as List)
        .whereType<Map>()
        .map((row) => AppNotification.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false);

    String? role;
    try {
      final profile = await _client
          .from('profiles')
          .select('role')
          .eq('id', userId)
          .maybeSingle();
      role = profile?['role']?.toString();
    } catch (_) {}

    // Eski sürümlerde “tekniker gidemiyor” bildirimi şirketteki bütün
    // sekreterlere gönderilmiş olabilir. Sekreter ekranında yalnız kendi
    // açtığı servislerle ilgili bildirimleri bırak.
    if (role == 'secretary') {
      final secretaryServiceIds = items
          .map((item) => item.serviceRequestId)
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList(growable: false);
      if (secretaryServiceIds.isNotEmpty) {
        try {
          final ownRows = await _client
              .from('service_requests')
              .select('id')
              .inFilter('id', secretaryServiceIds)
              .eq('created_by', userId);
          final ownIds = (ownRows as List)
              .whereType<Map>()
              .map((row) => row['id']?.toString() ?? '')
              .where((id) => id.isNotEmpty)
              .toSet();
          items = items.where((item) {
            final serviceId = item.serviceRequestId;
            if (serviceId == null || serviceId.isEmpty) return true;
            return ownIds.contains(serviceId);
          }).toList(growable: false);
        } catch (_) {}
      }
    }

    // Servis atama bildirimi, servis silindiyse veya artık başka teknisyene
    // atanmışsa eski teknisyenin bildirim merkezinde kalmamalı.
    final serviceIds = items
        .map((item) => item.serviceRequestId)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);

    if (serviceIds.isEmpty) return items;

    try {
      final activeRows = await _client
          .from('service_requests')
          .select('id, assigned_technician_id')
          .inFilter('id', serviceIds)
          .eq('assigned_technician_id', userId);

      final visibleServiceIds = (activeRows as List)
          .whereType<Map>()
          .map((row) => row['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();

      return items.where((item) {
        // Yalnızca teknisyene atama bildirimi, iş artık o teknisyende değilse
        // gizlenir. Yönetici/sekreter için oluşturulan “tekniker gidemiyor”
        // gibi operasyon bildirimleri bu filtreden etkilenmemelidir.
        if (item.notificationType != 'service_assignment') return true;
        final serviceId = item.serviceRequestId;
        if (serviceId == null || serviceId.isEmpty) return true;
        return visibleServiceIds.contains(serviceId);
      }).toList(growable: false);
    } on PostgrestException {
      // Bildirim ekranı servis kontrolü yüzünden tamamen bozulmasın.
      return items;
    }
  }

  Future<int> unreadCount() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) return 0;
    final items = await listMine();
    return items.where((item) => !item.isRead).length;
  }

  Future<void> markRead(String id) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) return;
    await _client
        .from('app_notifications')
        .update({
          'is_read': true,
          'read_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id)
        .eq('user_id', userId);
  }

  Future<void> markAllRead() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) return;
    await _client
        .from('app_notifications')
        .update({
          'is_read': true,
          'read_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('user_id', userId)
        .eq('is_read', false);
  }
}

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepository(ref.watch(supabaseClientProvider));
});

final notificationsProvider = FutureProvider.autoDispose<List<AppNotification>>((ref) {
  return ref.watch(notificationRepositoryProvider).listMine();
});

final unreadNotificationCountProvider = FutureProvider.autoDispose<int>((ref) {
  return ref.watch(notificationRepositoryProvider).unreadCount();
});
