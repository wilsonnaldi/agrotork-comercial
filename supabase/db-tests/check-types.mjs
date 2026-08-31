/**
 * Compara o schema real (dumps em /tmp) com a tipagem do projeto.
 *
 * Não é um parser de TypeScript: lê os arquivos como texto e confere
 * presença. É o suficiente para pegar os erros que importam — uma coluna
 * que existe no banco e não existe no tipo, e as duas listas escritas à
 * mão em `src/types/db.ts` que o compilador não tem como validar sozinho.
 */
import { readFileSync } from "node:fs";
import { execSync } from "node:child_process";

const tipos = readFileSync(new URL("../../src/types/database.types.ts", import.meta.url), "utf8");
const dominio = readFileSync(new URL("../../src/types/db.ts", import.meta.url), "utf8");
const problemas = [];
const avisos = [];

// ── Tabelas e colunas ────────────────────────────────────────
const linhas = readFileSync("/tmp/schema-real.txt", "utf8").trim().split("\n").filter(Boolean);
const porTabela = new Map();
for (const linha of linhas) {
  const [tabela, coluna] = linha.split("|");
  if (!porTabela.has(tabela)) porTabela.set(tabela, []);
  porTabela.get(tabela).push(coluna);
}

/** Tabelas que o TypeScript não precisa conhecer, e por quê. */
const IGNORADAS = new Map([
  ["quote_sequences", "sequência interna: só a função next_quote_number toca nela"],
]);

for (const [tabela, colunas] of porTabela) {
  if (IGNORADAS.has(tabela)) continue;

  // A tabela precisa aparecer no bloco Tables/Views do Database.
  if (!new RegExp(`\\b${tabela}\\s*:`).test(tipos)) {
    problemas.push(`tabela/view "${tabela}" existe no banco e não está em Database`);
    continue;
  }
  for (const coluna of colunas) {
    if (!new RegExp(`\\b${coluna}\\??\\s*:`).test(tipos)) {
      problemas.push(`coluna ${tabela}.${coluna} existe no banco e não está nos tipos`);
    }
  }
}

// ── Enums ────────────────────────────────────────────────────
const enums = new Map();
for (const linha of readFileSync("/tmp/enums-real.txt", "utf8").trim().split("\n").filter(Boolean)) {
  const [nome, valor] = linha.split("|");
  if (!enums.has(nome)) enums.set(nome, []);
  enums.get(nome).push(valor);
}
for (const [nome, valores] of enums) {
  for (const valor of valores) {
    if (!tipos.includes(`"${valor}"`)) {
      problemas.push(`enum ${nome} tem o valor "${valor}" que não aparece nos tipos`);
    }
  }
}

// ── Funções chamadas por rpc() ───────────────────────────────
// O gerador lista TODAS as funções do schema public. O que interessa aqui
// é o contrário: as que a aplicação chama de fato precisam existir nos
// tipos (senão o cliente tipado recusa a chamada) e precisam ser security
// definer (senão o RLS derruba a chamada em produção, não no typecheck).
const definers = readFileSync("/tmp/definers-real.txt", "utf8").trim().split("\n").filter(Boolean);
const blocoFunctions = tipos.slice(tipos.indexOf("    Functions: {"), tipos.indexOf("    Enums: {"));
const nosTipos = [...blocoFunctions.matchAll(/^ {6}(\w+): \{$/gm)].map((m) => m[1]);

const fontes = execSync("grep -rho '\\.rpc(\"[a-z_]*\"' " + new URL("../../src", import.meta.url).pathname, {
  encoding: "utf8",
});
const chamadasRpc = [...new Set([...fontes.matchAll(/\.rpc\("([a-z_]+)"/g)].map((m) => m[1]))];

for (const fn of chamadasRpc) {
  if (!nosTipos.includes(fn)) {
    problemas.push(`a aplicação chama rpc("${fn}") e a função não está nos tipos`);
  }
  if (!definers.includes(fn)) {
    avisos.push(`rpc("${fn}") não é security definer no banco`);
  }
}

// ── Camada de domínio: listas escritas à mão em src/types/db.ts ──
//
// Para o TypeScript, `numeric` e `integer` são `number`, e trigger não
// existe. Estas duas listas são o único ponto do sistema onde essa
// diferença está registrada — então é aqui que ela precisa ser conferida.

/** Extrai `tabela: "a" | "b";` de um bloco de tipo do db.ts. */
function listaDoBloco(fonte, nomeDoTipo) {
  const inicio = fonte.indexOf(`type ${nomeDoTipo} = {`);
  if (inicio === -1) return null;
  const fim = fonte.indexOf("\n};", inicio);
  const bloco = fonte.slice(inicio, fim);
  const mapa = new Map();
  for (const m of bloco.matchAll(/^ {2}(\w+):\s*([^;]+);$/gm)) {
    mapa.set(m[1], [...m[2].matchAll(/"([^"]+)"/g)].map((x) => x[1]));
  }
  return mapa;
}

function parPorTabela(caminho) {
  const mapa = new Map();
  for (const linha of readFileSync(caminho, "utf8").trim().split("\n").filter(Boolean)) {
    const [tabela, coluna] = linha.split("|");
    if (!mapa.has(tabela)) mapa.set(tabela, new Set());
    mapa.get(tabela).add(coluna);
  }
  return mapa;
}

const numericoReal = parPorTabela("/tmp/numeric-real.txt");
const declaradoNumerico = listaDoBloco(dominio, "NumericColumnsByTable");
let numericasConferidas = 0;

if (!declaradoNumerico) {
  problemas.push("NumericColumnsByTable não foi encontrado em src/types/db.ts");
} else {
  // Toda coluna numeric precisa estar declarada — senão a escrita como
  // string decimal deixa de compilar sem ninguém entender por quê.
  for (const [tabela, colunas] of numericoReal) {
    for (const coluna of colunas) {
      numericasConferidas += 1;
      if (!(declaradoNumerico.get(tabela) ?? []).includes(coluna)) {
        problemas.push(`${tabela}.${coluna} é numeric no banco e falta em NumericColumnsByTable`);
      }
    }
  }
  // E nada pode estar declarado a mais.
  for (const [tabela, colunas] of declaradoNumerico) {
    for (const coluna of colunas) {
      if (!(numericoReal.get(tabela) ?? new Set()).has(coluna)) {
        problemas.push(`${tabela}.${coluna} está em NumericColumnsByTable e não é numeric no banco`);
      }
    }
  }
}

const obrigatoriaSemDefault = parPorTabela("/tmp/required-real.txt");
const declaradoTrigger = listaDoBloco(dominio, "TriggerOwned");
let triggersConferidos = 0;

if (!declaradoTrigger) {
  problemas.push("TriggerOwned não foi encontrado em src/types/db.ts");
} else {
  for (const [tabela, colunas] of declaradoTrigger) {
    for (const coluna of colunas) {
      triggersConferidos += 1;
      // Se a coluna ganhar um default, ela deixa de precisar do trigger na
      // tipagem — e continuar na lista esconderia o novo comportamento.
      if (!(obrigatoriaSemDefault.get(tabela) ?? new Set()).has(coluna)) {
        problemas.push(
          `${tabela}.${coluna} está em TriggerOwned mas não é "not null sem default" no banco`,
        );
      }
    }
  }
}

// ── Resultado ────────────────────────────────────────────────
console.log(`tabelas e views conferidas: ${porTabela.size} (${IGNORADAS.size} ignorada por decisão)`);
console.log(`colunas conferidas: ${linhas.length}`);
console.log(`enums conferidos: ${enums.size}`);
console.log(`funções security definer no banco: ${definers.length}`);
console.log(`chamadas rpc() conferidas: ${chamadasRpc.length} (${chamadasRpc.join(", ")})`);
console.log(`colunas numeric conferidas contra src/types/db.ts: ${numericasConferidas}`);
console.log(`colunas preenchidas por trigger conferidas: ${triggersConferidos}`);
for (const [tabela, motivo] of IGNORADAS) console.log(`  ignorada: ${tabela} — ${motivo}`);
for (const aviso of avisos) console.log(`  AVISO: ${aviso}`);

if (problemas.length > 0) {
  console.log("\nDIVERGÊNCIAS:");
  for (const problema of problemas) console.log(`  ✗ ${problema}`);
  process.exit(1);
}
console.log("\n✔ database.types.ts confere com o schema das migrations");
