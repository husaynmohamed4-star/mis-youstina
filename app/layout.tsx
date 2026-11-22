import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Miss Youstina | English Academy",
  description: "منصة ميس يوستينا لتعلم اللغة الإنجليزية: دروس ومراجعات وملازم لكل صف دراسي.",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="ar" dir="rtl"><body>{children}</body></html>;
}
