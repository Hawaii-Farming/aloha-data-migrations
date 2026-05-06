"""
Sync QuickBooks Online Purchases ("Expenses") into edi_qb_expense + edi_qb_expense_line.
=========================================================================================

Pulls Purchase data directly from Intuit's API for every org in
org_quickbooks_token, refreshes the access token if near expiry (rotating
refresh tokens are persisted), paginates through every Purchase, and
upserts the local mirror tables.

Field selection mirrors the team's G-Accon export:
    header: PayeeRef.name, AccountRef.name, Credit, TxnDate
    lines : AccountRef.name (line-level), ClassRef.name, Description, Amount

Mirrors the architecture of 038_edi_qb_invoice.py:
  * Per-batch DB connection (no idle transactions across HTTP fetch).
  * Bulk UPSERT via execute_values (~300x fewer round-trips than per-row).
  * Default window = current calendar year. Pass since_date=None to force
    a full backfill.

Environment:
    SUPABASE_DB_URL       -- Postgres connection string
    INTUIT_CLIENT_ID      -- production Intuit app credentials
    INTUIT_CLIENT_SECRET

Usage:
    python gsheets/migrations/20260401000039_edi_qb_expense.py
"""
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

from psycopg2.extras import execute_values

sys.path.insert(0, str(Path(__file__).parent))

from _config import _load_env_file  # noqa: E402  triggers .env load
from _pg import get_pg_conn  # noqa: E402

_load_env_file()

INTUIT_CLIENT_ID = os.environ.get("INTUIT_CLIENT_ID")
INTUIT_CLIENT_SECRET = os.environ.get("INTUIT_CLIENT_SECRET")
INTUIT_API_BASE = "https://quickbooks.api.intuit.com"  # production
INTUIT_TOKEN_URL = "https://oauth.platform.intuit.com/oauth2/v1/tokens/bearer"
PAGE_SIZE = 1000
MINOR_VERSION = "70"
UPSERT_BATCH_SIZE = 200

_TRANSIENT_STATUSES = (429, 500, 502, 503, 504)


def _http_get_with_retry(url, headers, attempts=5, timeout=60):
    """GET with exponential backoff on 5xx/429."""
    delay = 2.0
    last_err = None
    for i in range(attempts):
        try:
            req = urllib.request.Request(url, headers=headers, method="GET")
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return json.loads(r.read().decode())
        except urllib.error.HTTPError as e:
            if e.code not in _TRANSIENT_STATUSES:
                raise
            body = e.read().decode(errors="replace")[:300]
            last_err = e
            if i == attempts - 1:
                break
            print(f"  Intuit {e.code} on GET; retry in {delay:.0f}s ({i+1}/{attempts-1}). body={body}")
            time.sleep(delay)
            delay *= 2
    assert last_err is not None
    raise last_err


def get_valid_access_token(conn, org_id):
    """Read tokens from org_quickbooks_token, refresh if near expiry, persist.

    Returns (realm_id, access_token). Raises if the refresh token itself has
    expired -- the org has to reconnect via aloha-app.
    """
    if not INTUIT_CLIENT_ID or not INTUIT_CLIENT_SECRET:
        raise SystemExit("ERROR: INTUIT_CLIENT_ID and INTUIT_CLIENT_SECRET must be set in env")

    with conn.cursor() as cur:
        cur.execute(
            """SELECT realm_id, access_token, refresh_token,
                      access_expires_at, refresh_expires_at
               FROM org_quickbooks_token
               WHERE org_id = %s AND is_deleted = false""",
            (org_id,),
        )
        row = cur.fetchone()

    if not row:
        return None, None
    realm_id, access_token, refresh_token, access_exp, refresh_exp = row

    now = datetime.now(timezone.utc)
    if refresh_exp <= now:
        raise SystemExit(
            f"Refresh token for org_id={org_id} expired at {refresh_exp}; "
            f"reconnect QuickBooks from aloha-app settings."
        )

    if access_exp - timedelta(seconds=60) > now:
        return realm_id, access_token

    print(f"  [{org_id}] access token near expiry, refreshing...")
    basic = base64.b64encode(f"{INTUIT_CLIENT_ID}:{INTUIT_CLIENT_SECRET}".encode()).decode()
    body = urllib.parse.urlencode(
        {"grant_type": "refresh_token", "refresh_token": refresh_token}
    ).encode()
    req = urllib.request.Request(
        INTUIT_TOKEN_URL,
        data=body,
        headers={
            "Authorization": f"Basic {basic}",
            "Content-Type": "application/x-www-form-urlencoded",
            "Accept": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            tok = json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        raise SystemExit(f"Token refresh failed: HTTP {e.code} {e.read().decode()[:300]}")

    new_access = tok["access_token"]
    new_refresh = tok["refresh_token"]
    new_access_exp = now + timedelta(seconds=tok["expires_in"])
    new_refresh_exp = now + timedelta(seconds=tok["x_refresh_token_expires_in"])

    with conn.cursor() as cur:
        cur.execute(
            """UPDATE org_quickbooks_token
               SET access_token=%s, refresh_token=%s,
                   access_expires_at=%s, refresh_expires_at=%s,
                   updated_at=now()
               WHERE org_id=%s""",
            (new_access, new_refresh, new_access_exp, new_refresh_exp, org_id),
        )
    conn.commit()
    print(f"  [{org_id}] tokens refreshed and persisted.")
    return realm_id, new_access


def fetch_all_purchases(realm_id, access_token, since_date=None):
    """Paginate the QB query endpoint for Purchase. Defaults to YTD."""
    if since_date is None:
        since_date = f"{datetime.now(timezone.utc).year}-01-01"

    where_clause = f"WHERE TxnDate >= '{since_date}' " if since_date else ""

    purchases = []
    start_pos = 1
    page = 0
    while True:
        page += 1
        sql = (
            f"SELECT * FROM Purchase {where_clause}"
            f"STARTPOSITION {start_pos} MAXRESULTS {PAGE_SIZE}"
        )
        url = (
            f"{INTUIT_API_BASE}/v3/company/{urllib.parse.quote(realm_id)}/query"
            f"?query={urllib.parse.quote(sql)}&minorversion={MINOR_VERSION}"
        )
        data = _http_get_with_retry(
            url,
            headers={
                "Authorization": f"Bearer {access_token}",
                "Accept": "application/json",
            },
        )
        page_rows = data.get("QueryResponse", {}).get("Purchase", []) or []
        if not page_rows:
            break
        purchases.extend(page_rows)
        print(f"  page {page}: {len(page_rows)} purchases (running total {len(purchases)})")
        if len(page_rows) < PAGE_SIZE:
            break
        start_pos += len(page_rows)
    return purchases


def _line_account(detail_block):
    """Return (account_name, class_name) from whichever detail block is present."""
    if not detail_block:
        return None, None
    acc = (detail_block.get("AccountRef") or {}).get("name")
    cls = (detail_block.get("ClassRef") or {}).get("name")
    return acc, cls


def upsert_purchases(org_id, purchases):
    """Bulk-upsert Purchases in batches via execute_values."""
    hdr_count = 0
    line_count = 0
    skipped_no_detail = 0
    total = len(purchases)

    for batch_start in range(0, total, UPSERT_BATCH_SIZE):
        batch = purchases[batch_start : batch_start + UPSERT_BATCH_SIZE]
        sync_time = datetime.now(timezone.utc)

        header_rows = []
        line_rows = []
        purchase_ids = []
        for p in batch:
            purchase_id = str(p.get("Id"))
            purchase_ids.append(purchase_id)
            # The "payee" on a QB Purchase is exposed via Purchase.EntityRef
            # (vendor / customer / employee). G-Accon labels it "Payee Ref"
            # in its UI but the JSON field is EntityRef.
            payee = p.get("EntityRef") or {}
            account = p.get("AccountRef") or {}
            header_rows.append((
                org_id,
                purchase_id,
                payee.get("name"),
                account.get("name"),
                bool(p.get("Credit", False)),
                p.get("TxnDate"),
                sync_time,
            ))
            # QB Purchase lines don't always include LineNum (especially
            # single-line expenses), but our PK requires it. Fall back to the
            # 1-based array index when missing so we still get a stable order.
            for idx, line in enumerate(p.get("Line") or [], start=1):
                # Two detail-block variants:
                #   AccountBasedExpenseLineDetail -- standard expense category
                #   ItemBasedExpenseLineDetail    -- when the expense buys an inventory item
                # Both expose AccountRef + ClassRef on the same shape.
                detail = (
                    line.get("AccountBasedExpenseLineDetail")
                    or line.get("ItemBasedExpenseLineDetail")
                )
                if not detail:
                    skipped_no_detail += 1
                    continue
                account_name, class_name = _line_account(detail)
                line_rows.append((
                    org_id,
                    purchase_id,
                    line.get("LineNum") or idx,
                    account_name,
                    class_name,
                    line.get("Description"),
                    line.get("Amount"),
                ))

        with get_pg_conn() as conn:
            with conn.cursor() as cur:
                # 1. Bulk UPSERT headers.
                execute_values(
                    cur,
                    """
                    INSERT INTO edi_qb_expense
                      (org_id, id, payee_name, account_name, is_credit, transaction_date, synced_at)
                    VALUES %s
                    ON CONFLICT (org_id, id) DO UPDATE SET
                        payee_name       = EXCLUDED.payee_name,
                        account_name     = EXCLUDED.account_name,
                        is_credit        = EXCLUDED.is_credit,
                        transaction_date = EXCLUDED.transaction_date,
                        synced_at        = EXCLUDED.synced_at
                    """,
                    header_rows,
                    page_size=UPSERT_BATCH_SIZE,
                )
                # 2. Bulk DELETE old lines for these purchases.
                cur.execute(
                    "DELETE FROM edi_qb_expense_line "
                    "WHERE org_id = %s AND expense_id = ANY(%s)",
                    (org_id, purchase_ids),
                )
                # 3. Bulk INSERT new lines.
                if line_rows:
                    execute_values(
                        cur,
                        """
                        INSERT INTO edi_qb_expense_line
                          (org_id, expense_id, line_num, account_name,
                           class_name, description, amount)
                        VALUES %s
                        """,
                        line_rows,
                        page_size=1000,
                    )
            conn.commit()

        hdr_count += len(header_rows)
        line_count += len(line_rows)
        if (batch_start // UPSERT_BATCH_SIZE) % 5 == 0:
            print(f"  upserted {hdr_count}/{total} purchases...")

    return hdr_count, line_count, skipped_no_detail


def sync_one_org(org_id):
    with get_pg_conn() as conn:
        realm_id, access_token = get_valid_access_token(conn, org_id)
    if realm_id is None:
        print(f"  [{org_id}] no QB token row -- skipping.")
        return
    print(f"  [{org_id}] realm_id={realm_id}, fetching purchases (YTD)...")
    purchases = fetch_all_purchases(realm_id, access_token)
    print(f"  [{org_id}] pulled {len(purchases)} purchases from QB; upserting...")
    hdr, lines, skipped = upsert_purchases(org_id, purchases)
    print(f"  [{org_id}] upserted {hdr} purchases, {lines} lines"
          f" (skipped {skipped} lines without an expense detail block)")


def main():
    print("=" * 60)
    print("EDI / QuickBooks Online: Expense (Purchase) sync")
    print("=" * 60)
    with get_pg_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """SELECT org_id FROM org_quickbooks_token
                   WHERE is_deleted = false ORDER BY org_id"""
            )
            org_ids = [r[0] for r in cur.fetchall()]
    if not org_ids:
        print("No connected QB orgs found in org_quickbooks_token. Nothing to sync.")
        return
    print(f"Syncing {len(org_ids)} org(s): {org_ids}")
    for org_id in org_ids:
        sync_one_org(org_id)
    print("=" * 60)
    print("DONE")
    print("=" * 60)


if __name__ == "__main__":
    main()
