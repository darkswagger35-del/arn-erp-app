# V32 - Yandex slash'li sokak düzeltmesi

- `924/1`, `1419/1`, `7467/1` gibi sayısal/slash içeren sokaklar Yandex rota URL'sine mümkün olduğunca adres metni olarak gönderilmiyor.
- Önce müşterinin kaydedilmiş MOTUS harita pini kullanılıyor; yoksa açık adres il/ilçe doğrulamasıyla geocode edilip koordinata çevriliyor.
- Bina numarası geocoder'da bulunamazsa ikinci deneme sadece `sokak + ilçe + il` ile yapılıyor.
- Yandex rota noktası koordinat olarak gönderildiği için `924/1 Sokak` -> `1 Sokak` şeklinde yanlış parçalanma engelleniyor.
- Tek müşteri `Harita` butonu da aynı koordinat çözümünü kullanıyor.
- V31'deki sekreter/arıza/0 TL değişiklikleri ve Yandex `Optimize et` sırasını uygulamaya aktarma korunmuştur.
