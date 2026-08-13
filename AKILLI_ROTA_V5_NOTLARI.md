# MOTUS Akilli Rota V5 - ROOT Oncelikli

Bu surumde is adedi dengelemesi rota motorundan tamamen cikarildi.

- 4-4-5 / esit is sayisi hedefi yoktur.
- Ana hedef toplam rota mesafesi ve surus suresini dusurmektir.
- Cografi kumeler MST (minimum spanning tree) tabanli olusturulur.
- Tek uzak is bir teknikeri tek basina kapatirsa, en yakin rotaya birlestirilir ve kalan buyuk cografi havuz dogal olarak bolunur.
- Son yerel optimizasyon tekli tasima + iki rota arasinda swap dener.
- Is tasima yalniz toplam rota maliyetini dusuruyorsa yapilir.
- Is yukunun 3-5-5, 6-4-3 vb. olmasi kabul edilir; ROOT daha onemlidir.
- Randevulu/saatli islerin gecikme cezasi korunur.

Beklenen ornek: Guzelbahce+Urla birlikte; Bornova+Bayrakli+Karsiyaka birlikte; Konak+Buca+Karabaglar birlikte, ancak bu sabit ilce kuralina gore degil koordinat mesafesine gore ortaya cikar.
