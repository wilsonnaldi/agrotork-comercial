/**
 * PREFLIGHT do provedor de síntese do BRAIN — manual, local, sem rede.
 *
 *   npm run brain:preflight              confere o ambiente desta máquina
 *   npm run brain:preflight -- --contract  só imprime o contrato (ignora o ambiente)
 *
 * Para quê: antes de cadastrar (ou depois de mudar) as variáveis do provedor
 * no painel da Netlify, saber se a configuração FECHA — sem ligar para o
 * provedor, sem banco e sem imprimir valor nenhum. É a mesma regra que o
 * servidor usa (`readProviderConfig`, em `src/modules/brain/llm/config.ts`),
 * não uma cópia.
 *
 * O que ele NÃO faz, de propósito:
 *   · não imprime valor, nem pedaço, nem tamanho de variável — só
 *     `presente`/`ausente`. O tamanho de uma chave já diz algo sobre ela, e
 *     esta saída acaba colada em chat e relatório;
 *   · não testa se a chave é válida: isso exigiria chamar o provedor, e o
 *     preflight não sai da máquina;
 *   · não entra no CI (o nome não começa com `check:brain`, então a guarda
 *     `check:brain-ci` não o exige lá). O CI roda sem chave, de propósito.
 *
 * Fonte: o ambiente do processo e os arquivos `.env*` do diretório atual (o
 * `npm run` roda na raiz do repositório), lidos pelo MESMO carregador do Next
 * (`@next/env`, `loadEnvConfig(dir, false)`), no modo de produção:
 * `.env.production.local` → `.env.local` → `.env.production` → `.env`. Por
 * que o carregador do Next e não um parser próprio: a revisão independente
 * (26/09) achou divergência real — `KEY=FAKEabc#def` o Next lê como
 * `FAKEabc`, e `"FAKE\nabc"` entre aspas duplas vira quebra de linha de
 * verdade. Um preflight que lê diferente do servidor dá veredito falso, nos
 * dois sentidos. Como no Next, o ambiente do processo vence os arquivos, e
 * nada dos arquivos é impresso — só os NOMES dos arquivos carregados.
 *
 * Saída (exit code):
 *   0  configuração completa (ou `--contract`)
 *   1  não configurado — o motivo sai da lista fechada de `config.ts` —, ou
 *      arquivo `.env*` ilegível, ou argumento desconhecido
 *   2  existe variável `NEXT_PUBLIC_BRAIN_LLM*`: isso mandaria o valor para o
 *      navegador, e é erro mesmo que o resto esteja certo
 */
import { statSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const RAIZ = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const {
  PROVIDER_ENV,
  SUPPORTED_PROVIDERS,
  DISABLED_VALUES,
  PROVIDER_CONFIG_REASONS,
  readProviderConfig,
  providerConfigMessage,
} = await import(pathToFileURL(join(RAIZ, "src/modules/brain/llm/config.ts")).href);

const PREFIXO_PROIBIDO = "NEXT_PUBLIC_BRAIN_LLM";
const out = (t = "") => process.stdout.write(`${t}\n`);
const falha = (t) => {
  process.stderr.write(`${t}\n`);
  process.exit(1);
};

// Só `--contract` existe. Qualquer outro argumento é erro, e não é ecoado:
// alguém pode ter colado a chave na linha de comando.
const ARGS_ACEITOS = new Set(["--contract"]);
if (process.argv.slice(2).some((a) => !ARGS_ACEITOS.has(a))) {
  falha("uso: npm run brain:preflight [-- --contract]  (argumento desconhecido; nada foi conferido)");
}

if (process.argv.includes("--contract")) {
  // Só o contrato: nomes, valores ACEITOS e regras. O ambiente nem é lido.
  out("BRAIN — contrato de configuração do provedor de síntese");
  out("");
  out("Variáveis (escopo: Production, só servidor; nunca NEXT_PUBLIC_):");
  out(`  ${PROVIDER_ENV.provider.padEnd(22)} ${SUPPORTED_PROVIDERS.join(" | ")}  ou  ${DISABLED_VALUES.join(" | ")} (desliga)`);
  out(`  ${PROVIDER_ENV.model.padEnd(22)} identificador do modelo: letras, dígitos e . _ : @ - (até 100), nunca sk-…`);
  out(`  ${PROVIDER_ENV.apiKey.padEnd(22)} <secret>, só ASCII visível (sem espaço interno, quebra de linha ou acento)`);
  out("");
  out("Regras:");
  out("  · valores com espaço nas pontas são aparados; vazio ou só espaço = ausente");
  out("  · ordem das conferências: provedor → modelo (ausente → inválido) → chave (ausente → inválida)");
  out("  · arquivos lidos como o servidor Next em produção (@next/env), do diretório atual:");
  out("    .env.production.local → .env.local → .env.production → .env (o ambiente do processo vence)");
  out("  · configuração pela metade = síntese desligada (resposta extractiva)");
  out(`  · qualquer ${PREFIXO_PROIBIDO}* é erro (o valor iria para o navegador)`);
  out("");
  out("Motivos de não configurado (vão ao log como `reason` do outcome no_provider):");
  for (const r of PROVIDER_CONFIG_REASONS) out(`  ${r.padEnd(22)} ${providerConfigMessage(r)}`);
  process.exit(0);
}

// Daqui para baixo o ambiente é lido. `--contract` já saiu acima sem tocar
// em arquivo nenhum — nem o carregador é importado antes deste ponto.

// Os arquivos que `next start` / `next build` carregam (modo produção), na
// ordem de precedência do próprio `@next/env`.
const ARQUIVOS_ENV = [".env.production.local", ".env.local", ".env.production", ".env"];

// Um `.env*` que é DIRETÓRIO o Next ignora em silêncio (só lê arquivo). Aqui
// é erro: quase sempre é engano, e seguir adiante daria "não configurado"
// sem dizer por quê. Só o código do erro sai — sem pilha (a pilha traz
// caminho absoluto e não ajuda quem roda).
for (const nome of ARQUIVOS_ENV) {
  let info = null;
  try {
    info = statSync(join(process.cwd(), nome));
  } catch (erro) {
    if (erro?.code !== "ENOENT") falha(`não foi possível ler ${nome} (${erro?.code ?? "erro desconhecido"}); nada foi conferido`);
  }
  if (info?.isDirectory()) falha(`não foi possível ler ${nome} (EISDIR); nada foi conferido`);
}

// Com NODE_ENV=test o `@next/env` troca o conjunto de arquivos (.env.test*)
// e pula o `.env.local`. O servidor de produção nunca roda assim; o preflight
// confere o conjunto de produção, sempre.
if (process.env.NODE_ENV === "test") delete process.env.NODE_ENV;

// `@next/env` vem com o `next` (dependência dele, instalada na raiz do
// `node_modules`) — a mesma versão que o servidor usa. É CommonJS sem
// export nomeado detectável pelo Node: import default.
// Importado só aqui, depois do `--contract`, para que o contrato nunca
// dependa do disco.
const { default: nextEnv } = await import("@next/env");
// O carregador reporta falha de leitura (permissão…) pelo `log.error`, com
// o erro inteiro — e, em erro de parse, o caminho absoluto. Nada disso vai
// para a tela: guardamos só o nome do arquivo e o código.
const errosLeitura = [];
const { loadedEnvFiles } = nextEnv.loadEnvConfig(process.cwd(), false, {
  info: () => {},
  error: (mensagem, erro) => {
    const nome = ARQUIVOS_ENV.find((n) => String(mensagem).endsWith(n)) ?? "arquivo .env";
    errosLeitura.push(`${nome} (${erro?.code ?? "erro desconhecido"})`);
  },
});
if (errosLeitura.length > 0) falha(`não foi possível ler ${errosLeitura.join(", ")}; nada foi conferido`);
const carregados = loadedEnvFiles.map((f) => f.path);
// O próprio process.env, já com os arquivos aplicados por baixo do ambiente
// (é o que o servidor enxerga).
const env = process.env;

const presente = (nome) => (typeof env[nome] === "string" && env[nome].trim() !== "" ? "presente" : "ausente");
// Nomes não são segredo; valores são. Só os nomes saem.
const publicas = Object.keys(env).filter((n) => n.toUpperCase().startsWith(PREFIXO_PROIBIDO)).sort();
const config = readProviderConfig(env);

const provedorLido = (env[PROVIDER_ENV.provider] ?? "").trim().toLowerCase();
const suportado = provedorLido === ""
  ? "—"
  : SUPPORTED_PROVIDERS.includes(provedorLido) ? "sim" : DISABLED_VALUES.includes(provedorLido) ? "desligado" : "não";

out("BRAIN — preflight do provedor de síntese (só configuração; nenhuma chamada ao provedor)");
out(`Fonte: ambiente do processo${carregados.length > 0 ? ` + ${carregados.join(" + ")}` : " (nenhum .env* neste diretório)"}`);
out("");
out(`  ${PROVIDER_ENV.provider.padEnd(26)} ${presente(PROVIDER_ENV.provider)}`);
out(`  ${PROVIDER_ENV.model.padEnd(26)} ${presente(PROVIDER_ENV.model)}`);
out(`  ${PROVIDER_ENV.apiKey.padEnd(26)} ${presente(PROVIDER_ENV.apiKey)}`);
out(`  ${`${PREFIXO_PROIBIDO}*`.padEnd(26)} ${publicas.length === 0 ? "nenhuma (correto)" : `ERRO: ${publicas.join(", ")}`}`);
out(`  ${"provedor suportado".padEnd(26)} ${suportado}`);
out(`  ${"modelo preenchido".padEnd(26)} ${presente(PROVIDER_ENV.model) === "presente" ? "sim" : "não"}`);
out("");

if (publicas.length > 0) {
  out(`VEREDITO: ERRO — remova ${publicas.join(", ")}: prefixo NEXT_PUBLIC_ entrega o valor ao navegador.`);
  process.exit(2);
}
if (config.configured) {
  out("VEREDITO: PRONTO PARA PRODUÇÃO (configuração)");
  out("  A validade da chave não é testada aqui: isso exige chamar o provedor.");
  process.exit(0);
}
out(`VEREDITO: NÃO CONFIGURADO: ${config.reason}`);
out(`  ${providerConfigMessage(config.reason)}`);
process.exit(1);
