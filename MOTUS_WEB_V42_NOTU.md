# MOTUS V42 - Web/PWA ilk calisan surum

Bu surum V41 tabanlidir. Mevcut Supabase, rol, servis, stok ve Windows akislarini degistirmeden Flutter Web icin derleme engelleri ayrildi.

## Ne yapildi
- `dart:io` kaynakli web derleme engelleri temizlendi.
- `webview_windows` dogrudan importlari platform katmanina alindi.
- Windows'ta mevcut gomulu Yandex WebView davranisi korunur.
- Web'de Yandex gomulu WebView yerine mevcut `Yandex'te Ac` akisi kullanilir.
- Ayarlar ekranindaki logo/yedek dosya okuma-yazma islemleri web uyumlu byte akisina cevrildi.
- PWA manifest ve tarayici basligi MOTUS olarak duzenlendi.
- `WEB_CALISTIR.bat`: Chrome'da ayni Supabase ile test.
- `WEB_BUILD.bat`: yayin icin `build/web` uretir.

## Veri mantigi
Windows ve Web AYNI Supabase URL/key ile calisir. Bu nedenle yoneticinin Windows uygulamasindan olusturdugu sekreter/tekniker hesabi webden de ayni Auth + `profiles` kaydina girer ve ayni rol/yetkilerle ayni veriyi gorur.

## Bilerek degistirilmeyenler
- V39/V40 Yandex adres eslestirme ve Windows rota kodu.
- Servis, stok, musteri, PDF ve rol/RLS akislari.
- Google OAuth henuz acilmadi. Domain yayina alindiktan sonra gercek redirect URL ile kurulmasi daha guvenlidir.

## Calistirma
`WEB_CALISTIR.bat` dosyasina cift tikla.

Yayin buildi icin `WEB_BUILD.bat` kullan. Cikti: `build/web`.
