# MOTUS V62

- Servis talebi oluştururken aynı müşteriye tek servis kaydı içinde 2, 3 veya daha fazla ürün eklenebilir.
- `+ Ürün Ekle` ile yeni ürün satırı açılır; her satırda ürün, adet ve toplam fiyat bulunur.
- Genel toplam otomatik hesaplanır; tekniker servisi açtığında planlanan tüm ürünler önceden seçili gelir.
- Ana Panelde `Geciken İşler` ile `İptal Edilen İşler` geniş ekranda yan yana, mobilde alt alta gösterilir.
- İptal edilen satıra tıklanınca iptal sebebi, tekniker, sekreter, iptal eden kişi ve tarih açılır.
- İptal listesine `Sekreter` kolonu eklendi.
- Aynı müşteriye birden fazla ürün için ayrı servis talebi açma ihtiyacı kaldırıldı; ürünler tek müşteri/tek servis altında tutulur.
- WEB_YAYINLA.bat akışı korunmuştur.
- İlk yayın öncesi `SUPABASE_V62_COKLU_URUN.sql` bir kez çalıştırılmalıdır.
