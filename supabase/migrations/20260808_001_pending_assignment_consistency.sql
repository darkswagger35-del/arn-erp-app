-- Bekleyen servislerde eski tekniker bilgisinin görünmesini engeller.
-- pending durumundaki kayıt teknikere atanmış sayılmaz.
update public.service_requests
set assigned_technician_id = null,
    updated_at = now()
where status::text = 'pending'
  and assigned_technician_id is not null;
