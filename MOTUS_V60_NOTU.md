# MOTUS V60 — İptal görünümü + mobil servis talepleri + kart komisyonu

Bu paket V59 üzerine hazırlanmıştır.

## Takvim
- Üst özet kartlarına **İptal / Yapılamadı** eklendi.
- Kart seçildiğinde yalnız seçili gündeki iptal edilen ve tamamlanamayan işler listelenir.
- Geciken işler ayrı tutulmaya devam eder; iptal edilen kayıtlar gecikene sayılmaz.

## Servis Talepleri — telefon
- Servis Talepleri ekranı telefonda kart görünümüne geçer.
- Arama, servis türü, teknisyen ve tarih filtreleri küçük ekranda tam genişlik olur.
- Lokasyon dağılımı mobilde alt alta gösterilir; yatay taşma azaltıldı.
- İptal Edildi sekmesi ve iptal kartları mobilde de kullanılabilir.

## Ürün yönetimi
- Ürün ekleme müşteri kartına bağlı değildir. Yönetici **Stok & Ürünler > Ürünler > Yeni Ürün** üzerinden tek merkezden ürün kartı açar.
- Tekniker servis sırasında bu merkezi ürün listesinden seçim yapar.

## Kredi kartı / taksit / komisyon
- Tekniker ödeme yöntemi **Kredi Kartı** seçince Taksit ve Kart Komisyonu (%) alanları açılır.
- Servis tamamlanırken brüt tahsilat korunur; komisyon ve net tahsilat ayrıca kaydedilir.
- Tahsilatlar ekranında bugünkü ve aylık **Kart Net** toplamları ile toplam komisyon görünür.
- Tahsilat detayında taksit, komisyon oranı/tutarı ve net tahsilat görünür.

### Supabase
Bir kez `SUPABASE_V60_KART_TAKSIT_KOMISYON.sql` çalıştırılmalıdır.
SQL çalıştırılmadan da servis kapatma akışı bozulmaz; yalnız kart detay kolonları kaydedilmez.
