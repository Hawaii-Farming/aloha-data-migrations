"""
Migrate Sales CRM Data
========================
Migrates store visits, store visit photos, store visit product observations,
and competitor products from legacy Google Sheets.

Source: https://docs.google.com/spreadsheets/d/1lSWWLxyD0l83HfuiNI_iud6F9hopY4hoL0F_4P9nATc
  - sales_CRM_stores: 114 rows → sales_crm_store
  - sales_CRM_store_visits: 568 rows → sales_crm_store_visit + sales_crm_store_visit_photo
  - sales_CRM_store_visit_prices: 356 rows → sales_crm_store_visit_result (unpivoted)

Usage:
    python scripts/migrations/20260401000022_sales_crm.py

Rerunnable: clears and reinserts all data on each run.
"""

import os
import re
from datetime import datetime

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

# Own product columns in the wide price sheet → sales_product_id
OWN_PRODUCT_COLS = {
    "KR": "kr", "JR": "jr", "LR": "lr", "AR": "ar", "WR": "wr",
    "LR14": "lr",  # 14oz variant → same product
    "KW": "kw", "JW": "jw", "LW": "lw",
}

# Competitor product columns → external product name
EXTERNAL_PRODUCT_COLS = {
    "Sensei": "Sensei 4oz",
    "Sensei8": "Sensei 8oz",
    "Nalo": "Nalo",
    "Mainland5": "Mainland 5oz",
    "Mainland16": "Mainland 16oz",
}


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


def parse_date(date_str):
    """Parse date string to YYYY-MM-DD or None."""
    if not date_str or not str(date_str).strip():
        return None
    for fmt in ("%m/%d/%Y", "%m/%d/%y", "%Y-%m-%d"):
        try:
            return datetime.strptime(str(date_str).strip(), fmt).strftime("%Y-%m-%d")
        except ValueError:
            continue
    return None


def safe_numeric(val, default=None):
    """Parse a numeric value, stripping commas, whitespace, and $."""
    try:
        v = str(val).strip().replace(",", "").replace("$", "")
        return float(v) if v else default
    except (ValueError, TypeError):
        return default


def get_sheets():
    """Connect to Google Sheets."""
    scopes = ["https://www.googleapis.com/auth/spreadsheets.readonly"]
    creds = Credentials.from_service_account_file("credentials.json", scopes=scopes)
    return gspread.authorize(creds)


# ─────────────────────────────────────────────────────────────
# EXTERNAL PRODUCTS
# ─────────────────────────────────────────────────────────────

def migrate_external_products(supabase):
    """Seed competitor products from the known set."""
    products = sorted(set(EXTERNAL_PRODUCT_COLS.values()))

    rows = [
        audit({
            "id": to_id(name),
            "org_id": ORG_ID,
            "name": name,
        })
        for name in products
    ]
    insert_rows(supabase, "sales_crm_external_product", rows)


# ─────────────────────────────────────────────────────────────
# STORES
# ─────────────────────────────────────────────────────────────

def migrate_stores(supabase, gc):
    """Migrate sales_CRM_stores → sales_crm_store."""
    wb = gc.open_by_key(SALES_SHEET_ID)
    data = wb.worksheet("sales_CRM_stores").get_all_records()

    print(f"\nProcessing {len(data)} store rows...")

    # Build customer lookup
    cust_result = supabase.table("sales_customer").select("id, name").eq("org_id", ORG_ID).execute()
    cust_by_name = {c["name"].lower(): c["id"] for c in cust_result.data}

    rows = []
    seen = set()
    for r in data:
        store_name = str(r.get("StoreName", "")).strip()
        if not store_name:
            continue

        store_id = to_id(store_name)
        if store_id in seen:
            continue
        seen.add(store_id)

        cust_name = str(r.get("CustomerName", "")).strip()
        cust_id = cust_by_name.get(cust_name.lower()) if cust_name else None

        rows.append(audit({
            "id": store_id,
            "org_id": ORG_ID,
            "sales_customer_id": cust_id,
            "chain": str(r.get("Chain", "")).strip() or None,
            "name": store_name,
            "location": str(r.get("Location", "")).strip() or None,
            "island": str(r.get("Island", "")).strip() or None,
            "contact_name": str(r.get("ContactName", "")).strip() or None,
            "contact_title": str(r.get("Title", "")).strip() or None,
            "contact_email": str(r.get("Email", "")).strip().lower() or None,
            "contact_phone": str(r.get("PhoneNumber", "")).strip() or None,
        }))

    insert_rows(supabase, "sales_crm_store", rows)


# ─────────────────────────────────────────────────────────────
# STORE VISITS + PHOTOS
# ─────────────────────────────────────────────────────────────

def migrate_visits(supabase, gc):
    """Migrate sales_CRM_store_visits → sales_crm_store_visit + sales_crm_store_visit_photo."""
    wb = gc.open_by_key(SALES_SHEET_ID)
    data = wb.worksheet("sales_CRM_store_visits").get_all_records()

    print(f"\nProcessing {len(data)} visit rows...")

    # Build store lookup
    store_result = supabase.table("sales_crm_store").select("id, name").eq("org_id", ORG_ID).execute()
    store_by_name = {s["name"].lower(): s["id"] for s in store_result.data}

    # Build employee lookup for visited_by
    emp_result = supabase.table("hr_employee").select("id, company_email").execute()
    emp_by_email = {e["company_email"]: e["id"] for e in emp_result.data if e.get("company_email")}

    visit_rows = []
    visit_meta = []  # parallel: (store_name, row) for photo pass
    skipped = 0

    for r in data:
        store_name = str(r.get("StoreName", "")).strip()
        store_id = store_by_name.get(store_name.lower()) if store_name else None
        if not store_id:
            skipped += 1
            continue

        visit_date = parse_date(r.get("VisitDate"))
        if not visit_date:
            skipped += 1
            continue

        reported_by = str(r.get("ReportedBy", "")).strip().lower() or AUDIT_USER
        visited_by = emp_by_email.get(reported_by)

        # Combine Notes and CustomerNotes
        notes = str(r.get("Notes", "")).strip()
        cust_notes = str(r.get("CustomerNotes", "")).strip()
        if cust_notes:
            notes = f"{notes}\n\nCustomer: {cust_notes}" if notes else f"Customer: {cust_notes}"
        notes = notes or None

        visit_rows.append({
            "org_id": ORG_ID,
            "sales_crm_store_id": store_id,
            "visit_date": visit_date,
            "notes": notes,
            "visited_by": visited_by,
            "created_by": reported_by,
            "updated_by": reported_by,
        })
        visit_meta.append(r)

    inserted_visits = insert_rows(supabase, "sales_crm_store_visit", visit_rows)

    # --- Photos ---
    photo_rows = []
    for idx, r in enumerate(visit_meta):
        visit_uuid = inserted_visits[idx]["id"]
        reported_by = str(r.get("ReportedBy", "")).strip().lower() or AUDIT_USER

        for col in ["Photo01", "Photo02", "Photo03"]:
            url = str(r.get(col, "")).strip()
            if url:
                photo_rows.append({
                    "org_id": ORG_ID,
                    "sales_crm_store_visit_id": visit_uuid,
                    "photo_url": url,
                    "created_by": reported_by,
                    "updated_by": reported_by,
                })

    insert_rows(supabase, "sales_crm_store_visit_photo", photo_rows)

    if skipped:
        print(f"  Skipped {skipped} visits (unknown store or missing date)")

    return inserted_visits


# ─────────────────────────────────────────────────────────────
# STORE VISIT RESULTS (unpivoted from wide price columns)
# ─────────────────────────────────────────────────────────────

def migrate_visit_results(supabase, gc):
    """Migrate sales_CRM_store_visit_prices → sales_crm_store_visit_result.

    Wide product columns are unpivoted into individual rows.
    Each product has up to 4 fields: PricePerTray, BestByDate, StockLevel, CasesPerWeek.
    """
    wb = gc.open_by_key(SALES_SHEET_ID)
    data = wb.worksheet("sales_CRM_store_visit_prices").get_all_records()

    print(f"\nProcessing {len(data)} price observation rows...")

    # Build store lookup
    store_result = supabase.table("sales_crm_store").select("id, name").eq("org_id", ORG_ID).execute()
    store_by_name = {s["name"].lower(): s["id"] for s in store_result.data}

    # Build external product lookup
    ext_result = supabase.table("sales_crm_external_product").select("id, name").execute()
    ext_by_name = {e["name"].lower(): e["id"] for e in ext_result.data}

    # Build visit lookup by (store_id, visit_date)
    visit_result = supabase.table("sales_crm_store_visit").select("id, sales_crm_store_id, visit_date").execute()
    visit_by_store_date = {}
    for v in visit_result.data:
        visit_by_store_date[(v["sales_crm_store_id"], v["visit_date"])] = v["id"]

    # Stock level normalization
    stock_map = {
        "zero": "zero", "low": "low", "medium": "medium", "full": "full",
        "med": "medium", "none": "zero",
    }

    rows = []
    skipped = 0

    for r in data:
        store_name = str(r.get("StoreName", "")).strip()
        store_id = store_by_name.get(store_name.lower()) if store_name else None
        visit_date = parse_date(r.get("VisitDate"))
        if not store_id or not visit_date:
            skipped += 1
            continue

        visit_id = visit_by_store_date.get((store_id, visit_date))
        if not visit_id:
            skipped += 1
            continue

        reported_by = str(r.get("ReportedBy", "")).strip().lower() or AUDIT_USER

        # Own products
        for col_prefix, product_id in OWN_PRODUCT_COLS.items():
            price = safe_numeric(r.get(f"{col_prefix}PricePerTray"))
            best_by = parse_date(r.get(f"{col_prefix}BestByDate"))
            stock_raw = str(r.get(f"{col_prefix}StockLevel", "")).strip().lower()
            stock = stock_map.get(stock_raw)
            cases = safe_numeric(r.get(f"{col_prefix}CasesPerWeek"))

            if price is None and best_by is None and stock is None and cases is None:
                continue

            rows.append({
                "org_id": ORG_ID,
                "sales_crm_store_visit_id": visit_id,
                "sales_product_id": product_id,
                "shelf_price": price,
                "best_by_date": best_by,
                "stock_level": stock,
                "cases_per_week": cases,
                "created_by": reported_by,
                "updated_by": reported_by,
            })

        # External/competitor products
        for col_prefix, ext_name in EXTERNAL_PRODUCT_COLS.items():
            price = safe_numeric(r.get(f"{col_prefix}PricePerTray"))
            best_by = parse_date(r.get(f"{col_prefix}BestByDate"))
            stock_raw = str(r.get(f"{col_prefix}StockLevel", "")).strip().lower()
            stock = stock_map.get(stock_raw)
            cases = safe_numeric(r.get(f"{col_prefix}CasesPerWeek"))

            if price is None and best_by is None and stock is None and cases is None:
                continue

            ext_id = ext_by_name.get(ext_name.lower())
            if not ext_id:
                continue

            rows.append({
                "org_id": ORG_ID,
                "sales_crm_store_visit_id": visit_id,
                "sales_crm_external_product_id": ext_id,
                "shelf_price": price,
                "best_by_date": best_by,
                "stock_level": stock,
                "cases_per_week": cases,
                "created_by": reported_by,
                "updated_by": reported_by,
            })

    insert_rows(supabase, "sales_crm_store_visit_result", rows)
    if skipped:
        print(f"  Skipped {skipped} rows (unknown store, missing date, or no matching visit)")


# ─────────────────────────────────────────────────────────────
# MAIN
# ────────────��────────────────────────────────────────────────

def main():
    supabase = create_client(SUPABASE_URL, SUPABASE_KEY)
    gc = get_sheets()

    print("=" * 60)
    print("SALES CRM MIGRATION")
    print("=" * 60)

    # Clear in FK order
    print("\nClearing CRM tables...")
    supabase.table("sales_crm_store_visit_result").delete().neq("id", "00000000-0000-0000-0000-000000000000").execute()
    supabase.table("sales_crm_store_visit_photo").delete().neq("id", "00000000-0000-0000-0000-000000000000").execute()
    supabase.table("sales_crm_store_visit").delete().neq("id", "00000000-0000-0000-0000-000000000000").execute()
    supabase.table("sales_crm_store").delete().neq("id", "__none__").execute()
    supabase.table("sales_crm_external_product").delete().neq("id", "__none__").execute()
    print("  Cleared")

    # Step 1: External products
    migrate_external_products(supabase)

    # Step 2: Stores
    migrate_stores(supabase, gc)

    # Step 3: Visits + photos
    migrate_visits(supabase, gc)

    # Step 4: Visit results (price observations)
    migrate_visit_results(supabase, gc)

    print("\n" + "=" * 60)
    print("DONE")
    print("=" * 60)


if __name__ == "__main__":
    main()
