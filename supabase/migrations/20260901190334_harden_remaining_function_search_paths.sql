begin;

-- Pin remaining application trigger/helper functions to an empty search_path.
-- Their non-system references are already schema-qualified.
alter function public.set_updated_at() set search_path = '';
alter function public.slugify(text) set search_path = '';
alter function public.only_digits(text) set search_path = '';
alter function public.normalize_customer() set search_path = '';
alter function public.set_catalog_slug() set search_path = '';
alter function public.stamp_quote_status() set search_path = '';
alter function public.audit_log_guard() set search_path = '';
alter function public.quote_is_shareable(public.quote_status) set search_path = '';

commit;