import type { KnowledgeEvidence } from "./evidence";
import { contemLiteral, contemToken, extractUnitPairs, pareceCodigo } from "./grounding";

/**
 * Checagem de EXAUSTÃO para perguntas de listagem.
 *
 * O grounding (`grounding.ts`) prova que nada foi INVENTADO: todo número
 * escrito existe na evidência citada. Ele não prova que nada foi OMITIDO.
 * "Quais as vazões da MJ981CAP em bar?" respondida com cinco dos seis pontos
 * passa no grounding — cada um dos cinco existe — e chega ao cliente como se
 * fosse a tabela inteira.
 *
 * Esta camada fecha esse buraco para o caso que importa hoje: tabela
 * numérica, pergunta com código. Ela é ADICIONAL ao grounding, roda depois
 * dele e nunca o substitui.
 *
 * Como funciona, sem NLP:
 *
 *  1. a pergunta pede listagem? — gatilho lexical ("quais", "todas",
 *     "liste", "opções", "disponíveis", "possíveis", "existem"…);
 *  2. de qual código? — o mesmo perfil de código do grounding;
 *  3. de qual campo? — vazão (L/min), pressão (bar/psi/kPa), volume (L/ha).
 *     Unidade explícita na pergunta ("em bar") restringe a pressão a ela;
 *  4. as LINHAS da evidência que trazem o código (e o valor fixado na
 *     pergunta, se houver: "quais … a 40 psi") formam o conjunto exigido;
 *  5. cada valor exigido tem de aparecer na resposta (FALTANTE se não);
 *  6. todo par número+unidade da resposta, numa unidade que essas linhas
 *     usam, tem de pertencer a elas (ESTRANHO se não) — é o que pega a
 *     vazão da MJ982CAP escrita como se fosse da MJ981CAP, que o grounding
 *     deixa passar porque o número existe na mesma tabela.
 *
 * O que ela NÃO faz, escrito para não virar promessa:
 *  · não verifica que cada vazão está ao lado da SUA pressão — presença e
 *    pertencimento ao conjunto, não associação par a par;
 *  · não se aplica quando a pergunta não traz código, quando o código não
 *    aparece na mesma linha que os valores, ou quando o valor fixado na
 *    pergunta não existe (aí não há o que listar, e o grounding segue
 *    barrando qualquer número inventado). Nesses casos devolve
 *    `not_applicable`, com o motivo.
 */

const normaliza = (t: string) =>
  t
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim();

/**
 * Palavras que pedem o conjunto, não um ponto. "qual" (singular) fica de
 * fora de propósito: "Qual a vazão a 40 psi?" pede UM valor.
 */
const GATILHOS = new Set([
  "quais", "todos", "todas", "liste", "listar", "lista", "listagem", "enumere",
  "opcoes", "disponiveis", "possiveis", "possibilidades", "existem", "existentes",
  "combinacoes", "tabela", "mostre", "mostrar",
]);

export function detectListingIntent(pergunta: string): boolean {
  return normaliza(pergunta).split(" ").some((t) => GATILHOS.has(t));
}

export type Campo = "pressao" | "vazao" | "volume";

const UNIDADES: Record<Campo, string[]> = {
  pressao: ["bar", "psi", "kPa"],
  vazao: ["L/min"],
  volume: ["L/ha"],
};

const UNIDADE_POR_PALAVRA: Record<string, string> = { bar: "bar", psi: "psi", kpa: "kPa" };

export type ListingField = {
  campo: Campo;
  /** Unidades aceitas. */
  unidades: string[];
  /**
   * `every` — cada valor de cada unidade listada é exigido (unidade pedida
   * explicitamente). `any` — basta um dos valores da linha, em qualquer das
   * unidades (a pergunta disse "pressões" sem dizer em quê).
   */
  modo: "every" | "any";
};

export type ListingSpec = {
  codes: string[];
  fields: ListingField[];
  pinned: { numero: string; unidade: string }[];
};

export function parseListingQuestion(pergunta: string): ListingSpec {
  const codes = [...new Set([...pergunta.matchAll(/[A-Za-z0-9][A-Za-z0-9-]*/g)].map((m) => m[0]).filter(pareceCodigo))];
  const palavras = normaliza(pergunta).split(" ");
  const pinned = extractUnitPairs(pergunta);

  // Unidade pedida = palavra de unidade que NÃO é só a de um valor fixado.
  // "em bar" pede a listagem em bar; "a 40 psi" fixa uma linha e não pede psi.
  const pressaoExplicita = Object.entries(UNIDADE_POR_PALAVRA)
    .filter(([palavra, unidade]) => {
      const citada = palavras.filter((p) => p === palavra).length;
      const fixada = pinned.filter((p) => p.unidade === unidade).length;
      return citada > fixada;
    })
    .map(([, unidade]) => unidade);

  const querVazao = palavras.some((p) => p.startsWith("vaz")) || /L\/min/i.test(pergunta);
  const querPressao = palavras.some((p) => p.startsWith("press")) || pressaoExplicita.length > 0;
  const querVolume = /L\/ha/i.test(pergunta) || palavras.includes("hectare");

  const fields: ListingField[] = [];
  if (querPressao) {
    fields.push(
      pressaoExplicita.length > 0
        ? { campo: "pressao", unidades: pressaoExplicita, modo: "every" }
        : { campo: "pressao", unidades: UNIDADES.pressao, modo: "any" },
    );
  }
  if (querVazao) fields.push({ campo: "vazao", unidades: UNIDADES.vazao, modo: "every" });
  if (querVolume) fields.push({ campo: "volume", unidades: UNIDADES.volume, modo: "every" });
  if (fields.length === 0) {
    // "Liste as opções da MJ981CAP": numa tabela de pontas, as opções são os
    // pontos de trabalho — pressão e vazão.
    fields.push({ campo: "pressao", unidades: UNIDADES.pressao, modo: "any" });
    fields.push({ campo: "vazao", unidades: UNIDADES.vazao, modo: "every" });
  }
  return { codes, fields, pinned };
}

export type Requirement = { linha: string; campo: Campo; alternativas: string[] };

export type ExhaustivenessResult =
  | { status: "not_applicable"; reason: string }
  | { status: "complete"; required: number }
  | { status: "incomplete"; required: number; missing: Requirement[]; extraneous: string[] };

const TODAS_AS_UNIDADES_DE_LINHA = new Set(Object.values(UNIDADES).flat());

/** As linhas de evidência que respondem pela pergunta. */
export function relevantLines(spec: ListingSpec, evidencias: KnowledgeEvidence[]): string[] {
  const linhas: string[] = [];
  for (const e of evidencias) {
    for (const bruta of e.content.split(/\r?\n/)) {
      const linha = bruta.replace(/\s+/g, " ").trim();
      if (linha.length === 0) continue;
      if (!spec.codes.some((c) => contemToken(linha, c))) continue;
      const fixadoOk = spec.pinned.every(
        (p) => contemLiteral(linha, `${p.numero} ${p.unidade}`) || contemLiteral(linha, `${p.numero}${p.unidade}`),
      );
      if (!fixadoOk) continue;
      linhas.push(linha);
    }
  }
  return linhas;
}

export function requirementsFor(spec: ListingSpec, linhas: string[]): Requirement[] {
  const vistos = new Set<string>();
  const exigidos: Requirement[] = [];
  const adiciona = (r: Requirement) => {
    const chave = `${r.campo}|${r.alternativas.join("|")}`;
    if (vistos.has(chave)) return;
    vistos.add(chave);
    exigidos.push(r);
  };
  for (const linha of linhas) {
    const pares = extractUnitPairs(linha);
    for (const f of spec.fields) {
      const doCampo = pares.filter((p) => f.unidades.includes(p.unidade));
      if (doCampo.length === 0) continue;
      if (f.modo === "any") {
        adiciona({ linha, campo: f.campo, alternativas: doCampo.map((p) => p.numero) });
      } else {
        for (const p of doCampo) adiciona({ linha, campo: f.campo, alternativas: [p.numero] });
      }
    }
  }
  return exigidos;
}

export function checkExhaustiveness(
  pergunta: string,
  resposta: string,
  evidencias: KnowledgeEvidence[],
): ExhaustivenessResult {
  if (!detectListingIntent(pergunta)) return { status: "not_applicable", reason: "a pergunta não pede listagem" };

  const spec = parseListingQuestion(pergunta);
  if (spec.codes.length === 0) return { status: "not_applicable", reason: "a pergunta não traz código" };

  const linhas = relevantLines(spec, evidencias);
  const exigidos = requirementsFor(spec, linhas);
  if (exigidos.length === 0) {
    return {
      status: "not_applicable",
      reason: "nenhuma linha das evidências traz, junto do código, o que foi pedido",
    };
  }

  // [1], [2] são ponteiros, não valores.
  const corpo = resposta.replace(/\[\d{1,3}\]/g, " ").replace(/\s+/g, " ");

  const missing = exigidos.filter((r) => !r.alternativas.some((a) => contemLiteral(corpo, a)));

  const permitidos = new Set<string>();
  const unidadesDasLinhas = new Set<string>();
  for (const linha of linhas) {
    for (const p of extractUnitPairs(linha)) {
      if (!TODAS_AS_UNIDADES_DE_LINHA.has(p.unidade)) continue;
      permitidos.add(`${p.numero} ${p.unidade}`);
      unidadesDasLinhas.add(p.unidade);
    }
  }
  const extraneous = [
    ...new Set(
      extractUnitPairs(corpo)
        .filter((p) => unidadesDasLinhas.has(p.unidade))
        .map((p) => `${p.numero} ${p.unidade}`)
        .filter((par) => !permitidos.has(par)),
    ),
  ];

  if (missing.length === 0 && extraneous.length === 0) return { status: "complete", required: exigidos.length };
  return { status: "incomplete", required: exigidos.length, missing, extraneous };
}

/** Linhas legíveis para o log. */
export function describeExhaustiveness(r: Extract<ExhaustivenessResult, { status: "incomplete" }>): string[] {
  const nomes: Record<Campo, string> = { pressao: "pressão", vazao: "vazão", volume: "volume" };
  return [
    ...r.missing.map(
      (m) => `listagem incompleta: faltou ${nomes[m.campo]} ${m.alternativas.join(" / ")} (${m.linha.slice(0, 40)}…)`,
    ),
    ...r.extraneous.map((x) => `listagem com valor fora das linhas do código consultado: ${x}`),
  ];
}
