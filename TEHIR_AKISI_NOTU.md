# Tehir Akışı Kaldırıldı

- Kullanıcı arayüzünde **Tehir** adında ayrı bir servis durumu yoktur.
- `deferred` değeri veritabanında yalnızca sekretere yeniden planlama için aktarımın dahili durumu olarak kullanılabilir.
- Aktif sekreter kuyruğu `isSecretaryRework` ile gösterilir ve **Sekretere Gönderilen** olarak adlandırılır.
- Eski kaynak aktarım kayıtları veritabanında geçmiş olarak korunur (`wasSentToSecretary`) ancak Servis Talepleri operasyon listesinde ikinci kez gösterilmez.
- Yönetici için **Tehire Al** butonu kaldırılmıştır.
