export default function AuthLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="grid min-h-dvh lg:grid-cols-2">
      {/* Painel de marca — escondido no celular para a tela caber sem rolagem. */}
      <div className="relative hidden flex-col justify-between bg-graphite p-10 text-white lg:flex">
        <div className="h-1.5 w-24 rounded-full bg-brand" />
        <div>
          <h2 className="font-display text-4xl leading-tight uppercase">
            Sistema
            <br />
            Comercial
          </h2>
          <p className="mt-4 max-w-sm text-sm text-white/60">
            Clientes, produtos, kits e orçamentos em um só lugar — do escritório à lavoura.
          </p>
        </div>
        <p className="text-xs text-white/30">AGROTORK · Londrina/PR</p>
      </div>

      <div className="flex items-center justify-center px-5 py-10 sm:px-8">
        <div className="w-full max-w-sm">{children}</div>
      </div>
    </div>
  );
}
