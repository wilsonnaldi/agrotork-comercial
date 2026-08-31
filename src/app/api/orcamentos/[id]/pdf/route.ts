import { NextResponse } from "next/server";

import { requirePermission } from "@/lib/auth/session";
import { buildDocument } from "@/modules/quotes/share/service";
import { pdfFileName, renderQuotePdf } from "@/modules/quotes/pdf/render";

/**
 * PDF do orçamento para quem está logado.
 *
 * É Route Handler, e não Server Action, porque o retorno é um ARQUIVO: o
 * navegador precisa de uma resposta com `content-type` e
 * `content-disposition` para baixar. Server Action devolve dados, não
 * corpo binário com cabeçalho de download.
 *
 * A autorização é a mesma do resto do módulo: `quotes.readOwn` na porta,
 * `buildDocument` recusando orçamento de outro vendedor, e o RLS por
 * baixo de tudo. Gerar o PDF não altera nada no orçamento.
 */
export async function GET(_request: Request, context: { params: Promise<{ id: string }> }) {
  const user = await requirePermission("quotes.readOwn");
  const { id } = await context.params;

  const document = await buildDocument(id, user.profile.role, user.id);
  // Orçamento inexistente e orçamento de outro vendedor respondem igual:
  // não confirmamos a existência de nada para quem não deveria ver.
  if (!document) return new NextResponse("Orçamento não encontrado", { status: 404 });

  const pdf = await renderQuotePdf(document);

  return new NextResponse(new Uint8Array(pdf), {
    headers: {
      "content-type": "application/pdf",
      "content-disposition": `attachment; filename="${pdfFileName(document)}"`,
      "content-length": String(pdf.length),
      // Documento comercial não fica em cache de intermediário.
      "cache-control": "private, no-store",
    },
  });
}
