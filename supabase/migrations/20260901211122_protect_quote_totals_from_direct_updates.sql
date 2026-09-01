create or replace function public.trg_recalc_from_quote()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  -- Recalculate at the outermost trigger invocation. This also catches
  -- direct API/PostgREST attempts to write subtotal/total while avoiding
  -- recursion when recalculate_quote_totals() updates those same columns.
  if pg_trigger_depth() = 1
     and (
       new.discount_percent is distinct from old.discount_percent
       or new.discount_amount is distinct from old.discount_amount
       or new.shipping_amount is distinct from old.shipping_amount
       or new.subtotal is distinct from old.subtotal
       or new.total is distinct from old.total
     ) then
    perform public.recalculate_quote_totals(new.id);
  end if;
  return new;
end;
$function$;