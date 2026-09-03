# V40 - Bölgeler & Rota / Akıllı Plan

- V39 tekniker rota ekranındaki çalışan Yandex adres seçme mantığı Bölgeler & Rota ekranına uygulandı.
- Yandex canlı rotasında koordinat / yaklaşık nokta / başka sokak fallback kullanılmıyor; yazılı adres tek tek Yandex önerilerinden seçiliyor.
- Kat / daire bilgisi Yandex sorgusundan çıkarılıyor; 924/1, 7467/1, 2193/3 gibi slash'lı sokak numaraları aynen korunuyor.
- 1023. Sok. gibi Yandex'in noktalı gösterimleri ve kapı numarasının sokaktan önce/sonra yazılması destekleniyor.
- Bölgeler & Rota başlangıcı sabit: 1921 Sok. No:19A, Bayraklı, İzmir.
- Yandex rota sonucu süre / km bilgisi mümkün olduğunda ekrandaki alt istatistiklere aktarılıyor; sahte 0 km gösteriminin önüne geçiliyor.
- Akıllı Plan önizlemesinde müşteri tutamaçtan başka tekniker kartına sürüklenebilir ve teknikeri değiştirilebilir.
- Akıllı Plan'a "Tehir / Bu Planda Atama Dışı" bırakma alanı eklendi. Buraya bırakılan iş Planı Uygula sırasında atanmaz; mevcut tarih/servis kaydı silinmez.
- Aynı tekniker içindeki rota sırası sürükle-bırak ile değiştirilebilir.
- V39 tekniker Günlük İşler rota koduna dokunulmadı.
- Yeni SQL gerekmiyor.
