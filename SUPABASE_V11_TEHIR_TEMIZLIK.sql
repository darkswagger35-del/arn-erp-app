-- MOTUS / ARN ERP V11
-- "Tehir" artik kullaniciya acik bir servis durumu degildir.
-- deferred yalnizca sekretere yeniden planlama icin aktarilan kayitlarin
-- dahili kuyruk durumudur.
--
-- Bu script sadece eski, hicbir sekreter aktarim metadatasi olmayan
-- tekil deferred kayitlari guvenli bir aktif duruma geri alir.
-- Sekretere gonderilmis gercek kayitlara ve aktarim gecmisine DOKUNMAZ.

update public.service_requests sr
set status = case
      when sr.assigned_technician_id is not null then 'assigned'
      else 'pending'
    end,
    updated_at = now()
where sr.status::text = 'deferred'
  and sr.rework_requested_at is null
  and sr.rework_source_service_request_id is null
  and sr.replacement_service_request_id is null;

notify pgrst, 'reload schema';
