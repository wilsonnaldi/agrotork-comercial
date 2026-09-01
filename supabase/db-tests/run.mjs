/**
 * Runner OFICIAL dos testes de banco. Multiplataforma: Windows, macOS e
 * Linux, sem exigir `psql` instalado no host.
 *
 *   npm run db:test
 *
 * ────────────────────────────────────────────────────────────
 * POR QUE UM BANCO DESCARTÁVEL, E NÃO O BANCO LOCAL
 *
 * Esta suíte é uma SEQUÊNCIA, não um conjunto de arquivos soltos: 01 cria
 * os usuários que 02 usa, 02 cria o orçamento que 09 confere, e assim por
 * diante. Os identificadores são fixos de propósito — é o que torna as
 * asserções legíveis ("o vendedor 2222… não enxerga o orçamento do admin").
 *
 * Rodar isso sobre um banco já povoado dá `duplicate key` em cascata, e
 * "limpar tudo antes" destruiria justamente o encadeamento que dá sentido
 * aos testes. Por isso: banco novo, ordem controlada, migrations do zero.
 * De quebra, isso testa também que as 20 migrations aplicam em sequência.
 *
 * As asserções ESTRUTURAIS de segurança — RLS ligado, policies presentes,
 * funções `security definer`, buckets — não dependem de sequência e por
 * isso vivem em `supabase/tests/` como pgTAP, rodando contra o Supabase
 * local com `npx supabase test db`. As duas suítes se complementam.
 * ────────────────────────────────────────────────────────────
 *
 * Três formas de chegar a um PostgreSQL, nesta ordem:
 *   1. `psql` no PATH (mais rápido; é o caso do CI e do Linux/macOS);
 *   2. o container do Supabase local, se estiver de pé (não baixa nada);
 *   3. um container `postgres:16` descartável.
 *
 * Variáveis: PGHOST, PGPORT, PGUSER, PGPASSWORD, DB_TEST_STRATEGY
 * (`psql` | `supabase` | `docker`) para forçar uma delas.
 */
import { spawnSync } from "node:child_process";
import { readFileSync, readdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const AQUI = dirname(fileURLToPath(import.meta.url));
const RAIZ = join(AQUI, "..", "..");
const IMAGEM = "postgres:16";

/** Ordem obrigatória: cada arquivo conta com o estado deixado pelo anterior. */
const SUITES = [
  ["regras de negócio", "01_regras_de_negocio.sql", /^ [0-9]+[a-z]?\)/],
  ["row level security", "02_rls.sql", /^ [A-K]\)|NOTICE/],
  ["travas de orçamento e perfil", "04_travas_de_orcamento.sql", /^ [P-U]\)|NOTICE|BRECHA|OK:/],
  ["isolamento do custo do produto", "05_custo_produto.sql", /^ [V-Z]\)|^ A[A-C]\)|NOTICE/],
  ["origem do produto", "06_origem_produto.sql", /^ A[D-N]\)|NOTICE/],
  ["cadastros de apoio", "07_cadastros.sql", /^ B[A-Z]\)|NOTICE/],
  ["kits: obrigatórios e opcionais", "08_kits.sql", /^ [CD][A-Z]\)|NOTICE/],
  ["orçamentos", "09_orcamentos.sql", /^ [DEF][A-Z]\)|NOTICE/],
  ["compartilhamento", "10_compartilhamento.sql", /^ [FG][A-Z]\)|NOTICE/],
  ["storage", "11_storage.sql", /^ G[A-Z]\)|NOTICE/],
  ["cadastro: papel não vem do metadata", "12_cadastro.sql", /^ H[A-Z]\)|NOTICE/],
  ["expiração automática de orçamentos", "13_expiracao.sql", /^ I[A-Z]\)|NOTICE/],
  ["trilha de auditoria", "14_auditoria.sql", /^ J[A-Z]+\)|NOTICE/],
  ["triggers e privilégios", "03_triggers_e_privilegios.sql", /^ [L-O]\)|NOTICE|ORC-/],
];

function roda(cmd, args, opcoes = {}) {
  return spawnSync(cmd, args, { encoding: "utf8", ...opcoes });
}

function existe(cmd, args = ["--version"]) {
  const r = roda(cmd, args);
  return r.status === 0;
}

function nomeDoContainerSupabase() {
  const r = roda("docker", ["ps", "--filter", "name=supabase_db_", "--format", "{{.Names}}"]);
  if (r.status !== 0) return null;
  return r.stdout.trim().split("\n").filter(Boolean)[0] ?? null;
}

/** Decide como falar com o PostgreSQL e devolve um executor de SQL. */
function escolherEstrategia() {
  const forcada = process.env.DB_TEST_STRATEGY;
  // `docker --version` responde mesmo sem daemon; o que importa é o daemon.
  const temDocker = existe("docker", ["info"]);

  if ((!forcada || forcada === "psql") && existe("psql")) {
    const base = [
      "-h", process.env.PGHOST ?? "/tmp/pgrun",
      "-p", process.env.PGPORT ?? "5433",
      "-U", process.env.PGUSER ?? "postgres",
    ];
    // Só serve se houver servidor atendendo.
    const ping = roda("psql", [...base, "-d", "postgres", "-At", "-c", "select 1"]);
    if (ping.status === 0) {
      return {
        nome: `psql do host (${base[1]}:${base[3]})`,
        sql: (db, args, entrada) =>
          roda("psql", [...base, "-d", db, ...args], entrada ? { input: entrada } : {}),
        encerrar: () => {},
      };
    }
    if (forcada === "psql") {
      throw new Error("DB_TEST_STRATEGY=psql, mas nenhum servidor respondeu.");
    }
  }

  if (!temDocker) {
    throw new Error(
      "Preciso de `psql` com um servidor no ar, ou do Docker.\n" +
        "No Windows, o caminho normal é ter o Docker Desktop rodando.",
    );
  }

  const supabaseDb = forcada === "docker" ? null : nomeDoContainerSupabase();
  if (supabaseDb) {
    return {
      nome: `container do Supabase local (${supabaseDb}), em banco descartável`,
      sql: (db, args, entrada) =>
        roda("docker", ["exec", "-i", supabaseDb, "psql", "-U", "postgres", "-d", db, ...args],
          entrada ? { input: entrada } : {}),
      encerrar: () => {},
    };
  }

  const cid = roda("docker", [
    "run", "-d", "--rm", "-e", "POSTGRES_PASSWORD=postgres", IMAGEM,
  ]).stdout.trim();
  if (!cid) throw new Error(`Não consegui subir um container ${IMAGEM}.`);

  process.stdout.write(`▶ subindo ${IMAGEM} descartável…\n`);
  // Espera síncrona e portátil: `sleep` não existe no Windows.
  const esperar = (ms) => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
  let pronto = false;
  for (let i = 0; i < 60 && !pronto; i += 1) {
    pronto = roda("docker", ["exec", cid, "pg_isready", "-U", "postgres"]).status === 0;
    if (!pronto) esperar(1000);
  }
  if (!pronto) {
    roda("docker", ["kill", cid]);
    throw new Error("O container do PostgreSQL não ficou pronto a tempo.");
  }
  return {
    nome: `container ${IMAGEM} descartável`,
    sql: (db, args, entrada) =>
      roda("docker", ["exec", "-i", cid, "psql", "-U", "postgres", "-d", db, ...args],
        entrada ? { input: entrada } : {}),
    encerrar: () => roda("docker", ["kill", cid]),
  };
}

const estrategia = escolherEstrategia();
const banco = `agrotork_check_${Date.now().toString(36)}`;
let falhas = 0;

function executarArquivo(db, caminho, extras = []) {
  // O arquivo vai por stdin: assim funciona igual com psql do host e com
  // `docker exec`, sem precisar montar volume nem traduzir caminho do
  // Windows para o container.
  return estrategia.sql(db, ["-v", "ON_ERROR_STOP=1", ...extras, "-f", "-"], readFileSync(caminho, "utf8"));
}

try {
  process.stdout.write(`▶ ${estrategia.nome}\n▶ criando banco descartável ${banco}\n`);
  estrategia.sql("postgres", ["-q", "-c", `create database ${banco};`]);

  estrategia.sql(banco, ["-q", "-c", "create extension if not exists pgcrypto;"]);
  const stub = executarArquivo(banco, join(AQUI, "00_supabase_stub.sql"), ["-q"]);
  if (stub.status !== 0) throw new Error(`stub falhou:\n${stub.stderr}`);

  process.stdout.write("▶ aplicando migrations\n");
  const migrations = readdirSync(join(RAIZ, "supabase", "migrations")).filter((f) => f.endsWith(".sql")).sort();
  for (const nome of migrations) {
    const r = executarArquivo(banco, join(RAIZ, "supabase", "migrations", nome), ["-q"]);
    if (r.status !== 0) {
      falhas += 1;
      process.stdout.write(`  ✗ ${nome}\n${r.stderr}\n`);
    } else {
      process.stdout.write(`  ok ${nome}\n`);
    }
  }

  for (const [titulo, arquivo, filtro] of SUITES) {
    process.stdout.write(`▶ ${titulo}\n`);
    const r = executarArquivo(banco, join(AQUI, arquivo));
    const saida = `${r.stdout}\n${r.stderr}`;
    for (const linha of saida.split("\n")) {
      if (filtro.test(linha)) process.stdout.write(`${linha.replace(/^psql:.*?NOTICE:\s+/, " ")}\n`);
    }
    if (r.status !== 0) {
      falhas += 1;
      process.stdout.write(`  ✗ ${arquivo} terminou com erro\n${r.stderr}\n`);
    }
    const problemas = (saida.match(/FALHA/g) ?? []).length;
    if (problemas > 0) {
      falhas += problemas;
      process.stdout.write(`  ✗ ${problemas} FALHA(S) em ${arquivo}\n`);
    }
  }
} finally {
  estrategia.sql("postgres", ["-q", "-c", `drop database if exists ${banco};`]);
  estrategia.encerrar();
}

process.stdout.write(falhas === 0 ? "\n✔ concluído sem falhas\n" : `\n✗ ${falhas} falha(s)\n`);
process.exit(falhas === 0 ? 0 : 1);
