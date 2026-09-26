/**
 * Confere o ADAPTER da Anthropic (Answer v1) — sem rede e sem chave real.
 *
 *   node --experimental-strip-types supabase/db-tests/check-brain-provider.mjs
 *
 * Por que existe: o adapter é o único lugar do BRAIN que toca uma credencial
 * e o único que fala com fora. Duas coisas podem dar errado aqui e as duas
 * são caras:
 *
 *   1. mandar um parâmetro que o modelo recusa — no Claude Sonnet 5,
 *      `temperature`, `top_p` e `top_k` em valor não-padrão devolvem 400, e
 *      o sintoma seria uma síntese que "nunca funciona" por motivo obscuro;
 *   2. deixar a chave ou o conteúdo dos documentos escapar — no corpo do
 *      request, numa mensagem de erro, num log.
 *
 * Nada aqui vai à rede: `globalThis.fetch` é substituído por um espião que
 * guarda o que seria enviado e devolve uma resposta de mentira. A "chave" é
 * uma string inventada neste arquivo. Nenhuma credencial de verdade é lida,
 * pedida ou escrita.
 */
import { mkdtempSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import { createServer } from "node:http";
import { inspect } from "node:util";
import { join, dirname } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const AQUI = dirname(fileURLToPath(import.meta.url));
const RAIZ = join(AQUI, "..", "..");

const ARQUIVOS = {
  "provider.ts": "src/modules/brain/llm/provider.ts",
  "anthropic.ts": "src/modules/brain/llm/anthropic.ts",
};

const destino = mkdtempSync(join(RAIZ, ".provider-check-"));
for (const [nome, caminho] of Object.entries(ARQUIVOS)) {
  const fonte = readFileSync(join(RAIZ, caminho), "utf8")
    // `server-only` existe para quebrar o build se este arquivo for importado
    // no cliente. Aqui não há bundler, então sai — a garantia continua valendo
    // no build de verdade, que roda na regressão.
    .replace(/^import "server-only";\n\n?/m, "")
    .replace(/from "\.\.\/evidence"/g, 'from "./evidence.ts"')
    .replace(/from "\.\/provider"/g, 'from "./provider.ts"');
  writeFileSync(join(destino, nome), fonte);
}
// `provider.ts` importa o tipo das evidências só para tipar; um stub basta.
writeFileSync(join(destino, "evidence.ts"), "export type KnowledgeEvidence = unknown;\n");

const imp = (n) => import(pathToFileURL(join(destino, n)).href);
const { AnthropicProvider } = await imp("anthropic.ts");
const { ProviderError } = await imp("provider.ts");

let falhas = 0;
const ok = (t) => process.stdout.write(`  ✓ ${t}\n`);
const nao = (t) => { falhas += 1; process.stdout.write(`  ✗ ${t}\n`); };
const confere = (t, c, d = "") => (c ? ok(`${t}${d ? ` — ${d}` : ""}`) : nao(`${t}${d ? ` — ${d}` : ""}`));

/**
 * Uma "chave" inventada, com a forma de uma chave só para o teste ser honesto
 * sobre o que procura. Não é credencial de ninguém e não sai deste arquivo.
 */
const CHAVE_FALSA = "sk-ant-api03-CHAVE-DE-TESTE-QUE-NAO-EXISTE-0000000000";
const MODELO = "claude-sonnet-5";

const ENTRADA = {
  question: "Qual a vazão da MJ985CAP a 40 psi?",
  evidence: [],
  systemPrompt: "Você responde só com o que está nas evidências.",
  userMessage: "EVIDÊNCIA [1]\nMJ985CAP ... 1,53 L/min a 40 psi\n\nPERGUNTA\nQual a vazão da MJ985CAP a 40 psi?",
  timeoutMs: 30_000,
};

/**
 * Espião de `fetch`. Guarda a chamada, não vai a lugar nenhum, e devolve o
 * que o teste mandar. `resposta` pode ser uma função para simular erro.
 */
function espiar(resposta) {
  const registro = { chamadas: [] };
  globalThis.fetch = async (url, init) => {
    registro.chamadas.push({ url: String(url), init });
    if (typeof resposta === "function") return resposta(init);
    return resposta;
  };
  return registro;
}

const respostaBoa = () => ({
  ok: true,
  status: 200,
  json: async () => ({ content: [{ type: "text", text: "A vazão é 1,53 L/min. [1]" }] }),
});

const fetchOriginal = globalThis.fetch;

// ───────────────────────────────────────────────────────────────────────────
process.stdout.write("\nADAPTER SONNET 5 — o corpo do request\n");

const espiao = espiar(respostaBoa());
const provedor = new AnthropicProvider(CHAVE_FALSA, MODELO);
const saida = await provedor.generate(ENTRADA);

const chamada = espiao.chamadas[0];
const corpoTexto = chamada.init.body;
const corpo = JSON.parse(corpoTexto);
const chaves = Object.keys(corpo).sort();

confere("P1 uma única chamada, e para a API de mensagens",
  espiao.chamadas.length === 1 && chamada.url === "https://api.anthropic.com/v1/messages",
  chamada.url);

confere("P2 model = claude-sonnet-5", corpo.model === MODELO, String(corpo.model));
confere("P3 max_tokens presente e numérico",
  typeof corpo.max_tokens === "number" && corpo.max_tokens > 0, String(corpo.max_tokens));
confere("P4 system presente e não vazio",
  typeof corpo.system === "string" && corpo.system.length > 0);
confere("P5 messages presente, com o papel e o conteúdo certos",
  Array.isArray(corpo.messages) && corpo.messages.length === 1 &&
  corpo.messages[0].role === "user" && corpo.messages[0].content === ENTRADA.userMessage);

confere("P6 temperature AUSENTE", !("temperature" in corpo));
confere("P7 top_p AUSENTE", !("top_p" in corpo));
confere("P8 top_k AUSENTE", !("top_k" in corpo));
confere("P9 thinking AUSENTE", !("thinking" in corpo));
confere("P10 budget_tokens AUSENTE", !("budget_tokens" in corpo));

confere("P11 o corpo tem SÓ as quatro chaves necessárias",
  chaves.length === 4 &&
  chaves.join(",") === "max_tokens,messages,model,system",
  chaves.join(", "));

// O teste acima passaria mesmo se alguém escrevesse `temperature: undefined`
// (que o JSON.stringify apaga) — mas aí o texto do arquivo ainda teria a
// palavra, e a próxima pessoa a editar reintroduziria o valor. Confere a fonte.
const FONTE = readFileSync(join(RAIZ, "src/modules/brain/llm/anthropic.ts"), "utf8");
const corpoDoArquivo = FONTE.slice(FONTE.indexOf("body: JSON.stringify("));
confere("P12 a fonte não tem parâmetro de amostragem dentro do body",
  !/^\s*(temperature|top_p|top_k|thinking|budget_tokens)\s*:/m.test(corpoDoArquivo));

// ───────────────────────────────────────────────────────────────────────────
process.stdout.write("\nSEGREDO — por onde a chave anda\n");

const cabecalhos = chamada.init.headers;
confere("S1 a chave está em x-api-key", cabecalhos["x-api-key"] === CHAVE_FALSA);
confere("S2 a chave NÃO aparece no corpo", !corpoTexto.includes(CHAVE_FALSA));
confere("S3 a chave não aparece em nenhum outro cabeçalho",
  Object.entries(cabecalhos)
    .filter(([k]) => k !== "x-api-key")
    .every(([, v]) => !String(v).includes(CHAVE_FALSA)));
confere("S4 não há Authorization: Bearer com a chave",
  !("authorization" in cabecalhos) && !("Authorization" in cabecalhos));
confere("S5 anthropic-version presente", cabecalhos["anthropic-version"] === "2023-06-01");
confere("S6 a chave não aparece na URL", !chamada.url.includes(CHAVE_FALSA));
confere("S7 a chave não volta no meta da resposta",
  !JSON.stringify(saida.meta).includes(CHAVE_FALSA) &&
  saida.meta.provider === "anthropic" && saida.meta.model === MODELO);
confere("S8 o texto da resposta sai do bloco content", saida.text === "A vazão é 1,53 L/min. [1]");

// ───────────────────────────────────────────────────────────────────────────
process.stdout.write("\nERRO DO PROVEDOR — o que o erro deixa ver\n");

/** Um corpo de erro que repete o prompt inteiro, como a API costuma fazer. */
const SEGREDO_NO_CORPO = "MJ985CAP ... 1,53 L/min a 40 psi";
const respostaRuim = (status) => ({
  ok: false,
  status,
  json: async () => ({ error: { message: `invalid request: ${SEGREDO_NO_CORPO}` } }),
  text: async () => `invalid request: ${SEGREDO_NO_CORPO} — key ${CHAVE_FALSA}`,
});

async function pegarErro(status) {
  espiar(respostaRuim(status));
  try {
    await new AnthropicProvider(CHAVE_FALSA, MODELO).generate(ENTRADA);
    return null;
  } catch (e) {
    return e;
  }
}

const e400 = await pegarErro(400);
confere("E1 400 vira ProviderError", e400 instanceof ProviderError && e400.kind === "unknown");
confere("E2 a mensagem do erro NÃO traz o corpo da resposta",
  !e400.message.includes(SEGREDO_NO_CORPO));
confere("E3 a mensagem do erro NÃO traz a chave", !e400.message.includes(CHAVE_FALSA));
confere("E4 o erro inteiro, serializado, não vaza nada",
  !JSON.stringify({ m: e400.message, s: e400.stack ?? "" }).includes(SEGREDO_NO_CORPO));

const e401 = await pegarErro(401);
confere("E5 401 é classificado como auth", e401 instanceof ProviderError && e401.kind === "auth");
confere("E6 nem no 401 a chave aparece", !e401.message.includes(CHAVE_FALSA));

const e429 = await pegarErro(429);
confere("E7 429 é classificado como rate_limit", e429?.kind === "rate_limit");

espiar(() => { throw new TypeError("fetch failed"); });
let eRede = null;
try { await new AnthropicProvider(CHAVE_FALSA, MODELO).generate(ENTRADA); } catch (e) { eRede = e; }
confere("E8 falha de rede vira ProviderError network",
  eRede instanceof ProviderError && eRede.kind === "network");
confere("E9 a falha de rede não carrega a chave", !eRede.message.includes(CHAVE_FALSA));

espiar(async () => {
  const erro = new Error("abortado");
  erro.name = "AbortError";
  throw erro;
});
let eTempo = null;
try { await new AnthropicProvider(CHAVE_FALSA, MODELO).generate(ENTRADA); } catch (e) { eTempo = e; }
confere("E10 abort vira ProviderError timeout",
  eTempo instanceof ProviderError && eTempo.kind === "timeout");

espiar({ ok: true, status: 200, json: async () => ({ content: [{ type: "tool_use" }] }) });
let eFormato = null;
try { await new AnthropicProvider(CHAVE_FALSA, MODELO).generate(ENTRADA); } catch (e) { eFormato = e; }
confere("E11 resposta sem bloco de texto vira invalid_response",
  eFormato instanceof ProviderError && eFormato.kind === "invalid_response");

// ───────────────────────────────────────────────────────────────────────────
process.stdout.write("\nTETO DE ESPERA — o relógio cobre também o corpo\n");

// Um servidor LOCAL (127.0.0.1, porta efêmera) manda o cabeçalho 200 e um
// pedaço do JSON, e trava. Antes, o relógio era desarmado ao chegar o
// cabeçalho e `resposta.json()` ficava pendurado para sempre; agora o mesmo
// AbortController corta o corpo e o erro é `timeout`. O `fetch` de verdade é
// usado (o espião só troca a URL da API pela do servidor local), para o
// corte passar pelo streaming real do corpo. Nada sai da máquina.
const TETO_MS = 300;
const conexoes = new Set();
const servidor = createServer((_req, res) => {
  res.writeHead(200, { "content-type": "application/json" });
  res.write('{"content":[{"type":"text","text":"come');   // e nunca termina
});
servidor.on("connection", (s) => { conexoes.add(s); s.on("close", () => conexoes.delete(s)); });
await new Promise((ok) => servidor.listen(0, "127.0.0.1", ok));
const porta = servidor.address().port;
globalThis.fetch = (_url, init) => fetchOriginal(`http://127.0.0.1:${porta}/`, init);

const t0 = Date.now();
// Guarda do próprio teste: sem o conserto, a promessa nunca resolveria e a
// suíte ficaria presa — assim ela falha em 3 s em vez de travar o CI.
const GUARDA = Symbol("guarda");
let guarda;
const eCorpo = await Promise.race([
  new AnthropicProvider(CHAVE_FALSA, MODELO).generate({ ...ENTRADA, timeoutMs: TETO_MS }).then(() => null, (e) => e),
  new Promise((ok) => { guarda = setTimeout(() => ok(GUARDA), 3_000); }),
]);
clearTimeout(guarda);
const decorrido = Date.now() - t0;
for (const s of conexoes) s.destroy();
await new Promise((ok) => servidor.close(ok));
confere("E12 cabeçalho chega e o corpo trava → ProviderError timeout, dentro do teto",
  eCorpo !== GUARDA && eCorpo instanceof ProviderError && eCorpo.kind === "timeout" && decorrido < TETO_MS + 1_500,
  `${eCorpo === GUARDA ? "pendurado (guarda de 3 s)" : eCorpo?.kind} em ${decorrido} ms, teto ${TETO_MS} ms`);

// ───────────────────────────────────────────────────────────────────────────
process.stdout.write("\nSEGREDO — o objeto do provedor não carrega a chave para fora\n");

const soltoNoLog = new AnthropicProvider(CHAVE_FALSA, MODELO);
confere("E13 JSON.stringify(provider) não contém a chave",
  !JSON.stringify(soltoNoLog).includes(CHAVE_FALSA), JSON.stringify(soltoNoLog));
confere("E14 util.inspect(provider) (o que console.log imprime) não contém a chave",
  !inspect(soltoNoLog, { showHidden: true, depth: 5 }).includes(CHAVE_FALSA) &&
  !Object.values(soltoNoLog).some((v) => String(v).includes(CHAVE_FALSA)),
  inspect(soltoNoLog).replace(/\s+/g, " "));

// ───────────────────────────────────────────────────────────────────────────
globalThis.fetch = fetchOriginal;
rmSync(destino, { recursive: true, force: true });

process.stdout.write(
  falhas === 0
    ? "\nADAPTER ANTHROPIC — tudo certo (sem rede, sem chave real).\n\n"
    : `\nADAPTER ANTHROPIC — ${falhas} falha(s).\n\n`);
process.exit(falhas === 0 ? 0 : 1);
