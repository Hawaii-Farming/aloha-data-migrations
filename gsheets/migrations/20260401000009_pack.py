"""
Migrate Pack Data
==================
Migrates sales_product (from sales sheet) and pack_lot / pack_lot_item
(from pack sheet) into Supabase.

Sources:
  - sales_product: https://docs.google.com/spreadsheets/d/1lSWWLxyD0l83HfuiNI_iud6F9hopY4hoL0F_4P9nATc
      - sales_product (tab gid=0): base product info (code, name, farm, lbs/case)
      - sales_product_specs (tab gid=2028451791): shelf life, UPC, images, description fields
      - sales_product_measurements (tab gid=2087257901): packaging hierarchy (item_uom, pack_uom, etc.)
      - sales_sysco_product_specs (tab gid=1855835306): case dims, temps, GTIN, TI/HI, flags
  - pack_lot + pack_lot_item:
      - Lettuce: https://docs.google.com/spreadsheets/d/1XEwjbU_NKNmoUED4w5iuaGV_ilovCJg4f2AkA9lB2cg
          - pack_L_packlot: 451 rows → pack_lot (lettuce) + pack_lot_item per product column
      - Cuke: same spreadsheet
          - pack_C_prod: 10394 rows → pack_lot (cuke) summed by date + pack_lot_item per product column

Usage:
    python scripts/migrations/20260401000009_pack.py

Rerunnable: clears and reinserts all data on each run.
"""

import os
import re
from collections import defaultdict
from datetime import datetime, timedelta

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
PACK_SHEET_ID = "1XEwjbU_NKNmoUED4w5iuaGV_ilovCJg4f2AkA9lB2cg"

# Lettuce product columns → sales_product.id
LETTUCE_PRODUCT_COLS = {
    "LRCases": "lr",
    "LWCases": "lw",
    "WRCases": "wr",
    "ARCases": "ar",
    "LFCases": "lf",
    "AFCases": "af",
}

# Cuke product columns → sales_product.id
CUKE_PRODUCT_COLS = {
    "KWCases": "kw",
    "KRCases": "kr",
    "KFCases": "kf",
    "OKCases": "ok",
    "JWCases": "jw",
    "JRCases": "jr",
    "JFCases": "jf",
    "OJCases": "oj",
    "EWCases": "ew",
    "ERCases": "er",
    "OECases": "oe",
}

# UOM mapping from sheet values → sys_uom codes
UOM_MAP = {
    "pound": "pound", "pounds": "pound", "us pounds": "pound", "lb": "pound",
    "ounce": "ounce", "oz": "ounce",
    "count": "count", "each": "each",
    "bag": "bag", "pack": "pack", "tray": "tray", "case": "case",
    "inch": "inch", "inches": "inch", "in": "inch",
    "fahrenheit": "fahrenheit", "f": "fahrenheit",
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


def parse_bool(val):
    """Parse a boolean value from sheet text."""
    return str(val).strip().upper() in ("TRUE", "YES", "1")


def safe_numeric(val, default=0):
    """Parse a numeric value, stripping commas and whitespace."""
    try:
        v = str(val).strip().replace(",", "")
        return float(v) if v else default
    except (ValueError, TypeError):
        return default


def safe_int(val, default=None):
    """Parse an integer value or return default."""
    try:
        v = str(val).strip().replace(",", "")
        return int(float(v)) if v else default
    except (ValueError, TypeError):
        return default


def parse_fraction(val):
    """Parse values like '23 7/8' to decimal."""
    if not val or not str(val).strip():
        return None
    s = str(val).strip()
    if s.upper() == "N/A" or not any(c.isdigit() for c in s):
        return None
    parts = s.split()
    total = 0
    for part in parts:
        if "/" in part:
            num, den = part.split("/")
            total += float(num) / float(den)
        else:
            total += float(part)
    return round(total, 4)


def get_sheets():
    """Connect to Google Sheets."""
    scopes = ["https://www.googleapis.com/auth/spreadsheets.readonly"]
    creds = Credentials.from_service_account_file("credentials.json", scopes=scopes)
    return gspread.authorize(creds)


# ─────────────────────────────────────────────────────────────
# MODULE-LEVEL BUILDERS & MAPPERS
# ─────────────────────────────────────────────────────────────

def map_uom(val):
    """Map a sheet UOM value to a sys_uom code."""
    if not val:
        return None
    return UOM_MAP.get(str(val).strip().lower())


def build_description(spec):
    """Build product description from 5 spec columns."""
    parts = []
    for col in ["Attributes", "Scale", "EnvironmentallyConscious", "Pests", "FoodSafety"]:
        v = str(spec.get(col, "")).strip()
        if v and v.upper() != "N/A":
            parts.append(v)
    return "\n\n".join(parts) if parts else None


def build_photos(spec):
    """Build photos JSONB array from Image01..Image03.

    Normalizes legacy 'images/sales_products/' -> 'images/sales_product/' to
    match the unified bucket layout (one folder per current table name).
    """
    photos = []
    for col in ["Image01", "Image02", "Image03"]:
        v = str(spec.get(col, "")).strip()
        if v:
            v = v.replace("images/sales_products/", "images/sales_product/")
            photos.append(v)
    return photos


# ─────────────────────────────────────────────────────────────
# SALES PRODUCT
# ─────────────────────────────────────────────────────────────

def migrate_sales_product(supabase, gc):
    """Seed sales_product from four tabs in the sales spreadsheet."""
    wb = gc.open_by_key(SALES_SHEET_ID)

    # --- Tab 1: sales_product (base) ---
    base_map = {r["ProductCode"]: r for r in wb.worksheet("sales_product").get_all_records()}

    # --- Tab 2: sales_product_specs ---
    specs_map = {r["ProductCode"]: r for r in wb.worksheet("sales_product_specs").get_all_records()}

    # --- Tab 3: sales_product_measurements ---
    meas_map = {r["ProductCode"]: r for r in wb.worksheet("sales_product_measurements").get_all_records()}

    # --- Tab 4: sales_sysco_product_specs ---
    sysco_map = {r["product_abbreviations"]: r for r in wb.worksheet("sales_sysco_product_specs").get_all_records()}

    # Deduplicate names within the same farm — append code suffix if collision
    farm_names = defaultdict(list)
    for code, base in base_map.items():
        farm_name = to_id(str(base.get("Farm", "")).strip())
        name = str(base.get("Description", "")).strip()
        farm_names[(farm_name, name)].append(code)

    name_overrides = {}
    for (farm_name, name), codes in farm_names.items():
        if len(codes) > 1:
            for c in codes:
                name_overrides[c] = f"{name} ({c})"

    # Clear dependent tables first (FK order: photos/results → shelf_life → sales_product)
    print("\nClearing shelf life tables...")
    supabase.table("pack_shelf_life_photo").delete().neq("id", "00000000-0000-0000-0000-000000000000").execute()
    supabase.table("pack_shelf_life_result").delete().neq("id", "00000000-0000-0000-0000-000000000000").execute()
    supabase.table("pack_shelf_life").delete().neq("id", "00000000-0000-0000-0000-000000000000").execute()
    print("Clearing pack_lot_item...")
    supabase.table("pack_lot_item").delete().neq("id", "00000000-0000-0000-0000-000000000000").execute()
    print("Clearing pack_lot...")
    supabase.table("pack_lot").delete().neq("id", "00000000-0000-0000-0000-000000000000").execute()
    print("Clearing sales_product...")
    supabase.table("sales_product").delete().neq("id", "__none__").execute()

    rows = []
    for code, base in base_map.items():
        farm_name = str(base.get("Farm", "")).strip()
        farm_name = to_id(farm_name)
        spec = specs_map.get(code, {})
        meas = meas_map.get(code, {})
        sysco = sysco_map.get(code, {})

        case_net_weight = safe_numeric(meas.get("sale_unit_gross_weight"), default=None)
        pallet_ti = safe_numeric(sysco.get("vendor_ti"), default=None)
        pallet_hi = safe_numeric(sysco.get("vendor_hi"), default=None)

        pallet_net_weight = None
        if case_net_weight and pallet_ti and pallet_hi:
            pallet_net_weight = round(case_net_weight * pallet_ti * pallet_hi, 2)

        row = {
            "org_id": ORG_ID,
            "farm_name": farm_name,
            "code": code,
            "name": proper_case(name_overrides.get(code, str(base.get("Description", spec.get("ProductName", ""))).strip())),
            "description": build_description(spec),
            "item_uom": map_uom(meas.get("product_item_unit_id")),
            "pack_uom": map_uom(meas.get("pack_unit_id")),
            "item_per_pack": safe_numeric(meas.get("product_item_per_pack_unit"), default=None),
            "pack_per_case": safe_numeric(meas.get("pack_per_sale_unit"), default=None),
            "maximum_case_per_pallet": safe_int(base.get("MaxCasesForFullPallets")),
            "weight_uom": map_uom(sysco.get("weight_unit_of_measure")) or "pound",
            "pack_net_weight": safe_numeric(meas.get("pack_unit_gross_weight"), default=None),
            "case_net_weight": case_net_weight,
            "pallet_net_weight": pallet_net_weight,
            "dimension_uom": map_uom(sysco.get("packaging_unit_of_measure")),
            "case_length": parse_fraction(sysco.get("packaging_length")),
            "case_width": parse_fraction(sysco.get("packaging_width")),
            "case_height": parse_fraction(sysco.get("packaging_height")),
            "manufacturer_storage_method": proper_case(sysco.get("manufacturer_storage_method", "")) or None,
            "temperature_uom": map_uom(sysco.get("temperature_unit_of_measure")),
            "minimum_storage_temperature": safe_numeric(sysco.get("minimum_storage_temperature"), default=None),
            "maximum_storage_temperature": safe_numeric(sysco.get("maximum_storage_temperature"), default=None),
            "shelf_life_days": safe_int(sysco.get("product_shelf_life_days") or spec.get("ShelfLifeDays")),
            "pallet_ti": safe_numeric(pallet_ti, default=None),
            "pallet_hi": safe_numeric(pallet_hi, default=None),
            "shipping_requirements": str(spec.get("Shipping", "")).strip() or None,
            "is_catch_weight": parse_bool(sysco.get("is_catch_weight")),
            "is_hazardous": parse_bool(sysco.get("is_hazardous")),
            "is_fsma_traceable": parse_bool(sysco.get("is_fsma_traceable")),
            "gtin": str(sysco.get("gtin", "")).strip() or None,
            "upc": str(sysco.get("upc", "")).strip() or None,
            "photos": build_photos(spec),
        }

        # Remove None values so Supabase uses column defaults
        row = {k: v for k, v in row.items() if v is not None}
        rows.append(audit(row))

    inserted = insert_rows(supabase, "sales_product", rows)
    return {r["id"]: r for r in inserted}


# ─────────────────────────────────────────────────────────────
# PACK LOT — LETTUCE (from pack_L_packlot)
# ─────────────────────────────────────────────────────────────

def migrate_pack_lettuce(supabase, gc, product_map):
    """Migrate pack_L_packlot → pack_lot + pack_lot_item for lettuce farm.

    Rows with the same lot_number are merged — product quantities are summed.
    """
    wb = gc.open_by_key(PACK_SHEET_ID)
    data = wb.worksheet("pack_L_packlot").get_all_records()

    print(f"\nProcessing {len(data)} lettuce pack lot rows...")

    # Group rows by lot_number, merging product quantities
    lots = {}  # lot_number → { meta + product totals }
    for row in data:
        pack_date = parse_date(row.get("PackDate"))
        if not pack_date:
            continue

        lot_number = str(row.get("PackLot", "")).strip()
        if not lot_number:
            lot_number = pack_date.replace("-", "")

        if lot_number not in lots:
            lots[lot_number] = {
                "pack_date": pack_date,
                "harvest_date": parse_date(row.get("HarvestDate")),
                "best_by": parse_date(row.get("BestByDate")),
                "reported_by": str(row.get("ReportedBy", "")).strip().lower() or None,
                "products": defaultdict(float),
            }

        for col, product_id in LETTUCE_PRODUCT_COLS.items():
            qty = safe_numeric(row.get(col))
            if qty > 0:
                lots[lot_number]["products"][product_id] += qty

        # Use best_by / reported_by from whichever row has it
        if not lots[lot_number]["best_by"]:
            lots[lot_number]["best_by"] = parse_date(row.get("BestByDate"))
        if not lots[lot_number]["reported_by"]:
            lots[lot_number]["reported_by"] = str(row.get("ReportedBy", "")).strip().lower() or None

    print(f"  Merged to {len(lots)} unique lots")

    # Clear existing (farm-scoped)
    print("\nClearing pack_lot_item (lettuce)...")
    existing_lots = supabase.table("pack_lot").select("id").eq("farm_name", "lettuce").execute().data
    if existing_lots:
        lot_ids = [l["id"] for l in existing_lots]
        for i in range(0, len(lot_ids), 100):
            batch = lot_ids[i:i + 100]
            supabase.table("pack_lot_item").delete().in_("pack_lot_id", batch).execute()
    print("Clearing pack_lot (lettuce)...")
    supabase.table("pack_lot").delete().eq("farm_name", "lettuce").execute()

    # Insert lots
    lot_rows = []
    sorted_lot_numbers = sorted(lots.keys())
    for lot_number in sorted_lot_numbers:
        info = lots[lot_number]
        reported_by = info["reported_by"] or AUDIT_USER
        lot_rows.append({
            "org_id": ORG_ID,
            "farm_name": "Lettuce",
            "lot_number": lot_number,
            "harvest_date": info["harvest_date"],
            "pack_date": info["pack_date"],
            "created_by": reported_by,
            "updated_by": reported_by,
        })

    inserted_lots = insert_rows(supabase, "pack_lot", lot_rows)

    # Insert items
    item_rows = []
    for idx, lot_number in enumerate(sorted_lot_numbers):
        info = lots[lot_number]
        lot_id = inserted_lots[idx]["id"]
        pack_date = info["pack_date"]
        best_by = info["best_by"]
        reported_by = info["reported_by"] or AUDIT_USER

        for product_id, qty in info["products"].items():
            item_best_by = best_by
            if not item_best_by:
                product = product_map.get(product_id, {})
                shelf_days = product.get("shelf_life_days")
                if shelf_days and pack_date:
                    dt = datetime.strptime(pack_date, "%Y-%m-%d") + timedelta(days=int(shelf_days))
                    item_best_by = dt.strftime("%Y-%m-%d")
            if not item_best_by:
                item_best_by = pack_date

            item_rows.append({
                "org_id": ORG_ID,
                "farm_name": "Lettuce",
                "pack_lot_id": lot_id,
                "sales_product_id": product_id,
                "best_by_date": item_best_by,
                "pack_quantity": qty,
                "created_by": reported_by,
                "updated_by": reported_by,
            })

    insert_rows(supabase, "pack_lot_item", item_rows)


# ─────────────────────────────────────────────────────────────
# PACK LOT — CUKE (from pack_C_prod, summed by date)
# ─────────────────────────────────────────────────────────────

def migrate_pack_cuke(supabase, gc, product_map):
    """Migrate pack_C_prod → pack_lot + pack_lot_item for cuke farm.

    Sums quantities across all packers for each date to produce
    one pack_lot per date with aggregated pack_lot_items.
    """
    wb = gc.open_by_key(PACK_SHEET_ID)
    data = wb.worksheet("pack_C_prod").get_all_records()

    print(f"\nProcessing {len(data)} cuke packer rows (will aggregate by date)...")

    # Aggregate: date → { product_id → total_cases }
    date_totals = defaultdict(lambda: defaultdict(float))
    date_reporters = {}  # date → first reported_by email
    for row in data:
        pack_date = parse_date(row.get("PackDate"))
        if not pack_date:
            continue
        for col, product_id in CUKE_PRODUCT_COLS.items():
            qty = safe_numeric(row.get(col))
            if qty > 0:
                date_totals[pack_date][product_id] += qty
        if pack_date not in date_reporters:
            date_reporters[pack_date] = str(row.get("ReportedBy", "")).strip().lower() or None

    print(f"  Aggregated to {len(date_totals)} unique pack dates")

    # Clear existing (farm-scoped)
    print("\nClearing pack_lot_item (cuke)...")
    existing_lots = supabase.table("pack_lot").select("id").eq("farm_name", "cuke").execute().data
    if existing_lots:
        lot_ids = [l["id"] for l in existing_lots]
        for i in range(0, len(lot_ids), 100):
            batch = lot_ids[i:i + 100]
            supabase.table("pack_lot_item").delete().in_("pack_lot_id", batch).execute()
    print("Clearing pack_lot (cuke)...")
    supabase.table("pack_lot").delete().eq("farm_name", "cuke").execute()

    # Insert lots sorted by date
    lot_rows = []
    sorted_dates = sorted(date_totals.keys())
    for pack_date in sorted_dates:
        reported_by = date_reporters.get(pack_date) or AUDIT_USER
        lot_rows.append({
            "org_id": ORG_ID,
            "farm_name": "Cuke",
            "lot_number": pack_date.replace("-", ""),
            "pack_date": pack_date,
            "created_by": reported_by,
            "updated_by": reported_by,
        })

    inserted_lots = insert_rows(supabase, "pack_lot", lot_rows)

    # Insert items
    item_rows = []
    for idx, pack_date in enumerate(sorted_dates):
        lot_id = inserted_lots[idx]["id"]
        products = date_totals[pack_date]

        for product_id, qty in products.items():
            product = product_map.get(product_id, {})
            shelf_days = product.get("shelf_life_days")
            if shelf_days:
                dt = datetime.strptime(pack_date, "%Y-%m-%d") + timedelta(days=int(shelf_days))
                best_by = dt.strftime("%Y-%m-%d")
            else:
                best_by = pack_date

            reported_by = date_reporters.get(pack_date) or AUDIT_USER
            item_rows.append({
                "org_id": ORG_ID,
                "farm_name": "Cuke",
                "pack_lot_id": lot_id,
                "sales_product_id": product_id,
                "best_by_date": best_by,
                "pack_quantity": qty,
                "created_by": reported_by,
                "updated_by": reported_by,
            })

    insert_rows(supabase, "pack_lot_item", item_rows)


# ─────────────────────────────────────────────────────────────
# SHELF LIFE (from pack_L_slife, pack_L_slife_obsv, pack_L_slife_photos)
# ─────────────────────────────────────────────────────────────

# Shelf life metrics — the 5 observation checks from legacy data
SHELF_LIFE_METRICS = [
    {
        "id": "external_damage",
        "name": "External Damage",
        "response_type": "enum",
        "enum_options": ["None", "A Little", "Wouldn't Buy"],
        "fail_enum_values": ["Wouldn't Buy"],
        "display_order": 1,
        "is_active": False,
    },
    {
        "id": "internal_damage",
        "name": "Internal Damage",
        "response_type": "enum",
        "enum_options": ["None", "A Little", "Wouldn't Buy"],
        "fail_enum_values": ["Wouldn't Buy"],
        "display_order": 2,
        "is_active": False,
    },
    {
        "id": "moisture",
        "name": "Moisture",
        "response_type": "enum",
        "enum_options": ["None", "A Little", "Wouldn't Buy"],
        "fail_enum_values": ["Wouldn't Buy"],
        "display_order": 3,
    },
    {
        "id": "color",
        "name": "Color",
        "response_type": "enum",
        "enum_options": ["Good", "Acceptable", "Wouldn't Buy"],
        "fail_enum_values": ["Wouldn't Buy"],
        "display_order": 4,
    },
    {
        "id": "texture",
        "name": "Texture",
        "response_type": "enum",
        "enum_options": ["Good", "Acceptable", "Wouldn't Buy"],
        "fail_enum_values": ["Wouldn't Buy"],
        "display_order": 5,
    },
]

# Map observation columns to metric IDs
OBSV_METRIC_MAP = {
    "ExternalDamage": "external_damage",
    "InternalDamage": "internal_damage",
    "Moisture": "moisture",
    "Color": "color",
    "Texture": "texture",
}

# Normalize enum values (legacy data has inconsistent casing)
ENUM_NORMALIZE = {
    "none": "None",
    "a little": "A Little",
    "wouldn't buy": "Wouldn't Buy",
    "wound't buy": "Wouldn't Buy",
    "good": "Good",
    "acceptable": "Acceptable",
}

# Photo type mapping
PHOTO_SIDE_MAP = {
    "TopPhoto": "top",
    "BottomPhoto": "bottom",
    "SidePhoto": "side",
}


def migrate_shelf_life_metrics(supabase):
    """Seed the 5 shelf life observation metrics."""
    print("\nClearing pack_shelf_life_metric...")
    supabase.table("pack_shelf_life_metric").delete().neq("name", "__none__").execute()

    rows = []
    for m in SHELF_LIFE_METRICS:
        rows.append(audit({
            "id": m["id"],
            "org_id": ORG_ID,
            "farm_name": "Lettuce",
            "name": m["name"],
            "response_type": m["response_type"],
            "enum_options": m["enum_options"],
            "fail_enum_values": m["fail_enum_values"],
            "display_order": m["display_order"],
            "is_active": m.get("is_active", True),
        }))

    insert_rows(supabase, "pack_shelf_life_metric", rows)


def migrate_shelf_life(supabase, gc):
    """Migrate pack_L_slife → pack_shelf_life, pack_L_slife_obsv → pack_shelf_life_result,
    and pack_L_slife_photos → pack_shelf_life_photo.

    Skips pack_L_slife(Old) per requirements.
    """
    wb = gc.open_by_key(PACK_SHEET_ID)

    # --- Load all sheet data ---
    slife_data = wb.worksheet("pack_L_slife").get_all_records()
    obsv_data = wb.worksheet("pack_L_slife_obsv").get_all_records()
    photo_data = wb.worksheet("pack_L_slife_photos").get_all_records()

    print(f"\nProcessing {len(slife_data)} shelf life trials...")
    print(f"  {len(obsv_data)} observations, {len(photo_data)} photos")

    # --- Build pack_lot lookup by date ---
    lots = supabase.table("pack_lot").select("id, pack_date").eq("farm_name", "lettuce").execute()
    lot_by_date = {}
    for l in lots.data:
        lot_by_date.setdefault(l["pack_date"], l["id"])

    # --- Clear existing shelf life data (FK order) ---
    print("\nClearing shelf life tables...")
    supabase.table("pack_shelf_life_photo").delete().neq("id", "00000000-0000-0000-0000-000000000000").execute()
    supabase.table("pack_shelf_life_result").delete().neq("id", "00000000-0000-0000-0000-000000000000").execute()
    supabase.table("pack_shelf_life").delete().neq("id", "00000000-0000-0000-0000-000000000000").execute()

    # --- Insert shelf life trials ---
    trial_rows = []
    for r in slife_data:
        trial_id = str(r.get("TrialID", "")).strip()
        if not trial_id:
            continue

        pack_date = parse_date(r.get("PackDate"))
        product_code = str(r.get("ProductCode", "")).strip()
        packaging = str(r.get("Packaging", "")).strip()
        trial_product = str(r.get("TrialProduct", "")).strip()
        status = str(r.get("Status", "")).strip()
        data_quality = str(r.get("DataQuality", "")).strip()
        sheet_notes = str(r.get("Notes", "")).strip()
        reported_by = str(r.get("RecordedBy", "")).strip().lower() or AUDIT_USER

        # Resolve sales_product_id (Trial -> null)
        sales_product_id = product_code if product_code and product_code != "Trial" else None

        # Resolve pack_lot_id by date
        pack_lot_id = lot_by_date.get(pack_date) if pack_date else None

        # Build notes — prepend packaging, unmatched date, trial product, data quality
        notes_parts = []
        if packaging:
            notes_parts.append(f"Packaging: {packaging}")
        if trial_product:
            notes_parts.append(f"Trial product: {trial_product}")
        if data_quality and data_quality != "Good":
            notes_parts.append(f"Data quality: {data_quality}")
        if pack_date and not pack_lot_id:
            notes_parts.append(f"Pack date: {pack_date} (no matching lot)")
        if sheet_notes:
            notes_parts.append(sheet_notes)
        notes = "; ".join(notes_parts) if notes_parts else None

        # Determine trial_purpose
        trial_purpose = trial_product if trial_product else (product_code if product_code == "Trial" else None)

        # is_terminated
        is_terminated = status == "Completed"

        trial_rows.append({
            "org_id": ORG_ID,
            "farm_name": "Lettuce",
            "pack_lot_id": pack_lot_id,
            "sales_product_id": sales_product_id,
            "trial_number": safe_int(trial_id),
            "trial_purpose": trial_purpose,
            "is_terminated": is_terminated,
            "notes": notes,
            "created_by": reported_by,
            "updated_by": reported_by,
        })

    inserted_trials = insert_rows(supabase, "pack_shelf_life", trial_rows)

    # Build trial_number -> inserted ID map
    trial_id_map = {}
    for t in inserted_trials:
        if t.get("trial_number"):
            trial_id_map[t["trial_number"]] = t["id"]

    print(f"  Mapped {len(trial_id_map)} trials by trial_number")

    # --- Insert observations as shelf life results ---
    # Each observation row has 5 metric columns -> up to 5 result rows
    # Deduplicate by (shelf_life_id, metric_id, obs_date) — last row wins
    result_map = {}  # (shelf_life_id, metric_id, obs_date) -> row
    terminate_map = {}  # trial_id -> termination info from observations
    skipped_obsv = 0

    for r in obsv_data:
        trial_num = safe_int(r.get("TrialID"))
        if not trial_num or trial_num not in trial_id_map:
            skipped_obsv += 1
            continue

        shelf_life_id = trial_id_map[trial_num]
        obs_date = parse_date(r.get("ObservationDate"))
        if not obs_date:
            skipped_obsv += 1
            continue

        shelf_life_day = safe_int(r.get("SlifeDay")) or 0
        reported_by = str(r.get("ReportedBy", "")).strip().lower() or AUDIT_USER
        obs_notes = str(r.get("Notes", "")).strip() or None
        terminate = str(r.get("TerminateTrial", "")).strip().lower() == "true"

        if terminate:
            terminate_map[trial_num] = obs_date

        for col, metric_id in OBSV_METRIC_MAP.items():
            val = str(r.get(col, "")).strip()
            if not val:
                continue

            # Normalize enum value
            normalized = ENUM_NORMALIZE.get(val.lower(), proper_case(val))

            key = (shelf_life_id, metric_id, obs_date)
            result_map[key] = {
                "org_id": ORG_ID,
                "farm_name": "Lettuce",
                "pack_shelf_life_id": shelf_life_id,
                "pack_shelf_life_metric_name": metric_id,
                "observation_date": obs_date,
                "shelf_life_day": shelf_life_day,
                "response_enum": normalized,
                "notes": obs_notes,
                "created_by": reported_by,
                "updated_by": reported_by,
            }
            # Only attach notes to the first metric per observation
            obs_notes = None

    result_rows = list(result_map.values())
    insert_rows(supabase, "pack_shelf_life_result", result_rows)
    if skipped_obsv:
        print(f"  Skipped {skipped_obsv} observations (unknown trial or missing date)")

    # Update termination reasons from observation data
    updates = 0
    for trial_num, term_date in terminate_map.items():
        trial_uuid = trial_id_map.get(trial_num)
        if trial_uuid:
            supabase.table("pack_shelf_life").update({
                "is_terminated": True,
                "termination_reason": f"Terminated on {term_date}",
            }).eq("id", trial_uuid).execute()
            updates += 1
    if updates:
        print(f"  Updated {updates} trials with termination info")

    # --- Insert photos ---
    photo_rows = []
    skipped_photos = 0

    for r in photo_data:
        trial_num = safe_int(r.get("TrialID"))
        if not trial_num or trial_num not in trial_id_map:
            skipped_photos += 1
            continue

        shelf_life_id = trial_id_map[trial_num]
        photo_url = str(r.get("Photo", "")).strip()
        if not photo_url:
            skipped_photos += 1
            continue
        # Normalize legacy 'images/pack_slife/' -> 'images/pack_shelf_life/'
        photo_url = photo_url.replace("images/pack_slife/", "images/pack_shelf_life/")

        photo_type = str(r.get("PhotoType", "")).strip()
        side = PHOTO_SIDE_MAP.get(photo_type)
        if not side:
            skipped_photos += 1
            continue

        # Derive observation_date and shelf_life_day from ObservationID (format: "746-22")
        obs_id = str(r.get("ObservationID", "")).strip()
        shelf_life_day = 0
        if "-" in obs_id:
            parts = obs_id.split("-")
            shelf_life_day = safe_int(parts[-1]) or 0

        # Get observation_date from ReportedDateTime (format: "03/30/26 08:06")
        reported_dt = str(r.get("ReportedDateTime", "")).strip()
        # Extract date part before the time
        date_part = reported_dt.split(" ")[0] if reported_dt else ""
        obs_date = parse_date(date_part)
        if not obs_date:
            skipped_photos += 1
            continue

        photo_rows.append({
            "org_id": ORG_ID,
            "farm_name": "Lettuce",
            "pack_shelf_life_id": shelf_life_id,
            "observation_date": obs_date,
            "shelf_life_day": shelf_life_day,
            "side": side,
            "photo_url": photo_url,
            "created_by": AUDIT_USER,
            "updated_by": AUDIT_USER,
        })

    insert_rows(supabase, "pack_shelf_life_photo", photo_rows)
    if skipped_photos:
        print(f"  Skipped {skipped_photos} photos (unknown trial, missing URL/side/date)")


# ─────────────────────────────────────────────────────────────
# PACK DRYER RESULT (from pack_L_moisture_checks)
# ─────────────────────────────────────────────────────────────

# Normalize legacy seed_name values to invnt_item IDs
SEED_NAME_MAP = {
    "3013": "3013",
    "3013 after dryer": "3013",
    "3310": "3310",
    "3404": "3404",
    "3901": "3901",
    "alboreto": "alboreto",
    "hf mix": None,
    "mixed version 2.0": "mixed_version_2_0",
    "mixedversion 2.0": "mixed_version_2_0",
    "mixed boards": None,
    "mixed seeds": None,
    "romaine": None,
    "romaine w heater overnight": None,
    "runaway": "runaway",
    "trial": "trial",
    "watercress": "watercress",
    "webber": "webber",
}

# Extract pond site_id from notes text
POND_REGEX = re.compile(r"pond\s*(\d)", re.IGNORECASE)


def parse_site_from_notes(notes):
    """Extract site_id (p1-p7) from notes text referencing a pond."""
    if not notes:
        return None
    m = POND_REGEX.search(notes)
    return f"p{m.group(1)}" if m else None


def parse_time(time_str):
    """Parse a time string like '8:23', '10:00:00', '12:14:00' to HH:MM:SS."""
    if not time_str or not str(time_str).strip():
        return None
    s = str(time_str).strip()
    for fmt in ("%H:%M:%S", "%H:%M"):
        try:
            from datetime import datetime as dt
            return dt.strptime(s, fmt).strftime("%H:%M:%S")
        except ValueError:
            continue
    return None


def migrate_pack_dryer_result(supabase, gc):
    """Migrate pack_L_moisture_checks → pack_dryer_result for lettuce farm.

    Parses site_id from notes (pond references) and maps seed_name to invnt_item_id.
    """
    wb = gc.open_by_key(PACK_SHEET_ID)
    data = wb.worksheet("pack_L_moisture_checks").get_all_records()

    print(f"\nProcessing {len(data)} dryer result rows...")

    # Clear existing
    print("Clearing pack_dryer_result...")
    supabase.table("pack_dryer_result").delete().neq("id", "00000000-0000-0000-0000-000000000000").execute()

    rows = []
    skipped = 0
    for r in data:
        check_date = parse_date(r.get("check_date"))
        if not check_date:
            skipped += 1
            continue

        check_time = parse_time(r.get("hour"))
        if check_time:
            check_at = f"{check_date}T{check_time}"
        else:
            check_at = f"{check_date}T00:00:00"

        notes = str(r.get("additional_notes", "")).strip() or None
        site_id = parse_site_from_notes(notes) or "gh"

        seed_name = str(r.get("seed_name", "")).strip()
        invnt_item_id = SEED_NAME_MAP.get(seed_name.lower()) if seed_name else None

        # If seed_name has no invnt_item match, prepend it to notes
        if seed_name and not invnt_item_id:
            notes = f"[{seed_name}] {notes}" if notes else f"[{seed_name}]"

        # Parse moisture percentages (strip % sign)
        moisture_before = str(r.get("moisture_loss_before_dryer", "")).strip().replace("%", "")
        moisture_after = str(r.get("moisture_loss_after_dryer", "")).strip().replace("%", "")

        reported_by = str(r.get("created_by", "")).strip().lower() or AUDIT_USER

        row = {
            "org_id": ORG_ID,
            "farm_name": "Lettuce",
            "site_id": site_id,
            "invnt_item_id": invnt_item_id,
            "check_at": check_at,
            "temperature_uom": "fahrenheit",
            "dryer_temperature": safe_numeric(r.get("dryer_temperature"), default=None),
            "greenhouse_temperature": safe_numeric(r.get("greenhouse_temperature"), default=None),
            "packhouse_temperature": safe_numeric(r.get("packhouse_temperature"), default=None),
            "pre_packing_leaf_temperature": safe_numeric(r.get("pre_packing_leaf_temperature"), default=None),
            "moisture_uom": "percent",
            "moisture_before_dryer": safe_numeric(moisture_before, default=None),
            "moisture_after_dryer": safe_numeric(moisture_after, default=None),
            "belt_speed": safe_numeric(r.get("belt_speed"), default=None),
            "tracking_code": str(r.get("pre_packing_tracking_code", "")).strip() or None,
            "notes": notes,
            "created_by": reported_by,
            "updated_by": reported_by,
        }

        # Remove None values so Supabase uses column defaults
        row = {k: v for k, v in row.items() if v is not None}
        rows.append(row)

    insert_rows(supabase, "pack_dryer_result", rows)
    if skipped:
        print(f"  Skipped {skipped} rows (missing date)")


# ─────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────

def main():
    supabase = create_client(SUPABASE_URL, SUPABASE_KEY)
    gc = get_sheets()

    print("=" * 60)
    print("PACK MIGRATION")
    print("=" * 60)

    # Step 1: Seed sales_product (needed as FK for pack_lot_item)
    product_map = migrate_sales_product(supabase, gc)

    # Step 2: Lettuce pack lots from pack_L_packlot
    migrate_pack_lettuce(supabase, gc, product_map)

    # Step 3: Cuke pack lots from pack_C_prod (summed by date)
    migrate_pack_cuke(supabase, gc, product_map)

    # Step 4: Shelf life metrics, trials, observations, photos
    migrate_shelf_life_metrics(supabase)
    migrate_shelf_life(supabase, gc)

    # Step 5: Dryer results from pack_L_moisture_checks
    migrate_pack_dryer_result(supabase, gc)

    print("\n" + "=" * 60)
    print("DONE")
    print("=" * 60)


if __name__ == "__main__":
    main()
