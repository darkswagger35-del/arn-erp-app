import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_provider.dart';
import '../data/operations_providers.dart';

class EntityField {
  const EntityField({
    required this.keyName,
    required this.label,
    this.keyboardType = TextInputType.text,
    this.required = false,
    this.numeric = false,
  });

  final String keyName;
  final String label;
  final TextInputType keyboardType;
  final bool required;
  final bool numeric;
}

class EntityListScreen extends ConsumerStatefulWidget {
  const EntityListScreen({
    super.key,
    required this.title,
    required this.table,
    required this.fields,
    required this.primaryLabelKey,
    this.subtitleKeys = const [],
  });

  final String title;
  final String table;
  final List<EntityField> fields;
  final String primaryLabelKey;
  final List<String> subtitleKeys;

  @override
  ConsumerState<EntityListScreen> createState() => _EntityListScreenState();
}

class _EntityListScreenState extends ConsumerState<EntityListScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await ref
          .read(operationsRepositoryProvider)
          .list(widget.table);
      if (!mounted) return;
      setState(() => _rows = rows);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error =
            'Kayıtlar yüklenemedi. SQL kurulumunu ve bağlantıyı kontrol edin.',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openForm([Map<String, dynamic>? row]) async {
    final controllers = <String, TextEditingController>{};
    for (final field in widget.fields) {
      controllers[field.keyName] = TextEditingController(
        text: row?[field.keyName]?.toString() ?? '',
      );
    }

    final formKey = GlobalKey<FormState>();
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          row == null ? '${widget.title} Ekle' : '${widget.title} Düzenle',
        ),
        content: SizedBox(
          width: 520,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: widget.fields.map((field) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextFormField(
                      controller: controllers[field.keyName],
                      keyboardType: field.keyboardType,
                      decoration: InputDecoration(labelText: field.label),
                      validator: field.required
                          ? (value) => value == null || value.trim().isEmpty
                                ? 'Bu alan zorunludur.'
                                : null
                          : null,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(dialogContext, true);
              }
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );

    if (save != true) {
      for (final controller in controllers.values) {
        controller.dispose();
      }
      return;
    }

    final auth = ref.read(authControllerProvider);
    final values = <String, dynamic>{'company_id': auth.profile?.companyId};
    for (final field in widget.fields) {
      final raw = controllers[field.keyName]!.text.trim();
      values[field.keyName] = field.numeric
          ? (double.tryParse(raw.replaceAll(',', '.')) ?? 0)
          : raw;
    }

    try {
      if (row == null) {
        await ref
            .read(operationsRepositoryProvider)
            .insert(widget.table, values);
      } else {
        await ref
            .read(operationsRepositoryProvider)
            .update(widget.table, row['id'].toString(), values);
      }
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Kayıt kaydedilemedi. Alanları ve SQL kurulumunu kontrol edin.',
            ),
          ),
        );
      }
    } finally {
      for (final controller in controllers.values) {
        controller.dispose();
      }
    }
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kaydı sil'),
        content: const Text('Bu kayıt silinsin mi?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref
        .read(operationsRepositoryProvider)
        .delete(widget.table, row['id'].toString());
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/admin-dashboard'),
        ),
        title: Text(widget.title),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openForm,
        icon: const Icon(Icons.add),
        label: const Text('Yeni Kayıt'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!),
              ),
            )
          : _rows.isEmpty
          ? const Center(child: Text('Henüz kayıt bulunmuyor.'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _rows.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final row = _rows[index];
                final subtitle = widget.subtitleKeys
                    .map((key) => row[key]?.toString() ?? '')
                    .where((value) => value.isNotEmpty)
                    .join(' • ');
                return Card(
                  child: ListTile(
                    title: Text(row[widget.primaryLabelKey]?.toString() ?? '-'),
                    subtitle: subtitle.isEmpty ? null : Text(subtitle),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'edit') _openForm(row);
                        if (value == 'delete') _delete(row);
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'edit', child: Text('Düzenle')),
                        PopupMenuItem(value: 'delete', child: Text('Sil')),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
