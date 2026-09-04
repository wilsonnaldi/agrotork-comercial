import { XMLParser } from "fast-xml-parser";
import { parseQuantityToMilli } from "@/lib/format/quantity";
import { parseMoneyToCents } from "@/lib/format/money";

/**
 * Leitor de NF-e.
 *
 * Função PURA: entra o texto do XML, sai a nota em estrutura. Não fala
 * com o banco e não sabe o que é fornecedor da AgroTork — quem faz o
 * casamento é o serviço. Assim ela pode ser lida, testada e corrigida
 * sozinha, que é o que se quer de um leitor de arquivo de terceiro.
 *
 * O QUE É LIDO, E POR QUÊ SÓ ISSO
 *
 * A NF-e tem centenas de campos: tributos, transporte, cobrança,
 * responsável técnico. Aqui só entra o que a entrada de mercadoria
 * usa — emitente, número, chave, itens, e os valores que compõem o
 * custo. Ler o resto seria carregar responsabilidade fiscal para dentro
 * de um app que decidiu, de propósito, ficar do lado gerencial da
 * fronteira.
 *
 * VALORES: SEM PONTO FLUTUANTE
 *
 * O XML traz "1234.56" como texto. Ele vira centavos e milésimos pelos
 * mesmos conversores do resto do sistema. Um `Number()` aqui reintroduzia
 * o erro de ponto flutuante justamente onde o custo nasce.
 */

export type NfeItem = {
  /** `cProd` — o código NO CATÁLOGO DO FORNECEDOR, não no nosso. */
  supplier_code: string;
  description: string;
  /** `cEAN`. A NF-e usa "SEM GTIN" quando não há; isso vira null. */
  gtin: string | null;
  ncm: string | null;
  unit: string | null;
  quantity_milli: number;
  unit_cost_cents: number;
  line_total_cents: number;
};

export type NfeDocument = {
  /** Chave de 44 dígitos, tirada do atributo `Id` de `infNFe`. */
  key: string | null;
  number: string | null;
  series: string | null;
  /** Emissão em yyyy-mm-dd. */
  issue_date: string | null;
  supplier: {
    document: string | null;
    legal_name: string | null;
    trade_name: string | null;
    state_registration: string | null;
    address: string | null;
    address_number: string | null;
    district: string | null;
    city: string | null;
    state: string | null;
    zip_code: string | null;
    phone: string | null;
  };
  totals: {
    products_cents: number;
    freight_cents: number;
    other_cents: number;
    discount_cents: number;
    invoice_cents: number;
  };
  items: NfeItem[];
};

export class NfeParseError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "NfeParseError";
  }
}

const parser = new XMLParser({
  ignoreAttributes: false,
  attributeNamePrefix: "@_",
  // Tudo como texto: `cProd` "0012" não pode virar o número 12, e
  // `nNF` "00055501" não pode perder os zeros à esquerda. Números viram
  // centavos e milésimos pelos conversores do sistema, não pelo parser.
  parseTagValue: false,
  parseAttributeValue: false,
  trimValues: true,
});

/** Lê um valor que pode vir como texto ou faltar. */
function texto(valor: unknown): string | null {
  if (valor === null || valor === undefined) return null;
  const s = String(valor).trim();
  return s === "" ? null : s;
}

function centavos(valor: unknown): number {
  const s = texto(valor);
  if (s === null) return 0;
  return parseMoneyToCents(s) ?? 0;
}

/**
 * A NF-e escreve quantidade com QUATRO casas ("3.0000", "0.5000"), e o
 * sistema trabalha com três — `numeric(14,3)`, milésimos. A quarta casa
 * é arredondada aqui, e não silenciosamente descartada mais adiante.
 *
 * Isto foi encontrado pelo teste XM8: sem o ajuste, TODA quantidade de
 * TODA nota real chegava como zero, porque o conversor do sistema recusa
 * mais de três casas — e um item com quantidade zero seria recusado pelo
 * banco depois, sem ninguém saber por quê.
 */
function milesimos(valor: unknown): number {
  const s = texto(valor);
  if (s === null) return 0;

  const normalizado = s.replace(",", ".");
  if (!/^\d+(\.\d+)?$/.test(normalizado)) return 0;

  const [inteiro = "0", decimais = ""] = normalizado.split(".");
  if (decimais.length <= 3) return parseQuantityToMilli(normalizado) ?? 0;

  // Arredonda a partir da quarta casa, sem passar por ponto flutuante.
  const tres = Number(`${inteiro}${decimais.slice(0, 3).padEnd(3, "0")}`);
  const quarta = Number(decimais[3]);
  return Number.isSafeInteger(tres) ? tres + (quarta >= 5 ? 1 : 0) : 0;
}

function apenasDigitos(valor: unknown): string | null {
  const s = texto(valor);
  if (s === null) return null;
  const d = s.replace(/\D/g, "");
  return d === "" ? null : d;
}

/**
 * A NF-e escreve "SEM GTIN" (e variações) quando o produto não tem
 * código de barras. Guardar esse texto como se fosse um EAN quebraria o
 * índice único de GTIN no primeiro produto sem código.
 */
function gtin(valor: unknown): string | null {
  const s = texto(valor);
  if (s === null) return null;
  if (/^sem\s*gtin$/i.test(s)) return null;
  const d = s.replace(/\D/g, "");
  return d.length >= 8 ? d : null;
}

/** `<det>` vem como objeto quando a nota tem UM item, e array quando tem vários. */
function comoLista(valor: unknown): unknown[] {
  if (valor === null || valor === undefined) return [];
  return Array.isArray(valor) ? valor : [valor];
}

type Node = Record<string, unknown>;
const filho = (no: unknown, chave: string): Node | undefined => {
  if (typeof no !== "object" || no === null) return undefined;
  const valor = (no as Node)[chave];
  return typeof valor === "object" && valor !== null ? (valor as Node) : undefined;
};
const campo = (no: unknown, chave: string): unknown =>
  typeof no === "object" && no !== null ? (no as Node)[chave] : undefined;

export function parseNfe(xml: string): NfeDocument {
  if (!xml || xml.trim() === "") {
    throw new NfeParseError("O arquivo está vazio.");
  }

  let arvore: unknown;
  try {
    arvore = parser.parse(xml);
  } catch {
    throw new NfeParseError("Não consegui ler este arquivo como XML.");
  }

  // A nota autorizada vem dentro de `nfeProc`; a nota "crua", direto em
  // `NFe`. As duas circulam por e-mail, e as duas precisam entrar.
  const raiz = filho(arvore, "nfeProc") ?? arvore;
  const nfe = filho(raiz, "NFe") ?? filho(raiz, "nfe");
  const info = filho(nfe, "infNFe") ?? filho(nfe, "infnfe");

  if (!info) {
    throw new NfeParseError(
      "Este XML não parece uma NF-e. Confira se o arquivo é a nota, e não o comprovante de e-mail.",
    );
  }

  const ide = filho(info, "ide");
  const emit = filho(info, "emit");
  const endereco = filho(emit, "enderEmit");
  const totais = filho(filho(info, "total"), "ICMSTot");

  // A chave vem no atributo como "NFe4312...". Os 44 dígitos são o que
  // interessa; o prefixo é ruído.
  const idBruto = texto(campo(info, "@_Id"));
  const chave = idBruto ? (idBruto.replace(/\D/g, "") || null) : null;

  const emissaoBruta = texto(campo(ide, "dhEmi")) ?? texto(campo(ide, "dEmi"));
  const emissao = emissaoBruta ? emissaoBruta.slice(0, 10) : null;

  const itens: NfeItem[] = comoLista(campo(info, "det")).map((det) => {
    const prod = filho(det, "prod");
    const quantidade = milesimos(campo(prod, "qCom"));
    const total = centavos(campo(prod, "vProd"));

    // `vUnCom` vem com até 10 casas na NF-e. Arredondar para centavos
    // aqui perderia a diferença; por isso o unitário é DERIVADO do total
    // da linha, que é o valor que o fornecedor cobra de fato.
    const unitario =
      quantidade > 0 ? Math.round((total * 1000) / quantidade) : centavos(campo(prod, "vUnCom"));

    return {
      supplier_code: texto(campo(prod, "cProd")) ?? "",
      description: texto(campo(prod, "xProd")) ?? "(sem descrição)",
      gtin: gtin(campo(prod, "cEAN")) ?? gtin(campo(prod, "cEANTrib")),
      ncm: apenasDigitos(campo(prod, "NCM")),
      unit: texto(campo(prod, "uCom")),
      quantity_milli: quantidade,
      unit_cost_cents: unitario,
      line_total_cents: total,
    } satisfies NfeItem;
  });

  if (itens.length === 0) {
    throw new NfeParseError("A nota não tem itens.");
  }

  return {
    key: chave && chave.length === 44 ? chave : null,
    number: texto(campo(ide, "nNF")),
    series: texto(campo(ide, "serie")),
    issue_date: emissao && /^\d{4}-\d{2}-\d{2}$/.test(emissao) ? emissao : null,
    supplier: {
      document: apenasDigitos(campo(emit, "CNPJ")) ?? apenasDigitos(campo(emit, "CPF")),
      legal_name: texto(campo(emit, "xNome")),
      trade_name: texto(campo(emit, "xFant")),
      state_registration: texto(campo(emit, "IE")),
      address: texto(campo(endereco, "xLgr")),
      address_number: texto(campo(endereco, "nro")),
      district: texto(campo(endereco, "xBairro")),
      city: texto(campo(endereco, "xMun")),
      state: texto(campo(endereco, "UF")),
      zip_code: apenasDigitos(campo(endereco, "CEP")),
      phone: apenasDigitos(campo(endereco, "fone")),
    },
    totals: {
      products_cents: centavos(campo(totais, "vProd")),
      freight_cents: centavos(campo(totais, "vFrete")),
      other_cents: centavos(campo(totais, "vOutro")),
      discount_cents: centavos(campo(totais, "vDesc")),
      invoice_cents: centavos(campo(totais, "vNF")),
    },
    items: itens,
  };
}
