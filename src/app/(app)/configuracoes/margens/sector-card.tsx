"use client";

import Link from "next/link";
import { useActionState } from "react";
import { useFormStatus } from "react-dom";
import { ArrowRight, TrendingUp } from "lucide-react";
import { Alert } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Card, CardBody } from "@/components/ui/card";
import { Field, Input } from "@/components/ui/field";
import { Select } from "@/components/ui/select";
import { formatCurrency } from "@/lib/format";
import type { FormState } from "@/lib/forms/action-state";
import {
  BASIS_LABEL,
  COST_BASES,
  MARGIN_MODES,
  MODE_LABEL,
  ROUNDINGS,
  ROUNDING_LABEL,
} from "@/modules/margins/schema";

/** O que a página envia para cada cartão. Só dado, nada de função. */
export type SectorView = {
  categoryId: string | null;
  name: string;
  description: string | null;
  produtos: number;
  semCusto: number;
  custoMin: number | null;
  custoMax: number | null;
  custoTotal: number;
  tabelaTotal: number;
  mudariam: number;
  rule: {
    mode: string;
    percent: number;
    cost_basis: string;
    rounding: string;
    is_active: boolean;
  } | null;
};

type Action = (state: FormState, formData: FormData) => Promise<FormState>;

/**
 * Um setor comercial, com sua regra de margem.
 *
 * Cada cartão é um `<form>` próprio: salvar a margem dos drones não
 * mexe no que está digitado nos outros setores.
 */
export function SectorCard({ sector, action }: { sector: SectorView; action: Action }) {
  const [state, formAction] = useActionState<FormState, FormData>(action, {});
  const value = (field: string, fallback: string) => state.values?.[field] ?? fallback;
  const error = (field: string) => state.fieldErrors?.[field];

  const rule = sector.rule;
  const ativa = rule?.is_active ?? false;
  const lucro = sector.tabelaTotal - sector.custoTotal;
  const margemReal = sector.tabelaTotal > 0 ? (lucro / sector.tabelaTotal) * 100 : 0;
  const destino = sector.categoryId ?? "sem-setor";

  return (
    <Card className={ativa ? "border-brand/30" : undefined}>
      <CardBody className="space-y-4">
        <div className="flex items-start justify-between gap-3">
          <div className="min-w-0">
            <h3 className="font-medium">{sector.name}</h3>
            {sector.description && (
              <p className="mt-0.5 text-xs text-graphite-500">{sector.description}</p>
            )}
          </div>
          <span className="shrink-0 rounded-full bg-sand px-2.5 py-1 text-xs tnum text-graphite-500">
            {sector.produtos} {sector.produtos === 1 ? "produto" : "produtos"}
          </span>
        </div>

        {sector.custoMin !== null && sector.custoMax !== null && (
          <p className="text-xs text-graphite-300">
            Custo de {formatCurrency(sector.custoMin)} a {formatCurrency(sector.custoMax)}
            {sector.semCusto > 0 && ` · ${sector.semCusto} sem custo cadastrado`}
          </p>
        )}

        <form key={state.attempt ?? 0} action={formAction} className="space-y-3" noValidate>
          <input type="hidden" name="category_id" value={sector.categoryId ?? ""} />
          {state.error && <Alert tone="error">{state.error}</Alert>}

          <div className="grid gap-3 sm:grid-cols-2">
            <Field label="Percentual" htmlFor={`percent-${destino}`} required error={error("percent")}>
              <Input
                id={`percent-${destino}`}
                name="percent"
                inputMode="decimal"
                autoComplete="off"
                placeholder="30"
                defaultValue={value("percent", rule ? String(rule.percent) : "")}
                required
              />
            </Field>

            <Field label="O percentual é" htmlFor={`mode-${destino}`}>
              <Select id={`mode-${destino}`} name="mode" defaultValue={value("mode", rule?.mode ?? "markup")}>
                {MARGIN_MODES.map((mode) => (
                  <option key={mode} value={mode}>
                    {MODE_LABEL[mode]}
                  </option>
                ))}
              </Select>
            </Field>

            <Field label="Calcular sobre" htmlFor={`basis-${destino}`}>
              <Select
                id={`basis-${destino}`}
                name="cost_basis"
                defaultValue={value("cost_basis", rule?.cost_basis ?? "maior")}
              >
                {COST_BASES.map((basis) => (
                  <option key={basis} value={basis}>
                    {BASIS_LABEL[basis]}
                  </option>
                ))}
              </Select>
            </Field>

            <Field label="Arredondar" htmlFor={`rounding-${destino}`}>
              <Select
                id={`rounding-${destino}`}
                name="rounding"
                defaultValue={value("rounding", rule?.rounding ?? "none")}
              >
                {ROUNDINGS.map((rounding) => (
                  <option key={rounding} value={rounding}>
                    {ROUNDING_LABEL[rounding]}
                  </option>
                ))}
              </Select>
            </Field>
          </div>

          <label className="flex items-center gap-3 text-sm">
            <input
              type="checkbox"
              name="is_active"
              value="true"
              defaultChecked={ativa}
              className="size-5 rounded border-line accent-brand"
            />
            Regra ativa
          </label>
          {/* Depois do checkbox: `FormData.get` devolve o primeiro valor. */}
          <input type="hidden" name="is_active" value="false" />

          <div className="flex flex-col gap-2 border-t border-line pt-3 sm:flex-row sm:items-center sm:justify-between">
            {ativa && sector.tabelaTotal > 0 ? (
              <p className="text-xs text-graphite-500">
                <TrendingUp className="mr-1 inline size-3.5 text-emerald-700" aria-hidden />
                Tabela de {formatCurrency(sector.tabelaTotal)} · margem de{" "}
                <strong className="tnum">{margemReal.toFixed(1)}%</strong> sobre a venda
              </p>
            ) : (
              <p className="text-xs text-graphite-300">
                {ativa ? "Sem custo para calcular." : "Regra desligada: não sugere preço."}
              </p>
            )}
            <SaveButton />
          </div>
        </form>

        {sector.mudariam > 0 && (
          <Link
            href={`/configuracoes/margens/${destino}`}
            className="flex items-center justify-between gap-2 rounded-lg bg-brand-soft px-3 py-2.5 text-sm text-brand-deep transition-colors hover:bg-brand/10"
          >
            <span>
              <strong className="tnum">{sector.mudariam}</strong>{" "}
              {sector.mudariam === 1 ? "produto mudaria" : "produtos mudariam"} de preço
            </span>
            <ArrowRight className="size-4 shrink-0" aria-hidden />
          </Link>
        )}
      </CardBody>
    </Card>
  );
}

function SaveButton() {
  const { pending } = useFormStatus();
  return (
    <Button type="submit" size="sm" variant="secondary" disabled={pending} className="sm:w-auto">
      {pending ? "Salvando…" : "Salvar regra"}
    </Button>
  );
}
