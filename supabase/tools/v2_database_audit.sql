-- MOTUS v2.0 güvenli veritabanı denetimi
-- Bu dosya hiçbir tablo/fonksiyon silmez. Çıktıları incelemeden DROP çalıştırmayın.

-- Aynı isim ve imzaya sahip fonksiyonların listesi.
select
  n.nspname as schema_name,
  p.proname as function_name,
  pg_get_function_identity_arguments(p.oid) as arguments,
  pg_get_function_result(p.oid) as result_type
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
order by p.proname, arguments;

-- Public trigger listesi.
select
  event_object_table as table_name,
  trigger_name,
  action_timing,
  event_manipulation,
  action_statement
from information_schema.triggers
where trigger_schema = 'public'
order by event_object_table, trigger_name;

-- Büyük tablolar ve yaklaşık satır sayıları.
select
  schemaname,
  relname as table_name,
  n_live_tup as estimated_rows,
  n_dead_tup as dead_rows,
  last_analyze,
  last_autoanalyze
from pg_stat_user_tables
order by n_live_tup desc;

-- Kullanılmayan index adayları. Primary/unique indexleri otomatik silmeyin.
select
  schemaname,
  relname as table_name,
  indexrelname as index_name,
  idx_scan,
  pg_size_pretty(pg_relation_size(indexrelid)) as index_size
from pg_stat_user_indexes
order by idx_scan asc, pg_relation_size(indexrelid) desc;
