import coreWebVitals from "eslint-config-next/core-web-vitals";
import typescript from "eslint-config-next/typescript";

/** Flat config do ESLint 9 (Next.js 16). */
const eslintConfig = [
  ...coreWebVitals,
  ...typescript,
  {
    ignores: [
      ".next/**",
      "node_modules/**",
      "src/types/database.types.ts",
      // Ferramentas de teste com dependências próprias — ver supabase/db-tests/.
      "supabase/db-tests/auth-double/**",
    ],
  },
  {
    // `database.types.ts` é regerado inteiro pelo Supabase a cada
    // `npm run db:types`. Quem importar dali de novo vai ver os apelidos
    // sumirem na próxima geração — foi exatamente o que já aconteceu uma
    // vez. A camada de domínio fica em `@/types/db`, e só ela toca no
    // arquivo gerado.
    files: ["src/**/*.{ts,tsx}"],
    ignores: ["src/types/db.ts"],
    rules: {
      "no-restricted-imports": [
        "error",
        {
          patterns: [
            {
              group: ["@/types/database.types", "**/types/database.types"],
              message:
                "Importe de @/types/db. O database.types.ts é gerado pelo Supabase e sobrescrito a cada db:types.",
            },
          ],
        },
      ],
    },
  },
];

export default eslintConfig;
