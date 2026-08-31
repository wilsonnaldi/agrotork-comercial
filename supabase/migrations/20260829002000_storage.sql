-- ============================================================
-- 2000 · Storage: logotipo da empresa e imagens de produto
--
-- Preparação para produção. Cria os buckets e as policies que o
-- Supabase Storage usa, com uma decisão em cada linha:
--
--   `public-assets`  → PÚBLICO na leitura. É o logotipo e a foto de
--                      produto, que precisam abrir no PDF e na página
--                      pública do orçamento, onde não há login nenhum.
--                      Escrita: só administrador.
--
--   `private-docs`   → PRIVADO. Nada é gravado aqui ainda; existe para
--                      que anexo de orçamento e documento de cliente
--                      tenham destino quando chegarem, sem que alguém
--                      seja tentado a jogá-los no bucket público.
--
-- POR QUE ISTO É SEGURO DE APLICAR AGORA
--
-- O schema `storage` é do Supabase e não existe num PostgreSQL comum.
-- Todo o arquivo roda dentro de uma checagem de existência: no Supabase
-- real cria bucket e policy; num banco sem Storage, não faz nada e não
-- falha. A suíte local reproduz o schema (`00_supabase_stub.sql`), então
-- as policies abaixo são de fato executadas e testadas — ver
-- `11_storage.sql`.
--
-- Nenhuma migration anterior foi alterada.
-- ============================================================

do $$
begin
  if to_regclass('storage.buckets') is null then
    raise notice 'Schema storage ausente: nada a fazer (banco sem Supabase Storage).';
    return;
  end if;

  -- ── Buckets ───────────────────────────────────────────────
  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values (
    'public-assets', 'public-assets', true,
    5242880,  -- 5 MB: logotipo e foto de produto não passam disso
    array['image/png', 'image/jpeg', 'image/webp', 'image/svg+xml']
  )
  on conflict (id) do nothing;

  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values (
    'private-docs', 'private-docs', false,
    10485760, -- 10 MB
    array['application/pdf', 'image/png', 'image/jpeg']
  )
  on conflict (id) do nothing;

  -- ── Policies ──────────────────────────────────────────────
  -- `create policy` não aceita `if not exists`; o drop antes torna a
  -- migration repetível sem erro.
  drop policy if exists public_assets_read   on storage.objects;
  drop policy if exists public_assets_write  on storage.objects;
  drop policy if exists public_assets_update on storage.objects;
  drop policy if exists public_assets_delete on storage.objects;
  drop policy if exists private_docs_read    on storage.objects;
  drop policy if exists private_docs_write   on storage.objects;
  drop policy if exists buckets_read         on storage.buckets;

  -- Leitura do bucket público: qualquer um, inclusive quem não tem
  -- login. É o que faz a imagem abrir no link público do orçamento.
  execute $p$
    create policy public_assets_read on storage.objects
      for select to anon, authenticated
      using (bucket_id = 'public-assets')
  $p$;

  -- Escrita: só administrador. O vendedor não troca o logotipo da
  -- empresa nem a foto do catálogo — é a mesma regra de `products`,
  -- onde ele lê e não escreve.
  execute $p$
    create policy public_assets_write on storage.objects
      for insert to authenticated
      with check (bucket_id = 'public-assets' and public.is_admin())
  $p$;

  execute $p$
    create policy public_assets_update on storage.objects
      for update to authenticated
      using (bucket_id = 'public-assets' and public.is_admin())
      with check (bucket_id = 'public-assets' and public.is_admin())
  $p$;

  execute $p$
    create policy public_assets_delete on storage.objects
      for delete to authenticated
      using (bucket_id = 'public-assets' and public.is_admin())
  $p$;

  -- Bucket privado: nem leitura anônima. Só administrador, e por
  -- enquanto ninguém grava nada.
  execute $p$
    create policy private_docs_read on storage.objects
      for select to authenticated
      using (bucket_id = 'private-docs' and public.is_admin())
  $p$;

  execute $p$
    create policy private_docs_write on storage.objects
      for all to authenticated
      using (bucket_id = 'private-docs' and public.is_admin())
      with check (bucket_id = 'private-docs' and public.is_admin())
  $p$;

  -- A lista de buckets pode ser lida por qualquer um: são dois nomes,
  -- e o cliente do Storage precisa resolvê-los.
  execute $p$
    create policy buckets_read on storage.buckets
      for select to anon, authenticated
      using (true)
  $p$;

  raise notice 'Storage configurado: public-assets (leitura pública) e private-docs (admin).';
end $$;

-- ── Onde o logotipo entra ───────────────────────────────────
--
-- `app_settings.company.logo_url` já é lido pelo módulo de orçamentos
-- (`share/repository.ts` → `toCompany`) e já chega ao gerador de PDF.
-- Nada no renderizador precisa mudar: basta o administrador gravar a URL
-- pública do arquivo em `public-assets` nessa chave.
--
-- Igual para `products.image_url` e `quote_items.image_url_snapshot`,
-- que existem desde as migrations 0400 e 0600 e hoje ficam nulos.
