# MOTUS Clean Paket

Bu paket, çalışma koduna dokunmadan proje kökündeki geliştirme artıklarını temizlemek için hazırlanmıştır.

Kaldırılanlar:
- `archive/` altındaki eski/legacy Dart kopyaları
- Android JVM crash logu (`hs_err_pid*.log`)
- Android `.kotlin/` yerel hata cache'i
- `.flutter-plugins-dependencies` (Flutter tarafından yeniden üretilir)
- `.vscode/` yerel editör ayarları
- Proje kökündeki eski FIX/OKU/revizyon `.txt` ve `.md` notları (README hariç)
- Proje kökündeki tek seferlik `.sql` yardımcı dosyaları; gerçek migration geçmişi `supabase/migrations/` altında korunmuştur

Korunanlar:
- `lib/`, `assets/`, `config/`
- `supabase/migrations`, `supabase/functions`, seed/tools
- Android/iOS/Windows/macOS/Linux/Web platform dosyaları
- `pubspec.yaml`, `pubspec.lock`, proje yapılandırmaları
- Windows WebView yardımcı `.bat` dosyaları

Not: `build/`, `.dart_tool/`, `node_modules/` gibi klasörler zaten kaynak pakette bulunmamalı ve `.gitignore` ile dışarıda tutulmalıdır.
