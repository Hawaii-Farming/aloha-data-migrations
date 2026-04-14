"""
Direct-SQL helpers via psycopg2 for migration scripts.

PostgREST (via supabase-py) has two limitations that hurt migrations:
  1. Silent 1000-row cap on SELECT responses — long lookups miss rows.
  2. One HTTP roundtrip per row/batch — bulk inserts of 10k+ rows take
     minutes. Bulk updates with per-row filters are even worse.

For large lookups, paginate supabase-py via .range() — or use
pg_select_all() here. For bulk inserts/updates over a few thousand rows,
use pg_bulk_insert() and pg_bulk_update() here.
"""

import os

import psycopg2
from psycopg2.extras import execute_values


def get_pg_conn():
    """Direct psycopg2 connection using SUPABASE_DB_URL from env/.env.

    Caller is responsible for closing. Prefer using as a context manager:
        with get_pg_conn() as conn:
            with conn.cursor() as cur:
                ...
            conn.commit()
    """
    db_url = os.environ.get("SUPABASE_DB_URL")
    if not db_url:
        raise SystemExit(
            "ERROR: SUPABASE_DB_URL must be set in .env for direct-SQL operations\n"
            "  Get it from: Supabase Dashboard -> Settings -> Database -> Connection string"
        )
    return psycopg2.connect(db_url)


def pg_select_all(conn, sql, params=None):
    """Run a SELECT and return all rows as list of dicts. No 1000-row cap."""
    with conn.cursor() as cur:
        cur.execute(sql, params or ())
        cols = [desc[0] for desc in cur.description]
        return [dict(zip(cols, row)) for row in cur.fetchall()]


def paginate_select(supabase, table, select_str, eq_filters=None, page_size=1000):
    """Supabase-py SELECT that bypasses the 1000-row cap via .range() pagination.

    Use this for lookup builds where you need ALL rows matching filters,
    not just the first 1000.

    Args:
        supabase: supabase-py client
        table: table name
        select_str: comma-separated column list (same as .select())
        eq_filters: dict of {column: value} applied as .eq() filters (optional)
        page_size: rows per request (max 1000 on most Supabase configs)

    Returns:
        Flat list of all matching rows as dicts.
    """
    all_data = []
    page = 0
    while True:
        q = supabase.table(table).select(select_str)
        if eq_filters:
            for col, val in eq_filters.items():
                q = q.eq(col, val)
        r = q.range(page * page_size, (page + 1) * page_size - 1).execute()
        if not r.data:
            break
        all_data.extend(r.data)
        if len(r.data) < page_size:
            break
        page += 1
    return all_data


def pg_bulk_insert(conn, table, rows, page_size=1000):
    """Bulk INSERT via execute_values — one query per page_size rows.

    `rows` is a list of dicts with identical keys. Column order comes from
    the first row. Transaction is NOT committed here; caller commits.

    Example:
        with get_pg_conn() as conn:
            pg_bulk_insert(conn, "ops_task_tracker", tracker_rows)
            conn.commit()
    """
    if not rows:
        return 0
    columns = list(rows[0].keys())
    values = [tuple(r.get(c) for c in columns) for r in rows]

    col_list = ", ".join(f'"{c}"' for c in columns)
    placeholders = "(" + ", ".join(["%s"] * len(columns)) + ")"
    sql = f'INSERT INTO "{table}" ({col_list}) VALUES %s'

    with conn.cursor() as cur:
        execute_values(cur, sql, values, template=placeholders, page_size=page_size)
    return len(rows)


def pg_bulk_update_by_key(conn, table, rows, key_columns, update_columns):
    """Bulk UPDATE where each row matches on key_columns and sets update_columns.

    Uses UPDATE ... FROM (VALUES ...) pattern — one query for all rows.

    `rows` is a list of dicts. Must contain all keys in key_columns +
    update_columns. Transaction is NOT committed here.

    Returns number of affected rows.
    """
    if not rows:
        return 0
    all_cols = key_columns + update_columns
    values = [tuple(r[c] for c in all_cols) for r in rows]

    set_clause = ", ".join(f'"{c}" = v."{c}"' for c in update_columns)
    where_clause = " AND ".join(f't."{c}" = v."{c}"' for c in key_columns)
    col_list = ", ".join(f'"{c}"' for c in all_cols)
    placeholders = "(" + ", ".join(["%s"] * len(all_cols)) + ")"

    sql = f"""
        UPDATE "{table}" AS t
        SET {set_clause}
        FROM (VALUES %s) AS v({col_list})
        WHERE {where_clause}
    """

    with conn.cursor() as cur:
        execute_values(cur, sql, values, template=placeholders, page_size=1000)
        return cur.rowcount
