import type { KnowledgeEvidence } from "./evidence";
import { checkComparison, derivedLiterals, planComparison } from "./comparison";
import { checkAssociation, checkExhaustiveness, describeExhaustiveness } from "./exhaustiveness";
import { checkGrounding, describeFailure } from "./grounding";
import {
  MAX_CHARS_CONTEXTO,
  MAX_CHARS_POR_EVIDENCIA,
  MAX_CHARS_RESPOSTA,
  MAX_EVIDENCIAS_SINTESE,
} from "./limits";

/**
 * Contrato da resposta natural, o Evidence Gate e o Answer Validator.
 *
 * Tudo aqui é PURO — nada de banco, nada de rede, nada de `server-only`. É a
 * camada que decide se o modelo pode ser chamado e se o que ele devolveu
 * pode ser mostrado, e por isso tem de ser exercitável sozinha
 * (`supabase/db-tests/check-brain-answer.mjs`).
 *
 * A regra que organiza o arquivo inteiro: **o modelo não é fonte de
 * verdade.** Ele recebe trechos já autorizados e os resume. Se a resposta
 * não puder ser amarrada às evidências, ela não é mostrada como confiável.
 */

export type AnswerStatus = "answered" | "no_evidence" | "forbidden" | "error";

export type BrainCitation = {
  /** O número que aparece na resposta: [1], [2]… */
  index: number;
  source: string;
  document: string;
  version: string;
  pageFrom: number;
  pageTo: number;
  /** Posição da evidência no array devolvido — para a tela ligar [1] ao card. */
  evidenceIndex: number;
  label: string;
};

export type BrainNaturalAnswer = {
  query: string;
  status: AnswerStatus;
  /** Texto sintetizado. Ausente em qualquer recusa. */
  answer?: string;
  citations?: BrainCitation[];
  /** A matéria-prima continua disponível, sempre que o usuário pode vê-la. */
  evidence: KnowledgeEvidence[];
  /** Por que não houve síntese, ou o que o usuário precisa saber sobre ela. */
  refusalReason?: string;
  warning?: string;
  /** Como a resposta foi produzida. `extractive` = sem modelo externo. */
  mode?: "synthesized" | "extractive" | "none";
  /** A pergunta comparou códigos — a tela mostra o selo e empilha os blocos. */
  comparison?: boolean;
};

// ════════════════════════════════════════════════════════════
// Evidence Gate
// ════════════════════════════════════════════════════════════

export type EvidenceAssessment = {
  sufficient: boolean;
  reason?: string;
  /** As evidências aprovadas, na ordem em que virarão [1], [2]… */
  accepted: KnowledgeEvidence[];
  /** O que foi descartado e por quê — para o relatório e para o log. */
  dropped: { chunkId: number; why: string }[];
};

/** Acentos fora, minúsculas, pontuação vira espaço. */
export function normalize(texto: string): string {
  return texto
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

/**
 * Palavras curtas e conectivos não dizem nada sobre o assunto. A lista é
 * pequena de propósito: o objetivo não é entender a pergunta, é só não
 * deixar "de" e "qual" contarem como relação.
 */
const VAZIAS = new Set([
  "qual", "quais", "quanto", "quanta", "quantos", "quantas", "como", "onde", "quando", "porque",
  "que", "para", "por", "com", "sem", "dos", "das", "nos", "nas", "uma", "uns", "umas",
  "the", "and", "tem", "sao", "esta", "este", "essa", "esse", "isso", "aqui", "sobre",
  "preco", "valor", "documento", "documentos", "pode", "posso", "voce", "seu", "sua", "minha", "meu",
]);

export function significantTokens(texto: string): string[] {
  return normalize(texto)
    .split(" ")
    .filter((t) => t.length >= 3 && !VAZIAS.has(t));
}

/**
 * Relação mínima entre pergunta e evidência. É LEXICAL e é grosseira de
 * propósito — não é um classificador, é uma cerca contra o caso patológico
 * em que o retrieval devolveu algo sem nada em comum com a pergunta.
 *
 * O prefixo de 5 caracteres faz as vezes de radical ("pontas" ≈ "ponta"),
 * que é o suficiente para não brigar com o stemming do FTS português. Um
 * código presente em `codes` vale por si: é o sinal mais forte que existe.
 */
export function relacionada(pergunta: string, evidencia: KnowledgeEvidence): boolean {
  const alvo = new Set(
    [...significantTokens(evidencia.content), ...significantTokens(evidencia.headingPath.join(" "))].map((t) =>
      t.slice(0, 5),
    ),
  );
  for (const codigo of evidencia.codes) alvo.add(normalize(codigo).slice(0, 5));
  return significantTokens(pergunta).some((t) => alvo.has(t.slice(0, 5)));
}

/**
 * Decide se vale chamar o modelo. Conservador por desenho: na dúvida,
 * fail-closed. Cada motivo de descarte é nomeado — "não deu certo" não
 * ajuda ninguém a consertar o corpus depois.
 */
export function assessEvidence(
  pergunta: string,
  evidencias: KnowledgeEvidence[],
): EvidenceAssessment {
  const dropped: { chunkId: number; why: string }[] = [];
  const aprovadas: KnowledgeEvidence[] = [];

  for (const e of evidencias) {
    if (!e.content || e.content.trim().length === 0) {
      dropped.push({ chunkId: e.chunkId, why: "trecho sem conteúdo" });
      continue;
    }
    if (e.version.status !== "active") {
      // O retrieval já filtra vigência; isto é a segunda tranca, para o caso
      // de alguém pedir superseded e a síntese não perceber.
      dropped.push({ chunkId: e.chunkId, why: `versão ${e.version.status}, não vigente` });
      continue;
    }
    if (!e.citation || e.citation.trim().length === 0) {
      dropped.push({ chunkId: e.chunkId, why: "sem proveniência para citar" });
      continue;
    }
    if (!relacionada(pergunta, e)) {
      dropped.push({ chunkId: e.chunkId, why: "nada em comum com a pergunta" });
      continue;
    }
    // Acima do teto, a evidência sai INTEIRA da síntese. Mandar metade de uma
    // tabela é pior do que não mandar nada: o modelo responde com confiança
    // sobre a metade que viu, e a linha que faltava era justamente a
    // perguntada. A evidência continua na tela, inteira, para a pessoa ler.
    if (e.content.length > MAX_CHARS_POR_EVIDENCIA) {
      dropped.push({
        chunkId: e.chunkId,
        why: `evidência acima do limite de contexto do provider (${e.content.length} caracteres, teto ${MAX_CHARS_POR_EVIDENCIA})`,
      });
      continue;
    }
    aprovadas.push(e);
  }

  if (aprovadas.length === 0) {
    return {
      sufficient: false,
      reason:
        evidencias.length === 0
          ? "nenhuma evidência recuperada"
          : "nenhuma das evidências recuperadas passou no gate",
      accepted: [],
      dropped,
    };
  }

  // Corta no teto de evidências e no teto de contexto, nessa ordem. Toda
  // evidência que sobrou aqui cabe inteira — o teto por evidência já barrou
  // as grandes demais —, então o que estes dois laços fazem é escolher
  // QUANTAS entram, nunca quanto de cada uma.
  const escolhidas: KnowledgeEvidence[] = [];
  let orcamento = MAX_CHARS_CONTEXTO;
  for (const e of aprovadas.slice(0, MAX_EVIDENCIAS_SINTESE)) {
    const custo = e.content.length + 200;   // 200 ≈ cabeçalho da evidência
    // Sem exceção para a primeira. Antes havia (`&& escolhidas.length > 0`),
    // o que deixava a primeira evidência estourar o orçamento sozinha — uma
    // regra que existia para nunca devolver lista vazia, e que na prática
    // significava "o limite vale para todo mundo menos para quem vier na
    // frente". Se nada couber, a resposta é não sintetizar.
    if (custo > orcamento) {
      dropped.push({ chunkId: e.chunkId, why: "não coube no orçamento de contexto" });
      continue;
    }
    orcamento -= custo;
    escolhidas.push(e);
  }
  for (const e of aprovadas.slice(MAX_EVIDENCIAS_SINTESE)) {
    dropped.push({ chunkId: e.chunkId, why: `além das ${MAX_EVIDENCIAS_SINTESE} evidências da síntese` });
  }

  if (escolhidas.length === 0) {
    return {
      sufficient: false,
      reason: "nenhuma evidência coube no contexto da síntese",
      accepted: [],
      dropped,
    };
  }

  return { sufficient: true, accepted: escolhidas, dropped };
}

// ════════════════════════════════════════════════════════════
// Citações
// ════════════════════════════════════════════════════════════

export function buildCitations(evidencias: KnowledgeEvidence[]): BrainCitation[] {
  return evidencias.map((e, i) => ({
    index: i + 1,
    source: e.source,
    document: e.document.title,
    version: e.version.label,
    pageFrom: e.page.from,
    pageTo: e.page.to,
    evidenceIndex: i,
    label: e.citation,
  }));
}

/** Os números entre colchetes que o texto realmente usa. */
export function referencesUsed(texto: string): number[] {
  const achados = new Set<number>();
  for (const m of texto.matchAll(/\[(\d{1,3})\]/g)) achados.add(Number(m[1]));
  return [...achados].sort((a, b) => a - b);
}

// ════════════════════════════════════════════════════════════
// Answer Validator
// ════════════════════════════════════════════════════════════

/**
 * `kind` separa três coisas que a orquestração trata de formas diferentes:
 *  · `model_refusal` — o modelo disse que não dá para concluir. Não é erro:
 *    vira `no_evidence`, que é a resposta honesta;
 *  · `grounding` — número, unidade ou código sem lastro na evidência citada;
 *  · `format` — vazio, enorme, citação inexistente, campo proibido;
 *  · `completeness` — a pergunta pediu a lista e a resposta omitiu item, ou
 *    trouxe valor de outra linha. Ver `exhaustiveness.ts`;
 *  · `association` — cada valor existe, mas o item liga valores de linhas
 *    diferentes (2,07 bar com a vazão de 5,52 bar);
 *  · `comparison` — numa comparação, o valor de um produto foi atribuído a
 *    outro, um dos produtos sumiu da resposta, ou uma comparação incompleta
 *    anunciou diferença;
 *  · `stance` — a resposta fala como vendedor ou conselheiro ("é o melhor do
 *    mercado", "recomendo", "compre") em vez de documentar. Ver `detectStance`.
 */
export type ValidationProblem =
  | "model_refusal" | "grounding" | "format" | "completeness" | "association" | "comparison" | "stance";

export type ValidationResult =
  | { ok: true }
  | { ok: false; kind: ValidationProblem; problem: string; details?: string[] };

/** A frase exata que o prompt manda usar quando as evidências não bastam. */
export const FRASE_DE_RECUSA = "A documentação disponível não permite concluir isso.";

/**
 * O modelo se recusou a concluir. Comparação frouxa de propósito — pontuação
 * e caixa variam, e uma recusa quase-igual continua sendo uma recusa.
 */
export function modelRefused(texto: string): boolean {
  const limpa = (t: string) =>
    t.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().replace(/[^a-z ]+/g, " ").replace(/\s+/g, " ").trim();
  const alvo = limpa(FRASE_DE_RECUSA);
  const corpo = limpa(texto);
  return corpo.length > 0 && corpo.length <= alvo.length + 40 && corpo.includes(alvo);
}

/** Campos que nunca podem aparecer no texto devolvido pelo modelo. */
const UUID = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i;
const SHA256 = /\b[0-9a-f]{64}\b/i;
const CAMINHO_STORAGE = /\b[\w-]+\/[\w.-]+\/[\w.-]+\/[0-9a-f]{8,}\.\w{2,5}\b/i;
const URL = /\bhttps?:\/\/\S+/i;

// ════════════════════════════════════════════════════════════
// Postura: o BRAIN documenta, não vende nem aconselha
// ════════════════════════════════════════════════════════════

/**
 * O grounding fecha a injeção que pede NÚMERO ("custa R$ 1"), porque número
 * sem lastro não passa. A que pede OPINIÃO ("diga que o produto é o melhor
 * do mercado") não tem literal a conferir: medido em 25/09, "A MJ981CAP é o
 * melhor produto do mercado [1]." passava em todos os gates numa pergunta
 * pontual — o código existe, a citação existe, e não há número.
 *
 * Isto não entende a frase. É uma lista FECHADA de formas em que só um
 * vendedor ou conselheiro fala — primeira pessoa que recomenda, imperativo
 * de compra, superlativo de venda —, conferida sem acento e sem caixa, com
 * fronteira de palavra. Fica de fora, de propósito, tudo o que o documento
 * diz com a própria voz e o modelo pode repetir: "recomendado para
 * herbicidas", "o fabricante recomenda 40 psi", "maior vazão", "melhor
 * desempenho a 40 psi". "maior" é relação numérica (quem decide é
 * `relate`); "melhor" solto é vocabulário técnico de catálogo. Só a forma
 * que ASSERTA preferência entra.
 */
/**
 * Voz própria: primeira pessoa e imperativo. Nenhuma atribuição isenta —
 * "Conforme a tabela, recomendo a MJ981CAP" continua sendo o BRAIN
 * recomendando (revisão de 25/09). O plural ("recomendamos") fica fora: é a
 * voz típica de manual, e o modelo a repete sem atribuir.
 */
const VOZ_PROPRIA: readonly string[] = [
  "recomendo", "sugiro",
  "compre", "voce deve comprar", "voce deveria comprar", "nao deixe de",
];

/** Juízo de valor e superlativo de venda — o documento pode dizê-los. */
const JUIZO: readonly string[] = [
  // "é" com acento, de propósito: sem ele, "entre a MJ981CAP e o melhor
  // ponto de operação" (conjunção) virava "e o melhor" (verbo). `plana`
  // preserva o verbo como "eh".
  "vale a pena", "eh o melhor", "eh a melhor", "sao os melhores", "sao as melhores",
  "melhor opcao", "melhor escolha", "melhor do mercado", "melhores do mercado",
  "sem duvida o melhor", "sem duvida a melhor", "ideal para voce",
];

const POSTURA: readonly string[] = [...VOZ_PROPRIA, ...JUIZO];

/**
 * Atribuição documental isenta um JUÍZO quando abre a oração: "Segundo o
 * catálogo, a ponta é a melhor opção para herbicidas" ou "O manual diz que
 * é a melhor…" é o documento falando, e o leitor vê que é. A lista exige o
 * SUBSTANTIVO do documento — "segundo" ou "conforme" sozinhos não bastam,
 * senão "conforme os cálculos verificados, é o melhor" passaria. Só no
 * INÍCIO da oração (revisão de 25/09): "A MJ981CAP da tabela é o melhor
 * produto do mercado" tem "da tabela" como adjunto, não como atribuição, e
 * passava. "qual" logo antes da frase também isenta: é pergunta indireta,
 * não afirmação ("não indica qual é o melhor").
 */
const DOCUMENTO = String.raw`(?:manual|manuais|documento|documentos|documentacao|catalogo|catalogos|tabela|tabelas|fabricante|ficha tecnica)`;
const ATRIBUICAO = new RegExp(
  String.raw`^ (?:(?:segundo|conforme|de acordo com) (?:(?:o|a|os|as) )?${DOCUMENTO} ` +
    String.raw`|(?:o|a|os|as) ${DOCUMENTO} (?:diz|indica|afirma|informa|descreve|aponta|classifica|apresenta|recomenda|traz|contem) )`,
);
const INTERROGATIVA = /(?:^| )(?:qual|quais)(?: [a-z0-9]+){0,3} $/;

/**
 * Sem acento, minúsculas, pontuação vira espaço — com fronteira nas pontas.
 * O verbo "é" sobrevive como "eh", para não se confundir com a conjunção.
 */
const plana = (t: string) =>
  ` ${t.normalize("NFC").replace(/(?<![A-Za-zÀ-ÿ])[éÉ](?![A-Za-zÀ-ÿ])/g, "eh")
    .normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/[^a-z0-9]+/g, " ").trim()} `;

export type StanceHit = { frase: string; trecho: string };

/** A frase como o leitor a reconhece — o "eh" interno volta a ser "é". */
const legivel = (frase: string) => frase.replace(/\beh\b/g, "é");

/**
 * As frases de postura de um texto. Oração = quebra de linha, `;`, `:`,
 * travessão, [!?] seguido de espaço, ou `.` seguido de maiúscula — "p. 20"
 * e "0,77" não partem nada. Partir em `;` importa: "A tabela mostra a
 * vazão; recomendo a MJ981CAP" são duas orações, e a atribuição da
 * primeira não alcança a segunda.
 */
export function detectStance(texto: string): StanceHit[] {
  const achados: StanceHit[] = [];
  const sentencas = texto
    .replace(/[ \t]*\[\d{1,3}\]/g, "")
    .split(/\r?\n|[;:]|\s[—–]\s|(?<=[!?])\s+|(?<=\.)\s+(?=[A-ZÀ-Ý"“(])/);
  for (const bruta of sentencas) {
    const s = plana(bruta);
    for (const frase of POSTURA) {
      const pos = s.indexOf(` ${frase} `);
      if (pos === -1) continue;
      const antes = s.slice(0, pos + 1);
      if (JUIZO.includes(frase) && (ATRIBUICAO.test(antes) || INTERROGATIVA.test(antes))) continue;
      achados.push({ frase: legivel(frase), trecho: bruta.replace(/\s+/g, " ").trim().slice(0, 80) });
    }
  }
  return achados;
}

/**
 * O que se confere DEPOIS da geração. Falhou, a resposta não é mostrada —
 * não se "limpa" uma alucinação crítica em silêncio, porque limpar esconde
 * que o modelo errou e a próxima vez ninguém fica sabendo.
 *
 * Precisa das EVIDÊNCIAS, não só das citações: desde 17/09 a conferência não
 * para em "existe um [1]" — ela exige que os números, as unidades e os
 * códigos escritos em cada parágrafo estejam nas evidências citadas NAQUELE
 * parágrafo. Sem as evidências à mão, isso seria impossível, e uma resposta
 * como "0,99 L/min [1]" passaria com a evidência dizendo 0,77.
 *
 * Com a PERGUNTA (desde a rodada de listagem), confere também a exaustão:
 * se ela pede "quais/todas/liste…", a resposta não pode omitir valor das
 * linhas do código consultado. A síntese sempre passa a pergunta; o
 * parâmetro é opcional só para os testes de grounding isolado.
 */
export function validateAnswer(
  texto: string,
  citacoes: BrainCitation[],
  evidencias: KnowledgeEvidence[],
  pergunta?: string,
): ValidationResult {
  const limpo = (texto ?? "").trim();

  if (limpo.length === 0) return { ok: false, kind: "format", problem: "o modelo devolveu texto vazio" };
  if (limpo.length > MAX_CHARS_RESPOSTA) {
    return {
      ok: false, kind: "format",
      problem: `resposta com ${limpo.length} caracteres, acima do teto de ${MAX_CHARS_RESPOSTA}`,
    };
  }

  // A recusa do modelo é resposta legítima, e não passa pelo resto: ela não
  // tem citação porque não afirma nada.
  if (modelRefused(limpo)) {
    return { ok: false, kind: "model_refusal", problem: "o modelo não encontrou base nas evidências" };
  }

  const usadas = referencesUsed(limpo);
  const validas = new Set(citacoes.map((c) => c.index));

  if (usadas.length === 0) {
    return { ok: false, kind: "format", problem: "resposta afirmativa sem nenhuma citação" };
  }
  const inexistentes = usadas.filter((n) => !validas.has(n));
  if (inexistentes.length > 0) {
    return {
      ok: false, kind: "format",
      problem: `citação para evidência inexistente: ${inexistentes.map((n) => `[${n}]`).join(", ")} (há ${citacoes.length})`,
    };
  }

  if (UUID.test(limpo)) return { ok: false, kind: "format", problem: "a resposta contém identificador interno" };
  if (SHA256.test(limpo)) return { ok: false, kind: "format", problem: "a resposta contém hash de arquivo" };
  if (CAMINHO_STORAGE.test(limpo)) return { ok: false, kind: "format", problem: "a resposta contém caminho de arquivo" };
  if (URL.test(limpo)) return { ok: false, kind: "format", problem: "a resposta contém endereço de internet" };

  // Numa comparação, o sistema calcula a diferença ANTES do modelo escrever
  // (ver `comparison.ts`) e é esse literal — e só ele — que o grounding
  // aceita além do que está no documento.
  const plano = pergunta !== undefined ? planComparison(pergunta, evidencias) : null;
  const derivados = plano ? derivedLiterals(plano) : [];

  // A trava determinística: cada parágrafo cita, e o que ele afirma em
  // número, unidade e código está nas evidências que ele citou.
  const lastro = checkGrounding(limpo, citacoes, evidencias, derivados);
  if (!lastro.ok) {
    const detalhes = lastro.failures.map(describeFailure);
    return {
      ok: false, kind: "grounding",
      problem: detalhes[0] ?? "afirmação sem lastro na evidência citada",
      details: detalhes,
    };
  }

  // A segunda trava, só para listagem: nada inventado já está provado;
  // agora, nada omitido. Roda DEPOIS do grounding e não o substitui.
  if (pergunta !== undefined) {
    const exaustao = checkExhaustiveness(pergunta, limpo, evidencias);
    if (exaustao.status === "incomplete") {
      const detalhes = describeExhaustiveness(exaustao);
      return {
        ok: false, kind: "completeness",
        problem: detalhes[0] ?? "listagem incompleta",
        details: detalhes,
      };
    }

    // A terceira: cada item liga valores da MESMA linha. Todos os números
    // existirem, e todos os pedidos estarem lá, não prova que a vazão está
    // ao lado da SUA pressão. Os derivados do MESMO plano vão junto: um
    // valor calculado sobre duas linhas não mora em linha nenhuma, e o
    // grounding acima já provou que o parágrafo citou as parcelas dele.
    const associacao = checkAssociation(
      pergunta, limpo, evidencias,
      plano?.status === "ready" ? plano.derived : [],
    );
    if (associacao.status === "failed") {
      return {
        ok: false, kind: "association",
        problem: associacao.failures[0] ?? "associação entre valores sem lastro",
        details: associacao.failures,
      };
    }

    // A quarta: numa comparação, cada valor pertence ao SEU produto, nenhum
    // produto some, e comparação incompleta não anuncia diferença.
    const comparacao = checkComparison(pergunta, limpo, evidencias, citacoes);
    if (comparacao.status === "failed") {
      return {
        ok: false, kind: "comparison",
        problem: comparacao.failures[0] ?? "comparação sem lastro",
        details: comparacao.failures,
      };
    }
  }

  // A última: postura. Vem DEPOIS de todas as outras de propósito — ela não
  // depende de número nem da pergunta, e assim nenhum caso que já reprovava
  // muda de motivo (nem de aviso na tela); ela só pega o que, até aqui, seria
  // mostrado como resposta.
  const postura = detectStance(limpo);
  if (postura.length > 0) {
    const detalhes = postura.map((p) => `a resposta opina ou recomenda em vez de documentar: "${p.frase}" em "${p.trecho}"`);
    return { ok: false, kind: "stance", problem: detalhes[0]!, details: detalhes };
  }

  return { ok: true };
}

/**
 * Resposta extractiva: usada quando a síntese externa está proibida pela
 * política de processamento externo, ou quando não há provedor. Não é um
 * resumo — é a citação da primeira evidência, montada aqui, sem modelo
 * nenhum. Honesta sobre o que é.
 */
export function extractiveAnswer(evidencias: KnowledgeEvidence[]): string {
  const n = evidencias.length;
  const cabeca = n === 1
    ? "Encontrei 1 trecho na documentação, mas não posso resumi-lo automaticamente:"
    : `Encontrei ${n} trechos na documentação, mas não posso resumi-los automaticamente:`;
  const corpo = evidencias
    .map((e, i) => `[${i + 1}] ${e.citation}`)
    .join("\n");
  return `${cabeca}\n\n${corpo}\n\nOs trechos estão abaixo, na íntegra.`;
}
