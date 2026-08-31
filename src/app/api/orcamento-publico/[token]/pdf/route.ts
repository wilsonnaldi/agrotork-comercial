import { NextResponse } from "next/server";

import { getSharedDocument } from "@/modules/quotes/share/service";
import { pdfFileName, renderQuotePdf } from "@/modules/quotes/pdf/render";

/**
 * PDF a partir do TOKEN público, sem login.
 *
 * O conteúdo é o mesmo documento que a página pública mostra — ou seja,
 * o que `get_shared_quote` devolve: sem custo, sem observações internas,
 * sem telefone e e-mail do cliente. A validação do token acontece no
 * banco; aqui só existe "veio documento" ou "não veio".
 */
export async function GET(_request: Request, context: { params: Promise<{ token: string }> }) {
  const { token } = await context.params;

  const document = await getSharedDocument(token);
  if (!document) return new NextResponse("Link inválido ou expirado", { status: 404 });

  const pdf = await renderQuotePdf(document);

  return new NextResponse(new Uint8Array(pdf), {
    headers: {
      "content-type": "application/pdf",
      "content-disposition": `attachment; filename="${pdfFileName(document)}"`,
      "content-length": String(pdf.length),
      "cache-control": "private, no-store",
    },
  });
}
