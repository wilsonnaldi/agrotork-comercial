"use client";

import { useEffect } from "react";

export default function GlobalError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    console.error(error);
  }, [error]);

  return (
    <main className="flex min-h-dvh flex-col items-center justify-center gap-4 px-6 text-center">
      <h1 className="font-display text-2xl">Alguma coisa deu errado</h1>
      <p className="max-w-md text-sm text-graphite-500">
        {error.message || "Erro inesperado ao carregar esta página."}
      </p>
      <button
        onClick={reset}
        className="mt-2 rounded-lg bg-graphite px-5 py-3 text-sm font-medium text-white"
      >
        Tentar novamente
      </button>
    </main>
  );
}
