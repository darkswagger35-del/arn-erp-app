# MOTUS V66 - Detaylı Kasa

V65.1 üzerine hazırlanmıştır.

## Kasa ekranı
- Görsel referansa göre yenilendi: Ana Kasa, Tekniker Kasaları, Bugün Nakit Tahsilat ve Bugün Gider kartları.
- Genel Bakış / Nakit Tahsilatlar / Personel Kasaları / Giderler sekmeleri.
- Bugün / Bu Hafta / Bu Ay / tarih aralığı filtreleri.
- Gider türü, kişi ve ödeme kaynağı filtreleri.
- Aylık gider kategori özetleri.
- Detaylı gider tablosu ve Excel dışa aktarım.
- Gider detay / düzenle / sil işlemleri.
- Son kasa hareketleri: nakit tahsilat, gider ve personelden ana kasaya transfer.

## Detaylı gider formu
- Gider Türü: Yakıt, Avans, Maaş, Reklam, Kira, SSK, Yemek, Malzeme, Araç, Diğer.
- Kime / Kim İçin.
- Tutar.
- Ödeme Şekli: Ana Kasa veya Personel Kasası.
- Personel Kasası seçilirse hangi personelin kasasından çıktığı ayrıca seçilir.
- Tarih, açıklama ve fiş/fatura no.

## Kasa mantığı
- Kredi kartı tahsilatları ana kasaya EKLENMEZ.
- Nakit tahsilat, tahsilatı alan kullanıcının kasasına gider.
- Yönetici personel kasasındaki parayı Ana Kasaya Çek ile merkeze alır.
- Ana Kasa gideri ana kasadan düşer.
- Personel Kasası gideri seçilen personelin mevcut nakit kasasından düşer.

## Kurulum
1. Önce `SUPABASE_V66_DETAYLI_KASA.sql` dosyasını Supabase SQL Editor'da bir kez çalıştırın.
2. Dosyaları mevcut proje klasörünün üstüne çıkarın.
3. `WEB_YAYINLA.bat` ile yayınlayın.
