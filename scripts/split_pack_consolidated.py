"""
Split the consolidated pack migration into one file per table.

Input:  docs/schema/pack_extracted.sql (the canonical state)
Output: supabase/migrations/<timestamp>_<table_name>.sql -- 13 files:
        1 shared functions file + 11 tables + 1 view.

Each table file contains everything that targets that table:
    CREATE TABLE
    COMMENT ON TABLE / COLUMN
    CREATE INDEX ... ON public.<table>
    ALTER TABLE public.<table> ADD CONSTRAINT ...  (FKs originating here)
    ALTER TABLE public.<table> ENABLE ROW LEVEL SECURITY
    CREATE POLICY ... ON public.<table>
    CREATE TRIGGER ... ON public.<table>
    GRANT ... ON TABLE public.<table>

Trigger functions live in a shared functions file so multi-table
functions (pack_shelf_life_set_day, etc.) aren't duplicated.

The 13 timestamps are sequential within 2026-05-19 so they sort in
dependency order: functions first, lookup tables, parents, children,
view.
"""
import re
from pathlib import Path

SRC = Path("docs/schema/pack_extracted.sql")
MIG_DIR = Path("supabase/migrations")

# (timestamp, table_or_view_name) -- dependency order.
LAYOUT = [
    ("20260519000000", "pack_functions"),         # special: just the 9 trigger fns
    ("20260519001000", "pack_fail_category"),     # lookup
    ("20260519001100", "pack_shelf_life_metric"), # lookup
    ("20260519001200", "pack_session"),           # parent
    ("20260519001300", "pack_session_cases"),     # child of pack_session
    ("20260519001400", "pack_session_fails"),     # child of pack_session + pack_fail_category
    ("20260519001500", "pack_session_labor_hour"),# child of pack_session
    ("20260519001600", "pack_session_leftover"),  # child of pack_session
    ("20260519001700", "pack_session_summary_v"), # view over pack_session*
    ("20260519001800", "pack_moisture"),          # standalone (links to org_site/seed_batch/etc.)
    ("20260519001900", "pack_shelf_life"),        # parent of result/photo, links to pack_session
    ("20260519002000", "pack_shelf_life_photo"),  # child of pack_shelf_life
    ("20260519002100", "pack_shelf_life_result"), # child of pack_shelf_life + pack_shelf_life_metric
]


def parse_statements(text):
    """Split SQL text into statements. Respects $$-quoted bodies."""
    statements = []
    buf = []
    in_dollar = False
    for line in text.splitlines(keepends=True):
        buf.append(line)
        if line.count("$$") % 2 == 1:
            in_dollar = not in_dollar
        if not in_dollar and line.rstrip().endswith(";"):
            statements.append("".join(buf))
            buf = []
    if buf and "".join(buf).strip():
        statements.append("".join(buf))
    return statements


# Map every pack statement to the table it targets (or "pack_functions"
# for trigger function definitions / standalone trigger CREATEs that
# fire on a specific table).
def classify(stmt):
    """Return the table this statement should live with, or None."""
    s = stmt.lstrip()

    # CREATE FUNCTION pack_* -> shared functions file
    m = re.search(r'^CREATE (?:OR REPLACE )?FUNCTION\s+"public"\."(pack_[a-z_]+)"', s, re.I)
    if m:
        return "pack_functions"

    # CREATE TABLE public.pack_X -> X
    m = re.search(r'^CREATE TABLE (?:IF NOT EXISTS )?"public"\."(pack_[a-z_]+)"', s, re.I)
    if m:
        return m.group(1)

    # CREATE OR REPLACE VIEW public.pack_X -> X
    m = re.search(r'^CREATE (?:OR REPLACE )?VIEW\s+"public"\."(pack_[a-z_]+)"', s, re.I)
    if m:
        return m.group(1)

    # COMMENT ON TABLE / VIEW / COLUMN public.pack_X -> X
    m = re.search(r'^COMMENT ON (?:TABLE|VIEW|COLUMN)\s+"public"\."(pack_[a-z_]+)"', s, re.I)
    if m:
        return m.group(1)

    # COMMENT ON FUNCTION public.pack_X -> shared functions file
    m = re.search(r'^COMMENT ON FUNCTION\s+"public"\."(pack_[a-z_]+)"', s, re.I)
    if m:
        return "pack_functions"

    # CREATE INDEX ... ON public.pack_X -> X
    m = re.search(r'^CREATE (?:UNIQUE )?INDEX\s+\S+\s+ON\s+(?:ONLY\s+)?"public"\."(pack_[a-z_]+)"', s, re.I)
    if m:
        return m.group(1)

    # ALTER TABLE [ONLY] public.pack_X ADD CONSTRAINT / ENABLE RLS -> X
    m = re.search(r'^ALTER TABLE(?:\s+ONLY)?\s+"public"\."(pack_[a-z_]+)"', s, re.I)
    if m:
        return m.group(1)

    # CREATE POLICY ... ON public.pack_X -> X
    m = re.search(r'^CREATE POLICY\s+\S+\s+ON\s+"public"\."(pack_[a-z_]+)"', s, re.I)
    if m:
        return m.group(1)

    # CREATE [OR REPLACE] TRIGGER ... ON public.pack_X -> X
    m = re.search(r'^CREATE (?:OR REPLACE )?TRIGGER\s+\S+\s+.*?\bON\s+"public"\."(pack_[a-z_]+)"', s, re.I | re.S)
    if m:
        return m.group(1)

    # GRANT ... ON FUNCTION public.pack_X -> shared functions file.
    m = re.search(r'^GRANT\s+.*?\bON\s+FUNCTION\s+"public"\."(pack_[a-z_]+)"', s, re.I | re.S)
    if m:
        return "pack_functions"

    # GRANT ... ON [TABLE] public.pack_X -> X
    m = re.search(r'^GRANT\s+.*?\bON\s+(?:TABLE\s+)?"public"\."(pack_[a-z_]+)"', s, re.I | re.S)
    if m:
        return m.group(1)

    return None


def main():
    text = SRC.read_text(encoding="utf-8")
    statements = parse_statements(text)
    print(f"Parsed {len(statements)} statements from {SRC}")

    # Bucket statements by target.
    buckets = {name: [] for _, name in LAYOUT}
    skipped = 0
    for stmt in statements:
        target = classify(stmt)
        if target is None:
            # Carve header / blank lines / unclassified -- skip silently.
            if stmt.strip().startswith("--") or not stmt.strip():
                continue
            print(f"  WARN: unclassified statement: {stmt[:80]!r}")
            skipped += 1
            continue
        if target not in buckets:
            print(f"  WARN: unknown bucket {target!r} for {stmt[:80]!r}")
            skipped += 1
            continue
        buckets[target].append(stmt)

    if skipped:
        print(f"  ({skipped} unclassified)")

    # Write per-table files.
    MIG_DIR.mkdir(parents=True, exist_ok=True)
    written = 0
    for timestamp, name in LAYOUT:
        stmts = buckets.get(name, [])
        if not stmts:
            print(f"  SKIP: no statements for {name}")
            continue
        header = (
            f"-- {name}\n"
            f"-- {'=' * (len(name) + 0)}\n"
            f"-- Sourced from the live dev schema on 2026-05-19. Split out of\n"
            f"-- the prior 20260518230000_pack_module_consolidated.sql so each\n"
            f"-- pack object lives in its own migration file again.\n\n"
        )
        # Strip ALTER ... OWNER TO postgres if any slipped in.
        cleaned = []
        for s in stmts:
            lines = [
                ln for ln in s.splitlines(keepends=True)
                if not re.match(r"^\s*ALTER (TABLE|FUNCTION|VIEW)\s+\"public\"\.\"pack_\w+\".*OWNER TO\b", ln, re.I)
            ]
            joined = "".join(lines).strip("\n")
            if joined.strip():
                cleaned.append(joined + "\n")

        body = "\n\n".join(cleaned) + "\n"
        path = MIG_DIR / f"{timestamp}_{name}.sql"
        path.write_text(header + body, encoding="utf-8")
        print(f"  wrote {path}  ({len(stmts)} stmts, {path.stat().st_size} bytes)")
        written += 1

    print(f"\nDone -- {written} files written.")


if __name__ == "__main__":
    main()
