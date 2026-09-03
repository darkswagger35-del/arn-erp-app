# MOTUS V65

- Admin/manager müşteri listesinde müşteriyi pasife alma, tekrar aktifleştirme ve kalıcı silme eklendi.
- Kullanıcılar ekranı tek Supabase sorgusuna indirildi; 5 saniye timeout ile sonsuz spinner engellendi.
- Giriş auth context önbelleğe alındı; aynı profil/şirket bilgisi art arda tekrar çekilmiyor.
- Hızlı giriş: kullanıcı adı 1 karakterden başlayabilir. 1-2 karakterlik kodlar arka planda mevcut backend ile uyumlu kodlanır.
- Hızlı şifre: kullanıcı arayüzünde 1 karakterden başlayan şifre kullanılabilir; Supabase Auth'ın 6 karakter alt sınırına arka planda uyumlu şekilde kodlanır.
- Finans & Raporlar > Kasa eklendi.
- Yalnız NAKİT tahsilatlar kasaya girer; kredi kartı kasaya eklenmez.
- Nakit tahsilat hangi müşteriden, hangi personel tarafından alındı görülebilir.
- Yönetici personel kasasındaki parayı Ana Kasa'ya çekebilir.
- Ana Kasa gider tablosu ve Gider Ekle akışı eklendi.
- Tekniker menüsüne Kasam eklendi; tekniker kendi aldığı nakitleri ve eldeki bakiyeyi görür.

## Kurulum
Önce `SUPABASE_V65_KASA.sql` Supabase SQL Editor'da bir kez çalıştırılmalı.
Ardından normal `WEB_YAYINLA.bat` ile web yayını yapılmalı.
