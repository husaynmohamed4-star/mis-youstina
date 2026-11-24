# Miss Youstina English Academy

منصة تعليمية عربية مبنية باستخدام Next.js وSupabase.

## المزايا الموجودة
- واجهة طلاب متجاوبة حسب الصف الدراسي.
- إنشاء حساب طالب وتسجيل الدخول وحفظ الاسم والصف.
- مكتبة فيديوهات الدروس مع علامة إكمال الدرس.
- مكتبة ملازم PDF.
- اختبارات اختيار من متعدد بتصحيح من الخادم وحفظ المحاولات والنتائج.
- صفحة حساب الطالب وملخص التقدم.
- إعلانات موجهة لكل الصفوف أو لصف محدد.
- لوحة إدارة مستقلة على `/admin`.
- ربط فيديوهات الدروس بروابط YouTube غير المدرجة، ورفع ملفات PDF من الجهاز.
- جدولة نشر وانتهاء عرض الدروس والملازم والاختبارات والإعلانات.
- إدارة حالة نشر المحتوى، حذف الدروس والملفات والاختبارات والإعلانات.
- لوحة إحصائيات وقائمة الطلاب ونتائج الاختبارات.

## التشغيل
1. ثبّت Node.js 20 أو أحدث.
2. نفّذ `npm install` ثم `npm run dev`.
3. انسخ `.env.example` إلى `.env.local` وأدخل إعدادات مشروع Supabase.

## إعداد Supabase
- إذا لم تكن قد شغّلت `supabase/setup.sql` من قبل، شغّله أولاً.
- بعده شغّل `supabase/full_platform.sql` مرة واحدة في SQL Editor. هذا ملف ترقية إضافي يحافظ على الجداول الحالية ويضيف خصائص المنصة.
- أنشئ حساب الإدارة من Supabase Authentication ثم امنحه الدور باستخدام UUID الخاص به:

```sql
insert into public.user_roles (user_id, role)
values ('AUTH_USER_UUID', 'admin')
on conflict (user_id) do update set role = excluded.role;
```

- أضف متغيري `NEXT_PUBLIC_SUPABASE_URL` و`NEXT_PUBLIC_SUPABASE_ANON_KEY` إلى Vercel ثم أعد النشر.
- تأكد من تفعيل تأكيد البريد الإلكتروني أو ضبطه حسب طريقة تسجيل الطلاب التي تريدها.

## ملاحظات مهمة قبل الإطلاق العام
- فيديوهات الدروس الجديدة مستضافة على YouTube بوضع Unlisted، بينما تحفظ Supabase بيانات الدروس فقط. قد تبقى ملفات فيديو قديمة أو فيديوهات حلول اختبارات في Supabase Storage.
- الدفع والاشتراكات متوقفة في الإصدار المجاني. الحصص المباشرة عبر Google Meet متاحة بعد إعداد Google API وبيانات حساب المدرّسة.
- راجع إعدادات البريد وتأكيد الحساب وسياسة الخصوصية وشروط الاستخدام قبل استقبال الطلاب.
- لا تضع مفاتيح Supabase السرية (service role) في متغيرات `NEXT_PUBLIC_` أو في المتصفح.

## تشغيل المنصة مجاناً بدون اشتراكات أو دفع
1. بعد تشغيل `setup.sql` و`full_platform.sql` و`upgrade_live_payments.sql` (إذا كنت تستخدم جداول Meet) و`youtube_lessons_subscriptions.sql`، شغّل `supabase/free_access_no_subscriptions.sql` في Supabase SQL Editor. هذا الملف يزيل شرط الاشتراك من قراءة الدروس والملازم والاختبارات والحصص، مع الإبقاء على تسجيل الدخول وتقييد المحتوى حسب الصف الدراسي.
2. لا تحتاج إلى حساب تاجر Fawry أو مفاتيح دفع أو إعداد باقات أو أكواد تفعيل في هذه المرحلة.
3. لا يحتاج الطالب إلى شراء اشتراك؛ ينشئ حساباً مجانياً ويسجل الدخول ليصل إلى المحتوى المنشور الخاص بصفه.
4. تظل صفحة `/admin/live` لإدارة الحصص، وصفحة `/live` للطلاب. إعداد Google Meet API وحساب المدرّسة ما زال مطلوباً إذا أردت إنشاء الاجتماعات وإضافة الطلاب تلقائياً.

### حدود التكامل الحالية
- Google Meet لا يوفّر تجربة مكالمة Meet الكاملة كتضمين iframe عادي داخل موقع خارجي؛ زر دخول الحصة يفتح Meet في تبويب/تطبيق منفصل. تظل صفحة المنصة مفتوحة في التبويب الأصلي.
- استيراد المشاركين من Meet يحفظ الاسم وأوقات الدخول/الخروج للمراجعة. لا يتم ربط الاسم تلقائياً بحساب الطالب لأن Meet قد يعرض أسماء غير موثقة أو متكررة؛ يلزم مطابقة إدارية أو نظام دخول موثّق إذا أردت حضوراً مؤكداً لكل حساب.
- إنهاء الحصة واستيراد الحضور يتم حالياً من لوحة الإدارة. الأتمتة الكاملة عند إغلاق اجتماع Meet تحتاج إعداد اشتراك Google Workspace Events webhook ونشر endpoint عام والتحقق من إشعارات Google.
- لم يتم نقل الفيديوهات إلى Bunny/Cloudflare في هذه المرحلة؛ يلزم اختيار مزود الفيديو وبيانات الحساب وخطة التخزين قبل نقل الأصول الحالية.

## YouTube Unlisted lessons — free student access
1. After running the previous SQL files, run `supabase/youtube_lessons_subscriptions.sql` only if needed for the YouTube columns, then run `supabase/free_access_no_subscriptions.sql` to enable free access.
2. Upload each lesson to the academy's YouTube channel and set its visibility to **Unlisted / غير مدرج** (not Private). Copy its share URL.
3. In `/admin`, choose **فيديو شرح**, enter the lesson title, grade, unit and YouTube URL, then save. Supabase stores only the lesson metadata and YouTube video ID; the video file itself stays on YouTube.
4. Students only need a free account and sign-in. Published lessons, worksheets, quizzes and live classes are available to accounts whose profile grade matches the content grade; no paid subscription is checked.
5. Existing Supabase-hosted videos remain supported and are not deleted by this migration. New lesson videos use YouTube's privacy-enhanced embed player (`youtube-nocookie.com`).

**YouTube Unlisted is link privacy, not strong access control:** anyone who gets the video URL can watch or share it outside the platform. The platform checks sign-in and grade before returning lesson metadata, but YouTube itself does not verify the student's account or grade. Do not use this mode for content that must be restricted to named students only. For stronger protection, move videos to a provider with signed playback tokens when the platform grows.


**الإصدار الحالي مجاني:** تم إيقاف واجهات الدفع والاشتراكات وأكواد التفعيل من واجهة الطالب والإدارة. جداول الاشتراكات القديمة قد تظل موجودة في Supabase إذا سبق تشغيل ملفات الترقية، لكنها غير مستخدمة في تدفق الطالب الحالي.
