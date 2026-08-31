/**
 * Duplê de teste do Supabase (Auth + REST).
 * NÃO é o Supabase. Ver README.md nesta pasta.
 *
 * Existe para exercitar o fluxo de sessão do sistema sem nenhuma
 * credencial real e sem depender de rede.
 */
import { createServer } from "node:http";
import { createHmac, timingSafeEqual, createHash } from "node:crypto";
import pg from "pg";

// ── Fidelidade de tipos com o PostgREST ─────────────────────
// O PostgREST devolve `date` como texto 'YYYY-MM-DD'. O node-postgres
// converteria para Date, e o JSON viraria '2026-08-29T00:00:00.000Z' —
// que um <input type="date"> recusa. Sem isto, o duplê testaria um
// formato que o Supabase real nunca envia.
pg.types.setTypeParser(1082, (value) => value); // date

const PORT = Number(process.env.PORT ?? 54321);
const JWT_SECRET = "duple-de-teste-nao-usar-em-producao";
const ANON_KEY = signJwt({ role: "anon", iss: "supabase-double" }, 60 * 60 * 24 * 365);

// O banco de teste é recriado entre as suítes, o que derruba as conexões
// ociosas. Sem este handler o processo cairia junto.
const pool = new pg.Pool({
  idleTimeoutMillis: 1000,
  host: process.env.PGHOST ?? "/tmp/pgrun",
  port: Number(process.env.PGPORT ?? 5433),
  user: process.env.PGUSER ?? "postgres",
  database: process.env.PGDATABASE ?? "agrotork_dev",
});

pool.on("error", (error) => {
  console.warn("conexão ociosa perdida (banco recriado?):", error.message);
});

// ── JWT (HS256) ─────────────────────────────────────────────
function b64url(input) {
  return Buffer.from(input).toString("base64url");
}
function signJwt(payload, ttlSeconds) {
  const now = Math.floor(Date.now() / 1000);
  const body = { ...payload, iat: now, exp: now + ttlSeconds };
  const head = b64url(JSON.stringify({ alg: "HS256", typ: "JWT" }));
  const data = `${head}.${b64url(JSON.stringify(body))}`;
  const sig = createHmac("sha256", JWT_SECRET).update(data).digest("base64url");
  return `${data}.${sig}`;
}
function verifyJwt(token) {
  if (!token) return null;
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  const expected = createHmac("sha256", JWT_SECRET).update(`${parts[0]}.${parts[1]}`).digest("base64url");
  const a = Buffer.from(parts[2]);
  const b = Buffer.from(expected);
  if (a.length !== b.length || !timingSafeEqual(a, b)) return null;
  const payload = JSON.parse(Buffer.from(parts[1], "base64url").toString());
  if (payload.exp && payload.exp < Math.floor(Date.now() / 1000)) return null;
  return payload;
}

const hash = (value) => createHash("sha256").update(value).digest("hex");

// ── Consulta com o RLS ativo ────────────────────────────────
async function withUser(userId, fn) {
  const client = await pool.connect();
  try {
    await client.query("begin");
    await client.query("set local role authenticated");
    await client.query("select set_config('request.jwt.claim.sub', $1, true)", [userId ?? ""]);
    await client.query("select set_config('request.jwt.claim.role', 'authenticated', true)");
    const result = await fn(client);
    await client.query("commit");
    return result;
  } catch (error) {
    await client.query("rollback").catch(() => {});
    throw error;
  } finally {
    client.release();
  }
}

// ── Tradução PostgREST -> SQL (subconjunto) ─────────────────
const IDENT = /^[a-z_][a-z0-9_]*$/;
function buildSelect(table, params) {
  if (!IDENT.test(table)) throw new Error(`tabela inválida: ${table}`);

  const columns = (params.get("select") ?? "*")
    .split(",")
    .map((c) => c.trim().split(":").pop())
    .filter((c) => c === "*" || IDENT.test(c));

  const { where, values } = buildWhere(params);

  let sql = `select ${columns.join(", ")} from public.${table}`;
  if (where.length) sql += ` where ${where.join(" and ")}`;

  const order = params.get("order");
  if (order) {
    const [col, dir] = order.split(".");
    if (IDENT.test(col)) sql += ` order by ${col} ${dir === "desc" ? "desc" : "asc"}`;
  }

  const limit = params.get("limit");
  if (limit && /^\d+$/.test(limit)) sql += ` limit ${limit}`;
  const offset = params.get("offset");
  if (offset && /^\d+$/.test(offset)) sql += ` offset ${offset}`;

  return {
    sql,
    values,
    columns,
    countSql: `select count(*)::int as n from public.${table}${where.length ? ` where ${where.join(" and ")}` : ""}`,
  };
}

/** Um predicado do PostgREST: `eq.x`, `ilike.%x%`, `is.null`, `in.(a,b)`. */
function predicate(column, raw, values) {
  const [op, ...rest] = raw.split(".");
  const value = rest.join(".");

  if (op === "eq") { values.push(value); return `${column} = $${values.length}`; }
  if (op === "neq") { values.push(value); return `${column} <> $${values.length}`; }
  if (op === "gt") { values.push(value); return `${column} > $${values.length}`; }
  if (op === "gte") { values.push(value); return `${column} >= $${values.length}`; }
  if (op === "lt") { values.push(value); return `${column} < $${values.length}`; }
  if (op === "lte") { values.push(value); return `${column} <= $${values.length}`; }
  if (op === "like") { values.push(value); return `${column} like $${values.length}`; }
  if (op === "ilike") { values.push(value); return `${column}::text ilike $${values.length}`; }
  if (op === "is") return `${column} is ${value === "null" ? "null" : "not null"}`;
  if (op === "in") {
    const list = value.replace(/^\(|\)$/g, "").split(",").map((v) => v.replace(/^"|"$/g, ""));
    const marks = list.map((v) => { values.push(v); return `$${values.length}`; });
    return `${column} in (${marks.join(",")})`;
  }
  return null;
}

const RESERVED = ["select", "order", "limit", "offset", "columns", "on_conflict"];

function buildWhere(params) {
  const where = [];
  const values = [];

  for (const [key, raw] of params.entries()) {
    if (RESERVED.includes(key)) continue;

    // `or=(a.ilike.%x%,b.eq.y)` — usado pela busca da listagem.
    // Observação: separar por vírgula é ingênuo e quebraria com vírgula
    // dentro do termo. Basta para um duplê de teste.
    if (key === "or") {
      const parts = raw.replace(/^\(|\)$/g, "").split(",");
      const clauses = [];
      for (const part of parts) {
        const [column, ...conditionParts] = part.split(".");
        if (!IDENT.test(column)) continue;
        const clause = predicate(column, conditionParts.join("."), values);
        if (clause) clauses.push(clause);
      }
      if (clauses.length) where.push(`(${clauses.join(" or ")})`);
      continue;
    }

    if (!IDENT.test(key)) continue;
    const clause = predicate(key, raw, values);
    if (clause) where.push(clause);
  }

  return { where, values };
}

/** INSERT a partir do corpo JSON. */
/**
 * Valor de parâmetro no formato que o Postgres espera.
 *
 * O node-postgres transforma array JS em literal de ARRAY (`{a,b}`) — o
 * que quebra uma coluna `jsonb`. O PostgREST recebe JSON e grava JSON.
 * Como este schema não tem nenhuma coluna de array, serializar todo
 * array e todo objeto como JSON reproduz o comportamento real.
 */
function toParam(value) {
  if (value === null || value === undefined) return null;
  if (Array.isArray(value) || (typeof value === "object" && !(value instanceof Date))) {
    return JSON.stringify(value);
  }
  return value;
}

function buildInsert(table, body, params) {
  const rows = Array.isArray(body) ? body : [body];
  const first = rows[0] ?? {};
  const cols = Object.keys(first).filter((c) => IDENT.test(c));
  const values = [];

  const tuples = rows.map((row) => {
    const marks = cols.map((c) => {
      values.push(toParam(row[c]));
      return `$${values.length}`;
    });
    return `(${marks.join(", ")})`;
  });

  const returning = (params.get("select") ?? "*")
    .split(",")
    .map((c) => c.trim())
    .filter((c) => c === "*" || IDENT.test(c));

  // `.upsert()` do supabase-js: on_conflict + Prefer: resolution=merge-duplicates
  const conflict = (params.get("on_conflict") ?? "")
    .split(",")
    .map((c) => c.trim())
    .filter((c) => IDENT.test(c));

  const onConflict = conflict.length
    ? ` on conflict (${conflict.join(", ")}) do update set ${cols
        .filter((c) => !conflict.includes(c))
        .map((c) => `${c} = excluded.${c}`)
        .join(", ")}`
    : "";

  const sql = cols.length
    ? `insert into public.${table} (${cols.join(", ")}) values ${tuples.join(", ")}${onConflict} returning ${returning.join(", ")}`
    : `insert into public.${table} default values returning ${returning.join(", ")}`;

  return { sql, values };
}

/** DELETE com os mesmos filtros do GET. Sem filtro, apaga a tabela toda —
 *  é o comportamento do PostgREST, e o RLS é quem limita o estrago. */
function buildDelete(table, params) {
  const { where, values } = buildWhere(params);
  const returning = (params.get("select") ?? "*")
    .split(",")
    .map((c) => c.trim())
    .filter((c) => c === "*" || IDENT.test(c));

  const sql =
    `delete from public.${table}` +
    (where.length ? ` where ${where.join(" and ")}` : "") +
    ` returning ${returning.join(", ")}`;

  return { sql, values };
}

/** UPDATE com os mesmos filtros do GET. */
function buildUpdate(table, body, params) {
  const cols = Object.keys(body).filter((c) => IDENT.test(c));
  const values = [];
  const sets = cols.map((c) => {
    values.push(toParam(body[c]));
    return `${c} = $${values.length}`;
  });

  const { where, values: whereValues } = buildWhere(params);
  // Reindexa os parâmetros do WHERE, que vêm depois dos do SET.
  const shifted = where.map((clause) =>
    clause.replace(/\$(\d+)/g, (_, n) => `$${Number(n) + values.length}`),
  );

  const returning = (params.get("select") ?? "*")
    .split(",")
    .map((c) => c.trim())
    .filter((c) => c === "*" || IDENT.test(c));

  const sql =
    `update public.${table} set ${sets.join(", ")}` +
    (shifted.length ? ` where ${shifted.join(" and ")}` : "") +
    ` returning ${returning.join(", ")}`;

  return { sql, values: [...values, ...whereValues] };
}

// ── Servidor ────────────────────────────────────────────────
function json(res, status, body, headers = {}) {
  const payload = JSON.stringify(body);
  res.writeHead(status, { "content-type": "application/json", "access-control-allow-origin": "*", ...headers });
  res.end(payload);
}
async function readBody(req) {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  if (!chunks.length) return {};
  try { return JSON.parse(Buffer.concat(chunks).toString()); } catch { return {}; }
}
function bearer(req) {
  const header = req.headers.authorization ?? "";
  const token = header.startsWith("Bearer ") ? header.slice(7) : null;
  return token && token !== ANON_KEY ? verifyJwt(token) : null;
}
async function userRow(id) {
  const { rows } = await pool.query(
    "select id, email, raw_user_meta_data from auth.users where id = $1", [id],
  );
  return rows[0] ?? null;
}
function sessionFor(user) {
  return {
    access_token: signJwt({ sub: user.id, email: user.email, role: "authenticated", aud: "authenticated" }, 3600),
    token_type: "bearer",
    expires_in: 3600,
    expires_at: Math.floor(Date.now() / 1000) + 3600,
    refresh_token: signJwt({ sub: user.id, kind: "refresh" }, 60 * 60 * 24 * 7),
    user: {
      id: user.id, aud: "authenticated", role: "authenticated", email: user.email,
      email_confirmed_at: new Date().toISOString(),
      user_metadata: user.raw_user_meta_data ?? {}, app_metadata: { provider: "email" },
      created_at: new Date().toISOString(), updated_at: new Date().toISOString(),
    },
  };
}

const server = createServer(async (req, res) => {
  try {
    const url = new URL(req.url, `http://localhost:${PORT}`);
    const path = url.pathname;

    if (path === "/auth/v1/token" && req.method === "POST") {
      const grant = url.searchParams.get("grant_type");
      const body = await readBody(req);

      if (grant === "refresh_token") {
        const claims = verifyJwt(body.refresh_token);
        const user = claims && (await userRow(claims.sub));
        if (!user) return json(res, 400, { error: "invalid_grant", error_description: "Invalid Refresh Token" });
        return json(res, 200, sessionFor(user));
      }

      const { rows } = await pool.query(
        "select id, email, raw_user_meta_data, encrypted_password from auth.users where lower(email) = lower($1)",
        [body.email ?? ""],
      );
      const user = rows[0];
      if (!user || user.encrypted_password !== hash(body.password ?? "")) {
        return json(res, 400, { error: "invalid_grant", error_description: "Invalid login credentials" });
      }
      return json(res, 200, sessionFor(user));
    }

    if (path === "/auth/v1/user" && req.method === "GET") {
      const claims = bearer(req);
      const user = claims && (await userRow(claims.sub));
      if (!user) return json(res, 401, { message: "invalid claim: missing sub claim" });
      return json(res, 200, sessionFor(user).user);
    }

    if (path === "/auth/v1/logout" && req.method === "POST") {
      res.writeHead(204).end();
      return;
    }

    // ── RPC: POST /rest/v1/rpc/<função> ──────────────────
    // O PostgREST expõe funções do schema public assim. O duplê chama a
    // função com argumentos NOMEADOS, como o PostgREST faz, e mantém o
    // papel e o `sub` do usuário — então `security definer` e RLS se
    // comportam como no Supabase real.
    if (path.startsWith("/rest/v1/rpc/") && req.method === "POST") {
      const fn = path.slice("/rest/v1/rpc/".length);
      if (!IDENT.test(fn)) return json(res, 400, { message: "função inválida" });

      const body = await readBody(req);
      const args = Object.keys(body ?? {}).filter((a) => IDENT.test(a));
      const values = args.map((a) => toParam(body[a]));
      const call = args.map((a, i) => `${a} => $${i + 1}`).join(", ");
      const claims = bearer(req);

      try {
        const rows = await withUser(claims?.sub, async (client) =>
          (await client.query(`select public.${fn}(${call}) as result`, values)).rows,
        );
        return json(res, 200, rows[0]?.result ?? null);
      } catch (error) {
        return json(res, error.code === "42501" ? 403 : 400, {
          code: error.code ?? "P0001",
          message: error.message,
          details: error.detail ?? null,
          hint: error.hint ?? null,
        });
      }
    }

    if (path.startsWith("/rest/v1/")) {
      const table = path.slice("/rest/v1/".length);
      const claims = bearer(req);
      const prefer = req.headers.prefer ?? "";
      // `.single()` pede um objeto em vez de lista.
      const wantsObject = (req.headers.accept ?? "").includes("pgrst.object");

      // ── Leitura ──────────────────────────────────────────
      if (req.method === "GET" || req.method === "HEAD") {
        const params = url.searchParams;

        // `.range(de, ate)` chega como cabeçalho Range.
        const range = /^(\d+)-(\d*)$/.exec(req.headers.range ?? "");
        if (range && !params.get("limit")) {
          const from = Number(range[1]);
          const to = range[2] === "" ? null : Number(range[2]);
          params.set("offset", String(from));
          if (to !== null) params.set("limit", String(to - from + 1));
        }

        const { sql, values, countSql } = buildSelect(table, params);
        const wantsCount = prefer.includes("count=exact");

        const out = await withUser(claims?.sub, async (client) => {
          const count = wantsCount ? (await client.query(countSql, values)).rows[0].n : null;
          const data = req.method === "HEAD" ? [] : (await client.query(sql, values)).rows;
          return { count, data };
        });

        const headers = { "content-type": "application/json" };
        if (out.count !== null) headers["content-range"] = `0-${Math.max(out.count - 1, 0)}/${out.count}`;
        if (req.method === "HEAD") { res.writeHead(200, headers).end(); return; }

        if (wantsObject) {
          if (out.data.length !== 1) {
            return json(res, 406, {
              code: "PGRST116",
              message: `JSON object requested, multiple (or no) rows returned`,
              details: `Results contain ${out.data.length} rows`,
            });
          }
          return json(res, 200, out.data[0], headers);
        }
        return json(res, 200, out.data, headers);
      }

      // ── Escrita ──────────────────────────────────────────
      const body = req.method === "DELETE" ? {} : await readBody(req);
      const returnsRows = prefer.includes("return=representation") || url.searchParams.has("select");

      const build =
        req.method === "POST"
          ? buildInsert(table, body, url.searchParams)
          : req.method === "PATCH"
            ? buildUpdate(table, body, url.searchParams)
            : req.method === "DELETE"
              ? buildDelete(table, url.searchParams)
              : null;

      if (!build) return json(res, 405, { message: `método ${req.method} não implementado no duplê` });

      let rows;
      try {
        rows = await withUser(claims?.sub, async (client) => (await client.query(build.sql, build.values)).rows);
      } catch (error) {
        // Reproduz o formato de erro do PostgREST para o supabase-js entender.
        return json(res, error.code === "42501" ? 403 : 400, {
          code: error.code ?? "P0001",
          message: error.message,
          details: error.detail ?? null,
          hint: error.hint ?? null,
        });
      }

      if (!returnsRows) { res.writeHead(204).end(); return; }
      if (wantsObject) {
        if (rows.length !== 1) {
          return json(res, 406, {
            code: "PGRST116",
            message: "JSON object requested, multiple (or no) rows returned",
            details: `Results contain ${rows.length} rows`,
          });
        }
        return json(res, req.method === "POST" ? 201 : 200, rows[0]);
      }
      return json(res, req.method === "POST" ? 201 : 200, rows);
    }

    json(res, 404, { message: "não implementado neste duplê", path });
  } catch (error) {
    json(res, 500, { message: String(error.message ?? error) });
  }
});

server.listen(PORT, () => {
  console.log(`duplê de teste do Supabase em http://127.0.0.1:${PORT}`);
  console.log("\nColoque em .env.local (ambiente de TESTE, nunca produção):\n");
  console.log(`NEXT_PUBLIC_SUPABASE_URL="http://127.0.0.1:${PORT}"`);
  console.log(`NEXT_PUBLIC_SUPABASE_ANON_KEY="${ANON_KEY}"`);
});
