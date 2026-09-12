-- ============================================================
-- CRIAR O BUCKET brain-documents — só com autorização explícita
-- ============================================================
-- O Lote B (migration 20260912030000) cria as POLICIES do bucket, mas não o
-- bucket: o limite de tamanho por arquivo depende do plano do projeto.
--
--   · plano Free: o Supabase limita cada upload a 50 MB, seja qual for o
--     `file_size_limit` do bucket. O Catálogo Magnojet V41 tem 177 MB, o
--     V40 tem 162 MB — não sobem;
--   · plano Pro: o limite global sobe (configurável) e o bucket pode
--     receber os ~250 MB projetados na Etapa 0.
--
-- Este roteiro cria o bucket PRIVADO com o limite que o plano permite.
-- Ajuste `v_limite` conforme a decisão do Wilson sobre o plano ANTES de
-- rodar. Idempotente: se o bucket existir, não muda nada e avisa.
--
-- COMO RODAR: SQL Editor do Supabase, colado inteiro, DEPOIS da autorização.
-- Não faz parte de nenhuma migration nem de nenhum ensaio automático.
-- ============================================================
do $$
declare
  v_limite bigint := 50 * 1024 * 1024;   -- 50 MB (Free). Pro: 250 * 1024 * 1024.
begin
  if to_regclass('storage.buckets') is null then
    raise exception 'Schema storage ausente. PARADO.';
  end if;
  if exists (select 1 from storage.buckets where id = 'brain-documents') then
    raise notice 'Bucket brain-documents ja existe (limite % bytes). Nada feito.',
      (select file_size_limit from storage.buckets where id = 'brain-documents');
    return;
  end if;
  if (select count(*) from pg_policies where schemaname = 'storage' and policyname like 'brain_documents_%') <> 4 then
    raise exception 'As 4 policies do bucket nao estao aplicadas (migration 20260912030000). PARADO.';
  end if;

  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('brain-documents', 'brain-documents', false, v_limite,
          array['application/pdf',
                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
                'text/csv', 'text/plain', 'text/markdown']);
  raise notice 'Bucket brain-documents criado: privado, limite % bytes, 5 tipos permitidos.', v_limite;
end
$$;
