"""
Migrate Sales PO Data
======================
Migrates sales_po (header), sales_po_line (products), and sales_po_fulfillment
(pack date/quantity/lot unpivoted from wide columns) from legacy Google Sheets.

Source: https://docs.google.com/spreadsheets/d/1lSWWLxyD0l83HfuiNI_iud6F9hopY4hoL0F_4P9nATc
  - sales_po: 24133 rows → sales_po + sales_po_line + sales_po_fulfillment

Auto-creates missing customers/products as inactive.

Usage:
    python scripts/migrations/20260401000023_sales_po.py

Rerunnable: clears and reinserts all data on each run.
"""

import os
import re
from collections import defaultdict
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


def safe_numeric(val, default=0):
    """Parse a numeric value, stripping commas and whitespace."""
    try:
        v = str(val).strip().replace(",", "")
        return float(v) if v else default
    except (ValueError, TypeError):
        return default


def get_sheets():
    """Connect to Google Sheets."""
    scopes = ["https://www.googleapis.com/auth/spreadsheets.readonly"]
    creds = Credentials.from_service_account_file("credentials.json", scopes=scopes)
    return gspread.authorize(creds)


# ─────────────────────────────────────────────────────────────
# AUTO-CREATE MISSING ENTITIES
# ─────────────────────────────────────────────────────────────

def ensure_missing_customers(supabase, data):
    """Auto-create customers that exist in PO data but not in sales_customer. Marked inactive."""
    cust_result = supabase.table("sales_customer").select("id").eq("org_id", ORG_ID).execute()
    existing = {c["id"].lower(): c["id"] for c in cust_result.data}

    sheet_custs = set()
    for r in data:
        name = str(r.get("CustomerName", "")).strip()
        if name:
            sheet_custs.add(name)

    missing = [c for c in sheet_custs if c.lower() not in existing]
    if not missing:
        print("  No missing customers")
        return

    rows = []
    for name in sorted(missing):
        rows.append(audit({
            "id": to_id(name),
            "org_id": ORG_ID,
            "id": proper_case(name),
            "is_active": False,
            "cc_emails": [],
        }))

    insert_rows(supabase, "sales_customer", rows)
    print(f"  Auto-created {len(rows)} inactive customers: {sorted(missing)}")


def ensure_missing_products(supabase, data):
    """Auto-create products that exist in PO data but not in sales_product. Marked inactive."""
    prod_result = supabase.table("sales_product").select("id").execute()
    existing = {p["id"] for p in prod_result.data}

    sheet_prods = set()
    for r in data:
        code = str(r.get("ProductCode", "")).strip()
        farm = str(r.get("Farm", "")).strip()
        if code:
            sheet_prods.add((code, farm))

    missing = [(code, farm) for code, farm in sheet_prods if code not in existing]
    if not missing:
        print("  No missing products")
        return

    rows = []
    for code, farm in sorted(missing):
        rows.append(audit({
            "org_id": ORG_ID,
            "farm_id": to_id(farm),
            "id": code,
            "name": proper_case(code),
            "is_active": False,
            "photos": [],
        }))

    insert_rows(supabase, "sales_product", rows)
    print(f"  Auto-created {len(rows)} inactive products: {[c for c, _ in sorted(missing)]}")


# ─────────────────────────────────────────────────────────────
# SALES PO MIGRATION
# ─────────────────────────────────────────────────────────────

def migrate_sales_po(supabase, gc):
    """Migrate sales_po tab → sales_po + sales_po_line + sales_po_fulfillment.

    Legacy data is one row per product per PO. Multiple rows with the same
    (PurchaseOrderDate, CustomerName, PurchaseOrderNumber) form one PO header.

    Wide columns PackDate01-06, Quantity01-06, PackLot01-06 are unpivoted
    into sales_po_fulfillment rows.
    """
    wb = gc.open_by_key(SALES_SHEET_ID)
    data = wb.worksheet("sales_po").get_all_records()

    print(f"\nProcessing {len(data)} PO rows...")

    # --- Ensure missing entities ---
    print("\nChecking for missing customers/products...")
    ensure_missing_customers(supabase, data)
    ensure_missing_products(supabase, data)

    # --- Build lookups ---
    cust_result = supabase.table("sales_customer").select("id").eq("org_id", ORG_ID).execute()
    cust_by_name = {c["id"].lower(): c["id"] for c in cust_result.data}

    group_result = supabase.table("sales_customer_group").select("id").eq("org_id", ORG_ID).execute()
    group_by_name = {g["id"].lower(): g["id"] for g in group_result.data}

    fob_result = supabase.table("sales_fob").select("id").eq("org_id", ORG_ID).execute()
    fob_by_name = {f["id"].lower(): f["id"] for f in fob_result.data}

    # Employee lookup for workflow fields (approved_by, qb_uploaded_by)
    emp_result = supabase.table("hr_employee").select("id, company_email").execute()
    emp_by_email = {e["company_email"]: e["id"] for e in emp_result.data if e.get("company_email")}

    # Pack lot lookup by (farm_id, pack_date) and by lot_number
    lot_result = supabase.table("pack_lot").select("id, farm_id, pack_date, lot_number").execute()
    lot_by_date_farm = {}
    lot_by_number = {}
    for l in lot_result.data:
        lot_by_date_farm[(l["farm_id"], l["pack_date"])] = l["id"]
        lot_by_number[l["lot_number"]] = l["id"]

    # --- Identify recurring future orders and filter ---
    # Future = order_date > 2026-04-02 (today)
    TODAY = "2026-04-02"

    # Group future rows by (customer, product) to detect recurring patterns
    future_by_cust_prod = defaultdict(list)  # (cust, prod) → [(order_date, row)]
    for r in data:
        order_date = parse_date(r.get("PurchaseOrderDate"))
        if not order_date or order_date <= TODAY:
            continue
        cust = str(r.get("CustomerName", "")).strip()
        prod = str(r.get("ProductCode", "")).strip()
        future_by_cust_prod[(cust, prod)].append((order_date, r))

    # Detect frequency and find PO keys to keep (most recent per combo)
    recurring_po_keys = {}  # po_key → frequency
    skip_future_keys = set()  # po_keys to exclude

    for (cust, prod), orders in future_by_cust_prod.items():
        if len(orders) < 3:
            continue
        orders.sort(key=lambda x: x[0])
        intervals = [(datetime.strptime(orders[i][0], "%Y-%m-%d") -
                       datetime.strptime(orders[i-1][0], "%Y-%m-%d")).days
                      for i in range(1, len(orders))]
        avg = sum(intervals) / len(intervals)

        if 5 <= avg <= 9:
            freq = "weekly"
        elif 12 <= avg <= 16:
            freq = "biweekly"
        elif 25 <= avg <= 35:
            freq = "monthly"
        else:
            continue  # irregular, don't set recurring

        # Keep only the most recent order, skip the rest
        most_recent_date = orders[-1][0]
        most_recent_row = orders[-1][1]
        po_number = str(most_recent_row.get("PurchaseOrderNumber", "")).strip()
        keep_key = (most_recent_date, cust, po_number)
        recurring_po_keys[keep_key] = freq

        # Mark all other future POs for this combo as skippable
        for order_date, row in orders[:-1]:
            po_num = str(row.get("PurchaseOrderNumber", "")).strip()
            skip_future_keys.add((order_date, cust, po_num))

    print(f"  Recurring combos detected: {len(future_by_cust_prod)} customer+product pairs")
    print(f"  Keeping {len(recurring_po_keys)} most-recent recurring POs, skipping {len(skip_future_keys)} future duplicates")

    # --- Group rows into PO headers (excluding skipped future orders) ---
    # Key: (order_date, customer_name, po_number)
    po_groups = defaultdict(list)
    skipped_future = 0
    for r in data:
        order_date = parse_date(r.get("PurchaseOrderDate"))
        cust_name = str(r.get("CustomerName", "")).strip()
        po_number = str(r.get("PurchaseOrderNumber", "")).strip()
        if not order_date or not cust_name:
            continue
        key = (order_date, cust_name, po_number)
        if key in skip_future_keys:
            skipped_future += 1
            continue
        po_groups[key].append(r)

    print(f"  {len(po_groups)} PO headers after filtering ({skipped_future} future rows skipped)")

    # --- Build PO header rows ---
    po_header_rows = []
    po_key_to_idx = {}  # key → index in po_header_rows

    for key in sorted(po_groups.keys()):
        order_date, cust_name, po_number = key
        lines = po_groups[key]
        first = lines[0]

        cust_id = cust_by_name.get(cust_name.lower())
        if not cust_id:
            continue

        # Customer group and FOB from first line
        group_name = str(first.get("CustomerGroup", "")).strip()
        group_id = group_by_name.get(group_name.lower()) if group_name else None

        fob_name = str(first.get("FOB", "")).strip()
        fob_id = fob_by_name.get(fob_name.lower()) if fob_name and fob_name != "#N/A" else None

        invoice_date = parse_date(first.get("InvoiceDate"))
        reported_by = str(first.get("RecordedBy", "")).strip().lower() or AUDIT_USER

        # Workflow: approved_by from RecordedBy, qb_uploaded_by from UploadedBy
        approved_by = emp_by_email.get(reported_by)
        uploaded_by_email = str(first.get("UploadedBy", "")).strip().lower()
        qb_uploaded_by = emp_by_email.get(uploaded_by_email) if uploaded_by_email else None

        # Determine status: check if any line has invoice quantity or wide quantities
        has_fulfillment = False
        all_zero = True
        for line in lines:
            inv_qty = safe_numeric(line.get("InvoiceQuantity"), default=None)
            if inv_qty is not None and inv_qty > 0:
                has_fulfillment = True
                all_zero = False
                break
            for i in range(1, 7):
                qty = safe_numeric(line.get(f"Quantity0{i}"), default=None)
                if qty is not None and qty > 0:
                    has_fulfillment = True
                    all_zero = False
                    break
            if has_fulfillment:
                break

        if has_fulfillment:
            status = "Fulfilled"
        elif invoice_date and all_zero:
            status = "Unfulfilled"
        else:
            status = "Approved"

        # Recurring frequency (only set on most-recent future POs)
        recurring = recurring_po_keys.get(key)

        po_key_to_idx[key] = len(po_header_rows)
        # created_at = order_date, updated_at = invoice_date (or order_date for future orders)
        created_at = f"{order_date}T00:00:00"
        updated_at = f"{invoice_date}T00:00:00" if invoice_date and order_date <= TODAY else created_at

        row = {
            "org_id": ORG_ID,
            "sales_customer_group_id": group_id,
            "sales_customer_id": cust_id,
            "sales_fob_id": fob_id,
            "po_number": po_number or None,
            "order_date": order_date,
            "invoice_date": invoice_date,
            "status": status,
            "approved_at": created_at,
            "approved_by": approved_by,
            "created_at": created_at,
            "created_by": reported_by,
            "updated_at": updated_at,
            "updated_by": reported_by,
        }
        if recurring:
            row["recurring_frequency"] = recurring
        if qb_uploaded_by and invoice_date:
            row["qb_uploaded_at"] = f"{invoice_date}T00:00:00"
            row["qb_uploaded_by"] = qb_uploaded_by
        po_header_rows.append(row)

    # Insert PO headers
    inserted_pos = insert_rows(supabase, "sales_po", po_header_rows)

    # --- Build PO line rows (deduplicate by PO + product, sum quantities) ---
    po_line_rows = []
    # line_key → (line_idx, [source_rows]) for fulfillment pass
    line_key_map = {}  # (po_key, product_id) → index in po_line_rows
    line_source_rows = []  # parallel: list of (source_rows, farm_id) per line

    for key in sorted(po_groups.keys()):
        if key not in po_key_to_idx:
            continue
        po_idx = po_key_to_idx[key]
        po_uuid = inserted_pos[po_idx]["id"]

        for r in po_groups[key]:
            product_code = str(r.get("ProductCode", "")).strip()
            if not product_code:
                continue

            farm_id = str(r.get("Farm", "")).strip()
            farm_id = to_id(farm_id)
            order_qty = safe_numeric(r.get("PurchaseOrderQuantity"))
            price = safe_numeric(r.get("PricePerCase"))
            reported_by = str(r.get("RecordedBy", "")).strip().lower() or AUDIT_USER

            line_key = (key, product_code.lower())
            if line_key in line_key_map:
                # Merge: sum order_quantity, keep all source rows for fulfillment
                idx = line_key_map[line_key]
                po_line_rows[idx]["order_quantity"] += order_qty
                line_source_rows[idx][0].append(r)
            else:
                line_key_map[line_key] = len(po_line_rows)
                po_line_rows.append({
                    "org_id": ORG_ID,
                    "farm_id": farm_id,
                    "sales_po_id": po_uuid,
                    "sales_product_id": product_code,
                    "order_quantity": order_qty,
                    "price_per_case": price,
                    "created_by": reported_by,
                    "updated_by": reported_by,
                })
                line_source_rows.append(([r], farm_id))

    # Insert PO lines
    inserted_lines = insert_rows(supabase, "sales_po_line", po_line_rows)

    # --- Build fulfillment rows ---
    fulfillment_rows = []

    for idx, (source_rows, farm_id) in enumerate(line_source_rows):
        line_uuid = inserted_lines[idx]["id"]
        po_uuid = po_line_rows[idx]["sales_po_id"]

        for r in source_rows:
            reported_by = str(r.get("RecordedBy", "")).strip().lower() or AUDIT_USER

            # Unpivot wide columns: PackDate01-06, Quantity01-06, PackLot01-06
            has_wide_qty = False
            for i in range(1, 7):
                qty = safe_numeric(r.get(f"Quantity0{i}"), default=None)
                if qty is None or qty <= 0:
                    continue

                has_wide_qty = True
                pack_date = parse_date(r.get(f"PackDate0{i}"))
                lot_code = str(r.get(f"PackLot0{i}", "")).strip()

                # Resolve pack_lot_id: try lot_number first, then date+farm
                pack_lot_id = None
                if lot_code:
                    pack_lot_id = lot_by_number.get(lot_code)
                if not pack_lot_id and pack_date:
                    pack_lot_id = lot_by_date_farm.get((farm_id, pack_date))

                fulfillment_rows.append({
                    "org_id": ORG_ID,
                    "farm_id": farm_id,
                    "sales_po_id": po_uuid,
                    "sales_po_line_id": line_uuid,
                    "pack_lot_id": pack_lot_id,
                    "fulfilled_quantity": qty,
                    "created_by": reported_by,
                    "updated_by": reported_by,
                })

            # If no wide quantities but invoice quantity is 0 → unfulfilled record
            if not has_wide_qty:
                inv_qty = safe_numeric(r.get("InvoiceQuantity"), default=None)
                if inv_qty is not None and inv_qty == 0:
                    fulfillment_rows.append({
                        "org_id": ORG_ID,
                        "farm_id": farm_id,
                        "sales_po_id": po_uuid,
                        "sales_po_line_id": line_uuid,
                        "fulfilled_quantity": 0,
                        "created_by": reported_by,
                        "updated_by": reported_by,
                    })

    insert_rows(supabase, "sales_po_fulfillment", fulfillment_rows)


# ─────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────

def main():
    supabase = create_client(SUPABASE_URL, SUPABASE_KEY)
    gc = get_sheets()

    print("=" * 60)
    print("SALES PO MIGRATION")
    print("=" * 60)

    # Clear in FK order
    print("\nClearing PO tables...")
    supabase.table("sales_po_fulfillment").delete().neq("id", "00000000-0000-0000-0000-000000000000").execute()
    supabase.table("sales_po_line").delete().neq("id", "00000000-0000-0000-0000-000000000000").execute()
    supabase.table("sales_po").delete().neq("id", "00000000-0000-0000-0000-000000000000").execute()
    print("  Cleared")

    migrate_sales_po(supabase, gc)

    print("\n" + "=" * 60)
    print("DONE")
    print("=" * 60)


if __name__ == "__main__":
    main()
