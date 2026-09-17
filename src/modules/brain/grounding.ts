import type { KnowledgeEvidence } from "./evidence";

/**
 * Grounding determinístico: números, unidades e códigos da resposta têm de
 * existir, LITERALMENTE, nas evidências citadas naquele mesmo parágrafo.
 *
 * Por que isto existe. Até a auditoria de 17/09, o validador conferia que a
 * citação existia — e só. Uma resposta como "a vazão é 0,99 L/min [1]"
 * passava, mesmo com a evidência dizendo 0,77, porque `[1]` era uma citação
 * legítima. A proibição de trocar número estava no prompt, isto é, dependia
 * de o modelo obedecer. Para preço, vazão, pressão e código de peça isso não
 * serve: é a classe de erro que chega ao cliente como se fosse informação da
 * AGROTORK.
 *
 * O que este arquivo faz é trocar "o modelo foi instruído a não inventar"
 * por "o número não passa se não estiver no documento".
 *
 * O que ele NÃO faz, e está escrito para não virar promessa: não entende a
 * frase. Se o documento diz que a vazão é 0,77 e a pressão 40, e o modelo
 * troca os papéis dizendo "pressão de 0,77 bar", a associação número+unidade
 * pega o caso (0,77 bar não existe no documento) — mas uma troca sem unidade
 * explícita, ou uma inferência errada entre dois números que ambos existem,
 * continua sendo responsabilidade do modelo e do prompt. A fronteira está em
 * `docs/brain/fase-2-answer-v1.md`.
 */

// ════════════════════════════════════════════════════════════
// Unidades
// ════════════════════════════════════════════════════════════

/**
 * As unidades que aparecem nos documentos da AGROTORK. A ordem importa: a
 * alternância do regex é testada da esquerda para a direita, então a mais
 * longa vem primeiro — sem isso, `L/min` casaria só o `L` e `km/h` só o `km`.
 */
const UNIDADES = [
  "L/min", "L/ha", "km/h", "kPa", "MPa", "kW", "mL", "mm", "cm", "km", "kg",
  "rpm", "psi", "bar", "ha", "L", "m", "g", "V", "A", "W", "%",
];

const MOEDAS = ["R$", "US$", "$"];

const escapa = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

/**
 * Um literal numérico: dígitos podendo carregar vírgula e ponto no meio,
 * nunca nas pontas. "0,77" sai inteiro; "0,77." sai sem o ponto final.
 */
const NUMERO = String.raw`\d(?:[\d.,]*\d)?`;

/**
 * Literal numérico SOLTO. As duas fronteiras existem por motivos diferentes:
 *
 *  · à direita, não pode vir letra — senão o "982" de "MJ982CAP" viraria um
 *    número reprovado, e a mensagem culparia um número que ninguém escreveu.
 *    Dentro de um token alfanumérico quem manda é a regra de código;
 *  · à esquerda, não pode vir letra, dígito, vírgula nem ponto — sem o dígito
 *    ali, o motor que desiste no "9" de "MJ981CAP" tenta de novo no "8" e
 *    extrai "81", um número que também não existe no texto.
 */
const RE_NUMERO = new RegExp(`(?<![A-Za-zÀ-ÿ0-9.,])(${NUMERO})(?![A-Za-zÀ-ÿ])`, "g");

/** Número seguido de unidade, com a fronteira à direita fechada. */
const RE_NUM_UNIDADE = new RegExp(
  `(${NUMERO})\\s*(${UNIDADES.map(escapa).join("|")})(?![A-Za-zÀ-ÿ0-9])`,
  "g",
);

/** Moeda antes do número — "R$ 1.250,00". */
const RE_MOEDA = new RegExp(`(${MOEDAS.map(escapa).join("|")})\\s*(${NUMERO})`, "g");

/**
 * Perfil de código. Duas formas, e as duas exigem dígito:
 *
 *  · letras E dígitos, com 3 caracteres ou mais — MJ981CAP, T70P, V41;
 *  · só dígitos, com 5 ou mais — 466113200, 4626215.
 *
 * O corte em 5 dígitos separa código de número: 40, 77, 2026 e 1250 são
 * quantidades, e já respondem pela regra dos literais. Abaixo de 3
 * caracteres não há código de peça — e "1a", "2ª" ficam de fora, que é o
 * que se quer.
 */
const RE_TOKEN = /[A-Za-z0-9][A-Za-z0-9-]*/g;

export function pareceCodigo(token: string): boolean {
  const temDigito = /\d/.test(token);
  if (!temDigito) return false;
  const temLetra = /[A-Za-z]/.test(token);
  if (temLetra) return token.length >= 3;
  return token.replace(/\D/g, "").length >= 5;
}

/**
 * Os pares número + unidade de um texto, na ordem em que aparecem. Mesma
 * regra que a conferência usa — exportada para a checagem de exaustão
 * (`exhaustiveness.ts`) não ter um segundo jeito de ler "2,07 bar".
 */
/** Os literais numéricos soltos de um texto — mesma fronteira da conferência. */
export function extractNumbers(texto: string): string[] {
  return [...texto.matchAll(RE_NUMERO)].map((m) => m[1] ?? m[0]);
}

export function extractUnitPairs(texto: string): { numero: string; unidade: string }[] {
  return [...texto.matchAll(RE_NUM_UNIDADE)].map((m) => ({ numero: m[1] ?? "", unidade: m[2] ?? "" }));
}

// ════════════════════════════════════════════════════════════
// O que a evidência sustenta
// ════════════════════════════════════════════════════════════

const espacos = (s: string) => s.replace(/\s+/g, " ").trim();

/**
 * O palheiro de uma evidência: exatamente o que o modelo recebeu, nada além.
 *
 * Inclui `version.label`, página e a citação porque o modelo tem direito de
 * escrever "na V41" e "p. 20" — são fatos que estavam na frente dele. NÃO
 * inclui `documentId`, `versionId`, `storage_path` nem `sha256`: se um deles
 * aparecesse na resposta, o validador já rejeita por outro motivo, e tê-los
 * no palheiro os transformaria em texto sustentado.
 */
export function haystackOf(e: KnowledgeEvidence): string {
  return espacos(
    [
      e.content,
      e.codes.join(" "),
      e.headingPath.join(" "),
      e.source,
      e.document.title,
      e.version.label,
      String(e.page.from),
      String(e.page.to),
      e.citation,
    ].join(" \n "),
  );
}

/**
 * O literal existe no palheiro COMO NÚMERO INTEIRO, não como pedaço de
 * outro. É o que impede "77" de se dar por sustentado dentro de "0,77" —
 * são números diferentes, e tratá-los como o mesmo seria justamente o erro
 * que este arquivo existe para pegar.
 */
export function contemLiteral(palheiro: string, literal: string): boolean {
  let de = palheiro.indexOf(literal);
  while (de !== -1) {
    const antes = de === 0 ? "" : (palheiro[de - 1] ?? "");
    const depois = palheiro[de + literal.length] ?? "";
    const antesDoAntes = de >= 2 ? (palheiro[de - 2] ?? "") : "";
    const depoisDoDepois = palheiro[de + literal.length + 1] ?? "";
    const coladoAntes = /\d/.test(antes) || ((antes === "," || antes === ".") && /\d/.test(antesDoAntes));
    const coladoDepois = /\d/.test(depois) || ((depois === "," || depois === ".") && /\d/.test(depoisDoDepois));
    if (!coladoAntes && !coladoDepois) return true;
    de = palheiro.indexOf(literal, de + 1);
  }
  return false;
}

/** Igual ao anterior, mas para texto: fronteira de palavra dos dois lados. */
export function contemToken(palheiro: string, token: string): boolean {
  const re = new RegExp(`(?<![A-Za-zÀ-ÿ0-9-])${escapa(token)}(?![A-Za-zÀ-ÿ0-9-])`, "i");
  return re.test(palheiro);
}

// ════════════════════════════════════════════════════════════
// A conferência
// ════════════════════════════════════════════════════════════

export type GroundingFailure = {
  paragrafo: number;
  tipo: "sem_citacao" | "numero" | "numero_unidade" | "codigo";
  achado: string;
  citadas: number[];
};

export type GroundingResult = { ok: true } | { ok: false; failures: GroundingFailure[] };

/** Os números entre colchetes de UM trecho de texto. */
function citacoesDoTrecho(trecho: string): number[] {
  const achados = new Set<number>();
  for (const m of trecho.matchAll(/\[(\d{1,3})\]/g)) achados.add(Number(m[1]));
  return [...achados].sort((a, b) => a - b);
}

/** Parágrafo com alguma letra ou dígito — linha em branco não conta. */
const temSubstancia = (p: string) => /[A-Za-zÀ-ÿ0-9]/.test(p);

/**
 * Confere o texto inteiro, parágrafo a parágrafo.
 *
 * Parágrafo é a unidade porque é determinística: quebra dupla de linha, sem
 * depender de separar frases em português, que é onde um validador começa a
 * chutar. Duas afirmações no mesmo parágrafo compartilham as citações dele —
 * é conservador na direção certa, porque o conjunto de evidências exigido
 * fica MENOR quanto mais o modelo separa em parágrafos.
 */
export function checkGrounding(
  texto: string,
  citacoes: { index: number; evidenceIndex: number }[],
  evidencias: KnowledgeEvidence[],
): GroundingResult {
  const porIndice = new Map(citacoes.map((c) => [c.index, evidencias[c.evidenceIndex]]));
  const failures: GroundingFailure[] = [];

  const paragrafos = texto.split(/\n\s*\n/);

  paragrafos.forEach((bruto, i) => {
    if (!temSubstancia(bruto)) return;
    const n = i + 1;

    const citadas = citacoesDoTrecho(bruto);
    if (citadas.length === 0) {
      failures.push({ paragrafo: n, tipo: "sem_citacao", achado: espacos(bruto).slice(0, 60), citadas: [] });
      return;
    }

    const palheiros = citadas
      .map((c) => porIndice.get(c))
      .filter((e): e is KnowledgeEvidence => Boolean(e))
      .map(haystackOf);
    if (palheiros.length === 0) return;   // citação inexistente: outro teste pega

    const sustentado = (valor: string, comparador: (p: string, v: string) => boolean) =>
      palheiros.some((p) => comparador(p, valor));

    // Os marcadores [1], [2] são ponteiros, não fatos: saem antes de
    // qualquer extração, senão o "1" viraria um número a sustentar.
    const corpo = espacos(bruto.replace(/\[\d{1,3}\]/g, " "));

    // 1. par número + unidade — "0,77 L/min" tem de existir JUNTO
    const paresOk = new Set<string>();
    for (const m of corpo.matchAll(RE_NUM_UNIDADE)) {
      const numero = m[1] ?? "";
      const unidade = m[2] ?? "";
      const par = `${numero} ${unidade}`;
      const colado = `${numero}${unidade}`;
      if (sustentado(par, contemLiteral) || sustentado(colado, contemLiteral)) {
        paresOk.add(numero);
        continue;
      }
      failures.push({ paragrafo: n, tipo: "numero_unidade", achado: par, citadas });
      paresOk.add(numero);   // já reprovado como par; não reprovar de novo como literal
    }

    // 2. moeda + número — "R$ 1.250,00"
    for (const m of corpo.matchAll(RE_MOEDA)) {
      const moeda = m[1] ?? "";
      const numero = m[2] ?? "";
      const par = `${moeda} ${numero}`;
      const colado = `${moeda}${numero}`;
      if (sustentado(par, contemLiteral) || sustentado(colado, contemLiteral)) {
        paresOk.add(numero);
        continue;
      }
      failures.push({ paragrafo: n, tipo: "numero_unidade", achado: par, citadas });
      paresOk.add(numero);
    }

    // 3. literais numéricos soltos
    for (const m of corpo.matchAll(RE_NUMERO)) {
      const numero = m[0];
      if (paresOk.has(numero)) continue;
      if (!sustentado(numero, contemLiteral)) {
        failures.push({ paragrafo: n, tipo: "numero", achado: numero, citadas });
      }
    }

    // 4. códigos e modelos
    for (const m of corpo.matchAll(RE_TOKEN)) {
      const token = m[0];
      if (!pareceCodigo(token)) continue;
      if (!sustentado(token, contemToken)) {
        failures.push({ paragrafo: n, tipo: "codigo", achado: token, citadas });
      }
    }
  });

  return failures.length === 0 ? { ok: true } : { ok: false, failures };
}

/** Uma linha legível para o log e para o aviso na tela. */
export function describeFailure(f: GroundingFailure): string {
  const onde = `parágrafo ${f.paragrafo}`;
  const refs = f.citadas.length > 0 ? ` (citou ${f.citadas.map((c) => `[${c}]`).join("")})` : "";
  switch (f.tipo) {
    case "sem_citacao":
      return `${onde} afirma sem citar: "${f.achado}…"`;
    case "numero":
      return `${onde}: o número ${f.achado} não está na evidência citada${refs}`;
    case "numero_unidade":
      return `${onde}: "${f.achado}" não aparece assim na evidência citada${refs}`;
    case "codigo":
      return `${onde}: o código ${f.achado} não está na evidência citada${refs}`;
  }
}
