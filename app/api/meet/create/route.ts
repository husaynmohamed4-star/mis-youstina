import { NextResponse } from 'next/server';
import { createSign } from 'node:crypto';
import { requireAdmin } from '@/lib/server/supabase-admin';
export const runtime = 'nodejs';

async function googleAccessToken() {
  const email = process.env.GOOGLE_SERVICE_ACCOUNT_EMAIL;
  const privateKey = process.env.GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY?.replace(/\\n/g, '\n');
  const organizer = process.env.GOOGLE_MEET_ORGANIZER_EMAIL;
  if (!email || !privateKey || !organizer) throw new Error('إعداد Google Meet غير مكتمل: أضف حساب الخدمة وبريد المنظّمة.');
  const now = Math.floor(Date.now() / 1000);
  const enc = (v: object) => Buffer.from(JSON.stringify(v)).toString('base64url');
  const unsigned = `${enc({ alg: 'RS256', typ: 'JWT' })}.${enc({ iss: email, sub: organizer, scope: 'https://www.googleapis.com/auth/meetings.space.created', aud: 'https://oauth2.googleapis.com/token', iat: now, exp: now + 3600 })}`;
  const signer = createSign('RSA-SHA256'); signer.update(unsigned);
  const assertion = `${unsigned}.${signer.sign(privateKey, 'base64url')}`;
  const response = await fetch('https://oauth2.googleapis.com/token', { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion }) });
  const result = await response.json();
  if (!response.ok) throw new Error(result.error_description || 'تعذر الحصول على صلاحية Google Meet.');
  return result.access_token as string;
}

export async function POST(request: Request) {
  try {
    const { db, user } = await requireAdmin(request);
    const { title, grade, startsAt, endsAt } = await request.json();
    if (!title || !grade || !startsAt) return NextResponse.json({ error: 'أدخل عنوان الحصة والصف والموعد.' }, { status: 400 });
    const accessToken = await googleAccessToken();
    const meetResponse = await fetch('https://meet.googleapis.com/v2/spaces', { method: 'POST', headers: { authorization: `Bearer ${accessToken}`, 'content-type': 'application/json' }, body: JSON.stringify({ config: { accessType: 'RESTRICTED', entryPointAccess: 'ALL' } }) });
    const space = await meetResponse.json();
    if (!meetResponse.ok) throw new Error(space.error?.message || 'تعذر إنشاء رابط Google Meet.');
    const { data, error } = await db.from('live_classes').insert({ title, grade, starts_at: startsAt, ends_at: endsAt || null, meet_space_name: space.name, meet_url: space.meetingUri, created_by: user.id }).select('*').single();
    if (error) throw new Error(error.message);
    return NextResponse.json({ class: data });
  } catch (error) { return NextResponse.json({ error: error instanceof Error ? error.message : 'حدث خطأ.' }, { status: 400 }); }
}
