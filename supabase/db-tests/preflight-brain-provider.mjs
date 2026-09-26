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
 * atual (o `npm run` roda na raiz do repositório) — só esse arquivo: nem
 * `.env`, nem `.env.production`, nem `.env.local` de diretório pai. Como no
 * Next, o ambiente do processo vence o arquivo. O arquivo é lido linha a
 * linha só para saber quais nomes estão definidos e entregar os valores ao
 * parser — nada dele é impresso. Uma variável por linha: valor multilinha
 * entre aspas é recusado (exit 1), em vez de lido pela metade.
 *
 * Saída (exit code):
 *   0  configuração completa (ou `--contract`)
 *   1  não configurado — o motivo sai da lista fechada de `config.ts` —, ou
 *      `.env.local` ilegível, ou valor multilinha, ou argumento desconhecido
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
  out("  · arquivo lido: só o .env.local do diretório atual, uma variável por linha (multilinha = erro)");
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
 *
 * Achados da revisão adversarial (S5, 26/09), agora iguais ao dotenv:
 *  · valor sem aspas que COMEÇA com `#` é comentário: `NOME=#x` vale vazio;
 *  · valor sem aspas é cortado no primeiro ` #` (espaço + cerquilha);
 *  · valor entre aspas pode ter comentário depois: `NOME="a b" # nota`;
 *  · BOM no começo do arquivo e CRLF não entram no valor.
 * Valor multilinha (aspas que não fecham na mesma linha) NÃO é suportado:
 * lê-lo pela metade daria um veredito falso, então é erro explícito — sem
 * imprimir o valor, só o nome.
 */
function lerEnvLocal(texto) {
  const env = {};
  for (const linha of texto.replace(/^\uFEFF/, "").split(/\r?\n/)) {
    const m = linha.match(/^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$/);
    if (!m) continue;
    const bruto = m[2].trim();
    const aspas = bruto[0];
    let valor;
    if (aspas === '"' || aspas === "'" || aspas === "`") {
      const fecha = bruto.indexOf(aspas, 1);
      const resto = fecha < 0 ? "" : bruto.slice(fecha + 1).trim();
      if (fecha < 0) falha(`valor multilinha não suportado em ${m[1]} (.env.local); use uma linha`);
      // Texto depois das aspas que não é comentário: fora do formato, ignorada.
      if (resto !== "" && !resto.startsWith("#")) continue;
      valor = bruto.slice(1, fecha);
    } else if (bruto.startsWith("#")) {
      valor = "";
    } else {
      valor = bruto.replace(/\s+#.*$/, "");
    }
    env[m[1]] = valor;
  }
  return env;
}

const arquivo = join(process.cwd(), ".env.local");
const temArquivo = existsSync(arquivo);
let textoArquivo = "";
if (temArquivo) {
  try {
    textoArquivo = readFileSync(arquivo, "utf8");
  } catch (erro) {
    // Diretório com esse nome, permissão negada…: só o código do erro, sem
    // pilha (a pilha traz caminho absoluto e não ajuda quem roda).
    falha(`não foi possível ler .env.local (${erro?.code ?? "erro desconhecido"}); nada foi conferido`);
  }
}
const env = { ...(temArquivo ? lerEnvLocal(textoArquivo) : {}), ...process.env };

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
