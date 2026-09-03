/// MOTUS quick-login compatibility helpers.
///
/// Supabase Auth requires a password of at least 6 characters and the legacy
/// company-user backend validates usernames with a 3-character minimum.
/// The UI may still accept a 1-2 character quick code; short values are encoded
/// before they reach Supabase and decoded again for display.
String encodeQuickUsername(String raw) {
  final value = raw.trim().toLowerCase();
  if (value.length >= 3) return value;
  if (value.isEmpty) return value;
  return 'q_$value';
}

String decodeQuickUsername(String stored) {
  final value = stored.trim();
  if (value.startsWith('q_') && value.length >= 3 && value.length <= 4) {
    return value.substring(2);
  }
  return value;
}

String encodeQuickPassword(String raw) {
  if (raw.length >= 6) return raw;
  if (raw.isEmpty) return raw;
  // Compatibility encoding only. The user's effective secret is still as weak
  // as the short code they chose; managers should prefer longer passwords.
  return 'M0tus#$raw';
}
