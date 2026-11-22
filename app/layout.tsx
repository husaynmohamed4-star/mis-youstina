import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Miss Youstina English",
  description: "منصتك لتعلم اللغة الإنجليزية مع ميس يوستينا",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="ar" dir="rtl"><body>{children}</body></html>;
}
