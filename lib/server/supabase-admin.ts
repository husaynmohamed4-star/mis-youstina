import { createClient } from '@supabase/supabase-js';

export function adminDb() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) throw new Error('SUPABASE_SERVICE_ROLE_KEY أو NEXT_PUBLIC_SUPABASE_URL غير مضبوط.');
  return createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
}

export async function requireUser(request: Request) {
  const token = request.headers.get('authorization')?.replace(/^Bearer\s+/i, '');
  if (!token) throw new Error('يجب تسجيل الدخول أولاً.');
  const db = adminDb();
  const { data, error } = await db.auth.getUser(token);
  if (error || !data.user) throw new Error('جلسة الدخول غير صالحة.');
  return { db, user: data.user };
}

export async function requireAdmin(request: Request) {
  const ctx = await requireUser(request);
  const { data } = await ctx.db.from('user_roles').select('role').eq('user_id', ctx.user.id).maybeSingle();
  if (data?.role !== 'admin') throw new Error('هذه العملية متاحة للإدارة فقط.');
  return ctx;
}
