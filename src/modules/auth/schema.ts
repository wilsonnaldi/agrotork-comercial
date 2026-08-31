import { z } from "zod";

export const signInSchema = z.object({
  email: z.string().trim().min(1, "Informe o e-mail").email("E-mail inválido"),
  password: z.string().min(6, "A senha deve ter ao menos 6 caracteres"),
  next: z.string().optional(),
});

export type SignInInput = z.infer<typeof signInSchema>;

export const updatePasswordSchema = z
  .object({
    password: z.string().min(8, "A senha deve ter ao menos 8 caracteres"),
    confirmation: z.string(),
  })
  .refine((data) => data.password === data.confirmation, {
    message: "As senhas não conferem",
    path: ["confirmation"],
  });
