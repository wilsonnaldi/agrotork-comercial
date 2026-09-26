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
import { ERRO_CONSULTA } from "@/modules/brain/evidence";
import {
  codigoConsultado,
  ehTabular,
  estadoDaResposta,
  formatarSetas,
  NIVEL_DE_ACESSO,
  parseAnswer,
  ROTULO_DO_ESTADO,
  rotuloDeFontes,
  rotuloDeTrechos,
  TIPO_DE_TRECHO,
} from "@/modules/brain/presentation";
import type { KnowledgeEvidence } from "@/modules/brain/service";

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
  const nivel = NIVEL_DE_ACESSO[evidencia.accessLevel] ?? { texto: evidencia.accessLevel, tom: "neutral" as const };
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

        {ehTabular(evidencia.kind) ? (
          // Linha de tabela é longa por natureza: rola na horizontal dentro do
          // card, em vez de esticar a página no celular.
          <div className="-mx-1 overflow-x-auto px-1">
            <pre className="w-max min-w-full font-sans text-sm leading-relaxed whitespace-pre text-graphite">
              {evidencia.content}
            </pre>
          </div>
        ) : (
          <p className="text-sm leading-relaxed break-words whitespace-pre-wrap text-graphite">
            {evidencia.content}
          </p>
        )}

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
function LinhaComCitacoes({
  texto,
  citacoes,
  aoClicar,
}: {
  texto: string;
  citacoes: BrainCitation[];
  aoClicar: (evidenceIndex: number) => void;
}) {
  const porIndice = new Map(citacoes.map((c) => [c.index, c]));
  const partes = formatarSetas(texto).split(/(\[\d{1,3}\])/g);
  return (
    <>
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
            aria-label={`Evidência ${citacao.index}: ${citacao.label}`}
            className="inline-flex min-h-5 items-center rounded bg-brand-soft px-1 align-baseline text-[0.7rem] leading-none font-medium text-brand-deep transition-colors hover:bg-brand hover:text-white focus-visible:ring-2 focus-visible:ring-brand focus-visible:ring-offset-1 focus-visible:outline-none"
          >
            {citacao.index}
          </button>
        );
      })}
    </>
  );
}

/**
 * A resposta na tela. O texto validado NÃO é reescrito: `parseAnswer` só
 * decide o que é abertura, o que é item de lista e o que é parágrafo, e
 * todos os marcadores [n] continuam onde o modelo os escreveu — menores e
 * mais discretos, porque repetidos em cada linha eles cansam, mas presentes,
 * porque são o lastro.
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
  const blocos = parseAnswer(texto);
  const itens = blocos.filter((b) => b.tipo === "item");
  const linha = (t: string) => <LinhaComCitacoes texto={t} citacoes={citacoes} aoClicar={aoClicar} />;

  if (itens.length === 0) {
    return (
      <div className="space-y-2 text-base leading-relaxed text-graphite">
        {blocos.map((b, i) => (
          <p key={i} className="break-words">{linha(b.texto)}</p>
        ))}
      </div>
    );
  }

  // Com lista, a leitura melhora agrupando: abertura, itens, e o que vier
  // depois. A ordem dos blocos é a da resposta, sempre.
  const elementos: React.ReactNode[] = [];
  let acumulados: { tipo: string; texto: string }[] = [];
  const despejarItens = (chave: number) => {
    if (acumulados.length === 0) return;
    elementos.push(
      <ul key={`ul-${chave}`} className="space-y-1.5">
        {acumulados.map((item, i) => (
          <li key={i} className="flex gap-2 break-words">
            <span className="mt-2 size-1.5 shrink-0 rounded-full bg-brand/70" aria-hidden />
            <span className="min-w-0">{linha(item.texto)}</span>
          </li>
        ))}
      </ul>,
    );
    acumulados = [];
  };

  blocos.forEach((b, i) => {
    if (b.tipo === "item") {
      acumulados.push(b);
      return;
    }
    despejarItens(i);
    elementos.push(
      <p key={i} className={b.tipo === "lead" ? "font-medium break-words" : "break-words"}>
        {linha(b.texto)}
      </p>,
    );
  });
  despejarItens(blocos.length);

  return <div className="space-y-3 text-base leading-relaxed text-graphite">{elementos}</div>;
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
      let answer: BrainNaturalAnswer;
      try {
        ({ answer } = await askBrainAction({ query: limpa, limit: 10 }));
      } catch {
        // A action já devolve recusa em vez de lançar; o que chega aqui é
        // falha de transporte (rede, deploy trocado no meio). Sem este catch
        // a tela ficava presa sem resposta. Mesmo estado de erro da action,
        // com a mesma frase genérica.
        answer = { query: limpa, status: "error", evidence: [], refusalReason: ERRO_CONSULTA, mode: "none" };
      }
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
  const estado = resposta ? estadoDaResposta(resposta.status, resposta.mode) : null;
  const codigo = resposta ? codigoConsultado(resposta.query) : null;
  const citacoes = resposta?.citations ?? [];

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
              <>
                <p>
                  Nenhum documento vigente na memória sustenta essa resposta. O BRAIN não completa com
                  conhecimento geral nem usa o cadastro do sistema como substituto.
                </p>
                {codigo && (
                  <p className="pt-1">
                    Código consultado: <span className="font-mono font-medium">{codigo}</span>
                  </p>
                )}
              </>
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
        <Card className={estado === "extractive" ? "border-amber-200" : "border-brand/20"}>
          <CardBody className="space-y-3" aria-live="polite">
            <div className="flex flex-wrap items-center gap-2">
              {estado === "extractive" ? (
                <ShieldAlert className="size-4 text-amber-600" aria-hidden />
              ) : (
                <MessageSquareQuote className="size-4 text-brand" aria-hidden />
              )}
              <h2 className="font-display text-sm tracking-wide uppercase">
                {ROTULO_DO_ESTADO[estado ?? "synthesized"]}
              </h2>
              {/* Comparação: o selo diz que a PERGUNTA compara códigos. Vale
                  também na resposta extractiva (gate externo, sem provedor,
                  erro), porque sai do texto da pergunta, não da evidência. */}
              {resposta.comparison && <Badge tone="info">Comparação</Badge>}
            </div>

            {/* Sem síntese, o texto do sistema não é resposta: é moldura. A
                razão do bloqueio fica em primeiro plano e a evidência, que é
                a resposta de verdade, abre logo abaixo. */}
            {estado === "extractive" ? (
              <div className="space-y-3">
                {resposta.warning && (
                  <p className="text-base leading-relaxed text-graphite">{resposta.warning}</p>
                )}
                <p className="text-sm text-graphite-500">
                  Os trechos encontrados estão abaixo, na íntegra e sem interpretação.
                </p>
              </div>
            ) : (
              <>
                <RespostaComCitacoes
                  texto={resposta.answer}
                  citacoes={citacoes}
                  aoClicar={irParaEvidencia}
                />
                {resposta.warning && (
                  <p className="flex items-start gap-2 text-xs text-graphite-500">
                    <ShieldAlert className="mt-0.5 size-3.5 shrink-0 text-amber-600" aria-hidden />
                    {resposta.warning}
                  </p>
                )}
              </>
            )}

            {citacoes.length > 0 && (
              <div className="space-y-1.5 border-t border-line pt-3">
                <p className="text-xs tracking-wide text-graphite-300 uppercase">
                  {rotuloDeFontes(citacoes.length)}
                </p>
                <ul className="space-y-1">
                  {citacoes.map((c) => (
                    <li key={c.index} className="text-xs text-graphite-500">
                      <button
                        type="button"
                        onClick={() => irParaEvidencia(c.evidenceIndex)}
                        aria-label={`Ver a evidência ${c.index}: ${c.label}`}
                        className="flex gap-2 rounded text-left hover:text-graphite hover:underline focus-visible:ring-2 focus-visible:ring-brand focus-visible:outline-none"
                      >
                        <span className="shrink-0 font-medium text-graphite-500">[{c.index}]</span>
                        <span className="min-w-0 break-words">{c.label}</span>
                      </button>
                    </li>
                  ))}
                </ul>
              </div>
            )}

            <p className="border-t border-line pt-3 text-xs text-graphite-300">
              {estado === "extractive"
                ? `${rotuloDeTrechos(resposta.evidence.length)} na documentação, sem síntese automática.`
                : `Resposta baseada em ${citacoes.length} ${citacoes.length === 1 ? "evidência" : "evidências"}.`}{" "}
              Confira no documento citado antes de usar com o cliente.
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
            aria-controls="brain-evidencias"
            className="flex w-full items-center gap-2 rounded-lg border border-line bg-white px-4 py-3 text-left text-sm text-graphite-500 transition-colors hover:bg-sand focus-visible:ring-2 focus-visible:ring-brand focus-visible:ring-offset-2 focus-visible:outline-none"
          >
            <BookOpenCheck className="size-4 shrink-0 text-brand" aria-hidden />
            <span className="min-w-0 flex-1">
              {evidenciasAbertas ? "Ocultar evidências" : "Ver evidências"} ·{" "}
              {rotuloDeTrechos(resposta.evidence.length)}
            </span>
            <ChevronDown
              className={`size-4 shrink-0 transition-transform ${evidenciasAbertas ? "rotate-180" : ""}`}
              aria-hidden
            />
          </button>

          {evidenciasAbertas && (
            <div id="brain-evidencias" className="space-y-3">
              {resposta.evidence.map((evidencia, i) => (
                <div
                  key={evidencia.chunkId}
                  id={`evidencia-${i}`}
                  className={`rounded-card transition-shadow ${destacada === i ? "ring-2 ring-brand ring-offset-2" : ""}`}
                >
                  <CartaoDeEvidencia evidencia={evidencia} numero={i + 1} />
                </div>
              ))}
              {/* Fora do card, o fundo é areia: graphite-300 ali fica em 4,16:1,
                  abaixo do mínimo AA. graphite-500 passa com folga. */}
              <p className="flex items-start gap-2 pt-1 text-xs text-graphite-500">
                <FileSearch className="mt-0.5 size-3.5 shrink-0" aria-hidden />
                Estes são os trechos recuperados, sem interpretação.
                {isAdmin && " Os detalhes da busca estão em cada card."}
              </p>
            </div>
          )}
        </section>
      )}
    </div>
  );
}
