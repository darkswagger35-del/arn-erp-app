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

    if (!callerProfileData.is_active) {
      return json(403, { success: false, message: 'Bu kullanıcı hesabı pasif durumdadır. Yöneticinizle iletişime geçin.' });
    }

    if (callerProfileData.role !== 'manager') {
      return json(403, { success: false, message: 'Yalnızca yöneticiler kullanıcı güncelleyebilir.' });
    }

    const body = await req.json().catch(() => ({}));
    const targetUserId = String(body.user_id ?? '').trim();
    if (!targetUserId) {
      return json(400, { success: false, message: 'Güncellenecek kullanıcı bilgisi eksik.' });
    }

    const serviceRoleClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: targetProfileData, error: targetProfileError } = await serviceRoleClient
      .from('profiles')
      .select('id, company_id, role, is_active, full_name, phone, email')
      .eq('id', targetUserId)
      .maybeSingle();

    if (targetProfileError || !targetProfileData) {
      return json(404, { success: false, message: 'Kullanıcı bulunamadı.' });
    }

    if (targetProfileData.company_id !== callerProfileData.company_id) {
      return json(403, { success: false, message: 'Bu kullanıcı aynı şirkette değil.' });
    }

    const newFullName = body.full_name !== undefined ? String(body.full_name ?? '').trim() : undefined;
    const newPhone = body.phone !== undefined ? String(body.phone ?? '').trim() : undefined;
    const newRole = body.role !== undefined ? String(body.role ?? '').trim() : undefined;
    const newIsActive = body.is_active !== undefined ? Boolean(body.is_active) : undefined;

    const allowedRoles = ['manager', 'secretary', 'technician'];
    if (newRole && !allowedRoles.includes(newRole)) {
      return json(400, { success: false, message: 'Geçersiz kullanıcı rolü.' });
    }

    if (targetProfileData.id === callerProfileData.id && (newIsActive === false || (newRole && newRole !== 'manager'))) {
      return json(403, { success: false, message: 'Kendi hesabınızı pasif yapamaz veya rolünü değiştiremezsiniz.' });
    }

    const { data: managerCountData, error: managerCountError } = await serviceRoleClient
      .from('profiles')
      .select('id', { count: 'exact', head: true })
      .eq('company_id', callerProfileData.company_id)
      .eq('role', 'manager')
      .eq('is_active', true);

    if (managerCountError) {
      return json(500, { success: false, message: 'Yönetici sayısı doğrulanamadı.' });
    }

    const activeManagerCount = managerCountData?.count ?? 0;
    const isTargetManager = targetProfileData.role === 'manager';
    const roleChange = newRole && newRole !== targetProfileData.role;
    const activeChange = newIsActive !== undefined && newIsActive !== targetProfileData.is_active;

    if (isTargetManager && activeManagerCount <= 1 && ((newIsActive === false) || (roleChange && newRole !== 'manager'))) {
      return json(403, { success: false, message: 'Son aktif yönetici korunmalıdır.' });
    }

    const updatePayload: Record<string, unknown> = {};
    if (newFullName !== undefined) updatePayload.full_name = newFullName || targetProfileData.full_name;
    if (newPhone !== undefined) updatePayload.phone = newPhone || null;
    if (newRole !== undefined) updatePayload.role = newRole;
    if (newIsActive !== undefined) updatePayload.is_active = newIsActive;

    const { error: updateError } = await serviceRoleClient
      .from('profiles')
      .update(updatePayload)
      .eq('id', targetUserId);

    if (updateError) {
      return json(500, { success: false, message: 'Kullanıcı güncellenemedi.' });
    }

    const action = roleChange
      ? 'user_role_changed'
      : activeChange
        ? (newIsActive ? 'user_activated' : 'user_deactivated')
        : 'user_updated';

    const { error: auditError } = await serviceRoleClient.from('audit_logs').insert({
      company_id: callerProfileData.company_id,
      user_id: authData.user.id,
      action,
      entity_type: 'profiles',
      entity_id: targetUserId,
      old_values: {
        full_name: targetProfileData.full_name,
        phone: targetProfileData.phone,
        role: targetProfileData.role,
        is_active: targetProfileData.is_active,
      },
      new_values: {
        full_name: updatePayload.full_name ?? targetProfileData.full_name,
        phone: updatePayload.phone ?? targetProfileData.phone,
        role: updatePayload.role ?? targetProfileData.role,
        is_active: updatePayload.is_active ?? targetProfileData.is_active,
      },
      metadata: { updated_by: authData.user.id },
    });

    if (auditError) {
      return json(500, { success: false, message: 'Kullanıcı güncellendi, ancak audit kaydı yazılamadı.' });
    }

    return json(200, { success: true, message: 'Kullanıcı bilgileri güncellendi.' });
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
