import "server-only";

import PDFDocument from "pdfkit";

import { formatCents } from "@/lib/format/money";
import { formatQuantity } from "@/lib/format/quantity";
import { formatDate } from "@/lib/format";
import { QUOTE_STATUS_LABELS } from "@/config/labels";
import { BRAND_COLORS } from "@/config/company";
import {
  declinedComponents,
  includedComponents,
  type DocumentItem,
  type QuoteDocument,
} from "../share/document";

/**
 * Geração do PDF do orçamento.
 *
 * Recebe o `QuoteDocument` pronto e desenha. Não consulta banco, não sabe
 * o que é RLS e não tem como buscar preço atual — a função é pura em
 * relação aos dados, e é isso que garante que reemitir o PDF de um
 * orçamento antigo produza o mesmo documento.
 *
 * `pdfkit` foi escolhido por rodar em Node puro (sem navegador headless,
 * que inviabilizaria a hospedagem serverless), por ter fontes padrão
 * embutidas com WinAnsi — que cobre todo o português — e por não exigir
 * nenhuma infraestrutura nova.
 */

const A4 = { width: 595.28, height: 841.89 };
const MARGIN = 42;
const CONTENT = A4.width - MARGIN * 2;

const COLORS = {
  brand: BRAND_COLORS.brand,
  ink: BRAND_COLORS.graphite,
  soft: BRAND_COLORS.graphiteSoft,
  line: "#d8d5d1",
  sand: BRAND_COLORS.sand,
  muted: "#8a8a8d",
};

const FONT = "Helvetica";
const FONT_BOLD = "Helvetica-Bold";
const FONT_OBLIQUE = "Helvetica-Oblique";

/** Colunas da tabela de itens, em pontos. Somam CONTENT. */
const COL = {
  code: 62,
  name: 201,
  qty: 62,
  unit: 78,
  disc: 44,
  total: 64,
};

type Doc = InstanceType<typeof PDFDocument>;

function money(cents: number) {
  return formatCents(cents);
}

function percent(value: number) {
  return `${String(value).replace(".", ",")}%`;
}

/** Linha horizontal fina, do jeito que se repete no documento inteiro. */
function rule(doc: Doc, y: number, color = COLORS.line) {
  doc.moveTo(MARGIN, y).lineTo(MARGIN + CONTENT, y).lineWidth(0.5).strokeColor(color).stroke();
}

function companyLines(document: QuoteDocument): string[] {
  const { company } = document;
  // Só entra o que está preenchido: nada de dado inventado no cabeçalho.
  const endereco = [company.address, company.city && `${company.city}${company.state ? `/${company.state}` : ""}`]
    .filter(Boolean)
    .join(" · ");
  const contato = [company.phone, company.whatsapp && `WhatsApp ${company.whatsapp}`, company.email]
    .filter(Boolean)
    .join(" · ");

  return [
    company.document ? `CNPJ ${company.document}` : null,
    endereco || null,
    contato || null,
    company.website,
  ].filter((line): line is string => Boolean(line));
}

function header(doc: Doc, document: QuoteDocument) {
  const top = MARGIN;

  doc.font(FONT_BOLD).fontSize(22).fillColor(COLORS.brand);
  doc.text(document.company.trade_name.toUpperCase(), MARGIN, top, { width: CONTENT * 0.55 });

  doc.font(FONT).fontSize(8).fillColor(COLORS.soft);
  let y = doc.y + 2;
  for (const line of companyLines(document)) {
    doc.text(line, MARGIN, y, { width: CONTENT * 0.55 });
    y = doc.y;
  }

  // Bloco de identificação, à direita.
  const boxWidth = 190;
  const boxLeft = MARGIN + CONTENT - boxWidth;
  doc.roundedRect(boxLeft, top, boxWidth, 74, 4).fillColor(COLORS.sand).fill();

  doc.font(FONT_BOLD).fontSize(9).fillColor(COLORS.soft);
  doc.text("ORÇAMENTO", boxLeft + 12, top + 10, { width: boxWidth - 24 });
  doc.font(FONT_BOLD).fontSize(16).fillColor(COLORS.ink);
  doc.text(document.number, boxLeft + 12, top + 22, { width: boxWidth - 24 });

  doc.font(FONT).fontSize(8).fillColor(COLORS.soft);
  const status = QUOTE_STATUS_LABELS[document.status];
  doc.text(`Emissão: ${formatDate(document.issue_date)}`, boxLeft + 12, top + 44, { width: boxWidth - 24 });
  doc.text(
    `Validade: ${document.valid_until ? formatDate(document.valid_until) : "a combinar"}`,
    boxLeft + 12,
    top + 54,
    { width: boxWidth - 24 },
  );
  doc.text(`Situação: ${status} · Vendedor: ${document.owner_name}`, boxLeft + 12, top + 64, {
    width: boxWidth - 24,
  });

  const bottom = Math.max(y, top + 74) + 12;
  rule(doc, bottom, COLORS.brand);
  return bottom + 14;
}

function customerBlock(doc: Doc, document: QuoteDocument, y: number) {
  const { customer } = document;

  doc.font(FONT_BOLD).fontSize(9).fillColor(COLORS.soft);
  doc.text("CLIENTE", MARGIN, y);

  doc.font(FONT_BOLD).fontSize(12).fillColor(COLORS.ink);
  doc.text(customer.name, MARGIN, doc.y + 2, { width: CONTENT });

  doc.font(FONT).fontSize(9).fillColor(COLORS.soft);
  const linhas = [
    customer.document,
    customer.address,
    [customer.city, customer.state].filter(Boolean).join("/") || null,
    [customer.phone, customer.email].filter(Boolean).join(" · ") || null,
  ].filter((line): line is string => Boolean(line));

  for (const linha of linhas) doc.text(linha, MARGIN, doc.y + 1, { width: CONTENT });

  return doc.y + 16;
}

function tableHeader(doc: Doc, y: number) {
  doc.rect(MARGIN, y, CONTENT, 20).fillColor(COLORS.sand).fill();
  doc.font(FONT_BOLD).fontSize(8).fillColor(COLORS.soft);

  let x = MARGIN + 8;
  doc.text("CÓDIGO", x, y + 6, { width: COL.code - 8 });
  x += COL.code;
  doc.text("DESCRIÇÃO", x, y + 6, { width: COL.name - 8 });
  x += COL.name;
  doc.text("QTD.", x, y + 6, { width: COL.qty - 8, align: "right" });
  x += COL.qty;
  doc.text("UNITÁRIO", x, y + 6, { width: COL.unit - 8, align: "right" });
  x += COL.unit;
  doc.text("DESC.", x, y + 6, { width: COL.disc - 8, align: "right" });
  x += COL.disc;
  doc.text("TOTAL", x, y + 6, { width: COL.total - 8, align: "right" });

  return y + 26;
}

/** Altura que a linha do item vai ocupar — para decidir a quebra de página. */
function itemHeight(doc: Doc, item: DocumentItem) {
  const nome = doc.font(FONT_BOLD).fontSize(9).heightOfString(item.name, { width: COL.name - 8 });
  const detalhe = [item.brand, item.description].filter(Boolean).join(" · ");
  const detalheAltura = detalhe
    ? doc.font(FONT).fontSize(7.5).heightOfString(detalhe, { width: COL.name - 8 })
    : 0;

  const incluidos = includedComponents(item).length;
  const recusados = declinedComponents(item).length;
  const composicao = incluidos > 0 ? 10 + incluidos * 10 + (recusados > 0 ? 10 + recusados * 10 : 0) : 0;

  return nome + detalheAltura + composicao + 14;
}

function drawItem(doc: Doc, item: DocumentItem, y: number) {
  let x = MARGIN + 8;

  doc.font(FONT).fontSize(8.5).fillColor(COLORS.soft);
  doc.text(item.code ?? "—", x, y, { width: COL.code - 8 });
  x += COL.code;

  doc.font(FONT_BOLD).fontSize(9).fillColor(COLORS.ink);
  doc.text(item.name, x, y, { width: COL.name - 8 });
  let nameBottom = doc.y;

  const detalhe = [item.brand, item.description].filter(Boolean).join(" · ");
  if (detalhe) {
    doc.font(FONT).fontSize(7.5).fillColor(COLORS.muted);
    doc.text(detalhe, x, nameBottom, { width: COL.name - 8 });
    nameBottom = doc.y;
  }
  x += COL.name;

  doc.font(FONT).fontSize(8.5).fillColor(COLORS.ink);
  const unidade = item.unit ? ` ${item.unit}` : "";
  doc.text(`${formatQuantity(item.quantity_milli)}${unidade}`, x, y, {
    width: COL.qty - 8,
    align: "right",
  });
  x += COL.qty;
  doc.text(money(item.unit_price_cents), x, y, { width: COL.unit - 8, align: "right" });
  x += COL.unit;
  doc.fillColor(item.discount_percent > 0 ? COLORS.ink : COLORS.muted);
  doc.text(item.discount_percent > 0 ? percent(item.discount_percent) : "—", x, y, {
    width: COL.disc - 8,
    align: "right",
  });
  x += COL.disc;
  doc.font(FONT_BOLD).fillColor(COLORS.ink);
  doc.text(money(item.line_total_cents), x, y, { width: COL.total - 8, align: "right" });

  // ── Composição do kit ─────────────────────────────────────
  const incluidos = includedComponents(item);
  let bottom = Math.max(nameBottom, y + 12);

  if (incluidos.length > 0) {
    const left = MARGIN + COL.code + 8;
    const largura = COL.name + COL.qty + COL.unit - 16;

    doc.font(FONT_BOLD).fontSize(7).fillColor(COLORS.soft);
    doc.text("INCLUI", left, bottom + 3, { width: largura });
    bottom = doc.y + 1;

    doc.font(FONT).fontSize(7.5).fillColor(COLORS.soft);
    for (const componente of incluidos) {
      const quantidade = Math.round((componente.quantity_milli * item.quantity_milli) / 1000);
      doc.text(
        `• ${componente.name} — ${formatQuantity(quantidade)} ${componente.unit ?? ""}`.trim(),
        left,
        bottom,
        { width: largura },
      );
      bottom = doc.y;
    }

    // Opcionais oferecidos e não escolhidos: seção à parte, em itálico e
    // rotulada. Nunca somam ao total e nunca se misturam ao que foi vendido.
    const recusados = declinedComponents(item);
    if (recusados.length > 0) {
      doc.font(FONT_BOLD).fontSize(7).fillColor(COLORS.muted);
      doc.text("OPCIONAIS NÃO INCLUÍDOS NESTA PROPOSTA", left, bottom + 3, { width: largura });
      bottom = doc.y + 1;

      doc.font(FONT_OBLIQUE).fontSize(7.5).fillColor(COLORS.muted);
      for (const componente of recusados) {
        doc.text(`• ${componente.name}`, left, bottom, { width: largura });
        bottom = doc.y;
      }
    }
  }

  return bottom + 8;
}

function totals(doc: Doc, document: QuoteDocument, y: number) {
  const largura = 220;
  const left = MARGIN + CONTENT - largura;

  const linhas: [string, string][] = [["Subtotal", money(document.subtotal_cents)]];

  if (document.discount_percent > 0) {
    const valor = Math.round((document.subtotal_cents * document.discount_percent) / 100);
    linhas.push([`Desconto ${percent(document.discount_percent)}`, `- ${money(valor)}`]);
  }
  if (document.discount_amount_cents > 0) {
    linhas.push(["Desconto", `- ${money(document.discount_amount_cents)}`]);
  }
  if (document.shipping_amount_cents > 0) {
    linhas.push(["Frete", `+ ${money(document.shipping_amount_cents)}`]);
  }

  let cursor = y;
  doc.font(FONT).fontSize(9).fillColor(COLORS.soft);
  for (const [rotulo, valor] of linhas) {
    doc.text(rotulo, left, cursor, { width: largura * 0.55 });
    doc.text(valor, left + largura * 0.55, cursor, { width: largura * 0.45, align: "right" });
    cursor += 14;
  }

  cursor += 2;
  doc.roundedRect(left, cursor, largura, 30, 4).fillColor(COLORS.brand).fill();
  doc.font(FONT_BOLD).fontSize(10).fillColor("#ffffff");
  doc.text("TOTAL", left + 12, cursor + 10);
  doc.fontSize(13);
  doc.text(money(document.total_cents), left + 12, cursor + 7, { width: largura - 24, align: "right" });

  return cursor + 42;
}

function commercialTerms(doc: Doc, document: QuoteDocument, y: number) {
  const blocos: [string, string][] = [];
  if (document.payment_terms) blocos.push(["Condição de pagamento", document.payment_terms]);
  if (document.delivery_terms) blocos.push(["Prazo de entrega", document.delivery_terms]);
  blocos.push([
    "Validade da proposta",
    document.valid_until ? formatDate(document.valid_until) : "a combinar",
  ]);

  let cursor = y;
  doc.font(FONT_BOLD).fontSize(9).fillColor(COLORS.soft);
  doc.text("CONDIÇÕES COMERCIAIS", MARGIN, cursor);
  cursor = doc.y + 4;

  for (const [rotulo, valor] of blocos) {
    doc.font(FONT_BOLD).fontSize(8.5).fillColor(COLORS.soft);
    doc.text(`${rotulo}: `, MARGIN, cursor, { continued: true });
    doc.font(FONT).fillColor(COLORS.ink);
    doc.text(valor);
    cursor = doc.y + 1;
  }

  if (document.notes) {
    cursor += 6;
    doc.font(FONT_BOLD).fontSize(9).fillColor(COLORS.soft);
    doc.text("OBSERVAÇÕES", MARGIN, cursor);
    doc.font(FONT).fontSize(8.5).fillColor(COLORS.ink);
    doc.text(document.notes, MARGIN, doc.y + 3, { width: CONTENT });
    cursor = doc.y;
  }

  return cursor + 10;
}

/**
 * Rodapé de todas as páginas, com "página X de Y".
 *
 * Só pode ser desenhado depois que o documento inteiro existe — antes
 * disso não se sabe quantas páginas são. Por isso roda no fim, percorrendo
 * as páginas já criadas.
 */
function footers(doc: Doc, document: QuoteDocument) {
  const range = doc.bufferedPageRange();
  const total = range.count;

  for (let index = 0; index < total; index += 1) {
    doc.switchToPage(range.start + index);

    // O rodapé mora ABAIXO da margem inferior. Sem zerar a margem, o
    // pdfkit entende o texto como transbordo e cria uma página nova para
    // ele — o documento saía com o dobro de páginas, todas em branco.
    doc.page.margins.bottom = 0;

    const y = A4.height - MARGIN + 6;
    rule(doc, y - 10);

    doc.font(FONT).fontSize(7.5).fillColor(COLORS.muted);
    const esquerda = [
      `${document.company.trade_name} · Orçamento ${document.number}`,
      document.company.document ? `CNPJ ${document.company.document}` : null,
    ]
      .filter(Boolean)
      .join(" · ");
    doc.text(esquerda, MARGIN, y, { width: CONTENT * 0.7, lineBreak: false });

    doc.text(`Página ${index + 1} de ${total}`, MARGIN + CONTENT * 0.7, y, {
      width: CONTENT * 0.3,
      align: "right",
      lineBreak: false,
    });

    if (document.valid_until) {
      doc.text(
        document.commercially_expired
          ? `Proposta com validade encerrada em ${formatDate(document.valid_until)}.`
          : `Proposta válida até ${formatDate(document.valid_until)}.`,
        MARGIN,
        y + 9,
        { width: CONTENT, lineBreak: false },
      );
    }
  }
}

/** Nome de arquivo estável: o mesmo orçamento gera sempre o mesmo nome. */
export function pdfFileName(document: QuoteDocument): string {
  const cliente = document.customer.name
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/[^A-Za-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 40);
  return `${document.number}${cliente ? `-${cliente}` : ""}.pdf`;
}

export function renderQuotePdf(document: QuoteDocument): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({
      size: "A4",
      margins: { top: MARGIN, bottom: MARGIN + 16, left: MARGIN, right: MARGIN },
      // Necessário para escrever "página X de Y" depois de saber o total.
      bufferPages: true,
      info: {
        Title: `Orçamento ${document.number}`,
        Author: document.company.trade_name,
        Subject: `Proposta comercial para ${document.customer.name}`,
        Creator: document.company.trade_name,
      },
    });

    const chunks: Buffer[] = [];
    doc.on("data", (chunk: Buffer) => chunks.push(chunk));
    doc.on("end", () => resolve(Buffer.concat(chunks)));
    doc.on("error", reject);

    try {
      let y = header(doc, document);
      y = customerBlock(doc, document, y);

      const limite = A4.height - MARGIN - 40;
      y = tableHeader(doc, y);

      for (const item of document.items) {
        const altura = itemHeight(doc, item);
        if (y + altura > limite) {
          doc.addPage();
          y = tableHeader(doc, MARGIN);
        }
        const proximo = drawItem(doc, item, y);
        rule(doc, proximo - 4);
        y = proximo;
      }

      if (document.items.length === 0) {
        doc.font(FONT_OBLIQUE).fontSize(9).fillColor(COLORS.muted);
        doc.text("Este orçamento não possui itens.", MARGIN + 8, y);
        y = doc.y + 10;
      }

      if (y + 150 > limite) {
        doc.addPage();
        y = MARGIN;
      }

      y = totals(doc, document, y + 6);
      commercialTerms(doc, document, y);

      footers(doc, document);
      doc.end();
    } catch (error) {
      reject(error);
    }
  });
}
