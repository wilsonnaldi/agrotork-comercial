import type { KnowledgeEvidence } from "./evidence";
import { parseListingQuestion, type ListingField } from "./exhaustiveness";
import { contemLiteral, contemToken, extractUnitPairs, pareceCodigo } from "./grounding";

/**
 * Comparação entre códigos — a quarta trava, e a primeira capacidade em que
 * o BRAIN devolve um número que NÃO está escrito no documento (a diferença).
 *
 * As três regras que organizam o arquivo:
 *
 *  1. **Identidade.** Um valor só vale para o código cuja LINHA o contém. A
 *     MJ981CAP e a MJ985CAP moram na mesma tabela; a linha de uma nunca
 *     sustenta o valor da outra. É o vazamento entre produtos, e é o erro
 *     que esta rodada existe para impedir;
 *  2. **Cálculo em código.** A diferença é calculada aqui, a partir de valores já
 *     validados, e só depois entregue ao modelo para ele escrever. O que o
 *     modelo escrever de número derivado é conferido contra o que este
 *     arquivo calculou — caractere a caractere;
 *  3. **Falta é falta.** Sem evidência para um dos códigos não há vencedor,
 *     não há diferença e não há comparação: há o valor que existe e a frase
 *     dizendo que o outro não foi encontrado.
 *
 * Nada aqui converte unidade, interpola, recomenda ou ordena "o melhor".
 */

const normaliza = (t: string) =>
  t.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/[^a-z0-9%]+/g, " ").trim();

/**
 * Intenção EXPLÍCITA. Dois códigos numa pergunta não bastam: "a MJ981CAP
 * substitui a MJ985CAP?" não é pedido de comparação de atributo, e tratá-la
 * como tal produziria uma tabela que ninguém pediu.
 */
const GATILHOS = [
  "compare", "comparar", "comparacao", "comparativo", "compara",
  "diferenca", "diferencas", "versus", " vs ", "lado a lado",
];
const GATILHOS_DE_ORDEM = [
  /qual (tem|possui|entrega|oferece) (a )?(maior|menor)/,
  /quanto .*(a mais|a menos)/,
  /qual (dos|das|deles|delas) .*(maior|menor)/,
];

export function detectComparisonIntent(pergunta: string): boolean {
  const n = ` ${normaliza(pergunta)} `;
  if (GATILHOS.some((g) => n.includes(g.trim().length === g.length ? ` ${g} ` : g))) return true;
  return GATILHOS_DE_ORDEM.some((re) => re.test(n));
}

/** Teto por consulta. Acima disso a resposta vira longa demais para conferir. */
export const MAX_CODIGOS_COMPARADOS = 5;

export type ComparisonSpec = {
  codes: string[];
  fields: ListingField[];
  pinned: { numero: string; unidade: string }[];
  /** Percentual só entra se a pergunta pedir. */
  wantsPercent: boolean;
};

export function parseComparison(pergunta: string): ComparisonSpec {
  // Os códigos e os campos vêm do MESMO parser da listagem: um só critério
  // de código no sistema inteiro.
  const base = parseListingQuestion(pergunta);
  const n = normaliza(pergunta);
  return {
    codes: base.codes,
    fields: base.fields,
    pinned: base.pinned,
    wantsPercent: /%|percentual|porcentagem|por cento/.test(n),
  };
}

export type ProductValue = { numero: string; unidade: string; linha: string; evidenceIndex: number };

export type ProductBlock = {
  code: string;
  values: ProductValue[];
  /** Nenhuma linha de evidência traz esse código com o que foi pedido. */
  missing: boolean;
};

export type DerivedValue = {
  tipo: "diferenca" | "percentual";
  de: string;
  para: string;
  unidade: string;
  /** O literal, em português, que a resposta pode escrever. */
  texto: string;
};

export type ComparisonPlan =
  | { status: "not_applicable"; reason: string }
  | { status: "too_many"; codes: string[]; limite: number }
  | {
      status: "ready";
      spec: ComparisonSpec;
      blocks: ProductBlock[];
      derived: DerivedValue[];
      /** Algum código ficou sem evidência: não há diferença nem vencedor. */
      incomplete: boolean;
    };

/** As linhas que sustentam UM código, e só ele. */
export function linesForCode(code: string, outros: string[], evidencias: KnowledgeEvidence[]): { texto: string; evidenceIndex: number }[] {
  const linhas: { texto: string; evidenceIndex: number }[] = [];
  evidencias.forEach((e, evidenceIndex) => {
    for (const bruta of e.content.split(/\r?\n/)) {
      const texto = bruta.replace(/\s+/g, " ").trim();
      if (texto.length === 0) continue;
      if (!contemToken(texto, code)) continue;
      // Linha que cita DOIS dos códigos comparados não identifica ninguém:
      // fail-closed, porque é exatamente onde o vazamento nasceria.
      if (outros.some((o) => o !== code && contemToken(texto, o))) continue;
      linhas.push({ texto, evidenceIndex });
    }
  });
  return linhas;
}

const decimais = (n: string) => (n.includes(",") ? n.split(",")[1]!.length : n.includes(".") ? n.split(".")[1]!.length : 0);
const paraNumero = (n: string) => Number(n.replace(/\./g, "").replace(",", "."));
const paraTexto = (v: number, casas: number) => v.toFixed(casas).replace(".", ",");

/**
 * Diferença entre dois valores JÁ validados. Mesma unidade, sempre; esta
 * rodada não converte nada. As casas decimais saem das entradas, não de um
 * arredondamento inventado.
 */
export function difference(a: ProductValue, b: ProductValue): { texto: string; unidade: string } | null {
  if (a.unidade !== b.unidade) return null;
  const casas = Math.max(decimais(a.numero), decimais(b.numero));
  const bruto = Math.abs(paraNumero(b.numero) - paraNumero(a.numero));
  // Aritmética binária deixa 0.7600000000000001; a soma volta à escala das
  // entradas antes de virar texto.
  const valor = Number(bruto.toFixed(casas));
  return { texto: paraTexto(valor, casas), unidade: a.unidade };
}

export function percentDifference(a: ProductValue, b: ProductValue): string | null {
  if (a.unidade !== b.unidade) return null;
  const base = paraNumero(a.numero);
  if (base === 0) return null;
  const variacao = ((paraNumero(b.numero) - base) / base) * 100;
  return paraTexto(Number(Math.abs(variacao).toFixed(1)), 1);
}

export function planComparison(pergunta: string, evidencias: KnowledgeEvidence[]): ComparisonPlan {
  if (!detectComparisonIntent(pergunta)) {
    return { status: "not_applicable", reason: "a pergunta não pede comparação" };
  }
  const spec = parseComparison(pergunta);
  if (spec.codes.length < 2) {
    return { status: "not_applicable", reason: "a pergunta não traz dois códigos" };
  }
  if (spec.codes.length > MAX_CODIGOS_COMPARADOS) {
    return { status: "too_many", codes: spec.codes, limite: MAX_CODIGOS_COMPARADOS };
  }

  const unidadesPedidas = spec.fields.flatMap((f) => f.unidades);

  const blocks: ProductBlock[] = spec.codes.map((code) => {
    const linhas = linesForCode(code, spec.codes, evidencias).filter((l) =>
      spec.pinned.every(
        (p) => contemLiteral(l.texto, `${p.numero} ${p.unidade}`) || contemLiteral(l.texto, `${p.numero}${p.unidade}`),
      ),
    );
    const values: ProductValue[] = [];
    for (const l of linhas) {
      for (const par of extractUnitPairs(l.texto)) {
        if (!unidadesPedidas.includes(par.unidade)) continue;
        values.push({ numero: par.numero, unidade: par.unidade, linha: l.texto, evidenceIndex: l.evidenceIndex });
      }
    }
    return { code, values, missing: values.length === 0 };
  });

  const incomplete = blocks.some((b) => b.missing);

  // A diferença só existe quando cada produto tem UM valor por unidade —
  // com a pergunta fixando o ponto ("a 40 psi"), é o caso normal. Sem isso,
  // não há par a subtrair e o sistema não inventa um.
  const derived: DerivedValue[] = [];
  if (!incomplete && blocks.length >= 2) {
    const unidades = [...new Set(blocks.flatMap((b) => b.values.map((v) => v.unidade)))];
    for (const unidade of unidades) {
      const porProduto = blocks.map((b) => b.values.filter((v) => v.unidade === unidade));
      if (porProduto.some((vs) => vs.length !== 1)) continue;
      for (let i = 0; i < blocks.length; i++) {
        for (let j = i + 1; j < blocks.length; j++) {
          const a = porProduto[i]![0]!;
          const b = porProduto[j]![0]!;
          const d = difference(a, b);
          // Diferença zero não é achado: é o ponto de operação que a
          // pergunta fixou ("a 40 psi" dá 0 psi de diferença, sempre). Fora
          // isso, dois valores iguais o modelo descreve como iguais, sem
          // precisar de um número calculado.
          if (d && paraNumero(d.texto) !== 0) {
            derived.push({
              tipo: "diferenca", de: blocks[i]!.code, para: blocks[j]!.code,
              unidade, texto: `${d.texto} ${d.unidade}`,
            });
          }
          if (spec.wantsPercent) {
            const p = percentDifference(a, b);
            if (p) {
              derived.push({
                tipo: "percentual", de: blocks[i]!.code, para: blocks[j]!.code,
                unidade: "%", texto: `${p}%`,
              });
            }
          }
        }
      }
    }
  }

  return { status: "ready", spec, blocks, derived, incomplete };
}

/**
 * O que a resposta pode escrever mesmo sem estar no documento:
 *
 *  · os valores DERIVADOS que este arquivo calculou sobre valores validados;
 *  · os CÓDIGOS da própria pergunta — sem isso, dizer "não encontrei
 *    documentação para a MJ999CAP" seria reprovado como código inventado, e
 *    a resposta honesta ficaria impossível. Escrever o código não autoriza
 *    atribuir valor a ele: `checkComparison` barra qualquer número posto ao
 *    lado de um produto sem linha.
 */
export function derivedLiterals(plan: ComparisonPlan): string[] {
  if (plan.status !== "ready") return [];
  return [...plan.derived.map((d) => d.texto), ...plan.spec.codes];
}

// ════════════════════════════════════════════════════════════
// Conferência da resposta comparativa
// ════════════════════════════════════════════════════════════

export type ComparisonResult =
  | { status: "not_applicable"; reason: string }
  | { status: "ok"; checked: number }
  | { status: "failed"; failures: string[] };

const UNIDADES_DE_LINHA = new Set(["bar", "psi", "kPa", "L/min", "L/ha"]);

/** Itens da resposta: linha, ";" ou fim de frase — igual à associação. */
function itens(resposta: string): string[] {
  return resposta
    .replace(/\[\d{1,3}\]/g, " ")
    .split(/\r?\n|;|\.\s+/)
    .map((i) => i.replace(/\s+/g, " ").trim())
    .filter((i) => i.length > 0);
}

/**
 * A conferência específica da comparação. Roda DEPOIS do grounding, da
 * exaustão e da associação, e não substitui nenhuma delas.
 */
export function checkComparison(
  pergunta: string,
  resposta: string,
  evidencias: KnowledgeEvidence[],
): ComparisonResult {
  const plan = planComparison(pergunta, evidencias);
  if (plan.status === "not_applicable") return { status: "not_applicable", reason: plan.reason };
  if (plan.status === "too_many") {
    return { status: "failed", failures: [`comparação com ${plan.codes.length} códigos, acima do limite de ${plan.limite}`] };
  }

  const failures: string[] = [];
  const porCodigo = new Map(plan.blocks.map((b) => [b.code.toUpperCase(), b]));

  // 1. Identidade: valor escrito ao lado de um código tem de ser DAQUELE código.
  let conferidos = 0;
  for (const item of itens(resposta)) {
    const codigosDoItem = [...new Set(
      [...item.matchAll(/[A-Za-z0-9][A-Za-z0-9-]*/g)].map((m) => m[0]).filter(pareceCodigo),
    )].filter((c) => porCodigo.has(c.toUpperCase()));
    if (codigosDoItem.length !== 1) continue;   // item sem dono único não afirma identidade
    const bloco = porCodigo.get(codigosDoItem[0]!.toUpperCase())!;
    const pares = extractUnitPairs(item).filter((p) => UNIDADES_DE_LINHA.has(p.unidade));
    for (const par of pares) {
      conferidos += 1;
      const daLinhaDele = bloco.values.some((v) => v.numero === par.numero && v.unidade === par.unidade) ||
        linesForCode(bloco.code, plan.spec.codes, evidencias).some(
          (l) => contemLiteral(l.texto, `${par.numero} ${par.unidade}`),
        );
      if (!daLinhaDele) {
        failures.push(
          `valor de outro produto atribuído a ${bloco.code}: "${par.numero} ${par.unidade}" não está em nenhuma linha desse código`,
        );
      }
    }
    if (bloco.missing && pares.length > 0) {
      failures.push(`${bloco.code} não tem evidência para o que foi pedido, mas a resposta apresenta valor para ele`);
    }
  }

  // 1b. Diferença escrita = diferença calculada. Um número que por acaso
  //     existe noutra linha da tabela (0,86 L/min é a MJ981CAP a 3,45 bar)
  //     passaria no grounding e mentiria aqui.
  const permitidosDerivados = new Set(plan.derived.map((d) => d.texto));
  for (const item of itens(resposta)) {
    if (!/diferen[çc]a|a mais|a menos|por cento|percentual/i.test(item)) continue;
    for (const par of extractUnitPairs(item)) {
      if (!UNIDADES_DE_LINHA.has(par.unidade) && par.unidade !== "%") continue;
      const texto = `${par.numero} ${par.unidade}`;
      const colado = `${par.numero}${par.unidade}`;
      if (permitidosDerivados.has(texto) || permitidosDerivados.has(colado)) continue;
      failures.push(
        plan.derived.length === 0
          ? `a resposta anuncia "${texto}" como diferença, e o sistema não calculou diferença nenhuma`
          : `diferença "${texto}" não confere com o cálculo do sistema (${[...permitidosDerivados].join(", ")})`,
      );
    }
  }

  // 2. Cada código comparado precisa aparecer na resposta — com valor ou com
  //    a falta declarada. Omitir um produto é responder outra pergunta.
  for (const b of plan.blocks) {
    if (!contemToken(resposta, b.code)) failures.push(`a resposta não menciona ${b.code}`);
  }

  // 3. Comparação incompleta não conclui: sem diferença, sem vencedor.
  if (plan.incomplete) {
    const faltantes = plan.blocks.filter((b) => b.missing).map((b) => b.code);
    const anunciaDiferenca = /diferen[çc]a/i.test(resposta) && /\d/.test(resposta);
    if (anunciaDiferenca) {
      failures.push(`comparação incompleta (sem evidência para ${faltantes.join(", ")}) não pode anunciar diferença`);
    }
  }

  return failures.length === 0 ? { status: "ok", checked: conferidos } : { status: "failed", failures };
}
