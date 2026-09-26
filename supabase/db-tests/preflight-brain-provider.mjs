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
 * Fonte: o ambiente do processo e, se existir, o `.env.local` do diretório
 * atual (o `npm run` roda na raiz do repositório). Como no Next, o ambiente
 * do processo vence o arquivo. O arquivo é lido linha a linha só para saber
 * quais nomes estão definidos e entregar os valores ao parser — nada dele é
 * impresso.
 *
 * Saída (exit code):
 *   0  configuração completa (ou `--contract`)
 *   1  não configurado — o motivo sai da lista fechada de `config.ts`
 *   2  existe variável `NEXT_PUBLIC_BRAIN_LLM*`: isso mandaria o valor para o
 *      navegador, e é erro mesmo que o resto esteja certo
 */
import { existsSync, readFileSync } from "node:fs";
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

if (process.argv.includes("--contract")) {
  // Só o contrato: nomes, valores ACEITOS e regras. O ambiente nem é lido.
  out("BRAIN — contrato de configuração do provedor de síntese");
  out("");
  out("Variáveis (escopo: Production, só servidor; nunca NEXT_PUBLIC_):");
  out(`  ${PROVIDER_ENV.provider.padEnd(22)} ${SUPPORTED_PROVIDERS.join(" | ")}  ou  ${DISABLED_VALUES.join(" | ")} (desliga)`);
  out(`  ${PROVIDER_ENV.model.padEnd(22)} identificador do modelo, não vazio`);
  out(`  ${PROVIDER_ENV.apiKey.padEnd(22)} <secret>, não vazio`);
  out("");
  out("Regras:");
  out("  · valores com espaço nas pontas são aparados; vazio ou só espaço = ausente");
  out("  · ordem das conferências: provedor → modelo → chave");
  out("  · configuração pela metade = síntese desligada (resposta extractiva)");
  out(`  · qualquer ${PREFIXO_PROIBIDO}* é erro (o valor iria para o navegador)`);
  out("");
  out("Motivos de não configurado (vão ao log como `reason` do outcome no_provider):");
  for (const r of PROVIDER_CONFIG_REASONS) out(`  ${r.padEnd(22)} ${providerConfigMessage(r)}`);
  process.exit(0);
}

/**
 * `.env.local` no formato do Next/dotenv, o bastante para este uso: `NOME=valor`,
 * `export NOME=valor`, comentário com `#`, aspas simples ou duplas em volta.
 * Linha que não fecha nesse formato é ignorada — nunca ecoada.
 */
function lerEnvLocal(caminho) {
  const env = {};
  for (const linha of readFileSync(caminho, "utf8").split(/\r?\n/)) {
    const m = linha.match(/^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$/);
    if (!m) continue;
    let valor = m[2].trim();
    const aspas = valor[0];
    if ((aspas === '"' || aspas === "'") && valor.endsWith(aspas) && valor.length >= 2) {
      valor = valor.slice(1, -1);
    } else {
      valor = valor.replace(/\s+#.*$/, "");
    }
    env[m[1]] = valor;
  }
  return env;
}

const arquivo = join(process.cwd(), ".env.local");
const temArquivo = existsSync(arquivo);
const env = { ...(temArquivo ? lerEnvLocal(arquivo) : {}), ...process.env };

const presente = (nome) => (typeof env[nome] === "string" && env[nome].trim() !== "" ? "presente" : "ausente");
// Nomes não são segredo; valores são. Só os nomes saem.
const publicas = Object.keys(env).filter((n) => n.toUpperCase().startsWith(PREFIXO_PROIBIDO)).sort();
const config = readProviderConfig(env);

const provedorLido = (env[PROVIDER_ENV.provider] ?? "").trim().toLowerCase();
const suportado = provedorLido === ""
  ? "—"
  : SUPPORTED_PROVIDERS.includes(provedorLido) ? "sim" : DISABLED_VALUES.includes(provedorLido) ? "desligado" : "não";

out("BRAIN — preflight do provedor de síntese (só configuração; nenhuma chamada ao provedor)");
out(`Fonte: ambiente do processo${temArquivo ? " + .env.local" : " (sem .env.local neste diretório)"}`);
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
