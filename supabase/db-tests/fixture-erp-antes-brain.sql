-- Exclusivamente no banco descartavel do ensaio: 1 orcamento e 2 pedidos.
insert into public.quotes (customer_id, owner_id)
select id, 'aaaaaaaa-0000-4000-8000-00000000d001'
from public.customers limit 1;

insert into public.orders
  (number, sequence_year, sequence_number, customer_id, owner_id, total)
select 'PRE-BRAIN-' || n, 2026, 900000 + n, c.id,
       'aaaaaaaa-0000-4000-8000-00000000d001', n * 100
from (select id from public.customers limit 1) c
cross join generate_series(1, 2) n;
