# MOTUS V55

Bu sürüm, çalışan V49 tabanı üzerine hazırlanmıştır. V50-V54'te mobil adresleri gereksiz yere kırmızı/engelli yapan katı doğrulama katmanları baz alınmamıştır.

## Yapılanlar

- Seçilen yeni MOTUS `M + damla + dalga` ikonu Web/PWA, favicon, Android, iOS, Windows ve macOS ikonlarına uygulandı.
- Uygulama görünen adı Android/iOS/Web/Windows tarafında `MOTUS` yapıldı.
- Tekniker telefon kartlarında `Sekreter Notu` doğrudan görünür hale getirildi; iş detayındaki not temizleme birden fazla planlama etiketi için düzeltildi.
- Mobilde `Adres Hatalı` durumu `İşi Aç` ve `Harita Aç` işlemlerini kilitlemiyor.
- Mobil Yandex açılışında adres, Yandex Geocoder ile yalnız o tıklamada koordinata çevriliyor; koordinat veritabanına kaydedilmiyor.
- Sokak (`Sk/Sok/Sokak`), cadde (`Cad/Cd/Cadde/Caddesi`) ve bulvar (`Blv/Bulvar`) adresleri destekleniyor.
- Kat, daire, zemin, apartman etiketi ve blok bilgisi mobil Yandex sorgusunda gürültü olarak temizleniyor; yol adı ve kapı numarası korunuyor.
- Örnek desteklenen yazımlar: `311/1 Sok. No:4`, `345 Sok. No:16`, `Yeni Sok. No:38`, `Fatih Cad. No:55`, `Cahit Sıtkı Tarancı Cad. No:5 A Blok`, `1921 Sok. No:19/A`.
- Windows'taki V39 Yandex öneri/doğrulama akışı korunmuştur.
- `Rotayı Oluştur` Windows Yandex ekranında duraklar eklendikten sonra `Optimize et` otomatik denenir. Yandex'in bitiş noktasını sabitleme sorusu çıkarsa, tüm durakların serbestçe en hızlı sıraya geçebilmesi için `Hayır, teşekkürler` seçilir.
- Yandex optimize sırası değiştiğinde MOTUS listesi aynı sıraya geçer ve `route_order` Supabase'e kaydedilir.
- Telefon tarafı Supabase'deki `route_order` ile sıralandığı için PC'de Yandex'ten alınan sıra telefonda da korunur.
- Mobilde doğrudan koordinatlı rota hazırlanamazsa iş akışı kilitlenmez; Yandex araması / web rotası yedek olarak açılır.
- Vercel Yandex Geocoder proxy'si ESM uyarısı oluşturmaması için CommonJS olarak paketlendi.

## Korunanlar

- Mevcut Supabase, rol, servis, stok, müşteri, PDF ve tekniker servis tamamlama akışları değiştirilmemiştir.
- Sabit başlangıç: `1921 Sok. No:19/A, Bayraklı, İzmir`.
- Geocoder koordinatları müşteriye yazılmaz; yalnızca Yandex uygulamasına rota hazırlamak için anlık kullanılır.

## Kontroller

- 131 Dart dosyasında parantez/string/comment yapısal taraması: geçti.
- `web/manifest.json` ve `config/dev.json` JSON doğrulaması: geçti.
- iOS `Info.plist` ve Android `AndroidManifest.xml` parse kontrolü: geçti.
- Vercel `yandex-geocode.js` Node sözdizimi ve 405/401 temel handler testleri: geçti.
- Yandex anahtarı proje dosyalarına gömülmedi; Vercel `YANDEX_GEOCODER_API_KEY` ortam değişkeninden okunuyor.
- Bu çalışma ortamında Flutter SDK bulunmadığından gerçek `flutter build web` çalıştırılamadı. `WEB_YAYINLA.bat` kullanıcının PC'sinde önce Flutter build yapar; build başarısız olursa deploy aşamasına geçmez ve log bırakır.

## Yayın

Vercel'deki `YANDEX_GEOCODER_API_KEY` ortam değişkeni kullanılmaya devam eder. `WEB_YAYINLA.bat`, build sonrası `vercel/api/yandex-geocode.js` dosyasını yayın klasörüne kopyalar ve mevcut `motus-app` projesine production deploy eder.
