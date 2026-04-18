"""
Migrate QuickBooks Invoices and Expenses
========================================
Nightly sync from the invoices/expenses spreadsheet into Supabase
`sales_invoice` and `fin_expense`. Reads via gviz CSV (no auth) since the sheet
is already the unauthenticated data source used by the dashboards.

Sources (https://docs.google.com/spreadsheets/d/124y8JdWXmbf_hb1vfimHmGaKLVXrRHybw02w_ozCExE):
  - invoices_23-25     (~18,663 rows, 2023-01 through 2025-12)
  - invoices_2025      (~2,916 rows, misnamed — holds 2026 data)
  - expenses_2019-25   (~16,368 rows, 2019-10 through 2025-12)
  - expense_2026       (2026 rows, note the singular 'expense')

Column drops (all derivable from txn/invoice dates):
  - Year, Month, ISOYear, ISOWeek, DOW on invoices
  - MM, YY on expenses
  Dashboards should read from sales_invoice_v / fin_expense_v to get these back.

Farm mapping on invoices: sheet "Farm" column (Cuke / Lettuce) -> org_farm.id
(cuke / lettuce). Expense sheet has no farm column; farm_id left null.

Usage:
    python migrations/20260417000010_fin_invoice_expense.py

Rerunnable: clears both tables then reinserts everything. Sheet is truth; no
merge logic.
"""

import csv
import io
import re
import sys
import urllib.request
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from supabase import create_client

from _config import AUDIT_USER, ORG_ID, SUPABASE_URL, require_supabase_key
from _pg import get_pg_conn, pg_bulk_insert


SHEET_ID = "124y8JdWXmbf_hb1vfimHmGaKLVXrRHybw02w_ozCExE"

INVOICE_TABS = ["invoices_23-25", "invoices_2025"]
EXPENSE_TABS = ["expenses_2019-25", "expense_2026"]

FARM_MAP = {"cuke": "cuke", "lettuce": "lettuce"}


# ---------------------------------------------------------------------------
# Standard helpers (matching repo conventions)
# ---------------------------------------------------------------------------

def audit(row: dict) -> dict:
    row["created_by"] = AUDIT_USER
    row["updated_by"] = AUDIT_USER
    return row


def fetch_gviz_csv(sheet_id: str, tab: str) -> list[dict]:
    """Fetch one tab as list of dicts via gviz CSV (no auth required)."""
    from urllib.parse import quote
    url = (
        f"https://docs.google.com/spreadsheets/d/{sheet_id}"
        f"/gviz/tq?tqx=out:csv&sheet={quote(tab)}"
    )
    with urllib.request.urlopen(url) as resp:
        raw = resp.read().decode("utf-8")
    return list(csv.DictReader(io.StringIO(raw)))


def parse_date(s):
    if s is None:
        return None
    s = str(s).strip()
    if not s:
        return None
    for fmt in ("%m/%d/%Y", "%m/%d/%y", "%Y-%m-%d"):
        try:
            return datetime.strptime(s, fmt).date()
        except ValueError:
            continue
    return None


def parse_number(s):
    if s is None:
        return None
    s = str(s).strip().replace(",", "")
    if not s:
        return None
    try:
        return float(s)
    except ValueError:
        return None


def parse_bool(s):
    if s is None:
        return False
    return str(s).strip().upper() in ("TRUE", "YES", "1")


def clean(s):
    if s is None:
        return None
    s = str(s).strip()
    return s if s else None


# ---------------------------------------------------------------------------
# Clear
# ---------------------------------------------------------------------------

def clear_existing(supabase):
    print("\nClearing existing rows (sheet is truth, rerunnable)...")
    supabase.table("sales_invoice").delete().neq(
        "id", "00000000-0000-0000-0000-000000000000"
    ).execute()
    print("  Cleared sales_invoice")
    supabase.table("fin_expense").delete().neq(
        "id", "00000000-0000-0000-0000-000000000000"
    ).execute()
    print("  Cleared fin_expense")


# ---------------------------------------------------------------------------
# Invoice sync
# ---------------------------------------------------------------------------

def transform_invoice(r: dict) -> dict | None:
    date = parse_date(r.get("InvoiceDate"))
    if not date:
        return None
    invoice_number = clean(r.get("InvoiceNumber"))
    customer = clean(r.get("CustomerName"))
    if not invoice_number or not customer:
        return None
    farm_raw = (r.get("Farm") or "").strip().lower()
    return audit({
        "org_id":         ORG_ID,
        "farm_id":        FARM_MAP.get(farm_raw),
        "invoice_number": invoice_number,
        "invoice_date":   date.isoformat(),
        "customer_name":  customer,
        "customer_group": clean(r.get("CustomerGroup")),
        "product_code":   clean(r.get("ProductCode")),
        "variety":        clean(r.get("Variety")),
        "grade":          clean(r.get("Grade")),
        "cases":          parse_number(r.get("Cases")),
        "pounds":         parse_number(r.get("Pounds")),
        "dollars":        parse_number(r.get("Dollars")) or 0,
    })


def sync_invoices() -> list[dict]:
    print("\n--- sales_invoice ---")
    rows = []
    for tab in INVOICE_TABS:
        records = fetch_gviz_csv(SHEET_ID, tab)
        kept = 0
        for r in records:
            out = transform_invoice(r)
            if out:
                rows.append(out)
                kept += 1
        print(f"  {tab}: {len(records)} sheet rows -> {kept} kept")
    return rows


# ---------------------------------------------------------------------------
# Expense sync
# ---------------------------------------------------------------------------

def transform_expense(r: dict) -> dict | None:
    date = parse_date(r.get("Txn Date"))
    if not date:
        return None
    is_credit = parse_bool(r.get("Creadit"))
    amount = parse_number(r.get("Line Item.amount"))
    effective = parse_number(r.get("Amt"))
    # If effective is null but we have amount, derive it
    if effective is None and amount is not None:
        effective = -amount if is_credit else amount
    return audit({
        "org_id":           ORG_ID,
        "farm_id":          None,
        "txn_date":         date.isoformat(),
        "payee_name":       clean(r.get("Payee Ref.name")),
        "description":      clean(r.get("Line Item.description")),
        "account_name":     clean(r.get("Line Item.account Name")),
        "account_ref":      clean(r.get("Account Ref.name")),
        "class_name":       clean(r.get("Line Item.class Name")),
        "amount":           amount,
        "is_credit":        is_credit,
        "effective_amount": effective,
        "macro_category":   clean(r.get("Macro")),
    })


def sync_expenses() -> list[dict]:
    print("\n--- fin_expense ---")
    rows = []
    for tab in EXPENSE_TABS:
        records = fetch_gviz_csv(SHEET_ID, tab)
        kept = 0
        for r in records:
            out = transform_expense(r)
            if out:
                rows.append(out)
                kept += 1
        print(f"  {tab}: {len(records)} sheet rows -> {kept} kept")
    return rows


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    supabase = create_client(SUPABASE_URL, require_supabase_key())

    print("=" * 60)
    print("FIN / SALES-INVOICE MIGRATION")
    print("=" * 60)

    clear_existing(supabase)

    invoice_rows = sync_invoices()
    expense_rows = sync_expenses()

    print(f"\nBulk-inserting {len(invoice_rows)} invoices...")
    with get_pg_conn() as conn:
        pg_bulk_insert(conn, "sales_invoice", invoice_rows)
        conn.commit()
    print(f"  Inserted {len(invoice_rows)} sales_invoice rows")

    print(f"\nBulk-inserting {len(expense_rows)} expenses...")
    with get_pg_conn() as conn:
        pg_bulk_insert(conn, "fin_expense", expense_rows)
        conn.commit()
    print(f"  Inserted {len(expense_rows)} fin_expense rows")

    print("\n" + "=" * 60)
    print("DONE")
    print("=" * 60)


if __name__ == "__main__":
    main()
