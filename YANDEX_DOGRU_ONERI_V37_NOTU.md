# Yandex doğru öneri eşleşmesi V37

- V36'da Yandex doğru adresi önerse bile kapı numarası başta gösterildiğinde (`13, 924/1 Sok.`) uygulama bunu reddediyordu.
- Eşleştirme artık Yandex'in iki gösterimini de kabul eder: `924/1 Sok., 13` ve `13, 924/1 Sok.`.
- Slash'li sokak numarası korunur; `7467/1` ile `7467` veya başka sokak eşleşmez.
- Kapı numarası da zorunlu eşleşir; örneğin `7467/1 No:1`, `7467/1 No:11A` sonucu ile eşleşmez.
- `542 Sok. No:44` gibi slash'siz numaralı sokaklarda baştaki `44` artık sokağın parçası sanılmaz.
- Koordinat, mahalle merkezi veya başka sokak fallback'i eklenmedi.
- Yandex Optimize et -> uygulama rota sırası senkronuna dokunulmadı.
