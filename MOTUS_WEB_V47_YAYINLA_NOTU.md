# MOTUS Web V47

V46 baz alınmıştır. Uygulama kaynak kodu, Supabase, servis, stok, PDF, Yandex ve rol akışlarında değişiklik yapılmadı.

Sadece Vercel yayını için şu yardımcı dosyalar eklendi:
- `WEB_YAYINLA.bat`
- `WEB_YAYINLA_IC.bat`
- `WEB_YAYINLA_KISA_NOT.txt`

Akış: Flutter web release build -> Vercel oturum kontrolü -> gerekirse login -> production deploy.
Hata durumunda `WEB_YAYINLA_LOG.txt` oluşturulur ve CMD penceresi açık kalır.
