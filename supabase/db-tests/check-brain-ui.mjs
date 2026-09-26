/**
 * Confere a camada de APRESENTAÇÃO do console do BRAIN (UX v1).
 *
 *   node --experimental-strip-types supabase/db-tests/check-brain-ui.mjs
 *
 * Por que existe: a rodada de UX mexe em como a resposta aparece, e a
 * tentação óbvia — "tira esses [1] repetidos que ficam feios" — apagaria o
 * lastro que as três travas construíram. Estes testes trancam o contrário:
 * a renderização pode reorganizar, nunca subtrair. Nenhum marcador some,
 * nenhum dígito muda.
 */
import { mkdtempSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const AQUI = dirname(fileURLToPath(import.meta.url));
const RAIZ = join(AQUI, "..", "..");

const ARQUIVOS = {
  "evidence.ts": "src/modules/brain/evidence.ts",
  "grounding.ts": "src/modules/brain/grounding.ts",
  "presentation.ts": "src/modules/brain/presentation.ts",
};

const destino = mkdtempSync(join(RAIZ, ".ui-check-"));
// Exceção não tratada no meio da suíte também passa pelo "exit": o
// diretório some mesmo quando o rmSync do fim não chega a rodar.
process.on("exit", () => rmSync(destino, { recursive: true, force: true }));
for (const [nome, caminho] of Object.entries(ARQUIVOS)) {
  const fonte = readFileSync(join(RAIZ, caminho), "utf8")
    .replace(/^import type \{ Json \} from "@\/types\/db";$/m, "type Json = unknown;")
    .replace(/from "\.\/evidence"/g, 'from "./evidence.ts"')
    .replace(/from "\.\/grounding"/g, 'from "./grounding.ts"');
  writeFileSync(join(destino, nome), fonte);
}
const P = await import(pathToFileURL(join(destino, "presentation.ts")).href);
const CONSOLE = readFileSync(join(RAIZ, "src/app/(app)/brain/brain-console.tsx"), "utf8");

let falhas = 0;
const ok = (t) => process.stdout.write(`  ✓ ${t}\n`);
const nao = (t) => { falhas += 1; process.stdout.write(`  ✗ ${t}\n`); };
const confere = (t, c, d = "") => (c ? ok(`${t}${d ? ` — ${d}` : ""}`) : nao(`${t}${d ? ` — ${d}` : ""}`));

/** A resposta real de produção, 18/09/2026. */
const LISTA = [
  "Vazões da MJ981CAP por pressão em bar [1]:",
  "- 2,07 bar -> 0,66 L/min [1]",
  "- 2,76 bar -> 0,77 L/min [1]",
  "- 3,45 bar -> 0,86 L/min [1]",
  "- 4,14 bar -> 0,94 L/min [1]",
  "- 4,83 bar -> 1,01 L/min [1]",
  "- 5,52 bar -> 1,08 L/min [1]",
].join("\n");
const PONTUAL = "A vazão da MJ981CAP a 40 psi é 0,77 L/min [1].";

// ════════════════════════════════════════════════════════════
process.stdout.write("▶ Blocos da resposta\n");

const blocos = P.parseAnswer(LISTA);
confere("U1  abertura + 6 itens",
  blocos.length === 7 && blocos[0].tipo === "lead" && blocos.slice(1).every((b) => b.tipo === "item"),
  blocos.map((b) => b.tipo).join(","));
confere("U1b o marcador '- ' sai do texto do item, o conteúdo fica",
  blocos[1].texto === "2,07 bar -> 0,66 L/min [1]");
confere("U2  resposta sem lista vira um parágrafo só",
  P.parseAnswer(PONTUAL).length === 1 && P.parseAnswer(PONTUAL)[0].tipo === "paragrafo");
confere("U2b linha terminada em ':' sem item depois continua parágrafo",
  P.parseAnswer("Segundo o catálogo [1]:").every((b) => b.tipo === "paragrafo"));
confere("U3  '•', '*' e '1.' também são itens",
  P.parseAnswer("Valores [1]:\n• a [1]\n* b [1]\n1. c [1]").filter((b) => b.tipo === "item").length === 3);
confere("U3b linha em branco não vira bloco",
  P.parseAnswer("A [1]\n\n\nB [1]").length === 2);

// ════════════════════════════════════════════════════════════
process.stdout.write("▶ A renderização não apaga lastro\n");

const FIXTURES = [LISTA, PONTUAL, "A [1]\n\n- 1,08 L/min [2]\n- 0,66 L/min [1]", P.formatarSetas(LISTA)];
const renderizado = (t) => P.parseAnswer(t).map((b) => P.formatarSetas(b.texto)).join("\n");

for (const [i, f] of FIXTURES.entries()) {
  const saida = renderizado(f);
  confere(`U4.${i + 1} nenhum marcador [n] some`,
    P.marcadoresDe(saida).join("") === P.marcadoresDe(f).join(""),
    `${P.marcadoresDe(f).length} marcador(es)`);
  confere(`U5.${i + 1} nenhum dígito muda`, P.digitosDe(saida) === P.digitosDe(f));
}

confere("U6  a seta ASCII entre espaços vira '→'",
  P.formatarSetas("2,07 bar -> 0,66 L/min") === "2,07 bar → 0,66 L/min");
confere("U6b e só ela: número negativo, hífen de código e '->' colado ficam como estão",
  P.formatarSetas("-4 °C, MUG-CV 02, a->b") === "-4 °C, MUG-CV 02, a->b");
confere("U6c aplicar duas vezes não muda mais nada (idempotente)",
  P.formatarSetas(P.formatarSetas(LISTA)) === P.formatarSetas(LISTA));
confere("U7  o console não remove marcador nenhum do texto validado",
  !/replace\(\s*\/\\\[\\d/.test(CONSOLE) && CONSOLE.includes("split(/(\\[\\d{1,3}\\])/g)"));

// ════════════════════════════════════════════════════════════
process.stdout.write("▶ Estados, rótulos e badges\n");

confere("U8  synthesized / extractive / no_evidence são derivados de status+mode",
  P.estadoDaResposta("answered", "synthesized") === "synthesized" &&
  P.estadoDaResposta("answered", "extractive") === "extractive" &&
  P.estadoDaResposta("no_evidence", "none") === "no_evidence" &&
  P.estadoDaResposta("forbidden", "none") === "forbidden");
confere("U8b os rótulos são os três pedidos, em português",
  P.ROTULO_DO_ESTADO.synthesized === "Resposta do BRAIN" &&
  P.ROTULO_DO_ESTADO.extractive === "Sem síntese automática" &&
  P.ROTULO_DO_ESTADO.no_evidence === "Sem documentação suficiente");
confere("U8c nenhum rótulo de tela usa vocabulário técnico",
  Object.values(P.ROTULO_DO_ESTADO).every(
    (r) => !/no_evidence|external_processing|grounding|association|extractive/i.test(r),
  ));
confere("U9  níveis de acesso: Público, Interno, Comercial, Admin",
  ["public", "internal", "commercial", "admin"].map((k) => P.NIVEL_DE_ACESSO[k].texto).join(",") ===
  "Público,Interno,Comercial,Admin");
confere("U9b cada nível tem o seu tom — a cor acompanha o rótulo, não o substitui",
  new Set(["public", "internal", "commercial", "admin"].map((k) => P.NIVEL_DE_ACESSO[k].tom)).size === 4);
confere("U10 tipos de trecho cobrem tabela, texto, manual, catálogo e tabela de preços",
  ["table", "text", "manual", "catalog", "price_table"].map((k) => P.TIPO_DE_TRECHO[k]).join(",") ===
  "Tabela,Texto,Manual,Catálogo,Tabela de preços");
confere("U10b tabela e tabela de preços rolam na horizontal; texto não",
  P.ehTabular("table") && P.ehTabular("price_table") && !P.ehTabular("text"));
confere("U11 fonte no singular e no plural",
  P.rotuloDeFontes(1) === "Fonte utilizada" && P.rotuloDeFontes(2) === "Fontes utilizadas");
confere("U11b trecho no singular e no plural",
  P.rotuloDeTrechos(1) === "1 trecho" && P.rotuloDeTrechos(3) === "3 trechos");
confere("U11c a lista de fontes é <ul>, não <ol> — nada de '1. [1]'",
  !/<ol/.test(CONSOLE) && CONSOLE.includes("rotuloDeFontes(citacoes.length)"));

// ════════════════════════════════════════════════════════════
process.stdout.write("▶ Sem evidência: o que foi procurado\n");

confere("U12 o código da pergunta aparece na tela de recusa",
  P.codigoConsultado("Qual a vazão da MJ999CAP?") === "MJ999CAP");
confere("U12b quantidade não é código: '40 psi' não vira código consultado",
  P.codigoConsultado("Qual a vazão a 40 psi?") === null);
confere("U12c código numérico longo também conta",
  P.codigoConsultado("O que é o código ARAG 466113200?") === "466113200");
confere("U12d o console mostra o código, e não sugere valor parecido",
  CONSOLE.includes("Código consultado:") && !/parecid|aproximad|talvez você/i.test(CONSOLE));

// ════════════════════════════════════════════════════════════
process.stdout.write("▶ Acessibilidade e responsividade, no fonte\n");

confere("A1  cada marcador [n] tem rótulo para leitor de tela",
  CONSOLE.includes("aria-label={`Evidência ${citacao.index}"));
confere("A2  a lista de fontes também",
  CONSOLE.includes("aria-label={`Ver a evidência ${c.index}"));
confere("A3  o acordeão diz o que controla e o seu estado",
  CONSOLE.includes('aria-controls="brain-evidencias"') && CONSOLE.includes("aria-expanded={evidenciasAbertas}"));
confere("A4  a resposta é uma região viva (anunciada quando chega)",
  CONSOLE.includes('aria-live="polite"'));
confere("A5  foco visível nos controles novos",
  (CONSOLE.match(/focus-visible:ring-2/g) ?? []).length >= 3);
confere("A6  o estado não depende só de cor: cada um tem título em texto",
  CONSOLE.includes("ROTULO_DO_ESTADO[estado ?? \"synthesized\"]"));
confere("R1  tabela da evidência rola na horizontal dentro do card",
  CONSOLE.includes("overflow-x-auto") && CONSOLE.includes("ehTabular(evidencia.kind)"));
confere("R2  texto longo e citação quebram linha em vez de estourar",
  (CONSOLE.match(/break-words/g) ?? []).length >= 4);
confere("R3  o botão Consultar ocupa a largura no celular e encolhe no desktop",
  CONSOLE.includes('className="w-full sm:w-auto"'));

confere("U13 comparação ganha selo próprio, sem redesenhar o console",
  CONSOLE.includes('resposta.comparison && <Badge tone="info">Comparação</Badge>'));

// ════════════════════════════════════════════════════════════
process.stdout.write("▶ Contraste (WCAG AA, texto normal ≥ 4,5:1)\n");

const CSS = readFileSync(join(RAIZ, "src/app/globals.css"), "utf8");
const cor = (nome) => (new RegExp(`--color-${nome}:\\s*(#[0-9a-fA-F]{6})`).exec(CSS) ?? [])[1];
const luminancia = (hex) => {
  const c = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255)
    .map((v) => (v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4));
  return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
};
const contraste = (a, b) => {
  const [x, y] = [luminancia(a), luminancia(b)].sort((p, q) => q - p);
  return (x + 0.05) / (y + 0.05);
};
const BRANCO = "#ffffff";
const PARES = [
  ["texto da resposta sobre o card", cor("graphite"), BRANCO],
  ["texto de apoio sobre o card", cor("graphite-500"), BRANCO],
  ["texto de apoio sobre o fundo areia", cor("graphite-500"), cor("sand")],
  ["marcador [n]", cor("brand-deep"), cor("brand-soft")],
  ["botão Consultar", BRANCO, cor("brand")],
];
for (const [nome, frente, fundo] of PARES) {
  const razao = contraste(frente, fundo);
  confere(`C1 ${nome}`, razao >= 4.5, `${razao.toFixed(2)}:1`);
}
confere("C2 o rodapé das evidências, que fica FORA do card, não usa o cinza mais claro",
  /Estes são os trechos recuperados/.test(CONSOLE) &&
  /text-graphite-500">\s*<FileSearch/.test(CONSOLE));

rmSync(destino, { recursive: true, force: true });
process.stdout.write(falhas === 0 ? "✔ apresentação do console\n" : `✗ ${falhas} falha(s)\n`);
process.exit(falhas === 0 ? 0 : 1);
