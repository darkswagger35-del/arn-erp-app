# MOTUS V58 — Tekniker Mesai Konum Takibi

Bu sürüm V57 üzerine konum takip altyapısını ekler. Rota başlangıç ayrımı değişmedi:

- **Yönetici rota dağıtımı:** 1921 Sok. No:19/A sabit merkez olarak kalır.
- **Tekniker Rotayı Oluştur:** teknikerin o anki gerçek GPS konumundan başlar.

## V58'de eklenenler

### Tekniker
- Tekniker rota için konum izni verdiğinde MOTUS konum paylaşımını da başlatır.
- Tekniker ana panelinde görünür **Konum Takibi / Konum Açık** düğmesi vardır.
- Web/PWA açıkken yaklaşık **40 metre hareket** veya **2 dakikalık heartbeat** ile son konum Supabase'e gönderilir.
- Çıkış yapıldığında konum akışı durur.
- Tekniker isterse **Konum Açık** düğmesinden paylaşımı kapatabilir.
- Web/PWA işletim sistemi tarafından arka plana alınırsa sürekli takip garanti değildir. Bu, daha sonra hazırlanacak native iOS uygulamasında arka plan konum servisiyle tamamlanacaktır.

### Yönetici
- Sol menüde **Servis Yönetimi > Tekniker Konumları** ekranı eklendi.
- Ana yönetici paneline **Tekniker Konumları** hızlı erişim düğmesi eklendi.
- Ekran 30 saniyede bir yenilenir.
- Son 5 dakikada sinyal gönderen tekniker **Canlı** görünür.
- Son koordinat, GPS doğruluğu ve son sinyal zamanı gösterilir.
- **Yandex'te Aç** ile teknikerin son noktası haritada açılır.
- **Bugünkü Geçmiş** ile gün içindeki konum kayıtları saat saat görülebilir.

## Supabase kurulumu — bir kez yapılır

V58 yayınlanmadan/denenmeden önce veya sonra aşağıdaki dosyanın içeriğini Supabase SQL Editor'da **bir kez** çalıştırın:

`SUPABASE_V58_TEKNIKER_KONUM_TAKIBI.sql`

Bu SQL:
- `technician_current_locations` son konum tablosunu,
- `technician_location_history` geçmiş tablosunu,
- teknikerin yalnız kendi konumunu yazabildiği güvenli RPC'yi,
- yalnız aynı şirketteki admin/yöneticinin okuyabildiği RLS kurallarını oluşturur.

Geçmiş verisi için 30 günlük temizlik yardımcı RPC'si de eklenmiştir.

## Veri ilkesi
- Konum, yalnız tekniker hesabından gönderilebilir.
- Tekniker başka kullanıcının konumunu yazamaz.
- Yönetici/admin yalnız kendi şirketinin tekniker konumunu görebilir.
- Rota müşteri koordinat mantığı ve V57 sıralama sistemi değiştirilmemiştir.
