# MOTUS V48 — Tekniker Web / Mobil Düzeltmeleri

- V47 baz alınmıştır.
- Telefon/web Günlük İşler kartına **Harita Aç**, **Müşteri**, **Düzenle** eklendi.
- Dar ekranda müşteri kartına dokunmak artık doğrudan Müşteri Kartını açar.
- Tek müşteri **Harita Aç** işlemi Yandex arama yerine mevcut konum -> müşteri adresi rota ekranını açar.
- Web/telefon **Rotayı Oluştur** ve üst **Haritayı Aç** işlemleri sabit `1921 Sok. No:19/A, Bayraklı, İzmir, Türkiye` başlangıcı + ekrandaki sıralı müşteri adreslerini Yandex `rtext` rotasına gönderir.
- Kat/daire temizliği ve V39 adres normalizasyonu aynen kullanılır.
- Windows masaüstündeki gömülü Yandex / öneri seçme / adres doğrulama / optimize sırası koduna dokunulmamıştır.
- `WEB_YAYINLA_IC.bat` mevcut Vercel projesi `motus-app` adına yayın yapacak şekilde güncellendi.
