# MOTUS V64 - Performans düzeltmesi

- Müşteri kaydında her işlemde tekrar tekrar yapılan profil/şirket RPC çağrıları 10 dk oturum önbelleğine alındı.
- Müşteri kaydından sonra bütün müşteri listesini yeniden Supabase'den çekme kaldırıldı; kayıt cevabı yerelde listeye uygulanıyor.
- Sekreter panelindeki tek bir yavaş sorgunun tüm ekranı bekletme süresi 12 sn'den 3 sn'ye indirildi.
- V62/V63 çoklu ürün, iptal detayları, kart komisyonu, rota/konum ve WEB_YAYINLA.bat korunur.
- Yeni SQL gerekmez.
