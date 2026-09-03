# MOTUS V59 — Canlı Harita + İlçe Güvenli Yandex Adresi

Bu sürüm **V58'in konum altyapısı ve V57'de çalışan tekniker rota sıralaması korunarak** hazırlanmıştır.

## 1) Tekniker Konumları artık gerçek harita ekranı

- Kart listesi ana ekran olmaktan çıkarıldı; ekranın ana bölümü interaktif harita oldu.
- Harita OpenStreetMap tabanı üzerinde çalışır ve Windows/Web/iOS/Android için aynı Flutter ekranını kullanır.
- Her tekniker haritada isimli pin olarak görünür.
- Durum renkleri:
  - Yeşil: son 3 dakika içinde konum geldi.
  - Turuncu: 3–10 dakika.
  - Gri: 10 dakikadan eski, paylaşım kapalı veya konum yok.
- Sağ panelden teknikere tıklayınca harita o teknikere yakınlaşır.
- `Bugünkü Hareket` teknikerin gün içindeki konum geçmişini harita üzerinde çizgi olarak gösterir.
- `Yandex'te Aç` ikincil işlem olarak korunmuştur.
- 30 saniyelik otomatik yenileme korunmuştur.
- V58'de çalıştırılan Supabase konum SQL'i aynen kullanılır; V59 için yeni SQL gerekmez.

## 2) Yönetici Yandex rota adresi — Menemen/Buca güvenlik düzeltmesi

Örnek hata: `İzmir > Menemen > Irmak Mah > 530 Sok No:15` kaydı, sadece `530 Sok No:15` gibi ele alındığında Buca'daki aynı sokak/kapı numarasına düşebiliyordu.

V59'da:

- Yandex'e gönderilen yönetici rota sorgusuna `mahalle + ilçe + il` birlikte eklenir.
- Yandex önerisi kabul edilirken **ilçe zorunlu eşleşmedir**.
- Öneride mahalle bilgisi görünüyorsa kayıtlı mahalleyle de uyuşması gerekir.
- Doğru ilçe içinde eşleşme bulunamazsa Yandex'in başka ilçede otomatik seçtiği nokta rota alanında bırakılmaz; adres `bulunamadı` sayılır.
- Adres varyantlarında ilçe artık son çare olarak hiçbir zaman atılmaz.

## Dokunulmayan kritik alanlar

- Teknikerin V57 mevcut-konum bazlı rota optimizasyonu.
- Yönetici rota başlangıcı 1921 Sok. No:19/A.
- Sekreter notu ve servis akışı.
- V58 Supabase konum tabloları/RLS/RPC yapısı.

## Sonraki paket

Kullanıcıyla kararlaştırılan V60 kapsamı: iptal/geciken iş ayrımı, servis formları filtre/beyaz tema/düzenleme, stokta ürün olmasa da tekniker tamamlaması, kasa ve kart/taksit/komisyon/net ciro düzenlemeleri.
