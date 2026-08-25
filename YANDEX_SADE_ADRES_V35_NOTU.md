# Yandex sade adres akisi - V35

- Musteri rotasinda koordinat kullanimi kaldirildi.
- Ilce merkezi, yakin sokak, OSM/Nominatim, kayitli eski pin veya baska sokaga otomatik fallback yok.
- Yandex'e musterinin acik adresi + ilce + il metin olarak gonderilir; sadece kat/daire bilgisi rota metninden cikarilir.
- Yandex rota alanlari cozuldukten sonra sokak ve varsa kapi numarasi kayitla birebir kontrol edilir.
- Yandex farkli sokak/numara bulursa rota gecersiz sayilir; is "Adres Hatali" olarak isaretlenir.
- Hatali adreste teknikerin Ara ve Bilgileri Duzenle islemleri acik kalir; Harita/Geliyorum/Ise Basla kapatilir.
- Konumu Duzelt butonu kaldirildi.
- Yandex Optimize et -> uygulamadaki sira esitleme korunur, ancak sadece dogrulanmis rota icin calisir.
- Saat/randevu mantigina dokunulmadi.
