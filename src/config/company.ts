/**
 * Dados institucionais usados no cabeçalho, no rodapé e no PDF.
 * O que for editável pelo administrador vive em `app_settings.company` no banco;
 * este arquivo é o valor de partida (fallback) e a identidade visual.
 */
export const COMPANY = {
  name: "AGROTORK",
  tagline: "Soluções para o agronegócio",
  city: "Londrina",
  state: "PR",
  website: "https://www.agrotork.com.br",
  logo: "/logo-agrotork.png",
  logoLight: "/logo-agrotork-light.png",
} as const;

export const BRAND_COLORS = {
  brand: "#d42424",
  brandDark: "#a81c1c",
  brandDeep: "#6e1414",
  graphite: "#1c1c1e",
  graphiteSoft: "#4a4a4d",
  sand: "#f7f5f1",
  line: "#e4e2df",
  whatsapp: "#25d366",
} as const;
