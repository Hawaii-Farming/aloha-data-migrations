"""
Recover the source SQL for prod-only migration versions.

Connects to prod via psycopg2, reads supabase_migrations.schema_migrations for
any version that isn't already a local file under supabase/migrations/, and
writes each as a `<version>_recovered_from_prod_<name>.sql` migration file
with a header comment.

Designed for the pull-prod-drift workflow: it preserves visibility into what
someone added directly to prod before any `supabase migration repair`
bookkeeping is done.

Env:
    PROD_DB_URL    Postgres connection string for the prod project (pooler
                   format works: postgresql://postgres.<ref>:<pwd>@aws-0-...).
                   Or alternatively set PROD_PROJECT_REF + PROD_DB_PASSWORD
                   and the script will assemble the pooler URL.
"""
import os
import pathlib
import re
import sys

import psycopg2

MIGRATIONS_DIR = pathlib.Path("supabase/migrations")


def get_conn():
    url = os.environ.get("PROD_DB_URL")
    if not url:
        ref = os.environ["PROD_PROJECT_REF"]
        pwd = os.environ["PROD_DB_PASSWORD"]
        url = f"postgresql://postgres.{ref}:{pwd}@aws-0-us-east-1.pooler.supabase.com:5432/postgres"
    return psycopg2.connect(url)


def local_versions():
    return {
        m.group(0)
        for p in MIGRATIONS_DIR.glob("*.sql")
        if (m := re.match(r"^\d{14}", p.name))
    }


def safe_name(name):
    return re.sub(r"[^A-Za-z0-9_]+", "_", name or "unknown").strip("_") or "unknown"


def main():
    have = local_versions()
    print(f"Local versions in repo: {len(have)}")

    conn = get_conn()
    with conn, conn.cursor() as cur:
        cur.execute(
            """SELECT version, COALESCE(name, 'unknown'), statements
                 FROM supabase_migrations.schema_migrations
                 ORDER BY version"""
        )
        rows = cur.fetchall()

    prod_only = [(v, n, s) for (v, n, s) in rows if v not in have]
    print(f"Prod-only versions to recover: {len(prod_only)}")

    if not prod_only:
        return 0

    for version, name, statements in prod_only:
        body = "\n-- ----\n".join(statements or [])
        fname = MIGRATIONS_DIR / f"{version}_recovered_from_prod_{safe_name(name)}.sql"
        fname.write_text(
            f"-- RECOVERED FROM PROD via pull-prod-drift workflow.\n"
            f"-- Original prod migration: version={version}, name={name!r}.\n"
            f"-- Review the SQL below, rename this file, and edit before\n"
            f"-- treating as authoritative.\n\n"
            f"{body}\n"
        )
        print(f"  wrote {fname}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
