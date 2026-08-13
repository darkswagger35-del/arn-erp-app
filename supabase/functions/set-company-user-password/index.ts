import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader?.startsWith('Bearer ')) return json(401, { success: false, message: 'Oturum doğrulanamadı.' });
    const url = Deno.env.get('SUPABASE_URL');
    const anon = Deno.env.get('SUPABASE_ANON_KEY');
    const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!url || !anon || !service) return json(500, { success: false, message: 'Sunucu yapılandırması eksik.' });

    const jwt = authHeader.substring(7);
    const callerClient = createClient(url, anon, {
      auth: { persistSession: false, autoRefreshToken: false },
      global: { headers: { Authorization: `Bearer ${jwt}` } },
    });
    const adminClient = createClient(url, service, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data: callerUser } = await callerClient.auth.getUser(jwt);
    if (!callerUser.user) return json(401, { success: false, message: 'Oturum doğrulanamadı.' });
    const { data: caller } = await adminClient.from('profiles')
      .select('company_id, role, is_active').eq('id', callerUser.user.id).maybeSingle();
    if (!caller || !caller.is_active || !['admin', 'manager'].includes(caller.role)) {
      return json(403, { success: false, message: 'Yalnızca yönetici şifre değiştirebilir.' });
    }

    const body = await req.json().catch(() => ({}));
    const userId = String(body.user_id ?? '');
    const password = String(body.password ?? '');
    if (!userId || password.length < 6) return json(400, { success: false, message: 'Şifre en az 6 karakter olmalıdır.' });
    const { data: target } = await adminClient.from('profiles')
      .select('id, company_id').eq('id', userId).maybeSingle();
    if (!target || target.company_id !== caller.company_id) {
      return json(404, { success: false, message: 'Kullanıcı bulunamadı.' });
    }
    const { error } = await adminClient.auth.admin.updateUserById(userId, { password, email_confirm: true });
    if (error) return json(400, { success: false, message: error.message });
    return json(200, { success: true, message: 'Şifre güncellendi.' });
  } catch (_) {
    return json(500, { success: false, message: 'Şifre güncellenemedi.' });
  }
});

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}
