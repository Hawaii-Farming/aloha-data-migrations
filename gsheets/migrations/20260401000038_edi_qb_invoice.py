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


def fetch_all_invoices(realm_id, access_token):
    """Paginate the QB query endpoint. Returns the full list of Invoice dicts."""
    invoices = []
    start_pos = 1
    page = 0
    while True:
        page += 1
        sql = f"SELECT * FROM Invoice STARTPOSITION {start_pos} MAXRESULTS {PAGE_SIZE}"
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


def _upsert_one_invoice(cur, org_id, inv):
    """Upsert a single invoice + its lines. Returns (1, line_count, skipped_no_detail)."""
    qb_id = str(inv.get("Id"))
    customer = inv.get("CustomerRef") or {}
    cur.execute(
        """
        INSERT INTO edi_qb_invoice
          (org_id, qb_id, qb_doc_number, qb_customer_id, qb_customer_name,
           txn_date, total_amt, raw_payload, qb_synced_at)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s::jsonb, now())
        ON CONFLICT (org_id, qb_id) DO UPDATE SET
            qb_doc_number    = EXCLUDED.qb_doc_number,
            qb_customer_id   = EXCLUDED.qb_customer_id,
            qb_customer_name = EXCLUDED.qb_customer_name,
            txn_date         = EXCLUDED.txn_date,
            total_amt        = EXCLUDED.total_amt,
            raw_payload      = EXCLUDED.raw_payload,
            qb_synced_at     = now(),
            updated_at       = now(),
            is_deleted       = false
        RETURNING id
        """,
        (
            org_id,
            qb_id,
            inv.get("DocNumber"),
            customer.get("value"),
            customer.get("name"),
            inv.get("TxnDate"),
            inv.get("TotalAmt"),
            json.dumps(inv),
        ),
    )
    edi_invoice_uuid = cur.fetchone()[0]

    # Wipe + reinsert lines so removed/edited lines drop out cleanly.
    cur.execute(
        "DELETE FROM edi_qb_invoice_line WHERE qb_invoice_id = %s",
        (edi_invoice_uuid,),
    )

    line_count = 0
    skipped = 0
    for line in inv.get("Line") or []:
        detail = line.get("SalesItemLineDetail")
        # Skip subtotal / tax / discount lines that don't have a sales-item detail block.
        if not detail:
            skipped += 1
            continue
        item = detail.get("ItemRef") or {}
        cur.execute(
            """
            INSERT INTO edi_qb_invoice_line
              (org_id, qb_invoice_id, line_num, qb_item_id, qb_item_name,
               description, qty, amount, service_date, raw_payload)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s::jsonb)
            """,
            (
                org_id,
                edi_invoice_uuid,
                line.get("LineNum"),
                item.get("value"),
                item.get("name"),
                line.get("Description"),
                detail.get("Qty"),
                line.get("Amount"),
                detail.get("ServiceDate"),
                detail.get("ServiceDate"),  # placeholder fixed below
            ),
        )
        line_count += 1
    return 1, line_count, skipped


def upsert_invoices(org_id, invoices):
    """Upsert invoices in batches. Each batch opens its own connection so a
    long HTTP fetch upstream can't leave a Postgres transaction idle past the
    pooler's timeout."""
    inv_count = 0
    line_count = 0
    skipped_no_detail = 0
    total = len(invoices)

    for batch_start in range(0, total, UPSERT_BATCH_SIZE):
        batch = invoices[batch_start : batch_start + UPSERT_BATCH_SIZE]
        with get_pg_conn() as conn:
            with conn.cursor() as cur:
                for inv in batch:
                    qb_id = str(inv.get("Id"))
                    customer = inv.get("CustomerRef") or {}
                    cur.execute(
                        """
                        INSERT INTO edi_qb_invoice
                          (org_id, qb_id, qb_doc_number, qb_customer_id, qb_customer_name,
                           txn_date, total_amt, raw_payload, qb_synced_at)
                        VALUES (%s, %s, %s, %s, %s, %s, %s, %s::jsonb, now())
                        ON CONFLICT (org_id, qb_id) DO UPDATE SET
                            qb_doc_number    = EXCLUDED.qb_doc_number,
                            qb_customer_id   = EXCLUDED.qb_customer_id,
                            qb_customer_name = EXCLUDED.qb_customer_name,
                            txn_date         = EXCLUDED.txn_date,
                            total_amt        = EXCLUDED.total_amt,
                            raw_payload      = EXCLUDED.raw_payload,
                            qb_synced_at     = now(),
                            updated_at       = now(),
                            is_deleted       = false
                        RETURNING id
                        """,
                        (
                            org_id,
                            qb_id,
                            inv.get("DocNumber"),
                            customer.get("value"),
                            customer.get("name"),
                            inv.get("TxnDate"),
                            inv.get("TotalAmt"),
                            json.dumps(inv),
                        ),
                    )
                    edi_invoice_uuid = cur.fetchone()[0]
                    inv_count += 1

                    cur.execute(
                        "DELETE FROM edi_qb_invoice_line WHERE qb_invoice_id = %s",
                        (edi_invoice_uuid,),
                    )
                    for line in inv.get("Line") or []:
                        detail = line.get("SalesItemLineDetail")
                        if not detail:
                            skipped_no_detail += 1
                            continue
                        item = detail.get("ItemRef") or {}
                        cur.execute(
                            """
                            INSERT INTO edi_qb_invoice_line
                              (org_id, qb_invoice_id, line_num, qb_item_id, qb_item_name,
                               description, qty, amount, service_date, raw_payload)
                            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s::jsonb)
                            """,
                            (
                                org_id,
                                edi_invoice_uuid,
                                line.get("LineNum"),
                                item.get("value"),
                                item.get("name"),
                                line.get("Description"),
                                detail.get("Qty"),
                                line.get("Amount"),
                                detail.get("ServiceDate"),
                                json.dumps(line),
                            ),
                        )
                        line_count += 1
            conn.commit()
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
