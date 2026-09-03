import "server-only";

import * as repository from "./repository";
import { LOGO_MAX_BYTES, LOGO_MIME, type CompanyInput } from "./schema";
import type { DocumentCompany } from "@/modules/quotes/share/document";

export class BusinessError extends Error {
  constructor(
    message: string,
    readonly field?: string,
  ) {
    super(message);
    this.name = "BusinessError";
  }
}

export function getCompany(): Promise<DocumentCompany> {
  return repository.findCompany();
}

export function saveCompany(input: CompanyInput, userId: string): Promise<void> {
  return repository.saveCompany(input, userId);
}

/**
 * Recusa o arquivo ANTES de subir.
 *
 * O bucket já limita tamanho e tipo (migration 2000) e o RLS já exige
 * administrador — esta checagem não substitui nenhum dos dois. Ela existe
 * para o usuário receber "o arquivo tem 8 MB" em vez de um erro cru do
 * Storage depois de esperar o upload inteiro.
 */
export async function replaceLogo(arquivo: File, userId: string): Promise<string> {
  if (arquivo.size === 0) throw new BusinessError("Escolha um arquivo de imagem.", "logo");
  if (arquivo.size > LOGO_MAX_BYTES) {
    const mb = (arquivo.size / 1024 / 1024).toFixed(1);
    throw new BusinessError(`A imagem tem ${mb} MB. O limite é 5 MB.`, "logo");
  }
  if (!LOGO_MIME.includes(arquivo.type as (typeof LOGO_MIME)[number])) {
    throw new BusinessError("Use PNG, JPG, WEBP ou SVG.", "logo");
  }

  const { url } = await repository.uploadLogo(arquivo);
  await repository.saveLogoUrl(url, userId);
  return url;
}

/**
 * Tira o logotipo do cabeçalho.
 *
 * O arquivo continua no bucket de propósito: um orçamento antigo pode ter
 * sido enviado com ele, e apagar o arquivo quebraria a imagem em um PDF já
 * compartilhado. Some do cadastro, não do histórico.
 */
export function removeLogo(userId: string): Promise<void> {
  return repository.saveLogoUrl(null, userId);
}
