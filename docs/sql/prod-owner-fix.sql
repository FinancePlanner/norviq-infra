-- Cutover window step 4: after `migrate-db.sh final` restores real prod data into
-- stockplan_production with --no-owner, the restored objects are owned by the
-- superuser (stockplan_user). The prod api connects as stockplan_production_app
-- and needs OWNERSHIP (not just GRANT) to run migrations / ALTER / DROP.
--
-- Idempotent + safe to re-run. Does NOT touch database-level ownership — that is
-- what breaks `REASSIGN OWNED BY` (the DB object is a system dependency).
--
-- Run against green: KUBECONFIG=~/.kube/norviq kubectl -n data exec -i postgres-0 \
--   -- sh -c 'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d stockplan_production' < docs/sql/prod-owner-fix.sql

-- Ensure the role exists (it already does on green; guard for portability).
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'stockplan_production_app') THEN
    CREATE ROLE stockplan_production_app LOGIN;
  END IF;
END $$;

GRANT ALL ON DATABASE stockplan_production TO stockplan_production_app;

\connect stockplan_production

DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT tablename FROM pg_tables WHERE schemaname = 'public' LOOP
    EXECUTE format('ALTER TABLE public.%I OWNER TO stockplan_production_app', r.tablename);
  END LOOP;
  FOR r IN SELECT sequencename FROM pg_sequences WHERE schemaname = 'public' LOOP
    EXECUTE format('ALTER SEQUENCE public.%I OWNER TO stockplan_production_app', r.sequencename);
  END LOOP;
  FOR r IN SELECT viewname FROM pg_views WHERE schemaname = 'public' LOOP
    EXECUTE format('ALTER VIEW public.%I OWNER TO stockplan_production_app', r.viewname);
  END LOOP;
  FOR r IN
    SELECT t.typname
    FROM pg_type t
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'public' AND t.typtype = 'e'
  LOOP
    EXECUTE format('ALTER TYPE public.%I OWNER TO stockplan_production_app', r.typname);
  END LOOP;
END $$;

ALTER SCHEMA public OWNER TO stockplan_production_app;
GRANT ALL ON SCHEMA public TO stockplan_production_app;
