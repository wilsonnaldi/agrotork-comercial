ALTER FUNCTION public.next_quote_number(integer) SET search_path = '';
ALTER FUNCTION public.assign_quote_number() SET search_path = '';
REVOKE ALL ON TABLE public.quote_sequences FROM anon, authenticated;
REVOKE ALL ON TABLE public.quote_sequences FROM public;
GRANT ALL ON TABLE public.quote_sequences TO postgres, service_role;
