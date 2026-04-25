"""
Migrate Inventory Data
=======================
Migrates invnt_vendor, invnt_category from legacy Google Sheets to Supabase.

Source: https://docs.google.com/spreadsheets/d/15ppDoDWLR1TIXCO5Gy3LIvEQ9KpJmtSqNY1Cao3E1Po
  - invnt_vendor: unique SupplierName values from invnt_item_po sheet
  - invnt_category: from invnt_item_category sheet + unique ItemSubCategory from invnt_item sheet

Usage:
    python scripts/migrations/20260401000006_invnt.py

Rerunnable: clears and reinserts all data on each run.
"""

import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

import gspread
from google.oauth2.service_account import Credentials
from supabase import create_client

from gsheets.migrations._pg import paginate_select

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
SHEET_ID = "15ppDoDWLR1TIXCO5Gy3LIvEQ9KpJmtSqNY1Cao3E1Po"


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


def get_sheets():
    """Connect to Google Sheets."""
    scopes = ["https://www.googleapis.com/auth/spreadsheets.readonly"]
    creds = Credentials.from_service_account_file("credentials.json", scopes=scopes)
    return gspread.authorize(creds)


def parse_date(date_str):
    """Parse date string to YYYY-MM-DD or None."""
    if not date_str or not str(date_str).strip():
        return None
    from datetime import datetime
    for fmt in ("%m/%d/%Y", "%m/%d/%y", "%Y-%m-%d"):
        try:
            return datetime.strptime(str(date_str).strip(), fmt).strftime("%Y-%m-%d")
        except ValueError:
            continue
    return None


def parse_timestamp(ts_str):
    """Parse timestamp to ISO format or None."""
    if not ts_str or not str(ts_str).strip():
        return None
    from datetime import datetime
    for fmt in ("%m/%d/%Y %H:%M:%S", "%m/%d/%Y %H:%M", "%m/%d/%Y"):
        try:
            return datetime.strptime(str(ts_str).strip(), fmt).isoformat()
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


def safe_int(val, default=None):
    """Parse an integer value or return default."""
    try:
        v = str(val).strip().replace(",", "")
        return int(float(v)) if v else default
    except (ValueError, TypeError):
        return default


def parse_bool(val):
    """Parse boolean from various formats."""
    return str(val).strip().upper() in ("TRUE", "YES", "1", "ACCEPTABLE")


def migrate_invnt_vendor(supabase, gc):
    """Migrate unique vendor names from invnt_item_po SupplierName column."""
    ws = gc.open_by_key(SHEET_ID).worksheet("invnt_item_po")
    records = ws.get_all_records()

    vendors = sorted(set(
        str(r.get("SupplierName", "")).strip()
        for r in records
        if str(r.get("SupplierName", "")).strip()
    ))

    rows = [
        audit({
            "org_id": ORG_ID,
            "name": proper_case(v),
        })
        for v in vendors
    ]
    insert_rows(supabase, "invnt_vendor", rows)
    return {v: proper_case(v) for v in vendors}


def migrate_invnt_category(supabase, gc):
    """Provision standard inventory categories + legacy subcategories from invnt_item."""
    sheet = gc.open_by_key(SHEET_ID)

    # Standard provisioned categories (from org_provisioning process doc)
    provisioned = [
        ("Chemicals/Pesticides", None),
        ("Fertilizers", None),
        ("Seeds", None),
        ("Seeds", "Trial"),
        ("Growing", None),
        ("Packing", None),
        ("Maintenance", None),
        ("Food Safety", None),
    ]

    # Map legacy category names to new provisioned names
    LEGACY_CAT_MAP = {
        "Chems/Pestic": "Chemicals/Pesticides",
        "Fert": "Fertilizers",
        "Seeds": "Seeds",
        "Trial Seeds": "Seeds",  # maps to Seeds with subcategory Trial
        "Grow": "Growing",
        "Packaging": "Packing",
        "Maint Parts": "Maintenance",
        "Lab Supplies": "Food Safety",
    }

    # Pull subcategories from legacy invnt_item ItemSubCategory column
    ws_item = sheet.worksheet("invnt_item")
    item_records = ws_item.get_all_records()

    legacy_subs = {}
    for r in item_records:
        cat = str(r.get("ItemCategory", "")).strip()
        sub = str(r.get("ItemSubCategory", "")).strip()
        if cat and sub:
            mapped_cat = LEGACY_CAT_MAP.get(cat, cat)
            legacy_subs.setdefault(mapped_cat, set()).add(sub)

    rows = []
    seen = set()

    # Provisioned categories first
    for cat, sub in provisioned:
        row_id = to_id(sub) if sub else to_id(cat)
        if row_id not in seen:
            seen.add(row_id)
            rows.append(audit({
                "id": row_id,
                "org_id": ORG_ID,
                "category_name": cat,
                "sub_category_name": proper_case(sub) if sub else sub,
            }))

    # Legacy subcategories mapped to new category names
    for cat, subs in sorted(legacy_subs.items()):
        for sub in sorted(subs):
            row_id = to_id(sub)
            if row_id not in seen:
                seen.add(row_id)
                rows.append(audit({
                    "id": row_id,
                    "org_id": ORG_ID,
                    "category_name": cat,
                    "sub_category_name": proper_case(sub),
                }))

    insert_rows(supabase, "invnt_category", rows)


def migrate_storage_sites(supabase, gc):
    """Create maintenance_storage subcategory and storage sites from ItemLocation."""

    # Add maintenance_storage subcategory to org_site_category
    supabase.table("org_site_category").insert(audit({
        "id": "maintenance_storage",
        "org_id": ORG_ID,
        "category_name": "storage",
        "sub_category_name": "maintenance_storage",
        "display_order": 5,
    })).execute()
    print("\n--- org_site_category ---")
    print("  Added maintenance_storage subcategory")

    # Get unique ItemLocation values
    ws = gc.open_by_key(SHEET_ID).worksheet("invnt_item")
    records = ws.get_all_records()

    locations = set()
    for r in records:
        loc = str(r.get("ItemLocation", "")).strip()
        if loc:
            locations.add(loc)

    # Create sites from unique locations
    rows = []
    seen_ids = set()
    for loc in sorted(locations):
        site_id = to_id(loc)
        # Skip duplicates that clean to the same ID
        if site_id in seen_ids or not site_id:
            continue
        seen_ids.add(site_id)
        rows.append(audit({
            "id": site_id,
            "org_id": ORG_ID,
            "name": proper_case(loc),
            "org_site_category_id": "storage",
            "org_site_subcategory_id": "maintenance_storage",
        }))

    insert_rows(supabase, "org_site", rows)


def migrate_invnt_item(supabase, gc):
    """Migrate inventory items from invnt_item sheet."""
    ws = gc.open_by_key(SHEET_ID).worksheet("invnt_item")
    records = ws.get_all_records()

    # Legacy category -> new category mapping
    LEGACY_CAT_MAP = {
        "Chems/Pestic": "chemicals_pesticides",
        "Fert": "fertilizers",
        "Seeds": "seeds",
        "Trial Seeds": "seeds",
        "Grow": "growing",
        "Packaging": "packing",
        "Maint Parts": "maintenance",
        "Lab Supplies": "food_safety",
    }

    # Trial Seeds -> subcategory "trial"
    LEGACY_SUB_OVERRIDE = {
        "Trial Seeds": "trial",
    }

    # UOM mapping: legacy names -> sys_uom codes
    UOM_MAP = {
        "seeds": "seed", "pieces": "piece", "bags": "bag", "boxes": "box",
        "pounds": "pound", "rolls": "roll", "bottles": "bottle",
        "gallons": "gallon", "trays": "tray", "packs": "pack",
        "labels": "label", "cases": "case", "drums": "drum",
        "clips": "clip", "kits": "kit", "pallets": "pallet",
        "units": "unit", "dozen": "dozen", "lids": "lid",
        "quarts": "quart", "ounces": "ounce", "grams": "gram",
        "feet": "feet", "meters": "meter", "impressions": "impression",
        "blades": "blade", "reactions": "reactions",
        "fluid ounces": "fluid_ounce", "fluid_ounces": "fluid_ounce",
        "ml": "milliliter", "milliliters": "milliliter",
        # Singular forms
        "seed": "seed", "piece": "piece", "bag": "bag", "box": "box",
        "pound": "pound", "roll": "roll", "bottle": "bottle",
        "gallon": "gallon", "tray": "tray", "pack": "pack",
        "label": "label", "case": "case", "drum": "drum",
        "clip": "clip", "kit": "kit", "pallet": "pallet",
        "unit": "unit", "lid": "lid", "quart": "quart",
        "ounce": "ounce", "gram": "gram", "blade": "blade",
        "impression": "impression", "count": "count",
        "cubes": "cubes",
    }

    def map_uom(val):
        v = str(val).strip().lower()
        return UOM_MAP.get(v, v) if v else None

    rows = []
    seen = set()

    for r_raw in records:
        # Strip whitespace from all keys (legacy headers have leading/trailing spaces)
        r = {str(k).strip(): v for k, v in r_raw.items()}
        name = str(r.get("ItemName", "")).strip()
        if not name:
            continue

        item_id = to_id(name)
        if item_id in seen:
            continue
        seen.add(item_id)

        # Category mapping
        legacy_cat = str(r.get("ItemCategory", "")).strip()
        cat_id = LEGACY_CAT_MAP.get(legacy_cat)

        # Subcategory: check override first, then ItemSubCategory
        sub_id = LEGACY_SUB_OVERRIDE.get(legacy_cat)
        if not sub_id:
            sub = str(r.get("ItemSubCategory", "")).strip()
            sub_id = to_id(sub) if sub else None

        # Farm — "HF" is the org, not a farm; skip it
        farm = str(r.get("Farm", "")).strip()
        farm_name = proper_case(farm) if farm and farm.upper() != "HF" else None

        # UOMs
        burn_uom = map_uom(r.get("BurnUnits", ""))
        order_uom = map_uom(r.get("OrderUnits", ""))
        onhand_uom = burn_uom  # Set onhand_uom same as burn_uom

        # Burn per order — use legacy value; default to 1 only when zero/empty AND burn_uom == order_uom
        burn_per_order = safe_numeric(r.get("BurnPerOrderUnit", ""))
        if burn_per_order == 0 and burn_uom and order_uom and burn_uom == order_uom:
            burn_per_order = 1
        burn_per_onhand = 1  # Since onhand_uom = burn_uom, 1:1 ratio

        # Burn rates
        burn_per_week = safe_numeric(r.get("EstimatedBurnPerWeek", ""))
        cushion_raw = safe_numeric(r.get("CushionWeeks", ""))
        lead_time = safe_numeric(r.get("EstimatedLeadTimeWeeks", ""))
        cushion_weeks = cushion_raw + lead_time

        # Calculate reorder point and quantity
        reorder_point = round(burn_per_week * cushion_weeks, 2)
        reorder_quantity = round(burn_per_week * cushion_weeks, 2)

        # Pallet
        is_palletized = parse_bool(r.get("Pallet", ""))
        order_per_pallet = safe_numeric(r.get("OrderUnitsPerPallet", ""))
        pallet_per_truckload = safe_numeric(r.get("PalletsPerTruckload", ""))

        # Site (storage location)
        location = str(r.get("ItemLocation", "")).strip()
        site_id = to_id(location) if location else None

        # Variety — only set if it exists in grow_variety (skip unknown codes like 'KL')
        variety = str(r.get("SeedVariety", "")).strip().upper()
        variety_id = variety if variety else None
        VALID_VARIETIES = {"BB","E","GA","GB","GC","GF","GG","GL","GO","GR","GT",
            "J","K","KE","MX","RB","RC","RL","RO","RR","SP","WC","WR","WS"}
        if variety_id and variety_id not in VALID_VARIETIES:
            variety_id = None

        # Pelleted
        pelleted_raw = str(r.get("Pelleted", "")).strip()
        seed_is_pelleted = True if pelleted_raw.lower() == "true" else (False if pelleted_raw.lower() == "false" else None)

        # Status — Active vs Inactive
        status = str(r.get("ItemStatus", "")).strip().lower()
        is_active = status != "inactive"

        # Photo — normalize legacy sheet path to the unified 'images/' bucket layout
        photo = str(r.get("ItemPhoto", "")).strip()
        if photo:
            photo = photo.replace("images/invnt/", "images/invnt_item/")
        photos = [photo] if photo else []

        # QB account
        qb = str(r.get("QuickBooksAccount", "")).strip()

        # Manufacturer from SeedMaker
        manufacturer = proper_case(r.get("SeedMaker", "")) or None

        # Maintenance part number from ModelSerialNumber
        maint_part_number = str(r.get("ModelSerialNumber", "")).strip() or None

        # Subcategory as maint_part_type for maintenance items
        maint_sub = str(r.get("ItemSubCategory", "")).strip()
        maint_part_type = proper_case(maint_sub) if legacy_cat == "Maint Parts" and maint_sub else None

        row = {
            "org_id": ORG_ID,
            "farm_name": farm_name,
            "invnt_category_id": cat_id,
            "invnt_subcategory_id": sub_id,
            "name": proper_case(name),
            "qb_account": qb or None,
            "burn_uom": burn_uom,
            "onhand_uom": onhand_uom,
            "order_uom": order_uom,
            "burn_per_onhand": burn_per_onhand,
            "burn_per_order": burn_per_order,
            "is_palletized": is_palletized,
            "order_per_pallet": order_per_pallet,
            "pallet_per_truckload": pallet_per_truckload,
            "is_frequently_used": parse_bool(r.get("FrequentlyOrdered", "")),
            "burn_per_week": burn_per_week,
            "cushion_weeks": cushion_weeks,
            "reorder_point_in_burn": reorder_point,
            "reorder_quantity_in_burn": reorder_quantity,
            "site_id": site_id,
            "invnt_vendor_name": None,
            "manufacturer": manufacturer,
            "grow_variety_id": variety_id,
            "seed_is_pelleted": seed_is_pelleted,
            "maint_part_type": maint_part_type,
            "maint_part_number": maint_part_number,
            "photos": photos,
            "is_active": is_active,
        }
        rows.append(audit(row))

    insert_rows(supabase, "invnt_item", rows)
    return records  # Return for downstream use


def migrate_invnt_po(supabase, gc):
    """Migrate POs from both invnt_item_po (historical) and proc_requests (active)."""

    # Build employee email -> id lookup from Supabase
    employees = paginate_select(supabase, "hr_employee", "name, company_email")
    email_to_emp = {}
    for e in employees:
        if e.get("company_email"):
            email_to_emp[e["company_email"].lower()] = e["name"]

    # Fallback employee for unresolved emails
    FALLBACK_EMP = email_to_emp.get("data@hawaiifarming.com") or email_to_emp.get("admin@hawaiifarming.com")

    # Build item name -> id lookup
    items = paginate_select(supabase, "invnt_item", "name, invnt_category_id, burn_uom, order_uom, burn_per_order, farm_name, is_active")
    item_by_name = {}
    for it in items:
        item_by_name[it["name"].lower()] = it

    # Build vendor name -> id lookup
    vendors = paginate_select(supabase, "invnt_vendor", "name")
    vendor_by_name = {v["name"].lower(): v["name"] for v in vendors}

    # UOM mapping
    UOM_MAP = {
        "seeds": "seed", "pieces": "piece", "bags": "bag", "boxes": "box",
        "pounds": "pound", "rolls": "roll", "bottles": "bottle",
        "gallons": "gallon", "trays": "tray", "packs": "pack",
        "labels": "label", "cases": "case", "drums": "drum",
        "clips": "clip", "kits": "kit", "pallets": "pallet",
        "units": "unit", "dozen": "dozen", "lids": "lid",
        "quarts": "quart", "ounces": "ounce", "grams": "gram",
        "feet": "feet", "meters": "meter", "impressions": "impression",
        "blades": "blade", "reactions": "reactions", "cubes": "cubes",
        "fluid ounces": "fluid_ounce", "fluid_ounces": "fluid_ounce",
        "ml": "milliliter", "milliliters": "milliliter",
        "seed": "seed", "piece": "piece", "bag": "bag", "box": "box",
        "pound": "pound", "roll": "roll", "bottle": "bottle",
        "gallon": "gallon", "tray": "tray", "pack": "pack",
        "label": "label", "case": "case", "drum": "drum",
        "clip": "clip", "kit": "kit", "pallet": "pallet",
        "unit": "unit", "lid": "lid", "quart": "quart",
        "ounce": "ounce", "gram": "gram", "blade": "blade",
        "impression": "impression", "count": "count",
    }

    def map_uom(val):
        v = str(val).strip().lower()
        return UOM_MAP.get(v, v) if v else None

    # ========================================
    # PART 1: Historical POs from invnt_item_po
    # ========================================
    sheet = gc.open_by_key(SHEET_ID)
    ws_po = sheet.worksheet("invnt_item_po")
    po_records = ws_po.get_all_records()

    # Status mapping
    STATUS_MAP = {
        "received": "received", "ordered": "ordered", "cancelled": "cancelled",
        "partial": "partial", "approved": "approved", "requested": "requested",
    }

    po_rows = []
    lot_rows = []
    received_rows = []
    lot_seen = set()

    for r_raw in po_records:
        r = {str(k).strip(): v for k, v in r_raw.items()}

        item_name = proper_case(r.get("ItemName", ""))
        if not item_name:
            continue

        # Resolve item
        item = item_by_name.get(item_name.lower(), {})
        item_id = item.get("name")

        # Status
        raw_status = str(r.get("OrderStatus", "")).strip().lower()
        status = STATUS_MAP.get(raw_status, "received")

        # Vendor
        vendor_name = str(r.get("SupplierName", "")).strip()
        vendor_id = vendor_by_name.get(vendor_name.lower()) if vendor_name else None

        # Employee lookups
        ordered_by_email = str(r.get("OrderedBy", "")).strip().lower()
        received_by_email = str(r.get("ReceivedBy", "")).strip().lower()
        ordered_by = email_to_emp.get(ordered_by_email)
        received_by = email_to_emp.get(received_by_email)

        # UOMs
        order_uom = map_uom(r.get("OrderUnits", ""))
        burn_uom = map_uom(r.get("BurnUnits", ""))
        received_uom = map_uom(r.get("ReceivedUnits", ""))

        # PO row
        po = {
            "org_id": ORG_ID,
            "farm_name": item.get("farm_name"),
            "request_type": "inventory_item",
            "invnt_category_id": item.get("invnt_category_id") or "packing",
            "invnt_item_name": item_id,
            "item_name": item_name,
            "burn_uom": burn_uom or item.get("burn_uom") or order_uom or "unit",
            "order_uom": order_uom or item.get("order_uom") or burn_uom or "unit",
            "order_quantity": safe_numeric(r.get("OrderedQuantity", "")),
            "burn_per_order": safe_numeric(r.get("BurnPerReceivedUnits", "")) or item.get("burn_per_order", 0),
            "total_cost": safe_numeric(r.get("TotalCost", "")) or None,
            "is_freight_included": parse_bool(r.get("PriceIncludesFreight", "")),
            "invnt_vendor_name": vendor_id,
            "expected_delivery_date": parse_date(r.get("ExpectedArrivalDate", "")),
            "request_photos": [],
            "status": status,
            "requested_at": parse_timestamp(r.get("OrderPlacedDate", "")),
            "requested_by": ordered_by or FALLBACK_EMP,
            "reviewed_at": parse_timestamp(r.get("OrderPlacedDate", "")),
            "reviewed_by": ordered_by or FALLBACK_EMP,
            "ordered_at": parse_timestamp(r.get("OrderPlacedDate", "")),
            "ordered_by": ordered_by or FALLBACK_EMP,
        }
        po_row = audit(po)
        po_row["created_by"] = ordered_by_email or AUDIT_USER
        po_row["updated_by"] = received_by_email or ordered_by_email or AUDIT_USER
        po_rows.append(po_row)
        po_index = len(po_rows) - 1

        # Lot — only migrate lots for active items
        lot_number = str(r.get("ItemLot", "")).strip()
        lot_id = None
        if lot_number and lot_number.upper() != "NA" and item_id:
            # Check if item is active
            item_obj = item_by_name.get(item_name.lower(), {})
            if item_obj.get("is_active", True):
                lot_key = to_id(lot_number)
                lot_id = lot_key
                if lot_key not in lot_seen:
                    lot_seen.add(lot_key)
                    lot_row = audit({
                        "id": lot_id,
                        "org_id": ORG_ID,
                        "farm_name": item.get("farm_name"),
                        "invnt_item_name": item_id,
                        "lot_number": lot_number,
                        "lot_expiry_date": parse_date(r.get("ExpiryDate", "")),
                    })
                    lot_row["created_by"] = received_by_email or ordered_by_email or AUDIT_USER
                    lot_row["updated_by"] = received_by_email or ordered_by_email or AUDIT_USER
                    lot_rows.append(lot_row)

        # Received record (only if status implies receipt)
        if status in ("received", "partial"):
            arrival = parse_date(r.get("ArrivalDate", ""))
            if arrival:
                photo = str(r.get("DeliveryPhoto", "")).strip()
                # Normalize legacy sheet paths to the unified 'images/' bucket layout
                if photo:
                    photo = photo.replace("Images/Orders/", "images/invnt_po_received/")
                    photo = photo.replace("images/invnt/", "images/invnt_po_received/")
                recv = {
                    "org_id": ORG_ID,
                    "farm_name": item.get("farm_name"),
                    "received_date": arrival,
                    "received_uom": received_uom or order_uom,
                    "received_quantity": safe_numeric(r.get("ReceivedQuantity", "")),
                    "burn_per_received": safe_numeric(r.get("BurnPerReceivedUnits", "")),
                    "invnt_lot_id": lot_id,
                    "fsafe_delivery_truck_clean": parse_bool(r.get("TruckCleanIntactAndPestFree", "")),
                    "fsafe_delivery_acceptable": str(r.get("ItemCondition", "")).strip().lower() == "acceptable",
                    "received_photos": [photo] if photo else [],
                    "received_at": parse_timestamp(r.get("LastUpdateDateTime", "")),
                    "received_by": received_by,
                }
                recv_row = audit(recv)
                recv_row["created_by"] = received_by_email or AUDIT_USER
                recv_row["updated_by"] = received_by_email or AUDIT_USER
                received_rows.append((po_index, recv_row))

    # ========================================
    # PART 2: Active requests from proc_requests
    # ========================================
    proc_ws = gc.open_by_key("1EFgT0XyBlUe10ENVkm4-_bb4uSPyd9hPbCIzD-RKNRA").worksheet("proc_requests")
    proc_records = proc_ws.get_all_records()

    URGENCY_MAP = {
        "today": "today", "2 days": "2_days", "1 week": "7_days",
        "2 weeks": "not_urgent", "month": "not_urgent",
    }

    PROC_STATUS_MAP = {
        "requested": "requested", "ordered": "ordered", "completed": "received",
    }

    for r in proc_records:
        req_type = str(r.get("request_type", "")).strip()
        if req_type == "Travel":
            continue  # Handled in HR migration

        # Map request type
        if req_type == "Inventory Item":
            mapped_type = "inventory_item"
        else:
            mapped_type = "non_inventory_item"

        # Item name
        item_name = proper_case(r.get("item_name", "")) or proper_case(r.get("general_item_name", ""))
        if not item_name:
            continue

        # Resolve item for inventory items
        item = item_by_name.get(item_name.lower(), {}) if mapped_type == "inventory_item" else {}
        item_id = item.get("name") if mapped_type == "inventory_item" else None

        # Vendor
        vendor_name = str(r.get("manufacturer_vendor", "")).strip()
        vendor_id = vendor_by_name.get(vendor_name.lower()) if vendor_name else None

        # Employee
        created_email = str(r.get("created_by", "")).strip().lower()
        updated_email = str(r.get("updated_by", "")).strip().lower()
        requested_by = email_to_emp.get(created_email)
        reviewed_by = email_to_emp.get(updated_email)

        # Status
        raw_status = str(r.get("request_status", "")).strip().lower()
        status = PROC_STATUS_MAP.get(raw_status, "requested")

        # Photos
        # Normalize legacy sheet paths to the unified 'images/' bucket layout
        photos = []
        for col in ["request_image_01_url", "request_image_02_url", "request_image_03_url"]:
            p = str(r.get(col, "")).strip()
            if p:
                p = p.replace("proc_requests_Images/", "images/invnt_po/")
                p = p.replace("images/invnt/", "images/invnt_po/")
                photos.append(p)

        # UOMs: non-inventory items use "each", inventory items use item UOMs
        if mapped_type == "non_inventory_item":
            po_burn_uom = "each"
            po_order_uom = "each"
            po_burn_per_order = 1
        else:
            po_burn_uom = item.get("burn_uom") or "unit"
            po_order_uom = item.get("order_uom") or "unit"
            po_burn_per_order = item.get("burn_per_order", 0)

        # For completed orders: updated_by is the orderer/reviewer, created_by is the receiver
        po = {
            "org_id": ORG_ID,
            "farm_name": item.get("farm_name"),
            "request_type": mapped_type,
            "urgency_level": URGENCY_MAP.get(str(r.get("urgency_level", "")).strip().lower()),
            "invnt_category_id": item.get("invnt_category_id") or "maintenance",
            "invnt_item_name": item_id,
            "item_name": item_name,
            "burn_uom": po_burn_uom,
            "order_uom": po_order_uom,
            "order_quantity": safe_numeric(r.get("request_quantity", "")),
            "burn_per_order": po_burn_per_order,
            "invnt_vendor_name": vendor_id,
            "expected_delivery_date": parse_date(r.get("expected_delivery_date", "")),
            "notes": str(r.get("request_notes", "")).strip() or None,
            "request_photos": photos,
            "status": status,
            "requested_at": parse_timestamp(r.get("created_on", "")),
            "requested_by": requested_by or FALLBACK_EMP,
            "reviewed_at": parse_timestamp(r.get("updated_on", "")) if status != "requested" else None,
            "reviewed_by": reviewed_by if status != "requested" else None,
            "ordered_at": parse_timestamp(r.get("updated_on", "")) if status in ("ordered", "received") else None,
            "ordered_by": reviewed_by if status in ("ordered", "received") else None,
        }
        po_row = audit(po)
        po_row["created_by"] = created_email or AUDIT_USER
        po_row["updated_by"] = updated_email or created_email or AUDIT_USER
        po_rows.append(po_row)

    # ========================================
    # INSERT: lots first, then POs with received
    # ========================================

    # Insert lots
    if lot_rows:
        insert_rows(supabase, "invnt_lot", lot_rows)

    # Insert POs in batches and collect returned IDs
    print(f"\n--- invnt_po ---")
    po_ids = []
    for i in range(0, len(po_rows), 100):
        batch = po_rows[i:i + 100]
        result = supabase.table("invnt_po").insert(batch).execute()
        for row in result.data:
            po_ids.append(row["id"])
    print(f"  Inserted {len(po_ids)} rows")

    # Insert received records with resolved PO IDs
    recv_to_insert = []
    for po_idx, recv in received_rows:
        if po_idx < len(po_ids):
            recv["invnt_po_id"] = po_ids[po_idx]
            recv_to_insert.append(recv)
    if recv_to_insert:
        insert_rows(supabase, "invnt_po_received", recv_to_insert)


def migrate_invnt_onhand(supabase, gc):
    """Migrate on-hand inventory snapshots from invnt_item_onhand sheet."""
    ws = gc.open_by_key(SHEET_ID).worksheet("invnt_item_onhand")
    records = ws.get_all_records()

    # Build item name -> record lookup from Supabase
    items = paginate_select(supabase, "invnt_item", "name, farm_name, burn_uom, onhand_uom, burn_per_onhand, is_active")
    item_by_name = {}
    for it in items:
        item_by_name[it["name"].lower()] = it

    # Build lot lookup: lot_number -> lot_id (only active-item lots)
    lots = paginate_select(supabase, "invnt_lot", "id, lot_number")
    lot_by_number = {}
    for lot in lots:
        lot_by_number[lot["lot_number"].lower()] = lot["id"]

    # UOM mapping
    UOM_MAP = {
        "seeds": "seed", "pieces": "piece", "bags": "bag", "boxes": "box",
        "pounds": "pound", "rolls": "roll", "bottles": "bottle",
        "gallons": "gallon", "trays": "tray", "packs": "pack",
        "labels": "label", "cases": "case", "drums": "drum",
        "clips": "clip", "kits": "kit", "pallets": "pallet",
        "units": "unit", "dozen": "dozen", "lids": "lid",
        "quarts": "quart", "ounces": "ounce", "grams": "gram",
        "feet": "feet", "meters": "meter", "impressions": "impression",
        "blades": "blade", "reactions": "reactions", "cubes": "cubes",
        "fluid ounces": "fluid_ounce", "fluid_ounces": "fluid_ounce",
        "ml": "milliliter", "milliliters": "milliliter",
        "seed": "seed", "piece": "piece", "bag": "bag", "box": "box",
        "pound": "pound", "roll": "roll", "bottle": "bottle",
        "gallon": "gallon", "tray": "tray", "pack": "pack",
        "label": "label", "case": "case", "drum": "drum",
        "clip": "clip", "kit": "kit", "pallet": "pallet",
        "unit": "unit", "lid": "lid", "quart": "quart",
        "ounce": "ounce", "gram": "gram", "blade": "blade",
        "impression": "impression", "count": "count", "each": "each",
        "lb": "pound", "oz": "ounce", "g": "gram", "kg": "kilogram",
        "ft": "feet", "fl oz": "fluid_ounce",
    }

    def map_uom(val):
        v = str(val).strip().lower()
        return UOM_MAP.get(v, v) if v else None

    rows = []
    skipped = 0

    for r_raw in records:
        r = {str(k).strip(): v for k, v in r_raw.items()}

        item_name = str(r.get("ItemName", "")).strip()
        if not item_name:
            continue

        # Resolve item
        item = item_by_name.get(item_name.lower())
        if not item:
            skipped += 1
            continue

        # Onhand date
        onhand_date = parse_date(r.get("OnhandReportedDate", ""))
        if not onhand_date:
            skipped += 1
            continue

        # UOM — use OnhandUnits from sheet, fall back to item's onhand_uom
        onhand_uom = map_uom(r.get("OnhandUnits", "")) or item.get("onhand_uom")

        # Quantity
        onhand_quantity = safe_numeric(r.get("OnhandQuantity", ""))

        # Burn per onhand
        burn_per_onhand = safe_numeric(r.get("BurnPerOnhandUnit", ""))

        # Lot
        lot_number = str(r.get("ItemLot", "")).strip()
        lot_id = None
        if lot_number and lot_number.upper() != "NA":
            lot_id = lot_by_number.get(lot_number.lower())

        # Reporter
        reported_by_email = str(r.get("ReportedBy", "")).strip().lower()
        reported_at = parse_timestamp(r.get("ReportedDateTime", ""))

        # Burn UOM from legacy BurnUnits, fall back to item's burn_uom
        burn_uom = map_uom(r.get("BurnUnits", "")) or item.get("burn_uom")

        row = audit({
            "org_id": ORG_ID,
            "farm_name": item.get("farm_name"),
            "invnt_item_name": item["name"],
            "onhand_date": onhand_date,
            "burn_uom": burn_uom,
            "onhand_uom": onhand_uom,
            "onhand_quantity": onhand_quantity,
            "burn_per_onhand": burn_per_onhand,
            "invnt_lot_id": lot_id,
            "created_at": reported_at,
            "updated_at": reported_at,
        })
        row["created_by"] = reported_by_email or AUDIT_USER
        row["updated_by"] = reported_by_email or AUDIT_USER
        rows.append(row)

    insert_rows(supabase, "invnt_onhand", rows)
    if skipped:
        print(f"  Skipped {skipped} rows (unknown item or missing date)")


def migrate_grow_spray_compliance(supabase, gc):
    """Migrate chemical/fertilizer compliance data from invnt_item_details sheet."""
    ws = gc.open_by_key(SHEET_ID).worksheet("invnt_item_details")
    records = ws.get_all_records()

    # Build item name -> record lookup
    items = paginate_select(supabase, "invnt_item", "name, burn_uom, farm_name")
    item_by_name = {}
    for it in items:
        item_by_name[it["name"].lower()] = it

    # Farm mapping
    FARM_MAP = {
        "lettuce": "Lettuce",
        "cuke": "Cuke",
        "cucumber": "Cuke",
    }

    # UOM mapping
    UOM_MAP = {
        "fluid_ounces": "fluid_ounce", "fluid ounces": "fluid_ounce",
        "ounces": "ounce", "oz": "ounce", "ounce": "ounce",
        "pounds": "pound", "lb": "pound", "pound": "pound",
        "grams": "gram", "g": "gram", "gram": "gram",
        "gallons": "gallon", "gallon": "gallon",
        "quarts": "quart", "quart": "quart",
        "ml": "milliliter", "milliliters": "milliliter",
        "pints": "quart", "pint": "quart",
        "liters": "liter", "liter": "liter",
    }

    def map_uom(val):
        v = str(val).strip().lower()
        return UOM_MAP.get(v, v) if v else None

    rows = []
    skipped_no_label = 0
    unresolved_items = set()
    unresolved_farms = set()

    for r_raw in records:
        r = {str(k).strip(): v for k, v in r_raw.items()}

        # Only require LabelLink — that's the regulatory document we care
        # about preserving. Everything else may be missing/null and the row
        # still imports. Schema columns (FKs and other NOT NULLs) for the
        # missing fields have been relaxed to nullable in
        # 20260401000056_grow_spray_compliance.sql to support this.
        label_url = str(r.get("LabelLink", "")).strip()
        if not label_url:
            skipped_no_label += 1
            continue

        item_name = str(r.get("ItemName", "")).strip()
        item = item_by_name.get(item_name.lower()) if item_name else None
        if item_name and not item:
            unresolved_items.add(item_name)
            print(f"  WARN: Unknown item '{item_name}' — inserting with NULL invnt_item_name")

        # Farm — try sheet, fall back to item, else None
        farm_raw = str(r.get("Farm", "")).strip().lower()
        farm_name = FARM_MAP.get(farm_raw) or (item.get("farm_name") if item else None)
        if not farm_name:
            unresolved_farms.add(farm_raw or "(blank)")

        # Registration — preserve when present, null when missing
        epa_reg = str(r.get("RegistrationNumber", "")).strip() or None

        # Application method -> JSONB array (empty list when missing)
        app_method = proper_case(r.get("ApplicationMethod", ""))
        application_method = [app_method] if app_method else []

        # Target -> JSONB array (empty list when missing)
        target = proper_case(r.get("Target", ""))
        target_pest_disease = [target] if target else []

        # UOM and quantity — null when missing rather than defaulting
        app_uom = map_uom(r.get("PerAcreUnits", ""))
        max_qty_raw = str(r.get("QuantityPerAcre", "")).strip()
        max_qty = safe_numeric(max_qty_raw) if max_qty_raw else None

        # Burn UOM from item, fall back to app_uom, else null
        burn_uom = (item.get("burn_uom") if item else None) or app_uom

        # Application per burn — schema is NOT NULL; default to 1 when blank
        # (means "one application unit per burn unit" — neutral fallback)
        app_per_burn_raw = str(r.get("MaximumUsagePerSeason", "")).strip()
        app_per_burn = safe_numeric(app_per_burn_raw) if app_per_burn_raw else 1

        # Dates — null when missing
        label_date = parse_date(r.get("LabelDate", ""))

        # PHI / REI — schema is NOT NULL; default to 0 when blank
        # (means "no waiting period required" — neutral fallback)
        phi_raw = str(r.get("PHIDays", "")).strip()
        rei_raw = str(r.get("REIHours", "")).strip()
        phi_days = int(safe_numeric(phi_raw)) if phi_raw else 0
        rei_hours = int(safe_numeric(rei_raw)) if rei_raw else 0

        # Audit
        updated_by_email = str(r.get("LastUpdateBy", "")).strip().lower()
        updated_at = parse_timestamp(r.get("LastUpdateDateTime", ""))

        row = {
            "org_id": ORG_ID,
            "farm_name": farm_name,
            "invnt_item_name": item["name"] if item else None,
            "epa_registration": epa_reg,
            "phi_days": phi_days,
            "rei_hours": rei_hours,
            "application_method": application_method,
            "target_pest_disease": target_pest_disease,
            "application_uom": app_uom,
            "maximum_quantity_per_acre": max_qty,
            "burn_uom": burn_uom,
            "application_per_burn": app_per_burn,
            "label_date": label_date,
            "effective_date": label_date,
            "external_label_url": label_url,
            "created_at": updated_at,
            "updated_at": updated_at,
            "created_by": updated_by_email or AUDIT_USER,
            "updated_by": updated_by_email or AUDIT_USER,
        }
        rows.append(row)

    insert_rows(supabase, "grow_spray_compliance", rows)
    if skipped_no_label:
        print(f"  Skipped {skipped_no_label} rows with no LabelLink")
    if unresolved_items:
        print(f"  Inserted with NULL invnt_item_name ({len(unresolved_items)} unique unknown items): {sorted(unresolved_items)[:5]}...")
    if unresolved_farms:
        print(f"  Inserted with NULL farm_name ({len(unresolved_farms)} unique unknown farms): {sorted(unresolved_farms)}")


def migrate_grow_lettuce_seed_mix(supabase, gc):
    """Migrate seed mix recipes from invt_mix_seed_ratio sheet.

    Each unique item_name becomes a grow_lettuce_seed_mix row.
    Each seed within that mix becomes a grow_lettuce_seed_mix_item row.
    """
    ws = gc.open_by_key(SHEET_ID).worksheet("invt_mix_seed_ratio")
    records = ws.get_all_records()

    print(f"\nProcessing {len(records)} seed mix ratio rows...")

    # Build invnt_item lookup — name is now the PK
    items = paginate_select(supabase, "invnt_item", "name")
    item_by_name = {it["name"].lower(): it["name"] for it in items}

    # Group by mix name
    mixes = {}
    for r in records:
        mix_name = str(r.get("item_name", "")).strip()
        if not mix_name:
            continue
        if mix_name not in mixes:
            mixes[mix_name] = {
                "created_by": str(r.get("created_by", "")).strip().lower() or AUDIT_USER,
                "items": [],
            }
        seed_name = str(r.get("seed_name", "")).strip()
        ratio_str = str(r.get("ratio", "")).strip().replace("%", "")
        ratio = safe_numeric(ratio_str) / 100 if ratio_str else 0

        item_id = item_by_name.get(seed_name.lower())
        if not item_id:
            print(f"  SKIP: Unknown seed item '{seed_name}' in mix '{mix_name}'")
            continue

        mixes[mix_name]["items"].append({
            "invnt_item_name": item_id,
            "percentage": round(ratio, 4),
            "created_by": str(r.get("created_by", "")).strip().lower() or AUDIT_USER,
        })

    print(f"  Found {len(mixes)} unique mixes")

    # Insert mix headers
    mix_rows = []
    for mix_name in sorted(mixes.keys()):
        info = mixes[mix_name]
        mix_rows.append({

            "org_id": ORG_ID,
            "farm_name": "Lettuce",
            "name": proper_case(mix_name),
            "created_by": info["created_by"],
            "updated_by": info["created_by"],
        })

    inserted_mixes = insert_rows(supabase, "grow_lettuce_seed_mix", mix_rows)

    # Insert mix items — FK points at grow_lettuce_seed_mix.name (proper-case)
    item_rows = []
    for mix_name in sorted(mixes.keys()):
        info = mixes[mix_name]
        for item in info["items"]:
            item_rows.append({
                "org_id": ORG_ID,
                "farm_name": "Lettuce",
                "grow_lettuce_seed_mix_name": proper_case(mix_name),
                "invnt_item_name": item["invnt_item_name"],
                "percentage": item["percentage"],
                "created_by": item["created_by"],
                "updated_by": item["created_by"],
            })

    insert_rows(supabase, "grow_lettuce_seed_mix_item", item_rows)


def main():
    if not SUPABASE_KEY:
        print("ERROR: Set SUPABASE_SERVICE_KEY in .env or environment")
        return

    supabase = create_client(SUPABASE_URL, SUPABASE_KEY)
    gc = get_sheets()

    print("=" * 60)
    print("INVENTORY MIGRATION")
    print("=" * 60)

    # Clear in reverse FK order
    print("Clearing tables...")
    for t in ["grow_spray_compliance", "invnt_onhand", "invnt_po_received", "invnt_lot", "invnt_po",
              "grow_lettuce_seed_mix_item", "grow_lettuce_seed_mix",
              "maint_request_invnt_item", "pack_dryer_result",
              "invnt_item", "invnt_category", "invnt_vendor"]:
        try:
            supabase.table(t).delete().neq("org_id", "___never___").execute()
        except Exception:
            pass
    # Clear only maintenance_storage sites (don't touch org.py sites)
    try:
        supabase.table("org_site").delete().eq("org_site_subcategory_id", "maintenance_storage").execute()
    except Exception:
        pass
    # Clear the maintenance_storage subcategory
    try:
        supabase.table("org_site_category").delete().eq("id", "maintenance_storage").execute()
    except Exception:
        pass
    print("  All cleared")

    migrate_invnt_vendor(supabase, gc)
    migrate_invnt_category(supabase, gc)
    migrate_storage_sites(supabase, gc)
    migrate_invnt_item(supabase, gc)
    migrate_invnt_po(supabase, gc)
    migrate_invnt_onhand(supabase, gc)
    migrate_grow_spray_compliance(supabase, gc)
    migrate_grow_lettuce_seed_mix(supabase, gc)

    print("\n" + "=" * 60)
    print("DONE")
    print("=" * 60)


if __name__ == "__main__":
    main()
