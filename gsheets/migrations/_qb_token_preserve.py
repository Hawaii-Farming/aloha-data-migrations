"""Preserve org_quickbooks_token across migration 001's destructive TRUNCATE.

Migration 001_sys.py TRUNCATEs every public-schema table CASCADE, which
wipes OAuth credentials that aren't recoverable from any migration
source. Backup-and-restore preserves the row across a full --all run.

Flow within a single _run_nightly.py invocation:
  - 001 calls backup() right before the TRUNCATE.
  - 003 calls restore() right after hr_employee is reseeded (so the
    composite FK (org_id, connected_by) -> hr_employee is satisfied
    when connected_by is non-NULL).
  - The backup lives in /tmp during a single workflow job; cross-job
    contamination is impossible on GitHub Actions runners since they
    start with an empty /tmp.

Idempotent and safe to skip: if the table doesn't yet exist (fresh DB
before the schema migration that created it runs), backup() is a no-op.
If 001 didn't run this invocation (e.g., nightly DEFAULT_SET excludes
it), the backup file is absent and restore() is a no-op.
"""
import json
import tempfile
from pathlib import Path

# Use the platform tmp dir so local Windows runs work too (the GH Actions
# runners are Linux, where this resolves to /tmp/).
BACKUP_PATH = Path(tempfile.gettempdir()) / "aloha_qb_token_backup.json"

# Column list mirrors the table definition in
# supabase/migrations/20260501141000_org_quickbooks_token.sql. Keep in
# sync if the schema changes.
COLUMNS = (
    "org_id",
    "realm_id",
    "access_token",
    "refresh_token",
    "access_expires_at",
    "refresh_expires_at",
    "connected_by",
    "connected_at",
    "updated_at",
    "is_deleted",
)


def _serialize(val):
    """Make a value JSON-encodable. datetimes go to ISO 8601 strings."""
    if hasattr(val, "isoformat"):
        return val.isoformat()
    return val


def backup(conn):
    """Snapshot org_quickbooks_token rows to BACKUP_PATH.

    Safe to call before the schema migration that creates the table has
    run -- the existence check skips the snapshot in that case.
    """
    with conn.cursor() as cur:
        cur.execute(
            "SELECT EXISTS(SELECT 1 FROM information_schema.tables "
            "WHERE table_schema = 'public' AND table_name = 'org_quickbooks_token')"
        )
        if not cur.fetchone()[0]:
            print("  org_quickbooks_token table does not exist; skipping backup")
            return

        col_list = ", ".join(COLUMNS)
        cur.execute(f"SELECT {col_list} FROM public.org_quickbooks_token")
        rows = cur.fetchall()

    payload = [
        {col: _serialize(val) for col, val in zip(COLUMNS, row)}
        for row in rows
    ]
    BACKUP_PATH.write_text(json.dumps(payload, indent=2))
    print(
        f"  Backed up {len(payload)} org_quickbooks_token row(s) to "
        f"{BACKUP_PATH} -- migration 003 will restore after hr_employee reseed"
    )


def restore(conn):
    """Restore org_quickbooks_token rows from BACKUP_PATH and delete the file.

    No-op if the file is absent (001 didn't run this invocation) or empty
    (no token rows existed before the truncate).
    """
    if not BACKUP_PATH.exists():
        return

    rows = json.loads(BACKUP_PATH.read_text())
    if not rows:
        print(f"  Backup file empty; removing {BACKUP_PATH}")
        BACKUP_PATH.unlink()
        return

    col_list = ", ".join(COLUMNS)
    placeholders = ", ".join(["%s"] * len(COLUMNS))
    updates = ", ".join(f"{c} = EXCLUDED.{c}" for c in COLUMNS if c != "org_id")
    sql = (
        f"INSERT INTO public.org_quickbooks_token ({col_list}) "
        f"VALUES ({placeholders}) "
        f"ON CONFLICT (org_id) DO UPDATE SET {updates}"
    )

    with conn.cursor() as cur:
        for row in rows:
            cur.execute(sql, [row.get(c) for c in COLUMNS])
    conn.commit()

    BACKUP_PATH.unlink()
    print(
        f"  Restored {len(rows)} org_quickbooks_token row(s); removed "
        f"{BACKUP_PATH}"
    )
