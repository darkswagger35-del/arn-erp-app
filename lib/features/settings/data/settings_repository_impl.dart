import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_exception.dart';
import '../domain/settings_model.dart';
import 'settings_repository.dart';

class SettingsRepositoryImpl implements SettingsRepository {
  SettingsRepositoryImpl({this.client});

  final SupabaseClient? client;

  @override
  Future<CompanySettingsModel> loadSettings() async {
    final supabase = client ?? _ensureClient();
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw const AppException('Oturum doğrulanamadı.');
    }

    final profileResponse = await supabase
        .from('profiles')
        .select('company_id')
        .eq('id', user.id)
        .maybeSingle();
    if (profileResponse == null) {
      throw const AppException('Şirket profili bulunamadı.');
    }

    final companyId = profileResponse['company_id']?.toString();
    if (companyId == null || companyId.isEmpty) {
      throw const AppException('Şirket bilgisi bulunamadı.');
    }

    final companyResponse = await supabase
        .from('companies')
        .select(
          'id, name, legal_name, phone, email, tax_number, tax_office, address, logo_url',
        )
        .eq('id', companyId)
        .maybeSingle();
    final settingsResponse = await supabase
        .from('company_settings')
        .select(
          'company_id, maintenance_reminder_months, qr_validation_required, customer_signature_required, service_photo_required, payment_required, pdf_auto_create, whatsapp_service_form_enabled, pdf_show_logo, pdf_show_seal, pdf_show_signature, whatsapp_notifications_enabled, sms_notifications_enabled, email_notifications_enabled',
        )
        .eq('company_id', companyId)
        .maybeSingle();

    final logoUrl = await _freshLogoUrl(
      supabase,
      companyResponse?['logo_url']?.toString(),
    );

    return CompanySettingsModel(
      companyId: companyId,
      companyName: companyResponse?['name']?.toString() ?? '',
      authorizedName: companyResponse?['legal_name']?.toString(),
      phone: companyResponse?['phone']?.toString(),
      email: companyResponse?['email']?.toString(),
      taxOffice: companyResponse?['tax_office']?.toString(),
      taxNumber: companyResponse?['tax_number']?.toString(),
      address: companyResponse?['address']?.toString(),
      logoUrl: logoUrl,
      maintenanceReminderMonths:
          int.tryParse(
            settingsResponse?['maintenance_reminder_months']?.toString() ?? '',
          ) ??
          6,
      qrValidationRequired:
          settingsResponse?['qr_validation_required'] as bool? ?? false,
      customerSignatureRequired:
          settingsResponse?['customer_signature_required'] as bool? ?? false,
      servicePhotoRequired:
          settingsResponse?['service_photo_required'] as bool? ?? false,
      paymentRequired: settingsResponse?['payment_required'] as bool? ?? false,
      pdfAutoCreate: settingsResponse?['pdf_auto_create'] as bool? ?? false,
      whatsappServiceFormEnabled:
          settingsResponse?['whatsapp_service_form_enabled'] as bool? ?? false,
      pdfShowLogo: settingsResponse?['pdf_show_logo'] as bool? ?? true,
      pdfShowSeal: settingsResponse?['pdf_show_seal'] as bool? ?? true,
      pdfShowSignature:
          settingsResponse?['pdf_show_signature'] as bool? ?? true,
      whatsappNotificationsEnabled:
          settingsResponse?['whatsapp_notifications_enabled'] as bool? ?? true,
      smsNotificationsEnabled:
          settingsResponse?['sms_notifications_enabled'] as bool? ?? false,
      emailNotificationsEnabled:
          settingsResponse?['email_notifications_enabled'] as bool? ?? true,
    );
  }

  @override
  Future<void> saveSettings(CompanySettingsModel settings) async {
    final supabase = client ?? _ensureClient();
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw const AppException('Oturum doğrulanamadı.');
    }

    final profileResponse = await supabase
        .from('profiles')
        .select('company_id')
        .eq('id', user.id)
        .maybeSingle();
    if (profileResponse == null) {
      throw const AppException('Şirket profili bulunamadı.');
    }

    final companyId = profileResponse['company_id']?.toString();
    if (companyId == null || companyId.isEmpty) {
      throw const AppException('Şirket bilgisi bulunamadı.');
    }

    await supabase
        .from('companies')
        .update({
          'name': settings.companyName,
          'legal_name': settings.authorizedName,
          'phone': settings.phone,
          'email': settings.email,
          'tax_office': settings.taxOffice,
          'tax_number': settings.taxNumber,
          'address': settings.address,
        })
        .eq('id', companyId);

    final settingsPayload = {
      'company_id': companyId,
      'maintenance_reminder_months': settings.maintenanceReminderMonths,
      'qr_validation_required': settings.qrValidationRequired,
      'customer_signature_required': settings.customerSignatureRequired,
      'service_photo_required': settings.servicePhotoRequired,
      'payment_required': settings.paymentRequired,
      'pdf_auto_create': settings.pdfAutoCreate,
      'whatsapp_service_form_enabled': settings.whatsappServiceFormEnabled,
      'pdf_show_logo': settings.pdfShowLogo,
      'pdf_show_seal': settings.pdfShowSeal,
      'pdf_show_signature': settings.pdfShowSignature,
      'whatsapp_notifications_enabled': settings.whatsappNotificationsEnabled,
      'sms_notifications_enabled': settings.smsNotificationsEnabled,
      'email_notifications_enabled': settings.emailNotificationsEnabled,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    await supabase
        .from('company_settings')
        .upsert(settingsPayload, onConflict: 'company_id');
  }

  @override
  Future<void> deleteLogo() async {
    final supabase = client ?? _ensureClient();
    final user = supabase.auth.currentUser;
    if (user == null) throw const AppException('Oturum doğrulanamadı.');
    final profile = await supabase.from('profiles').select('company_id, role').eq('id', user.id).maybeSingle();
    if (profile == null) throw const AppException('Şirket profili bulunamadı.');
    final role = profile['role']?.toString();
    if (role != 'manager' && role != 'admin') throw const AppException('Bu işlem için yetkiniz yok.');
    final companyId = profile['company_id']?.toString();
    if (companyId == null || companyId.isEmpty) throw const AppException('Şirket bilgisi bulunamadı.');
    final company = await supabase.from('companies').select('logo_url').eq('id', companyId).maybeSingle();
    final url = company?['logo_url']?.toString();
    await supabase.from('companies').update({'logo_url': null}).eq('id', companyId);
    if (url != null && url.isNotEmpty) {
      final path = _storedLogoPath(url);
      if (path != null) {
        final cleanPath = path.startsWith('company-logos/') ? path.substring('company-logos/'.length) : path;
        try { await supabase.storage.from('company-logos').remove([cleanPath]); } catch (_) {}
      }
    }
  }

  @override
  Future<String> uploadLogo({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final supabase = client ?? _ensureClient();
    final user = supabase.auth.currentUser;
    if (user == null) {
      throw const AppException('Oturum doğrulanamadı.');
    }

    if (bytes.lengthInBytes > 2 * 1024 * 1024) {
      throw const AppException('Logo dosyası 2 MB\'dan büyük olamaz.');
    }

    final lowerName = fileName.toLowerCase();
    if (!lowerName.endsWith('.png') &&
        !lowerName.endsWith('.jpg') &&
        !lowerName.endsWith('.jpeg')) {
      throw const AppException(
        'Geçersiz logo türü. Yalnızca PNG, JPG veya JPEG dosyaları yüklenebilir.',
      );
    }

    final profileResponse = await supabase
        .from('profiles')
        .select('company_id, role')
        .eq('id', user.id)
        .maybeSingle();
    if (profileResponse == null) {
      throw const AppException('Şirket profili bulunamadı.');
    }

    final role = profileResponse['role']?.toString();
    if (role != 'manager' && role != 'admin') {
      throw const AppException(
        'Yalnızca manager ve admin kullanıcılar logo yükleyebilir.',
      );
    }

    final companyId = profileResponse['company_id']?.toString();
    if (companyId == null || companyId.isEmpty) {
      throw const AppException('Şirket bilgisi bulunamadı.');
    }

    final safeExtension = _safeExtension(fileName);
    final path = '$companyId/logo.$safeExtension';
    final storage = supabase.storage.from('company-logos');

    try {
      await storage.uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(
          contentType: _contentType(fileName),
          upsert: true,
        ),
      );
    } on StorageException catch (error) {
      throw AppException(_translateStorageError(error.message));
    } catch (_) {
      throw const AppException(
        'Logo yüklenirken bir sorun oluştu. Lütfen tekrar deneyin.',
      );
    }

    try {
      final currentCompany = await supabase
          .from('companies')
          .select('logo_url')
          .eq('id', companyId)
          .maybeSingle();
      final previousLogoUrl = currentCompany?['logo_url']?.toString();
      final previousPath = previousLogoUrl == null || previousLogoUrl.isEmpty
          ? null
          : _storedLogoPath(previousLogoUrl);
      final signedUrl = await storage.createSignedUrl(path, 60 * 60);

      await supabase
          .from('companies')
          .update({'logo_url': 'company-logos/$path'})
          .eq('id', companyId);

      final cleanPreviousPath = previousPath == null
          ? null
          : previousPath.startsWith('company-logos/')
              ? previousPath.substring('company-logos/'.length)
              : previousPath;
      if (cleanPreviousPath != null &&
          cleanPreviousPath.isNotEmpty &&
          cleanPreviousPath != path) {
        try {
          await storage.remove([cleanPreviousPath]);
        } on StorageException catch (_) {
          return signedUrl;
        }
      }

      return signedUrl;
    } on AppException {
      rethrow;
    } on StorageException catch (error) {
      await storage.remove([path]);
      throw AppException(_translateStorageError(error.message));
    } catch (_) {
      await storage.remove([path]);
      throw const AppException('Logo kaydı güncellenemedi.');
    }
  }

  SupabaseClient _ensureClient() {
    try {
      return Supabase.instance.client;
    } catch (_) {
      throw const AppException('Bağlantı kurulamadı. Lütfen tekrar deneyin.');
    }
  }

  String _contentType(String fileName) {
    final lowerName = fileName.toLowerCase();
    if (lowerName.endsWith('.png')) {
      return 'image/png';
    }
    if (lowerName.endsWith('.jpg') || lowerName.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    return 'application/octet-stream';
  }

  String _safeExtension(String fileName) {
    final lowerName = fileName.toLowerCase();
    if (lowerName.endsWith('.png')) {
      return 'png';
    }
    if (lowerName.endsWith('.jpg') || lowerName.endsWith('.jpeg')) {
      return 'jpg';
    }
    return 'bin';
  }

  Future<String?> _freshLogoUrl(
    SupabaseClient supabase,
    String? stored,
  ) async {
    final value = stored?.trim() ?? '';
    if (value.isEmpty) return null;
    final path = _storedLogoPath(value);
    if (path == null || path.isEmpty) return value;
    final cleanPath = path.startsWith('company-logos/')
        ? path.substring('company-logos/'.length)
        : path;
    try {
      return await supabase.storage
          .from('company-logos')
          .createSignedUrl(cleanPath, 60 * 60);
    } catch (_) {
      return value.startsWith('http') ? value : null;
    }
  }

  String? _storedLogoPath(String url) {
    final trimmed = url.trim();
    if (trimmed.startsWith('company-logos/')) return trimmed;
    try {
      final uri = Uri.parse(url);
      final pathSegments = uri.pathSegments;
      final objectIndex = pathSegments.indexOf('object');
      if (objectIndex >= 0 && pathSegments.length > objectIndex + 2) {
        final afterObject = pathSegments.sublist(objectIndex + 1);
        final resourceIndex = afterObject.indexOf('public');
        final signedIndex = afterObject.indexOf('sign');
        final bucketIndex = resourceIndex >= 0
            ? resourceIndex + 1
            : signedIndex >= 0
            ? signedIndex + 1
            : 0;
        if (bucketIndex < afterObject.length) {
          final bucket = afterObject[bucketIndex];
          final pathParts = afterObject.sublist(bucketIndex + 1);
          if (pathParts.isNotEmpty) {
            return '$bucket/${pathParts.join('/')}';
          }
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  String _translateStorageError(String? message) {
    final normalized = message?.toLowerCase() ?? '';
    if (normalized.contains('permission') || normalized.contains('policy')) {
      return 'Bu işlem için yetkiniz yok.';
    }
    if (normalized.contains('size')) {
      return 'Logo dosyası boyutu desteklenmiyor.';
    }
    if (normalized.contains('mime') || normalized.contains('type')) {
      return 'Geçersiz logo türü.';
    }
    return 'Depolama hizmeti şu anda erişilemez.';
  }
}
