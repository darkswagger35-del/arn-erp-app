import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { status: 200, headers: corsHeaders });
  if (req.method !== 'POST') return json(405, { success: false, message: 'Yalnızca POST kullanılabilir.' });

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader?.startsWith('Bearer ')) return json(401, { success: false, message: 'Oturum bulunamadı.' });

    const jwt = authHeader.substring(7).trim();
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!supabaseUrl || !anonKey || !serviceRoleKey) return json(500, { success: false, message: 'Sunucu yapılandırması eksik.' });

    const authClient = createClient(supabaseUrl, anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
      global: { headers: { Authorization: `Bearer ${jwt}` } },
    });
    const adminClient = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false, autoRefreshToken: false } });

    const { data: authData, error: authError } = await authClient.auth.getUser(jwt);
    if (authError || !authData.user) return json(401, { success: false, message: 'Oturum doğrulanamadı.' });

    const { data: caller } = await adminClient.from('profiles').select('id, company_id, role, is_active').eq('id', authData.user.id).maybeSingle();
    if (!caller || caller.is_active !== true || !['admin', 'manager'].includes(String(caller.role))) {
      return json(403, { success: false, message: 'Bu işlem için yönetici yetkisi gerekir.' });
    }

    const body = await req.json().catch(() => ({}));
    const userId = String(body.user_id ?? '').trim();
    if (!userId) return json(400, { success: false, message: 'Kullanıcı seçilmedi.' });
    if (userId === authData.user.id) return json(400, { success: false, message: 'Kendi yönetici hesabınızı silemezsiniz.' });

    const { data: target } = await adminClient.from('profiles').select('id, company_id, full_name, email, role').eq('id', userId).maybeSingle();
    if (!target || target.company_id !== caller.company_id) return json(404, { success: false, message: 'Kullanıcı bulunamadı.' });
    if (['admin', 'manager'].includes(String(target.role))) return json(400, { success: false, message: 'Yönetici hesabı bu ekrandan kalıcı silinemez.' });

    // Eski servislerde isim snapshot alanları varsa son kez doldur.
    try {
      await adminClient.from('service_requests')
        .update({ assigned_technician_name_snapshot: target.full_name })
        .eq('assigned_technician_id', userId)
        .or('assigned_technician_name_snapshot.is.null,assigned_technician_name_snapshot.eq.');
      await adminClient.from('service_requests')
        .update({ created_by_name_snapshot: target.full_name })
        .eq('created_by', userId)
        .or('created_by_name_snapshot.is.null,created_by_name_snapshot.eq.');
    } catch (_) {}

    const { error: deleteError } = await adminClient.auth.admin.deleteUser(userId, false);
    if (deleteError) {
      console.error('deleteUser:', deleteError);
      return json(409, {
        success: false,
        message: 'Kullanıcı başka kayıtlarda bağlı olduğu için kalıcı silinemedi. Önce arşive alın veya bağlı kayıtları temizleyin.',
        detail: deleteError.message,
      });
    }

    // Auth silme profili cascade ile kaldırmıyorsa temizle.
    await adminClient.from('profiles').delete().eq('id', userId).eq('company_id', caller.company_id);

    return json(200, { success: true, message: `${target.full_name} kalıcı olarak silindi.` });
  } catch (error) {
    console.error('unexpected:', error);
    return json(500, { success: false, message: error instanceof Error ? error.message : 'Beklenmeyen hata.' });
  }
});

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json; charset=utf-8' },
  });
}
