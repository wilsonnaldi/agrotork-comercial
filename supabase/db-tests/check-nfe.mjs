/**
 * Confere o leitor de NF-e (`src/modules/purchases/nfe.ts`).
 *
 *   node supabase/db-tests/check-nfe.mjs
 *
 * Por que existe: o leitor é a única peça do sistema que recebe arquivo
 * de terceiro. Um XML malformado, uma nota com um item só, um produto
 * "SEM GTIN" — tudo isso chega de fora e não passa por nenhuma regra do
 * banco. O que protege aqui é este arquivo.
 *
 * Como roda sem test runner: o projeto não tem um, e não vale adicionar
 * por três arquivos. O truque é o `--experimental-strip-types` do Node 22
 * — os `.ts` são copiados para uma pasta temporária com os apelidos `@/`
 * trocados por caminho relativo, e importados direto. Nada é instalado.
 */
import { mkdtempSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const AQUI = dirname(fileURLToPath(import.meta.url));
const RAIZ = join(AQUI, "..", "..");

const ARQUIVOS = {
  "nfe.ts": "src/modules/purchases/nfe.ts",
  "money.ts": "src/lib/format/money.ts",
  "quantity.ts": "src/lib/format/quantity.ts",
};

// A pasta temporária fica DENTRO do projeto de propósito: o Node resolve
// `fast-xml-parser` subindo diretórios até achar node_modules, e uma
// pasta em /tmp nunca chegaria lá (NODE_PATH não vale para ESM).
const destino = mkdtempSync(join(RAIZ, ".nfe-check-"));
for (const [nome, caminho] of Object.entries(ARQUIVOS)) {
  const fonte = readFileSync(join(RAIZ, caminho), "utf8")
    .replace(/from "@\/lib\/format\/money"/g, 'from "./money.ts"')
    .replace(/from "@\/lib\/format\/quantity"/g, 'from "./quantity.ts"');
  writeFileSync(join(destino, nome), fonte);
}

const { parseNfe, NfeParseError } = await import(
  pathToFileURL(join(destino, "nfe.ts")).href
);

let falhas = 0;
const ok = (t) => process.stdout.write(` ${t}\n`);
const nao = (t) => { falhas += 1; process.stdout.write(`  ✗ ${t}\n`); };

function confere(titulo, condicao, detalhe = "") {
  if (condicao) ok(`${titulo} — ${detalhe}`);
  else nao(`${titulo}${detalhe ? ` — ${detalhe}` : ""}`);
}

/** Nota completa: dois itens, frete, desconto, GTIN em um e não no outro. */
const NOTA = `<?xml version="1.0" encoding="UTF-8"?>
<nfeProc versao="4.00" xmlns="http://www.portalfiscal.inf.br/nfe">
 <NFe><infNFe Id="NFe41260311222333000181550010000555011000555018" versao="4.00">
  <ide><nNF>0055501</nNF><serie>1</serie><dhEmi>2026-09-01T14:32:00-03:00</dhEmi></ide>
  <emit>
    <CNPJ>11222333000181</CNPJ>
    <xNome>DISTRIBUIDORA EXEMPLO LTDA</xNome>
    <xFant>EXEMPLO</xFant>
    <enderEmit>
      <xLgr>Rua das Industrias</xLgr><nro>1200</nro>
      <xBairro>Distrito Industrial</xBairro><xMun>Curitiba</xMun>
      <UF>PR</UF><CEP>81450000</CEP><fone>4133334444</fone>
    </enderEmit>
    <IE>1234567890</IE>
  </emit>
  <det nItem="1"><prod>
    <cProd>0012</cProd><cEAN>7891234560017</cEAN>
    <xProd>BATERIA INTELIGENTE 6000MAH</xProd>
    <NCM>85076000</NCM><uCom>UN</uCom>
    <qCom>3.0000</qCom><vUnCom>1250.0000000000</vUnCom><vProd>3750.00</vProd>
  </prod></det>
  <det nItem="2"><prod>
    <cProd>HEL-9</cProd><cEAN>SEM GTIN</cEAN>
    <xProd>HELICE 21 POLEGADAS</xProd>
    <NCM>88073000</NCM><uCom>PC</uCom>
    <qCom>12.0000</qCom><vUnCom>63.3333333333</vUnCom><vProd>760.00</vProd>
  </prod></det>
  <total><ICMSTot>
    <vProd>4510.00</vProd><vFrete>180.50</vFrete>
    <vDesc>10.00</vDesc><vOutro>0.00</vOutro><vNF>4680.50</vNF>
  </ICMSTot></total>
 </infNFe></NFe>
</nfeProc>`;

process.stdout.write("▶ leitor de NF-e\n");

const nota = parseNfe(NOTA);

confere("XM1) chave, número e série",
  nota.key === "41260311222333000181550010000555011000555018" &&
  nota.number === "0055501" && nota.series === "1",
  `${nota.number}/${nota.series} · ${nota.key?.slice(0, 12)}…`);

// Os zeros à esquerda de "0055501" e de "0012" precisam sobreviver: o
// parser não pode transformar texto em número por conta própria.
confere("XM2) zeros à esquerda preservados",
  nota.number === "0055501" && nota.items[0].supplier_code === "0012",
  `nNF "${nota.number}" e cProd "${nota.items[0].supplier_code}"`);

confere("XM3) emissão vira data ISO",
  nota.issue_date === "2026-09-01", nota.issue_date);

confere("XM4) emitente completo",
  nota.supplier.document === "11222333000181" &&
  nota.supplier.legal_name === "DISTRIBUIDORA EXEMPLO LTDA" &&
  nota.supplier.city === "Curitiba" && nota.supplier.zip_code === "81450000",
  `${nota.supplier.legal_name} · ${nota.supplier.city}/${nota.supplier.state}`);

confere("XM5) totais em centavos",
  nota.totals.products_cents === 451000 && nota.totals.freight_cents === 18050 &&
  nota.totals.discount_cents === 1000 && nota.totals.invoice_cents === 468050,
  `produtos ${nota.totals.products_cents} · frete ${nota.totals.freight_cents}`);

confere("XM6) dois itens lidos", nota.items.length === 2,
  nota.items.map((i) => i.description).join(" | "));

// O unitário é DERIVADO do total da linha: 760,00 / 12 = 63,3333…, e o
// vUnCom do XML tem 10 casas. Arredondar o unitário e multiplicar de
// volta daria 759,96 — quatro centavos de diferença numa linha só.
confere("XM7) unitário derivado do total da linha",
  nota.items[1].unit_cost_cents === 6333 && nota.items[1].line_total_cents === 76000,
  `12 × ${nota.items[1].unit_cost_cents} centavos = ${nota.items[1].line_total_cents}`);

// A NF-e sempre manda QUATRO casas na quantidade, e o sistema trabalha
// com três. Sem o ajuste no leitor, toda quantidade de toda nota real
// chegava zerada — e o item seria recusado pelo banco sem explicação.
confere("XM8) quantidade de 4 casas vira milésimos",
  nota.items[0].quantity_milli === 3000 && nota.items[1].quantity_milli === 12000,
  `${nota.items[0].quantity_milli} e ${nota.items[1].quantity_milli}`);

const FRACIONADA = NOTA
  .replace("<qCom>3.0000</qCom>", "<qCom>2.7185</qCom>")
  .replace("<qCom>12.0000</qCom>", "<qCom>0.4004</qCom>");
const fracionada = parseNfe(FRACIONADA);
confere("XM8b) a quarta casa arredonda, não some",
  fracionada.items[0].quantity_milli === 2719 && fracionada.items[1].quantity_milli === 400,
  `2,7185 → ${fracionada.items[0].quantity_milli} e 0,4004 → ${fracionada.items[1].quantity_milli}`);

// "SEM GTIN" é texto, não código de barras. Guardá-lo quebraria o índice
// único de gtin no primeiro produto sem código.
confere("XM9) \"SEM GTIN\" vira nulo",
  nota.items[0].gtin === "7891234560017" && nota.items[1].gtin === null,
  `item 1 "${nota.items[0].gtin}", item 2 ${nota.items[1].gtin}`);

/** Nota com UM item: o XML traz `det` como objeto, não como lista. */
const UM_ITEM = NOTA.replace(/<det nItem="2">[\s\S]*?<\/det>/, "");
const notaUnica = parseNfe(UM_ITEM);
confere("XM10) nota de um item só",
  notaUnica.items.length === 1 && notaUnica.items[0].supplier_code === "0012",
  "det veio como objeto e virou lista de 1");

/** NF-e "crua", sem o envelope nfeProc de autorização. */
const CRUA = NOTA.replace(/<\/?nfeProc[^>]*>/g, "").replace(/^\s*<\?xml[^>]*\?>/, "");
confere("XM11) nota sem envelope nfeProc",
  parseNfe(CRUA).items.length === 2, "as duas formas circulam por e-mail");

/** O que chega de fora e não é nota. */
for (const [titulo, entrada] of [
  ["XM12) arquivo vazio", ""],
  ["XM13) não é XML", "isto aqui e um pdf renomeado"],
  ["XM14) XML que não é NF-e", "<?xml version=\"1.0\"?><pedido><item/></pedido>"],
]) {
  let recusou = false;
  try { parseNfe(entrada); } catch (e) { recusou = e instanceof NfeParseError; }
  confere(titulo, recusou, "recusado com mensagem em português");
}

/** Nota sem itens: estrutura válida, conteúdo inútil. */
let semItens = false;
try {
  parseNfe(NOTA.replace(/<det nItem="1">[\s\S]*?<\/det>\s*<det nItem="2">[\s\S]*?<\/det>/, ""));
} catch (e) { semItens = e instanceof NfeParseError; }
confere("XM15) nota sem itens", semItens, "recusada antes de virar rascunho");

rmSync(destino, { recursive: true, force: true });

process.stdout.write(falhas === 0 ? "\n✔ leitor de NF-e sem falhas\n" : `\n✗ ${falhas} falha(s)\n`);
process.exit(falhas === 0 ? 0 : 1);
