import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../data/notification_repository.dart';
import '../../../core/auth/app_role.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/widgets/management_shell.dart';

class NotificationCenterScreen extends ConsumerWidget {
  const NotificationCenterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(notificationsProvider);
    final authState = ref.watch(authControllerProvider);
    final currentRole = authState.role ?? AppRole.secretary;
    return ManagementShell(
      role: currentRole,
      title: 'Bildirimler',
      subtitle: 'Servis, tahsilat ve sistem bildirimlerini tek ekrandan yönetin.',
      actions: [
        TextButton.icon(
          onPressed: () async {
            await ref.read(notificationRepositoryProvider).markAllRead();
            ref.invalidate(notificationsProvider);
            ref.invalidate(unreadNotificationCountProvider);
          },
          icon: const Icon(Icons.done_all),
          label: const Text('Tümünü okundu yap'),
        ),
      ],
      child: notifications.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorState(onRetry: () => ref.invalidate(notificationsProvider)),
        data: (items) {
          final unread = items.where((e) => !e.isRead).length;
          final today = items.where((e) {
            final d = e.createdAt.toLocal();
            final n = DateTime.now();
            return d.year == n.year && d.month == n.month && d.day == n.day;
          }).length;
          final important = items.where((e) {
            final t = '${e.title} ${e.message}'.toLowerCase();
            return t.contains('kritik') || t.contains('gecik') || t.contains('iptal');
          }).length;

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(notificationsProvider);
              await ref.read(notificationsProvider.future);
            },
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                LayoutBuilder(
                  builder: (context, c) {
                    final w = c.maxWidth >= 1000 ? (c.maxWidth - 36) / 4 : c.maxWidth >= 620 ? (c.maxWidth - 12) / 2 : c.maxWidth;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _MetricCard(width: w, title: 'Toplam Bildirim', value: items.length.toString(), subtitle: 'Tüm zamanlar', icon: Icons.notifications_active_outlined, color: const Color(0xFF22B8CF)),
                        _MetricCard(width: w, title: 'Okunmamış', value: unread.toString(), subtitle: 'Yeni bildirim', icon: Icons.mark_email_unread_outlined, color: const Color(0xFF8A6DF1)),
                        _MetricCard(width: w, title: 'Bugünkü', value: today.toString(), subtitle: 'Bugün gelen', icon: Icons.today_outlined, color: const Color(0xFF35C978)),
                        _MetricCard(width: w, title: 'Önemli', value: important.toString(), subtitle: 'Dikkat gereken', icon: Icons.warning_amber_rounded, color: const Color(0xFFFF6B6B)),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.tune_rounded, color: Color(0xFF22C7D4)),
                        const SizedBox(width: 10),
                        const Text('Bildirim Akışı', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(color: const Color(0xFF22B8CF).withOpacity(.12), borderRadius: BorderRadius.circular(999)),
                          child: Text('$unread okunmamış', style: const TextStyle(color: Color(0xFF22C7D4), fontWeight: FontWeight.w800, fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                if (items.isEmpty)
                  const _EmptyState()
                else
                  ...items.map((item) => _NotificationTile(
                        item: item,
                        onTap: () async {
                          if (!item.isRead) {
                            await ref.read(notificationRepositoryProvider).markRead(item.id);
                            ref.invalidate(notificationsProvider);
                            ref.invalidate(unreadNotificationCountProvider);
                          }
                          if (context.mounted && item.route != null && item.route!.isNotEmpty) {
                            try {
                              await context.push(item.route!);
                            } catch (_) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                                const SnackBar(
                                  content: Text('Bu bildirime bağlı kayıt artık mevcut değil.'),
                                ),
                              );
                            }
                          }
                        },
                      )),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.width, required this.title, required this.value, required this.subtitle, required this.icon, required this.color});
  final double width;
  final String title, value, subtitle;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(width: 46, height: 46, decoration: BoxDecoration(color: color.withOpacity(.14), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: color)),
                const SizedBox(width: 13),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(color: Color(0xFF91A4B7), fontSize: 12, fontWeight: FontWeight.w700)),
                  Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                  Text(subtitle, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
                ])),
              ],
            ),
          ),
        ),
      );
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item, required this.onTap});
  final AppNotification item;
  final VoidCallback onTap;

  Color get color {
    final text = '${item.title} ${item.message}'.toLowerCase();
    if (text.contains('kritik') || text.contains('iptal') || text.contains('gecik')) return const Color(0xFFFF6B6B);
    if (text.contains('tahsil')) return const Color(0xFF22B8CF);
    if (text.contains('tamam')) return const Color(0xFF35C978);
    if (text.contains('bakım') || text.contains('hatırlat')) return const Color(0xFFF4B740);
    return const Color(0xFF8A6DF1);
  }

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(width: 44, height: 44, decoration: BoxDecoration(color: color.withOpacity(.14), borderRadius: BorderRadius.circular(13)), child: Icon(item.isRead ? Icons.notifications_none : Icons.notifications_active, color: color)),
                const SizedBox(width: 13),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(item.title, style: TextStyle(fontWeight: item.isRead ? FontWeight.w700 : FontWeight.w900, fontSize: 15))),
                    if (!item.isRead) Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF22C7D4), shape: BoxShape.circle)),
                  ]),
                  const SizedBox(height: 4),
                  Text(item.message, style: const TextStyle(color: Color(0xFF607086))),
                  const SizedBox(height: 6),
                  Text(DateFormat('dd.MM.yyyy HH:mm', 'tr_TR').format(item.createdAt.toLocal()), style: const TextStyle(color: Color(0xFF71879A), fontSize: 11)),
                ])),
                const Icon(Icons.chevron_right_rounded, color: Color(0xFF71879A)),
              ],
            ),
          ),
        ),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 70, horizontal: 24),
          child: Column(
            children: [
              Container(width: 76, height: 76, decoration: BoxDecoration(color: const Color(0xFF22B8CF).withOpacity(.12), borderRadius: BorderRadius.circular(24)), child: const Icon(Icons.notifications_none_rounded, size: 40, color: Color(0xFF22C7D4))),
              const SizedBox(height: 18),
              const Text('Bildirim kutunuz tertemiz', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              const Text('Yeni servis, tahsilat veya sistem hareketi olduğunda burada görünecek.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF91A4B7))),
            ],
          ),
        ),
      );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline, size: 48),
        const SizedBox(height: 12),
        const Text('Bildirimler alınamadı.'),
        const SizedBox(height: 12),
        FilledButton(onPressed: onRetry, child: const Text('Tekrar Dene')),
      ]));
}
