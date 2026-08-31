import type { NextConfig } from "next";

/**
 * Cabeçalhos de segurança aplicados a todas as rotas.
 *
 * A Content-Security-Policy NÃO está aqui: ela leva um `nonce` diferente
 * por resposta e é montada no proxy (`lib/security/csp.ts`). O
 * `frame-ancestors 'none'` de lá é mais forte que o X-Frame-Options
 * abaixo, que fica por compatibilidade com navegador antigo.
 * Ver ARCHITECTURE.md §9.
 */
const securityHeaders = [
  { key: "X-Content-Type-Options", value: "nosniff" },
  { key: "X-Frame-Options", value: "DENY" },
  { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
  { key: "Permissions-Policy", value: "camera=(), microphone=(), geolocation=(self)" },
  { key: "X-DNS-Prefetch-Control", value: "on" },
];

const nextConfig: NextConfig = {
  reactStrictMode: true,
  poweredByHeader: false,
  // `pdfkit` é CommonJS e lê as métricas das fontes padrão do próprio
  // pacote em tempo de execução. Empacotá-lo quebraria esses caminhos;
  // mantido externo, roda no Node do servidor como foi feito para rodar.
  serverExternalPackages: ["pdfkit"],
  images: {
    // Imagens de produto/kit ficam no Supabase Storage.
    remotePatterns: [{ protocol: "https", hostname: "*.supabase.co", pathname: "/storage/v1/object/public/**" }],
  },
  async headers() {
    return [{ source: "/:path*", headers: securityHeaders }];
  },
};

export default nextConfig;
