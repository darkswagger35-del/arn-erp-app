# MOTUS V61

Bu sürüm V60 tabanı üzerine hazırlanmıştır.

- Yönetici Ana Paneline **İptal Edilen İşler** bölümü eklendi.
  - Müşteri
  - Tekniker
  - İptal eden kişi
  - İptal tarih/saat
  - Seçili gün/hafta/ay aralığına göre listelenir.
- Yönetici panelindeki tekniker/sekreter performans bölümleri mobilde tablo yerine kart yapısına geçer; personel satırları dar ekranda kaybolmaz.
- **Ayarlar > Stok & Tahsilat** bölümüne yönetici kontrollü kredi kartı komisyon oranları eklendi.
  - Tek çekim, 2, 3, 4, 5, 6, 9 ve 12 taksit oranları yönetici tarafından girilir.
  - Değişiklikler `Ayarları Kaydet` ile firma ayarlarına kaydolur.
- Tekniker kredi kartı tahsilatında yalnız taksit seçer.
  - Kart komisyon alanı kilitlidir.
  - Oran yönetici ayarlarından otomatik gelir.
  - Brüt tahsilat, komisyon ve net tahsilat V60 finans mantığıyla kaydedilir.
- Mevcut `WEB_YAYINLA.bat` yayın akışı korunmuştur.

Not: V60 kart tahsilat migrationı daha önce çalıştırılmadıysa `SUPABASE_V60_KART_TAKSIT_KOMISYON.sql` bir kez Supabase SQL Editor'da çalıştırılmalıdır.
