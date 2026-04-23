-- CI smoke test: verifies that new migration files in this repo are picked
-- up by the Deploy Supabase Schema workflow, applied to production via
-- supabase db push, and recorded in supabase_migrations.schema_migrations.
-- Changing the COMMENT on the public schema is idempotent and harmless.

COMMENT ON SCHEMA public IS 'Aloha Farming production schema — authored in Hawaii-Farming/aloha-data-migrations.';
