import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { status: 200, headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    return json(405, {
      success: false,
      message: 'Bu işlem için yalnızca POST isteği kullanılabilir.',
    });
  }

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader?.startsWith('Bearer ')) {
      return json(401, {
        success: false,
        message: 'Yetkilendirme başlığı eksik.',
      });
    }

    const jwt = authHeader.substring(7).trim();
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

    if (!supabaseUrl || !supabaseAnonKey || !serviceRoleKey) {
      return json(500, {
        success: false,
        message: 'Sunucu yapılandırması eksik.',
      });
    }

    const authClient = createClient(supabaseUrl, supabaseAnonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
      global: { headers: { Authorization: `Bearer ${jwt}` } },
    });

    const { data: authData, error: authError } =
        await authClient.auth.getUser(jwt);

    if (authError || !authData.user) {
      console.error('auth.getUser:', authError);
      return json(401, {
        success: false,
        message: 'Oturum doğrulanamadı. Çıkış yapıp tekrar giriş yapın.',
      });
    }

    const serviceRoleClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: callerProfile, error: callerProfileError } =
        await serviceRoleClient
            .from('profiles')
            .select('id, company_id, role, is_active')
            .eq('id', authData.user.id)
            .maybeSingle();

    if (callerProfileError || !callerProfile) {
      console.error('caller profile:', callerProfileError);
      return json(403, {
        success: false,
        message: 'Yönetici profili bulunamadı.',
      });
    }

    if (callerProfile.is_active !== true) {
      return json(403, {
        success: false,
        message: 'Bu kullanıcı hesabı pasif durumdadır.',
      });
    }

    // ARN ERP'de hem admin hem manager ekranda "Yönetici" görünür.
    if (!['admin', 'manager'].includes(String(callerProfile.role))) {
      return json(403, {
        success: false,
        message: 'Yalnızca yönetici kullanıcı oluşturabilir.',
      });
    }

    const body = await req.json().catch(() => ({}));
    const email = String(body.email ?? '').trim().toLowerCase();
    const fullName = String(body.full_name ?? '').trim();
    const username = String(body.username ?? '').trim().toLowerCase();
    const phone = String(body.phone ?? '').trim();
    const role = String(body.role ?? '').trim();
    const password = String(body.password ?? '');
    const passwordConfirmation =
        String(body.password_confirmation ?? '');
    const isActive = body.is_active !== false;

    if (!email || !fullName || !username || !password) {
      return json(400, {
        success: false,
        message: 'E-posta, ad soyad, kullanıcı adı ve şifre alanları zorunludur.',
      });
    }

    if (!/^[a-z0-9._-]{3,30}$/.test(username)) {
      return json(400, {
        success: false,
        message: 'Kullanıcı adı 3-30 karakter olmalı; harf, rakam, nokta, tire ve alt çizgi kullanılabilir.',
      });
    }

    const { data: existingUsername } = await serviceRoleClient
        .from('profiles')
        .select('id')
        .eq('company_id', callerProfile.company_id)
        .ilike('username', username)
        .maybeSingle();

    if (existingUsername) {
      return json(409, { success: false, message: 'Bu kullanıcı adı zaten kullanılıyor.' });
    }

    if (password !== passwordConfirmation) {
      return json(400, {
        success: false,
        message: 'Şifreler birbiriyle eşleşmiyor.',
      });
    }

    if (password.length < 6) {
      return json(400, {
        success: false,
        message: 'Şifre en az 6 karakter olmalıdır.',
      });
    }

    if (!['manager', 'secretary', 'technician'].includes(role)) {
      return json(400, {
        success: false,
        message: 'Geçersiz kullanıcı rolü.',
      });
    }

    const companyId = callerProfile.company_id;

    const { data: company, error: companyError } =
        await serviceRoleClient
            .from('companies')
            .select('id, is_active')
            .eq('id', companyId)
            .maybeSingle();

    if (companyError || !company || company.is_active !== true) {
      console.error('company:', companyError);
      return json(403, {
        success: false,
        message: 'Şirket aktif değil veya bulunamadı.',
      });
    }

    const { data: createdAuthUser, error: createAuthError } =
        await serviceRoleClient.auth.admin.createUser({
          email,
          password,
          email_confirm: true,
          user_metadata: {
            full_name: fullName,
            role,
            company_id: companyId,
          },
        });

    if (createAuthError || !createdAuthUser.user) {
      console.error('createUser:', createAuthError);
      return json(400, {
        success: false,
        message: createAuthError?.message?.toLowerCase().includes('already')
            ? 'Bu e-posta adresiyle kayıtlı bir kullanıcı zaten var.'
            : `Kullanıcı hesabı oluşturulamadı: ${createAuthError?.message ?? 'Bilinmeyen hata'}`,
      });
    }

    const createdUserId = createdAuthUser.user.id;

    const { error: profileInsertError } =
        await serviceRoleClient.from('profiles').insert({
          id: createdUserId,
          company_id: companyId,
          full_name: fullName,
          username,
          email,
          phone: phone.isEmpty ? null : phone,
          role,
          is_active: isActive,
        });

    if (profileInsertError) {
      console.error('profile insert:', profileInsertError);
      await serviceRoleClient.auth.admin.deleteUser(createdUserId);

      return json(500, {
        success: false,
        message:
            `Profil kaydı oluşturulamadı: ${profileInsertError.message}`,
      });
    }

    // audit_logs tablosu yoksa kullanıcı oluşturmayı bozmasın.
    try {
      const { error: auditError } =
          await serviceRoleClient.from('audit_logs').insert({
            company_id: companyId,
            user_id: authData.user.id,
            action: 'user_created',
            entity_type: 'profiles',
            entity_id: createdUserId,
            new_values: {
              full_name: fullName,
              username,
              role,
              email,
              phone: phone.isEmpty ? null : phone,
              is_active: isActive,
            },
            metadata: { created_by: authData.user.id },
          });

      if (auditError) {
        console.error('audit log:', auditError);
      }
    } catch (auditException) {
      console.error('audit exception:', auditException);
    }

    return json(200, {
      success: true,
      message: 'Kullanıcı başarıyla oluşturuldu.',
      user_id: createdUserId,
    });
  } catch (error) {
    console.error('unexpected:', error);

    return json(500, {
      success: false,
      message: error instanceof Error
          ? error.message
          : 'İşlem sırasında beklenmeyen bir hata oluştu.',
    });
  }
});

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json; charset=utf-8',
    },
  });
}
