# MOTUS Web V46 - HttpClient web derleme düzeltmesi

V45 logunda görülen web derleme hatası giderildi.

Sorun:
- `dispatch_board_screen.dart` içinde `HttpClient` ve `HttpHeaders` kullanımı vardı.
- V42+ web uyumluluğu için `dart:io` kaldırılınca bu tipler Flutter Web derlemesinde tanımsız kaldı.

Düzeltme:
- `package:http/http.dart` doğrudan bağımlılık olarak eklendi (`http: ^1.6.0`).
- Yandex geocoder ve mevcut fallback HTTP çağrıları `http.get` ile platform bağımsız hale getirildi.
- `HttpClient` / `HttpHeaders` kullanımı tamamen kaldırıldı.

Dokunulmayanlar:
- Supabase bağlantısı
- Rol/yetki akışı
- Windows Yandex WebView
- V39 tekniker adres/rota mantığı
- Servis, stok, PDF ve kullanıcı akışları
