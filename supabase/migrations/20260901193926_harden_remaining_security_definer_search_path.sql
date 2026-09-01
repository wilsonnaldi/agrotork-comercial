ALTER FUNCTION public.audit_capture() SET search_path = '';
ALTER FUNCTION public.expire_quotes() SET search_path = '';
ALTER FUNCTION public.handle_new_user() SET search_path = '';
ALTER FUNCTION public.purge_test_products() SET search_path = '';
ALTER FUNCTION public.recalculate_quote_totals(uuid) SET search_path = '';
ALTER FUNCTION public.trg_recalc_from_item() SET search_path = '';
ALTER FUNCTION public.trg_recalc_from_quote() SET search_path = '';