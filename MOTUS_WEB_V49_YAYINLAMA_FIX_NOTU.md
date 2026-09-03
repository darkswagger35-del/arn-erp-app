# MOTUS Web V49 - Yayınlama BAT düzeltmesi

- V48 içindeki PowerShell `2>&1 | Tee-Object` kaçış hatası kaldırıldı.
- Yayınlama artık doğrudan CMD üzerinden çalışıyor.
- `build/web` klasörü mevcut Vercel projesi `motus-app` ile `vercel link` kullanılarak eşleştiriliyor.
- Ardından `vercel deploy --prod --yes` ile production yayını yapılıyor.
- V48 uygulama kodu ve tekniker web/mobil düzeltmeleri korunmuştur.
