/**
 * Gerador de `src/types/database.types.ts` a partir de um PostgreSQL local.
 *
 * O arquivo oficial é gerado pelo Supabase (`npm run db:types`). Este script
 * existe para produzir EXATAMENTE o mesmo formato a partir das migrations,
 * sem depender de um projeto provisionado — é o que permite rodar o
 * typecheck offline contra a mesma tipagem que o Supabase entrega.
 *
 * Não escreva domínio aqui: os apelidos de domínio ficam em `src/types/db.ts`,
 * derivados do `Database` gerado. Regerar este arquivo nunca deve apagar nada.
 *
 *   node supabase/db-tests/gen-types.mjs /tmp/schema.json > src/types/database.types.ts
 */
import { readFileSync } from "node:fs";

const schema = JSON.parse(readFileSync(process.argv[2] ?? "/tmp/schema.json", "utf8"));

const SCALARS = new Map([
  ["bool", "boolean"],
  ["int2", "number"], ["int4", "number"], ["int8", "number"],
  ["numeric", "number"], ["float4", "number"], ["float8", "number"],
  ["text", "string"], ["varchar", "string"], ["bpchar", "string"], ["name", "string"],
  ["uuid", "string"], ["date", "string"], ["timestamp", "string"], ["timestamptz", "string"],
  ["time", "string"], ["timetz", "string"], ["inet", "string"], ["citext", "string"],
  ["json", "Json"], ["jsonb", "Json"],
]);

const enumNames = new Set(schema.enums.map((e) => e.name));

function tsType(col) {
  if (col.is_enum) return `Database["public"]["Enums"]["${col.udt}"]`;
  if (col.udt.startsWith("_")) {
    const inner = col.udt.slice(1);
    const base = enumNames.has(inner) ? `Database["public"]["Enums"]["${inner}"]` : SCALARS.get(inner) ?? "unknown";
    return `${base}[]`;
  }
  return SCALARS.get(col.udt) ?? "unknown";
}

/** Tipo de um argumento/retorno declarado em texto (pg_get_function_*). */
function tsFromSql(sql) {
  const clean = sql.trim().replace(/\[\]$/, "");
  const isArray = sql.trim().endsWith("[]");
  const udt = {
    boolean: "bool", integer: "int4", bigint: "int8", smallint: "int2",
    "double precision": "float8", real: "float4", numeric: "numeric",
    text: "text", uuid: "uuid", date: "date", jsonb: "jsonb", json: "json",
    "timestamp with time zone": "timestamptz", "timestamp without time zone": "timestamp",
    "character varying": "varchar", void: "void",
  }[clean] ?? clean;
  if (udt === "void") return "undefined";
  const base = enumNames.has(udt)
    ? `Database["public"]["Enums"]["${udt}"]`
    : SCALARS.get(udt) ?? "unknown";
  return isArray ? `${base}[]` : base;
}

const byName = (a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0);
const alpha = (cols) => [...cols].sort(byName);

function relationships(table) {
  const fks = schema.fks.filter((f) => f.table === table);
  if (fks.length === 0) return "        Relationships: []";
  const body = fks
    .map(
      (f) => `          {
            foreignKeyName: "${f.name}"
            columns: [${f.columns.map((c) => `"${c}"`).join(", ")}]
            isOneToOne: ${f.is_one_to_one}
            referencedRelation: "${f.ref_table}"
            referencedColumns: [${f.ref_columns.map((c) => `"${c}"`).join(", ")}]
          },`,
    )
    .join("\n");
  return `        Relationships: [\n${body}\n        ]`;
}

function tableBlock(t) {
  const cols = alpha(t.columns);
  // Em uma VIEW o PostgreSQL não guarda "not null": o gerador do Supabase
  // emite todas as colunas como anuláveis. É por isso que as projeções de
  // lista precisam ser reafirmadas em src/types/db.ts.
  const isView = t.kind === "view";
  const row = cols
    .map((c) => `          ${c.name}: ${tsType(c)}${isView || !c.notnull ? " | null" : ""}`)
    .join("\n");
  if (isView) {
    return `      ${t.name}: {
        Row: {
${row}
        }
${relationships(t.name)}
      }`;
  }
  const insert = cols
    .map((c) => {
      const opt = c.has_default || !c.notnull ? "?" : "";
      return `          ${c.name}${opt}: ${tsType(c)}${c.notnull ? "" : " | null"}`;
    })
    .join("\n");
  const update = cols
    .map((c) => `          ${c.name}?: ${tsType(c)}${c.notnull ? "" : " | null"}`)
    .join("\n");
  return `      ${t.name}: {
        Row: {
${row}
        }
        Insert: {
${insert}
        }
        Update: {
${update}
        }
${relationships(t.name)}
      }`;
}

function functionBlock(f) {
  const args = f.args.trim();
  const argEntries = args
    ? args.split(/,\s*(?![^(]*\))/).map((a) => {
        const withoutDefault = a.split(/\s+DEFAULT\s+/i)[0].trim();
        const parts = withoutDefault.split(/\s+/);
        const name = parts.shift();
        return { name, type: tsFromSql(parts.join(" ")), optional: /\sDEFAULT\s/i.test(a) };
      })
    : [];
  const argsType = argEntries.length
    ? `{\n${argEntries.map((a) => `          ${a.name}${a.optional ? "?" : ""}: ${a.type}`).join("\n")}\n        }`
    : "Record<PropertyKey, never>";

  const ret = f.returns.trim();
  let returns;
  const table = ret.match(/^TABLE\((.*)\)$/is);
  if (table) {
    const fields = table[1].split(/,\s*/).map((c) => {
      const parts = c.trim().split(/\s+/);
      const name = parts.shift();
      return `          ${name}: ${tsFromSql(parts.join(" "))}`;
    });
    returns = `{\n${fields.join("\n")}\n        }[]`;
  } else if (/^SETOF\s/i.test(ret)) {
    returns = `${tsFromSql(ret.replace(/^SETOF\s+/i, ""))}[]`;
  } else {
    returns = tsFromSql(ret);
  }
  return `      ${f.name}: {
        Args: ${argsType}
        Returns: ${returns}
      }`;
}

const tables = schema.tables.filter((t) => t.kind === "table").sort(byName);
const views = schema.tables.filter((t) => t.kind === "view").sort(byName);
const functions = schema.functions
  .filter((f) => f.returns.trim() !== "trigger")
  .sort(byName);

const out = `export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  public: {
    Tables: {
${tables.map(tableBlock).join("\n")}
    }
    Views: {
${views.map(tableBlock).join("\n")}
    }
    Functions: {
${functions.map(functionBlock).join("\n")}
    }
    Enums: {
${schema.enums
  .map((e) => `      ${e.name}: ${e.values.map((v) => `"${v}"`).join(" | ")}`)
  .join("\n")}
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] & DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends { Insert: infer I }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends { Update: infer U }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
${schema.enums
  .map((e) => `      ${e.name}: [${e.values.map((v) => `"${v}"`).join(", ")}],`)
  .join("\n")}
    },
  },
} as const
`;

process.stdout.write(out);
