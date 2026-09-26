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
 * Desde o Pacote C (26/09) confere também o CONTRATO de configuração
 * (`llm/config.ts`, CFG*), o `resolveProvider` com ambiente inventado e o
 * preflight manual (`brain:preflight`, PF*), rodado como processo filho num
 * diretório temporário — nenhum `.env.local` de verdade é lido.
 *
 * Nada aqui vai à rede: `globalThis.fetch` é substituído por um espião que
 * guarda o que seria enviado e devolve uma resposta de mentira. A "chave" é
 * uma string inventada neste arquivo. Nenhuma credencial de verdade é lida,
 * pedida ou escrita.
 */
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import { inspect } from "node:util";
import { join, dirname } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const AQUI = dirname(fileURLToPath(import.meta.url));
const RAIZ = join(AQUI, "..", "..");

const ARQUIVOS = {
  "provider.ts": "src/modules/brain/llm/provider.ts",
  "anthropic.ts": "src/modules/brain/llm/anthropic.ts",
  "config.ts": "src/modules/brain/llm/config.ts",
  "index.ts": "src/modules/brain/llm/index.ts",
};

const destino = mkdtempSync(join(RAIZ, ".provider-check-"));
// Exceção não tratada no meio da suíte também passa pelo "exit": o
// diretório some mesmo quando o rmSync do fim não chega a rodar.
process.on("exit", () => rmSync(destino, { recursive: true, force: true }));
for (const [nome, caminho] of Object.entries(ARQUIVOS)) {
  const fonte = readFileSync(join(RAIZ, caminho), "utf8")
    // `server-only` existe para quebrar o build se este arquivo for importado
    // no cliente. Aqui não há bundler, então sai — a garantia continua valendo
    // no build de verdade, que roda na regressão.
    .replace(/^import "server-only";\n\n?/m, "")
    .replace(/from "\.\.\/evidence"/g, 'from "./evidence.ts"')
    .replace(/from "\.\/provider"/g, 'from "./provider.ts"')
    .replace(/from "\.\/anthropic"/g, 'from "./anthropic.ts"')
    .replace(/from "\.\/config"/g, 'from "./config.ts"');
  writeFileSync(join(destino, nome), fonte);
}
// `provider.ts` importa o tipo das evidências só para tipar; um stub basta.
writeFileSync(join(destino, "evidence.ts"), "export type KnowledgeEvidence = unknown;\n");

const imp = (n) => import(pathToFileURL(join(destino, n)).href);
const { AnthropicProvider } = await imp("anthropic.ts");
const { ProviderError } = await imp("provider.ts");
const CFG = await imp("config.ts");
const { resolveProvider } = await imp("index.ts");

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
process.stdout.write("\nCONFIGURAÇÃO — o parser puro (llm/config.ts), sem process.env\n");

// Valores inventados, com cara de chave só para o teste procurar por eles.
const CHAVE_CFG = "sk-ant-FAKE-CFG9";
const cfg = (env) => CFG.readProviderConfig(env);
const motivo = (env) => {
  const r = cfg(env);
  return r.configured ? "configured" : r.reason;
};
const COMPLETO = { BRAIN_LLM_PROVIDER: "anthropic", BRAIN_LLM_MODEL: "claude-x", BRAIN_LLM_API_KEY: CHAVE_CFG };

confere("CFG1 provedor ausente → provider_missing",
  motivo({ BRAIN_LLM_MODEL: "claude-x", BRAIN_LLM_API_KEY: CHAVE_CFG }) === "provider_missing" &&
  motivo({}) === "provider_missing");
confere("CFG2 provedor \"\" ou \"   \" → provider_missing",
  motivo({ ...COMPLETO, BRAIN_LLM_PROVIDER: "" }) === "provider_missing" &&
  motivo({ ...COMPLETO, BRAIN_LLM_PROVIDER: "   " }) === "provider_missing");
const r3 = cfg({ ...COMPLETO, BRAIN_LLM_PROVIDER: "openai" });
confere("CFG3 \"openai\" → provider_unsupported, e o valor recusado não volta no resultado",
  r3.configured === false && r3.reason === "provider_unsupported" && !JSON.stringify(r3).includes("openai"),
  JSON.stringify(r3));
const r3b = cfg({ ...COMPLETO, BRAIN_LLM_PROVIDER: CHAVE_CFG });
confere("CFG3b a chave colada na variável do provedor → provider_unsupported, sem ecoar a chave",
  r3b.configured === false && r3b.reason === "provider_unsupported" && !JSON.stringify(r3b).includes("sk-ant"));
confere("CFG3c none / OFF / Disabled → provider_disabled (o rollback), mesmo com chave e modelo cadastrados",
  ["none", "OFF", " Disabled "].every((v) => motivo({ ...COMPLETO, BRAIN_LLM_PROVIDER: v }) === "provider_disabled"));
confere("CFG4 modelo ausente → model_missing",
  motivo({ BRAIN_LLM_PROVIDER: "anthropic", BRAIN_LLM_API_KEY: CHAVE_CFG }) === "model_missing");
confere("CFG5 modelo \"   \" → model_missing",
  motivo({ ...COMPLETO, BRAIN_LLM_MODEL: "   " }) === "model_missing");
confere("CFG5b ordem provedor → modelo → chave: sem modelo e sem chave, o motivo é o modelo",
  motivo({ BRAIN_LLM_PROVIDER: "anthropic" }) === "model_missing" &&
  motivo({ BRAIN_LLM_PROVIDER: "openai" }) === "provider_unsupported");
confere("CFG6 chave ausente → key_missing",
  motivo({ BRAIN_LLM_PROVIDER: "anthropic", BRAIN_LLM_MODEL: "claude-x" }) === "key_missing");
confere("CFG7 chave \"\" → key_missing", motivo({ ...COMPLETO, BRAIN_LLM_API_KEY: "" }) === "key_missing");
confere("CFG8 chave \"   \" → key_missing", motivo({ ...COMPLETO, BRAIN_LLM_API_KEY: "   " }) === "key_missing");
const r9 = cfg({ BRAIN_LLM_PROVIDER: " Anthropic ", BRAIN_LLM_MODEL: "claude-x", BRAIN_LLM_API_KEY: "sk-ant-FAKE-CFG9" });
confere("CFG9 configuração completa (com espaços e maiúscula) → configured, anthropic, claude-x, e o resultado não tem a chave",
  r9.configured === true && r9.provider === "anthropic" && r9.model === "claude-x" &&
  Object.keys(r9).sort().join() === "configured,model,provider" && !JSON.stringify(r9).includes("sk-ant"),
  JSON.stringify(r9));

// CFG10: todo caso de falha, e toda mensagem, sem nada com cara de chave.
const CHAVE_10 = "sk-ant-FAKE-CFG10";
const falhos = [
  {}, { BRAIN_LLM_PROVIDER: CHAVE_10, BRAIN_LLM_MODEL: CHAVE_10, BRAIN_LLM_API_KEY: CHAVE_10 },
  { BRAIN_LLM_PROVIDER: "none", BRAIN_LLM_MODEL: "claude-x", BRAIN_LLM_API_KEY: CHAVE_10 },
  { BRAIN_LLM_PROVIDER: "anthropic", BRAIN_LLM_API_KEY: CHAVE_10 },
  { BRAIN_LLM_PROVIDER: "anthropic", BRAIN_LLM_MODEL: "claude-x", BRAIN_LLM_API_KEY: "  " },
  { BRAIN_LLM_PROVIDER: "anthropic", BRAIN_LLM_MODEL: CHAVE_10, BRAIN_LLM_API_KEY: CHAVE_10 },
  { BRAIN_LLM_PROVIDER: "anthropic", BRAIN_LLM_MODEL: "claude-x", BRAIN_LLM_API_KEY: `${CHAVE_10} x` },
].map(cfg);
const mensagens = CFG.PROVIDER_CONFIG_REASONS.map((r) => CFG.providerConfigMessage(r));
confere("CFG10 nenhum resultado de falha nem mensagem traz valor com cara de chave (sk-ant-FAKE); os 7 motivos, 7 mensagens",
  falhos.every((r) => r.configured === false && !JSON.stringify(r).includes("sk-ant-FAKE")) &&
  new Set(falhos.map((r) => r.reason)).size === 7 && CFG.PROVIDER_CONFIG_REASONS.length === 7 &&
  mensagens.length === 7 && new Set(mensagens).size === 7 &&
  mensagens.every((m) => typeof m === "string" && m.length > 0 && !m.includes("sk-ant")),
  falhos.map((r) => r.reason).join(" · "));

// CFG16–CFG17 (revisão adversarial S1/S2, 26/09): o modelo vai ao LOG em
// todo evento, então a chave colada nele virava `"model":"sk-ant-…"`; e uma
// chave com espaço, controle ou não-ASCII passava na configuração e virava
// erro de REDE (o undici recusa o cabeçalho) em toda consulta.
const CANARIO_16 = "sk-ant-api03-CANARY";
const r16 = cfg({ ...COMPLETO, BRAIN_LLM_MODEL: CANARIO_16 });
confere("CFG16 modelo com cara de chave (\"sk-ant-api03-CANARY\") → model_invalid; o canário não está no resultado nem em mensagem nenhuma",
  r16.configured === false && r16.reason === "model_invalid" && !JSON.stringify(r16).includes("CANARY") &&
  !mensagens.join("\n").includes("CANARY") && !CFG.providerConfigMessage("model_invalid").includes("CANARY") &&
  motivo({ ...COMPLETO, BRAIN_LLM_MODEL: "SK-live-1" }) === "model_invalid",
  JSON.stringify(r16));
const r16b = cfg({ ...COMPLETO, BRAIN_LLM_MODEL: "claude-sonnet-4.5" });
confere("CFG16b \"claude-sonnet-4.5\" (e claude-x@2026, anthropic.claude-v2:1, 100 caracteres) → configured, modelo como veio",
  r16b.configured === true && r16b.model === "claude-sonnet-4.5" &&
  ["claude-x@2026", "anthropic.claude-v2:1", "a".repeat(100), "claude_3"].every((m) => motivo({ ...COMPLETO, BRAIN_LLM_MODEL: m }) === "configured"),
  JSON.stringify(r16b));
confere("CFG16c modelo com espaço interno, barra, aspas, quebra de linha, 101 caracteres ou começando por '-' → model_invalid",
  ["claude sonnet", "claude/x", '"claude-x"', "claude\nx", "a".repeat(101), "-claude", "clau\u200bde", "modelo-ç"]
    .every((m) => motivo({ ...COMPLETO, BRAIN_LLM_MODEL: m }) === "model_invalid"));
confere("CFG16d ordem: modelo inválido vem antes da chave (sem chave nenhuma, o motivo é o modelo)",
  motivo({ BRAIN_LLM_PROVIDER: "anthropic", BRAIN_LLM_MODEL: CANARIO_16 }) === "model_invalid");
const r17a = cfg({ ...COMPLETO, BRAIN_LLM_API_KEY: "sk-ant-a\nb" });
confere("CFG17a chave com quebra de linha, tab ou espaço INTERNO → key_invalid, sem ecoar a chave",
  r17a.configured === false && r17a.reason === "key_invalid" && !JSON.stringify(r17a).includes("sk-ant") &&
  ["sk-ant-a\tb", "sk-ant-a b", "sk-ant-a\rb", "sk-ant-\u0000x", "sk-ant-\u007fx"].every((k) => motivo({ ...COMPLETO, BRAIN_LLM_API_KEY: k }) === "key_invalid"));
confere("CFG17b chave com ZWSP (U+200B) ou NBSP interno → key_invalid (trim não tira ZWSP)",
  motivo({ ...COMPLETO, BRAIN_LLM_API_KEY: "sk-ant-\u200bx" }) === "key_invalid" &&
  motivo({ ...COMPLETO, BRAIN_LLM_API_KEY: "\u200bsk-ant-x" }) === "key_invalid" &&
  motivo({ ...COMPLETO, BRAIN_LLM_API_KEY: "sk-ant-\u00a0x" }) === "key_invalid");
confere("CFG17c chave com não-ASCII (ç, €) → key_invalid; ASCII visível com espaço só nas pontas → configured",
  motivo({ ...COMPLETO, BRAIN_LLM_API_KEY: "sk-ant-çx" }) === "key_invalid" &&
  motivo({ ...COMPLETO, BRAIN_LLM_API_KEY: "sk-ant-€x" }) === "key_invalid" &&
  motivo({ ...COMPLETO, BRAIN_LLM_API_KEY: "  sk-ant-FAKE_~!#$%&*+=?^{|}  " }) === "configured");
const FONTE_CFG = readFileSync(join(RAIZ, "src/modules/brain/llm/config.ts"), "utf8");
confere("CFG11 config.ts é puro: sem server-only e sem process.env (quem chama passa o ambiente)",
  !FONTE_CFG.includes('import "server-only"') && !/process\.env/.test(FONTE_CFG.replace(/\/\*[\s\S]*?\*\/|\/\/.*$/gm, "")));

// ── resolveProvider de ponta a ponta, com ambiente inventado ─────────────
const CHAVE_RES = "sk-ant-FAKE-RESOLVE-0000";
const res = resolveProvider({ BRAIN_LLM_PROVIDER: "anthropic", BRAIN_LLM_MODEL: "claude-x", BRAIN_LLM_API_KEY: ` ${CHAVE_RES} ` });
confere("CFG12 resolveProvider(env completo) → AnthropicProvider, reason null, modelo do ambiente",
  res.reason === null && res.provider instanceof AnthropicProvider && res.provider.model === "claude-x");
confere("CFG13 nem o provedor resolvido nem o resultado deixam a chave à mostra (JSON, inspect)",
  !JSON.stringify(res).includes(CHAVE_RES) &&
  !inspect(res, { showHidden: true, depth: 5 }).includes(CHAVE_RES) &&
  !Object.values(res.provider).some((v) => String(v).includes(CHAVE_RES)));
const espiaoRes = espiar(respostaBoa());
await res.provider.generate(ENTRADA);
confere("CFG14 a chave (aparada) chega só ao cabeçalho x-api-key",
  espiaoRes.chamadas[0].init.headers["x-api-key"] === CHAVE_RES && !espiaoRes.chamadas[0].init.body.includes(CHAVE_RES));
const semKey = resolveProvider({ BRAIN_LLM_PROVIDER: "anthropic", BRAIN_LLM_MODEL: "claude-x" });
const desligado = resolveProvider({ BRAIN_LLM_PROVIDER: "off", BRAIN_LLM_MODEL: "claude-x", BRAIN_LLM_API_KEY: CHAVE_RES });
confere("CFG15 resolveProvider(env incompleto ou desligado) → { provider: null, reason }, sem a chave",
  semKey.provider === null && semKey.reason === "key_missing" &&
  desligado.provider === null && desligado.reason === "provider_disabled" && !JSON.stringify(desligado).includes(CHAVE_RES));

// ───────────────────────────────────────────────────────────────────────────
process.stdout.write("\nPREFLIGHT — o script manual (brain:preflight), como processo filho\n");

// cwd num diretório temporário FORA do repositório: nenhum `.env.local` de
// verdade é lido. O ambiente do filho é só o que o teste passa.
const vazio = mkdtempSync(join(tmpdir(), "brain-preflight-"));
const SCRIPT = join(RAIZ, "supabase/db-tests/preflight-brain-provider.mjs");
const preflight = (env, args = []) => {
  const r = spawnSync(process.execPath, ["--experimental-strip-types", "--no-warnings", SCRIPT, ...args],
    { cwd: vazio, env, encoding: "utf8" });
  return { code: r.status, out: r.stdout ?? "", err: r.stderr ?? "" };
};
try {
  const CHAVE_PF = "sk-ant-FAKE-PREFLIGHT";
  const ENV_PF = { BRAIN_LLM_PROVIDER: "anthropic", BRAIN_LLM_MODEL: "modelo-pf-canario", BRAIN_LLM_API_KEY: CHAVE_PF };
  const pf1 = preflight(ENV_PF);
  confere("PF1 configuração completa → exit 0, PRONTO, a chave aparece só como 'presente' (nem valor, nem tamanho)",
    pf1.code === 0 && /BRAIN_LLM_API_KEY\s+presente/.test(pf1.out) && pf1.out.includes("PRONTO PARA PRODUÇÃO (configuração)") &&
    !pf1.out.includes(CHAVE_PF) && !pf1.out.includes("sk-ant") && !pf1.out.includes(String(CHAVE_PF.length)) &&
    !pf1.out.includes("modelo-pf-canario") && !(pf1.out + pf1.err).includes(CHAVE_PF),
    `exit ${pf1.code}`);
  const pf2 = preflight({ ...ENV_PF, NEXT_PUBLIC_BRAIN_LLM_API_KEY: CHAVE_PF });
  confere("PF2 NEXT_PUBLIC_BRAIN_LLM_API_KEY definida → exit 2, nomeia a variável, sem o valor",
    pf2.code === 2 && pf2.out.includes("NEXT_PUBLIC_BRAIN_LLM_API_KEY") && !(pf2.out + pf2.err).includes(CHAVE_PF),
    `exit ${pf2.code}`);
  const pf3 = preflight({});
  confere("PF3 nenhuma variável → exit 1, NÃO CONFIGURADO: provider_missing",
    pf3.code === 1 && pf3.out.includes("NÃO CONFIGURADO: provider_missing") && /BRAIN_LLM_API_KEY\s+ausente/.test(pf3.out),
    `exit ${pf3.code}`);
  const pf4 = preflight({ BRAIN_LLM_PROVIDER: "openai-canario", BRAIN_LLM_MODEL: "m", BRAIN_LLM_API_KEY: CHAVE_PF });
  confere("PF4 provedor não suportado → exit 1, provider_unsupported, sem ecoar o valor",
    pf4.code === 1 && pf4.out.includes("provider_unsupported") && !pf4.out.includes("openai-canario") && !pf4.out.includes(CHAVE_PF),
    `exit ${pf4.code}`);
  const pf5a = preflight({ ...ENV_PF, NEXT_PUBLIC_BRAIN_LLM_API_KEY: CHAVE_PF }, ["--contract"]);
  const pf5b = preflight({}, ["--contract"]);
  confere("PF5 --contract → exit 0 com qualquer ambiente, e nenhum VALOR do ambiente na saída",
    pf5a.code === 0 && pf5b.code === 0 && pf5a.out === pf5b.out &&
    pf5a.out.includes("BRAIN_LLM_API_KEY") && pf5a.out.includes("<secret>") &&
    !pf5a.out.includes(CHAVE_PF) && !pf5a.out.includes("modelo-pf-canario") && !pf5a.out.includes("sk-ant"),
    `exit ${pf5a.code}/${pf5b.code}`);
  const pf7 = preflight({ ...ENV_PF, BRAIN_LLM_MODEL: "sk-ant-api03-CANARY-PF7" });
  confere("PF7 BRAIN_LLM_MODEL com cara de chave → exit 1, model_invalid, o canário fora de stdout e stderr",
    pf7.code === 1 && pf7.out.includes("NÃO CONFIGURADO: model_invalid") &&
    !(pf7.out + pf7.err).includes("CANARY") && !(pf7.out + pf7.err).includes(CHAVE_PF),
    `exit ${pf7.code}`);
  const pf7b = preflight(ENV_PF, ["--verbose"]);
  const pf7c = preflight(ENV_PF, [CHAVE_PF]);
  confere("PF7b argumento desconhecido (--verbose, ou a chave colada como argumento) → exit 1, linha de uso, sem ecoar o argumento",
    pf7b.code === 1 && pf7b.err.includes("uso: npm run brain:preflight") && !pf7b.out.includes("VEREDITO") &&
    pf7c.code === 1 && !(pf7c.out + pf7c.err).includes(CHAVE_PF),
    `exit ${pf7b.code}/${pf7c.code}`);

  // PF8–PF11: o `.env.local` de verdade, escrito num diretório temporário
  // (o processo filho não recebe as variáveis pelo ambiente). Cada caso tem
  // o seu diretório.
  const comArquivo = (conteudo, args = []) => {
    const dir = mkdtempSync(join(tmpdir(), "brain-preflight-env-"));
    try {
      if (conteudo === null) mkdirSync(join(dir, ".env.local"));
      else writeFileSync(join(dir, ".env.local"), conteudo);
      const r = spawnSync(process.execPath, ["--experimental-strip-types", "--no-warnings", SCRIPT, ...args],
        { cwd: dir, env: {}, encoding: "utf8" });
      return { code: r.status, out: r.stdout ?? "", err: r.stderr ?? "" };
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  };
  const CHAVE_ARQ = "sk-ant-FAKE-ARQUIVO-PF8";
  const pf8 = comArquivo([
    "# comentário",
    'export BRAIN_LLM_PROVIDER="anthropic"',
    "export OUTRA=\"x y\"",
    "BRAIN_LLM_MODEL='claude-x'   # nota depois das aspas",
    `BRAIN_LLM_API_KEY=${CHAVE_ARQ} # comentário no fim`,
    "",
  ].join("\n"));
  confere("PF8 .env.local com export, aspas duplas/simples, `export K=\"x y\"` e comentário depois do valor → exit 0, PRONTO, sem valor na saída",
    pf8.code === 0 && pf8.out.includes("PRONTO PARA PRODUÇÃO") && pf8.out.includes("+ .env.local") &&
    !(pf8.out + pf8.err).includes(CHAVE_ARQ) && !(pf8.out + pf8.err).includes("x y"),
    `exit ${pf8.code} ${pf8.err.trim()}`);
  const base9 = "BRAIN_LLM_PROVIDER=anthropic\nBRAIN_LLM_MODEL=claude-x\n";
  const pf9a = comArquivo(`${base9}BRAIN_LLM_API_KEY=\n`);
  const pf9b = comArquivo(`${base9}BRAIN_LLM_API_KEY=#${CHAVE_ARQ}\n`);
  const pf9c = comArquivo(`${base9}BRAIN_LLM_API_KEY= # só comentário\n`);
  confere("PF9 `KEY=` e `KEY=#x` (como no dotenv: valor que começa com # é comentário) → exit 1, key_missing, sem o valor",
    [pf9a, pf9b, pf9c].every((r) => r.code === 1 && r.out.includes("NÃO CONFIGURADO: key_missing")) &&
    !(pf9b.out + pf9b.err).includes(CHAVE_ARQ),
    [pf9a, pf9b, pf9c].map((r) => `exit ${r.code}`).join(" "));
  const pf10a = comArquivo(null);
  const pf10b = comArquivo(`${base9}BRAIN_LLM_API_KEY="${CHAVE_ARQ}\ncontinua"\n`);
  const semPilha = (r) => !/\n\s+at |Error:|node:internal|file:\/\//.test(r.out + r.err);
  confere("PF10 .env.local que é DIRETÓRIO → exit 1, 'não foi possível ler .env.local (EISDIR)', sem pilha",
    pf10a.code === 1 && pf10a.err.includes("não foi possível ler .env.local (EISDIR)") && semPilha(pf10a) && !pf10a.out.includes("VEREDITO"),
    `exit ${pf10a.code} ${pf10a.err.trim()}`);
  confere("PF10b valor multilinha entre aspas → exit 1, 'valor multilinha não suportado … use uma linha', nomeia só a variável, sem o valor",
    pf10b.code === 1 && pf10b.err.includes("valor multilinha não suportado") && pf10b.err.includes("BRAIN_LLM_API_KEY") &&
    pf10b.err.includes("use uma linha") && !(pf10b.out + pf10b.err).includes(CHAVE_ARQ) && !(pf10b.out + pf10b.err).includes("continua") && semPilha(pf10b),
    `exit ${pf10b.code} ${pf10b.err.trim()}`);
  const pf11 = comArquivo(`\uFEFFBRAIN_LLM_PROVIDER=anthropic\r\nBRAIN_LLM_MODEL=claude-x\r\nBRAIN_LLM_API_KEY=${CHAVE_ARQ}\r\n`);
  confere("PF11 .env.local com BOM e CRLF → exit 0, PRONTO (nem o BOM entra no nome, nem o \\r entra no valor)",
    pf11.code === 0 && pf11.out.includes("PRONTO PARA PRODUÇÃO") && !(pf11.out + pf11.err).includes(CHAVE_ARQ),
    `exit ${pf11.code}`);
  const FONTE_PF = readFileSync(SCRIPT, "utf8");
  confere("PF6 o script não importa rede, banco nem provedor (só fs, path, url e o parser)",
    !/node:(http|https|net|tls|dgram|child_process)|fetch\(|@supabase|anthropic\.ts|llm\/index/.test(FONTE_PF));
} finally {
  rmSync(vazio, { recursive: true, force: true });
}

// ───────────────────────────────────────────────────────────────────────────
globalThis.fetch = fetchOriginal;
rmSync(destino, { recursive: true, force: true });

process.stdout.write(
  falhas === 0
    ? "\nADAPTER ANTHROPIC, CONFIGURAÇÃO E PREFLIGHT — tudo certo (sem rede, sem chave real).\n\n"
    : `\nADAPTER ANTHROPIC — ${falhas} falha(s).\n\n`);
process.exit(falhas === 0 ? 0 : 1);
