import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/app_role.dart';
import '../../../core/widgets/management_shell.dart';
import '../../../core/widgets/arn_app_bar.dart';
import '../data/user_management_repository_provider.dart';
import '../domain/user_management_user.dart';
import 'user_management_controller.dart';

class UserManagementScreen extends ConsumerStatefulWidget {
  const UserManagementScreen({super.key});

  @override
  ConsumerState<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends ConsumerState<UserManagementScreen> {
  late final UserManagementController controller;
  final searchController = TextEditingController();
  final fullNameController = TextEditingController();
  final usernameController = TextEditingController();
  final emailController = TextEditingController();
  final phoneController = TextEditingController();
  final passwordController = TextEditingController();
  final passwordRepeatController = TextEditingController();
  AppRole createRole = AppRole.secretary;
  AppRole? roleFilter;
  bool createActive = true;
  bool showArchived = false;
  bool showCreateForm = false;

  @override
  void initState() {
    super.initState();
    controller = UserManagementController(repository: ref.read(userManagementRepositoryProvider));
    controller.loadUsers();
    searchController.addListener(_refresh);
  }

  @override
  void dispose() {
    searchController.removeListener(_refresh);
    searchController.dispose();
    fullNameController.dispose();
    usernameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    passwordController.dispose();
    passwordRepeatController.dispose();
    controller.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  List<UserManagementUser> _visibleUsers(List<UserManagementUser> users) {
    final query = searchController.text.trim().toLowerCase();
    return users.where((user) {
      if (showArchived != user.isArchived) return false;
      if (roleFilter != null && user.role != roleFilter) return false;
      if (query.isEmpty) return true;
      return user.fullName.toLowerCase().contains(query) ||
          user.username.toLowerCase().contains(query) ||
          user.email.toLowerCase().contains(query) ||
          user.phone.contains(query);
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final state = controller.state;
        final users = _visibleUsers(state.users);
        final all = state.users.where((u) => !u.isArchived).toList(growable: false);
        final active = all.where((u) => u.isActive).length;
        final secretaries = all.where((u) => u.role == AppRole.secretary).length;
        final technicians = all.where((u) => u.role == AppRole.technician).length;
        final managers = all.where((u) => u.role == AppRole.manager || u.role == AppRole.admin).length;

        return ManagementShell(
          role: AppRole.admin,
          title: 'Tüm Kullanıcılar',
          subtitle: 'Sistemdeki kullanıcıları, rolleri ve erişimleri yönetin.',
          dark: true,
          actions: [
            IconButton(
              tooltip: 'Yenile',
              onPressed: state.isLoading ? null : controller.loadUsers,
              icon: const Icon(Icons.refresh),
            ),
          ],
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final cardWidth = width >= 1200 ? (width - 48) / 5 : width >= 760 ? (width - 24) / 3 : width;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _metricCard('Toplam Kullanıcı', all.length.toString(), 'Tüm kullanıcılar', Icons.groups_2_outlined, const Color(0xFF22B8CF), cardWidth),
                      _metricCard('Aktif Kullanıcı', active.toString(), 'Aktif durumda', Icons.verified_user_outlined, const Color(0xFF35C978), cardWidth),
                      _metricCard('Sekreter', secretaries.toString(), 'Sekreter hesabı', Icons.support_agent_outlined, const Color(0xFFF4B740), cardWidth),
                      _metricCard('Teknisyen', technicians.toString(), 'Teknisyen hesabı', Icons.engineering_outlined, const Color(0xFF8A6DF1), cardWidth),
                      _metricCard('Yönetici', managers.toString(), 'Yönetici hesabı', Icons.admin_panel_settings_outlined, const Color(0xFF4D8DF7), cardWidth),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final compact = constraints.maxWidth < 680;
                          final actions = <Widget>[
                            FilledButton.icon(
                              onPressed: () => setState(() => showCreateForm = !showCreateForm),
                              icon: Icon(showCreateForm ? Icons.close : Icons.person_add_alt_1),
                              label: Text(showCreateForm ? 'Formu Kapat' : 'Yeni Kullanıcı'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => setState(() => showArchived = !showArchived),
                              icon: Icon(showArchived ? Icons.inventory_2 : Icons.archive_outlined),
                              label: Text(showArchived ? 'Aktif Kullanıcıları Göster' : 'Arşivdekileri Göster'),
                            ),
                          ];
                          if (compact) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                ...actions.map((e) => Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: e,
                                    )),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text('${users.length} kayıt', style: const TextStyle(color: Color(0xFF91A4B7), fontWeight: FontWeight.w700)),
                                ),
                              ],
                            );
                          }
                          return Row(
                            children: [
                              actions[0],
                              const SizedBox(width: 10),
                              actions[1],
                              const Spacer(),
                              Text('${users.length} kayıt', style: const TextStyle(color: Color(0xFF91A4B7), fontWeight: FontWeight.w700)),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 14),
                      LayoutBuilder(
                        builder: (context, constraints) => Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            SizedBox(
                              width: constraints.maxWidth < 760 ? constraints.maxWidth : 420,
                              child: TextField(
                                controller: searchController,
                                decoration: const InputDecoration(
                                  prefixIcon: Icon(Icons.search),
                                  hintText: 'Kullanıcı adı, e-posta veya telefon ara...',
                                ),
                              ),
                            ),
                            SizedBox(
                              width: constraints.maxWidth < 760 ? constraints.maxWidth : 240,
                              child: DropdownButtonFormField<AppRole?>(
                                initialValue: roleFilter,
                                decoration: const InputDecoration(labelText: 'Rol'),
                                items: [
                                  const DropdownMenuItem<AppRole?>(value: null, child: Text('Tüm roller')),
                                  ...AppRole.values.map((role) => DropdownMenuItem<AppRole?>(value: role, child: Text(role.label))),
                                ],
                                onChanged: (value) => setState(() => roleFilter = value),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (showCreateForm) ...[
                const SizedBox(height: 12),
                _CreateUserCard(
                  fullNameController: fullNameController,
                  usernameController: usernameController,
                  emailController: emailController,
                  phoneController: phoneController,
                  passwordController: passwordController,
                  passwordRepeatController: passwordRepeatController,
                  role: createRole,
                  isActive: createActive,
                  isSaving: state.isSaving,
                  onRoleChanged: (value) => setState(() => createRole = value),
                  onActiveChanged: (value) => setState(() => createActive = value),
                  onCreate: _createUser,
                ),
              ],
              const SizedBox(height: 16),
              if (state.isLoading)
                const Center(child: Padding(padding: EdgeInsets.all(48), child: CircularProgressIndicator()))
              else if (users.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(48),
                    child: Column(
                      children: [
                        const Icon(Icons.manage_accounts_outlined, size: 54, color: Color(0xFF22C7D4)),
                        const SizedBox(height: 12),
                        Text(showArchived ? 'Arşivlenmiş kullanıcı yok.' : 'Bu filtreye uygun kullanıcı yok.'),
                      ],
                    ),
                  ),
                )
              else
                ...users.map((user) => _UserCard(
                  user: user,
                  isSaving: state.isSaving,
                  onEdit: () => _showEditDialog(user),
                  onProfile: () => _showPersonnelProfile(user),
                  onPassword: () => _changePassword(user),
                  onArchive: () => _archiveUser(user),
                  onRestore: () => _restoreUser(user),
                  onDelete: () => _deleteUserPermanently(user),
                )),
            ],
          ),
        );
      },
    );
  }

  Widget _metricCard(String title, String value, String subtitle, IconData icon, Color color, double width) {
    return SizedBox(
      width: width,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: color.withOpacity(.14), borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(color: Color(0xFF91A4B7), fontSize: 12, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                    Text(subtitle, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createUser() async {
    final ok = await controller.createUser(
      fullName: fullNameController.text,
      username: usernameController.text,
      email: emailController.text,
      phone: phoneController.text,
      role: createRole,
      password: passwordController.text,
      passwordConfirmation: passwordRepeatController.text,
      isActive: createActive,
    );
    if (!mounted) return;
    _showMessage();
    if (ok) {
      for (final c in [fullNameController, usernameController, emailController, phoneController, passwordController, passwordRepeatController]) {
        c.clear();
      }
      setState(() => showCreateForm = false);
    }
  }

  Future<void> _showEditDialog(UserManagementUser user) async {
    final name = TextEditingController(text: user.fullName);
    final username = TextEditingController(text: user.username);
    final phone = TextEditingController(text: user.phone);
    var role = user.role;
    var active = user.isActive;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Kullanıcıyı Düzenle'),
          content: SizedBox(
            width: MediaQuery.sizeOf(context).width < 620 ? MediaQuery.sizeOf(context).width * .82 : 480,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: name, decoration: const InputDecoration(labelText: 'Ad Soyad')),
                const SizedBox(height: 12),
                TextField(controller: username, decoration: const InputDecoration(labelText: 'Kullanıcı adı')),
                const SizedBox(height: 12),
                TextField(controller: phone, decoration: const InputDecoration(labelText: 'Telefon')),
                const SizedBox(height: 12),
                DropdownButtonFormField<AppRole>(
                  initialValue: role,
                  decoration: const InputDecoration(labelText: 'Rol'),
                  items: AppRole.values.map((r) => DropdownMenuItem(value: r, child: Text(r.label))).toList(),
                  onChanged: (value) => setDialogState(() => role = value ?? role),
                ),
                SwitchListTile(
                  value: active,
                  title: const Text('Aktif kullanıcı'),
                  contentPadding: EdgeInsets.zero,
                  onChanged: (value) => setDialogState(() => active = value),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Vazgeç')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Kaydet')),
          ],
        ),
      ),
    );
    if (saved == true) {
      await controller.updateUser(
        userId: user.id,
        fullName: name.text.trim(),
        username: username.text.trim(),
        phone: phone.text.trim(),
        role: role,
        isActive: active,
      );
      if (mounted) _showMessage();
    }
    name.dispose(); username.dispose(); phone.dispose();
  }

  Future<void> _showPersonnelProfile(UserManagementUser user) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${user.fullName} • Personel Profili'),
        content: SizedBox(
          width: 760,
          height: 560,
          child: FutureBuilder<PersonnelProfile>(
            future: controller.getPersonnelProfile(user.id),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
              if (snapshot.hasError) return Center(child: Text('Profil yüklenemedi: ${snapshot.error}'));
              final profile = snapshot.data!;
              return _PersonnelProfileView(user: user, profile: profile);
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Kapat'))],
      ),
    );
  }

  Future<void> _archiveUser(UserManagementUser user) async {
    final confirmed = await _confirm(
      'Kullanıcıyı Arşive Al',
      '${user.fullName} giriş yapamayacak ve yeni iş alamayacak. Eski servisleri ve adı geçmişte korunacak.',
      'Arşive Al',
    );
    if (!confirmed) return;
    await controller.archiveUser(user.id);
    if (mounted) _showMessage();
  }

  Future<void> _restoreUser(UserManagementUser user) async {
    String suggestedUsername() {
      final archivedBase = user.username.split('__arsiv__').first.trim().toLowerCase();
      if (RegExp(r'^[a-z0-9._-]{3,30}$').hasMatch(archivedBase)) {
        return archivedBase;
      }

      final emailBase = user.email.split('@').first.trim().toLowerCase();
      if (RegExp(r'^[a-z0-9._-]{3,30}$').hasMatch(emailBase)) {
        return emailBase;
      }

      var nameBase = user.fullName.toLowerCase();
      const tr = {
        'ç': 'c', 'ğ': 'g', 'ı': 'i', 'ö': 'o', 'ş': 's', 'ü': 'u',
      };
      tr.forEach((key, value) => nameBase = nameBase.replaceAll(key, value));
      nameBase = nameBase.replaceAll(RegExp(r'[^a-z0-9._-]+'), '');
      if (nameBase.length > 30) nameBase = nameBase.substring(0, 30);
      return nameBase.length >= 3 ? nameBase : 'user${user.id.substring(0, 6)}';
    }

    final username = TextEditingController(text: suggestedUsername());
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Kullanıcıyı Geri Yükle'),
        content: TextField(controller: username, decoration: const InputDecoration(labelText: 'Kullanıcı adı')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, username.text.trim()), child: const Text('Geri Yükle')),
        ],
      ),
    );
    username.dispose();
    if (result == null || result.isEmpty) return;
    await controller.restoreUser(user.id, result);
    if (mounted) _showMessage();
  }

  Future<void> _deleteUserPermanently(UserManagementUser user) async {
    final confirmed = await _confirm(
      'Kullanıcıyı Kalıcı Sil',
      '${user.fullName} hesabı Supabase Auth ve kullanıcı listesinden tamamen silinecek. Bu işlem geri alınamaz. Geçmiş servis bağlantısı varsa sistem güvenlik için silmeyi reddedebilir.',
      'Kalıcı Sil',
    );
    if (!confirmed) return;

    final second = await _confirm(
      'Son Onay',
      '${user.fullName} kullanıcısını gerçekten tamamen silmek istiyor musunuz?',
      'Evet, Sil',
    );
    if (!second) return;

    await controller.deleteUserPermanently(user.id);
    if (mounted) _showMessage();
  }

  Future<void> _changePassword(UserManagementUser user) async {
    final password = TextEditingController();
    final repeat = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${user.fullName} için yeni şifre'),
        content: SizedBox(width: MediaQuery.sizeOf(context).width < 540 ? MediaQuery.sizeOf(context).width * .82 : 400, child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Yeni şifre')),
          const SizedBox(height: 12),
          TextField(controller: repeat, obscureText: true, decoration: const InputDecoration(labelText: 'Şifre tekrar')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Vazgeç')),
          FilledButton(onPressed: () {
            if (password.text != repeat.text) return;
            Navigator.pop(dialogContext, password.text);
          }, child: const Text('Kaydet')),
        ],
      ),
    );
    password.dispose(); repeat.dispose();
    if (result == null) return;
    await controller.setUserPassword(user.id, result);
    if (mounted) _showMessage();
  }

  Future<bool> _confirm(String title, String message, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Vazgeç')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(action)),
          ],
        ),
      ) ?? false;

  void _showMessage() {
    final message = controller.state.errorMessage ?? controller.state.successMessage;
    if (message != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _CreateUserCard extends StatelessWidget {
  const _CreateUserCard({
    required this.fullNameController, required this.usernameController,
    required this.emailController, required this.phoneController,
    required this.passwordController, required this.passwordRepeatController,
    required this.role, required this.isActive, required this.isSaving,
    required this.onRoleChanged, required this.onActiveChanged, required this.onCreate,
  });
  final TextEditingController fullNameController, usernameController, emailController, phoneController, passwordController, passwordRepeatController;
  final AppRole role;
  final bool isActive, isSaving;
  final ValueChanged<AppRole> onRoleChanged;
  final ValueChanged<bool> onActiveChanged;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Yeni kullanıcı oluştur', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        Wrap(spacing: 12, runSpacing: 12, children: [
          _field(fullNameController, 'Ad Soyad'),
          _field(usernameController, 'Kullanıcı adı'),
          _field(emailController, 'E-posta'),
          _field(phoneController, 'Telefon'),
          SizedBox(width: 300, child: DropdownButtonFormField<AppRole>(
            initialValue: role,
            decoration: const InputDecoration(labelText: 'Rol'),
            items: AppRole.values.where((r) => r != AppRole.admin).map((r) => DropdownMenuItem(value: r, child: Text(r.label))).toList(),
            onChanged: (value) { if (value != null) onRoleChanged(value); },
          )),
          _field(passwordController, 'Şifre', obscure: true),
          _field(passwordRepeatController, 'Şifre tekrar', obscure: true),
        ]),
        SwitchListTile(value: isActive, title: const Text('Aktif kullanıcı'), contentPadding: EdgeInsets.zero, onChanged: onActiveChanged),
        FilledButton.icon(onPressed: isSaving ? null : onCreate, icon: const Icon(Icons.person_add), label: const Text('Kullanıcı Oluştur')),
      ]),
    ),
  );

  Widget _field(TextEditingController controller, String label, {bool obscure = false}) => SizedBox(
    width: 300,
    child: TextField(controller: controller, obscureText: obscure, decoration: InputDecoration(labelText: label)),
  );
}

class _UserCard extends StatelessWidget {
  const _UserCard({required this.user, required this.isSaving, required this.onEdit, required this.onProfile, required this.onPassword, required this.onArchive, required this.onRestore, required this.onDelete});
  final UserManagementUser user;
  final bool isSaving;
  final VoidCallback onEdit, onProfile, onPassword, onArchive, onRestore, onDelete;

  Color get _roleColor => switch (user.role) {
        AppRole.secretary => const Color(0xFFF4B740),
        AppRole.technician => const Color(0xFF8A6DF1),
        AppRole.manager => const Color(0xFF4D8DF7),
        AppRole.admin => const Color(0xFF22B8CF),
      };

  @override
  Widget build(BuildContext context) {
    final statusColor = user.isArchived
        ? const Color(0xFF8190A0)
        : user.isActive
            ? const Color(0xFF35C978)
            : const Color(0xFFFF6B6B);
    final status = user.isArchived ? 'Arşivde' : (user.isActive ? 'Aktif' : 'Pasif');
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onProfile,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFF17BECB),
                child: Text(user.fullName.isEmpty ? '?' : user.fullName.substring(0, 1).toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
              ),
              const SizedBox(width: 13),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.fullName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(height: 3),
                    Text('@${user.username.isEmpty ? '-' : user.username} • ${user.email}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF91A4B7), fontSize: 12)),
                  ],
                ),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: _roleColor.withOpacity(.14), borderRadius: BorderRadius.circular(999)),
                    child: Text(user.role.label, style: TextStyle(color: _roleColor, fontSize: 11, fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(user.phone.isEmpty ? '-' : user.phone, style: const TextStyle(color: Color(0xFFD5E0E8), fontWeight: FontWeight.w600)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: statusColor.withOpacity(.14), borderRadius: BorderRadius.circular(999)),
                child: Text(status, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 8),
              if (user.isArchived) ...[
                IconButton(tooltip: 'Personel Profili', onPressed: onProfile, icon: const Icon(Icons.badge_outlined)),
                IconButton(tooltip: 'Geri Yükle', onPressed: isSaving ? null : onRestore, icon: const Icon(Icons.unarchive_outlined)),
                IconButton(tooltip: 'Kalıcı Sil', onPressed: isSaving ? null : onDelete, color: const Color(0xFFFF6B6B), icon: const Icon(Icons.delete_forever_outlined)),
              ] else ...[
                IconButton(tooltip: 'Personel Profili', onPressed: onProfile, icon: const Icon(Icons.badge_outlined)),
                IconButton(tooltip: 'Düzenle', onPressed: isSaving ? null : onEdit, icon: const Icon(Icons.edit_outlined)),
                IconButton(tooltip: 'Şifre Belirle', onPressed: isSaving ? null : onPassword, icon: const Icon(Icons.password_outlined)),
                IconButton(tooltip: 'Arşive Al', onPressed: isSaving ? null : onArchive, icon: const Icon(Icons.archive_outlined)),
                IconButton(tooltip: 'Kalıcı Sil', onPressed: isSaving ? null : onDelete, color: const Color(0xFFFF6B6B), icon: const Icon(Icons.delete_forever_outlined)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PersonnelProfileView extends StatelessWidget {
  const _PersonnelProfileView({required this.user, required this.profile});
  final UserManagementUser user;
  final PersonnelProfile profile;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');
    return ListView(children: [
      Card(child: ListTile(
        leading: const Icon(Icons.person_outline),
        title: Text(user.fullName),
        subtitle: Text('@${user.username} • ${user.email}\n${user.role.label} • ${user.isArchived ? 'Arşivde' : 'Aktif'}'),
      )),
      const SizedBox(height: 8),
      Wrap(spacing: 10, runSpacing: 10, children: [
        _stat('Tamamlanan İş', profile.completedJobs.toString(), Icons.task_alt),
        _stat('Bu Ay İş', profile.monthJobs.toString(), Icons.calendar_month),
        _stat('Açtığı Servis', profile.openedServices.toString(), Icons.assignment_add),
        _stat('Bu Ay Açılan', profile.monthOpenedServices.toString(), Icons.today),
        _stat('Toplam Ciro', currency.format(profile.turnover), Icons.payments_outlined),
        _stat('Bu Ay Ciro', currency.format(profile.monthTurnover), Icons.trending_up),
      ]),
      const SizedBox(height: 18),
      Text('Son İşlemler', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 6),
      if (profile.recentJobs.isEmpty) const Text('Kayıt bulunmuyor.') else ...profile.recentJobs.map((job) => ListTile(
        dense: true,
        leading: const Icon(Icons.build_outlined),
        title: Text(job['customer_name']?.toString() ?? '-'),
        subtitle: Text('${job['service_type'] ?? '-'} • ${job['status'] ?? '-'}'),
        trailing: Text(currency.format((job['price'] as num?)?.toDouble() ?? 0)),
      )),
      const SizedBox(height: 12),
      Text('Kullandığı Ürünler', style: Theme.of(context).textTheme.titleMedium),
      if (profile.usedProducts.isEmpty) const Text('Ürün kaydı bulunmuyor.') else ...profile.usedProducts.map((product) => ListTile(
        dense: true,
        title: Text(product['product_name']?.toString() ?? '-'),
        trailing: Text('${product['quantity'] ?? 0} adet'),
      )),
    ]);
  }

  Widget _stat(String title, String value, IconData icon) => SizedBox(
    width: 220,
    child: Card(child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        Icon(icon), const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 12)),
          Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        ])),
      ]),
    )),
  );
}
