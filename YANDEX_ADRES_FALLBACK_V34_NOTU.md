# V34 - Yanlış sokak fallback düzeltmesi

- 7467/1 gibi bir adres geocoder tarafından çözülemezse artık Karşıyaka ilçe merkezine veya 7467 ana sokağına otomatik düşürülmez.
- V33'te görülen `1731 Sok.` bunun sonucuydu: iki çözülemeyen adres aynı Karşıyaka merkez koordinatına düşüyor, Yandex de o koordinatı en yakın yol adı olan 1731 Sok. olarak gösteriyordu.
- Yeni davranış: önce tam adres ve sokak denenir; güvenilir koordinat bulunamazsa koordinat uydurulmaz, Yandex'e tam adres metni gönderilir.
- Slash'li adres biçimi Yandex'in kendi aramasında görülen forma yaklaştırıldı: `7467/1 Sok. No:1, Karşıyaka, İzmir, Türkiye`.
- Kaydedilmiş gerçek MOTUS pini varsa her zaman önceliklidir.
- Yandex Optimize et -> uygulama sıra senkronu korunur.
