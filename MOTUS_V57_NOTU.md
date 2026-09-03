# MOTUS V57 — Tekniker Mevcut Konum Başlangıcı

Bu sürüm V56 üzerine yalnız tekniker rota başlangıcı davranışını düzeltir.

## Yönetici
- Yönetici dağıtım/rota planlama ekranı değişmedi.
- Yönetici için sabit merkez **1921 Sok. No:19/A, Bayraklı / İzmir** olarak kalır.

## Tekniker
- Web/PWA tekniker ekranında **Rotayı Oluştur** artık 1921'i aramaz.
- Butona basıldığı anda cihazın/tarayıcının güncel GPS konumu alınır.
- MOTUS müşteri koordinatlarını bu güncel konuma göre nearest-neighbor + 2-opt ile sıralar.
- Hesaplanan sıra `route_order` olarak kaydedilir ve günlük iş listesine 1-2-3... şeklinde yansır.
- Yandex Maps'e de aynı müşteri sırası gönderilir; başlangıç Yandex tarafında **mevcut konum**dur.
- **Haritayı Aç** toplu rota akışı da teknikerin mevcut konumundan başlar.
- Konum servisi/izni yoksa 1921 veya başka bir sabit noktaya geri düşülmez; kullanıcıdan konum izni istenir.

## Korunanlar
- Tek müşteri **Harita Aç** mevcut konum → müşteri akışı korunur.
- Sekreter notları korunur.
- Cadde/sokak/bulvar adres hazırlama ve yanlış konum fallback yasağı korunur.
- Native Windows V39 Yandex akışı korunur.
- MOTUS ikonları ve V56 cache-busting dosyaları değiştirilmedi.
