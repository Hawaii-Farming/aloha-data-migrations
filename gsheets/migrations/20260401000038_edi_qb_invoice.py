"""
Sync QuickBooks Online Invoices into edi_qb_invoice + edi_qb_invoice_line.
==========================================================================

Pulls Invoice data directly from Intuit's API (no Google Sheets middle-step)
for every org that has a row in org_quickbooks_token, refreshes the access
token on demand, paginates through every invoice, and upserts the local
mirror tables.

Header columns mirror what the team was extracting via G-Accon:
    Invoice Number, Customer Name, Txn Date, Total Amount

Line columns:
    Item Name, Qty, Amount, Service Date, Description

Replaces 037 (`fin_invoice_expense.py`) for invoices long-term -- 037 still
runs against the legacy spreadsheet path until the team retires it.

Environment:
    SUPABASE_DB_URL                 -- Postgres connection string
    INTUIT_CLIENT_ID                -- production Intuit app credentials
    INTUIT_CLIENT_SECRET

Idempotent: each run upserts header rows, then DELETEs and reinserts every
line for that invoice so deleted/edited lines are reflected. Other invoices
left untouched.

Usage:
    python gsheets/migrations/20260401000038_edi_qb_invoice.py
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

# Transient HTTP statuses that warrant a retry.
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
    expired -- in that case the org has to reconnect via aloha-app.
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

    # Refresh if access token is within 60 seconds of expiry.
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


def fetch_all_invoices(realm_id, access_token, since_date=None):
    """Paginate the QB query endpoint. Returns invoices with TxnDate >= since_date.

    since_date is an ISO date string ('YYYY-MM-DD'). Defaults to Jan 1 of the
    current year so the nightly only refreshes the current calendar year --
    historical invoices are left in place from earlier syncs. Pass an older
    date or None (None = no filter) to widen the window for backfills.
    """
    if since_date is None:
        since_date = f"{datetime.now(timezone.utc).year}-01-01"

    where_clause = f"WHERE TxnDate >= '{since_date}' " if since_date else ""

    invoices = []
    start_pos = 1
    page = 0
    while True:
        page += 1
        sql = (
            f"SELECT * FROM Invoice {where_clause}"
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
        page_invs = data.get("QueryResponse", {}).get("Invoice", []) or []
        if not page_invs:
            break
        invoices.extend(page_invs)
        print(f"  page {page}: {len(page_invs)} invoices (running total {len(invoices)})")
        if len(page_invs) < PAGE_SIZE:
            break
        start_pos += len(page_invs)
    return invoices


UPSERT_BATCH_SIZE = 200  # commit every N invoices so the pooler can't time us out


def upsert_invoices(org_id, invoices):
    """Upsert invoices in batches via execute_values bulk inserts.

    For each batch we collect header rows + line rows, then issue:
       1. one execute_values UPSERT for all headers in the batch
       2. one DELETE for all old line rows (by invoice_id = ANY(...))
       3. one execute_values INSERT for all new line rows
    That collapses ~5 round trips per invoice down to 3 per batch of 200,
    which is a ~300x reduction in pooler round-trips on the typical mix.
    """
    inv_count = 0
    line_count = 0
    skipped_no_detail = 0
    total = len(invoices)

    for batch_start in range(0, total, UPSERT_BATCH_SIZE):
        batch = invoices[batch_start : batch_start + UPSERT_BATCH_SIZE]
        sync_time = datetime.now(timezone.utc)

        # Build header + line rows for this batch.
        header_rows = []
        line_rows = []
        invoice_ids = []
        for inv in batch:
            invoice_id = str(inv.get("Id"))
            invoice_ids.append(invoice_id)
            customer = inv.get("CustomerRef") or {}
            header_rows.append((
                org_id,
                invoice_id,
                inv.get("DocNumber"),
                customer.get("value"),
                customer.get("name"),
                inv.get("TxnDate"),
                inv.get("TotalAmt"),
                inv.get("SyncToken"),
                sync_time,
            ))
            for line in inv.get("Line") or []:
                detail = line.get("SalesItemLineDetail")
                if not detail:
                    # Skip subtotal / tax / discount lines without sales-item detail.
                    skipped_no_detail += 1
                    continue
                item = detail.get("ItemRef") or {}
                line_rows.append((
                    org_id,
                    invoice_id,
                    line.get("LineNum"),
                    item.get("name"),
                    line.get("Description"),
                    detail.get("Qty"),
                    line.get("Amount"),
                    detail.get("ServiceDate"),
                ))

        with get_pg_conn() as conn:
            with conn.cursor() as cur:
                # 1. Bulk UPSERT headers.
                execute_values(
                    cur,
                    """
                    INSERT INTO edi_qb_invoice
                      (org_id, id, invoice_number, customer_id, customer_name,
                       invoice_date, total_amount, sync_token, synced_at)
                    VALUES %s
                    ON CONFLICT (org_id, id) DO UPDATE SET
                        invoice_number = EXCLUDED.invoice_number,
                        customer_id    = EXCLUDED.customer_id,
                        customer_name  = EXCLUDED.customer_name,
                        invoice_date   = EXCLUDED.invoice_date,
                        total_amount   = EXCLUDED.total_amount,
                        sync_token     = EXCLUDED.sync_token,
                        synced_at      = EXCLUDED.synced_at
                    """,
                    header_rows,
                    page_size=UPSERT_BATCH_SIZE,
                )
                # 2. Bulk DELETE old lines for these invoices.
                cur.execute(
                    "DELETE FROM edi_qb_invoice_line "
                    "WHERE org_id = %s AND invoice_id = ANY(%s)",
                    (org_id, invoice_ids),
                )
                # 3. Bulk INSERT new lines.
                if line_rows:
                    execute_values(
                        cur,
                        """
                        INSERT INTO edi_qb_invoice_line
                          (org_id, invoice_id, line_num, item_name,
                           description, cases, amount, service_date)
                        VALUES %s
                        """,
                        line_rows,
                        page_size=1000,
                    )
            conn.commit()

        inv_count += len(header_rows)
        line_count += len(line_rows)
        if (batch_start // UPSERT_BATCH_SIZE) % 5 == 0:
            print(f"  upserted {inv_count}/{total} invoices...")

    return inv_count, line_count, skipped_no_detail


def sync_one_org(org_id):
    # Token + access-token refresh use a short-lived connection so the
    # invoice fetch (long HTTP) doesn't keep a Postgres transaction open.
    with get_pg_conn() as conn:
        realm_id, access_token = get_valid_access_token(conn, org_id)
    if realm_id is None:
        print(f"  [{org_id}] no QB token row -- skipping.")
        return
    # Nightly window: current calendar year. Older invoices are kept
    # in the DB from prior syncs and don't get re-touched. To force a
    # full backfill, pass since_date=None (or a much earlier date).
    print(f"  [{org_id}] realm_id={realm_id}, fetching invoices...")
    invoices = fetch_all_invoices(realm_id, access_token)
    print(f"  [{org_id}] pulled {len(invoices)} invoices from QB; upserting...")
    inv_n, line_n, skipped = upsert_invoices(org_id, invoices)
    print(f"  [{org_id}] upserted {inv_n} invoices, {line_n} lines"
          f" (skipped {skipped} non-sales-item lines)")


def main():
    print("=" * 60)
    print("EDI / QuickBooks Online: Invoice sync")
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
