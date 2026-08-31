/**
 * Content Security Policy.
 *
 * Precisa ser montada por REQUISIÇÃO, e não em `next.config.ts`, porque
 * cada resposta leva um `nonce` diferente. O Next.js lê o nonce do
 * cabeçalho `Content-Security-Policy` da requisição e o repassa às suas
 * próprias tags `<script>`; com `strict-dynamic`, os pedaços que esses
 * scripts carregam herdam a permissão. Nada mais executa.
 *
 * Por que cada diretiva está como está:
 *
 *  script-src   nonce + strict-dynamic. Sem `unsafe-inline`, que anularia
 *               o nonce, e sem `unsafe-eval`.
 *  style-src    `unsafe-inline` é necessário: o Next injeta estilo inline
 *               na renderização. É o ponto mais fraco da política, e o
 *               risco é baixo — CSS não executa código.
 *  img-src      `data:` para os ícones embutidos; o domínio do Supabase
 *               para as imagens do Storage (logotipo e foto de produto).
 *  connect-src  o próprio domínio (navegação RSC) e o Supabase.
 *  frame-ancestors  ninguém embute o sistema num iframe. Substitui, com
 *               mais força, o X-Frame-Options.
 *  form-action  formulário só posta para o próprio domínio.
 *
 * Em desenvolvimento a política é afrouxada: o HMR do Next usa `eval`.
 */

const SUPABASE = "https://*.supabase.co";

export function buildCsp(nonce: string, isDev: boolean): string {
  const scriptSrc = isDev
    ? `'self' 'unsafe-inline' 'unsafe-eval'`
    : `'self' 'nonce-${nonce}' 'strict-dynamic'`;

  return [
    `default-src 'self'`,
    `script-src ${scriptSrc}`,
    `style-src 'self' 'unsafe-inline'`,
    `img-src 'self' data: blob: ${SUPABASE}`,
    `font-src 'self'`,
    `connect-src 'self' ${SUPABASE}${isDev ? " ws: http://127.0.0.1:* http://localhost:*" : ""}`,
    `frame-ancestors 'none'`,
    `form-action 'self'`,
    `base-uri 'self'`,
    `object-src 'none'`,
    `upgrade-insecure-requests`,
  ].join("; ");
}

/** Nonce aleatório por requisição. `crypto` global existe no Edge e no Node 18+. */
export function newNonce(): string {
  return Buffer.from(crypto.randomUUID()).toString("base64");
}
