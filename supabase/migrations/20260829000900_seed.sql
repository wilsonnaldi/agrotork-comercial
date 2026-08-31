-- ============================================================
-- 0900 · Dados iniciais (editáveis pelo administrador)
-- Nenhuma dessas listas é definitiva nem fixa no código.
-- ============================================================

insert into public.units (code, name, allows_fraction, sort_order) values
  ('UN',   'Unidade',    false, 1),
  ('KG',   'Quilograma', true,  2),
  ('L',    'Litro',      true,  3),
  ('M',    'Metro',      true,  4),
  ('JG',   'Jogo',       false, 5),
  ('CJ',   'Conjunto',   false, 6),
  ('PC',   'Peça',       false, 7),
  ('HR',   'Hora',       true,  8),
  ('SERV', 'Serviço',    false, 9)
on conflict do nothing;

insert into public.categories (name, slug, sort_order) values
  ('Implementos',              public.slugify('Implementos'),              1),
  ('Peças',                    public.slugify('Peças'),                    2),
  ('Pulverização',             public.slugify('Pulverização'),             3),
  ('Tecnologia',               public.slugify('Tecnologia'),               4),
  ('Agricultura de Precisão',  public.slugify('Agricultura de Precisão'),  5),
  ('Serviços',                 public.slugify('Serviços'),                 6),
  ('Acessórios',               public.slugify('Acessórios'),               7)
on conflict do nothing;

insert into public.brands (name, slug, sort_order) values
  ('AGROTORK', public.slugify('AGROTORK'), 1),
  ('DJI',      public.slugify('DJI'),      2),
  ('KUHN',     public.slugify('KUHN'),     3),
  ('BALDAN',   public.slugify('BALDAN'),   4),
  ('ARAG',     public.slugify('ARAG'),     5),
  ('MAGNOJET', public.slugify('MAGNOJET'), 6),
  ('TRIMBLE',  public.slugify('TRIMBLE'),  7),
  ('AGRES',    public.slugify('AGRES'),    8)
on conflict do nothing;

-- Dados da empresa usados no cabeçalho e no PDF. Editáveis em Configurações.
insert into public.app_settings (key, value, description) values
  ('company', jsonb_build_object(
      'legal_name',   'AGROTORK',
      'trade_name',   'AGROTORK',
      'document',     '',
      'phone',        '',
      'whatsapp',     '',
      'email',        '',
      'address',      '',
      'city',         'Londrina',
      'state',        'PR',
      'zip_code',     '',
      'website',      'https://www.agrotork.com.br'
   ), 'Dados da empresa exibidos no sistema e no PDF do orçamento'),
  ('quote_defaults', jsonb_build_object(
      'validity_days',  15,
      'payment_terms',  'A combinar',
      'notes',          ''
   ), 'Valores padrão ao criar um novo orçamento')
on conflict (key) do nothing;
