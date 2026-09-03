# MOTUS V56 — Ücretsiz MOTUS Rota Optimizasyonu

Bu sürüm V55 tabanı üzerine, kullanıcı geri bildirimindeki üç kalan konu için hazırlanmıştır: rota sırasının telefonda değişmemesi, 1921 Sok. No:19/A başlangıcının native Yandex rotasına çevrilememesi ve eksik adreslerin yanlış Yandex sonucuna gidebilmesi.

## Mobil rota

- `Rotayı Oluştur` telefonda artık Yandex'in ücretli Optimize özelliğine bağlı değildir.
- MOTUS, Yandex Geocoder ile yalnız kesin bina olarak doğrulanabilen müşteri noktalarını geçici olarak alır.
- Sabit başlangıç `1921 Sok. No:19/A, Bayraklı Mahallesi, Bayraklı, İzmir` olarak doğrulanır.
- MOTUS önce en yakın komşu sırası üretir, ardından 2-opt ile gereksiz çapraz/gecikmeli geçişleri azaltır.
- Hesaplanan sıra `technician_save_route_order_v1` üzerinden `route_order` olarak kaydedilir.
- Aynı sıra Yandex Maps uygulamasına koordinat durakları halinde gönderilir. Yandex açıldıktan sonra navigasyon ve canlı trafik Yandex'te kalır.
- Saat/randevu bilgisi rota optimizasyonuna karıştırılmaz.

## Adres güvenliği

- Sokak / cadde / bulvar bilgisi bulunmayan kayıt yaklaşık konuma gönderilmez.
- `Sk`, `Sok`, `Sokak`, `Cd`, `Cad`, `Cadde`, `Caddesi`, `Blv`, `Bulvar` biçimleri desteklenir.
- Kat, daire, apartman ve blok bilgileri navigasyon eşleştirmesini bozmaz.
- Kesin bulunamayan müşteri rotadan atılır, MOTUS listesinin sonuna alınır ve kırmızı `Adres Hatalı` olarak kalır; diğer doğrulanmış müşterilerin rotası yine açılır.
- Tek müşteri `Harita Aç` işleminde de yol türü olmayan eksik adres yanlış Yandex sonucuna gönderilmez.
- Koordinatlar veritabanına kaydedilmez; sadece ekran oturumu belleğinde cache'lenir.

## MOTUS ikonu

- Onaylanan MOTUS M + damla + dalga ikonu korunmuştur.
- Web/PWA ikon dosyaları `v56` adıyla yeniden üretildi/versiyonlandı; favicon ve manifest referansları v56'ya taşındı. Bu, yeni kurulumlarda eski Flutter ikon cache'ini engeller.
- Telefonda daha önce kurulmuş MOTUS PWA eski ikonu tutuyorsa, eski MOTUS kısayolunu bir kez kaldırıp siteyi tekrar `Ana ekrana ekle / Uygulamayı yükle` ile kurmak gerekir.

## Değişmeyenler

- Sekreter notu mobil kart/iş detayında görünmeye devam eder.
- Windows V39 Yandex WebView adres önerisi/Optimize akışı değiştirilmemiştir.
- Supabase rol, servis, stok, PDF ve müşteri akışlarına dokunulmamıştır.
