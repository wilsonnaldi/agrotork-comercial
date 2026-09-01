-- Revoke direct RPC execution from trigger-only SECURITY DEFINER functions.
-- These functions are invoked exclusively by PostgreSQL triggers and are not
-- used by RLS policies or the application frontend (confirmed via grep across
-- src/, and cross-checked against pg_trigger and pg_policies on the remote
-- project as of 2026-09-01).
-- PUBLIC, anon and authenticated must not be able to invoke them directly via
-- /rest/v1/rpc/... -- this closes 4 of the 32 Supabase Security Advisor
-- warnings (anon_security_definer_function_executable /
-- authenticated_security_definer_function_executable).
--
-- NOT revoked (reviewed and confirmed still required):
--   is_admin, auth_role, owns_quote, is_active_user, quote_is_editable
--     -> embedded directly in RLS policy USING/WITH CHECK clauses; revoking
--        EXECUTE from authenticated would break RLS evaluation for every
--        logged-in user.
--   get_shared_quote -> intentional public RPC for the quote-sharing feature
--        (looked up by token, not sequential id).
--   discard_quote_draft -> called directly by the frontend
--        (supabase.rpc('discard_quote_draft', ...)); authenticated access is
--        required.
--
-- service_role and postgres are untouched (need full access regardless).
--
-- NOT applied to the remote project yet -- review before running.

REVOKE EXECUTE ON FUNCTION public.assign_quote_number() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.trg_recalc_from_item() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.trg_recalc_from_quote() FROM PUBLIC, anon, authenticated;
