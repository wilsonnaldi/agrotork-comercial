import type { Metadata } from "next";
import { PageHeader } from "@/components/ui/page-header";
import { Card, CardBody } from "@/components/ui/card";
import { Alert } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { ROLE_LABELS } from "@/config/labels";
import { requirePermission } from "@/lib/auth/session";
import { listUsers } from "@/modules/users/service";
import { changeRoleAction, toggleActiveAction } from "@/modules/users/actions";

export const metadata: Metadata = { title: "Usuários" };

export default async function UsersPage({
  searchParams,
}: {
  searchParams: Promise<{ salvo?: string; erro?: string }>;
}) {
  const atual = await requirePermission("users.manage");
  const [usuarios, params] = await Promise.all([listUsers(), searchParams]);

  return (
    <>
      <PageHeader title="Usuários" description="Quem entra no sistema, com qual papel." />

      {params.salvo && <Alert tone="success">Alteração salva.</Alert>}
      {params.erro && <Alert tone="error">{params.erro}</Alert>}

      <Alert tone="info" className="mt-4">
        Contas novas são criadas no painel do Supabase, em{" "}
        <strong>Authentication → Users → Invite user</strong>. Quem entra pela primeira vez nasce{" "}
        <strong>vendedor</strong>; a promoção a administrador é feita aqui.
      </Alert>

      <div className="mt-4 space-y-3">
        {usuarios.map((usuario) => {
          const souEu = usuario.id === atual.id;
          return (
            <Card key={usuario.id}>
              <CardBody className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
                <div className="min-w-0 flex-1">
                  <div className="flex flex-wrap items-center gap-2">
                    <p className="font-medium">{usuario.full_name || "(sem nome)"}</p>
                    {souEu && <Badge tone="info">você</Badge>}
                    <Badge tone={usuario.role === "admin" ? "success" : "neutral"}>
                      {ROLE_LABELS[usuario.role]}
                    </Badge>
                    {!usuario.is_active && <Badge tone="warning">Inativo</Badge>}
                  </div>
                  <p className="mt-1 truncate text-sm text-graphite-500">{usuario.email}</p>
                </div>

                <div className="flex flex-col gap-2 sm:flex-row sm:items-center">
                  <form action={changeRoleAction}>
                    <input type="hidden" name="id" value={usuario.id} />
                    <input
                      type="hidden"
                      name="role"
                      value={usuario.role === "admin" ? "salesperson" : "admin"}
                    />
                    <Button
                      type="submit"
                      variant="secondary"
                      size="sm"
                      className="w-full sm:w-auto"
                      disabled={souEu && usuario.role === "admin"}
                    >
                      {usuario.role === "admin" ? "Tornar vendedor" : "Tornar administrador"}
                    </Button>
                  </form>

                  <form action={toggleActiveAction}>
                    <input type="hidden" name="id" value={usuario.id} />
                    <input type="hidden" name="activate" value={usuario.is_active ? "false" : "true"} />
                    <Button
                      type="submit"
                      variant={usuario.is_active ? "danger" : "secondary"}
                      size="sm"
                      className="w-full sm:w-auto"
                      disabled={souEu}
                    >
                      {usuario.is_active ? "Desativar" : "Reativar"}
                    </Button>
                  </form>
                </div>
              </CardBody>
            </Card>
          );
        })}
      </div>

      <p className="mt-4 text-xs text-graphite-500">
        Desativar não apaga nada: o histórico comercial depende do vendedor. O acesso é barrado no
        login e pelo RLS, mesmo com sessão aberta.
      </p>
    </>
  );
}
