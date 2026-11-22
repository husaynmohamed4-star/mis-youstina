 "use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { supabase } from "@/lib/supabase";
import {
  ArrowLeft, BookOpen, PlayCircle, FileText, GraduationCap, Menu, X,
  Sparkles, UploadCloud, Video, ClipboardList, LogIn, LogOut, CheckCircle2,
  Clock3, Search, BookMarked, Layers3, LockKeyhole, Trash2, ExternalLink
} from "lucide-react";

const grades = ["أولى ثانوي", "تانية ثانوي عام", "تانية ثانوي بكالوريا", "تالتة ثانوي"];
type Lesson = { id: string; title: string; grade: string; unit: string | null; video_url: string; storage_path: string; created_at: string; };
type Worksheet = { id: string; title: string; grade: string; file_url: string; storage_path: string; created_at: string; };

export default function Home() {
  const [section, setSection] = useState("home");
  const [grade, setGrade] = useState(grades[0]);
  const [lessons, setLessons] = useState<Lesson[]>([]);
  const [worksheets, setWorksheets] = useState<Worksheet[]>([]);
  const [menuOpen, setMenuOpen] = useState(false);
  const [adminOpen, setAdminOpen] = useState(false);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loggedIn, setLoggedIn] = useState(false);
  const [isAdmin, setIsAdmin] = useState(false);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [title, setTitle] = useState("");
  const [unit, setUnit] = useState("");
  const [kind, setKind] = useState<"video" | "pdf">("video");
  const [file, setFile] = useState<File | null>(null);
  const [uploadGrade, setUploadGrade] = useState(grades[0]);
  const [search, setSearch] = useState("");
  const fileRef = useRef<HTMLInputElement>(null);

  const configured = !!supabase;
  const filteredLessons = useMemo(() => lessons.filter(x => x.grade === grade && x.title.toLowerCase().includes(search.toLowerCase())), [lessons, grade, search]);
  const filteredWorksheets = worksheets.filter(x => x.grade === grade);

  async function loadContent() {
    if (!supabase) return;
    const [l, w] = await Promise.all([
      supabase.from("lessons").select("*").eq("published", true).order("created_at", { ascending: false }),
      supabase.from("worksheets").select("*").eq("published", true).order("created_at", { ascending: false })
    ]);
    if (l.data) setLessons(l.data as Lesson[]);
    if (w.data) setWorksheets(w.data as Worksheet[]);
  }

  async function checkAdmin() {
    if (!supabase) return;
    const { data: { user } } = await supabase.auth.getUser();
    setLoggedIn(!!user);
    if (user) {
      const { data } = await supabase.from("user_roles").select("role").eq("user_id", user.id).maybeSingle();
      setIsAdmin(data?.role === "admin");
    } else setIsAdmin(false);
  }

  useEffect(() => {
    loadContent();
    checkAdmin();
    if (!supabase) return;
    const { data: listener } = supabase.auth.onAuthStateChange(() => { checkAdmin(); });
    return () => listener.subscription.unsubscribe();
  }, []);

  function go(id: string) { setSection(id); setMenuOpen(false); setMessage(""); window.scrollTo({ top: 0, behavior: "smooth" }); }

  async function login(e: React.FormEvent) {
    e.preventDefault(); setBusy(true); setMessage("");
    if (!supabase) { setMessage("أضيفي إعدادات Supabase أولاً في ملف .env.local"); setBusy(false); return; }
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) setMessage("تعذر تسجيل الدخول: " + error.message);
    else { await checkAdmin(); setMessage("تم تسجيل الدخول."); }
    setBusy(false);
  }

  async function logout() {
    if (supabase) await supabase.auth.signOut();
    setLoggedIn(false); setIsAdmin(false); setAdminOpen(false); setMessage("");
  }

  async function uploadContent(e: React.FormEvent) {
    e.preventDefault();
    if (!supabase || !file || !title.trim()) { setMessage("اكتبي اسم المحتوى واختاري ملفاً."); return; }
    if (!isAdmin) { setMessage("هذا الحساب غير مصرح له بإدارة المحتوى."); return; }
    setBusy(true); setMessage("جاري رفع الملف...");
    const ext = file.name.split(".").pop() || "file";
    const path = `${uploadGrade.replaceAll(" ", "-")}/${Date.now()}-${crypto.randomUUID()}.${ext}`;
    const bucket = kind === "video" ? "videos" : "worksheets";
    const { error: uploadError } = await supabase.storage.from(bucket).upload(path, file, { upsert: false, contentType: file.type });
    if (uploadError) { setMessage("فشل رفع الملف: " + uploadError.message); setBusy(false); return; }
    const { data: publicData } = supabase.storage.from(bucket).getPublicUrl(path);
    // Insert into each table separately so TypeScript can validate the
    // distinct row shapes (lessons have `unit`; worksheets do not).
    const insertResult = kind === "video"
      ? await supabase.from("lessons").insert({
          title: title.trim(),
          grade: uploadGrade,
          unit: unit.trim() || null,
          video_url: publicData.publicUrl,
          storage_path: path,
          published: true
        })
      : await supabase.from("worksheets").insert({
          title: title.trim(),
          grade: uploadGrade,
          file_url: publicData.publicUrl,
          storage_path: path,
          published: true
        });
    const dbError = insertResult.error;
    if (dbError) { setMessage("تم رفع الملف لكن تعذر حفظ بياناته: " + dbError.message); setBusy(false); return; }
    setTitle(""); setUnit(""); setFile(null); if (fileRef.current) fileRef.current.value = "";
    setMessage("تم رفع المحتوى ونشره بنجاح."); await loadContent(); setBusy(false);
  }

  async function deleteContent(type: "video" | "pdf", item: Lesson | Worksheet) {
    if (!supabase || !isAdmin) return;
    const table = type === "video" ? "lessons" : "worksheets";
    const bucket = type === "video" ? "videos" : "worksheets";
    const path = "storage_path" in item ? item.storage_path : null;
    const { error } = await supabase.from(table).delete().eq("id", item.id);
    if (!error && path) await supabase.storage.from(bucket).remove([path]);
    await loadContent();
  }

  const nav = [
    { id: "home", label: "الرئيسية", icon: Sparkles },
    { id: "lessons", label: "فيديوهات الشرح", icon: PlayCircle },
    { id: "quizzes", label: "الأسئلة التفاعلية", icon: ClipboardList },
    { id: "worksheets", label: "الملازم", icon: FileText },
  ];

  return <main>
    <header className="topbar">
      <a className="wordmark" onClick={() => go("home")}><span className="mark">MY</span><span><b>Miss Youstina</b><small>ENGLISH ACADEMY</small></span></a>
      <nav className={menuOpen ? "nav open" : "nav"}>{nav.map(n => <button key={n.id} className={section === n.id ? "navlink selected" : "navlink"} onClick={() => go(n.id)}><n.icon size={16}/>{n.label}</button>)}</nav>
      <div className="top-actions"><button className="admin-trigger" onClick={() => {setAdminOpen(true);setMessage("");}}><LockKeyhole size={16}/> لوحة الميس</button><button className="mobile-menu" onClick={() => setMenuOpen(!menuOpen)}>{menuOpen ? <X/> : <Menu/>}</button></div>
    </header>

    {section === "home" && <><section className="hero">
      <div className="hero-copy"><div className="eyebrow"><Sparkles size={15}/> YOUR ENGLISH JOURNEY STARTS HERE</div><h1>الإنجليزي<br/><span>أسهل مع يوستينا.</span></h1><p>شرح واضح، تدريب ذكي، ومراجعات تساعدك تدخل الامتحان وأنت واثق.</p><div className="hero-buttons"><button className="btn-main" onClick={() => go("lessons")}>ابدأ التعلم <ArrowLeft size={17}/></button><button className="btn-ghost" onClick={() => go("worksheets")}>تصفح الملازم</button></div><div className="hero-proof"><span><CheckCircle2 size={15}/> محتوى لكل صف</span><span><CheckCircle2 size={15}/> تعلم في أي وقت</span></div></div>
      <div className="hero-visual"><div className="orb orb-one"/><div className="orb orb-two"/><div className="floating-card card-a"><PlayCircle/><span>شرح الدروس</span></div><div className="floating-card card-b"><BookMarked/><span>ملازم ومراجعات</span></div><div className="visual-core"><div className="big-book"><BookOpen size={76}/></div><div className="spark">✦</div><div className="visual-caption">Learn · Practice · Achieve</div></div><div className="floating-number">01 <small>START</small></div></div>
    </section>
    <section className="stats"><div><b>04</b><span>صفوف دراسية</span></div><div><b>24/7</b><span>تعلم في أي وقت</span></div><div><b>100%</b><span>مجانية في البداية</span></div></section>
    <section className="section"><div className="section-heading"><div><span className="kicker">CHOOSE YOUR GRADE</span><h2>ابدأ من صفك الدراسي</h2><p>كل صف له محتواه المنظم والمخصص.</p></div><span className="section-index">01 / GRADES</span></div><div className="grade-grid">{grades.map((g,i)=><button className={`grade-card grade-${i+1}`} key={g} onClick={()=>{setGrade(g);go("lessons");}}><span className="grade-no">0{i+1}</span><span className="grade-icon"><GraduationCap size={26}/></span><b>{g}</b><small>الدروس · الأسئلة · الملازم</small><span className="card-arrow"><ArrowLeft size={18}/></span></button>)}</div></section>
    <section className="feature-band"><div><span className="kicker light">A SMARTER WAY TO LEARN</span><h2>مشاهدة، تدريب، وتقدم.</h2><p>كل أدوات المذاكرة اللي تحتاجها في تجربة واحدة سهلة.</p></div><div className="feature-pills"><span><PlayCircle/> فيديوهات الشرح</span><span><ClipboardList/> أسئلة تفاعلية</span><span><FileText/> ملازم PDF</span></div></section></>}

    {section === "lessons" && <section className="section inner-page"><div className="section-heading"><div><span className="kicker">LESSON LIBRARY</span><h2>فيديوهات الشرح</h2><p>اختار الصف وابحث عن الدرس اللي محتاجه.</p></div></div><GradePicker grade={grade} setGrade={setGrade}/><div className="searchbox"><Search size={18}/><input value={search} onChange={e=>setSearch(e.target.value)} placeholder="ابحث عن درس أو وحدة..."/></div><div className="content-grid">{filteredLessons.map(x=><article className="content-card" key={x.id}><div className="content-thumb"><PlayCircle size={42}/><span>LESSON VIDEO</span></div><div className="content-body"><span className="kicker">{x.grade}</span><h3>{x.title}</h3>{x.unit&&<p>{x.unit}</p>}<a href={x.video_url} target="_blank" rel="noreferrer" className="text-link">مشاهدة الفيديو <ArrowLeft size={16}/></a></div></article>)}</div>{filteredLessons.length===0&&<Empty icon={<Video/>} text={configured?"لسه مفيش فيديوهات منشورة للصف ده.":"اربط المنصة بقاعدة البيانات لعرض الفيديوهات."}/>}</section>}

    {section === "quizzes" && <section className="section inner-page"><div className="section-heading"><div><span className="kicker">PRACTICE & IMPROVE</span><h2>الأسئلة التفاعلية</h2><p>اختبر فهمك وراجع إجاباتك بعد كل تدريب.</p></div></div><GradePicker grade={grade} setGrade={setGrade}/><div className="quiz-intro"><ClipboardList size={36}/><div><b>تدريباتك في مكان واحد</b><p>قسم الأسئلة قيد التجهيز؛ سيتم ربط بنك الأسئلة وفيديوهات الحل في المرحلة التالية.</p></div></div></section>}

    {section === "worksheets" && <section className="section inner-page"><div className="section-heading"><div><span className="kicker">STUDY MATERIALS</span><h2>الملازم والمراجعات</h2><p>كل ملفاتك الدراسية مرتبة حسب الصف.</p></div></div><GradePicker grade={grade} setGrade={setGrade}/><div className="worksheet-list">{filteredWorksheets.map(x=><div className="worksheet" key={x.id}><div className="pdf-icon"><FileText/></div><div className="worksheet-info"><b>{x.title}</b><small>{x.grade} · ملف PDF</small></div><a href={x.file_url} target="_blank" rel="noreferrer" className="download-link">فتح الملف <ExternalLink size={15}/></a></div>)}</div>{filteredWorksheets.length===0&&<Empty icon={<FileText/>} text="لا توجد ملازم مضافة لهذا الصف حتى الآن."/>}</section>}

    <footer><div className="footer-brand"><span className="mark">MY</span><b>Miss Youstina English</b></div><span>Learn English. Practice. Achieve.</span><span>© {new Date().getFullYear()} جميع الحقوق محفوظة</span></footer>

    {adminOpen && <div className="modal-backdrop" onClick={e=>{if(e.target===e.currentTarget)setAdminOpen(false);}}><div className="admin-modal"><div className="modal-head"><div><span className="kicker">ADMIN SPACE</span><h2>لوحة تحكم الميس</h2></div><button className="icon-button" onClick={()=>setAdminOpen(false)}><X/></button></div>
      {!loggedIn ? <form onSubmit={login} className="login-form"><div className="login-symbol"><LockKeyhole/></div><h3>تسجيل دخول الإدارة</h3><p>الدخول مخصص لحساب الإدارة المعتمد فقط.</p><label>البريد الإلكتروني</label><input type="email" value={email} onChange={e=>setEmail(e.target.value)} required placeholder="name@example.com"/><label>كلمة المرور</label><input type="password" value={password} onChange={e=>setPassword(e.target.value)} required placeholder="••••••••"/><button className="btn-main full" disabled={busy}>{busy?"جاري الدخول...":"تسجيل الدخول"} <LogIn size={16}/></button></form>
      : !isAdmin ? <div className="notice"><LockKeyhole/><b>الحساب غير مفعل كمسؤول</b><p>يجب منح هذا المستخدم صلاحية admin من جدول user_roles في Supabase.</p><button className="btn-ghost" onClick={logout}>تسجيل الخروج</button></div>
      : <><div className="admin-welcome"><CheckCircle2/><span>أهلاً بيكي، تقدري تضيفي المحتوى من هنا.</span><button onClick={logout}><LogOut size={15}/> خروج</button></div><form onSubmit={uploadContent} className="upload-form">
        <label>نوع المحتوى</label><div className="segmented"><button type="button" className={kind==="video"?"on":""} onClick={()=>{setKind("video");setFile(null);}}> <Video size={16}/> فيديو شرح</button><button type="button" className={kind==="pdf"?"on":""} onClick={()=>{setKind("pdf");setFile(null);}}> <FileText size={16}/> ملزمة PDF</button></div>
        <label>اسم المحتوى</label><input value={title} onChange={e=>setTitle(e.target.value)} required placeholder="مثال: Unit 1 - Lesson 1"/>
        {kind==="video"&&<><label>اسم الوحدة (اختياري)</label><input value={unit} onChange={e=>setUnit(e.target.value)} placeholder="مثال: Unit One"/></>}
        <label>الصف الدراسي</label><select value={uploadGrade} onChange={e=>setUploadGrade(e.target.value)}>{grades.map(g=><option key={g}>{g}</option>)}</select>
        <label>اختاري الملف من جهازك</label><div className="dropzone" onClick={()=>fileRef.current?.click()}><UploadCloud size={30}/><b>{file?file.name:"اضغطي لاختيار الملف"}</b><small>{kind==="video"?"MP4 أو MOV أو WebM · يفضل ضغط الفيديوهات الكبيرة":"ملف PDF"}</small><input ref={fileRef} type="file" accept={kind==="video"?"video/mp4,video/quicktime,video/webm,video/*":".pdf,application/pdf"} onChange={e=>setFile(e.target.files?.[0]||null)} hidden/></div>
        {file&&<div className="file-selected"><CheckCircle2 size={16}/>{(file.size/1024/1024).toFixed(1)} MB <button type="button" onClick={()=>{setFile(null);if(fileRef.current)fileRef.current.value="";}}>إزالة</button></div>}
        <button className="btn-main full" disabled={busy||!file}>{busy?"جاري الرفع...":"رفع ونشر المحتوى"} <UploadCloud size={17}/></button>
        <p className="upload-note">يتم رفع الملف مباشرة إلى مساحة التخزين، ثم إضافته لقائمة المحتوى.</p>
      </form><div className="admin-items"><h3>المحتوى المنشور</h3>{lessons.map(x=><div className="admin-row" key={x.id}><span><Video size={16}/>{x.title} <small>{x.grade}</small></span><button onClick={()=>deleteContent("video",x)}><Trash2 size={15}/></button></div>)}{worksheets.map(x=><div className="admin-row" key={x.id}><span><FileText size={16}/>{x.title} <small>{x.grade}</small></span><button onClick={()=>deleteContent("pdf",x)}><Trash2 size={15}/></button></div>)}</div></>}
      {message&&<div className="status-message">{message}</div>}
      {!configured&&<div className="config-warning">قبل استخدام الرفع، أكملي إعداد Supabase وأضيفي مفاتيح المشروع في Vercel.</div>}
    </div></div>}
  </main>;
}

function GradePicker({grade,setGrade}:{grade:string;setGrade:(g:string)=>void}) {
  return <div className="grade-picker">{grades.map(g=><button key={g} className={grade===g?"active":""} onClick={()=>setGrade(g)}>{g}</button>)}</div>;
}
function Empty({icon,text}:{icon:React.ReactNode;text:string}) { return <div className="empty-state"><div>{icon}</div><b>{text}</b></div>; }
