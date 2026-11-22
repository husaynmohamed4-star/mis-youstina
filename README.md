# Miss Youstina English

واجهة تعليمية احترافية مبنية بـ Next.js، جاهزة للنشر على Vercel بعد إعداد Supabase.

## المميزات
- تصميم عربي RTL متجاوب مع حركات بسيطة وواجهة احترافية.
- الصفوف الأربعة المطلوبة.
- عرض فيديوهات الشرح والملازم حسب الصف.
- لوحة إدارة محمية بتسجيل دخول Supabase.
- رفع الفيديو وملفات PDF مباشرة من جهاز الميس إلى Supabase Storage، بدون نسخ روابط.
- حذف المحتوى من لوحة الإدارة.

## 1. إنشاء مشروع Supabase
1. أنشئي مشروعاً جديداً على https://supabase.com
2. افتحي SQL Editor وشغّلي كامل ملف `supabase/setup.sql`.
3. من Authentication > Users أنشئي حساباً للميس.
4. انسخي UUID الخاص بالمستخدم من صفحة المستخدمين.
5. في SQL Editor نفذي:
   `insert into public.user_roles (user_id, role) values ('UUID_HERE', 'admin');`
6. من Project Settings > API انسخي Project URL و anon/public key.

## 2. إعداد متغيرات البيئة
انسخي `.env.example` إلى `.env.local` وضعي القيم الحقيقية:
- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`

لا تضعي service_role key في الموقع أو في متغير يبدأ بـ NEXT_PUBLIC.

## 3. التشغيل محلياً
```bash
npm install
npm run dev
```
ثم افتحي http://localhost:3000

## 4. النشر على Vercel
1. ارفعي مجلد المشروع إلى GitHub.
2. من Vercel اختاري Add New Project ثم اربطي مستودع GitHub.
3. أضيفي متغيري البيئة نفسهما في Project Settings > Environment Variables.
4. اضغطي Deploy.

## ملاحظات مهمة حول الفيديو
- الملفات ترفع مباشرة من المتصفح إلى Supabase Storage، ولا تُخزن على قرص Vercel.
- الحد المضبوط في SQL هو 2GB للفيديو، لكن رفع الملفات الكبيرة يحتاج التأكد من حدود مشروع Supabase وخطة التخزين/الرفع. يفضّل ضغط الفيديو قبل رفعه.
- هذا الإصدار يعرض الفيديو كرابط مباشر من التخزين؛ يمكن لاحقاً إضافة مشغل فيديو داخلي، حماية المحتوى، اختبارات بوقت محدد، واشتراكات.
- الاختبارات التفاعلية لم تُنفذ بعد في هذه النسخة؛ قسمها واجهة تمهيدية.
