/**
 * Validação estrutural da carga de catálogo, ANTES de gerar SQL.
 *
 *   node supabase/importacao/validar.mjs
 *
 * Lê `dados/integrar_supabase.csv` (a aba INTEGRAR_SUPABASE da planilha,
 * exportada tal e qual) e `dados/rastreabilidade.csv`. Não fala com banco
 * nenhum: são as regras que a planilha e o schema já impõem, conferidas
 * fora do Excel, onde dá para versionar o resultado.
 *
 * Uma linha rejeitada aqui não vira SQL. A carga é tudo ou nada.
 */
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const AQUI = dirname(fileURLToPath(import.meta.url));

/** CSV com aspas duplas, como o Excel exporta. */
export function lerCsv(caminho) {
  const texto = readFileSync(caminho, "utf8").replace(/^﻿/, "");
  const linhas = [];
  let campo = "";
  let linha = [];
  let aspas = false;
  for (let i = 0; i < texto.length; i += 1) {
    const c = texto[i];
    if (aspas) {
      if (c === '"' && texto[i + 1] === '"') { campo += '"'; i += 1; }
      else if (c === '"') aspas = false;
      else campo += c;
    } else if (c === '"') aspas = true;
    else if (c === ",") { linha.push(campo); campo = ""; }
    else if (c === "\n") { linha.push(campo); linhas.push(linha); linha = []; campo = ""; }
    else if (c !== "\r") campo += c;
  }
  if (campo !== "" || linha.length) { linha.push(campo); linhas.push(linha); }
  const [cabecalho, ...corpo] = linhas;
  return corpo
    .filter((l) => l.some((v) => v !== ""))
    .map((l) => Object.fromEntries(cabecalho.map((h, i) => [h, (l[i] ?? "").trim()])));
}

/** Marcas e categorias que o seed do banco cria. Fonte: migration 0900. */
export const MARCAS_NO_SEED = ["AGROTORK", "DJI", "KUHN", "BALDAN", "ARAG", "MAGNOJET", "TRIMBLE", "AGRES"];
export const CATEGORIAS_NO_SEED = [
  "Implementos", "Peças", "Pulverização", "Tecnologia",
  "Agricultura de Precisão", "Serviços", "Acessórios",
];
export const UNIDADES_NO_SEED = ["UN", "KG", "L", "M", "JG", "CJ", "PC", "HR", "SERV"];

const RE_CODE = /^[A-Za-z0-9][A-Za-z0-9._/-]*$/;   // igual ao Zod de products/schema.ts
const RE_INTEIRO = /^\d+$/;
const RE_DATA = /^\d{4}-\d{2}-\d{2}$/;

export function validar(carga, trilha) {
  const erros = [];
  const avisos = [];
  const reprova = (id, regra, detalhe) => erros.push({ id, regra, detalhe });
  const avisa = (id, regra, detalhe) => avisos.push({ id, regra, detalhe });

  const vistos = new Map();
  const idsTrilha = new Set(trilha.map((t) => t.PRODUTO_ID_ORIGEM));
  const marcasNecessarias = new Set();
  const categoriasNecessarias = new Set();

  for (const l of carga) {
    const id = l.CODIGO_SISTEMA || l.PRODUTO_ID_ORIGEM || "(sem id)";

    if (l.IMPORTAR !== "SIM") { reprova(id, "escopo", `IMPORTAR = ${l.IMPORTAR || "(vazio)"} na aba de carga`); continue; }

    // ── identidade ──
    if (!l.CODIGO_SISTEMA) reprova(id, "code", "CODIGO_SISTEMA vazio");
    else if (!RE_CODE.test(l.CODIGO_SISTEMA)) reprova(id, "code", `"${l.CODIGO_SISTEMA}" não passa no formato aceito pelo cadastro`);
    else if (l.CODIGO_SISTEMA.length > 40) reprova(id, "code", "acima de 40 caracteres");
    const chave = l.CODIGO_SISTEMA.toUpperCase();
    if (vistos.has(chave)) reprova(id, "code", `duplicado de ${vistos.get(chave)} (o índice é unique(upper(code)))`);
    else vistos.set(chave, id);

    if (!l.NOME_PADRONIZADO) reprova(id, "name", "NOME_PADRONIZADO vazio");
    else if (l.NOME_PADRONIZADO.length > 180) reprova(id, "name", "acima de 180 caracteres");
    if ((l.OBSERVACAO ?? "").length > 2000) reprova(id, "notes", "OBSERVACAO acima de 2000 caracteres");

    // ── a trava que quebra a carga: código de fábrica exige marca ──
    if (l.CODIGO_FABRICANTE && !l.MARCA) {
      reprova(id, "chk_products_manufacturer_brand", "CODIGO_FABRICANTE preenchido sem MARCA");
    }
    if (l.CODIGO_FABRICANTE && l.CODIGO_FABRICANTE.length > 60) reprova(id, "manufacturer_code", "acima de 60 caracteres");
    if (l.MARCA) marcasNecessarias.add(l.MARCA);
    if (l.CATEGORIA_AGROTORK) categoriasNecessarias.add(l.CATEGORIA_AGROTORK);

    // ── unidade é o único FK obrigatório ──
    if (!l.UNIDADE) reprova(id, "unit_id", "UNIDADE vazia (unit_id é not null)");
    else if (!UNIDADES_NO_SEED.includes(l.UNIDADE)) reprova(id, "unit_id", `unidade "${l.UNIDADE}" não existe no cadastro`);

    if (l.CATEGORIA_AGROTORK && !CATEGORIAS_NO_SEED.includes(l.CATEGORIA_AGROTORK)) {
      reprova(id, "category_id", `categoria "${l.CATEGORIA_AGROTORK}" não existe no cadastro`);
    }

    // ── preço de venda nunca é inferido ──
    if (l.PRECO_VENDA !== "") reprova(id, "sale_price", `PRECO_VENDA preenchido (${l.PRECO_VENDA}); a carga entra sem preço de venda`);
    if (l.IS_ACTIVE_NA_IMPORTACAO !== "NAO") reprova(id, "is_active", `IS_ACTIVE_NA_IMPORTACAO = ${l.IS_ACTIVE_NA_IMPORTACAO || "(vazio)"}; a carga entra inativa`);

    // ── custo por condição ──
    const av = l.CUSTO_A_VISTA;
    const fat = l.CUSTO_FATURADO;
    for (const [campo, v] of [["CUSTO_A_VISTA", av], ["CUSTO_FATURADO", fat]]) {
      if (v !== "" && !/^\d+(\.\d+)?$/.test(v)) reprova(id, "cost_price", `${campo} não é número: "${v}"`);
      if (v !== "" && Number(v) < 0) reprova(id, "cost_price", `${campo} negativo`);
    }
    const cond = l.CONDICAO_CUSTO;
    const esperada = av !== "" && fat !== "" ? "AVISTA + FATURADO" : av !== "" ? "AVISTA" : fat !== "" ? "FATURADO" : "SEM CUSTO";
    if (cond !== esperada) reprova(id, "condition_id", `CONDICAO_CUSTO diz "${cond}" mas os valores dizem "${esperada}"`);

    if (!RE_DATA.test(l.VIGENCIA_INICIO)) reprova(id, "valid_from", `VIGENCIA_INICIO inválida: "${l.VIGENCIA_INICIO}"`);

    // PRECO_REVENDA_JR é rastreabilidade: se divergir do custo à vista,
    // não dá para escolher a fonte canônica sozinho.
    if (l.PRECO_REVENDA_JR !== "" && l.PRECO_REVENDA_JR !== av) {
      reprova(id, "custo duplicado", `PRECO_REVENDA_JR (${l.PRECO_REVENDA_JR}) diverge de CUSTO_A_VISTA (${av}); decida a fonte canônica`);
    }

    // ── procedência ──
    if (l.SOURCE_TYPE !== "price_list") reprova(id, "source_type", `SOURCE_TYPE = "${l.SOURCE_TYPE}"; a carga é de tabela de preços`);

    // ── NCM é campo fiscal, não texto livre ──
    if (l.NCM !== "" && !(RE_INTEIRO.test(l.NCM) && l.NCM.length === 8)) {
      avisa(id, "ncm", `NCM "${l.NCM}" não tem 8 dígitos; será descartado`);
    }

    // ── rastreabilidade ──
    if (!idsTrilha.has(l.PRODUTO_ID_ORIGEM)) reprova(id, "rastreabilidade", "sem linha correspondente na trilha");
  }

  // Marca ausente do seed não é linha inválida: é PRÉ-REQUISITO. O SQL da
  // carga cria as marcas que faltam na mesma transação, antes de resolver
  // o brand_id — e é isso que impede `manufacturer_code` com marca nula.
  const marcasFaltando = [...marcasNecessarias].filter((m) => !MARCAS_NO_SEED.includes(m)).sort();
  const comCodigoDeFabrica = new Set(
    carga.filter((l) => l.CODIGO_FABRICANTE && marcasFaltando.includes(l.MARCA)).map((l) => l.MARCA),
  );

  return {
    erros,
    avisos,
    marcasFaltando,
    marcasQueBloqueiam: [...comCodigoDeFabrica].sort(),
    categoriasUsadas: [...categoriasNecessarias].sort(),
  };
}

export function resumo(carga) {
  const num = (v) => (v === "" ? null : Number(v));
  let av = 0, fat = 0, ambos = 0, sem = 0;
  for (const l of carga) {
    const a = num(l.CUSTO_A_VISTA) !== null;
    const f = num(l.CUSTO_FATURADO) !== null;
    if (a) av += 1;
    if (f) fat += 1;
    if (a && f) ambos += 1;
    if (!a && !f) sem += 1;
  }
  return { total: carga.length, avista: av, faturado: fat, ambos, semCusto: sem };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const carga = lerCsv(join(AQUI, "dados", "integrar_supabase.csv"));
  const trilha = lerCsv(join(AQUI, "dados", "rastreabilidade.csv"));
  const { erros, avisos, marcasFaltando, marcasQueBloqueiam, categoriasUsadas } = validar(carga, trilha);
  const r = resumo(carga);

  console.log("── CARGA DE CATÁLOGO — VALIDAÇÃO ESTRUTURAL ──");
  console.log(`produtos na carga............. ${r.total}`);
  console.log(`com custo à vista............. ${r.avista}`);
  console.log(`com custo faturado............ ${r.faturado}`);
  console.log(`com as duas condições......... ${r.ambos}`);
  console.log(`sem nenhum custo.............. ${r.semCusto}`);
  console.log(`linhas na trilha.............. ${trilha.length}`);
  console.log(`categorias usadas............. ${categoriasUsadas.join(", ") || "(nenhuma)"}`);
  console.log(`marcas a cadastrar antes...... ${marcasFaltando.join(", ") || "(nenhuma)"}`);
  if (marcasQueBloqueiam.length) {
    console.log(`  destas, BLOQUEIAM a carga.... ${marcasQueBloqueiam.join(", ")}`);
    console.log("  (há CODIGO_FABRICANTE nessas linhas; sem brand_id o banco recusa por chk_products_manufacturer_brand)");
  }
  if (avisos.length) {
    console.log(`\nAVISOS (${avisos.length}) — não impedem a carga:`);
    for (const a of avisos) console.log(`  ${a.id} · ${a.regra}: ${a.detalhe}`);
  }
  if (erros.length) {
    console.log(`\nREJEITADAS (${erros.length}):`);
    for (const e of erros) console.log(`  ${e.id} · ${e.regra}: ${e.detalhe}`);
    console.log("\n✖ a carga NÃO pode ser gerada enquanto houver linha rejeitada.");
    process.exit(1);
  }
  console.log("\n✔ nenhuma linha rejeitada.");
}
