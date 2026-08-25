# Yandex adres güvenlik düzeltmesi V33

- 7467/1, 924/1 gibi slash'li sokaklar için tam adres -> sokak -> ana sokak kademeli çözümleme eklendi.
- Nominatim araması müşterinin kayıtlı ili içinde `bounded` viewbox ile sınırlandı.
- Nominatim il doğrulaması mümkün olduğunda Türkiye il ISO koduyla yapılıyor (örn. İzmir TR-35).
- İzmir kayıtlı bir müşterinin Aydın/Manisa vb. koordinata düşmesi engellendi.
- Adres hiçbir şekilde çözülemezse yanlış ile göndermek yerine doğru ilçe merkezi güvenli fallback olarak kullanılıyor.
- Sağ müşteri detayına `Konumu Düzelt` eklendi; bir kez gerçek bina pini seçilirse sonraki rotalarda o pin öncelikli kullanılır.
- Yandex Optimize et -> uygulama sıra senkronizasyonu korunmuştur; slash sokak ana-sokak fallback'i için eşleştirme toleransı eklendi.
- Sekreter servis akışındaki V30 değişiklikleri korunmuştur.
