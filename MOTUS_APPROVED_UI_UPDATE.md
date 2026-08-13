# MOTUS / ARN ERP — Onaylı Arayüz Güncellemesi

Bu paket, kullanıcının onayladığı son MOTUS tasarım ve çalışma kararları esas alınarak güncellenmiştir. Kaynak olarak son gönderilen ARN ERP proje ZIP'i kullanılmıştır; mevcut Supabase şeması ve ana iş akışları mümkün olduğunca korunmuştur.

## Uygulanan başlıca değişiklikler

- Yönetim ekranları açık/beyaz temaya taşındı ve `ManagementShell` açık temayı yerel olarak zorlayacak şekilde düzenlendi.
- Ana Panel günlük operasyon özeti olarak yeniden düzenlendi: müşteri, aktif servis, günlük iş, ciro ve tahsilat; tekniker/sekreter performansı; günlük iş programı; tahsilatlar ve hızlı erişim. Tarih seçimi gerçek sorgulara bağlandı.
- Müşteriler ekranında ad/soyad ve telefon aramaları ayrıldı; detay/düzenleme/servis açma akışlarında geri dönüşün liste durumunu koruması için push tabanlı gezinme kullanıldı.
- Bölgeler & Rota ekranında Yandex harita korundu; atanmış işler görünümünde seçilen tekniker gerçek filtre olarak listeye ve haritaya uygulanır.
- Ürünler ekranına toplu stok işlemleri eklendi: stok ekle, düş, belirle, sıfırla, aktif yap, arşivle.
- Depolar ekranı ana depo ve tekniker araç depoları için açılır/kapanır stok görünümüne dönüştürüldü. Düşük stok uyarı/eşik mantığı bu ekrandan kaldırıldı.
- Stok Hareketleri ürün ve tekniker bazında iki açılır bölüm olarak düzenlendi; hareketlerde tekniker ve servis müşterisi bilgileri gösterilebilecek şekilde veri modeli genişletildi.
- Tahsilatlar ekranına günlük / haftalık / aylık / yıllık / özet dönem seçimleri eklendi.
- Raporlar, Kullanıcılar, Excel, Bildirimler ve Ayarlar açık tema doğrultusunda düzenlendi.
- Mevcut servis talebi saat mantığı korunmuştur: saat zorunlu değildir; gün içi servis kaydı desteklenmeye devam eder.

## Doğrulama notu

Bu çalışma ortamında Flutter/Dart SDK bulunmadığı için `flutter analyze`, `flutter test` veya Windows/Android gerçek build komutları çalıştırılamadı. Değiştirilen Dart dosyalarında yapısal parantez/delimiter kontrolü, rota kontrolleri ve ZIP bütünlük kontrolü yapıldı. İlk yerel kontrolde Flutter SDK bulunan bilgisayarda `flutter pub get` ve `flutter analyze` çalıştırılması önerilir.

## Windows build hotfix (2026-08-14)
- `warehouse_management_screen.dart`: `_WarehouseAccordion` içindeki stok miktarı formatlayıcı çağrıları state sınıfındaki static metoda yönlendirildi.
- `dispatch_board_screen.dart`: çalışma zamanında `_listMode` kullanan `InputDecoration` üzerindeki hatalı `const` kaldırıldı.
