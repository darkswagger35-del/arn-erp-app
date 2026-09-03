# MOTUS Web V44

- V43'teki `WEB_CALISTIR.bat` Windows'ta `flutter.bat` komutunu `call` kullanmadan cagiriyordu.
- Windows batch davranisi nedeniyle ilk Flutter komutu bittiginde ana script'e geri donulmuyor ve pencere kapanabiliyordu.
- V44'te tum Flutter cagirilari `call flutter ...` olarak duzeltildi.
- ZIP icinden calistirma kontrolu eklendi; `pubspec.yaml` yoksa kullaniciya once arsivi cikarmasi soylenir.
- `WEB_CALISTIR_LOG.txt` olusturulur ve Flutter surum/on kontrol bilgileri burada tutulur.
- Uygulama, Supabase, servis, stok, Yandex ve rol kodlarinda degisiklik yapilmadi. Yalnizca web baslatma/build scriptleri duzeltildi.
