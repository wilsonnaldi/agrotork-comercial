import {
  LayoutDashboard,
  Users,
  Package,
  Boxes,
  FileText,
  ClipboardCheck,
  Warehouse,
  PackagePlus,
  ChartColumn,
  Settings,
  type LucideIcon,
} from "lucide-react";
import type { Permission } from "./permissions";

export type NavItem = {
  label: string;
  shortLabel: string;
  href: string;
  icon: LucideIcon;
  permission: Permission;
  /** Aparece na barra inferior do celular. */
  mobile: boolean;
};

/**
 * Navegação principal. Um módulo novo (Pedidos, Estoque...) entra aqui
 * e aparece automaticamente na sidebar, no menu e na barra do celular.
 */
export const NAV_ITEMS: NavItem[] = [
  { label: "Painel",     shortLabel: "Painel",   href: "/dashboard",     icon: LayoutDashboard, permission: "quotes.readOwn",   mobile: true },
  { label: "Orçamentos", shortLabel: "Orçam.",   href: "/orcamentos",    icon: FileText,        permission: "quotes.readOwn",   mobile: true },
  { label: "Pedidos",    shortLabel: "Pedidos",  href: "/pedidos",       icon: ClipboardCheck,  permission: "orders.read",      mobile: true },
  { label: "Clientes",   shortLabel: "Clientes", href: "/clientes",      icon: Users,           permission: "customers.read",   mobile: true },
  { label: "Produtos",   shortLabel: "Produtos", href: "/produtos",      icon: Package,         permission: "products.read",    mobile: true },
  { label: "Kits",       shortLabel: "Kits",     href: "/kits",          icon: Boxes,           permission: "kits.read",        mobile: false },
  { label: "Estoque",    shortLabel: "Estoque",  href: "/estoque",       icon: Warehouse,       permission: "stock.read",       mobile: false },
  { label: "Entradas",   shortLabel: "Entradas", href: "/compras",       icon: PackagePlus,     permission: "purchases.manage", mobile: false },
  { label: "Relatórios", shortLabel: "Relat.",   href: "/relatorios",    icon: ChartColumn,     permission: "reports.read",     mobile: false },
  { label: "Configurações", shortLabel: "Config.", href: "/configuracoes", icon: Settings,      permission: "settings.manage",  mobile: false },
];
