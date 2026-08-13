class AppEnvironment {
  const AppEnvironment({
    required this.supabaseUrl,
    required this.supabasePublishableKey,
    required this.isConfigured,
    required this.message,
  });

  final String supabaseUrl;
  final String supabasePublishableKey;
  final bool isConfigured;
  final String message;

  factory AppEnvironment.fromEnvironment() {
    const supabaseUrl = String.fromEnvironment(
      'SUPABASE_URL',
      defaultValue: '',
    );
    const supabasePublishableKey = String.fromEnvironment(
      'SUPABASE_PUBLISHABLE_KEY',
      defaultValue: '',
    );
    const legacySupabaseAnonKey = String.fromEnvironment(
      'SUPABASE_ANON_KEY',
      defaultValue: '',
    );

    final effectivePublishableKey = supabasePublishableKey.isNotEmpty
        ? supabasePublishableKey
        : legacySupabaseAnonKey;

    final isConfigured =
        supabaseUrl.isNotEmpty && effectivePublishableKey.isNotEmpty;

    return AppEnvironment(
      supabaseUrl: supabaseUrl,
      supabasePublishableKey: effectivePublishableKey,
      isConfigured: isConfigured,
      message: isConfigured
          ? 'Supabase yapılandırıldı.'
          : 'Geliştirme modu: Supabase bağlantısı henüz yapılandırılmadı.',
    );
  }
}
