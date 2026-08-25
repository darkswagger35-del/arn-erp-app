# V29 - Tekniker Tamamlanan İşler ve PDF düzeltmesi

- Tekniker Günlük İşler ekranında tamamlanan kayıtlarda müşteri adı tekrar gösterilir.
- Tamamlanan kartta yapılan işlem, tahsil edilen tutar ve toplam tutar gösterilir.
- Tekniker RLS nedeniyle nested müşteri bilgisi boş gelirse `technician_customer_card_v1` ile güvenli fallback kullanılır.
- Tamamlanan iş detayında çoklu tahsilatlar toplanır.
- Tekniker servis PDF'inde Müşteri Bilgileri ve Servis Bilgileri belirgin bölümler olarak yazılır.
- PDF'de müşteri adı, telefon, açık adres, planlanan/tamamlanan tarih, yapılan işlem, tahsil edilen ve kalan tutar bulunur.
- Yeni SQL gerektirmez; daha önce V13 müşteri kartı SQL'i uygulanmış olmalıdır.
