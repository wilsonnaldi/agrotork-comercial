import type { Metadata } from "next";
import { Logo } from "@/components/layout/logo";
import { Alert } from "@/components/ui/alert";
import { isSupabaseConfigured } from "@/lib/utils/env";
import { LoginForm } from "./login-form";

export const metadata: Metadata = { title: "Entrar" };

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ next?: string }>;
}) {
  const { next } = await searchParams;
  const configured = isSupabaseConfigured();

  return (
    <div className="space-y-7">
      <div className="space-y-3">
        <Logo className="lg:hidden" />
        <div>
          <h1 className="font-display text-2xl uppercase tracking-wide">Entrar</h1>
          <p className="mt-1 text-sm text-graphite-500">Acesse com seu e-mail corporativo.</p>
        </div>
      </div>

      {!configured ? (
        <Alert tone="error" title="Supabase ainda não configurado">
          Copie <code className="font-mono">.env.example</code> para{" "}
          <code className="font-mono">.env.local</code> e preencha a URL e a chave anônima do projeto.
          Depois rode <code className="font-mono">npm run db:push</code> para aplicar as migrations.
        </Alert>
      ) : (
        <LoginForm next={next} />
      )}
    </div>
  );
}
