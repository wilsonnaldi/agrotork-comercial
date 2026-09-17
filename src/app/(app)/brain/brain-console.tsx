"use client";

import { useRef, useState, useTransition } from "react";
import { BookOpenCheck, Brain, Check, ChevronDown, Copy, FileSearch, MessageSquareQuote, SearchX, ShieldAlert, Sparkles } from "lucide-react";
import { Alert } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardBody } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/empty-state";
import { Textarea } from "@/components/ui/field";
import { askBrainAction } from "@/modules/brain/actions";
import type { BrainCitation, BrainNaturalAnswer } from "@/modules/brain/answer";
import type { KnowledgeEvidence } from "@/modules/brain/service";

/** Rótulos de nível de acesso. `internal` é o nível do vendedor. */
const NIVEL: Record<string, { texto: string; tom: "neutral" | "info" | "warning" | "danger" }> = {
  public: { texto: "Público", tom: "neutral" },
  internal: { texto: "Interno", tom: "info" },
  commercial: { texto: "Comercial", tom: "warning" },
  admin: { texto: "Administrativo", tom: "danger" },
};

const TIPO_DE_TRECHO: Record<string, string> = {
  text: "Texto",
  heading: "Título",
  list: "Lista",
  table: "Tabela",
  price_table: "Tabela de preços",
};

const EXEMPLOS = [
  "Qual a vazão da MJ981CAP a 40 psi?",
  "Pontas de cone vazio para fungicida",
  "Qual a faixa de operação do sensor 466113200?",
];

function CopiarTrecho({ texto }: { texto: string }) {
  const [copiado, setCopiado] = useState(false);
  return (
    <button
      type="button"
      onClick={() => {
        navigator.clipboard?.writeText(texto).then(
          () => {
            setCopiado(true);
            setTimeout(() => setCopiado(false), 1600);
          },
          () => undefined,
        );
      }}
      className="inline-flex h-9 items-center gap-1.5 rounded-lg px-2 text-xs font-medium text-graphite-500 transition-colors hover:bg-line/60 hover:text-graphite"
    >
      {copiado ? <Check className="size-3.5" aria-hidden /> : <Copy className="size-3.5" aria-hidden />}
      {copiado ? "Copiado" : "Copiar trecho"}
    </button>
  );
}

function CartaoDeEvidencia({ evidencia, numero }: { evidencia: KnowledgeEvidence; numero: number }) {
  const nivel = NIVEL[evidencia.accessLevel] ?? { texto: evidencia.accessLevel, tom: "neutral" as const };
  const paginas =
    evidencia.page.from === evidencia.page.to
      ? `p. ${evidencia.page.from}`
      : `p. ${evidencia.page.from}–${evidencia.page.to}`;

  return (
    <Card>
      <CardBody className="space-y-3">
        {/* Identificação: fonte, documento, versão, página. Nunca um id.
            O número é o mesmo da citação [n] — é o que liga um ao outro. */}
        <div className="flex flex-wrap items-center gap-x-2 gap-y-1 text-sm">
          <span className="flex size-6 shrink-0 items-center justify-center rounded bg-brand-soft text-xs font-medium text-brand-deep">
            {numero}
          </span>
          <span className="font-medium text-graphite">{evidencia.source}</span>
          <span className="text-graphite-300" aria-hidden>·</span>
          <span className="text-graphite-500">{evidencia.document.title}</span>
          <Badge tone="info">{evidencia.version.label}</Badge>
          <Badge>{paginas}</Badge>
          {evidencia.version.status !== "active" && <Badge tone="warning">Versão anterior</Badge>}
        </div>

        {evidencia.headingPath.length > 0 && (
          <p className="text-xs uppercase tracking-wide text-graphite-300">
            {evidencia.headingPath.join(" › ")}
          </p>
        )}

        <p className="whitespace-pre-wrap text-sm leading-relaxed text-graphite">{evidencia.content}</p>

        {evidencia.codes.length > 0 && (
          <div className="flex flex-wrap gap-1.5">
            {evidencia.codes.map((codigo) => (
              <span key={codigo} className="rounded bg-sand px-2 py-1 font-mono text-xs text-graphite-500">
                {codigo}
              </span>
            ))}
          </div>
        )}

        <div className="flex flex-wrap items-center justify-between gap-2 border-t border-line pt-3">
          <div className="min-w-0 space-y-1">
            <p className="text-xs text-graphite-300">Proveniência</p>
            <p className="text-xs text-graphite-500">{evidencia.citation}</p>
          </div>
          <div className="flex shrink-0 items-center gap-1">
            <Badge tone={nivel.tom}>{nivel.texto}</Badge>
            <Badge>{TIPO_DE_TRECHO[evidencia.kind] ?? evidencia.kind}</Badge>
            <CopiarTrecho texto={`${evidencia.content}\n\n— ${evidencia.citation}`} />
          </div>
        </div>

        {/* Só chega preenchido para admin: o service decide pelo papel. */}
        {evidencia.debug && (
          <details className="border-t border-line pt-3">
            <summary className="cursor-pointer text-xs font-medium text-graphite-500">
              Detalhes da busca
            </summary>
            <dl className="mt-2 grid grid-cols-2 gap-x-4 gap-y-1 font-mono text-xs text-graphite-500 sm:grid-cols-3">
              <div><dt className="inline text-graphite-300">chunk </dt><dd className="inline">{evidencia.debug.chunkId}</dd></div>
              <div><dt className="inline text-graphite-300">score </dt><dd className="inline">{evidencia.debug.score.toFixed(4)}</dd></div>
              <div><dt className="inline text-graphite-300">exato </dt><dd className="inline">{evidencia.debug.rankExact ?? "—"}</dd></div>
              <div><dt className="inline text-graphite-300">trgm </dt><dd className="inline">{evidencia.debug.rankTrgm ?? "—"}</dd></div>
              <div><dt className="inline text-graphite-300">fts </dt><dd className="inline">{evidencia.debug.rankFts ?? "—"}</dd></div>
              <div><dt className="inline text-graphite-300">fonte </dt><dd className="inline">{evidencia.debug.sourceKey}</dd></div>
            </dl>
          </details>
        )}
      </CardBody>
    </Card>
  );
}

/**
 * A resposta com as referências [n] clicáveis. Clicar rola até o card da
 * evidência e o destaca por um instante — a citação tem de levar a pessoa à
 * matéria-prima, senão é enfeite.
 */
function RespostaComCitacoes({
  texto,
  citacoes,
  aoClicar,
}: {
  texto: string;
  citacoes: BrainCitation[];
  aoClicar: (evidenceIndex: number) => void;
}) {
  const porIndice = new Map(citacoes.map((c) => [c.index, c]));
  const partes = texto.split(/(\[\d{1,3}\])/g);
  return (
    <p className="whitespace-pre-wrap text-base leading-relaxed text-graphite">
      {partes.map((parte, i) => {
        const m = /^\[(\d{1,3})\]$/.exec(parte);
        const citacao = m ? porIndice.get(Number(m[1])) : undefined;
        if (!citacao) return <span key={i}>{parte}</span>;
        return (
          <button
            key={i}
            type="button"
            onClick={() => aoClicar(citacao.evidenceIndex)}
            title={citacao.label}
            className="mx-0.5 inline-flex min-h-6 items-center rounded bg-brand-soft px-1.5 align-baseline text-xs font-medium text-brand-deep transition-colors hover:bg-brand hover:text-white"
          >
            {citacao.index}
          </button>
        );
      })}
    </p>
  );
}

/**
 * Uma ferramenta de consulta, não um painel. Campo, resposta, evidências.
 * Enter consulta; Shift+Enter quebra linha.
 *
 * A resposta natural NÃO substitui as evidências: elas continuam ali,
 * recolhidas, e a pessoa pode abrir a qualquer momento. Esconder a
 * matéria-prima atrás de um parágrafo bonito é exatamente o que este
 * projeto não quer.
 */
export function BrainConsole({ isAdmin }: { isAdmin: boolean }) {
  const [pergunta, setPergunta] = useState("");
  const [resposta, setResposta] = useState<BrainNaturalAnswer | null>(null);
  const [consultando, iniciar] = useTransition();
  const [evidenciasAbertas, setEvidenciasAbertas] = useState(false);
  const [destacada, setDestacada] = useState<number | null>(null);
  const campo = useRef<HTMLTextAreaElement>(null);

  function consultar(texto: string) {
    const limpa = texto.trim();
    if (limpa.length < 2 || consultando) return;
    setDestacada(null);
    iniciar(async () => {
      const { answer } = await askBrainAction({ query: limpa, limit: 10 });
      setResposta(answer);
      // Sem síntese, a evidência é a resposta: já abre.
      setEvidenciasAbertas(answer.mode !== "synthesized");
    });
  }

  function limpar() {
    setPergunta("");
    setResposta(null);
    setDestacada(null);
    campo.current?.focus();
  }

  function irParaEvidencia(indice: number) {
    setEvidenciasAbertas(true);
    setDestacada(indice);
    // O card só existe depois de a seção abrir.
    requestAnimationFrame(() => {
      document.getElementById(`evidencia-${indice}`)?.scrollIntoView({ behavior: "smooth", block: "center" });
    });
    setTimeout(() => setDestacada(null), 2400);
  }

  const recusado = resposta !== null && resposta.status !== "answered";
  const temEvidencia = (resposta?.evidence.length ?? 0) > 0;

  return (
    <div className="space-y-5">
      <Card>
        <CardBody className="space-y-3">
          <Textarea
            ref={campo}
            value={pergunta}
            onChange={(e) => setPergunta(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter" && !e.shiftKey) {
                e.preventDefault();
                consultar(pergunta);
              }
            }}
            placeholder="O que você precisa saber? Ex.: vazão da MJ981CAP a 40 psi"
            aria-label="Pergunta"
            maxLength={1000}
            className="min-h-28 text-base"
          />
          <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
            <p className="text-xs text-graphite-300">Enter consulta · Shift+Enter quebra linha</p>
            <div className="flex gap-2">
              {(pergunta || resposta) && (
                <Button type="button" variant="secondary" onClick={limpar} disabled={consultando}>
                  Limpar
                </Button>
              )}
              <Button
                type="button"
                onClick={() => consultar(pergunta)}
                disabled={consultando || pergunta.trim().length < 2}
                className="w-full sm:w-auto"
              >
                {consultando ? "Consultando…" : "Consultar"}
              </Button>
            </div>
          </div>
        </CardBody>
      </Card>

      {resposta === null && !consultando && (
        <Card>
          <EmptyState
            icon={Brain}
            title="A memória responde com documento na mão"
            description="Cada resposta vem com fonte, versão e página. Quando não houver evidência, o sistema diz que não sabe — não completa por conta própria."
          />
          <CardBody className="border-t border-line pt-4">
            <p className="mb-2 text-xs uppercase tracking-wide text-graphite-300">Exemplos</p>
            <div className="flex flex-wrap gap-2">
              {EXEMPLOS.map((exemplo) => (
                <button
                  key={exemplo}
                  type="button"
                  onClick={() => {
                    setPergunta(exemplo);
                    consultar(exemplo);
                  }}
                  className="rounded-full border border-line px-3 py-2 text-left text-xs text-graphite-500 transition-colors hover:bg-sand hover:text-graphite"
                >
                  {exemplo}
                </button>
              ))}
            </div>
          </CardBody>
        </Card>
      )}

      {consultando && (
        <Card>
          <CardBody className="space-y-2 text-sm text-graphite-500">
            <p className="flex items-center gap-3">
              <Sparkles className="size-4 animate-pulse text-brand" aria-hidden />
              Consultando documentos…
            </p>
            <p className="pl-7 text-xs text-graphite-300">Depois: analisando as evidências encontradas.</p>
          </CardBody>
        </Card>
      )}

      {!consultando && recusado && resposta && (
        <div className="space-y-3">
          <Alert tone={resposta.status === "error" ? "error" : "warning"} title={resposta.refusalReason}>
            {resposta.status === "no_evidence" && (
              <p>
                Nenhum documento vigente na memória sustenta essa resposta. O BRAIN não completa com
                conhecimento geral nem usa o cadastro do sistema como substituto.
              </p>
            )}
            {resposta.status === "forbidden" && (
              <p>Fale com a administração se precisar consultar a memória corporativa.</p>
            )}
            {resposta.status === "error" && <p>Tente de novo em instantes.</p>}
          </Alert>
          {resposta.status === "no_evidence" && !temEvidencia && (
            <Card>
              <EmptyState
                icon={SearchX}
                title="Sem evidência para esta pergunta"
                description="Talvez o documento ainda não tenha sido ingerido, ou a pergunta use um termo que não aparece nos documentos. Tente pelo código da peça."
              />
            </Card>
          )}
        </div>
      )}

      {!consultando && resposta?.status === "answered" && resposta.answer && (
        <Card className="border-brand/20">
          <CardBody className="space-y-3">
            <div className="flex flex-wrap items-center gap-2">
              <MessageSquareQuote className="size-4 text-brand" aria-hidden />
              <h2 className="font-display text-sm uppercase tracking-wide">Resposta do BRAIN</h2>
              {resposta.mode === "extractive" && <Badge tone="warning">Sem síntese automática</Badge>}
            </div>

            <RespostaComCitacoes
              texto={resposta.answer}
              citacoes={resposta.citations ?? []}
              aoClicar={irParaEvidencia}
            />

            {resposta.warning && (
              <p className="flex items-start gap-2 text-xs text-graphite-500">
                <ShieldAlert className="mt-0.5 size-3.5 shrink-0 text-amber-600" aria-hidden />
                {resposta.warning}
              </p>
            )}

            {(resposta.citations?.length ?? 0) > 0 && (
              <div className="space-y-1 border-t border-line pt-3">
                <p className="text-xs uppercase tracking-wide text-graphite-300">Fontes utilizadas</p>
                <ol className="space-y-1">
                  {resposta.citations?.map((c) => (
                    <li key={c.index} className="text-xs text-graphite-500">
                      <button
                        type="button"
                        onClick={() => irParaEvidencia(c.evidenceIndex)}
                        className="text-left hover:text-graphite hover:underline"
                      >
                        [{c.index}] {c.label}
                      </button>
                    </li>
                  ))}
                </ol>
              </div>
            )}

            <p className="border-t border-line pt-3 text-xs text-graphite-300">
              Resposta baseada em {resposta.citations?.length ?? 0}{" "}
              {(resposta.citations?.length ?? 0) === 1 ? "evidência" : "evidências"}. Confira no
              documento citado antes de usar com o cliente.
            </p>
          </CardBody>
        </Card>
      )}

      {!consultando && temEvidencia && resposta && (
        <section className="space-y-3">
          <button
            type="button"
            onClick={() => setEvidenciasAbertas((v) => !v)}
            aria-expanded={evidenciasAbertas}
            className="flex w-full items-center gap-2 rounded-lg border border-line bg-white px-4 py-3 text-left text-sm text-graphite-500 transition-colors hover:bg-sand"
          >
            <BookOpenCheck className="size-4 shrink-0 text-brand" aria-hidden />
            <span className="min-w-0 flex-1">
              {evidenciasAbertas ? "Ocultar evidências" : "Ver evidências"} · {resposta.evidence.length}{" "}
              {resposta.evidence.length === 1 ? "trecho" : "trechos"}
            </span>
            <ChevronDown
              className={`size-4 shrink-0 transition-transform ${evidenciasAbertas ? "rotate-180" : ""}`}
              aria-hidden
            />
          </button>

          {evidenciasAbertas && (
            <>
              {resposta.evidence.map((evidencia, i) => (
                <div
                  key={evidencia.chunkId}
                  id={`evidencia-${i}`}
                  className={`rounded-card transition-shadow ${destacada === i ? "ring-2 ring-brand ring-offset-2" : ""}`}
                >
                  <CartaoDeEvidencia evidencia={evidencia} numero={i + 1} />
                </div>
              ))}
              <p className="flex items-start gap-2 pt-1 text-xs text-graphite-300">
                <FileSearch className="mt-0.5 size-3.5 shrink-0" aria-hidden />
                Estes são os trechos recuperados, sem interpretação.
                {isAdmin && " Os detalhes da busca estão em cada card."}
              </p>
            </>
          )}
        </section>
      )}
    </div>
  );
}
