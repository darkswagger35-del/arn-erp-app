# Supabase temel altyapı

Bu klasör, ARN ERP için Milestone 3 kapsamında hazırlanan SQL tabanlı şirket, profil, ayar ve denetim altyapısını içerir.

## Migration dosyası ne oluşturuyor?

- `public.companies`: şirket kayıtlarını tutar.
- `public.profiles`: auth kullanıcılarına bağlı şirket ve rol kayıtlarını tutar.
- `public.company_settings`: her şirket için tekil ayar kaydını tutar.
- `public.audit_logs`: şirket bazlı denetim kayıtlarını tutar.
- `updated_at` trigger'ları ve güvenli RLS yardımcı fonksiyonları eklenir.

## SQL Editor üzerinden nasıl çalıştırılır?

1. Supabase projesinin SQL Editor bölümünü açın.
2. [supabase/migrations/20260725_001_auth_company_foundation.sql](supabase/migrations/20260725_001_auth_company_foundation.sql) içeriğini yapıştırın.
3. Çalıştırın.

## Çalıştırmadan önce kontrol edilmesi gerekenler

- `auth.users` tablosu erişilebilir olmalı.
- `pgcrypto` uzantısı etkin olmalı.
- RLS ve policy isimleri hedef projede uyumlu olmalı.
- Gerçek ortamda yalnızca publishable key kullanın; secret key Flutter uygulamasına eklenmemelidir.

## İlk şirket ve ilk yönetici kullanıcı

İlk kurulum için örnek SQL dosyası [supabase/seed/initial_setup_example.sql](supabase/seed/initial_setup_example.sql) içinde yer almaktadır. Bu dosya otomatik çalıştırılmaz; elle uygulanmalıdır.

## RLS neden önemlidir?

RLS, her kullanıcıya yalnızca kendi şirket verisinin görünmesini sağlar. Böylece bir kullanıcı diğer şirketlerin verilerine erişemez.

## Migration daha önce çalıştıysa

Migration dosyasının tekrar çalıştırılması isteniyorsa önce mevcut obje isimlerinin durumu kontrol edilmelidir. Bu örnek dosya, mümkün olduğunca idempotent olacak şekilde hazırlanmıştır.
