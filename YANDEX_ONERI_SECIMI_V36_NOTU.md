# Yandex adres önerisi ile rota - V36

Bu sürümde tekniker Günlük İşler rota oluşturma akışı değiştirilmiştir.

- Müşteri adresleri artık `rtext` içinde topluca Yandex'e bırakılmaz.
- Başlangıç noktası açıldıktan sonra her müşteri adresi Yandex rota alanına tek tek yazılır.
- Yandex'in ekranda gösterdiği adres önerileri okunur.
- Sokak + kapı numarası + ilçe + il müşterinin kaydıyla eşleşen öneri seçilir.
- Örneğin `7467/1 Sok. No:1, Karşıyaka, İzmir` için `7467/1 Sok., 1 / Örnekköy Mah., Karşıyaka, İzmir` kabul edilir; `7467/1 Sok., 11A / Bayraklı` kabul edilmez.
- Tam eşleşen Yandex önerisi yoksa rota geçerli sayılmaz ve müşteri aranıp adresin düzeltilmesi istenir.
- Müşteri adreslerinde koordinat, yakın nokta, mahalle merkezi veya başka sokak fallback'i kullanılmaz.
- Yandex `Optimize et` sonrası uygulama sırasının eşitlenmesi korunmuştur.
- Sekreter/servis akışındaki önceki değişikliklere dokunulmamıştır.

Not: Windows Yandex WebView canlı testi bu çalışma ortamında yapılamadı. Kod içindeki JavaScript bloklarının sözdizimi Node ile, ZIP bütünlüğü de `unzip -t` ile kontrol edilmiştir.
