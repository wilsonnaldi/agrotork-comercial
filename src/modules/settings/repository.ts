import "server-only";

import { createClient } from "@/lib/supabase/server";
import { toCompany } from "@/modules/quotes/share/repository";
import type { DocumentCompany } from "@/modules/quotes/share/document";
import type { CompanyInput } from "./schema";
import { LOGO_MIME } from "./schema";

/**
 * Acesso a `app_settings` e ao bucket do logotipo.
 *
 * Quem autoriza é o RLS: `app_settings_admin` exige `is_admin()` para
 * escrever, e as policies de `storage.objects` da migration 2000 exigem o
 * mesmo para gravar em `public-assets`. Nenhuma chave privilegiada é usada
 * — o cliente aqui age com o JWT do usuário logado, como em todo o resto.
 */

const BUCKET = "public-assets";
const PASTA = "empresa";

/** Lê os dados da empresa já normalizados no formato do documento. */
export async function findCompany(): Promise<DocumentCompany> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("app_settings")
    .select("value")
    .eq("key", "company")
    .maybeSingle();

  if (error) throw new Error(error.message);
  return toCompany(data?.value);
}

/**
 * Grava os dados da empresa preservando o que não veio no formulário —
 * hoje o `logo_url`, que tem fluxo próprio de upload.
 */
export async function saveCompany(input: CompanyInput, userId: string): Promise<void> {
  const supabase = await createClient();
  const atual = await findCompany();

  const { error } = await supabase
    .from("app_settings")
    .update({
      value: { ...input, logo_url: atual.logo_url },
      updated_by: userId,
    })
    .eq("key", "company");

  if (error) throw new Error(error.message);
}

/** Grava só o endereço do logotipo, sem tocar no resto do cadastro. */
export async function saveLogoUrl(logoUrl: string | null, userId: string): Promise<void> {
  const supabase = await createClient();
  const atual = await findCompany();

  const { error } = await supabase
    .from("app_settings")
    .update({ value: { ...atual, logo_url: logoUrl }, updated_by: userId })
    .eq("key", "company");

  if (error) throw new Error(error.message);
}

export type LogoUpload = { url: string; path: string };

/**
 * Sobe o arquivo e devolve a URL pública.
 *
 * O nome leva um sufixo de tempo de propósito: trocar o logotipo por outro
 * de mesmo nome deixaria o navegador e a CDN servindo o antigo. Arquivo
 * novo, endereço novo, sem cache velho no PDF do cliente.
 */
export async function uploadLogo(arquivo: File): Promise<LogoUpload> {
  const supabase = await createClient();

  const extensao = EXTENSOES[arquivo.type as (typeof LOGO_MIME)[number]] ?? "png";
  const caminho = `${PASTA}/logo-${Date.now()}.${extensao}`;

  const { error } = await supabase.storage.from(BUCKET).upload(caminho, arquivo, {
    contentType: arquivo.type,
    upsert: false,
  });
  if (error) throw new Error(error.message);

  const { data } = supabase.storage.from(BUCKET).getPublicUrl(caminho);
  return { url: data.publicUrl, path: caminho };
}

const EXTENSOES: Record<(typeof LOGO_MIME)[number], string> = {
  "image/png": "png",
  "image/jpeg": "jpg",
  "image/webp": "webp",
  "image/svg+xml": "svg",
};
