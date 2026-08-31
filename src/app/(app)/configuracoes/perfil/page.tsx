import type { Metadata } from "next";
import { Mail, Phone, ShieldCheck, User } from "lucide-react";
import { PageHeader } from "@/components/ui/page-header";
import { Card, CardBody } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { requireUser } from "@/lib/auth/session";
import { ROLE_LABELS } from "@/config/labels";
import { formatPhone } from "@/lib/format";

export const metadata: Metadata = { title: "Meu perfil" };

/** Dados do usuário logado. Edição chega na Fase 1 (cadastro de usuários). */
export default async function ProfilePage() {
  const user = await requireUser();
  const { profile } = user;

  const rows = [
    { icon: User, label: "Nome", value: profile.full_name || "—" },
    { icon: Mail, label: "E-mail", value: user.email },
    { icon: Phone, label: "Telefone", value: formatPhone(profile.phone) || "—" },
  ];

  return (
    <>
      <PageHeader title="Meu perfil" description="Seus dados de acesso ao sistema." />

      <Card className="max-w-xl">
        <CardBody className="space-y-4">
          {rows.map((row) => (
            <div key={row.label} className="flex items-start gap-3">
              <row.icon className="mt-0.5 size-4 shrink-0 text-graphite-300" aria-hidden />
              <div className="min-w-0">
                <p className="text-xs text-graphite-300">{row.label}</p>
                <p className="truncate text-sm">{row.value}</p>
              </div>
            </div>
          ))}

          <div className="flex items-start gap-3 border-t border-line pt-4">
            <ShieldCheck className="mt-0.5 size-4 shrink-0 text-graphite-300" aria-hidden />
            <div>
              <p className="text-xs text-graphite-300">Nível de acesso</p>
              <Badge tone={profile.role === "admin" ? "danger" : "info"} className="mt-1">
                {ROLE_LABELS[profile.role]}
              </Badge>
            </div>
          </div>
        </CardBody>
      </Card>

      <p className="mt-4 text-xs text-graphite-300">
        Para alterar nome, telefone ou senha, fale com o administrador. A edição pelo próprio
        usuário entra na Fase 1.
      </p>
    </>
  );
}
