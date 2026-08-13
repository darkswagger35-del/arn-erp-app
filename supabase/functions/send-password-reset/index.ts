import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';

Deno.serve(async (req: Request) => {
  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader?.startsWith('Bearer ')) {
      return json(401, { success: false, message: 'Yetkilendirme başlığı eksik.' });
    }

    const jwt = authHeader.replace('Bearer ', '').trim();
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

    if (!supabaseUrl || !supabaseAnonKey || !serviceRoleKey) {
      return json(500, { success: false, message: 'Sunucu yapılandırması eksik.' });
    }

    const authClient = createClient(supabaseUrl, supabaseAnonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
      global: { headers: { Authorization: `Bearer ${jwt}` } },
    });

    const { data: authData, error: authError } = await authClient.auth.getUser(jwt);
    if (authError || !authData.user) {
      return json(401, { success: false, message: 'Oturum doğrulanamadı.' });
    }

    const { data: callerProfileData, error: callerProfileError } = await authClient
      .from('profiles')
      .select('id, company_id, role, is_active')
      .eq('id', authData.user.id)
      .maybeSingle();

    if (callerProfileError || !callerProfileData) {
      return json(403, { success: false, message: 'Yönetici profili bulunamadı.' });
    }

    if (!callerProfileData.is_active || callerProfileData.role !== 'manager') {
      return json(403, { success: false, message: 'Yalnızca aktif yöneticiler şifre sıfırlama bağlantısı gönderebilir.' });
    }

    const body = await req.json().catch(() => ({}));
    const email = String(body.email ?? '').trim();
    if (!email) {
      return json(400, { success: false, message: 'E-posta adresi eksik.' });
    }

    const serviceRoleClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: targetProfileData, error: targetProfileError } = await serviceRoleClient
      .from('profiles')
      .select('id, company_id, email, is_active')
      .eq('email', email)
      .maybeSingle();

    if (targetProfileError || !targetProfileData) {
      return json(404, { success: false, message: 'Bu e-posta adresine ait kullanıcı bulunamadı.' });
    }

    if (targetProfileData.company_id !== callerProfileData.company_id) {
      return json(403, { success: false, message: 'Bu kullanıcı aynı şirkette değil.' });
    }

    if (!targetProfileData.is_active) {
      return json(403, { success: false, message: 'Pasif kullanıcıya şifre sıfırlama bağlantısı gönderilemez.' });
    }

    const { error: resetError } = await serviceRoleClient.auth.admin.generateLink({
      type: 'recovery',
      email,
    });

    if (resetError) {
      return json(400, { success: false, message: 'Şifre sıfırlama bağlantısı oluşturulamadı.' });
    }

    const { error: auditError } = await serviceRoleClient.from('audit_logs').insert({
      company_id: callerProfileData.company_id,
      user_id: authData.user.id,
      action: 'password_reset_sent',
      entity_type: 'profiles',
      entity_id: targetProfileData.id,
      metadata: { recipient_email: email, sender_id: authData.user.id },
    });

    if (auditError) {
      return json(500, { success: false, message: 'Bağlantı gönderildi, ancak audit kaydı yazılamadı.' });
    }

    return json(200, { success: true, message: 'Şifre sıfırlama bağlantısı kullanıcının e-posta adresine gönderildi.' });
  } catch (error) {
    return json(500, { success: false, message: 'İşlem sırasında beklenmeyen bir hata oluştu.' });
  }
});

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}
