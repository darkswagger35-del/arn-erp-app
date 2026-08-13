# MOTUS Akıllı Rota V4

Bu sürümde 0 km / 0 dk üreten koordinat kopması için iki katmanlı çözüm eklendi:

1. Önce müşterinin Supabase `customers.latitude/longitude` koordinatı kullanılır.
2. Yoksa Yandex/Nominatim geocoding denenir.
3. Geocoding de sonuç vermezse rota motoru kör kalmaz; şehir+ilçenin gerçek yaklaşık merkez koordinatı kullanılır.

İlçe merkezleri sabit "rota grubu" değildir. SmartRoutePlanner tüm noktalar arasında Haversine mesafesi hesaplar. Bu nedenle Bornova/Bayraklı/Karşıyaka gibi yakın ilçeler doğal olarak yakın, Urla/Güzelbahçe batı hattı doğal olarak yakın çıkar.

Ayrıca küme başlangıç seçimi değiştirildi: merkezden başlamak yerine en uzak iki nokta başlangıç medoidleri olur, sonraki medoid en yakın mevcut tohuma en uzak noktadan seçilir. Bu, batıdaki iki işi ayrı kümelere bölüp kuzey/doğu işlerini tek merkeze yığma sorununu azaltır.

Not: İlçe merkezi fallback'i sokak seviyesinde kesin koordinat değildir. Müşteri koordinatı/geocoding bulunduğunda otomatik olarak onun yerine gerçek nokta kullanılır.
