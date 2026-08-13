-- ARN ERP / PARAKENDE.xlsx güvenli veri aktarımı
-- Oluşturulma: 30.07.2026
-- Excel satırı: 1025
-- Benzersiz ürün: 33
-- Bu dosya tek transaction içinde çalışır; hata olursa hiçbir kayıt yarım kalmaz.
-- ÖNEMLİ: Önce V18 migration'ları çalışmış olmalıdır.

begin;

create extension if not exists pgcrypto;

create or replace function public.arn_import_norm(p_text text)
returns text
language sql
immutable
as $$
  select regexp_replace(
    lower(translate(coalesce(btrim(p_text), ''), 'İIı', 'iii')),
    '\s+', ' ', 'g'
  );
$$;

create table if not exists public.arn_excel_import_batches (
  batch_id text primary key,
  source_file text not null,
  source_row_count integer not null,
  imported_at timestamptz not null default now()
);

do $$
begin
  if exists(select 1 from public.arn_excel_import_batches where batch_id='PARAKENDE_2026_07_30_V1') then
    raise exception 'Bu Excel daha önce aktarılmış: %', 'PARAKENDE_2026_07_30_V1';
  end if;
end $$;

-- Excel'de telefonu boş olan müşterilerin ayrı kartlar halinde korunabilmesi için
-- boş telefonlar unique kontrolünün dışında bırakılır.
drop index if exists public.idx_customers_company_phone_unique;
create unique index if not exists idx_customers_company_phone_unique_nonempty
  on public.customers(company_id, phone)
  where btrim(phone) <> '';

alter table public.customer_maintenance_records
  add column if not exists import_batch_id text,
  add column if not exists import_source_row integer;

alter table public.historical_customer_sales
  add column if not exists import_batch_id text,
  add column if not exists import_source_row integer;

create unique index if not exists customer_maintenance_import_row_unique
  on public.customer_maintenance_records(import_batch_id, import_source_row)
  where import_batch_id is not null;

create unique index if not exists historical_sales_import_row_unique
  on public.historical_customer_sales(import_batch_id, import_source_row)
  where import_batch_id is not null;

create temporary table tmp_parakende_import (
  source_row integer primary key,
  customer_name text not null,
  phone text not null,
  address text not null,
  city text not null,
  district text not null,
  product_name text not null,
  quantity numeric(12,2) not null,
  amount numeric(12,2) not null,
  transaction_date date not null,
  technician_name text not null,
  secretary_name text not null
) on commit drop;

insert into tmp_parakende_import(
  source_row, customer_name, phone, address, city, district,
  product_name, quantity, amount, transaction_date,
  technician_name, secretary_name
) values
(2,'Gamze Eroğlu','5076856373','126/11 sk no:4 k:1 d:2','İzmir','Bornova','Montaj',1,0,'2025-09-30'::date,'Ali','Sultan'),
(3,'Bahadır Alp','5424494530','8790-10 sk no:26 d:2','İzmir','Çiğli','Tam Takım',1,1250,'2025-10-01'::date,'Ali','Sultan'),
(4,'Belgin Hanım','5308766849','2638 no:9 d:2','İzmir','Konak','Tam Takım',1,1250,'2025-10-01'::date,'Ali','Sultan'),
(5,'Bülent Bey','5334038395','2827 SK. No:60 1. sanayi st.','İzmir','Konak','Tam Takım',1,1000,'2025-10-01'::date,'Ali','Sultan'),
(6,'Hasan Karagöz','5378603904','8927/4 No:10 K:4 D:29','İzmir','Çiğli','Tam Takım',1,1500,'2025-10-01'::date,'Ali','Sultan'),
(7,'Hasan Karagöz','5378603904','8927/4 No:10 K:4 D:29','İzmir','Çiğli','Alkali',1,1250,'2025-10-01'::date,'Ali','Sultan'),
(8,'Ali Bozan','5459697603','Mustafa kemal atatürk mh. 7019 sk. No:4','İzmir','Torbalı','Tam Takım',1,1400,'2025-10-02'::date,'Ali','Sultan'),
(9,'kadir akkuş','5514395370','seyrantepe cd. 562 sk no:35 kuşçuburun','İzmir','Torbalı','Lg Eco',1,6000,'2025-10-02'::date,'Ali','Sultan'),
(10,'mehmet bey','5436809113','emrez mh 190 sk no:1 k:2','İzmir','Gaziemir','Tam Takım',1,1000,'2025-10-02'::date,'Ali','Sultan'),
(11,'Mustafa Taştan','5323363304','Günaltay mh. 4876 sk. No:30','İzmir','Karabağlar','Lg Eco',1,7000,'2025-10-02'::date,'Ali','Sultan'),
(12,'Mustafa Taştan','5323363304','Günaltay mh. 4876 sk. No:30','İzmir','Karabağlar','Tam Takım',2,2000,'2025-10-02'::date,'Ali','Sultan'),
(13,'Serkan Başak','5379470378','1615/9 sk. No:57 d:1-2-3','İzmir','Bayraklı','Tam Takım',3,4500,'2025-10-02'::date,'Ali','Sultan'),
(14,'Hakan Küçük','5322842306','7216 sk. No:2 k:3 d:9','İzmir','Bayraklı','Tam Takım',1,1200,'2025-10-03'::date,'Ali','Sultan'),
(15,'Hakan Küçük','5322842306','7216 sk. No:2 k:3 d:9','İzmir','Bayraklı','Alkali',1,1000,'2025-10-03'::date,'Ali','Sultan'),
(16,'Hakan Küçük','5322842306','7216 sk. No:2 k:3 d:9','İzmir','Bayraklı','Tank',1,1000,'2025-10-03'::date,'Ali','Sultan'),
(17,'Hamide Aydoğdu','5531175951','1918 sk. No:22 d:1','İzmir','Bayraklı','Tam Takım',1,1500,'2025-10-03'::date,'Ali','Sultan'),
(18,'Hamide Aydoğdu','5531175951','1918 sk. No:22 d:1','İzmir','Bayraklı','Tam Takım',1,1000,'2025-10-03'::date,'Ali','Sultan'),
(19,'Hüseyin Görmez','5446930740','5714/32 sk. No:34 d:3','İzmir','Karabağlar','Tam Takım',1,1500,'2025-10-03'::date,'Ali','Sultan'),
(20,'seyit ahmet arabacı','5325828133','1201 sk no:34 murathan mh','İzmir','Buca','Tam Takım',1,1000,'2025-10-03'::date,'Ali','Sultan'),
(21,'seyit ahmet arabacı','5325828133','1201 sk no:34 murathan mh','İzmir','Buca','Alkali',1,1500,'2025-10-03'::date,'Ali','Sultan'),
(22,'Gülşen çağan','5078935579','2071 sk. No:7 A K:1','İzmir','Bayraklı','Lg Eco',1,8000,'2025-10-04'::date,'Ali','Sultan'),
(23,'mehmet gülnur','5374767205','5757/2 sk. No:37 k:2 d:2','İzmir','Karabağlar','Tam Takım',1,1500,'2025-10-04'::date,'Ali','Sultan'),
(24,'Rıza Dolu','5326514509','1145/5 sk. No:11 d:104/105','İzmir','Karşıyaka','Lg Eco',1,12000,'2025-10-04'::date,'Ali','Sultan'),
(25,'Rıza Dolu','5326514509','1145/5 sk. No:11 d:104/105','İzmir','Karşıyaka','Alkali',1,2000,'2025-10-04'::date,'Ali','Sultan'),
(26,'Rıza Dolu','5326514509','1145/5 sk. No:11 d:104/105','İzmir','Karşıyaka','Sebil Ap.',1,1000,'2025-10-04'::date,'Ali','Sultan'),
(27,'taner koyuncu','5558314778','3867 sk. No:70/1 k:4 d:4','İzmir','Karabağlar','Tam Takım',1,1500,'2025-10-04'::date,'Ali','Sultan'),
(28,'taner koyuncu','5558314778','3867 sk. No:70/1 k:4 d:4','İzmir','Karabağlar','Alkali',1,1000,'2025-10-04'::date,'Ali','Sultan'),
(29,'Ali Şirin','5389855823','torbalı mh 5013 sk kat:7 d:31','İzmir','Torbalı','Tam Takım',1,1250,'2025-10-04'::date,'Ali','Sultan'),
(30,'hakan çağan','5327438285','murat bey mh. 3560 sk. No:9 d:1','İzmir','Torbalı','Lg Eco',1,8000,'2025-10-05'::date,'Ali','Sultan'),
(31,'abidin çelik','5352485270','7467/1 sk. No:1 k:2 d:4','İzmir','Karşıyaka','Tam Takım',1,1000,'2025-10-07'::date,'Ali','Sultan'),
(32,'bayram inan','5369414062','5044 sk. No:86 d:2','İzmir','Karabağlar','Tam Takım',1,1200,'2025-10-07'::date,'Ali','Sultan'),
(33,'hüseyin karataş','5352621881','7563/3 sk no:15 k:2 d:10','İzmir','Karşıyaka','Tam Takım',1,1000,'2025-10-07'::date,'Ali','Sultan'),
(34,'liman şen','5342049052','4399/33 no:12','İzmir','Bayraklı','Tam Takım',1,1100,'2025-10-07'::date,'Ali','Sultan'),
(35,'yılmaz yiğit','5384015655','1637/16 sk no:56 k:2 d:2','İzmir','Bayraklı','Lg Eco',1,5000,'2025-10-07'::date,'Ali','Sultan'),
(36,'yusuf tezdönen','5447871081','4957 sk no:24 d:1','İzmir','Karabağlar','Tam Takım',1,1100,'2025-10-07'::date,'Ali','Sultan'),
(37,'ganik hanım','5354276917','bahariye mh 1865 sk no:23 d:4','İzmir','Karşıyaka','Lg Eco',1,5000,'2025-10-08'::date,'Ali','Sultan'),
(38,'ganik hanım','5354276917','bahariye mh 1865 sk no:23 d:4','İzmir','Karşıyaka','Alkali',1,2000,'2025-10-08'::date,'Ali','Sultan'),
(39,'İkran Öztunç','5434291123','292/21 sk no:20 d:1','İzmir','Buca','Lg Eco',1,7000,'2025-10-08'::date,'Ali','Sultan'),
(40,'İkran Öztunç','5434291123','292/21 sk no:20 d:1','İzmir','Buca','Pompa',1,2000,'2025-10-08'::date,'Ali','Sultan'),
(41,'Sebehattin Dinç','5325044619','Yazar sk no:13 d:10','İzmir','Balçova','Montaj',1,750,'2025-10-08'::date,'Ali','Sultan'),
(42,'seher koç','5318649387','2628 sk. No:12 d:2','İzmir','Konak','Tam Takım',1,1000,'2025-10-08'::date,'Ali','Sultan'),
(43,'seher koç','5318649387','2628 sk. No:12 d:2','İzmir','Konak','Alkali',1,1000,'2025-10-08'::date,'Ali','Sultan'),
(44,'Serpil Gökçe','5333318817','187/4 sk no:33 İnönü mah','İzmir','Torbalı','Tam Takım',1,1100,'2025-10-09'::date,'Ali','Sultan'),
(45,'Ali Çakmakçı','5075575655','2918 sk no:82B','İzmir','Karabağlar','Tam Takım',1,1500,'2025-10-10'::date,'Ali','Sultan'),
(46,'Çetin Akkaya','5443867855','8205 sk no:25 k:1','İzmir','Çiğli','Tam Takım',1,1100,'2025-10-10'::date,'Mehmet','Sultan'),
(47,'Gökhan Aydoğan','5451354919','292/21 sk no:16 k:1 d:1','İzmir','Buca','Tam Takım',1,1000,'2025-10-10'::date,'Ali','Sultan'),
(48,'Gökhan Aydoğan','5451354919','292/21 sk no:16 k:1 d:1','İzmir','Buca','Alkali',1,1000,'2025-10-10'::date,'Ali','Sultan'),
(49,'Gülnur Ölçen','5355271281','1675 sk no:39 kat:5 d:7 alaybey','İzmir','Bayraklı','Tam Takım',1,1500,'2025-10-10'::date,'Ali','Sultan'),
(50,'Saliha Hanım','5531481715','186 sk no:12 d:7','İzmir','konak','Tam Takım',1,1100,'2025-10-11'::date,'Ali','Sultan'),
(51,'Coşkun Bey','5339276335','Güven mh 387 sk d:1','İzmir','Konak','Lg Eco',1,5000,'2025-10-11'::date,'Ali','Sultan'),
(52,'Coşkun Bey','5339276335','Güven mh 387 sk d:1','İzmir','Konak','Alkali',1,1000,'2025-10-11'::date,'Ali','Sultan'),
(53,'İdris Nazik','5074320036','1261/1 sk No:33 D:1','İzmir','Bornova','Lg Eco',1,5000,'2025-10-12'::date,'Ali','Sultan'),
(54,'İdris Nazik','5074320036','1261/1 sk No:33 D:1','İzmir','Bornova','Alkali',1,1000,'2025-10-12'::date,'Ali','Sultan'),
(55,'Cemile Moğlu','5388509823','707 sk no:15 d:3','İzmir','Konak','Lg Eco',1,4500,'2025-10-13'::date,'Ali','Sultan'),
(56,'Feridun Tezkorkmaz','5057081796','7399/24 sk no:13','İzmir','Bayraklı','Tam Takım',1,1100,'2025-10-13'::date,'Ali','Sultan'),
(57,'melda bölükbaş','5402500045','ekrem akungan cd no:20 d:4','İzmir','Bayraklı','Lg Eco',1,7000,'2025-10-13'::date,'Ali','Sultan'),
(58,'melda bölükbaş','5402500045','ekrem akungan cd no:20 d:4','İzmir','Bayraklı','Sebil Ap.',1,0,'2025-10-13'::date,'Ali','Sultan'),
(59,'Murtaza Özüpek','5383614133','3968/11 sk  no:7','İzmir','Karabağlar','Tam Takım',1,1100,'2025-10-13'::date,'Ali','Sultan'),
(60,'Seyhan Sarıkaya','5421751912','1620/32 sk no:10','İzmir','Bayraklı','Montaj',1,500,'2025-10-13'::date,'Ali','Sultan'),
(61,'Taner Başdemir','5536095398','2166/11 sk no:4 k:2','İzmir','Bayraklı','Tam Takım',1,1100,'2025-10-13'::date,'Ali','Sultan'),
(62,'Taner Başdemir','5536095398','2166/11 sk no:4 k:2','İzmir','Bayraklı','Alkali',1,1200,'2025-10-13'::date,'Ali','Sultan'),
(63,'Zatin Aktaş','5553143239','5057 sk no:23 d:1','İzmir','Karabağlar','Tam Takım',1,1100,'2025-10-13'::date,'Ali','Sultan'),
(64,'Zatin Aktaş','5553143239','5057 sk no:23 d:1','İzmir','Karabağlar','Alkali',1,1100,'2025-10-13'::date,'Ali','Sultan'),
(65,'döndü ay','5358113707','6221/1 sk. No:15 k:5 d:10','İzmir','Karşıyaka','ön takım',1,800,'2025-10-14'::date,'Ali','Sultan'),
(66,'Feride Kurt','5466846240','7382/1 sk A3 blok 80. Ada 9/31','İzmir','Bayraklı','Lg Eco',1,5500,'2025-10-14'::date,'Ali','Sultan'),
(67,'Feride Kurt','5466846240','7382/1 sk A3 blok 80. Ada 9/31','İzmir','Bayraklı','Alkali',1,1500,'2025-10-14'::date,'Ali','Sultan'),
(68,'Selma Sağınç','5417817050','10/2 sk no:2 d:13 k:3','İzmir','Ayrancılar','Tam Takım',1,1000,'2025-10-14'::date,'Ali','Sultan'),
(69,'Selma Sağınç','5417817050','10/2 sk no:2 d:13 k:3','İzmir','Ayrancılar','Alkali',1,1500,'2025-10-14'::date,'Ali','Sultan'),
(70,'Burçin Gökçe','5057686264','Abdülhamit yavuz cad no:79 d:21','İzmir','Gaziemir','Tam Takım',1,1100,'2025-10-15'::date,'Ali','Sultan'),
(71,'Burçin Gökçe','5057686264','Abdülhamit yavuz cad no:79 d:21','İzmir','Gaziemir','Alkali',1,1200,'2025-10-15'::date,'Ali','Sultan'),
(72,'Hayati özbek','5365634282','ozan sk. No:22 d:1','İzmir','Balçova','Tam Takım',1,1800,'2025-10-15'::date,'Ali','Sultan'),
(73,'Murat Cantürk','5325148762','mithatpasa cd. No:89 d:9','İzmir','Balçova','Tam Takım',1,0,'2025-10-15'::date,'Ali','Sultan'),
(74,'Servet Duruk','5541593513','3.Selim sk no:27 d:9','İzmir','Balçova','Tam Takım',1,1100,'2025-10-15'::date,'Ali','Sultan'),
(75,'Süheyla Dayan','5530183886','7161 sk no:136 k:2 d:2','İzmir','Bayraklı','Tam Takım',1,1500,'2025-10-15'::date,'Ali','Sultan'),
(76,'Süleyman Çetin','5312472135','Gediz sk no:13 d:3','İzmir','Balçova','Tam Takım',1,1500,'2025-10-15'::date,'Ali','Sultan'),
(77,'bekir öztekin','5383690976','subaşı mh. 312 sk no:13','İzmir','Torbalı','Lg Eco',1,6000,'2025-10-16'::date,'Ali','Sultan'),
(78,'bekir öztekin','5383690976','subaşı mh. 312 sk no:13','İzmir','Torbalı','Alkali',1,1500,'2025-10-16'::date,'Ali','Sultan'),
(79,'Dilara turasan','5522372643','173/1 sk. No:8 tombul apt. k:1 d:1','izmir','Karabağlar','Lg Eco',1,6000,'2025-10-16'::date,'Ali','Sultan'),
(80,'Dilara turasan','5522372643','173/1 sk. No:8 tombul apt. k:1 d:1','izmir','Karabağlar','Alkali',1,1500,'2025-10-16'::date,'Ali','Sultan'),
(81,'Gökçe Cantürk','5076636769','65/11 sk no:2 k:4 d:8','İzmir','Karabağlar','Tam Takım',1,0,'2025-10-16'::date,'Ali','Sultan'),
(82,'Murat Kollar','5323322927','349 sk. No:62 k:1 d:4','İzmir','Buca','Lg Eco',1,6000,'2025-10-16'::date,'Ali','Sultan'),
(83,'Murat Kollar','5323322927','349 sk. No:62 k:1 d:4','İzmir','Buca','Alkali',1,1500,'2025-10-16'::date,'Ali','Sultan'),
(84,'Vahide karaaslan','5057749292','5708/2 sk. No:2 d:1','İzmir','Karabağlar','Tam Takım',1,1000,'2025-10-16'::date,'Ali','Sultan'),
(85,'Vahide karaaslan','5057749292','5708/2 sk. No:2 d:1','İzmir','Karabağlar','Alkali',1,1000,'2025-10-16'::date,'Ali','Sultan'),
(86,'ali rıza karataş','','7601 sk no:1 k:8 d:32','İzmir','menemen','Tam Takım',1,1500,'2025-10-17'::date,'Ali','Sultan'),
(87,'ali rıza karataş','','7601 sk no:1 k:8 d:32','İzmir','menemen','Alkali',1,1000,'2025-10-17'::date,'Ali','Sultan'),
(88,'handan şakman','5336195123','1835/1 sk no:12 d:3','İzmir','Karşıyaka','servis',1,1600,'2025-10-17'::date,'Ali','Sultan'),
(89,'mehmet fadil dağ','','1211/2 no:9 d:6','İzmir','menemen','Tam Takım',1,1000,'2025-10-17'::date,'Ali','Sultan'),
(90,'mehmet fadil dağ','','1211/2 no:9 d:6','İzmir','menemen','Alkali',1,1000,'2025-10-17'::date,'Ali','Sultan'),
(91,'dilan demirbaş','5530567551','küplücealtı küme evleri no:66/10','İzmir','kemalpasa','Lg Eco',1,5000,'2025-10-18'::date,'Ali','Sultan'),
(92,'gazi özhan','5452329091','çukuraltı mh 2082 sk no:17/1','İzmir','Özdere','Tam Takım',1,1900,'2025-10-18'::date,'RAİF','Sultan'),
(93,'hüseyin elekçi','5319662561','kılıçreis cad no:13','İzmir','Konak','Tam Takım',1,1000,'2025-10-18'::date,'Ali','Sultan'),
(94,'Mehmet bozdoğan','5377297296','1443 sk garden bornova st no:15','İzmir','Konak','Lg Eco',1,6500,'2025-10-18'::date,'Ali','Sultan'),
(95,'Mehmet bozdoğan','5377297296','1443 sk garden bornova st no:15','İzmir','Konak','Alkali',1,1500,'2025-10-18'::date,'Ali','Sultan'),
(96,'şerif elekçi','5373661853','kılıçreis cad no:13','İzmir','Konak','Tam Takım',1,1000,'2025-10-18'::date,'Ali','Sultan'),
(97,'doğan çetinkaya','5052352555','2980 sk no:12 d:7','İzmir','Karabağlar','LG Vıp',1,7000,'2025-10-20'::date,'Ali','Sultan'),
(98,'doğan çetinkaya','5052352555','2980 sk no:12 d:7','İzmir','Karabağlar','Alkali',1,1000,'2025-10-20'::date,'Ali','Sultan'),
(99,'doğan çetinkaya','5052352555','2980 sk no:12 d:7','İzmir','Karabağlar','Tam Takım',1,1000,'2025-10-20'::date,'Ali','Sultan'),
(100,'kemal türkekul','5368700375','pilot volkan koçyiğit blv no:56 k:1 d:5','İzmir','Karabağlar','Lg Eco',1,5000,'2025-10-20'::date,'Ali','Sultan'),
(101,'murat kaya','5550972409','4215/1 sk no:49 d:2','İzmir','altındağ','Lg Eco',1,5500,'2025-10-20'::date,'Ali','Sultan'),
(102,'murat kaya','5550972409','4215/1 sk no:49 d:2','İzmir','altındağ','Alkali',1,1500,'2025-10-20'::date,'Ali','Sultan'),
(103,'tanju sefilli','5558389337','4854 sk no:18 k:1 d:2','İzmir','Karabağlar','Lg Eco',1,6000,'2025-10-20'::date,'Ali','Sultan'),
(104,'tanju sefilli','5558389337','4854 sk no:18 k:1 d:2','İzmir','Karabağlar','Alkali',1,1000,'2025-10-20'::date,'Ali','Sultan'),
(105,'aladdin kurşun','5367123547','289/3 sk no:8/a d:2','İzmir','buca','Tam Takım',1,1100,'2025-10-21'::date,'Ali','Sultan'),
(106,'emir kalaycıoğlu','5426576803','çamdibi sk no:4','İzmir','kemalpasa','Tam Takım',1,1250,'2025-10-21'::date,'Ali','Sultan'),
(107,'lütfi bayrak','5323631536','soğukpınar mh 263 sk no:15 d:3-4','İzmir','kemalpasa','Lg Eco',1,5000,'2025-10-21'::date,'Ali','Sultan'),
(108,'lütfi bayrak','5323631536','soğukpınar mh 263 sk no:15 d:3-4','İzmir','kemalpasa','Alkali',1,1000,'2025-10-21'::date,'Ali','Sultan'),
(109,'mevlüt taştan','','29 ekim mh bahçıvan bekir sk no:17','İzmir','kemalpasa','Tam Takım',1,1250,'2025-10-21'::date,'Ali','Sultan'),
(110,'temel yeleş','5354264182','2629 sk no:10 çınartepe mh','İzmir','Gültepe','Tam Takım',1,1100,'2025-10-21'::date,'Ali','Sultan'),
(111,'zeki özbek','5355566744','efeler mh forbes sk no:64C','İzmir','buca','Alkali',1,1000,'2025-10-21'::date,'Ali','Sultan'),
(112,'zeki özbek','5355566744','efeler mh forbes sk no:64C','İzmir','buca','Lg Eco',1,6000,'2025-10-21'::date,'Ali','Sultan'),
(113,'cemaliye koçyiğit','5527211971','8081 sokak no:11 d:2','İzmir','Çiğli','Tam Takım',1,1200,'2025-10-22'::date,'Ali','Sultan'),
(114,'cemaliye koçyiğit','5527211971','8081 sokak no:11 d:2','İzmir','Çiğli','Musluk',1,1000,'2025-10-22'::date,'Ali','Sultan'),
(115,'ercais mert','5353461578','2084/5 sk no:1 k:4 d:4','İzmir','Bayraklı','Lg Eco',1,6000,'2025-10-22'::date,'Ali','Sultan'),
(116,'haluk gülüsta','','yazar sk no:9 d:10','İzmir','Gaziemir','Tam Takım',1,1100,'2025-10-22'::date,'Ali','Sultan'),
(117,'Müslüm Koçak','5369206125','2119 sk no:9 d:1-2-3','İzmir','Bayraklı','Tam Takım',3,0,'2025-10-22'::date,'RAİF','Sultan'),
(118,'serdar tazegül','','8050 sk no:106 k:7 d:15','İzmir','Çiğli','Tam Takım',1,1100,'2025-10-22'::date,'Ali','Sultan'),
(119,'teslime kaya','5426393435','yüzbaşı hakkı no:209 d:11','İzmir','Bayraklı','Lg Eco',1,5000,'2025-10-22'::date,'Ali','Sultan'),
(120,'uğur akalın','5392116541','bahçelievler mh 909 sk c-7 d:25','İzmir','Torbalı','Lg Eco',1,5000,'2025-10-22'::date,'Ali','Sultan'),
(121,'ziya civlez','5448826004','3616 sk no:12 k:2 d:5','İzmir','Torbalı','Tam Takım',1,1100,'2025-10-22'::date,'Ali','Sultan'),
(122,'Şemistan Güngör','5315813864','3988/2 sk no:41 d:10','İzmir','Karabağlar','Tam Takım',1,1500,'2025-10-23'::date,'Ali','Sultan'),
(123,'Şemistan Güngör','5315813864','3988/2 sk no:41 d:10','İzmir','Karabağlar','Alkali',1,1500,'2025-10-23'::date,'Ali','Sultan'),
(124,'Aytaç Ertunç','5426230237','Yavuz sultan selim cd no:4 d:6','İzmir','buca','Lg Eco',1,4400,'2025-10-24'::date,'Ali','Sultan'),
(125,'Aytaç Ertunç','5426230237','Yavuz sultan selim cd no:4 d:6','İzmir','Buca','Alkali',1,900,'2025-10-24'::date,'Ali','Sultan'),
(126,'Fatih Şencan','5549897728','Belenbaşı mh 3020 sk no:15/8','İzmir','buca','Lg Eco',1,6000,'2025-10-24'::date,'Ali','Sultan'),
(127,'Fatih Şencan','5549897728','Belenbaşı mh 3020 sk no:15/8','İzmir','buca','Alkali',1,1500,'2025-10-24'::date,'Ali','Sultan'),
(128,'Mehmet Emin Baybostan','5059903563','222/54 sk no:3 d:7','İzmir','Buca','Tam Takım',1,1500,'2025-10-24'::date,'Ali','Sultan'),
(129,'Hasan Yıldırım','5442265838','255/2 sk no:1 d:12','İzmir','Konak','Lg Eco',1,6000,'2025-10-25'::date,'Ali','Sultan'),
(130,'Hasan Yıldırım','5442265838','255/2 sk no:1 d:12','İzmir','Konak','Alkali',1,1000,'2025-10-25'::date,'Ali','Sultan'),
(131,'Hayrettin Sevim','5424134254','1665 sk no:23 d:10','İzmir','Karşıyaka','Lg Eco',1,6000,'2025-10-25'::date,'Ali','Sultan'),
(132,'Hayrettin Sevim','5424134254','1665 sk no:23 d:10','İzmir','Karşıyaka','Alkali',1,1500,'2025-10-25'::date,'Ali','Sultan'),
(133,'Yaşar Taş','5340143361','4767 sk no:8 çamkule','İzmir','altındağ','Tam Takım',1,1500,'2025-10-25'::date,'Ali','Sultan'),
(134,'Cavit Gökdemir','5369216378','1652 Sk No:9 D:4 K:5','İzmir','Bornova','Tam Takım',1,1100,'2025-10-27'::date,'Ali','Sultan'),
(135,'Cavit Gökdemir','5369216378','1652 Sk No:9 D:4 K:5','İzmir','Bornova','Lg Eco',1,7000,'2025-10-27'::date,'Ali','Sultan'),
(136,'Mehmet Turan','5346086052','Turgut Reis Cd. No:112','İzmir','Bornova','Tam Takım',1,1100,'2025-10-27'::date,'Ali','Sultan'),
(137,'Medeni Gürbüz','5336866114','203/1 No:11 K:4 D:18','İzmir','Bornova','Tam Takım',1,1100,'2025-10-27'::date,'Ali','Sultan'),
(138,'Ünal Şen','5324960264','Mansuroğlu mh 273/8 sk no:7','İzmir','Bayraklı','Lg Eco',1,6000,'2025-10-27'::date,'Ali','Sultan'),
(139,'Ünal Şen','5324960264','Mansuroğlu mh 273/8 sk no:7','İzmir','Bayraklı','Alkali',1,1000,'2025-10-27'::date,'Ali','Sultan'),
(140,'Ünal Şen','5324960264','Mansuroğlu mh 273/8 sk no:7','İzmir','Bayraklı','40 Lt. Tank',1,3000,'2025-10-27'::date,'Ali','Sultan'),
(141,'İbrahim Çakır','5355914048','1254 sk no:2 d:5 cumhuriyet mh','İzmir','buca','Lg Eco',1,4000,'2025-10-27'::date,'Ali','Sultan'),
(142,'Leyla Acar','5304290703','Yaşar kemal mh 6004 sk no:16 k:8 d:37','İzmir','Karabağlar','Lg Eco',1,5000,'2025-10-27'::date,'Ali','Sultan'),
(143,'Leyla Acar','5304290703','Yaşar kemal mh 6004 sk no:16 k:8 d:37','İzmir','Karabağlar','Alkali',1,2000,'2025-10-27'::date,'Ali','Sultan'),
(144,'Bilal Şipal','5367890812','552 Sk No:22 Gerenköy','İzmir','Foça','Tam Takım',1,1100,'2025-10-28'::date,'Ali','Sultan'),
(145,'Mehmet Sevilgen','5425043689','696/9 Sk No:2A B-Blok D:2','İzmir','Buca','Tam Takım',1,1100,'2025-10-28'::date,'Ali','Sultan'),
(146,'Mehmet Sevilgen','5425043689','696/9 Sk No:2A B-Blok D:2','İzmir','Buca','Alkali',1,900,'2025-10-28'::date,'Ali','Sultan'),
(147,'Ramazan Dağlı','5365652685','Maresal fevzi çakmak mh 552 sk no:8 d:1','İzmir','Foça','Lg Eco',1,7500,'2025-10-28'::date,'Ali','Sultan'),
(148,'Sabahat Civan','5065641597','Ceren Sk No:29','İzmir','Foça','Tam Takım',1,1100,'2025-10-28'::date,'Ali','Sultan'),
(149,'Yağmur Bulut','5075444774','1921 Sk. No:10 D:6 K:3','İzmir','Bayraklı','Lg Eco',1,7500,'2025-10-28'::date,'Ali','Sultan'),
(150,'Serhat Özak','5304054041','1013 sk no:23 İnönü mah Bornova','İzmir','Bornova','Lg Eco',1,5500,'2025-10-28'::date,'Ali','Sultan'),
(151,'Serhat Özak','5304054041','1013 sk no:23 İnönü mah Bornova','İzmir','Bornova','Alkali',1,1500,'2025-10-28'::date,'Ali','Sultan'),
(152,'Ethem Gürcü','5322848561','Mithatpasa cd. No:623','İzmir','Konak','Tam Takım',1,1000,'2025-10-29'::date,'Ali','Sultan'),
(153,'Ethem Gürcü','5322848561','Mithatpasa cd. No:623','İzmir','Konak','Alkali',1,1500,'2025-10-29'::date,'Ali','Sultan'),
(154,'Kader Kuru','5075677045','120/1 Sk. No:6 Bahar Apt. D:4','İzmir','Buca','Tam Takım',1,850,'2025-10-29'::date,'Ali','Sultan'),
(155,'Mualla Büyük','5337178537','98 sk no:26 D:4','İzmir','Konak','Lg Eco',1,5000,'2025-10-29'::date,'Ali','Sultan'),
(156,'Mualla Büyük','5337178537','98 sk no:26 D:4','İzmir','Konak','Alkali',1,1000,'2025-10-29'::date,'Ali','Sultan'),
(157,'Sabriye Hanım(Annesi)','5373661853','','İzmir','Konak','Tam Takım',1,1000,'2025-10-29'::date,'Ali','Sultan'),
(158,'Ersin Polat','5369670141','99 Sk No:12 Melek apt A Blok','İzmir','Ayrancılar','Tam Takım',1,1100,'2025-10-30'::date,'Ali','Sultan'),
(159,'Ersin Polat','5369670141','99 Sk No:12 Melek apt A Blok','İzmir','Ayrancılar','Alkali',1,1000,'2025-10-30'::date,'Ali','Sultan'),
(160,'Ali Güneş','5346840113','7465/3 sk no:12 k:3 d:5','İzmir','Karşıyaka','Tam Takım',1,1100,'2025-10-30'::date,'Ali','Sultan'),
(161,'Hakan Aydemir','5522103504','130 sk no:4 d:4 no:3','İzmir','Ayrancılar','Tam Takım',1,1100,'2025-10-30'::date,'Ali','Sultan'),
(162,'Hüseyin Koçer','5424611883','Seyrantepe cd no:5 Kuşçuburun','İzmir','Torbalı','Tam Takım',1,1100,'2025-10-30'::date,'Ali','Sultan'),
(163,'Yaşar Bülbül','5379723758','1645 Sk No:16 d:3','İzmir','Bayraklı','Tam Takım',1,1000,'2025-10-30'::date,'Ali','Sultan'),
(164,'Yaşar Bülbül','5379723758','1645 Sk No:16 d:3','İzmir','Bayraklı','Alkali',1,1000,'2025-10-30'::date,'Ali','Sultan'),
(165,'Menderes Buldak','5369670141','99 sk no:12 melek apt A Blok d:13','İzmir','Ayrancılar','Tam Takım',1,1100,'2025-10-30'::date,'Ali','Sultan'),
(166,'Menderes Buldak','5369670141','99 sk no:12 melek apt A Blok d:13','İzmir','Ayrancılar','Alkali',1,1100,'2025-10-30'::date,'Ali','Sultan'),
(167,'Ünsal Üsküdar','5382864856','374 sk no:24','İzmir','Güzelbahçe','Tam Takım',1,1100,'2025-10-30'::date,'Ali','Sultan'),
(168,'Murat Akıncı','5358275872','Namık kemal cd no:73','İzmir','Güzelbahçe','Lg Eco',1,5000,'2025-10-31'::date,'Ali','Sultan'),
(169,'Murat Akıncı','5358275872','Namık kemal cd no:73','İzmir','Güzelbahçe','Alkali',1,1000,'2025-10-31'::date,'Ali','Sultan'),
(170,'Nurittin Ateşli','5336011226','1113 sk no:19','İzmir','Konak','Lg Eco',1,5000,'2025-11-01'::date,'Ali','Sultan'),
(171,'Nurittin Ateşli','5336011226','1113 sk no:19','İzmir','Konak','Alkali',1,6000,'2025-11-01'::date,'Ali','Sultan'),
(172,'Veli Bulut','5356245344','683 sk no:7 d:7 çimentepe','İzmir','Konak','Tam Takım',1,1000,'2025-11-01'::date,'Ali','Sultan'),
(173,'Veli Bulut','5356245344','683 sk no:7 d:7 çimentepe','İzmir','Konak','Alkali',1,1000,'2025-11-01'::date,'Ali','Sultan'),
(174,'Tolga Kara','5530202635','7314/1 sk no:4','İzmir','Bornova','Tam Takım',1,1100,'2025-11-03'::date,'Ali','Sultan'),
(175,'Necdet Mumcu','5373374209','6007 sk no:16 k:1 d:1','İzmir','Karşıyaka','Tam Takım',1,1100,'2025-11-03'::date,'Ali','Sultan'),
(176,'Ali Şimşek','5366031435','7600 sk no:97 k:6 d:23','İzmir','Bayraklı','Tam Takım',1,1100,'2025-11-03'::date,'Ali','Sultan'),
(177,'Murat Yalçınkaya','5366031435','7600 No: 97 d:23 k:6','izmir','Bayraklı','Tam Takım',1,1100,'2025-11-03'::date,'Ali','Sultan'),
(178,'Niyazi Kaba','5325136849','4532 sk no:2 d:3','izmir','altındağ','Tam Takım',1,1000,'2025-11-03'::date,'Ali','Sultan'),
(179,'Niyazi Kaba','5325136849','4532 sk no:2 d:3','izmir','altındağ','Tam Takım',1,1000,'2025-11-03'::date,'Ali','Sultan'),
(180,'Çağlar Bekinsoy','5545929160','1620/8 sk no:7 d:7 k:3','İzmir','Bayraklı','Lg Eco',1,5000,'2025-11-03'::date,'Ali','Sultan'),
(181,'Çağlar Bekinsoy','5545929160','1620/8 sk no:7 d:7 k:3','İzmir','Bayraklı','Alkali',1,1000,'2025-11-03'::date,'Ali','Sultan'),
(182,'Aysel Sarı','5053679693','1639 sk no:32 d:3','İzmir','Bayraklı','Lg Eco',2,10000,'2025-11-04'::date,'Ali','Sultan'),
(183,'Aysel Sarı','5053679693','1639 sk no:32 d:3','İzmir','Bayraklı','Alkali',1,1000,'2025-11-04'::date,'Ali','Sultan'),
(184,'Aygül Esendemir','5453313100','erzene mh istanbul cd no:23 k:1 d:3','İzmir','Bornova','Lg Eco',1,6000,'2025-11-04'::date,'Ali','Sultan'),
(185,'Aygül Esendemir','5453313100','erzene mh istanbul cd no:23 k:1 d:3','İzmir','Bornova','Alkali',1,1000,'2025-11-04'::date,'Ali','Sultan'),
(186,'Emel Mordoğan','5542747046','1643/31 sk No:6k:1 d:4','İzmir','Bayraklı','Lg Eco',1,5000,'2025-11-05'::date,'Ali','Sultan'),
(187,'Zehra Güleşçi','5315197352','2136/1 sk no:12 d:1','İzmir','Bayraklı','Tam Takım',1,1000,'2025-11-05'::date,'Ali','Sultan'),
(188,'Zehra Güleşçi','5315197352','2136/1 sk no:12 d:1','İzmir','Bayraklı','Alkali',1,1000,'2025-11-05'::date,'Ali','Sultan'),
(189,'Memet Otu','5368159823','4834 sk no:6 günaltay mh','İzmir','Karabağlar','Lg Eco',1,8000,'2025-11-05'::date,'Ali','Sultan'),
(190,'Memet Otu','5368159823','4834 sk no:6 günaltay mh','İzmir','Karabağlar','Alkali',1,2000,'2025-11-05'::date,'Ali','Sultan'),
(191,'Nursel Türker','5327424662','istiklal cd no:54 k:2 d:2','İzmir','Buca','Lg Eco',1,5000,'2025-11-05'::date,'Ali','Sultan'),
(192,'Nursel Türker','5327424662','istiklal cd no:54 k:2 d:2','İzmir','Buca','Alkali',1,1000,'2025-11-05'::date,'Ali','Sultan'),
(193,'Mehmet Bat','5314390872','1616 sk no:19 k:1 d:1','İzmir','Bayraklı','Tam Takım',1,1000,'2025-11-05'::date,'Ali','Sultan'),
(194,'Yücel Aladağ','5364358807','9300 sk no:11 d:3','İzmir','Karabağlar','Tam Takım',1,1100,'2025-11-06'::date,'Ali','Sultan'),
(195,'Muteber Dağdeviren','5386386623','9087 sk no:41 d:20','İzmir','Karabağlar','Lg Eco',1,5000,'2025-11-06'::date,'Ali','Sultan'),
(196,'Muteber Dağdeviren','5386386623','9087 sk no:41 d:20','İzmir','Karabağlar','Alkali',1,1500,'2025-11-06'::date,'Ali','Sultan'),
(197,'Gülten Şirin','5312999062','692 sk no:38 k:2 d:2','İzmir','buca','Lg Eco',2,11000,'2025-11-06'::date,'Ali','Sultan'),
(198,'Ferhat Öztürkçi','5534583449','3279 sk no:4/1 kalabak','İzmir','Urla','Lg Eco',1,7500,'2025-11-06'::date,'Ali','Sultan'),
(199,'Ferhat Öztürkçi','5534583449','3279 sk no:4/1 kalabak','İzmir','Urla','Alkali',1,1000,'2025-11-06'::date,'Ali','Sultan'),
(200,'İrfan Çakıcı','5324853296','8827 sk no:2 d:10 k:3','İzmir','Çiğli','Lg Eco',1,5500,'2025-11-06'::date,'Ali','Sultan'),
(201,'İrfan Çakıcı','5324853296','8827 sk no:2 d:10 k:3','İzmir','Çiğli','Alkali',1,1500,'2025-11-06'::date,'Ali','Sultan'),
(202,'Feruzan Kaya','5531069161','8423/1 sk no:5 d:3','İzmir','menemen','Tam Takım',1,1100,'2025-11-07'::date,'Ali','Sultan'),
(203,'Nurettin Çelik','5396250373','Hardal sk no:35 d:2','İzmir','Bornova','Membran',1,500,'2025-11-07'::date,'Ali','Sultan'),
(204,'Nurettin Çelik','5396250373','Hardal sk no:35 d:2','İzmir','Bornova','Tatlandırıcı',1,250,'2025-11-07'::date,'Ali','Sultan'),
(205,'Melek Güneş','5365516451','7733 sk no:7/1 d:7','İzmir','menemen','Tam Takım',1,1000,'2025-11-07'::date,'Ali','Sultan'),
(206,'Fidan Kaya','5352850135','Şen sk no:15 d:1','İzmir','menemen','Lg Eco',1,5500,'2025-11-07'::date,'Ali','Sultan'),
(207,'Fidan Kaya','5352850135','Şen sk no:15 d:1','İzmir','menemen','Alkali',1,1500,'2025-11-07'::date,'Ali','Sultan'),
(208,'Nejdet Aydoğan','5382007813','8929 sk no:12 k:2 d:9','İzmir','Çiğli','Lg Eco',1,5000,'2025-11-07'::date,'Ali','Sultan'),
(209,'Nejdet Aydoğan','5382007813','8929 sk no:12 k:2 d:9','İzmir','Çiğli','Alkali',1,1000,'2025-11-07'::date,'Ali','Sultan'),
(210,'Çetin Çekin','5058393636','7448/7 sk no:2/3 k:2','İzmir','Karşıyaka','Tam Takım',1,1500,'2025-11-08'::date,'Ali','Sultan'),
(211,'Halil Elhalaf','5357128289','1185/5 SK NO:16 D:2','İzmir','Konak','Lg Eco',1,5000,'2025-11-08'::date,'Ali','Sultan'),
(212,'Vedat Hark','5327668110','1762/1 sk no:1 d:4','İzmir','Karşıyaka','Lg Eco',1,7000,'2025-11-08'::date,'Ali','Sultan'),
(213,'Vedat Hark','5327668110','1762/1 sk no:1 d:4','İzmir','Karşıyaka','Alkali',1,1500,'2025-11-08'::date,'Ali','Sultan'),
(214,'Vedat Hark','5327668110','1762/1 sk no:1 d:4','İzmir','Karşıyaka','Sebil Ap.',1,1500,'2025-11-08'::date,'Ali','Sultan'),
(215,'Sevda Artan','5316612411','400 sk no:8-10 d:5','İzmir','Buca','Tam Takım',1,1100,'2025-11-10'::date,'Ali','Sultan'),
(216,'Sevda Artan','5316612411','400 sk no:8-10 d:5','İzmir','Buca','Alkali',1,100,'2025-11-10'::date,'Ali','Sultan'),
(217,'Ferdi Tarakçı','5536351586','Menderes mh 1017 sk no:31 d:1-2','İzmir','buca','Lg Eco',2,10000,'2025-11-10'::date,'Ali','Sultan'),
(218,'Sevda Artan','5531481715','186 sk no:12 d:7','İzmir','Konak','Tam Takım',1,1000,'2025-11-10'::date,'Ali','Sultan'),
(219,'Sevda Artan','5531481715','186 sk no:12 d:7','İzmir','Konak','Alkali',1,1000,'2025-11-10'::date,'Ali','Sultan'),
(220,'Ferdi Bey','5536331586','1017 sk no:31 k:1-2','İzmir','buca','Lg Eco',2,1000,'2025-11-10'::date,'Ali','Sultan'),
(221,'Muhsin Bey','5530068725','2149 sk no:28 k:3','İzmir','Bayraklı','Lg Eco',1,5500,'2025-11-10'::date,'Ali','Sultan'),
(222,'Muhsin Bey','5530068725','2149 sk no:28 k:3','İzmir','Bayraklı','Alkali',1,1500,'2025-11-10'::date,'Ali','Sultan'),
(223,'Cengiz Bey','5326907147','205/2 sk No:66/1','İzmir','buca','Tam Takım',1,1100,'2025-11-10'::date,'Ali','Sultan'),
(224,'Hulusi Bey','5052729096','1844/11 Sk No:2 D:7','İzmir','Bayraklı','Tam Takım',1,1100,'2025-11-11'::date,'Ali','Sultan'),
(225,'İbrahim Şemsit','5535147180','2133 sk no:44 k:3d:7','İzmir','Bayraklı','Tam Takım',1,1100,'2025-11-11'::date,'Ali','Sultan'),
(226,'İbrahim Şemsit','5535147180','2133 sk no:44 k:3d:7','İzmir','Bayraklı','Alkali',1,1100,'2025-11-11'::date,'Ali','Sultan'),
(227,'Aysel Uludinç','5352335901','bahriye üçak bul. No:16 d:1','İzmir','Karşıyaka','Tam Takım',1,1500,'2025-11-12'::date,'Ali','Sultan'),
(228,'Aysel Uludinç','5352335901','bahriye üçak bul. No:16 d:1','İzmir','Karşıyaka','Alkali',1,1400,'2025-11-12'::date,'Ali','Sultan'),
(229,'Bayram Yay','','Menderes mh 1152 sk no:28','İzmir','Sarnıç','Tam Takım',1,1100,'2025-11-12'::date,'Ali','Sultan'),
(230,'Önder Gürefe','5354999751','Osmangazi cd. No:41 K:5 D:19','İzmir','Bornova','Lg Eco',1,5000,'2025-11-12'::date,'Ali','Sultan'),
(231,'Nadir Benli','5323581181','7651/1 Sk No:9 D:30 K:7','İzmir','Bayraklı','Tam Takım',1,0,'2025-11-12'::date,'Ali','Sultan'),
(232,'Nuri Çiçek','5309413500','9317 sk no:3 d:25','İzmir','Karabağlar','Tam Takım',1,1000,'2025-11-13'::date,'Ali','Sultan'),
(233,'Nuri Çiçek','5309413500','9317 sk no:3 d:25','İzmir','Karabağlar','Alkali',1,1000,'2025-11-13'::date,'Ali','Sultan'),
(234,'Kadir Çelik','5073487070','131 sk no:13','İzmir','Gaziemir','Tam Takım',1,1100,'2025-11-14'::date,'Ali','Sultan'),
(235,'Kadir Çelik','5073487070','131 sk no:13','İzmir','Gaziemir','Jumber Vana',1,300,'2025-11-14'::date,'Ali','Sultan'),
(236,'Burhan Öztürk','5333306218','3570 sk no:18 d:1','İzmir','Torbalı','Lg Eco',1,5500,'2025-11-15'::date,'Ali','Sultan'),
(237,'Burhan Öztürk','5333306218','3570 sk no:18 d:1','İzmir','Torbalı','Alkali',1,1500,'2025-11-15'::date,'Ali','Sultan'),
(238,'Ahmet Ataş','5530663527','5013 sk no:11 k:4 d:7','İzmir','Torbalı','Lg Eco',1,5000,'2025-11-15'::date,'Ali','Sultan'),
(239,'Metin Baki Aysel','5424019417','Torbalı mh 5038 sk no:13 k: 4 d:7','İzmir','Torbalı','Lg Eco',1,5500,'2025-11-15'::date,'Ali','Sultan'),
(240,'Metin Baki Aysel','5424019417','Torbalı mh 5038 sk no:13 k: 4 d:7','İzmir','Torbalı','Alkali',1,1500,'2025-11-15'::date,'Ali','Sultan'),
(241,'Hüseyin Bey','5333306218','1660 Sk No:114 D:3','İzmir','Bornova','Tam Takım',1,1000,'2025-11-16'::date,'Ali','Sultan'),
(242,'Hüseyin Bey','5333306218','1660 Sk No:114 D:3','İzmir','Bornova','Alkali',1,800,'2025-11-16'::date,'Ali','Sultan'),
(243,'Aslı Erzurumlu','5335769543','1673 Sk No:32 D:3','İzmir','Karşıyaka','Tam Takım',1,1500,'2025-11-16'::date,'Ali','Sultan'),
(244,'Aslı Erzurumlu','5335769543','1673 Sk No:32 D:3','İzmir','Karşıyaka','Alkali',1,0,'2025-11-16'::date,'Ali','Sultan'),
(245,'İlhan Aydın','5323017775','6332/1 sk no:7/2 pınar mevki ormanköy','İzmir','Torbalı','Lg Eco',1,8000,'2025-11-17'::date,'Ali','Sultan'),
(246,'İlhan Aydın','5323017775','6332/1 sk no:7/2 pınar mevki ormanköy','İzmir','Torbalı','Alkali',1,1500,'2025-11-17'::date,'Ali','Sultan'),
(247,'Selçuk Aktaş','5356752673','202/26 Sk No:14 D:3','İzmir','buca','Tam Takım',2,1800,'2025-11-17'::date,'Ali','Sultan'),
(248,'Mehmet Sönmez','5059831764','220/62 sk no:20 d:2','İzmir','buca','Tam Takım',1,1100,'2025-11-17'::date,'Ali','Sultan'),
(249,'Nilüfer Bozkurt','5306961041','236 sk no:4 d:4 cengiz bulut st.','İzmir','Bayraklı','Lg Eco',1,5000,'2025-11-18'::date,'Ali','Sultan'),
(250,'Nilüfer Bozkurt','5306961041','236 sk no:4 d:4 cengiz bulut st.','İzmir','Bayraklı','Alkali',1,1000,'2025-11-18'::date,'Ali','Sultan'),
(251,'Medeni Akgün','5368621676','4958 sk no:52/1','İzmir','Karabağlar','Tam Takım',1,1100,'2025-11-18'::date,'Ali','Sultan'),
(252,'Selma Durusoy','5075240096','288/8 sk no:7 k:1 d:1','İzmir','buca','Lg Eco',1,6500,'2025-11-18'::date,'Ali','Sultan'),
(253,'Selma Durusoy','5075240096','288/8 sk no:7 k:1 d:1','İzmir','buca','Alkali',1,1300,'2025-11-18'::date,'Ali','Sultan'),
(254,'Cantürk Erbağ','5350745803','1637/10 sk no:63 k:3 d:5','İzmir','Bayraklı','Tam Takım',1,1500,'2025-11-18'::date,'Ali','Sultan'),
(255,'Cantürk Erbağ','5350745803','1637/10 sk no:63 k:3 d:5','İzmir','Bayraklı','Tank',1,2000,'2025-11-18'::date,'Ali','Sultan'),
(256,'Ali Karadoğan','5529419511','1620/11 sk no:10 d:2','İzmir','Bayraklı','Tam Takım',1,1500,'2025-11-18'::date,'Ali','Sultan'),
(257,'Behçet Özkan','5327990200','269 sk no:17 d:15','İzmir','Konak','Lg Eco',1,7500,'2025-11-19'::date,'Ali','Sultan'),
(258,'Behçet Özkan','5327990200','269 sk no:17 d:15','İzmir','Konak','Alkali',1,1250,'2025-11-19'::date,'Ali','Sultan'),
(259,'Birsoy Ocak','5379761555','33 sk no:71 d:3','İzmir','Ayrancılar','Tam Takım',1,1100,'2025-11-19'::date,'Ali','Sultan'),
(260,'Mehmet Ökde','5335653864','825 Sk No:3 d:4','İzmir','Bornova','Tam Takım',1,1100,'2025-11-19'::date,'Ali','Sultan'),
(261,'Barbaros Özcan','5321609852','155 sk no:33 d:2','İzmir','Konak','Tam Takım',1,1500,'2025-11-19'::date,'Ali','Sultan'),
(262,'Barbaros Özcan','5321609852','155 sk no:33 d:2','İzmir','Konak','Alkali',1,1500,'2025-11-19'::date,'Ali','Sultan'),
(263,'Hüseyin Barışık','5426635053','1272 sk no:6/1 d:2','İzmir','menemen','Lg Eco',1,6000,'2025-11-20'::date,'Ali','Sultan'),
(264,'Hüseyin Barışık','5426635053','1272 sk no:6/1 d:2','İzmir','menemen','Alkali',1,1500,'2025-11-20'::date,'Ali','Sultan'),
(265,'Volkan Çiftçi','5077963913','1281 sk no:33 d:2','İzmir','Menemen','Tam Takım',1,1100,'2025-11-20'::date,'Ali','Sultan'),
(266,'Gökhan Çiftçi','5459478840','1281 sk no:33 d:3','İzmir','Menemen','Tam Takım',1,1100,'2025-11-20'::date,'Ali','Sultan'),
(267,'Yonca Rukan Gargın','5304180418','Narlıdere yenikale mh gündüz sk no:3 d:3','İzmir','Narlıdere','Lg Eco',1,5500,'2025-11-21'::date,'Ali','Sultan'),
(268,'Davut Demir','5385107429','Kalabak 3267 sk no:32 d:2','İzmir','Urla','Lg Eco',1,5000,'2025-11-21'::date,'Ali','Sultan'),
(269,'Davut Demir','5385107429','Kalabak 3267 sk no:32 d:2','İzmir','Urla','Alkali',1,2000,'2025-11-21'::date,'Ali','Sultan'),
(270,'Zeynep Hanım','5363123412','İsmail Cem sk no:54 d:13','İzmir','Narlıdere','Ön Takım',1,800,'2025-11-21'::date,'Ali','Sultan'),
(271,'Hasan Hüseyin Halaç','5316678445','Erdoğan Ker sk no:120','İzmir','Urla','Tam Takım',1,1100,'2025-11-21'::date,'Ali','Sultan'),
(272,'Yılmaz Turan','5458560601','Urla sanayi sitesi içi','İzmir','Urla','Tam Takım',1,1100,'2025-11-21'::date,'Ali','Sultan'),
(273,'Yılmaz Turan','5458560601','Urla sanayi sitesi içi','İzmir','Urla','Alkali',1,1100,'2025-11-21'::date,'Ali','Sultan'),
(274,'Şerife Karasu','5542479492','Güngören cd no:29 d:9','İzmir','Narlıdere','Tam Takım',1,1100,'2025-11-21'::date,'Ali','Sultan'),
(275,'Ayhan Aynacı','5424773501','Pınarlı Sk no:6','İzmir','Urla','Tam Takım',1,1000,'2025-11-21'::date,'Ali','Sultan'),
(276,'Ayhan Aynacı','5424773501','Pınarlı Sk no:6','İzmir','Urla','Alkali',1,1000,'2025-11-21'::date,'Ali','Sultan'),
(277,'Özgün Aktepe','','357/3 sk no:5 myvia st. K:4 d:63','İzmir','Bornova','Lg Eco',1,5000,'2025-11-22'::date,'Ali','Sultan'),
(278,'Halim Demir','5442471243','1261/17 sk no:2 d:2','İzmir','Bornova','Lg Eco',1,5000,'2025-11-22'::date,'Ali','Sultan'),
(279,'Halim Demir','5442471243','1261/17 sk no:2 d:2','İzmir','Bornova','Alkali',1,1000,'2025-11-22'::date,'Ali','Sultan'),
(280,'Özgün Aktepe','','357/3 sk no:5 myvia st. K:4 d:63','İzmir','Bornova','Alkali',1,1000,'2025-11-22'::date,'Ali','Sultan'),
(281,'Birsen Bedir Akdemir','5375018637','1620/28 sk no:8 k:2 d:4','İzmir','Bayraklı','Lg Eco',1,5000,'2025-11-22'::date,'Ali','Sultan'),
(282,'Birsen Bedir Akdemir','5375018637','1620/28 sk no:8 k:2 d:4','İzmir','Bayraklı','Alkali',1,1000,'2025-11-22'::date,'Ali','Sultan'),
(283,'Murat Özarık','','694/47 sk no:4 k:3 d:15','İzmir','Buca','Tam Takım',1,1100,'2025-11-22'::date,'Ali','Sultan'),
(284,'Murat Özarık','','694/47 sk no:4 k:3 d:15','İzmir','Buca','Alkali',1,1100,'2025-11-22'::date,'Ali','Sultan'),
(285,'Hüseyin Cesur','5465178071','1582 sk no:8 d:2','İzmir','Doğanlar','Lg Eco',1,6000,'2025-11-22'::date,'Ali','Sultan'),
(286,'Hüseyin Cesur','5465178071','1582 sk no:8 d:2','İzmir','Doğanlar','Alkali',1,1000,'2025-11-22'::date,'Ali','Sultan'),
(287,'Ramazan Hundi','5325547275','668 sk no:7 k:4 d:4','İzmir','Buca','Lg Eco',1,5500,'2025-11-24'::date,'Ali','Sultan'),
(288,'Ramazan Hundi','5325547275','668 sk no:7 k:4 d:4','İzmir','Buca','Alkali',1,1500,'2025-11-24'::date,'Ali','Sultan'),
(289,'Mahmut Atlı','5322475680','46/27 sk no:30 d:14 k:8','İzmir','Karabağlar','Tam Takım',1,1100,'2025-11-24'::date,'Ali','Sultan'),
(290,'Mahmut Atlı','5322475680','46/27 sk no:30 d:14 k:8','İzmir','Karabağlar','Alkali',1,1400,'2025-11-24'::date,'Ali','Sultan'),
(291,'Yolcu Karadeniz','5462836483','1776/9 sk no:53 d:3','İzmir','Bornova','Lg Eco',1,5000,'2025-11-24'::date,'Ali','Sultan'),
(292,'Yolcu Karadeniz','5462836483','1776/9 sk no:53 d:3','İzmir','Bornova','Alkali',1,1000,'2025-11-24'::date,'Ali','Sultan'),
(293,'Asiye Gül','5442995352','1634 sk no:12 d:6','İzmir','Bayraklı','Tam Takım',1,1700,'2025-11-24'::date,'Ali','Sultan'),
(294,'Esma Gaşhi','5350279930','Yaşar Kemal mh 6002 sk no:41 d:50','İzmir','Karabağlar','Membran',1,500,'2025-11-24'::date,'Ali','Sultan'),
(295,'Esma Gaşhi','5350279930','Yaşar Kemal mh 6002 sk no:41 d:50','İzmir','Karabağlar','Tatlandırıcı',1,200,'2025-11-24'::date,'Ali','Sultan'),
(296,'Füsun Hanım','','1762/1 sk no:9 d:6','İzmir','Karşıyaka','Tam Takım',1,1100,'2025-11-25'::date,'Ali','Sultan'),
(297,'Füsun Hanım','','1762/1 sk no:9 d:6','İzmir','Karşıyaka','Alkali',1,1100,'2025-11-25'::date,'Ali','Sultan'),
(298,'Abdulbakir Atmaz','5425590705','7515 sk metokent sk 1. etap 5/B K:5 D:21','İzmir','Menemen','Lg Eco',1,5000,'2025-11-25'::date,'Ali','Sultan'),
(299,'Abdulbakir Atmaz','5425590705','7515 sk metokent sk 1. etap 5/B K:5 D:21','İzmir','Menemen','Alkali',1,1000,'2025-11-25'::date,'Ali','Sultan'),
(300,'Şehriban Çiçek','5015499881','441/2 sk no:4 d:1','İzmir','Menemen','Lg Eco',1,5500,'2025-11-25'::date,'Ali','Sultan'),
(301,'Şehriban Çiçek','5015499881','441/2 sk no:4 d:1','İzmir','Menemen','Alkali',1,1500,'2025-11-25'::date,'Ali','Sultan'),
(302,'Şehriban Çiçek','5015499881','441/2 sk no:4 d:1','İzmir','Menemen','Tam Takım',5,5000,'2025-11-25'::date,'Ali','Sultan'),
(303,'Cüneyt Arikan','5373873432','9509 sk no:4 k:5 d:42-81','İzmir','Çiğli','Lg Eco',2,12000,'2025-11-25'::date,'Ali','Sultan'),
(304,'Cüneyt Arikan','5373873432','9509 sk no:4 k:5 d:42-81','İzmir','Çiğli','Alkali',2,3000,'2025-11-25'::date,'Ali','Sultan'),
(305,'Cüneyt Arikan','5373873432','9509 sk no:4 k:5 d:42-81','İzmir','Çiğli','Tam Takım',5,5000,'2025-11-25'::date,'Ali','Sultan'),
(306,'Mualla Madanlar','5057152530','659 sk no:4 d:10 k:4','izmir','Gaziemir','Tam Takım',1,1200,'2025-11-26'::date,'Ali','Sultan'),
(307,'Mualla Madanlar','5057152530','659 sk no:4 d:10 k:4','izmir','Gaziemir','Alkali',1,1200,'2025-11-26'::date,'Ali','Sultan'),
(308,'Hakim Erkan','5447195839','1641 sk no:62 d:3 k:1','İzmir','Bayraklı','Lg Eco',1,5000,'2025-11-26'::date,'Ali','Sultan'),
(309,'Hakim Erkan','5447195839','1641 sk no:62 d:3 k:1','İzmir','Bayraklı','Alkali',1,1000,'2025-11-26'::date,'Ali','Sultan'),
(310,'Sakine Batak','5011685030','203/3 sk no:14/1','İzmir','Buca','Lg Eco',1,6000,'2025-11-26'::date,'Ali','Sultan'),
(311,'Sakine Batak','5011685030','203/3 sk no:14/1','İzmir','Buca','Alkali',1,1000,'2025-11-26'::date,'Ali','Sultan'),
(312,'Nuri Nuray Dengiz','5533210773','Efes 3 17/18 giriş k:4 d:4','İzmir','Karşıyaka','Lg Eco',1,5000,'2025-11-26'::date,'Ali','Sultan'),
(313,'Nuri Nuray Dengiz','5533210773','Efes 3 17/18 giriş k:4 d:4','İzmir','Karşıyaka','Alkali',1,1000,'2025-11-26'::date,'Ali','Sultan'),
(314,'Nuri Nuray Dengiz','5533210773','Efes 3 17/18 giriş k:4 d:4','İzmir','Karşıyaka','Tam Takım',1,5000,'2025-11-26'::date,'Ali','Sultan'),
(315,'Necdet Bayrakçı','5452682264','931 sk no:14','İzmir','Bornova','Tam Takım',1,1100,'2025-11-27'::date,'Ali','Sultan'),
(316,'Cengiz Özyürek','5386973007','Esentepe mh Mimkent st. 46/25 sk No:20 D:10','İzmir','Karabağlar','Tam Takım',1,1100,'2025-11-27'::date,'Ali','Sultan'),
(317,'Cengiz Özyürek','5386973007','Esentepe mh Mimkent st. 46/25 sk No:20 D:10','İzmir','Karabağlar','Alkali',1,1500,'2025-11-27'::date,'Ali','Sultan'),
(318,'Kenan Ağır','5542221617','7163 Sk No:25 K:2','İzmir','Bayraklı','Lg Eco',1,5000,'2025-11-27'::date,'Ali','Sultan'),
(319,'Alev Ayşe Tayşi','5375722685','190 sk No:4 D:15','İzmir','Konak','Tam Takım',1,1100,'2025-11-27'::date,'Ali','Sultan'),
(320,'Zeki Altun','5372433304','Camikabir mh. 97 sk no:16 d:5','İzmir','Seferihisar','Tam Takım',1,1100,'2025-11-28'::date,'Ali','Sultan'),
(321,'Necati Onur','5347105497','15 sk no:11','İzmir','Seferihisar','Tam Takım',1,1500,'2025-11-28'::date,'Ali','Sultan'),
(322,'Halit Ziya Demircioğlu','5386331444','61 sk no:18','İzmir','Bornova','Tam Takım',3,3000,'2025-11-28'::date,'Ali','Sultan'),
(323,'Habibe Akdemir','5546416796','92/1 sk no:12/2','İzmir','Seferihisar','Tam Takım',1,1100,'2025-11-28'::date,'Ali','Sultan'),
(324,'Ufuk Nalbant','5327965091','128 sk no:22 d:4','İzmir','Buca','Lg Eco',1,8000,'2025-11-30'::date,'Ali','Sultan'),
(325,'Ufuk Nalbant','5327965091','128 sk no:22 d:4','İzmir','Buca','Alkali',1,2000,'2025-11-30'::date,'Ali','Sultan'),
(326,'Taner Koşak','5555116045','7122/1 sk no:17','İzmir','Bayraklı','Tam Takım',1,1100,'2025-11-30'::date,'Ali','Sultan'),
(327,'Mehmet Türkeş','5358759932','4145 sk no:6 k:1 d:2','İzmir','Bornova','Lg Eco',1,5000,'2025-11-30'::date,'Ali','Sultan'),
(328,'Mehmet Türkeş','5358759932','4145 sk no:6 k:1 d:2','İzmir','Bornova','Alkali',1,1000,'2025-11-30'::date,'Ali','Sultan'),
(329,'İkran Öztunç','5434291123','292/21 sk no:20 d:1','İzmir','Buca','Arıza',1,0,'2025-11-30'::date,'Ali','Sultan'),
(330,'Hakime Yeşilyurt','5372439275','220/12 sk no:7 k:3','İzmir','Buca','Tam Takım',1,1000,'2025-11-30'::date,'Ali','Sultan'),
(331,'Naci Çelik','5433639121','694/39 sk no:2','İzmir','Buca','Tam Takım',1,1100,'2025-11-30'::date,'Ali','Sultan'),
(332,'Recep Sarı','','110 sk no:19 d:2','İzmir','Buca','Tam Takım',1,1100,'2025-11-30'::date,'Ali','Sultan'),
(333,'Recep Sarı','','110 sk no:19 d:2','İzmir','Buca','Montaj',1,800,'2025-11-30'::date,'Ali','Sultan'),
(334,'Sezer Susam','','47 SK No:14 D:10','İzmir','Ayrancılar','Lg Eco',1,4500,'2025-11-30'::date,'Ali','Sultan'),
(335,'Sezer Susam','','47 SK No:14 D:10','İzmir','Ayrancılar','Alkali',1,1000,'2025-11-30'::date,'Ali','Sultan'),
(336,'Zühre Kale','','204/2 sk no:37 k:2/3','İzmir','Buca','Tam Takım',2,2100,'2025-12-01'::date,'Ali','Sultan'),
(337,'Zühre Kale','','204/2 sk no:37 k:2/3','İzmir','Buca','Alkali',1,1000,'2025-12-01'::date,'Ali','Sultan'),
(338,'Halime Kaya','5333086961','430 sk no:26','İzmir','Konak','Lg Eco',1,5000,'2025-12-01'::date,'Ali','Sultan'),
(339,'Halime Kaya','5333086961','430 sk no:26','İzmir','Konak','Alkali',1,1500,'2025-12-01'::date,'Ali','Sultan'),
(340,'Muhammed Ali Akyol','5336852002','Torbalı mh 5139/9 sk No:2 D:17','İzmir','Torbalı','Lg Eco',1,7000,'2025-12-01'::date,'Ali','Sultan'),
(341,'Muhammed Ali Akyol','5336852002','Torbalı mh 5139/9 sk No:2 D:17','İzmir','Torbalı','Alkali',1,1000,'2025-12-01'::date,'Ali','Sultan'),
(342,'Engin Tükenmez','','Naci Tuncel cd. No:41 C K:4 D:19','İzmir','Torbalı','Tam Takım',1,1100,'2025-12-01'::date,'Ali','Sultan'),
(343,'Orhan Aktaş','5314290977','5596 sk no:30 d:1','İzmir','Torbalı','Tam Takım',1,1100,'2025-12-01'::date,'Ali','Sultan'),
(344,'Sebahattin Bulut','5314836830','1496 sk no:6 d:1','İzmir','Bornova','Tam Takım',1,1100,'2025-12-01'::date,'Ali','Sultan'),
(345,'Sebahattin Bulut','5314836830','1496 sk no:6 d:1','İzmir','Bornova','Alkali',1,1100,'2025-12-01'::date,'Ali','Sultan'),
(346,'Fahrettin Çamdalı','5359768067','Mehmet Akif Ersoy sk no:6 d:3','İzmir','Balçova','Lg Eco',1,5500,'2025-12-02'::date,'Ali','Sultan'),
(347,'Fahrettin Çamdalı','5359768067','Mehmet Akif Ersoy sk no:6 d:3','İzmir','Balçova','Alkali',1,1500,'2025-12-02'::date,'Ali','Sultan'),
(348,'Sami Güldağlar','5355285388','Yamaç sk no:7 d:4','İzmir','Balçova','Tam Takım',1,1200,'2025-12-02'::date,'Ali','Sultan'),
(349,'Sadık eytünlü','5378771070','3947/2 sk no:15/1 d:3','İzmir','Karabağlar','Tam Takım',1,1100,'2025-12-02'::date,'Ali','Sultan'),
(350,'Bekir Seyyar','5334061130','1776/14 sk no:3','İzmir','Bornova','Tam Takım',1,1100,'2025-12-02'::date,'Ali','Sultan'),
(351,'Durmuş Faydalı','5323569504','7412 sk no:64','İzmir','Bornova','Tam Takım',1,1000,'2025-12-02'::date,'Ali','Sultan'),
(352,'Birgül Kavak','5050574253','4509 sk no:6 d:1','İzmir','Altındağ','Lg Eco',1,5000,'2025-12-02'::date,'Ali','Sultan'),
(353,'Birgül Kavak','5050574253','4509 sk no:6 d:1','İzmir','Altındağ','Alkali',1,1000,'2025-12-02'::date,'Ali','Sultan'),
(354,'Orhan Çetinkaya','5343807166','8809/10 sk no:6 k:7 d:27','İzmir','Çiğli','Tam Takım',1,1100,'2025-12-03'::date,'Ali','Sultan'),
(355,'Aslı Türe','5352180319','8819 sk no:27 k:6 d:13','İzmir','Çiğli','Ao Smith',1,0,'2025-12-03'::date,'Ali','Sultan'),
(356,'Aslı Türe','5352180319','8819 sk no:27 k:6 d:13','İzmir','Çiğli','Üç Yollu Musluk',1,0,'2025-12-03'::date,'Ali','Sultan'),
(357,'Lütfiye Şayir Karaçam','5324266600','8950/3 sk no:1 Begonvil Evleri k:4 d:20','İzmir','Çiğli','Tam Takım',1,11000,'2025-12-03'::date,'Ali','Sultan'),
(358,'Lütfiye Şayir Karaçam','5324266600','8950/3 sk no:1 Begonvil Evleri k:4 d:20','İzmir','Çiğli','Alkali',1,1100,'2025-12-03'::date,'Ali','Sultan'),
(359,'Nesrin Şeyhoğlu','','5. cad. no:34 Yaylapark st. K:1 d:7','İzmir','Menemen','Tam Takım',1,1100,'2025-12-03'::date,'Ali','Sultan'),
(360,'Nesrin Şeyhoğlu','','5. cad. no:34 Yaylapark st. K:1 d:7','İzmir','Menemen','Alkali',1,1100,'2025-12-03'::date,'Ali','Sultan'),
(361,'Ali İhsan Yelken','5357919950','7117 sk no:3/B D:5 K:2','İzmir','Menemen','Lg Eco',1,5500,'2025-12-03'::date,'Ali','Sultan'),
(362,'Ali İhsan Yelken','5357919950','7117 sk no:3/B D:5 K:2','İzmir','Menemen','Alkali',1,1500,'2025-12-03'::date,'Ali','Sultan'),
(363,'Ali Ekber Beyazgül','5387834130','8087/10 sk no:13 d:2','İzmir','Çiğli','Lg Eco',1,5500,'2025-12-03'::date,'Ali','Sultan'),
(364,'Ali Ekber Beyazgül','5387834130','8087/10 sk no:13 d:2','İzmir','Çiğli','Alkali',1,1500,'2025-12-03'::date,'Ali','Sultan'),
(365,'Turgay Kolay','5373827853','218 sk no:10/A D:5','İzmir','Kemalpasa','Tam Takım',1,1100,'2025-12-04'::date,'Ali','Sultan'),
(366,'Turgay Kolay','5373827853','218 sk no:10/A D:5','İzmir','Kemalpasa','Alkali',1,1100,'2025-12-04'::date,'Ali','Sultan'),
(367,'Nuray Yılmazer','5396724761','Hürriyet mh. Mersin sk. No:10 K:3 D:7','İzmir','Gaziemir','Tam Takım',1,1500,'2025-12-04'::date,'Ali','Sultan'),
(368,'Sedat Yılmazer','5389897032','Dereli sk. No:20 d:1 Armutlu','İzmir','Kemalpasa','Tam Takım',1,1500,'2025-12-04'::date,'Ali','Sultan'),
(369,'Yaşar Yeşilyurt','5305206574','Atatürk mh. Dr. Fikret Baycan Cd. No:54 D:2','İzmir','Kemalpasa','Tam Takım',1,1100,'2025-12-04'::date,'Ali','Sultan'),
(370,'Yaşar Yeşilyurt','5305206574','Atatürk mh. Dr. Fikret Baycan Cd. No:54 D:2','İzmir','Kemalpasa','Alkali',1,1100,'2025-12-04'::date,'Ali','Sultan'),
(371,'Haydar Atalay','5445788746','Atatürk mh. 50 sk. No:6','İzmir','Kemalpasa','Tam Takım',1,1000,'2025-12-04'::date,'Ali','Sultan'),
(372,'Haydar Atalay','5445788746','Atatürk mh. 50 sk. No:6','İzmir','Kemalpasa','Alkali',1,1000,'2025-12-04'::date,'Ali','Sultan'),
(373,'Perihan Aygören','5366966281','81/1 sk no:14/8','İzmir','Kemalpasa','Tam Takım',1,1100,'2025-12-04'::date,'Ali','Sultan'),
(374,'Perihan Aygören','5366966281','81/1 sk no:14/8','İzmir','Kemalpasa','Alkali',1,1100,'2025-12-04'::date,'Ali','Sultan'),
(375,'Rojin Ariz','5453537035','4187 sk no:17 d:3','İzmir','Karabağlar','Tam Takım',1,1100,'2025-12-05'::date,'Ali','Sultan'),
(376,'Süheyla Aybastı','5352555638','52/75 sk no:17 d:20 k:-2','İzmir','Karabağlar','Tam Takım',1,1000,'2025-12-05'::date,'Ali','Sultan'),
(377,'Süheyla Aybastı','5352555638','52/75 sk no:17 d:20 k:-2','İzmir','Karabağlar','Alkali',1,1000,'2025-12-05'::date,'Ali','Sultan'),
(378,'Arzu Özçelik','5304041034','Kahramanlar cad. No:6/1','İzmir','Gaziemir','Tam Takım',1,1100,'2025-12-05'::date,'Ali','Sultan'),
(379,'Kudret Aktaş','5336924918','Menderes mh. 1009 sk. No:7 D:3 K:3','İzmir','Buca','Tam Takım',2,2200,'2025-12-05'::date,'Ali','Sultan'),
(380,'Neslihan Kıvrık','5443011687','Laleli mh. Menderes cdç No:378 K:3 D:6','İzmir','Buca','Lg Eco',1,5500,'2025-12-05'::date,'Ali','Sultan'),
(381,'Neslihan Kıvrık','5443011687','Laleli mh. Menderes cdç No:378 K:3 D:6','İzmir','Buca','Alkali',1,1500,'2025-12-05'::date,'Ali','Sultan'),
(382,'Muhittin Taş','5066872657','1651/16 sk no:81 d:5','İzmir','Karşıyaka','Tam Takım',1,1100,'2025-12-05'::date,'Ali','Sultan'),
(383,'Yıldırım Acar','5539642803','4655/1 sk no:10 d:2','İzmir','Karabağlar','Tam Takım',1,1100,'2025-12-05'::date,'Ali','Sultan'),
(384,'ali osman gürbüz','5324211058','7298 sk. No:10 d:2','İzmir','Karşıyaka','Lg Eco',1,7000,'2025-12-06'::date,'Ali','Sultan'),
(385,'Mahmut Efetürk','5355532617','Akarcalı mh 1090 sk no:35','İzmir','Konak','Tam Takım',1,1100,'2025-12-06'::date,'Ali','Sultan'),
(386,'Hikmet Hışır','5345279441','3876 sk no:107','İzmir','Karabağlar','Tam Takım',1,1000,'2025-12-06'::date,'Ali','Sultan'),
(387,'Hikmet Hışır','5345279441','3876 sk no:107','İzmir','Karabağlar','Alkali',1,1000,'2025-12-06'::date,'Ali','Sultan'),
(388,'Hülya Cici','5304144017','219 sk no:2 kemalpasa mh. K:4 d:14','İzmir','Menderes','Tam Takım',1,1100,'2025-12-06'::date,'Ali','Sultan'),
(389,'Halil Karakoç','5070273117','Ziya Gökalp cd. No:34 K:1 D:1','İzmir','Bornova','Tam Takım',1,1100,'2025-12-06'::date,'Ali','Sultan'),
(390,'Ahmet Honça','5364659135','916 sk no:25 d:5','İzmir','Buca','Lg Eco',1,6500,'2025-12-06'::date,'Ali','Sultan'),
(391,'Ahmet Honça','5364659135','916 sk no:25 d:5','İzmir','Buca','Alkali',2,2500,'2025-12-06'::date,'Ali','Sultan'),
(392,'Ahmet Honça','5364659135','916 sk no:25 d:5','İzmir','Buca','Tam Takım',1,1000,'2025-12-06'::date,'Ali','Sultan'),
(393,'Serhat Özak - Kudret Bey','5304054041','1013 sk no:23 İnönü mah Bornova','İzmir','Bornova','Tatlandırıcı',1,0,'2025-12-06'::date,'Ali','Sultan'),
(394,'Serhat Özak - Kudret Bey','5304054041','1013 sk no:23 İnönü mah Bornova','İzmir','Bornova','Membran',1,0,'2025-12-06'::date,'Ali','Sultan'),
(395,'Arife Baykal','5352118200','1733/1 sk no:8 inönü mh','İzmir','Karşıyaka','Tam Takım',1,2000,'2025-12-06'::date,'Ali','Sultan'),
(396,'Senem Şen','','Ulvi Başbay sk no:15 d:3','İzmir','Karşıyaka','Tam Takım',1,1100,'2025-12-06'::date,'Ali','Sultan'),
(397,'Senem Şen','','Ulvi Başbay sk no:15 d:3','İzmir','Karşıyaka','Alkali',1,1000,'2025-12-06'::date,'Ali','Sultan'),
(398,'Selin Keskin Vural','5319422425','7379/3 sk no:2 k:2 d:22','İzmir','Bayraklı','Ao Smith',0,0,'2025-12-08'::date,'Ali','Sultan'),
(399,'Süleyman Ufaklı','5324223448','323 sk no:2/C','İzmir','Konak','Lg Eco',1,6500,'2025-12-08'::date,'Ali','Sultan'),
(400,'Süleyman Ufaklı','5324223448','323 sk no:2/C','İzmir','Konak','Alkali',1,1500,'2025-12-08'::date,'Ali','Sultan'),
(401,'İlyas Ekinci','5366792144','556 sk no:3 k:5 d:9','İzmir','Buca','Lg Eco',1,8000,'2025-12-08'::date,'Ali','Sultan'),
(402,'İlyas Ekinci','5366792144','556 sk no:3 k:5 d:9','İzmir','Buca','Alkali',1,2000,'2025-12-08'::date,'Ali','Sultan'),
(403,'Güler Günedak','5013171162','1617 sk no:10 k:4 d:7','İzmir','Bayraklı','Tam Takım',1,1100,'2025-12-08'::date,'Ali','Sultan'),
(404,'Serhat Payçu','5326574827','7356/4 sk no:19 d:1','İzmir','Bayraklı','Tam Takım',1,1100,'2025-12-08'::date,'Ali','Sultan'),
(405,'Ahmet Çimen','5383215830','236 sk no:87 d:7','İzmir','Karabağlar','Tam Takım',1,1100,'2025-12-08'::date,'Ali','Sultan'),
(406,'Neval Ayvalı','5377486450','1163 sk no:54 k:1 d:1','İzmir','Konak','Tam Takım',1,1100,'2025-12-08'::date,'Ali','Sultan'),
(407,'Zeynep Oral','5373942722','984 sk no:19 d:3','izmir','Bornova','Tam Takım',1,1100,'2025-12-09'::date,'Ali','Sultan'),
(408,'Filiz Öztopçu','5307812688','206/41 sk no:14 d:1','İzmir','Buca','Tam Takım',1,1300,'2025-12-09'::date,'Ali','Sultan'),
(409,'İsmail Hakkı Tutar','5055073596','Zübeyde hanım mh 7448/11 sk no:4B K:3','İzmir','Karşıyaka','Lg Eco',1,8000,'2025-12-09'::date,'Ali','Sultan'),
(410,'İsmail Hakkı Tutar','5055073596','Zübeyde hanım mh 7448/11 sk no:4B K:3','İzmir','Karşıyaka','Alkali',1,2000,'2025-12-09'::date,'Ali','Sultan'),
(411,'Melina Naimi','5538301341','6405 sk no:4 k:1 d:6','İzmir','Karşıyaka','Tam Takım',1,0,'2025-12-09'::date,'Ali','Sultan'),
(412,'Manolya Köroğlu','5072542660','Yavuz sultan selim cd Gaziler mh. 1085 sk no:13 k:5 d:15','İzmir','Buca','Lg Eco',2,11000,'2025-12-10'::date,'Ali','Sultan'),
(413,'Manolya Köroğlu','5072542660','Yavuz sultan selim cd Gaziler mh. 1085 sk no:13 k:5 d:15','İzmir','Buca','Alkali',2,3000,'2025-12-10'::date,'Ali','Sultan'),
(414,'Yasemin Çağlı','5367284218','3996/4 sk no:23','İzmir','Karabağlar','Tam Takım',1,1100,'2025-12-10'::date,'Ali','Sultan'),
(415,'Yasemin Çağlı','5367284218','3996/4 sk no:23','İzmir','Karabağlar','Alkali',1,1100,'2025-12-10'::date,'Ali','Sultan'),
(416,'Kürşat Uysal','5053430816','Manavkuyu mh. 249/5 sk no:5 d:6','İzmir','Bayraklı','Lg Eco',1,5500,'2025-12-10'::date,'Ali','Sultan'),
(417,'Kürşat Uysal','5053430816','Manavkuyu mh. 249/5 sk no:5 d:6','İzmir','Bayraklı','Alkali',1,1500,'2025-12-10'::date,'Ali','Sultan'),
(418,'Bülent Uluğ','5555978486','Göksu mh. 649/1 sk. No:35/37 k:3 d:3','İzmir','Buca','Tam Takım',1,1000,'2025-12-10'::date,'Ali','Sultan'),
(419,'Gülsüm Dağdibi','5433165917','2095/2 sk no:7 d:7','İzmir','Bayraklı','Tam Takım',1,1100,'2025-12-10'::date,'Ali','Sultan'),
(420,'Mustafa Gargın','5325827118','Yenikale mh. Getaş 2 st. A blok 3/3 K:1 D:3','İzmir','Narlıdere','Alkali',1,1500,'2025-12-11'::date,'Ali','Sultan'),
(421,'Mustafa Köklüoğlu','5327839620','2282 sk no:4 d:8','İzmir','Güzelbahçe','Tam Takım',1,1200,'2025-12-11'::date,'Ali','Sultan'),
(422,'Mustafa Köklüoğlu','5327839620','2282 sk no:4 d:8','İzmir','Güzelbahçe','Alkali',1,1000,'2025-12-11'::date,'Ali','Sultan'),
(423,'Mustafa Topuz','5375462534','Atatürk mh. 708 sk No:10','İzmir','Güzelbahçe','Tam Takım',1,1100,'2025-12-11'::date,'Ali','Sultan'),
(424,'Serhat Demiray','5322311511','Yelki mh. Namık Elac Cd. No:32','İzmir','Güzelbahçe','Tam Takım',1,1100,'2025-12-11'::date,'Ali','Sultan'),
(425,'Ümit Büyükbalbak','5325674863','Ali özütemiz sk no:3 d:3','İzmir','Narlıdere','Tam Takım',1,1100,'2025-12-11'::date,'Ali','Sultan'),
(426,'Leyla Kasap','5548704648','Aras sk. No:12 D:9','İzmir','Narlıdere','Tam Takım',1,1500,'2025-12-11'::date,'Ali','Sultan'),
(427,'Naciye Çavdar','5070493069','53 Sk. No:15 D:9','İzmir','Ayrancılar','Tam Takım',1,1100,'2025-12-15'::date,'Ali','Sultan'),
(428,'Feridun Gedikçi','5530621005','İnönü Mh. 147 Sk. No:2 D:14','İzmir','Ayrancılar','Tam Takım',1,1000,'2025-12-15'::date,'Ali','Sultan'),
(429,'Ahmet Serbest','5375607841','5226 Sk. No:19 K:2 Çamdibi','İzmir','Bornova','Tam Takım',2,3000,'2025-12-15'::date,'Ali','Sultan'),
(430,'Ahmet Serbest','5375607841','5226 Sk. No:19 K:2 Çamdibi','İzmir','Bornova','Lg Eco',1,5500,'2025-12-15'::date,'Ali','Sultan'),
(431,'Ahmet Serbest','5375607841','5226 Sk. No:19 K:2 Çamdibi','İzmir','Bornova','Alkali',1,1500,'2025-12-15'::date,'Ali','Sultan'),
(432,'Sait Yanar','5323489258','Atıf Bey Mh. 6 Sk. No: 69 D: 13 K: 1','İzmir','Gaziemir','Tam Takım',1,1100,'2025-12-15'::date,'Ali','Sultan'),
(433,'Caner Dağdeviren','5556203401','Gazi Mh. Albay İbrahim Karacaoğlanoğlu Cd. No:57 K:1 D:5','İzmir','Gaziemir','Tam Takım',1,1400,'2025-12-15'::date,'Ali','Sultan'),
(434,'Soner Çoban','5321654435','52/29 Sk. No:7 K:4 D:4','İzmir','Karabağlar','Tam Takım',1,1100,'2025-12-15'::date,'Ali','Sultan'),
(435,'Naile Açar','5065352609','173/1 Sk. No:8/1 D:2','İzmir','Karabağlar','Tam Takım',1,1000,'2025-12-15'::date,'Ali','Sultan'),
(436,'Naile Açar','5065352609','173/1 Sk. No:8/1 D:2','İzmir','Karabağlar','Alkali',1,1000,'2025-12-15'::date,'Ali','Sultan'),
(437,'İdris Bayar','5468579088','Hava Eğitim Lojmanları','İzmir','Karabağlar','Tam Takım',1,1100,'2025-12-15'::date,'Ali','Sultan'),
(438,'Dudu Duygu Aydın','5054813310','Muammer Acar Mh. 45/2 Sk. No:4 D:4','İzmir','Karabağlar','Lg Eco',1,6000,'2025-12-15'::date,'Ali','Sultan'),
(439,'Dudu Duygu Aydın','5054813310','Muammer Acar Mh. 45/2 Sk. No:4 D:4','İzmir','Karabağlar','Alkali',1,2000,'2025-12-15'::date,'Ali','Sultan'),
(440,'Emine Dabakan','5347918551','Kılıçreis mh. 319 Sk. No: 33 K:3 D:4','İzmir','Konak','Lg Eco',1,6000,'2025-12-15'::date,'Ali','Sultan'),
(441,'Emine Dabakan','5347918551','Kılıçreis mh. 319 Sk. No: 33 K:3 D:4','İzmir','Konak','Alkali',1,2000,'2025-12-15'::date,'Ali','Sultan'),
(442,'Kadriye Cesur','5465178073','1582 Sk. No:8 D:1 Doğanlar','İzmir','Bornova','Tam Takım',1,1100,'2025-12-16'::date,'Ali','Sultan'),
(443,'Kadriye Cesur','5465178073','1582 Sk. No:8 D:1 Doğanlar','İzmir','Bornova','Montaj',1,800,'2025-12-16'::date,'Ali','Sultan'),
(444,'Nasif Üçoğlu','5060390751','4016/2 Sk No:2 D:2','İzmir','Bornova','Tam Takım',1,1100,'2025-12-16'::date,'Ali','Sultan'),
(445,'Ahmet Koç','5053793102','156 Sk No:15 D:5','İzmir','Buca','Tam Takım',1,1100,'2025-12-16'::date,'Ali','Sultan'),
(446,'Ahmet Koç','5053793102','156 Sk No:15 D:5','İzmir','Buca','Alkali',1,1100,'2025-12-16'::date,'Ali','Sultan'),
(447,'Orkun Sol','5334810004','Güzelyurt Cd. No:8 D: 2','İzmir','Karabağlar','Tam Takım',1,1100,'2025-12-16'::date,'Ali','Sultan'),
(448,'Orkun Sol','5334810004','Güzelyurt Cd. No:8 D: 2','İzmir','Karabağlar','Musluk',1,900,'2025-12-16'::date,'Ali','Sultan'),
(449,'Orkun Sol','5334810004','Güzelyurt Cd. No:8 D: 2','İzmir','Karabağlar','Alkali',1,1100,'2025-12-16'::date,'Ali','Sultan'),
(450,'Murat Ceylanlı','5524452468','2468 Sk. No:10 K:1 D:1','İzmir','Gültepe','Tam Takım',1,1100,'2025-12-16'::date,'Ali','Sultan'),
(451,'Mesut Kuş','5304059513','Karacaoğlan Mh. 6245 Sk. No:18 D:2 K:3','İzmir','Bornova','Lg Eco',1,5000,'2025-12-16'::date,'Ali','Sultan'),
(452,'Mesut Kuş','5304059513','Karacaoğlan Mh. 6245 Sk. No:18 D:2 K:3','İzmir','Bornova','Alkali',1,1500,'2025-12-16'::date,'Ali','Sultan'),
(453,'Mustafa Dağkır','5364877721','4102 sk No:2 D:1 Zemin Kat','İzmir','Karabağlar','Tam Takım',1,1800,'2025-12-17'::date,'Ali','Sultan'),
(454,'Mustafa Dağkır','5364877721','4102 sk No:2 D:1 Zemin Kat','İzmir','Karabağlar','Alkali',1,1000,'2025-12-17'::date,'Ali','Sultan'),
(455,'Saime Özdemir','5317888188','2. inönü mh. Manzara sk. No:10','İzmir','Narlıdere','Lg Eco',1,5000,'2025-12-17'::date,'Ali','Sultan'),
(456,'Saime Özdemir','5317888188','2. inönü mh. Manzara sk. No:10','İzmir','Narlıdere','Alkali',1,1000,'2025-12-17'::date,'Ali','Sultan'),
(457,'Nevin Ercan','5557375797','Atatürk mh. 2036 sk No:29/1','İzmir','Urla','Tam Takım',1,1100,'2025-12-17'::date,'Ali','Sultan'),
(458,'Nevin Ercan','5557375797','Atatürk mh. 2036 sk No:29/1','İzmir','Urla','Montaj',1,800,'2025-12-17'::date,'Ali','Sultan'),
(459,'Abdullah Ayçu','5326574827','90 Sk No:15/2 Denizli Mh.','İzmir','Urla','Tam Takım',1,1100,'2025-12-17'::date,'Ali','Sultan'),
(460,'Esat Eskin','5386560540','2. Dere Sk. No:7A','İzmir','Urla','Membran',1,500,'2025-12-17'::date,'Ali','Sultan'),
(461,'Esat Eskin','5386560540','2. Dere Sk. No:7A','İzmir','Urla','Tatlandırıcı',1,250,'2025-12-17'::date,'Ali','Sultan'),
(462,'Veysel Bircan','5337648456','2. İnönü Mh. Altınvadi Cd. No:61 D:3','İzmir','Narlıdere','Lg Eco',1,6000,'2025-12-17'::date,'Ali','Sultan'),
(463,'Veysel Bircan','5337648456','2. İnönü Mh. Altınvadi Cd. No:61 D:3','İzmir','Narlıdere','Alkali',1,2000,'2025-12-17'::date,'Ali','Sultan'),
(464,'Yasemin Akgün','5437950035','396 Sk. No:9 K:3 D:3','İzmir','Buca','Tam Takım',1,1100,'2025-12-18'::date,'Ali','Sultan'),
(465,'Yaşar Değirmencioğlu','5375118342','1306 Sk. No:14 K:2 D:5 İzkent','İzmir','Buca','Lg Eco',1,6000,'2025-12-18'::date,'Ali','Sultan'),
(466,'Yaşar Değirmencioğlu','5375118342','1306 Sk. No:14 K:2 D:5 İzkent','İzmir','Buca','Alkali',1,2000,'2025-12-18'::date,'Ali','Sultan'),
(467,'Battal Yiğit','5358672859','1637/16 Sk. No:35 K:1 D:1','İzmir','Bayraklı','Lg Eco',1,4000,'2025-12-18'::date,'Ali','Sultan'),
(468,'Battal Yiğit','5358672859','1637/16 Sk. No:35 K:1 D:1','İzmir','Bayraklı','Alkali',1,1000,'2025-12-18'::date,'Ali','Sultan'),
(469,'Neslihan Şanlı','5393745382','28/3 Sk No:57 D:3','İzmir','Buca','Tam Takım',1,1100,'2025-12-18'::date,'Ali','Sultan'),
(470,'Neslihan Şanlı','5393745382','28/3 Sk No:57 D:3','İzmir','Buca','Alkali',1,1100,'2025-12-18'::date,'Ali','Sultan'),
(471,'Tayyar Yargıç','5344381828','Adnan Kahveci Cd. No:19 D:8','İzmir','Buca','Tam Takım',1,1100,'2025-12-18'::date,'Ali','Sultan'),
(472,'Arif Çoruk','5052302357','Adnan Kahveci Cd. No:137/2 D:11','İzmir','Buca','Tam Takım',1,1100,'2025-12-18'::date,'Ali','Sultan'),
(473,'Sabit Usluk','5357124292','6017 Sk. No:24 D:2','İzmir','Karşıyaka','Tam Takım',1,1100,'2025-12-19'::date,'Ali','Sultan'),
(474,'Ünsal Kelleci','5326132655','Yalı Mh 6421 Sk. No:10 D:5 K:4','İzmir','Karşıyaka','Lg Eco',1,12000,'2025-12-19'::date,'Ali','Sultan'),
(475,'Ünsal Kelleci','5326132655','Yalı Mh 6421 Sk. No:10 D:5 K:4','İzmir','Karşıyaka','Alkali',1,3000,'2025-12-19'::date,'Ali','Sultan'),
(476,'Yasemin Yıldızkol','5063060730','Zübeyde Hanım Cd. No:90 D:4','İzmir','Karşıyaka','Lg Eco',1,8000,'2025-12-19'::date,'Ali','Sultan'),
(477,'Yasemin Yıldızkol','5063060730','Zübeyde Hanım Cd. No:90 D:4','İzmir','Karşıyaka','Alkali',1,2000,'2025-12-19'::date,'Ali','Sultan'),
(478,'Yasemin Yıldızkol','5063060730','Zübeyde Hanım Cd. No:90 D:4','İzmir','Karşıyaka','Tam Takım',1,1000,'2025-12-19'::date,'Ali','Sultan'),
(479,'Adem Balıkçı','5071689737','293/1 Sk. No:11 K:3 D:3','İzmir','Buca','Tam Takım',1,1100,'2025-12-19'::date,'Ali','Sultan'),
(480,'Ümit Çavuşoğlu','5324939926','510 Sk. No:27/A','İzmir','Buca','Tam Takım',2,2200,'2025-12-19'::date,'Ali','Sultan'),
(481,'Ümit Çavuşoğlu','5324939926','510 Sk. No:27/A','İzmir','Buca','Alkali',1,1100,'2025-12-19'::date,'Ali','Sultan'),
(482,'Serdar Uysal','5335783345','108/18 Sk. No:2 D:1','İzmir','Karabağlar','Musluk',1,0,'2025-12-19'::date,'Ali','Sultan'),
(483,'Pınar Öden','5524201252','8756 Sk. No:13 D:2 Rıfkı Keskin Apt','İzmir','Çiğli','Lg Eco',1,12000,'2025-12-20'::date,'Ali','Sultan'),
(484,'Pınar Öden','5524201252','8756 Sk No:13 D:2 Rıfkı Keskin Apt','İzmir','Çiğli','Alkali',1,3000,'2025-12-20'::date,'Ali','Sultan'),
(485,'Müslüm Yılmaz','5456200386','7303 Sk. 1. Cadde No:42 Nova Yaşam Apt. K:5 D:20','İzmir','Karşıyaka','Lg Eco',1,6000,'2025-12-20'::date,'Ali','Sultan'),
(486,'Müslüm Yılmaz','5456200386','7303 Sk. 1. Cadde No:42 Nova Yaşam Apt. K:5 D:20','İzmir','Karşıyaka','Alkali',1,2000,'2025-12-20'::date,'Ali','Sultan'),
(487,'Mehmet Ali Ata','5323063260','Kazımdirik Mh. 230 Sk. No:12 K:1 D:2','İzmir','Bornova','Lg Eco',1,5500,'2025-12-20'::date,'Ali','Sultan'),
(488,'Mehmet Ali Ata','5323063260','Kazımdirik Mh. 230 Sk. No:12 K:1 D:2','İzmir','Bornova','Alkali',1,1500,'2025-12-20'::date,'Ali','Sultan'),
(489,'Leyla Alan','5305463674','8846 Sk. No:16 D:7','İzmir','Çiğli','Tam Takım',1,1000,'2025-12-20'::date,'Ali','Sultan'),
(490,'Leyla Alan','5305463674','8846 Sk. No:16 D:7','İzmir','Çiğli','Alkali',1,1000,'2025-12-20'::date,'Ali','Sultan'),
(491,'Yakup Güzel','5072426626','7061 Sk. No:75 D:3','İzmir','Bayraklı','Tam Takım',1,1100,'2025-12-20'::date,'Ali','Sultan'),
(492,'Münevver Kaya','5079204542','8208 Sk. No:67 K:2 D:4','İzmir','Çiğli','Tam Takım',1,1100,'2025-12-20'::date,'Ali','Sultan'),
(493,'Okan Güneysi','5368497816','Manço Sk. No:4 K:1 D:1','İzmir','Torbalı','Lg Eco',2,12000,'2025-12-22'::date,'Ali','Sultan'),
(494,'Okan Güneysi','5368497816','Manço Sk. No:4 K:1 D:1','İzmir','Torbalı','Alkali',2,3000,'2025-12-22'::date,'Ali','Sultan'),
(495,'Tuncay Alptekin','5422771080','3075 Sk. No:5 D:4','İzmir','Karabağlar','Tam Takım',1,1100,'2025-12-22'::date,'Ali','Sultan'),
(496,'Yasin Turan','5054572999','Mithatpaşa Mh. 179 Sk. No:12 D:5','İzmir','Konak','Lg Eco',1,6000,'2025-12-22'::date,'Ali','Sultan'),
(497,'Yasin Turan','5054572999','Mithatpaşa Mh. 179 Sk. No:12 D:5','İzmir','Konak','Alkali',1,2000,'2025-12-22'::date,'Ali','Sultan'),
(498,'Mahmut Yelli','5053855320','3109 Sk. No:3 K:2 D:2','İzmir','Torbalı','Tam Takım',1,1100,'2025-12-22'::date,'Ali','Sultan'),
(499,'Nezire Usta Coşkun','5385241443','Tepekule mh. 2086 sk. 2/1 k:5','İzmir','Bayraklı','Tam Takım',1,1100,'2025-12-23'::date,'Ali','Sultan'),
(500,'Nezire Usta Coşkun','5385241443','Tepekule mh. 2086 sk. 2/1 k:5','İzmir','Bayraklı','Musluk',1,300,'2025-12-23'::date,'Ali','Sultan'),
(501,'Nezire Usta Coşkun','5385241443','Tepekule mh. 2086 sk. 2/1 k:5','İzmir','Bayraklı','Montaj',1,700,'2025-12-23'::date,'Ali','Sultan'),
(502,'Vedat Eyigün','5434801972','9677/3 Sk. No:3 K:2 salih omurtak','İzmir','Karabağlar','Lg Eco',1,8000,'2025-12-23'::date,'Ali','Sultan'),
(503,'Vedat Eyigün','5434801972','9677/3 Sk. No:3 K:2 salih omurtak','İzmir','Karabağlar','Alkali',1,2000,'2025-12-23'::date,'Ali','Sultan'),
(504,'Gamze Bükmez','5337160538','Rakım Erkutlu Cd. No:3 K:3 D:4','İzmir','Konak','Lg Eco',1,6000,'2025-12-23'::date,'Ali','Sultan'),
(505,'Gamze Bükmez','5337160538','Rakım Erkutlu Cd. No:3 K:3 D:4','İzmir','Konak','Alkali',1,2000,'2025-12-23'::date,'Ali','Sultan'),
(506,'Ramazan Türkseven','5514068096','5032 Sk. No:7 K:1','İzmir','Bornova','Tam Takım',1,1100,'2025-12-23'::date,'Ali','Sultan'),
(507,'Ramazan Örnek','5465835575','Atalan Mh. 609 Sk. No:5','İzmir','Torbalı','Tam Takım',2,2200,'2025-12-24'::date,'Ali','Sultan'),
(508,'Besim Dursun','5452324847','2960 Sk. No:5/7 K:1 D:3','İzmir','Karabağlar','Tam Takım',1,1100,'2025-12-24'::date,'Ali','Sultan'),
(509,'Nurdan Sütlü Doğruözlü','5359774911','Cengizhan Cd. No:15 K:1 D:2','İzmir','Gaziemir','Tam Takım',1,1100,'2025-12-24'::date,'Ali','Sultan'),
(510,'Mehmet Ardahan','5354778844','Yeşilova Mh. 4068 Sk. No:16 D:4','İzmir','Bornova','Tam Takım',1,1100,'2025-12-24'::date,'Ali','Sultan'),
(511,'Elif Arslan','5438153504','Kıvanç Cd. No:37/43 Sk. K:1 D:3','İzmir','Bornova','Lg Eco',1,4000,'2025-12-24'::date,'Ali','Sultan'),
(512,'Yusuf Gökçen','5422612211','Sevim Barulay Sk. No:3 D:2','İzmir','Karşıyaka','Lg Eco',1,6000,'2025-12-25'::date,'Ali','Sultan'),
(513,'Yusuf Gökçen','5422612211','Sevim Barulay Sk. No:3 D:2','İzmir','Karşıyaka','Alkali',1,2000,'2025-12-25'::date,'Ali','Sultan'),
(514,'Salih Koral','5438632024','1920 Sk. No:1 D:1','İzmir','Bayraklı','Tam Takım',1,1000,'2025-12-25'::date,'Ali','Sultan'),
(515,'Salih Koral','5438632024','1920 Sk. No:1 D:1','İzmir','Bayraklı','Alkali',1,1000,'2025-12-25'::date,'Ali','Sultan'),
(516,'Münir Bey','5326738794','7005 Sk. No:5 K:3','İzmir','Bayraklı','Tam Takım',1,1100,'2025-12-25'::date,'Ali','Sultan'),
(517,'Tunay Ballıkaya','5305459948','7302/2 Sk. No:4 D:2','İzmir','Bayraklı','Tam Takım',1,1100,'2025-12-25'::date,'Ali','Sultan'),
(518,'Yaşar Zeyrek','5458679677','8809/4 Sk. No:6 D:Kapıcı Dairesi','İzmir','Çiğli','Lg Eco',1,5500,'2025-12-25'::date,'Ali','Sultan'),
(519,'Yaşar Zeyrek','5458679677','8809/4 Sk. No:6 D:Kapıcı Dairesi','İzmir','Çiğli','Alkali',1,1500,'2025-12-25'::date,'Ali','Sultan'),
(520,'Cenker Atkoşar','5354675713','Doğanay Mh. Şükrü Karaduman Cd. No:1-3 D:15 K:2','İzmir','Karabağlar','Tam Takım',1,1100,'2025-12-26'::date,'Ali','Sultan'),
(521,'Cenker Atkoşar','5354675713','Doğanay Mh. Şükrü Karaduman Cd. No:1-3 D:15 K:2','İzmir','Karabağlar','Alkali',1,1500,'2025-12-26'::date,'Ali','Sultan'),
(522,'Ahmet Sevlüş','5068364482','6512 Sk. No:4','İzmir','Karabağlar','Tam Takım',1,1100,'2025-12-26'::date,'Ali','Sultan'),
(523,'Seydi Ateş','5326666143','292/42 Sk. No:8 K:4 D:9','İzmir','Buca','Lg Eco',1,6000,'2025-12-26'::date,'Ali','Sultan'),
(524,'Seydi Ateş','5326666143','292/42 Sk. No:8 K:4 D:9','İzmir','Buca','Alkali',1,2000,'2025-12-26'::date,'Ali','Sultan'),
(525,'Kasım Yalçın','5320583080','Mustafa Kemal Mh. 694/31 Sk. No:16 D:4','İzmir','Buca','Lg Eco',1,8000,'2025-12-26'::date,'Ali','Sultan'),
(526,'Kasım Yalçın','5320583080','Mustafa Kemal Mh. 694/31 Sk. No:16 D:4','İzmir','Buca','Alkali',1,2000,'2025-12-26'::date,'Ali','Sultan'),
(527,'Ulaş Bey','5525212608','','İzmir','Gümüşpala','Arıza',1,800,'2025-12-26'::date,'Ali','Sultan'),
(528,'Asuman Dayran','5322524307','1751 Sk. No:26 K:2 D:2','İzmir','Karşıyaka','Lg Eco',1,6000,'2025-12-26'::date,'Ali','Sultan'),
(529,'Asuman Dayran','5322524307','1751 Sk. No:26 K:2 D:2','İzmir','Karşıyaka','Alkali',1,2000,'2025-12-26'::date,'Ali','Sultan'),
(530,'Güler Hanım','5322125404','183/1 Sk. No:2/11 D:14','İzmir','Ayrancılar','Tam Takım',1,1100,'2025-12-27'::date,'Ali','Sultan'),
(531,'Adnan Üzen','5334760464','4/2 Sk. No:8 D:5 Güzelyalı','İzmir','Konak','Tam Takım',1,0,'2025-12-29'::date,'Ali','Sultan'),
(532,'Adnan Üzen','5334760464','4/2 Sk. No:8 D:5 Güzelyalı','İzmir','Konak','Arıza',1,0,'2025-12-29'::date,'Ali','Sultan'),
(533,'Ender Sait Öz','5398660660','Ayrancılar Mh. 83 Sk. No:19 K:8 D:34','İzmir','Torbalı','Lg Eco',1,6000,'2025-12-29'::date,'Ali','Sultan'),
(534,'Ender Sait Öz','5398660660','Ayrancılar Mh. 83 Sk. No:19 K:8 D:34','İzmir','Torbalı','Alkali',1,2000,'2025-12-29'::date,'Ali','Sultan'),
(535,'Ebru Apaydın','5555148118','Güzelyalı Mh. Mithatpaşa Cd. No:1172/B','İzmir','Konak','Tam Takım',1,1100,'2025-12-29'::date,'Ali','Sultan'),
(536,'Osman Özer','5306647695','Zübeyde Hanım Mh. 7448/11 Sk. No:4 K:6 D:23','İzmir','Karşıyaka','Lg Eco',1,6000,'2025-12-29'::date,'Ali','Sultan'),
(537,'Osman Özer','5306647695','Zübeyde Hanım Mh. 7448/11 Sk. No:4 K:6 D:23','İzmir','Karşıyaka','Alkali',1,2000,'2025-12-29'::date,'Ali','Sultan'),
(538,'Gönül Hattuza','5312782665','1242 Sk. No:13 D:4','İzmir','Bornova','Lg Eco',1,6000,'2025-12-29'::date,'Ali','Sultan'),
(539,'Gönül Hattuza','5312782665','1242 Sk. No:13 D:4','İzmir','Bornova','Alkali',1,2000,'2025-12-29'::date,'Ali','Sultan'),
(540,'Ebru Apaydın','5535148118','Güzelyalı Mh. Mithatpaşa Cd. No:1172/B','İzmir','Konak','12W Selenoid',1,500,'2025-12-30'::date,'Ali','Sultan'),
(541,'Ebru Apaydın','5535148118','Güzelyalı Mh. Mithatpaşa Cd. No:1172/B','İzmir','Konak','Sebil Ap.',1,1000,'2025-12-30'::date,'Ali','Sultan'),
(542,'Abdulhakim Kılbaş','5368933380','5157 Sk. No:52 D:2 Pekar Mh.','İzmir','Karabağlar','Tam Takım',1,1100,'2025-12-30'::date,'Ali','Sultan'),
(543,'Fehri Akoğlu','5359123388','150 Sk. No:40 K:3 D:6','İzmir','Konak','Tam Takım',1,1100,'2025-12-30'::date,'Ali','Sultan'),
(544,'Veli Yılmaz','5425737919','Limontepe Mh. 9757 Sk. No:25/1 K:3 D:3','İzmir','Karabağlar','Tam Takım',1,1100,'2025-12-30'::date,'Ali','Sultan'),
(545,'İrfan İlmen','5375976088','119/8 Sk. No:6/2 K:7 D:30','İzmir','Bornova','Tam Takım',1,1100,'2026-01-02'::date,'Ali','Sultan'),
(546,'Levent Durmuş','5337386518','1723 Sk. No:8 K:5 D:5','İzmir','Bornova','Tam Takım',1,1100,'2026-01-02'::date,'Ali','Sultan'),
(547,'Turgut Güler','5057749255','Murat Bey mh. 3639 sk. No:15 D:26 K:6','İzmir','Torbalı','Lg Eco',1,12000,'2026-01-02'::date,'Ali','Sultan'),
(548,'Cuma Çelik','5051517273','392 Sk. No:3 D:3 Binbaşı Reşat Bey Mh.','İzmir','Gaziemir','Lg Eco',1,5500,'2026-01-02'::date,'Ali','Sultan'),
(549,'Cuma Çelik','5051517273','392 Sk. No:3 D:3 Binbaşı Reşat Bey Mh.','İzmir','Gaziemir','Alkali',1,1500,'2026-01-02'::date,'Ali','Sultan'),
(550,'Derya Soydan','5073942727','5175 Sk. No:20 K:3 Rafetpaşa Mh. Çamdibi','İzmir','Bornova','Lg Eco',1,7000,'2026-01-02'::date,'Ali','Sultan'),
(551,'Derya Soydan','5073942727','5175 Sk. No:20 K:3 Rafetpaşa Mh. Çamdibi','İzmir','Bornova','Alkali',1,2000,'2026-01-02'::date,'Ali','Sultan'),
(552,'Mustafa Geliş','5366977358','Cumhuriyet Mh. Haluk Alpsu Blv. 43/22 Blok D:20 K:3','İzmir','Torbalı','Lg Eco',1,7500,'2026-01-02'::date,'Ali','Sultan'),
(553,'Mustafa Geliş','5366977358','Cumhuriyet Mh. Haluk Alpsu Blv. 43/22 Blok D:20 K:3','İzmir','Torbalı','Alkali',1,1500,'2026-01-02'::date,'Ali','Sultan'),
(554,'Engin Tükenmez','5384021042','Naci Tuncel cd. No:41 C K:4 D:19','İzmir','Torbalı','Membran(Arıza)',1,0,'2026-01-02'::date,'Ali','Sultan'),
(555,'Ozan Özçelik','','Folkart Towers A Blok','İzmir','Bayraklı','3 Yollu Musluk',2,6000,'2026-01-02'::date,'Ali','Sultan'),
(556,'Süleyman Karakuş','5346717889','2464 Sk. No:99 Gültepe','İzmir','Konak','Tam Takım',1,1100,'2026-01-02'::date,'Ali','Sultan'),
(557,'Turgut Güler','5057749255','Murat Bey mh. 3639 sk. No:15 D:26 K:6','İzmir','Torbalı','Alkali',1,3000,'2026-01-02'::date,'Ali','Sultan'),
(558,'Kemal Bey','5446445620','29 ekim mh 8. cd 30B No:9 K:2 D:9','İzmir','menemen','Tam Takım',1,1450,'2026-01-02'::date,'Ali','Sultan'),
(559,'Şenol Tahir Sezer','5349666878','Osmangazi Mh. 592/20 Sk. No:1 D:9 Güneşkent St.','İzmir','Bayraklı','Lg Eco',1,5500,'2026-01-03'::date,'Ali','Sultan'),
(560,'Şenol Tahir Sezer','5349666878','Osmangazi Mh. 592/20 Sk. No:1 D:9 Güneşkent St.','İzmir','Bayraklı','Alkali',1,1500,'2026-01-03'::date,'Ali','Sultan'),
(561,'Cavit Kırcan','5322484950','560 Sk. No:6 Eşrefpaşa','İzmir','Konak','Tam Takım',1,1100,'2026-01-03'::date,'Ali','Sultan'),
(562,'Emirhan Demirci','5443129450','3613 Sk. No:8','İzmir','Konak','Tam Takım',1,1100,'2026-01-03'::date,'Ali','Sultan'),
(563,'Mehmet Sinan Sarıyıldız','5052246368','Yenigün Mh. 268/6 Sk. No:12 D:8','İzmir','Buca','Tam Takım',1,1100,'2026-01-03'::date,'Ali','Sultan'),
(564,'Şenol Tunç','5054950420','6753/7 Sk. No:11 D:29 K:7','İzmir','Karşıyaka','Lg Eco',1,8500,'2026-01-03'::date,'Ali','Sultan'),
(565,'Şenol Tunç','5054950420','6753/7 Sk. No:11 D:29 K:7','İzmir','Karşıyaka','Alkali',1,1500,'2026-01-03'::date,'Ali','Sultan'),
(566,'Güner Gül','5055608678','1593/1 Sk. P Blok No:24 D:29 K:5','İzmir','Bayraklı','Lg Eco',1,9000,'2026-01-03'::date,'Ali','Sultan'),
(567,'Güner Gül','5055608678','1593/1 Sk. P Blok No:24 D:29 K:5','İzmir','Bayraklı','Alkali',1,3000,'2026-01-03'::date,'Ali','Sultan'),
(568,'Murat Çiftçi','5524606090','183/1 Sk. No:3 D:5 T2-1 Blok Yeni','İzmir','Ayrancılar','Tam Takım',1,1100,'2026-01-03'::date,'Ali','Sultan'),
(569,'Murat Çiftçi','5524606090','183/1 Sk. No:3 D:5 T2-1 Blok Yeni','İzmir','Ayrancılar','Alkali',1,1100,'2026-01-03'::date,'Ali','Sultan'),
(570,'Osman Sabahattin Kılıç','5315220835','1637/17 Sk. No:43 K:2 D:2','İzmir','Bayraklı','Tam Takım',1,1100,'2026-01-03'::date,'Ali','Sultan'),
(571,'Turgay Bozdağ','5530532467','1626 Sk. No:42 D:4-5','İzmir','Bayraklı','Tam Takım',2,2200,'2026-01-03'::date,'Ali','Sultan'),
(572,'Ali Çetin','5057084895','Muammer Akar Mh. 45 Sk. No:17 D:2','İzmir','Karabağlar','Lg Eco',1,8000,'2026-01-05'::date,'Ali','Sultan'),
(573,'Ali Çetin','5057084895','Muammer Akar Mh. 45 Sk. No:17 D:2','İzmir','Karabağlar','Alkali',1,2000,'2026-01-05'::date,'Ali','Sultan'),
(574,'Ali Avşar','5016171605','Şehitler Mh. 52/25 Sk. No:19 K:2 D:2','İzmir','Karabağlar','Tam Takım',1,1100,'2026-01-05'::date,'Ali','Sultan'),
(575,'Hanife Karadoğan','5529419511','1620/11 Sk. No:10/2','İzmir','Bayraklı','Membran',1,0,'2026-01-05'::date,'Ali','Sultan'),
(576,'Süleyman Alkurt','5323369208','Rafet Bele Mh. 9180 Sk. No:25 D:2','İzmir','Karabağlar','Tam Takım',1,1100,'2026-01-05'::date,'Ali','Sultan'),
(577,'Süleyman Alkurt','5323369208','Rafet Bele Mh. 9180 Sk. No:25 D:2','İzmir','Karabağlar','Alkali',1,1100,'2026-01-05'::date,'Ali','Sultan'),
(578,'Ali Bey','5414198262','Fuat Edip Baksı Mh. 1609/7 Sk. No: 2C','İzmir','Bayraklı','Lg Eco',1,5500,'2026-01-05'::date,'Ali','Sultan'),
(579,'Ali Bey','5414198262','Fuat Edip Baksı Mh. 1609/7 Sk. No: 2C','İzmir','Bayraklı','Alkali',1,1500,'2026-01-05'::date,'Ali','Sultan'),
(580,'Şahin Şen','5079464057','Toki Bayraklı 2. Etap 2. Kısım D-2 Blok No:23 D:1','İzmir','Bayraklı','Tam Takım',1,1100,'2026-01-06'::date,'Ali','Sultan'),
(581,'Şahin Şen','5079464057','Toki Bayraklı 2. Etap 2. Kısım D-2 Blok No:23 D:1','İzmir','Bayraklı','Alkali',1,1500,'2026-01-06'::date,'Ali','Sultan'),
(582,'Serkan Araç','5059623891','7323/2 Sk. No:13 D:3 Yamanlar','İzmir','Bayraklı','Lg Eco',1,5500,'2026-01-06'::date,'Ali','Sultan'),
(583,'Mustafa Gültan','5436358620','9 Eylül Mh. 318 Sk. No:18A','İzmir','Gaziemir','Tam Takım',1,1100,'2026-01-06'::date,'Ali','Sultan'),
(584,'Arda Şölen','5439431310','271 Sk. No:58 D:8','İzmir','Konak','Tam Takım',1,1500,'2026-01-06'::date,'Ali','Sultan'),
(585,'Arda Şölen','5439431310','271 Sk. No:58 D:8','İzmir','Konak','Alkali',1,1000,'2026-01-06'::date,'Ali','Sultan'),
(586,'Abdullah Doğan','5442165220','3948 Sk. No:10 D:3','İzmir','Karabağlar','Tam Takım',1,1100,'2026-01-07'::date,'Ali','Sultan'),
(587,'Soner Süleyman Erol','5057966618','Fahrettin Altay Mh. 2/22 Sk. No:11 K:7 D:30','İzmir','Karabağlar','Tam Takım',1,1100,'2026-01-07'::date,'Ali','Sultan'),
(588,'Nevin İtap','5053099474','404 Sk. No:40 K:2 D:3','İzmir','Buca','Lg Eco',1,6000,'2026-01-07'::date,'Ali','Sultan'),
(589,'Nevin İtap','5053099474','404 Sk. No:40 K:2 D:3','İzmir','Buca','Alkali',1,2000,'2026-01-07'::date,'Ali','Sultan'),
(590,'Erkan Şatırlar','5339265054','5407 Sk. No:5 K:2 Çamdibi','İzmir','Bornova','Tam Takım',1,1100,'2026-01-07'::date,'Ali','Sultan'),
(591,'Fikret Bey','','Yeşilpınar Mh. Veli Kutlu Aktaş Cd. No:1 D:1','İzmir','Menemen','Tam Takım',1,1100,'2026-01-08'::date,'Ali','Sultan'),
(592,'Fikret Bey','','Yeşilpınar Mh. Veli Kutlu Aktaş Cd. No:1 D:1','İzmir','Menemen','Alkali',1,1100,'2026-01-08'::date,'Ali','Sultan'),
(593,'Selami Özcan','5516516359','57 Sk. No:14 D:5','İzmir','Ayrancılar','Tam Takım',1,1100,'2026-01-08'::date,'Ali','Sultan'),
(594,'Cemal Çelik','5366491354','İncirli Pınar Mh. 120 sk. No:1 D:1','İzmir','Menemen','Tam Takım',1,1000,'2026-01-08'::date,'Ali','Sultan'),
(595,'Cemal Çelik','5366491354','İncirli Pınar Mh. 120 sk. No:1 D:1','İzmir','Menemen','Alkali',1,1000,'2026-01-08'::date,'Ali','Sultan'),
(596,'Serkan Bey','5059623891','1671 Sk. No:194 D:9 K:5','İzmir','Karşıyaka','Tam Takım',1,1100,'2026-01-08'::date,'Ali','Sultan'),
(597,'Muharrem Bey','5059144741','1849/1 Sk. No:14 D:18 Bahçelievler','İzmir','Karşıyaka','Tam Takım',1,1100,'2026-01-08'::date,'Ali','Sultan'),
(598,'Saime Özdemir','5386140826','Cumhuriyet Mh. 94 Sk. No:6/2 B Blok D:10 K:3 Nar Evleri','İzmir','Menemen','Lg Eco',1,6000,'2026-01-08'::date,'Ali','Sultan'),
(599,'Saime Özdemir','5386140826','Cumhuriyet Mh. 94 Sk. No:6/2 B Blok D:10 K:3 Nar Evleri','İzmir','Menemen','Alkali',1,2000,'2026-01-08'::date,'Ali','Sultan'),
(600,'Mehmet Kaya','5324820548','756 Sk. No:11 İnönü Mh.','İzmir','Bornova','Tam Takım',1,1100,'2026-01-09'::date,'Ali','Sultan'),
(601,'Galip Özşahin','5417344752','Atatürk Mh. 831 Sk. No:11 K:3 D:3','İzmir','Bornova','Lg Eco',1,6000,'2026-01-09'::date,'Ali','Sultan'),
(602,'Galip Özşahin','5417344752','Atatürk Mh. 831 Sk. No:11 K:3 D:3','İzmir','Bornova','Alkali',1,2000,'2026-01-09'::date,'Ali','Sultan'),
(603,'Barış Kara','5413110279','1261/14 Sk. No:10 D:-1','İzmir','Bornova','Lg Eco',1,5000,'2026-01-09'::date,'Ali','Sultan'),
(604,'Barış Kara','5413110279','1261/14 Sk. No:10 D:-1','İzmir','Bornova','Lg Eco',1,1000,'2026-01-09'::date,'Ali','Sultan'),
(605,'Turan Tekin','5320538663','457 Sk. No:3 K:6 D:16','İzmir','Bornova','Lg Eco',1,5500,'2026-01-09'::date,'Ali','Sultan'),
(606,'Turan Tekin','5320538663','457 Sk. No:3 K:6 D:16','İzmir','Bornova','Alkali',1,1500,'2026-01-09'::date,'Ali','Sultan'),
(607,'Gülizar Tekdemir','5332330676','177 Sk. No:87 D:3 K:2','İzmir','Konak','Tam Takım',1,1100,'2026-01-10'::date,'Ali','Sultan'),
(608,'Bedri Demir','5466646701','3157 Sk. No:6 K:3 D:4','İzmir','Karabağlar','Lg Eco',1,6000,'2026-01-10'::date,'Ali','Sultan'),
(609,'Bedri Demir','5466646701','3157 Sk. No:6 K:3 D:4','İzmir','Karabağlar','Alkali',1,2000,'2026-01-10'::date,'Ali','Sultan'),
(610,'Erdal Kuşari','5314692122','1509 Sk. No:13/1 D:5 Doğanlar','İzmir','Bornova','Lg Eco',1,6000,'2026-01-10'::date,'Ali','Sultan'),
(611,'Erdal Kuşari','5314692122','1509 Sk. No:13/1 D:5 Doğanlar','İzmir','Bornova','Alkali',1,2000,'2026-01-10'::date,'Ali','Sultan'),
(612,'Rıza Bayat','5344088763','Özsağlık Sk. No:39 D:1','İzmir','Balçova','Tam Takım',1,1100,'2026-01-10'::date,'Ali','Sultan'),
(613,'Ali Öztürk','5523203544','Onur Mh. Kaan Sk. No:14 D:2','İzmir','Balçova','Tam Takım',1,1100,'2026-01-10'::date,'Ali','Sultan'),
(614,'Eda Mıdık','5350170405','Eğitim Mh. Hüseyin Cahit Yalçın Sk. No:14 K:4','İzmir','Balçova','Lg Eco',1,60000,'2026-01-10'::date,'Ali','Sultan'),
(615,'Eda Mıdık','5350170405','Eğitim Mh. Hüseyin Cahit Yalçın Sk. No:14 K:4','İzmir','Balçova','Alkali',1,1500,'2026-01-10'::date,'Ali','Sultan'),
(616,'Ecevit Yaman','5322914387','Yenikale Mh. Dilmaç Sk. No:9 D:7','İzmir','Narlıdere','Tam Takım',1,1100,'2026-01-10'::date,'Ali','Sultan'),
(617,'Göksel Dikmenoğlu','5326549923','52/15 Sk. No:41 D:3','İzmir','Karabağlar','Montaj',1,800,'2026-01-12'::date,'Ali','Sultan'),
(618,'Esra Oluç','5538483147','633 Sk. No:12-14 D:1 K:1','İzmir','Buca','Tam Takım',1,1100,'2026-01-12'::date,'Ali','Sultan'),
(619,'Servet Bulut','5365819458','9131/5 Sk. No:4/1 D:4','İzmir','Karabağlar','Tam Takım',1,1100,'2026-01-12'::date,'Ali','Sultan'),
(620,'Dursun Ali Genç','5443433811','343 Sk. No:29 D:2','İzmir','Buca','Tam Takım',1,1100,'2026-01-12'::date,'Ali','Sultan'),
(621,'İsmail Can','5414191750','2. Kadriye Mh. 690 Sk. No:22','İzmir','Konak','Tam Takım',1,1100,'2026-01-12'::date,'Ali','Sultan'),
(622,'Sümeyye Demir','5412370356','637 Sk. No:50 D:5','İzmir','Buca','Tam Takım',1,1100,'2026-01-12'::date,'Ali','Sultan'),
(623,'Hüseyin Tuluğ Bayram','5362689016','Mansuroğlu Mh. Dumlupınar Mh. No:68 D:30 K:4','İzmir','Bayraklı','Lg Eco',1,6000,'2026-01-13'::date,'Ali','Sultan'),
(624,'Hüseyin Tuluğ Bayram','5362689016','Mansuroğlu Mh. Dumlupınar Mh. No:68 D:30 K:4','İzmir','Bayraklı','Alkali',1,2000,'2026-01-13'::date,'Ali','Sultan'),
(625,'Tezcan Gültekin','5319751186','1176 Sk. No:18-20A','İzmir','Bornova','Tam Takım',1,1100,'2026-01-13'::date,'Ali','Sultan'),
(626,'Korhan Özen','5397003190','7355/2 Sk. No:10 D:29 K:7','İzmir','Karşıyaka','Tam Takım',1,1100,'2026-01-13'::date,'Ali','Sultan'),
(627,'Korhan Özen','5397003190','7355/2 Sk. No:10 D:29 K:7','İzmir','Karşıyaka','Alkali',1,1500,'2026-01-13'::date,'Ali','Sultan'),
(628,'Elif Yaylacı','5388557707','529 Sk. No:3 K:3 D:7','İzmir','Bornova','Tam Takım',1,1100,'2026-01-14'::date,'Ali','Sultan'),
(629,'Ercais Mert','5353461578','2084/5 sk no:1 k:4 d:4','İzmir','Bayraklı','Yenilenmiş Cihaz',1,3000,'2026-01-14'::date,'Ali','Sultan'),
(630,'Cemal Çelik','5334406764','Çamkule Mh. 4726 Sk. No:13 K:4 D:4','İzmir','Bornova','Lg Eco',1,5500,'2026-01-14'::date,'Ali','Sultan'),
(631,'Cemal Çelik','5334406764','Çamkule Mh. 4726 Sk. No:13 K:4 D:4','İzmir','Bornova','Alkali',1,1500,'2026-01-14'::date,'Ali','Sultan'),
(632,'Mustafa Anıl','5469300435','5136 Sk. No:16 D:4','İzmir','Karabağlar','Tam Takım',1,1100,'2026-01-14'::date,'Ali','Sultan'),
(633,'Erhan Görmez','5353726068','3449 Sk. No:4 Ferahlı Mh.','İzmir','Konak','Tam Takım',1,1100,'2026-01-14'::date,'Ali','Sultan'),
(634,'Nadir Murat Demir','5335160347','Kozağaç Mh. 231/2 Sk. No:22 D:20 K:5','İzmir','Buca','Tam Takım',1,1100,'2026-01-14'::date,'Ali','Sultan'),
(635,'Fahri Dursun','5418860972','5787 Sk. No:39 D:39A','İzmir','Karabağlar','Lg Eco',1,6000,'2026-01-14'::date,'Ali','Sultan'),
(636,'Fahri Dursun','5418860972','5787 Sk. No:39 D:39A','İzmir','Karabağlar','Alkali',1,2000,'2026-01-14'::date,'Ali','Sultan'),
(637,'Salih Olgun','5386873643','Karşıyaka Mh. 7313 Sk. No:20 D:1','İzmir','Torbalı','Lg Eco',1,6000,'2026-01-15'::date,'Ali','Sultan'),
(638,'Müjgan Çetindağ','5524150814','131 Sk. No:27 D:3 K:1 İnönü Mh.','İzmir','Torbalı','Ön Takım',1,800,'2026-01-15'::date,'Ali','Sultan'),
(639,'Serpil Kızılateş','5334347773','53 Sk. No:24 K:1 D:1','İzmir','Konak','Tam Takım',1,1100,'2026-01-16'::date,'Ali','Sultan'),
(640,'Salih Cantürk','5011229460','129 Sk. No:8 Çankaya','İzmir','Konak','Lg Eco',1,6000,'2026-01-16'::date,'Ali','Sultan'),
(641,'Salih Cantürk','5011229460','129 Sk. No:8 Çankaya','İzmir','Konak','Alkali',1,2000,'2026-01-16'::date,'Ali','Sultan'),
(642,'Nevin Gündüz','5350186672','Halil Rıfat Paşa Cd. 278 Sk. D:1','İzmir','Konak','Tam Takım',1,1100,'2026-01-16'::date,'Ali','Sultan'),
(643,'Seyfullah Teknur','5376100061','1227 Sk. No:47 Müstakil','İzmir','Konak','Tam Takım',1,1100,'2026-01-16'::date,'Ali','Sultan'),
(644,'Merhamet Hanım','5306549758','Boğaziçi Cd. No:81 K:3 D:6','İzmir','Konak','Tam Takım',1,1100,'2026-01-16'::date,'Ali','Sultan'),
(645,'Orhan Sargın','5467341738','689/8 Sk. No:22 K:3 D:4','İzmir','Buca','Tam Takım',2,2200,'2026-01-16'::date,'Ali','Sultan'),
(646,'Melek Toprak','5424652678','848/2 Sk. No:1 D:1','İzmir','Buca','Tam Takım',1,1100,'2026-01-16'::date,'Ali','Sultan'),
(647,'Yusuf Dursun','5452737172','686/10 Sk. No:19 D:12','İzmir','Buca','Tam Takım',1,1100,'2026-01-16'::date,'Ali','Sultan'),
(648,'Mahir Öztezcan','5326133687','Sağlık Sk. Çamlı Mh.','İzmir','Güzelbahçe','Lg Eco',1,8500,'2026-01-17'::date,'Ali','Sultan'),
(649,'Mahir Öztezcan','5326133687','Sağlık Sk. Çamlı Mh.','İzmir','Güzelbahçe','Alkali',1,1500,'2026-01-17'::date,'Ali','Sultan'),
(650,'Ali Keser','','5020 Sk. No:53','İzmir','Karabağlar','Tam Takım',1,1100,'2026-01-17'::date,'Ali','Sultan'),
(651,'Mehmet Hasan Nursa','5550075122','Arap Hasan Mh. Gazeteci Hasan Tahsin Cd. No:76 D:4','İzmir','Karabağlar','Tam Takım',1,1100,'2026-01-17'::date,'Ali','Sultan'),
(652,'Ömer Hamzaoğlu','','9298/1 Sk. No:1 D:11','İzmir','Karabağlar','Tam Takım',1,1100,'2026-01-17'::date,'Ali','Sultan'),
(653,'Özgür Özcan','','','','','Shutoff+flow+checkvalf',1,1000,'2026-01-17'::date,'Ali','Sultan'),
(654,'Özgür Özcan','','','','','Tam Takım',1,1000,'2026-01-17'::date,'Ali','Sultan'),
(655,'Müzeyyen Erken','5064867464','İnönü Cd. 2281 Sk. No: C-61 Yelki','İzmir','Güzelbahçe','Tam Takım',1,1100,'2026-01-17'::date,'Ali','Sultan'),
(656,'İlhan Ulupınar','5383109386','8712 Sk. No:67 D:3','İzmir','Çiğli','Tam Takım',1,1100,'2026-01-19'::date,'Ali','Sultan'),
(657,'Yılmaz Yıldırım','5325495593','Yeşilçam Mh. 2005 Sk. No:33 K:1 D:1','İzmir','Bornova','Lg Eco',1,6000,'2026-01-19'::date,'Ali','Sultan'),
(658,'Yılmaz Yıldırım','5325495593','Yeşilçam Mh. 2005 Sk. No:33 K:1 D:1','İzmir','Bornova','Alkali',1,2000,'2026-01-19'::date,'Ali','Sultan'),
(659,'Gürcü Şener','5071322113','2093 Sk. No:10 K:3 D:8','İzmir','Bayraklı','Tam Takım',1,1100,'2026-01-19'::date,'Ali','Sultan'),
(660,'Binali Bayın','5532973009','915 Sk. No:165 D:4','İzmir','Bornova','Tam Takım',1,1100,'2026-01-19'::date,'Ali','Sultan'),
(661,'Binali Bayın','5532973009','915 Sk. No:165 D:4','İzmir','Bornova','Alkali',1,1100,'2026-01-19'::date,'Ali','Sultan'),
(662,'Samet Çalışkan','5433203629','6221/3 Sk. No:7 D:3','İzmir','Karşıyaka','Tam Takım',1,1100,'2026-01-19'::date,'Ali','Sultan'),
(663,'Metin Dağlı','5385215426','8038 Sk. No:2 D:3','İzmir','Çiğli','Tam Takım',1,1100,'2026-01-19'::date,'Ali','Sultan'),
(664,'Orhan Çetinkaya','5343807166','8809/10 Sk. No:6 K:7 D:27','İzmir','Çiğli','Lg Eco',1,6000,'2026-01-20'::date,'Ali','Sultan'),
(665,'Orhan Çetinkaya','5343807166','8809/10 Sk. No:6 K:7 D:27','İzmir','Çiğli','Alkali',1,2000,'2026-01-20'::date,'Ali','Sultan'),
(666,'Mithat Tanır','5372703407','5741 Sk. No:83 D:3','İzmir','Karabağlar','Tam Takım',1,1100,'2026-01-20'::date,'Ali','Sultan'),
(667,'Serkan Domurcuk','5552909589','Mehmetçik Blv. No:51C','İzmir','Karabağlar','Tam Takım',1,1100,'2026-01-20'::date,'Ali','Sultan'),
(668,'Çağdaş Özmen','5011500035','293/12 Sk. No:7 D:3 Çamlıpınar','İzmir','Buca','Tam Takım',1,1100,'2026-01-20'::date,'Ali','Sultan'),
(669,'Çağdaş Özmen','5011500035','293/12 Sk. No:7 D:3 Çamlıpınar','İzmir','Buca','Alkali',1,1100,'2026-01-20'::date,'Ali','Sultan'),
(670,'Fuat Fidan','5071301006','637/22 Sk. No:8 D:4','İzmir','Buca','Tam Takım',1,1100,'2026-01-20'::date,'Ali','Sultan'),
(671,'Turgut Seylan','5337720458','İkiz çay mh. RIFAT ILGAZ CD. No:32/4 D:5 Havza st. Güneş apt.','Balıkesir','Edremit','Lg Eco',1,1000,'2026-01-21'::date,'Ali','Sultan'),
(672,'Firdevs-Hasan Aykanat','5366370529','2034 Sk. Bergama 2 apt. No:34 D:25','İzmir','Karşıyaka','Lg Eco',1,7000,'2026-01-21'::date,'Ali','Sultan'),
(673,'Firdevs-Hasan Aykanat','5366370529','2034 Sk. Bergama 2 apt. No:34 D:25','İzmir','Karşıyaka','Alkali',1,2000,'2026-01-21'::date,'Ali','Sultan'),
(674,'Turgut Çalışkan','5368306801','6280/1 Sk.No:9 K:5 D:15','İzmir','Karşıyaka','Tam Takım',1,1100,'2026-01-21'::date,'Ali','Sultan'),
(675,'Burhan Eker','5334728155','72 Sk. No:6 D:8 Atıfbey Mh.','İzmir','Gaziemir','Lg Eco',1,8000,'2026-01-21'::date,'Ali','Sultan'),
(676,'Burhan Eker','5334728155','72 Sk. No:6 D:8 Atıfbey Mh.','İzmir','Gaziemir','Alkali',1,2000,'2026-01-21'::date,'Ali','Sultan'),
(677,'Gazi Keleş','5334932687','Kasımpaşa Mh. 255 Sk. No:5/1','İzmir','Menderes','Tam Takım',2,2200,'2026-01-21'::date,'Ali','Sultan'),
(678,'Emin Keleş','5446012636','İnönü Mh. 994 Sk. No:31 K:1 D:1','İzmir','Bornova','Tam Takım',1,1100,'2026-01-21'::date,'Ali','Sultan'),
(679,'İsmail Söbe','5056876266','Akın Kıvanç Sk. No:79 D:12','İzmir','Karşıyaka','Tam Takım',1,1100,'2026-01-21'::date,'Ali','Sultan'),
(680,'Musa Gezer','5322459473','Menderes Cd. Cumhuriyet Mh. No:38 Oğlananası','İzmir','Menderes','Tam Takım',1,1100,'2026-01-21'::date,'Ali','Sultan'),
(681,'Musa Gezer','5322459473','Menderes Cd. Cumhuriyet Mh. No:38 Oğlananası','İzmir','Menderes','Alkali',1,1100,'2026-01-21'::date,'Ali','Sultan'),
(682,'Ali Osman Ayvacı','5377486450','1163 Sk. No:54 K:1 D:1','İzmir','Konak','Musluk',1,600,'2026-01-22'::date,'Ali','Sultan'),
(683,'Haydar Bilgen','5327030817','6743 Sk. No:31 D:3 İnönü Mh.','İzmir','Karşıyaka','Tam Takım',1,1100,'2026-01-22'::date,'Ali','Sultan'),
(684,'Fatma Şen','5330257084','284 Sk. No:12 K:2 D:4','İzmir','Konak','Tam Takım',1,1000,'2026-01-22'::date,'Ali','Sultan'),
(685,'Fatma Şen','5330257084','284 Sk. No:12 K:2 D:4','İzmir','Konak','Alkali',1,1000,'2026-01-22'::date,'Ali','Sultan'),
(686,'Nesimi Bek','5392589977','4743 Sk. No:3 D:4','İzmir','Karşıyaka','Lg Eco',1,7000,'2026-01-22'::date,'Ali','Sultan'),
(687,'Nesimi Bek','5392589977','4743 Sk. No:3 D:4','İzmir','Karşıyaka','Alkali',1,3000,'2026-01-22'::date,'Ali','Sultan'),
(688,'Yeşim Komaç','5336403693','Dr. Orhan Altyözük Sk. No:12 K:2 D:7','İzmir','Karşıyaka','Tam Takım',1,1100,'2026-01-22'::date,'Ali','Sultan'),
(689,'Süreyla Tekçe','5011013578','290/9 Sk. No:7 D:1','İzmir','Buca','Tam Takım',1,1100,'2026-01-22'::date,'Ali','Sultan'),
(690,'Süreyla Tekçe','5011013578','290/9 Sk. No:7 D:1','İzmir','Buca','Alkali',1,1100,'2026-01-22'::date,'Ali','Sultan'),
(691,'Ahmet Özdemir','','Kemalpasa cd. No:287','İzmir','Bornova','Lg Eco',1,3500,'2026-01-23'::date,'Ali','Sultan'),
(692,'Nazmiye Özcan','5383600868','754 Sk. No:74','İzmir','Bornova','Lg Eco',1,5000,'2026-01-23'::date,'Ali','Sultan'),
(693,'Nazmiye Özcan','5383600868','754 Sk. No:74','İzmir','Bornova','Alkali',1,1500,'2026-01-23'::date,'Ali','Sultan'),
(694,'İlhan Bozca','5454803385','8809/13 Sk. No:10 K:4 D:16','İzmir','Çiğli','Tam Takım',3,3300,'2026-01-23'::date,'Ali','Sultan'),
(695,'Banu Çiçekçi','5326536850','8846 Sk. No:4 K:7 D:15','İzmir','Çiğli','Tam Takım',1,1100,'2026-01-23'::date,'Ali','Sultan'),
(696,'Selçuk Sezen','5356583206','Ergene Mh. 523 Sk. No:40 K:1 D:1','İzmir','Bornova','Tam Takım',1,1100,'2026-01-23'::date,'Ali','Sultan'),
(697,'Şefik Gültekin','5399443030','Kızılay Mh. 716 Sk. No:23 D:5','İzmir','Bornova','Tam Takım',1,1100,'2026-01-23'::date,'Ali','Sultan'),
(698,'Veysel Bayram Özkılıç','5323348334','Aşık Veysel Sk. No:9 D:4 Atakent','İzmir','Karşıyaka','Tam Takım',1,1100,'2026-01-23'::date,'Ali','Sultan'),
(699,'Veysel Bayram Özkılıç','5323348334','Aşık Veysel Sk. No:9 D:4 Atakent','İzmir','Karşıyaka','Alkali',1,1100,'2026-01-23'::date,'Ali','Sultan'),
(700,'Nihat Mert','5358546970','1851/10 Sk. No:7 K:3 D:5','İzmir','Karşıyaka','Tam Takım',1,1100,'2026-01-23'::date,'Ali','Sultan'),
(701,'Mahmut Ada','5392947194','4992 Sk. No:4','İzmir','Karabağlar','Tam Takım',1,1100,'2026-01-24'::date,'Ali','Sultan'),
(702,'Osman Turgay','5372563700','3972/1 Sk. No:3 D:2','İzmir','Karabağlar','Tam Takım',1,1100,'2026-01-24'::date,'Ali','Sultan'),
(703,'Osman Turgay','5372563700','3972/1 Sk. No:3 D:2','İzmir','Karabağlar','Shut off',1,300,'2026-01-24'::date,'Ali','Sultan'),
(704,'İlhami Kotan','5057150481','3771/16 Sk. No:6 K:5 D:23','İzmir','Karabağlar','Tam Takım',1,1100,'2026-01-24'::date,'Ali','Sultan'),
(705,'Ahmet Özdemir (Raif Bey)','','','İzmir','Bornova','Lg Eco',1,3500,'2026-01-24'::date,'Ali','Sultan'),
(706,'Mesut Kepenek','5321733050','646/15 Sk. No:3 D:2/4','İzmir','Buca','Tam Takım',1,2200,'2026-01-24'::date,'Ali','Sultan'),
(707,'Murat Bey','5545506789','100. Yıl Mh. 1925 Sk. No:167 153 Blok D:4','İzmir','Bayraklı','Tam Takım',1,1100,'2026-01-26'::date,'Ali','Sultan'),
(708,'Vedat Uğur Tek','5355152316','6265/2 Sk. No:4 K:3 D:16','İzmir','Karşıyaka','Tam Takım',1,1100,'2026-01-26'::date,'Ali','Sultan'),
(709,'Ergün Sayer','5058219263','4021 Sk. No:2/1 K:2 D:2','İzmir','Bornova','Tam Takım',1,1100,'2026-01-26'::date,'Ali','Sultan'),
(710,'Yüksel Bahadır','5366239881','202/26 Sk No:1 D:2','İzmir','Buca','Tam Takım',1,1100,'2026-01-26'::date,'Ali','Sultan'),
(711,'Yüksel Bahadır','5366239881','202/26 Sk No:1 D:2','İzmir','Buca','Alkali',1,1100,'2026-01-26'::date,'Ali','Sultan'),
(712,'Ramazan Gökhan Gülbahar','5468008887','1320 Sk. No:4 K:4 D:16','İzmir','Buca','Tam Takım',1,1100,'2026-01-27'::date,'Ali','Sultan'),
(713,'Çimen Karaca','5308402791','91 Sk. No:22 K:4 D:18','İzmir','Torbalı','Tam Takım',1,1100,'2026-01-27'::date,'Ali','Sultan'),
(714,'Çimen Karaca','5308402791','91 Sk. No:22 K:4 D:18','İzmir','Torbalı','Alkali',1,1100,'2026-01-27'::date,'Ali','Sultan'),
(715,'İkbal Değer','5423533752','Mithatpaşa cd. No:913 K:1 D:3 Güzelyalı','İzmir','Konak','Tam Takım',1,1100,'2026-01-27'::date,'Ali','Sultan'),
(716,'İkbal Değer','5423533752','Mithatpaşa cd. No:913 K:1 D:3 Güzelyalı','İzmir','Konak','Alkali',1,1500,'2026-01-27'::date,'Ali','Sultan'),
(717,'Necdet Aktaş','5332875590','5714/1 Sk. No:415A','İzmir','Karabağlar','Tam Takım',1,1000,'2026-01-27'::date,'Ali','Sultan'),
(718,'Necdet Aktaş','5332875590','5714/1 Sk. No:415A','İzmir','Karabağlar','Alkali',1,1000,'2026-01-27'::date,'Ali','Sultan'),
(719,'Salim Yılmaz','5052655193','370 Sk. No: 61/4','İzmir','Karabağlar','Tam Takım',1,1100,'2026-01-27'::date,'Ali','Sultan'),
(720,'Şükrü Tonel','5423721944','157 Sk. No:8 K:1 D:1','İzmir','Gaziemir','Tam Takım',1,1100,'2026-01-28'::date,'Ali','Sultan'),
(721,'Ömer Acar','5316406548','341 Sk. No:32/1 K:2 D:5','İzmir','Konak','Tam Takım',1,1000,'2026-01-28'::date,'Ali','Sultan'),
(722,'Ömer Acar','5316406548','341 Sk. No:32/1 K:2 D:5','İzmir','Konak','Alkali',1,1000,'2026-01-28'::date,'Ali','Sultan'),
(723,'Fahrettin Eğrikanat','5373009495','4516 Sk. No:33','İzmir','Karabağlar','Lg Eco',1,6000,'2026-01-28'::date,'Ali','Sultan'),
(724,'Fahrettin Eğrikanat','5373009495','4516 Sk. No:33','İzmir','Karabağlar','Alkali',1,2000,'2026-01-28'::date,'Ali','Sultan'),
(725,'Şehnaz Öztürk','5374849353','5005 Sk. No:26 D:1','İzmir','Karabağlar','Tam Takım',1,1100,'2026-01-28'::date,'Ali','Sultan'),
(726,'Ayşegül Toprak Özkul','5412905784','Laleli Mh. 429 Sk. No:22 K:3 D:4','İzmir','Buca','Lg Eco',1,6000,'2026-01-28'::date,'Ali','Sultan'),
(727,'Ayşegül Toprak Özkul','5412905784','Laleli Mh. 429 Sk. No:22 K:3 D:4','İzmir','Buca','Alkali',1,2000,'2026-01-28'::date,'Ali','Sultan'),
(728,'Mustafa Çoban','5353745815','862 Sk. No:37 K:1 D:1','İzmir','Buca','Tam Takım',1,1100,'2026-01-28'::date,'Ali','Sultan'),
(729,'Zeki Özbek','5355566744','341 Sk. No:31 D:4','İzmir','Buca','Montaj',1,500,'2026-01-28'::date,'Ali','Sultan'),
(730,'Necip Hassoy','5323959830','1419/1 Sk. No:1 K:6 D:22','İzmir','Buca','Lg Eco',1,6000,'2026-01-28'::date,'Ali','Sultan'),
(731,'Necip Hassoy','5323959830','1419/1 Sk. No:1 K:6 D:22','İzmir','Buca','Alkali',1,2000,'2026-01-28'::date,'Ali','Sultan'),
(732,'Refiye Yılmaz','5323201614','429 Sk. No:22 D:2','İzmir','Buca','Tam Takım',1,1100,'2026-01-28'::date,'Ali','Sultan'),
(733,'Ali Ekiz','5335609137','2092 Sk. No: 13A','İzmir','Bayraklı','Tam Takım',1,1000,'2026-01-29'::date,'Ali','Sultan'),
(734,'Ali Ekiz','5335609137','2092 Sk. No: 13A','İzmir','Bayraklı','Alkali',1,1000,'2026-01-29'::date,'Ali','Sultan'),
(735,'Leyla Gülşen','5070193976','1024 Sk. No:5 D:1 Sarnıç','İzmir','Gaziemir','Tam Takım',1,1100,'2026-01-29'::date,'Ali','Sultan'),
(736,'Doğan Eray','5417760170','670/2 Sk. No: 6/8 K:1 D:2','İzmir','Buca','Lg Eco',1,5500,'2026-01-29'::date,'Ali','Sultan'),
(737,'Doğan Eray','5417760170','670/2 Sk. No: 6/8 K:1 D:2','İzmir','Buca','Alkali',1,1500,'2026-01-29'::date,'Ali','Sultan'),
(738,'Kamil Türkmen','5346672262','240 Sk. No:23 D:2','İzmir','Bayraklı','Tam Takım',1,1100,'2026-01-29'::date,'Ali','Sultan'),
(739,'Saim Ergül','5382260438','1847/5 Sk. No: 6/1 D:1 Örnekköy','İzmir','Karşıyaka','Lg Eco',1,5000,'2026-01-29'::date,'Ali','Sultan'),
(740,'Saim Ergül','5382260438','1847/5 Sk. No: 6/1 D:1 Örnekköy','İzmir','Karşıyaka','Alkali',1,1000,'2026-01-29'::date,'Ali','Sultan'),
(741,'Melek Yıldız','5301394913','Dr. Orhan Akyörük Sk. No:2 D: 4','İzmir','Karşıyaka','Tam Takım',1,1100,'2026-01-29'::date,'Ali','Sultan'),
(742,'Hakan Bursalı','5053509021','Yelki Mh. 2267 Sk. No:4 D:5','İzmir','Güzelbahçe','Lg Eco',1,7000,'2026-01-30'::date,'Ali','Sultan'),
(743,'Hakan Bursalı','5053509021','Yelki Mh. 2267 Sk. No:4 D:5','İzmir','Güzelbahçe','Alkali',1,1000,'2026-01-30'::date,'Ali','Sultan'),
(744,'Hayrettin Mutugu','5356508837','Ilıca Mh. Ilıca Sk. No:9 D:10','İzmir','Narlıdere','Tam Takım',1,1100,'2026-01-30'::date,'Ali','Sultan'),
(745,'Hayrettin Mutugu','5356508837','Ilıca Mh. Ilıca Sk. No:9 D:10','İzmir','Narlıdere','Musluk',1,750,'2026-01-30'::date,'Ali','Sultan'),
(746,'Hakan Serin','5543475616','14/4 Sk. No:19 D:9','İzmir','Karabağlar','Tam Takım',1,1100,'2026-01-30'::date,'Ali','Sultan'),
(747,'Hüseyin Kündür','5078950049','M. Fevzi Çakmak Mh. 4124 Sk. No:22 D:1','İzmir','Urla','Tam Takım',1,1100,'2026-01-30'::date,'Ali','Sultan'),
(748,'Memet Ferah','5058324254','Sipahiler Sk. No:1 D:3','İzmir','Balçova','Lg Eco',1,6000,'2026-01-30'::date,'Ali','Sultan'),
(749,'Memet Ferah','5058324254','Sipahiler Sk. No:1 D:3','İzmir','Balçova','Alkali',1,2000,'2026-01-30'::date,'Ali','Sultan'),
(750,'Neslihan Demiral','5056891241','Eğitim Mh. Ahmet Yatman Sk. No:34 D:1 K:1','İzmir','Balçova','Tam Takım',1,1100,'2026-01-30'::date,'Ali','Sultan'),
(751,'Neslihan Demiral','5056891241','Eğitim Mh. Ahmet Yatman Sk. No:34 D:1 K:1','İzmir','Balçova','Alkali',1,1100,'2026-01-30'::date,'Ali','Sultan'),
(752,'Mukadden Tekin','5363177379','Yeni Mh. General Fahrettin Sk. No:12A K:2','İzmir','Balçova','Tam Takım',1,1100,'2026-01-30'::date,'Ali','Sultan'),
(753,'Nejla Elkıran','5077886632','4141 Sk. No:8 Zeytinalanı','İzmir','Urla','Lg Eco',1,6000,'2026-01-30'::date,'Ali','Sultan'),
(754,'Nejla Elkıran','5077886632','4141 Sk. No:8 Zeytinalanı','İzmir','Urla','Alkali',1,2000,'2026-01-30'::date,'Ali','Sultan'),
(755,'Fatih Kaplan','5373611212','596 Sk. No:20 D:6 Osmangazi','İzmir','Bayraklı','Lg Eco',1,7000,'2026-01-31'::date,'Ali','Sultan'),
(756,'Fatih Kaplan','5373611212','596 Sk. No:20 D:6 Osmangazi','İzmir','Bayraklı','Alkali',1,1000,'2026-01-31'::date,'Ali','Sultan'),
(757,'Yavuz Koldaş','5545648742','2163 Sk. No:1 D:1 Müstakil','İzmir','Bayraklı','Lg Eco',1,5500,'2026-01-31'::date,'Ali','Sultan'),
(758,'Yavuz Koldaş','5545648742','2163 Sk. No:1 D:1 Müstakil','İzmir','Bayraklı','Alkali',1,1500,'2026-01-31'::date,'Ali','Sultan'),
(759,'Ertan Sevinç','5300472735','Postaevler Mh. 7662 Sk. No: 7 D:1','İzmir','Bayraklı','Tam Takım',1,1100,'2026-01-31'::date,'Ali','Sultan'),
(760,'Ertan Sevinç','5300472735','Postaevler Mh. 7662 Sk. No: 7 D:1','İzmir','Bayraklı','Alkali',1,1100,'2026-01-31'::date,'Ali','Sultan'),
(761,'Ali Gürcur','5435338593','1930/1 Sk. No:76 F65 Blok D:9','İzmir','Bayraklı','Tam Takım',1,1100,'2026-01-31'::date,'Ali','Sultan'),
(762,'Semahat Üstüner','5057503615','1787/1 Sk. No:47 D:2 Bostanlı','İzmir','Karşıyaka','Tam Takım',1,1100,'2026-01-31'::date,'Ali','Sultan'),
(763,'Fadime Gürbüzer','5334940839','688/12 Sk. No:22 K:7 D:40','İzmir','Buca','Lg Eco',1,6500,'2026-01-31'::date,'Ali','Sultan'),
(764,'Fadime Gürbüzer','5334940839','688/12 Sk. No:22 K:7 D:40','İzmir','Buca','3 Yollu Musluk',1,2000,'2026-01-31'::date,'Ali','Sultan'),
(765,'Hasan Uzunbaz','5452995615','Anadolu Cd. No:63 K:5 D:20','İzmir','Bayraklı','Lg Eco',1,5500,'2026-01-31'::date,'Ali','Sultan'),
(766,'Hasan Uzunbaz','5452995615','Anadolu Cd. No:63 K:5 D:20','İzmir','Bayraklı','Alkali',1,1500,'2026-01-31'::date,'Ali','Sultan'),
(767,'Ahmet Gedik','5075030984','856 Sk. No:66 K:5 D:10','İzmir','Buca','Tam Takım',1,1100,'2026-02-02'::date,'Ali','Sultan'),
(768,'Ahmet Gedik','5075030984','856 Sk. No:66 K:5 D:10','İzmir','Buca','Alkali',1,1100,'2026-02-02'::date,'Ali','Sultan'),
(769,'Remzi Özsiner','5418701619','2579 Sk. No:43 D:3 Millet Mh.','İzmir','Konak','Tam Takım',1,1100,'2026-02-02'::date,'Ali','Sultan'),
(770,'Remzi Özsiner','5418701619','2579 Sk. No:43 D:3 Millet Mh.','İzmir','Konak','Montaj',1,800,'2026-02-02'::date,'Ali','Sultan'),
(771,'Münevver Çuhacı','5059889828','5238 Sk. No:8 D:2','İzmir','Bornova','Tam Takım',1,1000,'2026-02-02'::date,'Ali','Sultan'),
(772,'Hatice Yıldırım','5362582641','3141 Sk. No:1-3 No:5','İzmir','Karabağlar','Tam Takım',1,1100,'2026-02-02'::date,'Ali','Sultan'),
(773,'Hülya Dikayak','5330358324','5003 Sk. No:40 Çamdibi','İzmir','Bornova','Tam Takım',1,1100,'2026-02-02'::date,'Ali','Sultan'),
(774,'Ömer Çenik','5525901784','3900 Sk. No:16A K:2','İzmir','Karabağlar','Tam Takım',1,1100,'2026-02-02'::date,'Ali','Sultan'),
(775,'Erdoğan Demirel','5418136290','Aydın Hotkoyu Cd. No:553A','İzmir','Buca','Tam Takım',1,1100,'2026-02-02'::date,'Ali','Sultan'),
(776,'Muzaffer Yıldırım','5358274259','4030/1 Sk. No:3 D:4','İzmir','Bornova','Tam Takım',1,1000,'2026-02-02'::date,'Ali','Sultan'),
(777,'Seda Gündoğdu','5528623915','Seyitnizam mh. Topkapı küpteşevleri 2. etap A-7 Blok D:29','İstanbul','Zeytinburnu','Lg Eco',1,8000,'2026-02-02'::date,'',''),
(778,'Zeynep Başaran','5344152620','582 Sk. No:36 K:3 D:3','İzmir','Konak','Lg Eco',1,5500,'2026-02-03'::date,'Ali','Sultan'),
(779,'Zeynep Başaran','5344152620','582 Sk. No:36 K:3 D:3','İzmir','Konak','Alkali',1,1500,'2026-02-03'::date,'Ali','Sultan'),
(780,'Zeynep Başaran','5344152620','582 Sk. No:36 K:3 D:3','İzmir','Konak','Üç Yollu Musluk',1,2500,'2026-02-03'::date,'Ali','Sultan'),
(781,'Zeynep Başaran','5344152620','582 Sk. No:36 K:3 D:3','İzmir','Konak','Sebil Ap.',1,1000,'2026-02-03'::date,'Ali','Sultan'),
(782,'Leyla Aksu','5077757520','65/20 Sk No:31 D:3 Üçkuyular','İzmir','Karabağlar','Lg Eco',1,5500,'2026-02-03'::date,'Ali','Sultan'),
(783,'Leyla Aksu','5077757520','65/20 Sk No:31 D:3 Üçkuyular','İzmir','Karabağlar','Alkali',1,1500,'2026-02-03'::date,'Ali','Sultan'),
(784,'Mehmet Altun','5352174588','1107 Sk. No:6 Akarcalı mh.','İzmir','Konak','Tam Takım',1,1100,'2026-02-03'::date,'Ali','Sultan'),
(785,'Gülay Yener','5428380102','Eğitim Mh. Ruşen Eşref Sk. No:54 D:3','İzmir','Balçova','Lg Eco',1,5500,'2026-02-03'::date,'Ali','Sultan'),
(786,'Gülay Yener','5428380102','Eğitim Mh. Ruşen Eşref Sk. No:54 D:3','İzmir','Balçova','Alkali',1,1500,'2026-02-03'::date,'Ali','Sultan'),
(787,'Hafize Karakaya','5356701652','Osmangazi Mh. 597/4 Sk. No:2 A blok K:5 D:11','İzmir','Bayraklı','Tam Takım',1,1100,'2026-02-04'::date,'Ali','Sultan'),
(788,'Cuma Çetin','5379859575','Hürriyet Cd. No:156 K:3 D:3','İzmir','Bornova','Tam Takım',1,1100,'2026-02-04'::date,'Ali','Sultan'),
(789,'Ogün Sefer','5396721689','1271/2 Sk. No:10 K:1 K:2 Naldöken','İzmir','Bornova','Tam Takım',2,2200,'2026-02-04'::date,'Ali','Sultan'),
(790,'Hamza Açıkgöz','5054146536','6792/1 Sk. No:10 D:13','İzmir','Çiğli','Tam Takım',1,1100,'2026-02-04'::date,'Ali','Sultan'),
(791,'Hamza Açıkgöz','5054146536','6792/1 Sk. No:10 D:13','İzmir','Çiğli','Alkali',1,1100,'2026-02-04'::date,'Ali','Sultan'),
(792,'Turan Bezgal','5055437031','6762/1 Sk. No:2 D:15 K:7','İzmir','Çiğli','Tam Takım',1,1100,'2026-02-04'::date,'Ali','Sultan'),
(793,'Turan Bezgal','5055437031','6762/1 Sk. No:2 D:15 K:7','İzmir','Çiğli','Alkali',1,1100,'2026-02-04'::date,'Ali','Sultan'),
(794,'Halil Kavalcı','5539811136','8843/1 Sk. No:1 K:3 D:9','İzmir','Çiğli','Tam Takım',1,1100,'2026-02-04'::date,'Ali','Sultan'),
(795,'Neziha Bora','5385151592','8823 Sk. No:9 D:5 Egekent','İzmir','Çiğli','Tam Takım',1,1100,'2026-02-04'::date,'Ali','Sultan'),
(796,'Mehmet Korkmaz','5414109780','1318 Sk. No:21 K:5','İzmir','Menemen','Tam Takım',1,1100,'2026-02-04'::date,'Ali','Sultan'),
(797,'Murat Taşan','5056716232','30 Ağustos Mh. 7104/2 Sk. No:1B K:2 D:12','İzmir','Menemen','Lg Eco',1,6000,'2026-02-04'::date,'Ali','Sultan'),
(798,'Murat Taşan','5056716232','30 Ağustos Mh. 7104/2 Sk. No:1B K:2 D:12','İzmir','Menemen','Alkali',1,2000,'2026-02-04'::date,'Ali','Sultan'),
(799,'Muzaffer Yavuz','5336622825','Eşrefpaşa Mh. 1211 Sk. No:7 D:5 K:3','İzmir','Menemen','Lg Eco',1,6000,'2026-02-04'::date,'Ali','Sultan'),
(800,'Muzaffer Yavuz','5336622825','Eşrefpaşa Mh. 1211 Sk. No:7 D:5 K:3','İzmir','Menemen','Alkali',1,2000,'2026-02-04'::date,'Ali','Sultan'),
(801,'İkbal Çabuk','5535389771','129/13 Sk. No:23 Evka-3','İzmir','Bornova','Tam Takım',1,1100,'2026-02-04'::date,'Ali','Sultan'),
(802,'İbrahim Baydere','5325108877','İnönü Mh. 187/6 No:6 K:4 D:5','İzmir','Torbalı','Lg Eco',1,6000,'2026-02-05'::date,'Ali','Sultan'),
(803,'Aydın Kayapınar','5336321381','83 Sk. No:13 K:5 D:21 Ayrancılar','İzmir','Torbalı','Tam Takım',1,1000,'2026-02-05'::date,'Ali','Sultan'),
(804,'Erdal Polat','5519072655','3945/7 Sk. No:6 K:4 D:10','İzmir','Karabağlar','Tam Takım',1,1100,'2026-02-05'::date,'Ali','Sultan'),
(805,'Faruk Görsün','5075469223','1573 Sk. No:11 K:3 D:12','İzmir','Torbalı','Tam Takım',1,1100,'2026-02-05'::date,'Ali','Sultan'),
(806,'Mehmet Cokal','5077757503','4621 Sk. No:2 D:3','İzmir','Karabağlar','Tam Takım',1,1100,'2026-02-05'::date,'Ali','Sultan'),
(807,'Mehmet Cokal','5077757503','4621 Sk. No:2 D:3','İzmir','Karabağlar','Tank',1,1200,'2026-02-05'::date,'Ali','Sultan'),
(808,'Uğur Sevgel','5465740071','5715 Sk. No:11 D:2','İzmir','Karabağlar','Tam Takım',1,1100,'2026-02-05'::date,'Ali','Sultan'),
(809,'Uğur Sevgel','5465740071','5715 Sk. No:11 D:2','İzmir','Karabağlar','Alkali',1,1100,'2026-02-05'::date,'Ali','Sultan'),
(810,'Mithat Çelikten','5358925305','Atatürk Mh. Türkaz Sitesi Kapıcı Dairesi','İzmir','Bornova','Tam Takım',1,1000,'2026-02-05'::date,'Ali','Sultan'),
(811,'Mithat Çelikten','5358925305','Atatürk Mh. Türkaz Sitesi Kapıcı Dairesi','İzmir','Bornova','Alkali',1,1000,'2026-02-05'::date,'Ali','Sultan'),
(812,'Kasım Sert','5324731084','3721 Sk. No:30 D: Giriş','İzmir','Bornova','Tam Takım',1,1000,'2026-02-05'::date,'Ali','Sultan'),
(813,'Kasım Sert','5324731084','3721 Sk. No:30 D: Giriş','İzmir','Bornova','Alkali',1,1000,'2026-02-05'::date,'Ali','Sultan'),
(814,'Kenan Sevgel','5073841100','214 Sk. No:17 K:4 D:4','İzmir','Bornova','Tam Takım',1,1100,'2026-02-06'::date,'Ali','Sultan'),
(815,'Yusuf Karademir','5054009027','Donanmacı Mh. 1727 Sk. No:21 D:1','İzmir','Karşıyaka','Lg Eco',1,5000,'2026-02-07'::date,'Ali','Sultan'),
(816,'Yusuf Karademir','5054009027','Donanmacı Mh. 1727 Sk. No:21 D:1','İzmir','Karşıyaka','Alkali',1,1500,'2026-02-07'::date,'Ali','Sultan'),
(817,'Fadime Candoğan','5414155295','526/3 Sk. No:6 D:1 K:1','İzmir','Konak','Tam Takım',1,1100,'2026-02-07'::date,'Ali','Sultan'),
(818,'Emel Uytu','5526828542','779 Sk. No:2 Müstakil','İzmir','Konak','Tam Takım',1,1100,'2026-02-07'::date,'Ali','Sultan'),
(819,'Hikmet Gürel','5365696029','Karacaoğlan Mh. 6236 Sk. No:35 K:1 D:3','İzmir','Bornova','Lg Eco',1,5800,'2026-02-07'::date,'Ali','Sultan'),
(820,'Hikmet Gürel','5365696029','Karacaoğlan Mh. 6236 Sk. No:35 K:1 D:3','İzmir','Bornova','Tam Takım',1,1100,'2026-02-07'::date,'Ali','Sultan'),
(821,'Hikmet Gürel','5365696029','Karacaoğlan Mh. 6236 Sk. No:35 K:1 D:3','İzmir','Bornova','Alkali',1,1100,'2026-02-07'::date,'Ali','Sultan'),
(822,'Figen Arslantekin','5431983035','5777 Sk. No:12 Müstakil','İzmir','Karabağlar','Lg Eco',1,5500,'2026-02-07'::date,'Ali','Sultan'),
(823,'Figen Arslantekin','5431983035','5777 Sk. No:12 Müstakil','İzmir','Karabağlar','Alkali',1,1500,'2026-02-07'::date,'Ali','Sultan'),
(824,'Murat Sakızoğlu','5305412130','242/33 Sk. No:8 K:5 D:17','İzmir','Buca','Lg Eco',1,6000,'2026-02-07'::date,'Ali','Sultan'),
(825,'Murat Sakızoğlu','5305412130','242/33 Sk. No:8 K:5 D:17','İzmir','Buca','Alkali',1,2000,'2026-02-07'::date,'Ali','Sultan'),
(826,'Mustafa Öztürk','5537089580','5055 Sk. No:5 D:1','İzmir','Karabağlar','Lg Eco',1,6000,'2026-02-07'::date,'Ali','Sultan'),
(827,'Mustafa Öztürk','5537089580','5055 Sk. No:5 D:1','İzmir','Karabağlar','Alkali',1,2000,'2026-02-07'::date,'Ali','Sultan'),
(828,'Hakan Aydemir','5444278834','5055 Sk. No:5 D:2 K:2','İzmir','Karabağlar','Lg Eco',1,6000,'2026-02-07'::date,'Ali','Sultan'),
(829,'Hakan Aydemir','5444278834','5055 Sk. No:5 D:2 K:2','İzmir','Karabağlar','Alkali',1,2000,'2026-02-07'::date,'Ali','Sultan'),
(830,'Ayhan Karadaş','5301161447','565 Sk. No:32 D:2','İzmir','Ayrancılar','Tam Takım',1,1100,'2026-02-07'::date,'Ali','Sultan'),
(831,'Gül Ömür','5347363301','78. Sk. No:1 K:4 D:10','İzmir','Konak','Tam Takım',1,1100,'2026-02-10'::date,'Ali','Sultan'),
(832,'Tuncay Fırat','5323010057','158 Sk. No:15 D:1 Güvendik Mh.','İzmir','Urla','Tam Takım',1,1100,'2026-02-10'::date,'Ali','Sultan'),
(833,'Tuncay Fırat','5323010057','158 Sk. No:15 D:1 Güvendik Mh.','İzmir','Urla','Alkali',1,1500,'2026-02-10'::date,'Ali','Sultan'),
(834,'Selma Erdemir','5334027015','Doğu Sk. No:5 D:5','İzmir','Narlıdere','Lg Eco',1,6000,'2026-02-10'::date,'Ali','Sultan'),
(835,'Selma Erdemir','5334027015','Doğu Sk. No:5 D:5','İzmir','Narlıdere','Alkali',1,2000,'2026-02-10'::date,'Ali','Sultan'),
(836,'Zeki Atabay','5305457064','Saltuk Buğra Han Cd. No:23 D:18 K:5','İzmir','Evka-4','Lg Eco',1,5500,'2026-02-11'::date,'Ali','Sultan'),
(837,'Zeki Atabay','5305457064','Saltuk Buğra Han Cd. No:23 D:18 K:5','İzmir','Evka-4','Alkali',1,1500,'2026-02-11'::date,'Ali','Sultan'),
(838,'Necati Karaosmanoğlu','5386031718','8026 Sk. No:2 K:1 D:1','İzmir','Çiğli','Tam Takım',1,1100,'2026-02-11'::date,'Ali','Sultan'),
(839,'İrfan Nişancı','5372135536','1859 Sk. No:20 D:7','İzmir','Karşıyaka','Tam Takım',1,1100,'2026-02-11'::date,'Ali','Sultan'),
(840,'Fatih Utkugün','5333055253','1739 Sk. No:4 D:5','İzmir','Karşıyaka','Tam Takım',1,1100,'2026-02-11'::date,'Ali','Sultan'),
(841,'Sayit Yıldız','5425441051','8211/9 Sk. No:8 D:18 K:5','İzmir','Çiğli','Lg Eco',1,6000,'2026-02-11'::date,'Ali','Sultan'),
(842,'Sayit Yıldız','5425441051','8211/9 Sk. No:8 D:18 K:5','İzmir','Çiğli','Alkali',1,2000,'2026-02-11'::date,'Ali','Sultan'),
(843,'Yiğit Yıldız','5425441051','8211/9 Sk. No:8 D:18 K:5','İzmir','Çiğli','Lg Eco',1,6000,'2026-02-11'::date,'Ali','Sultan'),
(844,'Yiğit Yıldız','5425441051','8211/9 Sk. No:8 D:18 K:5','İzmir','Çiğli','Alkali',1,2000,'2026-02-11'::date,'Ali','Sultan'),
(845,'Hasan Tüğen','5324002640','1847/17 Sk. No:6 D:22','İzmir','Bayraklı','Lg Eco',1,9000,'2026-02-11'::date,'Ali','Sultan'),
(846,'Hasan Tüğen','5324002640','1847/17 Sk. No:6 D:22','İzmir','Bayraklı','Alkali',1,3000,'2026-02-11'::date,'Ali','Sultan'),
(847,'Hasan Tüğen','5324002640','1847/17 Sk. No:6 D:22','İzmir','Bayraklı','Tam Takım',1,1000,'2026-02-11'::date,'Ali','Sultan'),
(848,'Fatih Uğur','5353352592','945/2 Sk. No:6 Müstakil','İzmir','Bornova','Lg Eco',1,5500,'2026-02-11'::date,'Ali','Sultan'),
(849,'Fatih Uğur','5353352592','945/2 Sk. No:6 Müstakil','İzmir','Bornova','Alkali',1,1500,'2026-02-11'::date,'Ali','Sultan'),
(850,'İdris Muhammet','5077758040','3709 Sk. No:28 K:2','İzmir','Karabağlar','Lg Eco',1,5500,'2026-02-11'::date,'Ali','Sultan'),
(851,'İdris Muhammet','5077758040','3709 Sk. No:28 K:2','İzmir','Karabağlar','Alkali',1,1500,'2026-02-11'::date,'Ali','Sultan'),
(852,'Ömer Akın','5324416573','4506 Sk. No:6 K:1 D:1','İzmir','Karabağlar','Tam Takım',1,1100,'2026-02-11'::date,'Ali','Sultan'),
(853,'Evin Yeşilova','5542199896','132 Sk. No:4 D:2','İzmir','Gaziemir','Tam Takım',1,1100,'2026-02-11'::date,'Ali','Sultan'),
(854,'Fatma Coşkun','5528013952','679/5 Sk. No:3 K:4','İzmir','Buca','Tam Takım',1,1100,'2026-02-11'::date,'Ali','Sultan'),
(855,'Kasım Eren','5313742032','288/2 No:26 D:3','İzmir','Buca','Tam Takım',1,1100,'2026-02-11'::date,'Ali','Sultan'),
(856,'Harun Doğaner','5435759586','3072 Sk. No:1/1 D:1','İzmir','Karabağlar','Tam Takım',1,1100,'2026-02-11'::date,'Ali','Sultan'),
(857,'Maşallah Kunur','5305286588','7353/4 Sk. No:3 K:2','İzmir','Bayraklı','Lg Eco',1,5500,'2026-02-11'::date,'Ali','Sultan'),
(858,'Maşallah Kunur','5305286588','7353/4 Sk. No:3 K:2','İzmir','Bayraklı','Alkali',1,1500,'2026-02-11'::date,'Ali','Sultan'),
(859,'Salim Tire','5317255385','1113 Sk. No:7 D:1 Sarnıç','İzmir','Gaziemir','Tam Takım',1,1900,'2026-02-13'::date,'Süleyman','Sultan'),
(860,'Gülgün Cangüler','5346440564','Murat Bey Mh. 3507 Sk. No:8 D:2','İzmir','Torbalı','Tam Takım',1,1100,'2026-02-13'::date,'Süleyman','Sultan'),
(861,'Bayram Bey','5343568049','2025 Sk. No:7 K:5','İzmir','','Tam Takım',1,1100,'2026-02-13'::date,'Süleyman','Sultan'),
(862,'İlhami Bey','','3055 Sk. No:23 K:2 D:9','İzmir','Torbalı','Tam Takım',1,1100,'2026-02-13'::date,'Süleyman','Sultan'),
(863,'Hasan Vurmak','','6. Cadde No:7 D:7','İzmir','Torbalı','Tam Takım',1,1000,'2026-02-13'::date,'Süleyman','Sultan'),
(864,'Hasan Vurmak(Komşusu)','','6. Cadde No:7 D:7','İzmir','Torbalı','Tam Takım',1,1500,'2026-02-13'::date,'Süleyman','Sultan'),
(865,'Çiğdem Oğuz','5527059062','7449 Sk. No:2 D:5','İzmir','Karşıyaka','Tam Takım',1,1100,'2026-02-13'::date,'Süleyman','Sultan'),
(866,'Mehmet Tümen','5462967374','8790/1 Sk. No:65 A Blok D:3','İzmir','Çiğli','Tam Takım',1,1100,'2026-02-13'::date,'Süleyman','Sultan'),
(867,'Mehmet Tümen','5462967374','8790/1 Sk. No:65 A Blok D:3','İzmir','Çiğli','Shut off',1,350,'2026-02-13'::date,'Süleyman','Sultan'),
(868,'Mehmet Tuncel','5326056898','7323/2 Sk. No:22 D:2','İzmir','Bayraklı','Tam Takım',1,1100,'2026-02-13'::date,'Süleyman','Sultan'),
(869,'Mehmet Tuncel','5326056898','7323/2 Sk. No:22 D:2','İzmir','Bayraklı','Tank',1,1300,'2026-02-13'::date,'Süleyman','Sultan'),
(870,'Mehmet Tuncel','5326056898','7323/2 Sk. No:22 D:2','İzmir','Bayraklı','Flow',1,100,'2026-02-13'::date,'Süleyman','Sultan'),
(871,'Banu Hanım','5326536850','8846 Sk. No:4 D:15','İzmir','Çiğli','Membran+Tcr',1,0,'2026-02-13'::date,'Süleyman','Sultan'),
(872,'İbrahim Birol','5552013637','6872/4 Sk. No:8','İzmir','Çiğli','Tam Takım',1,1100,'2026-02-13'::date,'Süleyman','Sultan'),
(873,'Murat Bey','5055121084','8001/3 Sk. No:95 K:3 D:6','İzmir','Çiğli','Lg Eco',1,6000,'2026-02-13'::date,'Süleyman','Sultan'),
(874,'Oktay Bulut','5524070893','8788/4 Sk. No:4/9','İzmir','Çiğli','Tam Takım',1,1100,'2026-02-13'::date,'Süleyman','Sultan'),
(875,'Oktay Bulut','5524070893','8788/4 Sk. No:4/9','İzmir','Çiğli','Shut off',1,350,'2026-02-14'::date,'Süleyman','Sultan'),
(876,'Özcan Bey','5079726362','923 Sk. No:16 D:1','İzmir','Bornova','Tam Takım',1,1100,'2026-02-14'::date,'Süleyman','Sultan'),
(877,'Aziz Bey','5325998392','113/13 Sk. No:6/67','İzmir','Bornova','Tam Takım',1,1100,'2026-02-14'::date,'Süleyman','Sultan'),
(878,'Aziz Bey','5325998392','113/13 Sk. No:6/67','İzmir','Bornova','Alkali',1,1100,'2026-02-14'::date,'Süleyman','Sultan'),
(879,'Aziz Bey','5325998392','113/13 Sk. No:6/67','İzmir','Bornova','Sed.+Blok',1,800,'2026-02-14'::date,'Süleyman','Sultan'),
(880,'Sedat Bey','5428448545','Ankara cd. No:163 D:25','İzmir','Bornova','Tam Takım',1,1100,'2026-02-14'::date,'Süleyman','Sultan'),
(881,'Salim Kocakahya','5398746060','5714/1 Sk. No:648 D:9','İzmir','Karabağlar','Lg Eco',1,5000,'2026-02-16'::date,'Süleyman','Sultan'),
(882,'Edibe Yardım','5358263802','9505 Sk. No:6','İzmir','Karabağlar','Tam Takım',1,1100,'2026-02-16'::date,'Süleyman','Sultan'),
(883,'Rıfat Öner','5322028156','9913 Sk. No:26 D:17','İzmir','Karabağlar','Tam Takım',1,1100,'2026-02-16'::date,'Süleyman','Sultan'),
(884,'Rıfat Öner','5322028156','9913 Sk. No:26 D:17','İzmir','Karabağlar','Alkali',1,900,'2026-02-16'::date,'Süleyman','Sultan'),
(885,'Hasan Ataş','','9313/1 Sk. No:2 D:14','İzmir','Karabağlar','Tam Takım',1,1100,'2026-02-16'::date,'Süleyman','Sultan'),
(886,'Hasan Ataş','','9313/1 Sk. No:2 D:14','İzmir','Karabağlar','Tank',1,1400,'2026-02-16'::date,'Süleyman','Sultan'),
(887,'Gülay Oğuz','5305758509','Mimar Sinan Sokağı No:11 D:1','İzmir','Balçova','Tam Takım',1,1100,'2026-02-16'::date,'Süleyman','Sultan'),
(888,'Nail Tezel','5382727814','Mehmetçik Blv. No:88 D:25','İzmir','Karabağlar','Tam Takım',1,1100,'2026-02-16'::date,'Süleyman','Sultan'),
(889,'Nail Tezel','5382727814','Mehmetçik Blv. No:88 D:25','İzmir','Karabağlar','Alkali',1,500,'2026-02-16'::date,'Süleyman','Sultan'),
(890,'Ahmet Abaycı','','Mehmetçik Blv. No:88 D:25','İzmir','Balçova','Tam Takım',1,1100,'2026-02-16'::date,'Süleyman','Sultan'),
(891,'Ahmet Abaycı','','Mehmetçik Blv. No:88 D:25','İzmir','Balçova','Tank',1,1100,'2026-02-16'::date,'Süleyman','Sultan'),
(892,'Ahmet Abaycı','','Mehmetçik Blv. No:88 D:25','İzmir','Balçova','Shutoff+flow',1,300,'2026-02-16'::date,'Süleyman','Sultan'),
(893,'Hüseyin Acar','5326347285','697/3 Sk. No:1 D:17','İzmir','Buca','Tam Takım',1,1100,'2026-02-16'::date,'Ali','Sultan'),
(894,'Hüseyin Acar','5326347285','697/3 Sk. No:1 D:17','İzmir','Buca','Musluk',1,600,'2026-02-16'::date,'Ali','Sultan'),
(895,'Bekir Şekerci','5334722304','800 Sk. No:2 D:8','İzmir','Gaziemir','Lg Eco',1,6000,'2026-02-16'::date,'Ali','Sultan'),
(896,'Bekir Şekerci','5334722304','800 Sk. No:2 D:8','İzmir','Gaziemir','Alkali',1,2000,'2026-02-16'::date,'Ali','Sultan'),
(897,'Sedat Tokay','5369295953','8104/1 Sk. No:5 D:6','İzmir','Ayrancılar','Lg Eco',1,5500,'2026-02-16'::date,'Ali','Sultan'),
(898,'Sedat Tokay','5369295953','8104/1 Sk. No:5 D:6','İzmir','Ayrancılar','Alkali',1,1000,'2026-02-16'::date,'Ali','Sultan'),
(899,'Metin Öz','5359264442','200/71 Sk. No:7 D:28','İzmir','Buca','Tam Takım',1,1100,'2026-02-16'::date,'Ali','Sultan'),
(900,'Metin Öz','5359264442','200/71 Sk. No:7 D:28','İzmir','Buca','Alkali',1,1100,'2026-02-16'::date,'Ali','Sultan'),
(901,'Metin Öz','5359264442','200/71 Sk. No:7 D:28','İzmir','Buca','Alkali',1,1100,'2026-02-16'::date,'Ali','Sultan'),
(902,'İbrahim Özkartal','5372500388','Zeki Yavaş No:110 K:6 D:23','İzmir','Bayraklı','Lg Eco',1,6000,'2026-02-17'::date,'Ali','Sultan'),
(903,'İbrahim Özkartal','5372500388','Zeki Yavaş No:110 K:6 D:23','İzmir','Bayraklı','Alkali',1,2000,'2026-02-17'::date,'Ali','Sultan'),
(904,'Muhammet Aslan','5356817860','Manavkuyu Mh. 275/14 Sk. No:2/1 D:1','İzmir','Bayraklı','Tam Takım',1,1100,'2026-02-17'::date,'Ali','Sultan'),
(905,'Emine Acar','5423738488','293/37 Sk. No:11A Çamlık','İzmir','Buca','Tam Takım',1,1100,'2026-02-17'::date,'Ali','Sultan'),
(906,'Şenol Yanar','5365652814','5147 Sk. No:30 Çamdibi','İzmir','Bornova','Lg Eco',1,6000,'2026-02-17'::date,'Ali','Sultan'),
(907,'Şenol Yanar','5365652814','5147 Sk. No:30 Çamdibi','İzmir','Bornova','Alkali',1,2000,'2026-02-17'::date,'Ali','Sultan'),
(908,'Aksel Hepbayraktar','5396580950','Koşukavak Mh. 4216 Sk. No:1 D:3','İzmir','Bornova','Tam Takım',1,1080,'2026-02-17'::date,'Ali','Sultan'),
(909,'Musap Pektaş','5538513512','Kazımdirik Mh. 174 Sk. No:11 K:4 D:9','İzmir','Bornova','Lg Eco',1,6000,'2026-02-17'::date,'Ali','Sultan'),
(910,'Musap Pektaş','5538513512','Kazımdirik Mh. 174 Sk. No:11 K:4 D:9','İzmir','Bornova','Alkali',1,2000,'2026-02-17'::date,'Ali','Sultan'),
(911,'Sedat Özgün','5314652078','Subaşı Mevlana Camii Lojmanı','İzmir','Torbalı','Lg Eco',1,6000,'2026-02-17'::date,'Ali','Sultan'),
(912,'Sedat Özgün','5314652078','Subaşı Mevlana Camii Lojmanı','İzmir','Torbalı','Alkali',1,2000,'2026-02-17'::date,'Ali','Sultan'),
(913,'Şehmuz Ağırağaç','5415774832','Atatürk Mh. 1563 Sk. No:16 D:2','İzmir','Torbalı','Lg Eco',1,5500,'2026-02-17'::date,'Ali','Sultan'),
(914,'Şehmuz Ağırağaç','5415774832','Atatürk Mh. 1563 Sk. No:16 D:2','İzmir','Torbalı','Alkali',1,1500,'2026-02-17'::date,'Ali','Sultan'),
(915,'Yasemin İzdeş','5546030544','312 Sk. No:30 D:3 Kozağaç','İzmir','Buca','Lg Eco',1,5500,'2026-02-18'::date,'Ali','Sultan'),
(916,'Yasemin İzdeş','5546030544','312 Sk. No:30 D:3 Kozağaç','İzmir','Buca','Alkali',1,1500,'2026-02-18'::date,'Ali','Sultan'),
(917,'Mustafa Turan','5336611344','Kozağaç Mh. 282/1 Sk. No:8 D:3','İzmir','Buca','Tam Takım',1,1000,'2026-02-18'::date,'Ali','Sultan'),
(918,'Mustafa Turan','5336611344','Kozağaç Mh. 282/1 Sk. No:8 D:3','İzmir','Buca','Alkali',1,1000,'2026-02-18'::date,'Ali','Sultan'),
(919,'Yeşim Turan','5525054677','2023 Sk. No:5 K:1 D:2','İzmir','Torbalı','Lg Eco',1,5500,'2026-02-18'::date,'Ali','Sultan'),
(920,'Yeşim Turan','5525054677','2023 Sk. No:5 K:1 D:2','İzmir','Torbalı','Alkali',1,1500,'2026-02-18'::date,'Ali','Sultan'),
(921,'Erol Aköz','5416972938','Menderes Mh. Atatürk Cd. No:3 K:1 D:1','İzmir','Gaziemir','Lg Eco',1,5500,'2026-02-18'::date,'Ali','Sultan'),
(922,'Erol Aköz','5416972938','Menderes Mh. Atatürk Cd. No:3 K:1 D:1','İzmir','Gaziemir','Alkali',1,1500,'2026-02-18'::date,'Ali','Sultan'),
(923,'Mehmet Yıldız','5548022229','İsmail Silivri Blv. No:108 D:4','İzmir','Buca','Lg Eco',1,5000,'2026-02-18'::date,'Süleyman','Sultan'),
(924,'Mehmet Yıldız','5548022229','İsmail Silivri Blv. No:108 D:4','İzmir','Buca','Alkali',1,1000,'2026-02-18'::date,'Süleyman','Sultan'),
(925,'Hüseyin Tandırcıoğlu','5387063255','254 Sk. No:97 K:2 D:6','İzmir','Buca','Tak Çevir',1,2000,'2026-02-18'::date,'Süleyman','Sultan'),
(926,'Bülent Ergenç','5334171330','8229 Sk. No:4 D:32','İzmir','Çiğli','Tam Takım',1,1100,'2026-02-18'::date,'Süleyman','Sultan'),
(927,'Sedat Özhan','5397199571','8216 Sk. No:17 D:4','İzmir','Çiğli','Tam Takım',1,1100,'2026-02-18'::date,'Süleyman','Sultan'),
(928,'Murat Kemal','5455584392','274 Sk. No:5 D:13','İzmir','Bayraklı','Montaj',1,0,'2026-02-18'::date,'Süleyman','Sultan'),
(929,'Özel Öztürk','5545762918','803 Sk. No:2 D:2','İzmir','Bornova','Tam Takım',1,1100,'2026-02-18'::date,'Süleyman','Sultan'),
(930,'Gürkan Gürgen','5542754343','6660 Sk. No:14','İzmir','Karşıyaka','Tam Takım',1,1100,'2026-02-18'::date,'Süleyman','Sultan'),
(931,'Sedat Bey','5428448545','Ankara cd. No:163 D:25','İzmir','Bornova','Alkali',1,1000,'2026-02-18'::date,'Süleyman','Sultan'),
(932,'Barış Bey','5015434678','1003 Sk. No:48 D:1','İzmir','Bornova','Tam Takım',1,1100,'2026-02-18'::date,'Süleyman','Sultan'),
(933,'Aziz Bey','5325998392','113/13 Sk. No:6/67','İzmir','Bornova','Silifoz+Yıkn.',1,1000,'2026-02-19'::date,'Süleyman','Sultan'),
(934,'Sıraç Bey','5364228371','1713/7 Sk. No:17','İzmir','Bornova','Tam Takım',1,1100,'2026-02-19'::date,'Süleyman','Sultan'),
(935,'İsmet Sayım','5077554235','Ziya ApaK Sk. No:4/1 D:3','İzmir','Karşıyaka','Tam Takım',1,1100,'2026-02-19'::date,'Süleyman','Sultan'),
(936,'Bülent Başer','5054541302','515 Sk. No:48 D:4','İzmir','Üçyol','Tam Takım',1,1250,'2026-02-19'::date,'Süleyman','Sultan'),
(937,'Hasan Hüseyin','5456141121','Hızır Reis Cd. No:51','İzmir','Gültepe','Tam Takım',1,1100,'2026-02-19'::date,'Süleyman','Sultan'),
(938,'Hasan Hüseyin','5456141121','Hızır Reis Cd. No:51','İzmir','Gültepe','Alkali',1,1000,'2026-02-19'::date,'Süleyman','Sultan'),
(939,'Ramazan Bey','5324228371','Erzene Mh. 113/28 Sk. No:7 D:1','İzmir','Bornova','Tak Çevir',1,2500,'2026-02-19'::date,'Süleyman','Sultan'),
(940,'Nemin Kirişkuzu','5363703135','3932 Sk. No:2 K:1 D:2','İzmir','Karabağlar','Tam Takım',1,1100,'2026-02-19'::date,'Ali','Sultan'),
(941,'Ayhan Karadaş','5301161447','565 Sk. No:32 D:2','İzmir','Buca','Alkali',1,1100,'2026-02-19'::date,'Ali','Sultan'),
(942,'Nuri Çalış','5052299468','Atatürk Mh. 63/1 Sk. No:2 D:28 K:6','İzmir','Buca','Tam Takım',1,1100,'2026-02-19'::date,'Ali','Sultan'),
(943,'Nuri Çalış','5052299468','Atatürk Mh. 63/1 Sk. No:2 D:28 K:6','İzmir','Buca','Alkali',1,1100,'2026-02-19'::date,'Ali','Sultan'),
(944,'Nazlı Akman','5349390145','Atatürk Cd. No:52/B D:9 Sarnıç','İzmir','Gaziemir','Lg Eco',1,5500,'2026-02-19'::date,'Ali','Sultan'),
(945,'Nazlı Akman','5349390145','Atatürk Cd. No:52/B D:9 Sarnıç','İzmir','Gaziemir','Alkali',1,1500,'2026-02-19'::date,'Ali','Sultan'),
(946,'Yunus Yüksel','5055645320','1405 Sk. No:21 D:11','İzmir','Buca','Arıtmalı Sebil',1,17000,'2026-02-19'::date,'Ali','Sultan'),
(947,'Yunus Yüksel','5055645320','1405 Sk. No:21 D:11','İzmir','Buca','Alkali',1,3000,'2026-02-19'::date,'Ali','Sultan'),
(948,'İbrahim Çetinkaya','5367319825','Gaziosmanpaşa Cd. No:44 K:1 D:3','İzmir','Buca','Tam Takım',1,1100,'2026-02-20'::date,'Ali','Sultan'),
(949,'Uğur Temizsu','5053193856','91 Sk. No:5 D:4','İzmir','Konak','Tam Takım',1,1100,'2026-02-20'::date,'Ali','Sultan'),
(950,'Ayça Eralmış','5424861976','636 Sk. No:50 K:4 D:7','İzmir','Menderes','Tam Takım',1,1100,'2026-02-20'::date,'Ali','Sultan'),
(951,'Ayça Eralmış','5424861976','636 Sk. No:50 K:4 D:7','İzmir','Menderes','Alkali',1,1100,'2026-02-20'::date,'Ali','Sultan'),
(952,'Yalçın Çevik','5161612580','İnönü cd. 676A','İzmir','Konak','Tam Takım',1,1100,'2026-02-20'::date,'Ali','Sultan'),
(953,'Yalçın Çevik','5161612580','İnönü cd. 676A','İzmir','Konak','Alkali',1,1100,'2026-02-20'::date,'Ali','Sultan'),
(954,'Hacer Hanım','5423670468','4747 Sk. No:4 D:3','İzmir','Karabağlar','Tam Takım',1,1100,'2026-02-20'::date,'Süleyman','Sultan'),
(955,'Hacer Hanım','5423670468','4747 Sk. No:4 D:3','İzmir','Karabağlar','Alkali',1,600,'2026-02-20'::date,'Süleyman','Sultan'),
(956,'Murat Bey','5365802917','5482 Sk. No:28 D:2','İzmir','Bornova','Tam Takım',1,1100,'2026-02-20'::date,'Süleyman','Sultan'),
(957,'Yusuf Akmeşe','5324620341','5708 Sk. No:74/1 D:4','İzmir','Karabağlar','Tam Takım',1,1100,'2026-02-20'::date,'Süleyman','Sultan'),
(958,'Lütfettin Türker','5366863592','7309 Sk. No:52 D:1','İzmir','Bayraklı','Tak Çevir',1,2000,'2026-02-20'::date,'Süleyman','Sultan'),
(959,'Arife Hanım','5416192777','Demet Sk. No:3/1','İzmir','Narlıdere','Tam Takım',1,1100,'2026-02-21'::date,'Süleyman','Sultan'),
(960,'Hasan Bey','5419308222','Erdoğan Kar Sk. No:120','İzmir','','Ön Takım',1,1000,'2026-02-21'::date,'Süleyman','Sultan'),
(961,'Tülay Hanım','5054144884','1021/1 Sk. No:140 D:1','İzmir','Güzelbahçe','Puretech',1,2000,'2026-02-21'::date,'Süleyman','Sultan'),
(962,'Bülent Kıdak','5529405028','1146/5 Sk. No:11 D:1','İzmir','Urla','Puretech',1,2000,'2026-02-21'::date,'Süleyman','Sultan'),
(963,'Hatice Albayrak','5060968177','5508 Sk. No:32 D:4','İzmir','Bornova','Lg Eco',1,5000,'2026-02-21'::date,'Süleyman','Sultan'),
(964,'Yusuf Şahin','5354413550','2121/3 Sk. No:21 D:1','İzmir','Urla','Tam Takım',1,1100,'2026-02-21'::date,'Süleyman','Sultan'),
(965,'Tuncay Bey','5445375145','2301 Sk. No:16 D:2','İzmir','Güzelbahçe','Tam Takım',1,1100,'2026-02-21'::date,'Süleyman','Sultan'),
(966,'Tuncay Bey','5445375145','2301 Sk. No:16 D:2','İzmir','Güzelbahçe','Alkali',1,900,'2026-02-21'::date,'Süleyman','Sultan'),
(967,'Umut Uçak','5435351978','7448/14 Sk. No:9 D:14','İzmir','Karşıyaka','Tam Takım',1,1100,'2026-02-21'::date,'Ali','Sultan'),
(968,'Özcan Dağ','5055616102','Fuat Edip Baksı Mh. 1657 Sk. No:7','İzmir','Bayraklı','Lg Eco',1,1200,'2026-02-21'::date,'Ali','Sultan'),
(969,'Özcan Dağ','5055616102','Fuat Edip Baksı Mh. 1657 Sk. No:7','İzmir','Bayraklı','Alkali',1,3000,'2026-02-21'::date,'Ali','Sultan'),
(970,'Muhaffak Sinemler','5446050502','898 Sk. No:30A','İzmir','Buca','Lg Eco',1,5000,'2026-02-21'::date,'Ali','Sultan'),
(971,'Muhaffak Sinemler','5446050502','898 Sk. No:30A','İzmir','Buca','Alkali',1,1500,'2026-02-21'::date,'Ali','Sultan'),
(972,'Mustafa Karaca','5359693980','390 Sk. No:3 D:1','İzmir','Buca','Tam Takım',1,1000,'2026-02-21'::date,'Ali','Sultan'),
(973,'Hamide Seren Tekiner','5075719919','810 Sk. No:12 K:8 D:16','İzmir','Gaziemir','Tam Takım',1,1100,'2026-02-21'::date,'Ali','Sultan'),
(974,'Shuhrat Gencayf','5531691185','510/5 Sk. No:4 D:3','İzmir','Karabağlar','Lg Eco',1,7000,'2026-02-23'::date,'Süleyman','Sultan'),
(975,'Ahmet Bey','5395137536','3947/7 Sk. No:22 D:1','İzmir','Karabağlar','Lg Eco',1,5000,'2026-02-23'::date,'Süleyman','Sultan'),
(976,'Ahmet Yüksel','','467 Sk. No:14 D:1','İzmir','Buca','Tam Takım',1,1100,'2026-02-23'::date,'Süleyman','Sultan'),
(977,'İlkay Ayözen','5079640496','3205 Sk. No:28 C Blok','İzmir','Karabağlar','Puretech',1,2000,'2026-02-23'::date,'Süleyman','Sultan'),
(978,'İlkay Ayözen','5079640496','3205 Sk. No:28 C Blok','İzmir','Karabağlar','Alkali',1,600,'2026-02-23'::date,'Süleyman','Sultan'),
(979,'Cengiz Cenan','5325241673','45/8 Sk. No:12 D:5','İzmir','Karabağlar','Tam Takım',1,1100,'2026-02-23'::date,'Süleyman','Sultan'),
(980,'Engin Toygarlı','5333907419','1244/1 Sk. No:59/1','İzmir','Karabağlar','Tam Takım',1,1100,'2026-02-23'::date,'Süleyman','Sultan'),
(981,'Dilek Atabay','5315746076','Mehmetçid cad no:16 d:2 Buca','İzmir','Buca','Tam Takım',1,1100,'2026-02-26'::date,'Süleyman','Sultan'),
(982,'Kamile Göçmez','5379272016','İsmetpaşa cad no:26 d:4 Karabağlar','İzmir','Karabağlar','Alkali',1,800,'2026-02-26'::date,'Süleyman','Sultan'),
(983,'Mustafa Küçük','5327854324','Zaimağa cad no:75 d:28 Karabağlar','İzmir','Karabağlar','Tam Takım',1,1250,'2026-02-26'::date,'Süleyman','Sultan'),
(984,'Cem Uysal','5531057910','202 sk no:10 d:3 Kemalpaşa','İzmir','Kemalpasa','Tam Takım',1,1100,'2026-02-24'::date,'Süleyman','Sultan'),
(985,'Begüm Can Borhan','5434334723','8831 sk no:47 k:5 d:12','İzmir','Çiğli','Tam Takım',1,1100,'2026-02-26'::date,'Ali','Sultan'),
(986,'Bekir Gökçe','5498786996','275/2 sk no:17 k:3 d:13 Anıl apt','İzmir','Bayraklı','Lg Eco',1,5000,'2026-02-26'::date,'Ali','Sultan'),
(987,'Bekir Gökçe','5498786996','275/2 sk no:17 k:3 d:13 Anıl apt','İzmir','Bayraklı','Alkali',1,1000,'2026-02-26'::date,'Ali','Sultan'),
(988,'hacı baykara','5356939456','4526 sk no:18 d:7','İzmir','Torbalı','Tam Takım',1,1250,'2026-02-25'::date,'Ali','Melike'),
(989,'Sönmez Toparlak','5056410887','Uğur mumcu bulvarı no:26 k:3 d:4','İzmir','Torbalı','Tam Takım',1,1100,'2026-02-25'::date,'Ali','Sultan'),
(990,'Sönmez Toparlak','5056410887','Uğur mumcu bulvarı no:26 k:3 d:4','İzmir','Torbalı','Alkali',1,1100,'2026-02-25'::date,'Ali','Sultan'),
(991,'Çağlar Koçyiğit','5357285454','1613 sk no:18 k:1 Doğanlar','İzmir','Bornova','Tam Takım',1,1100,'2026-02-25'::date,'Ali','Sultan'),
(992,'Niyazi Kabay','5325136849','4532 sk no:2 d:2 Altındağ','İzmir','Bornova','Lg Eco',1,6000,'2026-02-26'::date,'Ali','Sultan'),
(993,'Niyazi Kabay','5325136849','4532 sk no:2 d:2 Altındağ','İzmir','Bornova','Alkali',1,2000,'2026-02-26'::date,'Ali','Sultan'),
(994,'Hasan Ünal','5438616209','1106 sk no:9 d:32 Buca','İzmir','Buca','Tam Takım',1,1100,'2026-02-26'::date,'Ali','Sultan'),
(995,'Uğur Kol','5071323026','90/6 sk no:16 d:1 Ayrancılar','İzmir','Ayrancılar','Tam Takım',1,1100,'2026-03-03'::date,'Ali','Sultan'),
(996,'Uğur Kol','5071323026','90/6 sk no:16 d:1 Ayrancılar','İzmir','Ayrancılar','Musluk',1,700,'2026-03-03'::date,'Ali','Sultan'),
(997,'Zekiye Albayrak','5075198599','Seyrantepe cad no:59 Kuşçuburun','İzmir','Torbalı','Tam Takım',1,1100,'2026-03-02'::date,'Ali','Sultan'),
(998,'Sehadettin Altınok','5325125588','Şehithüseyin olgun sk no:25 d:7','İzmir','Karşıyaka','Tam Takım',2,2200,'2026-03-02'::date,'Ali','Sultan'),
(999,'Sehadettin Altınok','5325125588','Şehithüseyin olgun sk no:25 d:7','İzmir','Karşıyaka','Alkali',1,1100,'2026-03-02'::date,'Ali','Sultan'),
(1000,'Türkan Yaşar','5368330947','8846 sk no:9 k:5 d:10','İzmir','Çiğli','Tam Takım',1,1100,'2026-03-02'::date,'Ali','Sultan'),
(1001,'Fatih Yumrutepe','5459139873','Dumlupınar cad no:55 k:5 d:10','İzmir','Bayraklı','Tam Takım',1,1100,'2026-03-02'::date,'Ali','Sultan'),
(1002,'Fatih Yumrutepe','5459139873','Dumlupınar cad no:55 k:5 d:10','İzmir','Bayraklı','Alkali',1,1100,'2026-03-02'::date,'Ali','Sultan'),
(1003,'Caner Gürbüz','5467999069','Kazımkarabekir mah Mustafa kemal cad no:44 d:4 Pancar','İzmir','Torbalı','Tam Takım',1,1100,'2026-03-02'::date,'Ali','Sultan'),
(1004,'Esra Korkmaz','5511058522','672/32 Sk no:1 d:7','İzmir','Buca','Tam Takım',1,1100,'2026-03-02'::date,'Ali','Sultan'),
(1005,'Şükrü Dağdelen','5334240187','Torbalı cad no:13 b blok k:2 d:8','İzmir','Torbalı','Lg Eco',1,5500,'2026-01-28'::date,'Ali',''),
(1006,'Abdullah Atakul','5313247697','Mektep cad no:53 d:2 Seferisar','İzmir','Seferishar','Tam Takım',1,1100,'2026-02-27'::date,'Ali',''),
(1007,'Çetin Kurşun','','3966/3 sk no:8/A','İzmir','Gaziemir','Lg Eco',1,6000,'2026-02-28'::date,'Ali',''),
(1008,'Çetin Kurşun','','3966/3 sk no:8/A','İzmir','Gaziemir','Alkali',1,2000,'2026-02-28'::date,'Ali',''),
(1009,'Fikret Uluer','5053917666','Metin oktay sk no:8/1 d:6 d:13 Narlıdere','İzmir','Narlıdere','Lg Eco',1,7000,'2026-02-27'::date,'',''),
(1010,'Fikret Uluer','5053917666','Metin oktay sk no:8/1 d:6 d:13 Narlıdere','İzmir','Narlıdere','Alkali',1,2250,'2026-02-27'::date,'',''),
(1011,'Bülent Soydaş','5536162591','Nejat  hepgom mah gözsüzler cad no:108 d:5','İzmir','Seferishar','Lg Eco',1,6000,'2026-02-27'::date,'',''),
(1012,'Bülent Soydaş','5536162591','Nejat  hepgom mah gözsüzler cad no:108 d:5','İzmir','Seferishar','Alkali',1,2000,'2026-02-27'::date,'',''),
(1013,'Ergün Özer','5327445432','810 sk no:20 d:2 EVKA 7','İzmir','Gaziemir','Lg Eco',1,6000,'2026-02-28'::date,'',''),
(1014,'Ergün Özer','5327445432','810 sk no:20 d:2 EVKA 7','İzmir','Gaziemir','Alkali',1,2000,'2026-02-28'::date,'',''),
(1015,'Abdurrahman Alkan','5424717911','4125/19 sk no:4 d:3 Karabağlar','İzmir','Karabağlar','Tam Takım',1,1100,'2026-02-28'::date,'',''),
(1016,'Fethi Ahmet Şahin','5436989077','48 sk no:28 d:2 Seferishar','İzmir','Seferishar','Tam Takım',1,1100,'2026-02-27'::date,'',''),
(1017,'Bayram Tutkun','5327619957','Akarca Mah 1003 sk no:10 d:2 Seferishar','İzmir','Seferishar','Tam Takım',1,1100,'2026-02-27'::date,'',''),
(1018,'Aydın Gürbüz','5353969561','Gediz Cad no:35 d:12 Bayraklı','İzmir','Bayraklı','Tam Takım',1,1100,'2026-02-28'::date,'',''),
(1019,'Dilek Gazi','5383717572','2116 SK NO:4/A','İzmir','Bayraklı','Tam Takım',1,1100,'2026-02-28'::date,'',''),
(1020,'Semiha Barış','5448660191','7060 sk no:3 d:1','İzmir','Bornova','Tam Takım',1,1100,'2026-02-28'::date,'',''),
(1021,'Derya Cingi','5075805416','2116 sk no:3 d:2','İzmir','Bornova','Tam Takım',1,2200,'2026-02-28'::date,'',''),
(1022,'Ali Şimşek','5316656994','7427 sk no:15 d:8 Örnekköy','İzmir','Karşıyaka','Tam Takım',1,1400,'2026-02-28'::date,'',''),
(1023,'Suat Özkütük','5317758888','240 sk no:23 d:21 Bayraklı','İzmir','Bayraklı','Tam Takım',1,1100,'2026-02-28'::date,'',''),
(1024,'Atife Saraçoğlu','5315062659','220/21 sk no:113 d:3 Buca','İzmir','Buca','Tam Takım',1,1100,'2026-02-27'::date,'',''),
(1025,'Yakup Güven','5379471301','Eski haykıran yolu sk no:3 d:89','İzmir','Menemen','Tam Takım',2,2200,'2026-02-25'::date,'',''),
(1026,'Ferit Filiz','5078652912','7104 sk Mavi ege sit d:6 Egekent','İzmir','Menemen','Lg Eco',1,10000,'2026-02-27'::date,'','');

-- Firma seçimi: sistemde tam olarak bir aktif firma olmalı.
create temporary table tmp_import_context(company_id uuid primary key) on commit drop;

do $$
declare
  v_count integer;
  v_company_id uuid;
begin
  select count(*) into v_count
  from public.companies
  where coalesce(is_active, true)=true;

  select id into v_company_id
  from public.companies
  where coalesce(is_active, true)=true
  order by created_at, id
  limit 1;

  if v_count <> 1 then
    raise exception 'Aktarım için sistemde tam olarak 1 aktif firma olmalı. Bulunan: %', v_count;
  end if;

  insert into tmp_import_context values(v_company_id);
end $$;

-- Excel'deki sekreter ve teknisyenlerin sistemde mevcut olduğunu doğrula.
do $$
declare
  v_missing text;
  v_ambiguous text;
begin
  select string_agg(x.staff_name || ' (' || x.staff_role || ')', ', ')
  into v_missing
  from (
    select distinct secretary_name staff_name, 'secretary' staff_role
    from tmp_parakende_import where btrim(secretary_name)<>''
    union
    select distinct technician_name, 'technician'
    from tmp_parakende_import where btrim(technician_name)<>''
  ) x
  cross join tmp_import_context c
  where not exists (
    select 1
    from public.profiles p
    where p.company_id=c.company_id
      and p.is_active=true
      and p.role=x.staff_role
      and (
        public.arn_import_norm(p.full_name)=public.arn_import_norm(x.staff_name)
        or split_part(public.arn_import_norm(p.full_name), ' ', 1)=public.arn_import_norm(x.staff_name)
      )
  );

  if v_missing is not null then
    raise exception 'Önce bu personelleri kullanıcı yönetiminden ekleyin: %', v_missing;
  end if;

  select string_agg(x.staff_name || ' (' || x.staff_role || ')', ', ')
  into v_ambiguous
  from (
    select distinct secretary_name staff_name, 'secretary' staff_role
    from tmp_parakende_import where btrim(secretary_name)<>''
    union
    select distinct technician_name, 'technician'
    from tmp_parakende_import where btrim(technician_name)<>''
  ) x
  cross join tmp_import_context c
  where (
    select count(*)
    from public.profiles p
    where p.company_id=c.company_id
      and p.is_active=true
      and p.role=x.staff_role
      and (
        public.arn_import_norm(p.full_name)=public.arn_import_norm(x.staff_name)
        or split_part(public.arn_import_norm(p.full_name), ' ', 1)=public.arn_import_norm(x.staff_name)
      )
  ) > 1;

  if v_ambiguous is not null then
    raise exception 'Aynı isimle birden fazla personel eşleşti: %', v_ambiguous;
  end if;
end $$;

-- Personel ID eşleştirmesi.
create temporary table tmp_staff_map(
  staff_role text not null,
  excel_name text not null,
  profile_id uuid not null,
  primary key(staff_role, excel_name)
) on commit drop;

insert into tmp_staff_map(staff_role, excel_name, profile_id)
select x.staff_role, x.staff_name,
       (
         select p.id
         from public.profiles p
         cross join tmp_import_context c
         where p.company_id=c.company_id
           and p.is_active=true
           and p.role=x.staff_role
           and (
             public.arn_import_norm(p.full_name)=public.arn_import_norm(x.staff_name)
             or split_part(public.arn_import_norm(p.full_name), ' ', 1)=public.arn_import_norm(x.staff_name)
           )
         order by case when public.arn_import_norm(p.full_name)=public.arn_import_norm(x.staff_name) then 0 else 1 end
         limit 1
       )
from (
  select distinct secretary_name staff_name, 'secretary' staff_role
  from tmp_parakende_import where btrim(secretary_name)<>''
  union
  select distinct technician_name, 'technician'
  from tmp_parakende_import where btrim(technician_name)<>''
) x;

-- Mevcut müşterilerle telefon çakışması varsa yanlış birleştirmeyi önlemek için dur.
do $$
declare
  v_collision text;
begin
  select string_agg(distinct i.phone, ', ')
  into v_collision
  from tmp_parakende_import i
  cross join tmp_import_context c
  join public.customers cu
    on cu.company_id=c.company_id
   and btrim(i.phone)<>''
   and cu.phone=i.phone;

  if v_collision is not null then
    raise exception 'Sistemde aynı telefonla mevcut müşteri var. Aktarım durduruldu. Telefonlar: %', v_collision;
  end if;
end $$;

-- Excel ürünlerini adları birebir korunarak ekle.
insert into public.products(
  company_id, name, unit, purchase_price, sale_price,
  stock_quantity, critical_stock, maintenance_months, is_active
)
select c.company_id, p.product_name, 'adet', 0, 0, 10000, 0,
       case when p.product_name in ('Tam Takım', 'Alkali', 'Lg Eco', 'Sebil Ap.', 'Membran', 'Tatlandırıcı', 'Ön Takım', 'ön takım', 'Puretech', 'Ao Smith', 'LG Vıp', 'Membran(Arıza)', 'Yenilenmiş Cihaz', 'Membran+Tcr', 'Sed.+Blok', 'Silifoz+Yıkn.', 'Arıtmalı Sebil') then 8 else 0 end,
       true
from (select distinct product_name from tmp_parakende_import) p
cross join tmp_import_context c
where not exists (
  select 1 from public.products x
  where x.company_id=c.company_id and x.name=p.product_name
);

-- Aktarımdaki tüm ürünlerin stoklarını 10.000 yap; filtre/cihaz bakım süresini 8 ay yap.
update public.products p
set stock_quantity=10000,
    maintenance_months=case when p.name in ('Tam Takım', 'Alkali', 'Lg Eco', 'Sebil Ap.', 'Membran', 'Tatlandırıcı', 'Ön Takım', 'ön takım', 'Puretech', 'Ao Smith', 'LG Vıp', 'Membran(Arıza)', 'Yenilenmiş Cihaz', 'Membran+Tcr', 'Sed.+Blok', 'Silifoz+Yıkn.', 'Arıtmalı Sebil') then 8 else 0 end,
    is_active=true,
    updated_at=now()
from tmp_import_context c
where p.company_id=c.company_id
  and p.name in (select distinct product_name from tmp_parakende_import);

-- Müşteri grupları:
-- Telefon varsa aynı telefon tek müşteri kartıdır.
-- Telefon boşsa aynı ad+adres+il+ilçe tek karttır.
create temporary table tmp_customer_rows as
select i.*,
       case
         when btrim(i.phone)<>'' then 'P:' || i.phone
         else 'B:' || encode(digest(
           public.arn_import_norm(i.customer_name) || '|' ||
           public.arn_import_norm(i.address) || '|' ||
           public.arn_import_norm(i.city) || '|' ||
           public.arn_import_norm(i.district), 'sha256'), 'hex')
       end as customer_key
from tmp_parakende_import i;

create temporary table tmp_customer_master as
with ranked as (
  select r.*,
         row_number() over(
           partition by customer_key
           order by transaction_date desc, source_row desc
         ) as latest_rank,
         min(transaction_date) over(partition by customer_key) as first_date
  from tmp_customer_rows r
)
select r.customer_key, r.customer_name, r.phone, r.address, r.city, r.district,
       r.first_date,
       (
         select sm.profile_id from tmp_staff_map sm
         join tmp_customer_rows e
           on e.customer_key=r.customer_key
          and sm.staff_role='secretary'
          and sm.excel_name=e.secretary_name
         order by e.transaction_date, e.source_row
         limit 1
       ) as created_by,
       (
         select string_agg(v.variant, ' | ' order by v.variant)
         from (
           select distinct
             'Ad: ' || x.customer_name ||
             '; Adres: ' || x.address ||
             '; İl/İlçe: ' || x.city || '/' || x.district as variant
           from tmp_customer_rows x
           where x.customer_key=r.customer_key
         ) v
       ) as original_variants,
       (
         select count(distinct
           public.arn_import_norm(x.customer_name) || '|' ||
           public.arn_import_norm(x.address) || '|' ||
           public.arn_import_norm(x.city) || '|' ||
           public.arn_import_norm(x.district)
         )
         from tmp_customer_rows x
         where x.customer_key=r.customer_key
       ) as variant_count
from ranked r
where r.latest_rank=1;

insert into public.customers(
  company_id, customer_type, full_name, phone, city, district, address,
  notes, is_active, registration_date, created_by, updated_by,
  created_at, updated_at
)
select c.company_id, 'individual', m.customer_name, m.phone, m.city, m.district, m.address,
       case when m.variant_count>1
         then 'Excel aktarımı. Orijinal kayıt çeşitleri: ' || m.original_variants
         else 'Excel aktarımı (PARAKENDE_2026_07_30_V1)'
       end,
       true, m.first_date, m.created_by, m.created_by,
       m.first_date::timestamptz, now()
from tmp_customer_master m
cross join tmp_import_context c;

create temporary table tmp_customer_map(
  customer_key text primary key,
  customer_id uuid not null
) on commit drop;

insert into tmp_customer_map(customer_key, customer_id)
select m.customer_key, cu.id
from tmp_customer_master m
cross join tmp_import_context c
join public.customers cu
  on cu.company_id=c.company_id
 and (
   (btrim(m.phone)<>'' and cu.phone=m.phone)
   or
   (btrim(m.phone)='' and cu.created_at::date=m.first_date
      and cu.full_name=m.customer_name and cu.address=m.address
      and cu.notes like 'Excel aktarımı%')
 );

-- Her Excel satırını müşteri kartında ayrı ürün/işlem geçmişi olarak kaydet.
insert into public.customer_maintenance_records(
  company_id, customer_id, product_id, product_name,
  performed_at, next_maintenance_date,
  assigned_user_id, assigned_role, secretary_id, technician_id,
  notes, created_by, import_batch_id, import_source_row
)
select c.company_id,
       cm.customer_id,
       p.id,
       i.product_name,
       i.transaction_date,
       case when p.maintenance_months=8
            then (i.transaction_date + interval '8 months')::date
            else null end,
       coalesce(tm.profile_id, sm.profile_id),
       case when tm.profile_id is not null then 'technician' else 'secretary' end,
       sm.profile_id,
       tm.profile_id,
       'Excel geçmiş işlemi. Adet: ' || i.quantity::text ||
       '; Tutar: ' || i.amount::text || ' TL; Ödeme: Ödendi',
       sm.profile_id,
       'PARAKENDE_2026_07_30_V1',
       i.source_row
from tmp_customer_rows i
cross join tmp_import_context c
join tmp_customer_map cm on cm.customer_key=i.customer_key
join public.products p on p.company_id=c.company_id and p.name=i.product_name
left join tmp_staff_map sm on sm.staff_role='secretary' and sm.excel_name=i.secretary_name
left join tmp_staff_map tm on tm.staff_role='technician' and tm.excel_name=i.technician_name;

-- Ciro/geçmiş satış kaydı; ödeme durumlarının tamamı paid (Ödendi).
insert into public.historical_customer_sales(
  company_id, customer_id, product_id, product_name,
  quantity, amount, payment_status, payment_due_date,
  transaction_date, created_by, import_batch_id, import_source_row
)
select c.company_id,
       cm.customer_id,
       p.id,
       i.product_name,
       i.quantity,
       i.amount,
       'paid',
       null,
       i.transaction_date,
       sm.profile_id,
       'PARAKENDE_2026_07_30_V1',
       i.source_row
from tmp_customer_rows i
cross join tmp_import_context c
join tmp_customer_map cm on cm.customer_key=i.customer_key
join public.products p on p.company_id=c.company_id and p.name=i.product_name
left join tmp_staff_map sm on sm.staff_role='secretary' and sm.excel_name=i.secretary_name;

insert into public.arn_excel_import_batches(batch_id, source_file, source_row_count)
values('PARAKENDE_2026_07_30_V1', 'PARAKENDE.xlsx', 1025);

commit;

-- KONTROL RAPORU
select
  (select count(*) from public.arn_excel_import_batches where batch_id='PARAKENDE_2026_07_30_V1') as batch_ok,
  (select count(*) from public.customer_maintenance_records where import_batch_id='PARAKENDE_2026_07_30_V1') as aktarilan_islem,
  (select count(*) from public.historical_customer_sales where import_batch_id='PARAKENDE_2026_07_30_V1') as aktarilan_satis,
  (select count(distinct customer_id) from public.customer_maintenance_records where import_batch_id='PARAKENDE_2026_07_30_V1') as olusan_musteri_karti,
  (select count(distinct product_id) from public.customer_maintenance_records where import_batch_id='PARAKENDE_2026_07_30_V1') as eklenen_urun;
