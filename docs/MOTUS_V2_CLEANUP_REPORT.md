# MOTUS v2.0 Temizlik Raporu

## Uygulanan güvenli temizlik

- Çalışan uygulama ağacından erişilemeyen 31 eski Dart dosyası `archive/legacy_dart/` altına taşındı.
- Eski `devices` modülü, kök dizindeki eski ekran/model/service dosyaları ve kullanılmayan çift rapor/ürün ekranları artık Flutter derlemesine dahil değil.
- `pubspec.yaml` sürümü `2.0.0+200`, açıklaması MOTUS olarak güncellendi.
- Ana uygulama sınıfı `ArnErpApp` yerine `MotusApp` oldu.
- Dashboard fallback sayımı bütün `service_requests` tablosunu istemciye çekmek yerine yalnız ilgili durumların `id` alanlarını sunucudan ister.
- Yanlışlıkla migration klasöründe kalan `.tmp` dosyası kaldırıldı.

## Bilerek dokunulmayanlar

- Canlı Supabase tabloları, fonksiyonları, triggerları ve geçmiş migrationlar otomatik silinmedi.
- Eski migration dosyaları runtime performansını etkilemez; silinmeleri Supabase migration geçmişini bozabilir.
- Canlı veritabanında DROP işlemi için önce `supabase/tools/v2_database_audit.sql` çıktısı incelenmelidir.

## Performans için sonraki güvenli adımlar

1. Dashboard ve rapor sorgularını tek, sürümlü RPC setine geçirmek.
2. Müşteri/servis listelerinde tüm ekranlarda pagination kullanmak.
3. `service_requests(company_id,status,planned_date)` ve bakım tarihleri için canlı index denetimi yapmak.
4. Büyük ekran dosyalarını küçük widgetlara bölmek; bu bakım kolaylığı sağlar, tek başına veritabanı hızını artırmaz.
