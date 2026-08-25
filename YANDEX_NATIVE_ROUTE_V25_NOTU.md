# Yandex native route V25

- Baslangic noktasi artik haritaya tiklayarak secilmez.
- Uygulama Yandex Maps'in kendi `mode=routes` ekranini acar.
- Tekniker Yandex'teki **Nereden** alanina adres yazar, Yandex onerilerinden secer veya **Konumum** kullanir.
- `Rotayi Olustur` musterilerin acik adreslerini (adres + mahalle + ilce + il + Turkiye) Yandex rota ekranina yukler.
- Eski Nominatim / motus-pin koordinatlari rota noktasi olarak zorlanmaz.
- Yandex'teki `Optimize et` otomatik tiklanmaya calisilir; bulunamazsa tekniker bir kez tiklayabilir.
- Uygulama Yandex rota alanlarini ve `rtext` sirasini takip ederek soldaki is listesini ayni siraya almaya calisir ve `route_order` kaydeder.
- Yanlis adres metni tekniker tarafinda `Bilgileri Duzenle` ile duzeltilebilir.
- Yeni SQL gerektirmez; V14 route_order altyapisi varsa kalici sira kaydi kullanilir.
