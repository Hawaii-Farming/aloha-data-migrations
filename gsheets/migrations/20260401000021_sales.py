"""
Migrate Sales Data
===================
Migrates sales_fob, sales_customer_group, and sales_customer from legacy
Google Sheets to Supabase.

Source: https://docs.google.com/spreadsheets/d/1lSWWLxyD0l83HfuiNI_iud6F9hopY4hoL0F_4P9nATc
  - sales_FOB: 6 rows → sales_fob
  - sales_customer: 66 rows → sales_customer_group (unique groups) + sales_customer

Usage:
    python scripts/migrations/20260401000021_sales.py

Rerunnable: clears and reinserts all data on each run.
"""

import os
import re

import gspread
from google.oauth2.service_account import Credentials
from supabase import create_client

SUPABASE_URL = os.environ.get("SUPABASE_URL", "https://kfwqtaazdankxmdlqdak.supabase.co")
SUPABASE_KEY = os.environ.get("SUPABASE_SERVICE_KEY")

if not SUPABASE_KEY:
    try:
        with open(".env") as f:
            for line in f:
                if line.startswith("SUPABASE_SERVICE_KEY="):
                    SUPABASE_KEY = line.strip().split("=", 1)[1]
    except FileNotFoundError:
        pass

AUDIT_USER = "data@hawaiifarming.com"
ORG_ID = "hawaii_farming"

SALES_SHEET_ID = "1lSWWLxyD0l83HfuiNI_iud6F9hopY4hoL0F_4P9nATc"


# ─────────────────────────────────────────────────────────────
# STANDARD HELPERS
# ─────────────────────────────────────────────────────────────

def to_id(name: str) -> str:
    """Convert a display name to a TEXT PK."""
    return re.sub(r"[^a-z0-9_]+", "_", name.lower()).strip("_") if name else ""


def proper_case(val):
    """Normalize a string to title case, stripping extra whitespace."""
    if not val or not str(val).strip():
        return val
    return str(val).strip().title()


def safe_numeric(val, default=0):
    """Parse a numeric value, stripping commas and whitespace."""
    try:
        v = str(val).strip().replace(",", "")
        return float(v) if v else default
    except (ValueError, TypeError):
        return default


def audit(row: dict) -> dict:
    """Add audit fields to a row."""
    row["created_by"] = AUDIT_USER
    row["updated_by"] = AUDIT_USER
    return row


def insert_rows(supabase, table: str, rows: list):
    """Insert rows in batches of 100. Returns inserted data."""
    print(f"\n--- {table} ---")
    all_data = []
    if rows:
        for i in range(0, len(rows), 100):
            batch = rows[i:i + 100]
            result = supabase.table(table).insert(batch).execute()
            all_data.extend(result.data)
        print(f"  Inserted {len(rows)} rows")
    return all_data


def get_sheets():
    """Connect to Google Sheets."""
    scopes = ["https://www.googleapis.com/auth/spreadsheets.readonly"]
    creds = Credentials.from_service_account_file("credentials.json", scopes=scopes)
    return gspread.authorize(creds)


# ─────────────────────────────────────────────────────────────
# SALES FOB
# ─────────────────────────────────────────────────────────────

def migrate_sales_fob(supabase, gc):
    """Migrate sales_FOB tab → sales_fob."""
    wb = gc.open_by_key(SALES_SHEET_ID)
    data = wb.worksheet("sales_FOB").get_all_records()

    print(f"\nProcessing {len(data)} FOB rows...")

    rows = []
    for r in data:
        name = str(r.get("FOB", "")).strip()
        if not name:
            continue
        rows.append(audit({
            "id": to_id(name),
            "org_id": ORG_ID,
            "id": proper_case(name),
        }))

    insert_rows(supabase, "sales_fob", rows)


# ─────────────────────────────────────────────────────────────
# SALES CUSTOMER GROUP + CUSTOMER
# ─────────────────────────────────────────────────────────────

def migrate_sales_customer(supabase, gc):
    """Migrate sales_customer tab → sales_customer_group + sales_customer."""
    wb = gc.open_by_key(SALES_SHEET_ID)
    data = wb.worksheet("sales_customer").get_all_records()

    print(f"\nProcessing {len(data)} customer rows...")

    # --- Extract and insert unique customer groups ---
    groups = sorted(set(
        str(r.get("CustomerGroup", "")).strip()
        for r in data
        if str(r.get("CustomerGroup", "")).strip()
    ))

    group_rows = [
        audit({
            "id": to_id(g),
            "org_id": ORG_ID,
            "id": proper_case(g),
        })
        for g in groups
    ]
    insert_rows(supabase, "sales_customer_group", group_rows)

    # --- Build FOB lookup ---
    fob_result = supabase.table("sales_fob").select("id").eq("org_id", ORG_ID).execute()
    fob_by_name = {f["id"].lower(): f["id"] for f in fob_result.data}

    # --- Insert customers ---
    customer_rows = []
    seen = set()
    for r in data:
        name = str(r.get("CustomerName", "")).strip()
        if not name:
            continue

        cust_id = to_id(name)
        if cust_id in seen:
            continue
        seen.add(cust_id)

        # FOB lookup
        fob_name = str(r.get("FOB", "")).strip()
        fob_id = fob_by_name.get(fob_name.lower()) if fob_name else None

        # Customer group
        group_name = str(r.get("CustomerGroup", "")).strip()
        group_id = to_id(group_name) if group_name else None

        # QB account from CustomerID
        qb_account = str(r.get("CustomerID", "")).strip() or None
        if qb_account == "0":
            qb_account = None

        # Email
        email = str(r.get("CustomerEmails", "")).strip().lower() or None

        # CC emails → JSONB array (split on comma/semicolon)
        cc_raw = str(r.get("CCs", "")).strip()
        cc_emails = []
        if cc_raw:
            for e in re.split(r"[,;]\s*", cc_raw):
                e = e.strip().lower()
                if e:
                    cc_emails.append(e)

        customer_rows.append(audit({
            "id": cust_id,
            "org_id": ORG_ID,
            "sales_customer_group_id": group_id,
            "sales_fob_id": fob_id,
            "qb_account": qb_account,
            "id": proper_case(name),
            "email": email,
            "cc_emails": cc_emails,
        }))

    insert_rows(supabase, "sales_customer", customer_rows)


# ─────────────────────────────────────────────────────────────
# SALES CONTAINER TYPE
# ─────────────────────────────────────────────────────────────

def migrate_sales_container_type(supabase, gc):
    """Migrate sales_Vehicles tab → sales_container_type."""
    wb = gc.open_by_key(SALES_SHEET_ID)
    data = wb.worksheet("sales_Vehicles").get_all_records()

    print(f"\nProcessing {len(data)} vehicle rows...")

    rows = []
    for r in data:
        name = str(r.get("Vehicle", "")).strip()
        spaces = int(str(r.get("PalletSpaces", "0")).strip() or 0)
        if not name:
            continue

        rows.append(audit({
            "id": to_id(name),
            "org_id": ORG_ID,
            "id": proper_case(name),
            "maximum_spaces": spaces,
        }))

    insert_rows(supabase, "sales_container_type", rows)


# ─────────────────────────────────────────────────────────────
# SALES PRODUCT PRICE
# ─────────────────────────────────────────────────────────────

def migrate_sales_product_price(supabase, gc):
    """Migrate sales_product_prices tab → sales_product_price.

    SpecialPricing resolution:
      - "Default" → sales_customer_group_id = null, sales_customer_id = null
      - Check sales_customer_group first → sales_customer_group_id
      - Fall back to sales_customer → sales_customer_id
    """
    wb = gc.open_by_key(SALES_SHEET_ID)
    data = wb.worksheet("sales_product_prices").get_all_records()

    print(f"\nProcessing {len(data)} product price rows...")

    # Build lookups
    fob_result = supabase.table("sales_fob").select("id").eq("org_id", ORG_ID).execute()
    fob_by_name = {f["id"].lower(): f["id"] for f in fob_result.data}

    group_result = supabase.table("sales_customer_group").select("id").eq("org_id", ORG_ID).execute()
    group_by_name = {g["id"].lower(): g["id"] for g in group_result.data}

    cust_result = supabase.table("sales_customer").select("id").eq("org_id", ORG_ID).execute()
    cust_by_name = {c["id"].lower(): c["id"] for c in cust_result.data}

    rows = []
    skipped = 0
    for r in data:
        product_code = str(r.get("ProductCode", "")).strip()
        if not product_code:
            skipped += 1
            continue

        price = safe_numeric(r.get("PricePerCase"), default=None)
        if price is None or price == 0:
            skipped += 1
            continue

        farm_id = str(r.get("Farm", "")).strip()
        farm_id = to_id(farm_id)
        sales_product_id = product_code

        # FOB
        fob_name = str(r.get("FOB", "")).strip()
        fob_id = fob_by_name.get(fob_name.lower())
        if not fob_id:
            skipped += 1
            continue

        # SpecialPricing → customer group or customer
        special = str(r.get("SpecialPricing", "")).strip()
        group_id = None
        cust_id = None

        if special and special != "Default":
            # Try customer group first
            group_id = group_by_name.get(special.lower())
            if not group_id:
                # Fall back to customer
                cust_id = cust_by_name.get(special.lower())
                if not cust_id:
                    print(f"  WARN: Unknown SpecialPricing '{special}' for {product_code}/{fob_name}")

        row = {
            "org_id": ORG_ID,
            "farm_id": farm_id,
            "sales_product_id": sales_product_id,
            "sales_fob_id": fob_id,
            "price_per_case": price,
            "effective_from": "2024-01-01",
        }
        if group_id:
            row["sales_customer_group_id"] = group_id
        if cust_id:
            row["sales_customer_id"] = cust_id

        rows.append(audit(row))

    insert_rows(supabase, "sales_product_price", rows)
    if skipped:
        print(f"  Skipped {skipped} rows (missing product, zero price, or unknown FOB)")


# ─────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────

def main():
    supabase = create_client(SUPABASE_URL, SUPABASE_KEY)
    gc = get_sheets()

    print("=" * 60)
    print("SALES MIGRATION")
    print("=" * 60)

    # Clear in FK order
    print("\nClearing sales tables...")
    supabase.table("sales_product_price").delete().neq("id", "00000000-0000-0000-0000-000000000000").execute()
    supabase.table("sales_customer").delete().neq("id", "__none__").execute()
    supabase.table("sales_customer_group").delete().neq("id", "__none__").execute()
    supabase.table("sales_fob").delete().neq("id", "__none__").execute()
    supabase.table("sales_container_type").delete().neq("id", "__none__").execute()
    print("  Cleared")

    # Step 1: FOB lookup
    migrate_sales_fob(supabase, gc)

    # Step 2: Customer groups + customers
    migrate_sales_customer(supabase, gc)

    # Step 3: Container types
    migrate_sales_container_type(supabase, gc)

    # Step 4: Product prices
    migrate_sales_product_price(supabase, gc)

    print("\n" + "=" * 60)
    print("DONE")
    print("=" * 60)


if __name__ == "__main__":
    main()
