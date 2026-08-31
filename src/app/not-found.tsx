import Link from "next/link";

export default function NotFound() {
  return (
    <main className="flex min-h-dvh flex-col items-center justify-center gap-4 px-6 text-center">
      <p className="font-display text-6xl text-brand">404</p>
      <h1 className="font-display text-2xl">Página não encontrada</h1>
      <p className="max-w-sm text-sm text-graphite-500">
        O endereço acessado não existe ou foi movido.
      </p>
      <Link
        href="/dashboard"
        className="mt-2 rounded-lg bg-graphite px-5 py-3 text-sm font-medium text-white"
      >
        Voltar ao painel
      </Link>
    </main>
  );
}
