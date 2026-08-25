# Yandex rota doğrulama V38

- V37'de Yandex'in tam eşleşen adres önerisi seçildikten sonra rota oluşsa bile, bazı duraklarda rota input'u ham sorgu metnini göstermeye devam ediyordu.
- Bu nedenle doğru adres yanlışlıkla `Adres Hatalı` olarak işaretlenebiliyordu.
- V38'de adres yalnızca Yandex önerileri arasından sokak + kapı no + ilçe + il tam eşleşmesi bulunduğunda kabul edilir.
- Tam eşleşen Yandex önerisine başarılı tıklama sonrasında input metninin ikinci kez aynı formatta dönmesi zorunlu değildir.
- Koordinat, ilçe merkezi, başka sokak fallback'i veya tahmin eklenmemiştir.
- Optimize et ve rota sıra senkronizasyonuna dokunulmamıştır.
