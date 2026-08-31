"use client";

import { useState } from "react";
import { Check, Copy, Share2 } from "lucide-react";

import { Button } from "@/components/ui/button";
import { formatDateTime } from "@/lib/format";
import type { ShareLink } from "@/modules/quotes/share/service";

/**
 * Copiar e compartilhar o link público.
 *
 * A Web Share API abre a folha nativa do celular — que é onde o vendedor
 * de fato manda a proposta pelo WhatsApp. Onde ela não existe (desktop),
 * o botão copia para a área de transferência. Nada aqui fala com o
 * WhatsApp diretamente: integração é outra fase.
 */
export function ShareActions({ link, quoteNumber }: { link: ShareLink; quoteNumber: string }) {
  const [copiado, setCopiado] = useState(false);
  const [erro, setErro] = useState<string | null>(null);

  async function copiar() {
    setErro(null);
    try {
      await navigator.clipboard.writeText(link.url);
      setCopiado(true);
      setTimeout(() => setCopiado(false), 2500);
    } catch {
      // Sem permissão de área de transferência: o link está visível na
      // tela e pode ser copiado à mão.
      setErro("Não foi possível copiar. Selecione o endereço acima.");
    }
  }

  async function compartilhar() {
    setErro(null);
    if (typeof navigator.share !== "function") {
      await copiar();
      return;
    }
    try {
      await navigator.share({
        title: `Orçamento ${quoteNumber}`,
        text: `Segue o orçamento ${quoteNumber}.`,
        url: link.url,
      });
    } catch {
      // O usuário fechou a folha de compartilhamento. Não é erro.
    }
  }

  return (
    <div className="space-y-2">
      <p
        data-testid="share-url"
        className="rounded-lg border border-line bg-sand px-3 py-2 text-xs break-all text-graphite-500"
      >
        {link.url}
      </p>

      {erro && <p className="text-xs text-brand">{erro}</p>}

      <div className="flex flex-col gap-2 sm:flex-row">
        <Button type="button" variant="secondary" fullWidth onClick={copiar}>
          {copiado ? (
            <>
              <Check className="size-4" aria-hidden />
              Copiado
            </>
          ) : (
            <>
              <Copy className="size-4" aria-hidden />
              Copiar link
            </>
          )}
        </Button>
        <Button type="button" fullWidth onClick={compartilhar}>
          <Share2 className="size-4" aria-hidden />
          Compartilhar
        </Button>
      </div>

      <p className="text-xs text-graphite-300">
        {link.expires_at
          ? `O link expira em ${formatDateTime(link.expires_at)}.`
          : "Este link não tem prazo de expiração."}
        {link.view_count > 0 && ` Aberto ${link.view_count}×.`}
      </p>
    </div>
  );
}
