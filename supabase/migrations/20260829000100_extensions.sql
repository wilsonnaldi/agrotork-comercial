-- ============================================================
-- 0100 · Extensões
-- ============================================================
create extension if not exists "pgcrypto";   -- gen_random_uuid, gen_random_bytes
create extension if not exists "pg_trgm";    -- busca por similaridade (nome de cliente/produto)
create extension if not exists "unaccent";   -- busca ignorando acentos
