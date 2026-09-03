-- MOTUS V67 - Cuma İş Listesi -> 28.08.2026 Günlük İşlere Aktarım
-- Kaynak: Cuma İş Listesi.xlsx
-- Amaç: Müşterileri oluştur/güncelle, Sekreter sütununu sekretere,
-- Tekniker sütununu teknikere bağla ve bütün satırları 28.08.2026 iş listesine ata.
-- Bu dosya SQL Editor'da yönetici olarak bir kez çalıştırılmak içindir.

begin;

do $$
declare
  v_company uuid;
begin
  select id into v_company from public.companies order by created_at nulls last limit 1;
  if v_company is null then
    raise exception 'Şirket kaydı bulunamadı.';
  end if;
end $$;

create temporary table motus_cuma_import (
  source_row integer,
  full_name text,
  phone text,
  address text,
  district text,
  product_name text,
  price numeric,
  service_type text,
  note text,
  secretary_name text,
  technician_name text
) on commit drop;

insert into motus_cuma_import values
(2, $motus$Oğuz Yılmaz$motus$, $motus$5557420546$motus$, $motus$75. yıl mah. Görken sit. I Blok D:9$motus$, $motus$Bayraklı$motus$, $motus$tam takım$motus$, 1450.00, $motus$maintenance$motus$, $motus$18'den sonra bekler gitmeden ara 6. filtresi de olabilr$motus$, $motus$Sultan Özdaş$motus$, $motus$Ali Sevinç$motus$),
(3, $motus$Selda Karlıdağ$motus$, $motus$5527173793$motus$, $motus$249/2 sok. No:1/1 D:14 K:6 Seçkinler sit. Monalya Aprt.$motus$, $motus$Bayraklı$motus$, $motus$tam takım$motus$, 1450.00, $motus$maintenance$motus$, $motus$18'den sonra bekler gitmeden ara$motus$, $motus$Sultan Özdaş$motus$, $motus$Ali Sevinç$motus$),
(4, $motus$Murat Tunga$motus$, $motus$5421591743$motus$, $motus$Emek Mah. 7297 sok. No:15c K:3$motus$, $motus$Bayraklı$motus$, $motus$musluk Arıza$motus$, 0.00, $motus$maintenance$motus$, $motus$15 Ağustosta kuruldu cihazımız musluk sallanıyor der | Excel fiyat notu: servis$motus$, $motus$Sultan Özdaş$motus$, $motus$Ali Sevinç$motus$),
(5, $motus$amine solmaz$motus$, $motus$5063630857$motus$, $motus$nafiz gürman mah 7098 sok no.166 d.2 bayraklı$motus$, $motus$Bayraklı$motus$, $motus$tam takım$motus$, 1490.00, $motus$maintenance$motus$, $motus$$motus$, $motus$Melike İşler$motus$, $motus$Ali Sevinç$motus$),
(6, $motus$Mahmut Gürgen$motus$, $motus$5052521200$motus$, $motus$Nergiz mah. Girne Bulvarı No:135 K:4 D:17$motus$, $motus$Karşıyaka$motus$, $motus$tam takım$motus$, 1250.00, $motus$maintenance$motus$, $motus$12 kadar bekler gitmeden ara  Açık kasa cihaz$motus$, $motus$Sultan Özdaş$motus$, $motus$Ali Sevinç$motus$),
(7, $motus$Gürkan Gürgen$motus$, $motus$5542754343$motus$, $motus$İnönü mah. 6660 sok. Soyak sit. 1. Etap B1 Blok D:14 Mavi şehir$motus$, $motus$Karşıyaka$motus$, $motus$tam takım$motus$, 1250.00, $motus$maintenance$motus$, $motus$Gitmeden ara daha öncede bakımını biz yaptık Annesine cihaz bağladık$motus$, $motus$Sultan Özdaş$motus$, $motus$Ali Sevinç$motus$),
(8, $motus$Gamze Güner$motus$, $motus$5412356557$motus$, $motus$29 Ekim mah. 7314/1 sok. No:2 Pırlanta evleri A blok K:3 D:11 egekent$motus$, $motus$Menemen$motus$, $motus$tam takım$motus$, 1450.00, $motus$maintenance$motus$, $motus$6. filtresi yeni değişti der gitmeden ara$motus$, $motus$Sultan Özdaş$motus$, $motus$Ali Sevinç$motus$),
(9, $motus$Mustafa Polat$motus$, $motus$5465468027$motus$, $motus$Gazi mah. 7733 sok. No:7/3 K:6 D:12$motus$, $motus$Menemen$motus$, $motus$tam takım$motus$, 1450.00, $motus$maintenance$motus$, $motus$Gitmeden ara$motus$, $motus$Sultan Özdaş$motus$, $motus$Ali Sevinç$motus$),
(10, $motus$Ali Baykara$motus$, $motus$5386905942$motus$, $motus$4122 Sok. No:1 Gazi Mustafa Kemal mah. Seyrek$motus$, $motus$Menemen$motus$, $motus$tam takım$motus$, 1450.00, $motus$maintenance$motus$, $motus$Gitmeden ara cumadan sonra İster$motus$, $motus$Sultan Özdaş$motus$, $motus$Ali Sevinç$motus$),
(11, $motus$İlhan Kaya$motus$, $motus$5554347353$motus$, $motus$Teleferik mah. Ceren sok. No:1 D:3$motus$, $motus$Balçova$motus$, $motus$tam takım$motus$, 1250.00, $motus$maintenance$motus$, $motus$Açık kasa gitmeden ara$motus$, $motus$Sultan Özdaş$motus$, $motus$Barış Can Gökçek$motus$),
(12, $motus$İlhan Kaya$motus$, $motus$5554347353$motus$, $motus$Teleferik mah. Ceren sok. No:1 D:3$motus$, $motus$Balçova$motus$, $motus$tam takım$motus$, 1250.00, $motus$maintenance$motus$, $motus$Açık kasa gitmeden ara kız kardeşinin$motus$, $motus$Sultan Özdaş$motus$, $motus$Barış Can Gökçek$motus$),
(13, $motus$İbrahim Kösekli$motus$, $motus$5555913388$motus$, $motus$Fevzi Çakmak mah. No:30 İğde sok. D:8$motus$, $motus$Balçova$motus$, $motus$tam takım$motus$, 1100.00, $motus$maintenance$motus$, $motus$Gitmeden ara$motus$, $motus$Sultan Özdaş$motus$, $motus$Barış Can Gökçek$motus$),
(14, $motus$mehmet gültemur$motus$, $motus$5373185058$motus$, $motus$gazi mah 28/3 no.20 gaziemir$motus$, $motus$Gaziemir$motus$, $motus$tam takım$motus$, 1490.00, $motus$maintenance$motus$, $motus$17.30 dan sonra bekliyor water home diye firma belirtilsin$motus$, $motus$Melike İşler$motus$, $motus$Barış Can Gökçek$motus$),
(15, $motus$Serkan karabağ$motus$, $motus$5364582225$motus$, $motus$4830 sok. No:33 D:1 Gün Altay mah.$motus$, $motus$Karabağlar$motus$, $motus$tam takım$motus$, 1100.00, $motus$maintenance$motus$, $motus$Gitmeden ara$motus$, $motus$Sultan Özdaş$motus$, $motus$Barış Can Gökçek$motus$),
(16, $motus$Kübra Demirbaş$motus$, $motus$5078653680$motus$, $motus$Yurtoğlu mah. 3947/7 sok. No:20 K:3 D:8 Haberleşme sit.$motus$, $motus$Karabağlar$motus$, $motus$tam takım$motus$, 1500.00, $motus$maintenance$motus$, $motus$Gitmeden ara ismail beyin Arkadaşının annesi(Aguaminanın sahibi)$motus$, $motus$Sultan Özdaş$motus$, $motus$Barış Can Gökçek$motus$),
(17, $motus$ali osman ayman$motus$, $motus$5326479389$motus$, $motus$umut mah 3845 sok no.25 k.3 d.4 karabağlar$motus$, $motus$Karabağlar$motus$, $motus$tam takım$motus$, 1490.00, $motus$maintenance$motus$, $motus$$motus$, $motus$Melike İşler$motus$, $motus$Barış Can Gökçek$motus$),
(18, $motus$Zeynep Ünsal$motus$, $motus$5324880372$motus$, $motus$2. İnönü mah. 27 Mayıs cad.  Evleri sit. No:152 Blok 14 K:7 No:15$motus$, $motus$Narlıdere$motus$, $motus$tam takım$motus$, 1100.00, $motus$maintenance$motus$, $motus$Gitmeden ara 30 dk Önceden aranacak$motus$, $motus$Sultan Özdaş$motus$, $motus$Barış Can Gökçek$motus$),
(19, $motus$ahmet ölçer$motus$, $motus$5432411921$motus$, $motus$narlı mah gelincik sok 12/1 narlıdere$motus$, $motus$Narlıdere$motus$, $motus$tam takım$motus$, 1490.00, $motus$maintenance$motus$, $motus$$motus$, $motus$Melike İşler$motus$, $motus$Barış Can Gökçek$motus$),
(20, $motus$aslıhan kurtlu$motus$, $motus$5548743454$motus$, $motus$huzur mah mithatpaşa cad. 583 b k.7 d.14 narlıdere$motus$, $motus$Narlıdere$motus$, $motus$tam takım$motus$, 1490.00, $motus$maintenance$motus$, $motus$$motus$, $motus$Melike İşler$motus$, $motus$Barış Can Gökçek$motus$),
(21, $motus$Emre Doslu$motus$, $motus$5497900841$motus$, $motus$Rüstem Mah. İrem sok. No:7$motus$, $motus$Urla$motus$, $motus$LG ECO$motus$, 7000.00, $motus$maintenance$motus$, $motus$Nakit 6500 tl 12 kadar bekler gitmeden ara | Excel fiyat notu: 7000/4$motus$, $motus$Sultan Özdaş$motus$, $motus$Barış Can Gökçek$motus$),
(22, $motus$Sefer Ceylan$motus$, $motus$5326078854$motus$, $motus$Gazi Osman Paşa mah. 5428 sok. No:19$motus$, $motus$Bornova$motus$, $motus$tam takım$motus$, 1450.00, $motus$maintenance$motus$, $motus$12 kadar bekler gitmeden ara Açık kasa cihaz$motus$, $motus$Sultan Özdaş$motus$, $motus$Ali Sevinç$motus$),
(23, $motus$cansu kılıç$motus$, $motus$5511679560$motus$, $motus$inönü mah 791/9 sok no.1 k.1 bornova$motus$, $motus$Bornova$motus$, $motus$tam takım$motus$, 1490.00, $motus$maintenance$motus$, $motus$14.00 den sonra bekliyor k.k ile ödeme olcak$motus$, $motus$Melike İşler$motus$, $motus$Ali Sevinç$motus$),
(24, $motus$vesile aydemir$motus$, $motus$5353009691$motus$, $motus$751 sok no.4 polatlı kuyu mah yapıcıoğlu eşrefpaşa$motus$, $motus$Konak$motus$, $motus$tam takım$motus$, 1490.00, $motus$maintenance$motus$, $motus$12.00 e kadar bekliyor$motus$, $motus$Melike İşler$motus$, $motus$Engin Doğan$motus$),
(25, $motus$İbrahim bey$motus$, $motus$5366776972$motus$, $motus$731 sok. No:9 Hasan Özdemir mah. Çimentepe$motus$, $motus$Konak$motus$, $motus$tam takım$motus$, 1250.00, $motus$maintenance$motus$, $motus$Gitmeden ara$motus$, $motus$Sultan Özdaş$motus$, $motus$Engin Doğan$motus$),
(26, $motus$Talha Kaya$motus$, $motus$5441445834$motus$, $motus$Zafer Tepe Mah. 538 sok. No:34/36 D:6 K:3  Eşrefpaşa$motus$, $motus$Konak$motus$, $motus$tam takım$motus$, 1450.00, $motus$maintenance$motus$, $motus$cihazı kendi kurmuş bağlantıları da kontrol etsin der gitmeden  ara$motus$, $motus$Sultan Özdaş$motus$, $motus$Engin Doğan$motus$),
(27, $motus$faruk uğur$motus$, $motus$5052253715$motus$, $motus$güven mah 382 sok no.19 d.1 şirinyer$motus$, $motus$Buca$motus$, $motus$8'LT TANK$motus$, 2000.00, $motus$maintenance$motus$, $motus$12.00 den sonra bekliyor$motus$, $motus$Melike İşler$motus$, $motus$Engin Doğan$motus$),
(28, $motus$Aytaç Köseoğlu$motus$, $motus$5079180107$motus$, $motus$Akıncılar mah. 528 sok. No:21 K:2 D:2 Şirinyer$motus$, $motus$Buca$motus$, $motus$tam takım$motus$, 1450.00, $motus$maintenance$motus$, $motus$14 kadar evde gitmeden ara$motus$, $motus$Sultan Özdaş$motus$, $motus$Engin Doğan$motus$),
(29, $motus$Ayhan hanım$motus$, $motus$5301161447$motus$, $motus$565 sk No:32 D: 2 akıncılar$motus$, $motus$Buca$motus$, $motus$tam takım$motus$, 1500.00, $motus$maintenance$motus$, $motus$7 Şubat yapmışız  en son bakımı Gelmeden 1 saat Önceden arasın beni der$motus$, $motus$Sultan Özdaş$motus$, $motus$Engin Doğan$motus$),
(30, $motus$Engin Çalık$motus$, $motus$5073643345$motus$, $motus$İskent mah 1319 sk no:15 k.1 d:7 Köşem Apartmanı$motus$, $motus$Buca$motus$, $motus$LG ECO Alkali$motus$, 6750.00, $motus$new_installation$motus$, $motus$13500/4 olacak 3 den sonra istediği saate gelsin der$motus$, $motus$Sultan Özdaş$motus$, $motus$Engin Doğan$motus$),
(31, $motus$Ahmet Demirkol$motus$, $motus$5559683932$motus$, $motus$Adatepe mah. 2 sok. No:7 D:9$motus$, $motus$Buca$motus$, $motus$Arıza$motus$, 0.00, $motus$maintenance$motus$, $motus$13 Ağustos cihazımız kuruldu suyundan memnun değil Ölçüm ister | Excel fiyat notu: servis$motus$, $motus$Sultan Özdaş$motus$, $motus$Engin Doğan$motus$),
(32, $motus$Mehmet Karadağ$motus$, $motus$5414606891$motus$, $motus$Seyhan mah. 667/4 sok. No:17$motus$, $motus$Buca$motus$, $motus$5li filtre değişimi$motus$, 1450.00, $motus$maintenance$motus$, $motus$Gitmeden ara$motus$, $motus$Sultan Özdaş$motus$, $motus$Engin Doğan$motus$),
(33, $motus$Mustafa Değmen$motus$, $motus$5387457257$motus$, $motus$686 sok. No:27 K:2 D:1 Mustafa Kemal  mah.$motus$, $motus$Buca$motus$, $motus$5li filtre değişimi$motus$, 1450.00, $motus$maintenance$motus$, $motus$Gitmeden ara cumadan sonra ister$motus$, $motus$Sultan Özdaş$motus$, $motus$Engin Doğan$motus$),
(34, $motus$Mustafa Eşmekaya$motus$, $motus$5052699492$motus$, $motus$Huzur Mah 2408 sk no:4 d:1$motus$, $motus$Konak$motus$, $motus$LG ECO +Alkali+ Sebil Apt$motus$, 6750.00, $motus$new_installation$motus$, $motus$2 de bekler para alınmıcak$motus$, $motus$Sultan Özdaş$motus$, $motus$Engin Doğan$motus$);

do $$
declare
  r record;
  v_company uuid;
  v_customer uuid;
  v_secretary uuid;
  v_technician uuid;
  v_request uuid;
begin
  select id into v_company from public.companies order by created_at nulls last limit 1;

  for r in select * from motus_cuma_import order by source_row loop
    select id into v_secretary
      from public.profiles
     where company_id = v_company
       and role = 'secretary'
       and is_active = true
       and lower(trim(full_name)) = lower(trim(r.secretary_name))
     limit 1;

    if v_secretary is null then
      raise exception 'Satır %: Sekreter bulunamadı: %', r.source_row, r.secretary_name;
    end if;

    select id into v_technician
      from public.profiles
     where company_id = v_company
       and role = 'technician'
       and is_active = true
       and lower(trim(full_name)) = lower(trim(r.technician_name))
     limit 1;

    if v_technician is null then
      raise exception 'Satır %: Tekniker bulunamadı: %', r.source_row, r.technician_name;
    end if;

    select id into v_customer
      from public.customers
     where company_id = v_company
       and regexp_replace(coalesce(phone,''), '\D', '', 'g') = r.phone
     order by created_at desc nulls last
     limit 1;

    if v_customer is null then
      insert into public.customers (
        company_id, customer_type, full_name, phone, city, district, address,
        notes, is_active, registration_date, created_by, updated_by, created_at, updated_at
      ) values (
        v_company, 'individual', trim(r.full_name), r.phone, 'İzmir', trim(r.district), trim(r.address),
        null, true, date '2026-08-28', v_secretary, v_secretary, now(), now()
      )
      returning id into v_customer;
    else
      update public.customers
         set full_name = trim(r.full_name),
             city = 'İzmir',
             district = trim(r.district),
             address = trim(r.address),
             is_active = true,
             updated_by = v_secretary,
             updated_at = now()
       where id = v_customer;
    end if;

    -- Aynı SQL yanlışlıkla iki kere çalıştırılırsa aynı günlük işi tekrar oluşturma.
    if not exists (
      select 1
        from public.service_requests sr
       where sr.company_id = v_company
         and sr.customer_id = v_customer
         and sr.assigned_technician_id = v_technician
         and sr.planned_date::date = date '2026-08-28'
         and coalesce(sr.planned_product_name,'') = trim(r.product_name)
         and abs(coalesce(sr.price,0) - coalesce(r.price,0)) < 0.01
    ) then
      insert into public.service_requests (
        company_id,
        customer_id,
        service_type,
        description,
        price,
        status,
        planned_date,
        assigned_technician_id,
        created_by,
        planned_product_id,
        planned_product_name,
        planned_quantity,
        planned_unit_price,
        planned_items,
        route_order,
        route_plan_date,
        created_at,
        updated_at
      ) values (
        v_company,
        v_customer,
        r.service_type,
        coalesce(r.note,''),
        coalesce(r.price,0),
        'assigned',
        timestamptz '2026-08-28 09:00:00+03',
        v_technician,
        v_secretary,
        null,
        trim(r.product_name),
        1,
        coalesce(r.price,0),
        '[]'::jsonb,
        null,
        date '2026-08-28',
        now(),
        now()
      )
      returning id into v_request;
    end if;
  end loop;
end $$;

commit;

-- Kontrol özeti
select
  p.full_name as tekniker,
  count(*) as bugunku_is
from public.service_requests sr
join public.profiles p on p.id = sr.assigned_technician_id
where sr.planned_date::date = date '2026-08-28'
group by p.full_name
order by p.full_name;

select
  creator.full_name as sekreter,
  count(*) as girilen_is
from public.service_requests sr
join public.profiles creator on creator.id = sr.created_by
where sr.planned_date::date = date '2026-08-28'
group by creator.full_name
order by creator.full_name;
