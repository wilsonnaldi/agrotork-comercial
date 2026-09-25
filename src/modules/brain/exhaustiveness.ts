import type { KnowledgeEvidence } from "./evidence";
import { contemLiteral, contemToken, extractNumbers, extractUnitPairs, pareceCodigo } from "./grounding";

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

// ════════════════════════════════════════════════════════════
// Associação: cada item afirma valores da MESMA linha
// ════════════════════════════════════════════════════════════

/**
 * O buraco que a exaustão não fecha. Presença e pertencimento ao conjunto
 * não provam relação: a lista
 *
 *   2,07 bar -> 1,08 L/min
 *   2,76 bar -> 1,01 L/min   …
 *
 * tem todas as pressões e todas as vazões da MJ981CAP, nenhuma estranha —
 * e todos os pares errados. Para quem pergunta "qual vazão a qual pressão",
 * é o erro que importa.
 *
 * A regra, sem parser semântico:
 *
 *  1. a resposta é quebrada em ITENS — linha, ponto-e-vírgula ou fim de
 *     frase ("." seguido de espaço). Vírgula não quebra: é decimal;
 *  2. num item com par número+unidade de tabela (bar, psi, kPa, L/min, L/ha)
 *     e mais de um número, tudo o que ele escreve — os pares, os números
 *     soltos e os códigos de peça — tem de existir numa MESMA linha da
 *     evidência. "2,07 bar -> 1,08 L/min" só passa se houver uma linha com
 *     2,07 bar E 1,08 L/min;
 *  3. exceção explícita: item de UMA unidade só, em que todo número existe
 *     com essa unidade em alguma linha ("1,01 e 1,08 L/min", "2,07; 2,76 e
 *     3,45 bar") é enumeração de um campo, não relação entre campos;
 *  4. as linhas candidatas: as que trazem o código escrito no item; sem
 *     código no item, as do código da pergunta; sem nenhum dos dois, todas;
 *  5. só vale onde há TABELA: se nenhuma linha candidata traz duas unidades
 *     diferentes juntas, a evidência não tem linha para conferir relação
 *     (ficha técnica com um valor por linha) e o item não é julgado aqui.
 *
 * Roda depois do grounding e da exaustão. Não converte, não interpola.
 */

const UNIDADES_DE_LINHA = new Set(["bar", "psi", "kPa", "L/min", "L/ha"]);

/** Os itens de uma resposta, sem os marcadores [n]. */
export function answerItems(resposta: string): string[] {
  return resposta
    .replace(/\[\d{1,3}\]/g, " ")
    .split(/\r?\n|;|\.\s+/)
    .map((i) => i.replace(/\s+/g, " ").trim())
    .filter((i) => /\d/.test(i));
}

// ════════════════════════════════════════════════════════════
// Contexto de bloco: o cabeçalho empresta o código às linhas de baixo
// ════════════════════════════════════════════════════════════

/**
 * O formato que o prompt manda o modelo usar numa comparação é em BLOCOS:
 *
 *   MJ981CAP [1]:
 *   - 40 psi -> 0,77 L/min [1]
 *
 * A linha do valor não carrega o código — ele está na linha de cima. Até
 * 25/09 os dois gates que provam o vínculo produto → valor (associação e
 * comparação) olhavam cada linha sozinha: a do valor, sem código, caía nos
 * códigos da PERGUNTA (linha da tabela com os dois → nenhuma) e era
 * pulada. Valor errado, produto trocado e linha trocada passavam — no
 * formato oficial, o que o provedor escreve de fato.
 *
 * A regra aqui é estrutural, e só isso: um CABEÇALHO é uma linha que, sem
 * as citações, a ênfase de markdown e os dois-pontos finais, é exatamente
 * UM código conhecido. "MJ981CAP:", "MJ981CAP [1]:", "**MJ981CAP** [1][2]:"
 * são cabeçalhos; "A MJ981CAP tem maior vazão", "MJ981CAP e MJ985CAP:",
 * "Para MJ981CAP a 40 psi:" não são — prosa não cria contexto. O contexto
 * vale para as linhas seguintes até uma linha em branco ou outro cabeçalho,
 * e um código escrito na própria linha vence o herdado. Nada disto altera
 * o texto mostrado: é metadado de validação.
 */
export function blockHeaderCode(linha: string, conhecidos: Set<string>): string | null {
  const limpa = linha
    .replace(/\[\d{1,3}\]/g, " ")
    .replace(/^\s*[-•*]\s+/, " ")
    .replace(/[*_`#]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .replace(/:$/, "")
    .trim();
  if (!/^[A-Za-z0-9][A-Za-z0-9-]*$/.test(limpa)) return null;
  if (!pareceCodigo(limpa)) return null;
  const canonico = limpa.toUpperCase();
  return conhecidos.has(canonico) ? canonico : null;
}

export type ContextLine = { linha: string; contexto: string | null; cabecalho: boolean };

/** Cada linha da resposta com o código de bloco que vale para ela. */
export function blockContexts(resposta: string, conhecidos: Set<string>): ContextLine[] {
  let ativo: string | null = null;
  return resposta.split(/\r?\n/).map((linha) => {
    if (linha.trim().length === 0) {
      ativo = null;                       // linha em branco encerra o bloco
      return { linha, contexto: null, cabecalho: false };
    }
    const cabecalho = blockHeaderCode(linha, conhecidos);
    if (cabecalho !== null) {
      ativo = cabecalho;                  // novo cabeçalho substitui o anterior
      return { linha, contexto: cabecalho, cabecalho: true };
    }
    return { linha, contexto: ativo, cabecalho: false };
  });
}

export type ContextItem = { texto: string; contexto: string | null };

/**
 * `answerItems` com o contexto de bloco de cada item — a mesma quebra
 * (linha, ';', fim de frase), sem os [n], só itens com dígito.
 */
export function answerItemsWithContext(resposta: string, conhecidos: Set<string>): ContextItem[] {
  const saida: ContextItem[] = [];
  for (const { linha, contexto } of blockContexts(resposta, conhecidos)) {
    for (const bruto of linha.replace(/\[\d{1,3}\]/g, " ").split(/;|\.\s+/)) {
      const texto = bruto.replace(/\s+/g, " ").trim();
      if (/\d/.test(texto)) saida.push({ texto, contexto });
    }
  }
  return saida;
}

type Linha = { texto: string; pares: Set<string>; unidades: Set<string> };

const temPar = (linha: string, numero: string, unidade: string) =>
  contemLiteral(linha, `${numero} ${unidade}`) || contemLiteral(linha, `${numero}${unidade}`);

export type AssociationResult =
  | { status: "ok"; checked: number }
  | { status: "failed"; checked: number; failures: string[] };

/**
 * Um valor DERIVADO que o sistema calculou (ver `comparison.ts`): o literal
 * exato que a resposta pode escrever sem que ele exista numa linha do
 * documento. Só o texto interessa aqui — a proveniência (quais evidências o
 * parágrafo precisa citar) é conferida ANTES, pelo grounding, e este gate
 * não a repete.
 */
export type DerivedLiteral = { texto: string };

/**
 * Tira de um item os literais derivados, e SÓ eles — "0,76 L/min" e "98,7%"
 * saem; "40 psi", "0,86 L/min" e os códigos ficam, para a associação
 * conferir o que sobrou. As duas grafias do par (com e sem espaço antes da
 * unidade) são as mesmas que o grounding aceita. A fronteira é a de
 * `contemLiteral`: "0,76 L/min" não sai de dentro de "10,76 L/min".
 */
function semDerivados(item: string, derivados: DerivedLiteral[]): string {
  let texto = item;
  for (const d of derivados) {
    const pares = extractUnitPairs(d.texto);
    const formas = pares.length === 1 && pares[0]
      ? [`${pares[0].numero} ${pares[0].unidade}`, `${pares[0].numero}${pares[0].unidade}`]
      : [d.texto];
    for (const forma of formas) {
      let de = texto.indexOf(forma);
      while (de !== -1) {
        const antes = de === 0 ? "" : (texto[de - 1] ?? "");
        const depois = texto[de + forma.length] ?? "";
        const coladoAntes = /[\d.,]/.test(antes) && /\d/.test(texto[de - 2] ?? antes);
        const coladoDepois = /[\d.,]/.test(depois) && /\d/.test(texto[de + forma.length + 1] ?? depois);
        if (!coladoAntes && !coladoDepois) {
          texto = `${texto.slice(0, de)} ${texto.slice(de + forma.length)}`;
          de = texto.indexOf(forma, de);
        } else {
          de = texto.indexOf(forma, de + 1);
        }
      }
    }
  }
  return texto.replace(/\s+/g, " ").trim();
}

export function checkAssociation(
  pergunta: string,
  resposta: string,
  evidencias: KnowledgeEvidence[],
  /**
   * Os valores derivados que o plano de comparação calculou — os MESMOS que
   * o grounding recebeu, vindos do mesmo `planComparison()`. Sem eles (o
   * caso normal, fora de comparação) a regra é exatamente a de antes.
   *
   * Por que precisam chegar aqui: um derivado nasce de DUAS linhas — "0,76
   * L/min" é a MJ985CAP a 40 psi menos a MJ981CAP a 40 psi — e por
   * construção não existe em linha nenhuma. Exigir que ele apareça numa
   * única linha ao lado de "40 psi" contradiz o que o sistema acabou de
   * calcular: era o falso positivo que derrubava a comparação com percentual
   * mesmo com todos os números certos e citados. O derivado sai do item;
   * tudo o que sobra — pares documentais, números soltos, códigos — continua
   * submetido à mesma linha única de sempre.
   */
  derivados: DerivedLiteral[] = [],
): AssociationResult {
  const codigosDaPergunta = parseListingQuestion(pergunta).codes;
  const codigosConhecidos = new Set(evidencias.flatMap((e) => e.codes.map((c) => c.toUpperCase())));

  const linhas: Linha[] = [];
  for (const e of evidencias) {
    for (const bruta of e.content.split(/\r?\n/)) {
      const texto = bruta.replace(/\s+/g, " ").trim();
      const pares = extractUnitPairs(texto).filter((p) => UNIDADES_DE_LINHA.has(p.unidade));
      if (pares.length === 0) continue;
      linhas.push({
        texto,
        pares: new Set(pares.map((p) => `${p.numero} ${p.unidade}`)),
        unidades: new Set(pares.map((p) => p.unidade)),
      });
    }
  }

  const failures: string[] = [];
  let checked = 0;

  for (const { texto: bruto, contexto } of answerItemsWithContext(resposta, codigosConhecidos)) {
    // O derivado sai ANTES de contar pares e números: "a 40 psi é de 0,76
    // L/min e 98,7% a mais" vira "a 40 psi é de e a mais", que é o ponto de
    // operação sozinho — sem segundo número, não há relação a conferir.
    const item = derivados.length > 0 ? semDerivados(bruto, derivados) : bruto;
    const pares = extractUnitPairs(item).filter((p) => UNIDADES_DE_LINHA.has(p.unidade));
    if (pares.length === 0) continue;
    const numeros = extractNumbers(item);
    if (numeros.length < 2) continue;

    const codigosDoItem = [
      ...new Set(
        [...item.matchAll(/[A-Za-z0-9][A-Za-z0-9-]*/g)]
          .map((m) => m[0])
          .filter((t) => pareceCodigo(t) && codigosConhecidos.has(t.toUpperCase())),
      ),
    ];
    // O sujeito: o código escrito no item; senão, o do cabeçalho do bloco;
    // senão, os da pergunta. A ordem importa — o explícito vence o herdado.
    const sujeito = codigosDoItem.length > 0
      ? codigosDoItem
      : contexto !== null
      ? [contexto]
      : codigosDaPergunta;
    const candidatas = sujeito.length > 0
      ? linhas.filter((l) => sujeito.every((c) => contemToken(l.texto, c)))
      : linhas;

    // Sem linha de tabela entre as candidatas, não há relação a conferir aqui.
    if (!candidatas.some((l) => l.unidades.size >= 2)) {
      if ((codigosDoItem.length > 0 || contexto !== null) && candidatas.length === 0 && linhas.some((l) => l.unidades.size >= 2)) {
        // O item põe um código (escrito ou herdado do cabeçalho) numa tabela
        // em que esse código não tem linha.
        checked += 1;
        failures.push(`associação sem lastro: "${bruto.slice(0, 60)}" — nenhuma linha traz ${sujeito.join(", ")} com esses valores`);
      }
      continue;
    }
    checked += 1;

    const unidades = new Set(pares.map((p) => p.unidade));
    if (unidades.size === 1) {
      const [u] = [...unidades] as [string];
      const enumeracao = numeros.every((n) => candidatas.some((l) => temPar(l.texto, n, u)));
      if (enumeracao) continue;
    }

    const mesmaLinha = candidatas.some(
      (l) =>
        pares.every((p) => l.pares.has(`${p.numero} ${p.unidade}`)) &&
        numeros.every((n) => contemLiteral(l.texto, n)),
    );
    if (!mesmaLinha) {
      const sujeitoTxt = sujeito.length > 0 ? ` de ${sujeito.join(", ")}` : "";
      failures.push(
        `associação sem lastro: "${bruto.slice(0, 60)}" — nenhuma linha${sujeitoTxt} traz ${pares
          .map((p) => `${p.numero} ${p.unidade}`)
          .join(" com ")}${numeros.length > pares.length ? " e os demais números do item" : ""}`,
      );
    }
  }

  return failures.length === 0 ? { status: "ok", checked } : { status: "failed", checked, failures };
}
