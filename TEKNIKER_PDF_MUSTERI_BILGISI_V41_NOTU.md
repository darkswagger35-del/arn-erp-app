# V41 - Tekniker PDF müşteri bilgisi düzeltmesi

- Tekniker servis ekranında `service_requests` kaydı görünürken nested `customers` ilişkisi boş dönerse, mevcut `technician_customer_card_v1` güvenli RPC'si ile müşteri kartı yeniden yüklenir.
- Böylece teknikerin oluşturduğu servis PDF'sinde Müşteri, Telefon ve Adres alanlarının `-` görünmesi engellenir.
- Servis tamamlandıktan sonra `PDF Paylaş` seçildiğinde PDF oluşturulmadan hemen önce iş/müşteri bilgileri repository'den tekrar yenilenir.
- Tamamlanan işler listesinden sonradan paylaşılan PDF'ler de aynı `getJob` zenginleştirmesini kullandığı için aynı düzeltmeden yararlanır.
- Rota/Yandex, stok, sekreter akışı ve servis tamamlama mantığı değiştirilmedi.
- Yeni SQL gerektirmez; projede zaten kullanılan `technician_customer_card_v1` fonksiyonunu kullanır.
