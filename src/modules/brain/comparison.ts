import type { KnowledgeEvidence } from "./evidence";
import { blockContexts, parseListingQuestion, type ListingField } from "./exhaustiveness";
import { contemLiteral, contemToken, extractUnitPairs, pareceCodigo, type AllowedLiteral } from "./grounding";

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

/**
 * De onde saiu uma parcela do cálculo. É o que transforma um número
 * derivado em prova: sem isto, "0,76 L/min" é só um número que o sistema
 * afirma ter calculado, e o parágrafo podia citar qualquer evidência.
 */
export type DerivedSource = {
  code: string;
  numero: string;
  unidade: string;
  evidenceIndex: number;
};

export type DerivedValue = {
  tipo: "diferenca" | "percentual";
  de: string;
  para: string;
  unidade: string;
  /** O literal, em português, que a resposta pode escrever. */
  texto: string;
  /**
   * As DUAS parcelas, com a evidência de cada uma. O parágrafo que escrever
   * `texto` precisa ter citado todas as evidências daqui — se as parcelas
   * moram na mesma evidência, é uma citação só; se vêm de documentos
   * diferentes, são as duas.
   */
  sources: DerivedSource[];
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
          const fontes: DerivedSource[] = [
            { code: blocks[i]!.code, numero: a.numero, unidade: a.unidade, evidenceIndex: a.evidenceIndex },
            { code: blocks[j]!.code, numero: b.numero, unidade: b.unidade, evidenceIndex: b.evidenceIndex },
          ];
          if (d && paraNumero(d.texto) !== 0) {
            derived.push({
              tipo: "diferenca", de: blocks[i]!.code, para: blocks[j]!.code,
              unidade, texto: `${d.texto} ${d.unidade}`, sources: fontes,
            });
          }
          if (spec.wantsPercent) {
            const p = percentDifference(a, b);
            if (p) {
              derived.push({
                tipo: "percentual", de: blocks[i]!.code, para: blocks[j]!.code,
                unidade: "%", texto: `${p}%`, sources: fontes,
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
export function derivedLiterals(plan: ComparisonPlan): AllowedLiteral[] {
  if (plan.status !== "ready") return [];
  return [
    ...plan.derived.map((d) => ({
      texto: d.texto,
      requires: [...new Set(d.sources.map((f) => f.evidenceIndex))].sort((x, y) => x - y),
    })),
    // Os códigos da pergunta não dependem de evidência nenhuma: eles vieram
    // da pergunta. `requires: []` é essa exceção, e ela é só isto.
    ...plan.spec.codes.map((code) => ({ texto: code, requires: [] })),
  ];
}

// ════════════════════════════════════════════════════════════
// Conferência da resposta comparativa
// ════════════════════════════════════════════════════════════

export type ComparisonResult =
  | { status: "not_applicable"; reason: string }
  | { status: "ok"; checked: number }
  | { status: "failed"; failures: string[] };

const UNIDADES_DE_LINHA = new Set(["bar", "psi", "kPa", "L/min", "L/ha"]);

/** A citação como o validador a recebe: o número entre colchetes e a evidência. */
export type CitacaoRef = { index: number; evidenceIndex: number };

/**
 * Um item da resposta COM as citações que valem para ele.
 *
 * Por que as citações vêm junto. Até a auditoria de 18/09 a conferência
 * apagava os `[n]` antes de olhar o item, e perguntava só "existe alguma
 * evidência que sustente isto?". Com duas evidências trazendo o mesmo
 * número para produtos diferentes, "MJ981CAP: 0,77 L/min [2]" passava: o
 * grounding via 0,77 em [2] e a comparação via 0,77 numa linha da MJ981CAP
 * em [1]. Duas provas verdadeiras, e nenhuma delas a prova pedida.
 *
 * `evidencias` são as do próprio item; vazio, herda as do PARÁGRAFO — mesma
 * unidade do grounding, que já diz que duas afirmações no mesmo parágrafo
 * compartilham as citações dele.
 */
/**
 * `contexto` é o código do CABEÇALHO do bloco em que o item está (ver
 * `blockContexts`, em exhaustiveness.ts — a mesma regra que a associação
 * usa, para não haver duas noções de bloco). Uma linha "- 40 psi -> 0,77
 * L/min" debaixo de "MJ981CAP [1]:" é uma afirmação SOBRE a MJ981CAP, e
 * até 25/09 este arquivo não sabia disso: o item sem código não afirmava
 * identidade, e o valor de outro produto passava no formato oficial.
 */
type Item = { texto: string; citadas: number[]; evidencias: Set<number>; contexto: string | null };

function itens(resposta: string, citacoes: CitacaoRef[], conhecidos: Set<string>): Item[] {
  const daCitacao = new Map(citacoes.map((c) => [c.index, c.evidenceIndex]));
  const lidas = (trecho: string) => {
    const numeros: number[] = [];
    const evid = new Set<number>();
    for (const m of trecho.matchAll(/\[(\d{1,3})\]/g)) {
      const n = Number(m[1]);
      if (!numeros.includes(n)) numeros.push(n);
      const e = daCitacao.get(n);
      if (e !== undefined) evid.add(e);
    }
    return { numeros: numeros.sort((a, b) => a - b), evid };
  };

  // Parágrafo (de onde um item sem citação própria herda as citações) é o
  // trecho entre linhas em branco — a mesma quebra que `blockContexts`
  // usa para encerrar um bloco. Percorrer as linhas já anotadas e agrupá-las
  // nas linhas em branco dá os mesmos parágrafos de `split(/\n\s*\n/)`.
  const anotadas = blockContexts(resposta, conhecidos);
  const paragrafos: typeof anotadas[] = [];
  let atual: typeof anotadas = [];
  for (const l of anotadas) {
    if (l.linha.trim().length === 0) {
      if (atual.length > 0) paragrafos.push(atual);
      atual = [];
    } else {
      atual.push(l);
    }
  }
  if (atual.length > 0) paragrafos.push(atual);

  const saida: Item[] = [];
  for (const paragrafo of paragrafos) {
    const doParagrafo = lidas(paragrafo.map((l) => l.linha).join("\n"));
    for (const { linha, contexto } of paragrafo) {
      for (const bruto of linha.split(/;|\.\s+/)) {
        const proprias = lidas(bruto);
        const texto = bruto.replace(/\[\d{1,3}\]/g, " ").replace(/\s+/g, " ").trim();
        if (texto.length === 0) continue;
        const tem = proprias.evid.size > 0 ? proprias : doParagrafo;
        saida.push({ texto, citadas: tem.numeros, evidencias: tem.evid, contexto });
      }
    }
  }
  return saida;
}

/** Os códigos comparados que aparecem num item, na ordem em que aparecem. */
function codigosDoItem(texto: string, conhecidos: Set<string>): { code: string; pos: number }[] {
  const achados: { code: string; pos: number }[] = [];
  for (const m of texto.matchAll(/[A-Za-z0-9][A-Za-z0-9-]*/g)) {
    const t = m[0];
    if (!pareceCodigo(t)) continue;
    if (!conhecidos.has(t.toUpperCase())) continue;
    if (achados.some((a) => a.code.toUpperCase() === t.toUpperCase())) continue;
    achados.push({ code: t, pos: m.index ?? 0 });
  }
  return achados;
}

// ════════════════════════════════════════════════════════════
// Relação numérica: maior, menor, igual
// ════════════════════════════════════════════════════════════

/**
 * Quem é maior não é opinião, e não é trabalho do modelo. Os valores já
 * foram validados linha a linha; a ordem entre eles é uma subtração.
 *
 * Isto NÃO é ranking e NÃO é recomendação: não existe "melhor". É a relação
 * objetiva entre dois números da mesma grandeza, e só.
 */
export type RelationalIntent = "greater" | "lower" | null;

/**
 * A pergunta pede QUAL é o maior/menor?
 *
 * "quanto a MJ985CAP entrega a mais" pede o TAMANHO da diferença, não o
 * vencedor — e já é respondido pelo derivado. Por isso "quanto" desqualifica.
 * Pedir os dois ("qual tem maior vazão e menor consumo") também: são duas
 * relações, e concluir uma só seria responder metade.
 */
export function parseRelationalIntent(pergunta: string): RelationalIntent {
  const n = ` ${normaliza(pergunta)} `;
  if (!/ (qual|quais|quem) /.test(n)) return null;
  if (/ quanto /.test(n)) return null;
  const maior = / (maior|mais) /.test(n);
  const menor = / (menor|menos) /.test(n);
  if (maior === menor) return null;
  return maior ? "greater" : "lower";
}

export type Relation =
  | { status: "not_applicable"; reason: string }
  | {
      status: "ready";
      unidade: string;
      /** Do maior para o menor. */
      ordem: { code: string; numero: string }[];
      maiores: string[];
      menores: string[];
      todosIguais: boolean;
    };

/**
 * A relação entre os produtos, a partir dos valores JÁ validados.
 *
 * Exige tudo o que uma comparação honesta exige: comparação completa, mesma
 * unidade, e UM valor por produto. Dois valores para um produto significa
 * que a pergunta não fixou o ponto de operação — e aí "qual tem maior vazão"
 * não tem resposta única, tem três. Nesse caso não se conclui nada, que é
 * diferente de concluir errado.
 */
export function relate(plan: ComparisonPlan): Relation {
  if (plan.status !== "ready") return { status: "not_applicable", reason: "não há plano de comparação" };
  if (plan.incomplete) return { status: "not_applicable", reason: "comparação incompleta" };
  if (plan.blocks.length < 2) return { status: "not_applicable", reason: "menos de dois produtos" };

  const unidades = [...new Set(plan.blocks.flatMap((b) => b.values.map((v) => v.unidade)))];
  const comparaveis = unidades.filter((u) =>
    plan.blocks.every((b) => b.values.filter((v) => v.unidade === u).length === 1),
  );
  if (comparaveis.length !== 1) {
    return {
      status: "not_applicable",
      reason: comparaveis.length === 0
        ? "nenhuma grandeza tem exatamente um valor por produto"
        : `mais de uma grandeza comparável (${comparaveis.join(", ")})`,
    };
  }

  const unidade = comparaveis[0]!;
  const pares = plan.blocks.map((b) => {
    const v = b.values.find((x) => x.unidade === unidade)!;
    return { code: b.code, numero: v.numero, valor: paraNumero(v.numero) };
  });
  const ordenado = [...pares].sort((a, b) => b.valor - a.valor);
  const topo = ordenado[0]!.valor;
  const fundo = ordenado[ordenado.length - 1]!.valor;
  const todosIguais = topo === fundo;

  return {
    status: "ready",
    unidade,
    ordem: ordenado.map((p) => ({ code: p.code, numero: p.numero })),
    // Empate geral não tem maior nem menor: tem iguais. Devolver a lista
    // cheia faria "a MJ981CAP é a maior" passar num empate.
    maiores: todosIguais ? [] : ordenado.filter((p) => p.valor === topo).map((p) => p.code),
    menores: todosIguais ? [] : ordenado.filter((p) => p.valor === fundo).map((p) => p.code),
    todosIguais,
  };
}

const RE_MAIOR = /\b(maior|maiores|mais alta|mais alto|superior|a mais)\b/;
const RE_MENOR = /\b(menor|menores|mais baixa|mais baixo|inferior|a menos)\b/;
const RE_IGUAL = /\b(iguais|igual|equivalentes|mesmo valor|mesma vazao|empat)/;

type Claim = { tipo: "maior" | "menor" | "igual"; code?: string; texto: string };

/**
 * O que a resposta AFIRMA sobre a ordem. Conservador de propósito: item com
 * dois códigos só vira afirmação na forma "A … maior … B", que é a ordem do
 * português. Qualquer construção fora disso não é lida como afirmação — é
 * melhor não julgar do que reprovar quem escreveu certo.
 */
function claimsDe(itensDaResposta: Item[], conhecidos: Set<string>): Claim[] {
  const claims: Claim[] = [];
  for (const item of itensDaResposta) {
    const n = normaliza(item.texto);
    const maior = RE_MAIOR.test(n);
    const menor = RE_MENOR.test(n);
    if (RE_IGUAL.test(n) && !maior && !menor) {
      claims.push({ tipo: "igual", texto: item.texto });
      continue;
    }
    if (maior === menor) continue;
    const tipo = maior ? "maior" : "menor";
    const codigos = codigosDoItem(item.texto, conhecidos);
    if (codigos.length === 1) {
      claims.push({ tipo, code: codigos[0]!.code, texto: item.texto });
      continue;
    }
    if (codigos.length === 2) {
      const alvo = (maior ? RE_MAIOR : RE_MENOR).exec(n);
      const posComparativo = alvo?.index ?? -1;
      // "A tem maior vazão que B": o comparativo fica ENTRE os dois códigos.
      if (posComparativo > codigos[0]!.pos && posComparativo < codigos[1]!.pos) {
        claims.push({ tipo, code: codigos[0]!.code, texto: item.texto });
      }
    }
  }
  return claims;
}

/**
 * A conferência específica da comparação. Roda DEPOIS do grounding, da
 * exaustão e da associação, e não substitui nenhuma delas.
 *
 * Precisa das CITAÇÕES desde 18/09: sem elas, provar que o número existe e
 * provar que o produto tem aquele número são duas verificações que podem se
 * apoiar em evidências diferentes — e duas meias-provas não fazem uma prova.
 */
export function checkComparison(
  pergunta: string,
  resposta: string,
  evidencias: KnowledgeEvidence[],
  citacoes: CitacaoRef[],
): ComparisonResult {
  const plan = planComparison(pergunta, evidencias);
  if (plan.status === "not_applicable") return { status: "not_applicable", reason: plan.reason };
  if (plan.status === "too_many") {
    return { status: "failed", failures: [`comparação com ${plan.codes.length} códigos, acima do limite de ${plan.limite}`] };
  }

  const failures: string[] = [];
  const porCodigo = new Map(plan.blocks.map((b) => [b.code.toUpperCase(), b]));
  const conhecidos = new Set(plan.blocks.map((b) => b.code.toUpperCase()));
  const partes = itens(resposta, citacoes, conhecidos);

  // 1. Identidade + proveniência: o valor escrito ao lado de um código tem de
  //    ser DAQUELE código, e tem de estar na evidência que o item citou.
  //    O dono do item é o código escrito nele; sem nenhum, o do cabeçalho
  //    do bloco. Dois códigos escritos continuam sem dono único.
  let conferidos = 0;
  for (const item of partes) {
    const codigos = codigosDoItem(item.texto, conhecidos);
    const dono = codigos.length === 1
      ? codigos[0]!.code
      : codigos.length === 0 && item.contexto !== null
      ? item.contexto
      : null;
    if (dono === null) continue;   // item sem dono único não afirma identidade
    const bloco = porCodigo.get(dono.toUpperCase())!;
    const linhasDele = linesForCode(bloco.code, plan.spec.codes, evidencias);
    const pares = extractUnitPairs(item.texto).filter((p) => UNIDADES_DE_LINHA.has(p.unidade));

    for (const par of pares) {
      conferidos += 1;
      // (a) existe uma linha DESSE código com esse valor — e quais evidências a têm
      const provam = new Set<number>([
        ...bloco.values
          .filter((v) => v.numero === par.numero && v.unidade === par.unidade)
          .map((v) => v.evidenceIndex),
        ...linhasDele
          .filter((l) => contemLiteral(l.texto, `${par.numero} ${par.unidade}`))
          .map((l) => l.evidenceIndex),
      ]);
      if (provam.size === 0) {
        failures.push(
          `valor de outro produto atribuído a ${bloco.code}: "${par.numero} ${par.unidade}" não está em nenhuma linha desse código`,
        );
        continue;
      }
      // (b) e o item citou pelo menos uma dessas evidências. Citar OUTRA que
      //     por acaso tem o mesmo número é a prova cruzada, e é o que fecha aqui.
      if (item.evidencias.size > 0 && ![...provam].some((i) => item.evidencias.has(i))) {
        failures.push(
          `${bloco.code}: "${par.numero} ${par.unidade}" existe na documentação, mas não na evidência citada nesse item (${item.citadas.map((c) => `[${c}]`).join("") || "nenhuma"})`,
        );
      }
    }

    if (bloco.missing && pares.length > 0) {
      failures.push(`${bloco.code} não tem evidência para o que foi pedido, mas a resposta apresenta valor para ele`);
    }
  }

  // 1b. Diferença escrita = diferença calculada, e citada de onde saiu. Um
  //     número que por acaso existe noutra linha da tabela (0,86 L/min é a
  //     MJ981CAP a 3,45 bar) passaria no grounding e mentiria aqui.
  //     O ponto que a PERGUNTA fixou ("a 40 psi") não é diferença: é o lugar
  //     da tabela onde as parcelas foram lidas, e a frase "a diferença a 40
  //     psi é de 0,76 L/min" o repete de propósito. Só esse literal — o da
  //     pergunta, escrito igual — fica de fora; "30 psi" numa frase de
  //     diferença continua sendo lido como diferença anunciada.
  const fixados = new Set(plan.spec.pinned.flatMap((p) => [`${p.numero} ${p.unidade}`, `${p.numero}${p.unidade}`]));
  for (const item of partes) {
    if (!/diferen[çc]a|a mais|a menos|por cento|percentual/i.test(item.texto)) continue;
    for (const par of extractUnitPairs(item.texto)) {
      if (!UNIDADES_DE_LINHA.has(par.unidade) && par.unidade !== "%") continue;
      const texto = `${par.numero} ${par.unidade}`;
      const colado = `${par.numero}${par.unidade}`;
      if (fixados.has(texto)) continue;
      const casa = plan.derived.filter((d) => d.texto === texto || d.texto === colado);
      if (casa.length === 0) {
        failures.push(
          plan.derived.length === 0
            ? `a resposta anuncia "${texto}" como diferença, e o sistema não calculou diferença nenhuma`
            : `diferença "${texto}" não confere com o cálculo do sistema (${plan.derived.map((d) => d.texto).join(", ")})`,
        );
        continue;
      }
      // A conta é de parcelas que estavam em evidências concretas. Escrever o
      // resultado sem citá-las é apresentar um total sem as parcelas.
      if (item.evidencias.size === 0) continue;   // parágrafo sem citação: o grounding já reprova
      const cobre = casa.some((d) =>
        [...new Set(d.sources.map((f) => f.evidenceIndex))].every((i) => item.evidencias.has(i)),
      );
      if (!cobre) {
        const exigidas = [...new Set(casa[0]!.sources.map((f) => f.evidenceIndex))];
        const nomes = exigidas
          .map((i) => citacoes.find((c) => c.evidenceIndex === i))
          .map((c) => (c ? `[${c.index}]` : "?"))
          .join("");
        failures.push(
          `a diferença "${texto}" foi calculada sobre ${casa[0]!.sources.map((f) => `${f.code} ${f.numero} ${f.unidade}`).join(" e ")}, e o item não cita ${nomes} — cita ${item.citadas.map((c) => `[${c}]`).join("") || "nada"}`,
        );
      }
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

  // 4. Maior, menor e igual: relação numérica, decidida aqui.
  const relacao = relate(plan);
  const claims = claimsDe(partes, conhecidos);
  const intencao = parseRelationalIntent(pergunta);

  if (relacao.status === "ready") {
    for (const c of claims) {
      if (c.tipo === "igual") {
        if (!relacao.todosIguais) {
          failures.push(
            `a resposta diz que são iguais, e os valores diferem (${relacao.ordem.map((o) => `${o.code} ${o.numero} ${relacao.unidade}`).join(" · ")})`,
          );
        }
        continue;
      }
      if (relacao.todosIguais) {
        failures.push(
          `a resposta declara ${c.code} como ${c.tipo}, e os valores são iguais (${relacao.ordem.map((o) => `${o.code} ${o.numero}`).join(" = ")} ${relacao.unidade})`,
        );
        continue;
      }
      const certos = c.tipo === "maior" ? relacao.maiores : relacao.menores;
      if (c.code !== undefined && !certos.some((x) => x.toUpperCase() === c.code!.toUpperCase())) {
        failures.push(
          `a resposta aponta ${c.code} como ${c.tipo} e o ${c.tipo} é ${certos.join(", ")} (${relacao.ordem.map((o) => `${o.code} ${o.numero} ${relacao.unidade}`).join(" > ")})`,
        );
      }
    }
    if (intencao !== null && claims.length === 0) {
      const esperado = intencao === "greater" ? relacao.maiores : relacao.menores;
      failures.push(
        relacao.todosIguais
          ? "a pergunta pede qual é o maior ou o menor, os valores são iguais e a resposta não diz isso"
          : `a pergunta pede qual é o ${intencao === "greater" ? "maior" : "menor"} e a resposta não aponta nenhum (é ${esperado.join(", ")})`,
      );
    }
  } else {
    // Sem relação calculável — comparação incompleta, unidades diferentes,
    // mais de um valor por produto — nenhuma conclusão de ordem se sustenta.
    for (const c of claims) {
      if (c.tipo === "igual") continue;
      failures.push(
        `a resposta declara ${c.code ?? "um produto"} como ${c.tipo}, e o sistema não tem base para ordenar: ${relacao.reason}`,
      );
    }
  }

  return failures.length === 0 ? { status: "ok", checked: conferidos } : { status: "failed", failures };
}
