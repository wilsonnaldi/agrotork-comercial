import type { Metadata, Viewport } from "next";
import localFont from "next/font/local";
import "./globals.css";

/**
 * Fontes da marca AGROTORK, auto-hospedadas.
 * Sem requisição ao Google Fonts: carrega mais rápido em rede fraca (uso em campo),
 * o build funciona offline e nenhum dado do usuário sai para terceiros.
 */
const oswald = localFont({
  variable: "--font-oswald",
  display: "swap",
  src: [
    { path: "../fonts/oswald-400.woff2", weight: "400", style: "normal" },
    { path: "../fonts/oswald-500.woff2", weight: "500", style: "normal" },
    { path: "../fonts/oswald-600.woff2", weight: "600", style: "normal" },
    { path: "../fonts/oswald-700.woff2", weight: "700", style: "normal" },
  ],
});

const workSans = localFont({
  variable: "--font-work-sans",
  display: "swap",
  src: [
    { path: "../fonts/work-sans-400.woff2", weight: "400", style: "normal" },
    { path: "../fonts/work-sans-500.woff2", weight: "500", style: "normal" },
    { path: "../fonts/work-sans-600.woff2", weight: "600", style: "normal" },
  ],
});

export const metadata: Metadata = {
  title: {
    default: "AGROTORK · Sistema Comercial",
    template: "%s · AGROTORK",
  },
  description: "Clientes, produtos, kits e orçamentos da AGROTORK.",
  robots: { index: false, follow: false },
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  maximumScale: 5,
  themeColor: "#1c1c1e",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="pt-BR" className={`${oswald.variable} ${workSans.variable}`}>
      <body className="min-h-dvh antialiased">{children}</body>
    </html>
  );
}
