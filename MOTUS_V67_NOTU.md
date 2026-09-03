# MOTUS V67

## Kasa / Gider Özeti
- Giderler ekranında seçili tarih + kişi + ödeme kaynağına göre dinamik **Toplam Gider Özeti** eklendi.
- Bir personel seçildiğinde Avans, Yakıt, Yemek, Araç, Malzeme, Maaş, Reklam, Kira, SSK ve Diğer toplamları aynı anda görünür.
- Sağ üstte **GENEL TOPLAM** görünür.
- Kategori filtresi yalnız alt tabloyu daraltır; personel özeti tüm gider türlerini göstermeye devam eder.
- `Tümü` seçiliyse aynı alan şirket geneli gider özetine dönüşür.
- Bugün / Bu Hafta / Bu Ay / Tarih Aralığı filtreleri özete uygulanır.

## 28.08.2026 Cuma İş Listesi
- `SUPABASE_V67_CUMA_IS_LISTESI_28_08_2026.sql` dosyası 33 Excel satırını 28.08.2026 günlük işlerine aktarır.
- Exceldeki **Sekreter** sütunu aktif secretary profiline, **Tekniker** sütunu aktif technician profiline bağlanır.
- Müşteri telefonla bulunursa güncellenir; yoksa oluşturulur.
- İşler doğrudan ilgili teknikere `assigned` durumuyla atanır.
- SQL yeniden çalıştırılırsa aynı müşteri/tekniker/tarih/ürün/fiyat eşleşmesini ikinci kez oluşturmaz.
