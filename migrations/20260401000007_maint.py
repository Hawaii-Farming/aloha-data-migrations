"""
Migrate Maintenance Data
========================
Migrates maint_req from legacy Google Sheets to Supabase.

Source: https://docs.google.com/spreadsheets/d/1e7AuQAOpKAHpmvizIgBNyUk42GscXNpz96hFX8C8uio
  - maint_sites: 168 maintenance site names → org_site
  - maint_req: 8344 maintenance requests → maint_request, maint_request_invnt_item, maint_request_photo

Usage:
    python scripts/migrations/20260401000007_maint.py

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
SHEET_ID = "1e7AuQAOpKAHpmvizIgBNyUk42GscXNpz96hFX8C8uio"


def to_id(name: str) -> str:
    """Convert a display name to a TEXT PK."""
    return re.sub(r"[^a-z0-9_]+", "_", name.lower()).strip("_") if name else ""


def proper_case(val):
    """Normalize a string to title case, stripping extra whitespace."""
    if not val or not str(val).strip():
        return val
    return str(val).strip().title()


def insert_rows(supabase, table: str, rows: list):
    """Insert rows into a table. Returns inserted data."""
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
    """Parse a boolean value from sheet text."""
    return str(val).strip().upper() in ("TRUE", "YES", "1")


def audit(row: dict) -> dict:
    """Add audit fields to a row."""
    row["created_by"] = AUDIT_USER
    row["updated_by"] = AUDIT_USER
    return row


def get_sheets():
    """Connect to Google Sheets."""
    scopes = ["https://www.googleapis.com/auth/spreadsheets.readonly"]
    creds = Credentials.from_service_account_file("credentials.json", scopes=scopes)
    return gspread.authorize(creds)


def migrate_maint_sites(supabase):
    """Create org_site entries for maintenance sites, mapped to proper categories.

    Each legacy maint_site is explicitly mapped to:
      - An existing org_site ID (if it overlaps with growing/housing/storage sites), OR
      - A new org_site with the correct category (growing, packing, housing, storage, other)

    Review and adjust the mappings below before running.
    """

    # =====================================================================
    # EXPLICIT SITE MAPPING
    # =====================================================================
    # Format: "Legacy SiteName" → (org_site_id, category, subcategory)
    #   - If org_site_id matches an existing site, the maint_req will link to it
    #   - If it's a new site, it will be created with the given category
    #   - Set to None to skip the site (won't be created or linked)
    #
    # Categories: growing, greenhouse, nursery, pond, row, growing_room,
    #             packing, packing_room, housing, room,
    #             storage, warehouse, chemical_storage, cold_storage,
    #             food_safety, pest_trap, other
    # =====================================================================

    SITE_MAP = {
        # Format: "Legacy SiteName" → (org_site_id, category_id, subcategory_id)
        #   category_id    = org_site_category row where sub_category_name IS NULL
        #   subcategory_id = org_site_category row where sub_category_name IS NOT NULL (or None)

        # ----- GROWING: Cuke greenhouses (JTL) → existing sites 01-08 -----
        "GH 01":                ("01",                      "growing",   "greenhouse"),
        "GH 01 Storage":        ("gh_01_storage",           "storage",   None),       # NEW
        "GH 02":                ("02",                      "growing",   "greenhouse"),
        "GH 03":                ("03",                      "growing",   "greenhouse"),
        "GH 04":                ("04",                      "growing",   "greenhouse"),
        "GH 05":                ("05",                      "growing",   "greenhouse"),
        "GH 06":                ("06",                      "growing",   "greenhouse"),
        "GH 07":                ("07",                      "growing",   "greenhouse"),
        "GH 08":                ("08",                      "growing",   "greenhouse"),

        # ----- GROWING: Lettuce greenhouses (BIP) → existing sites -----
        "GH HI":                ("hi",                      "growing",   "greenhouse"),
        "GH HK":                ("hk",                      "growing",   "greenhouse"),
        "GH KH":                ("hk",                      "growing",   "greenhouse"),  # duplicate of hk
        "GH KO":                ("ko",                      "growing",   "greenhouse"),
        "GH WA":                ("wa",                      "growing",   "greenhouse"),
        "Cravo GH":             ("cravo_gh",                "other",     None),       # NEW
        "Lettuce GH":           ("gh",                      "growing",   None),       # existing parent

        # ----- GROWING: Lettuce ponds P1-P7 → existing sites -----
        "Lettuce P1":           ("p1",                      "growing",   "pond"),
        "Lettuce P2":           ("p2",                      "growing",   "pond"),
        "Lettuce P3":           ("p3",                      "growing",   "pond"),
        "Lettuce P4":           ("p4",                      "growing",   "pond"),
        "Lettuce P5":           ("p5",                      "growing",   "pond"),
        "Lettuce P6":           ("p6",                      "growing",   "pond"),
        "Lettuce P7":           ("p7",                      "growing",   "pond"),
        # ----- GROWING: Nursery -----
        "Nursery":              ("nursery",                 "growing",   "nursery"),   # NEW
        "Nursery (E)":          ("nursery_e",               "growing",   "nursery"),   # NEW
        "Nursery (W)":          ("nursery_w",               "growing",   "nursery"),   # NEW

        # ----- FERTIGATION: Rooms within growing sites -----
        "Fert BIP":             ("fert_bip",                "growing",   "growing_room"),  # NEW: parent=bip
        "Fert JTL":             ("fert_jtl",                "growing",   "growing_room"),  # NEW: parent=jtl
        "Lettuce Fert Station": ("lettuce_fert_station",    "growing",   "growing_room"),  # NEW: parent=gh

        # ----- PACKING: BIP packhouse (parent=bip, farm=cuke) -----
        "BIP PH":               ("bip_ph",                  "packing",   "packing_room"),  # NEW
        "BIP Breakroom":        ("bip_breakroom",           "packing",   "packing_other"),  # NEW
        "BIP office":           ("bip_office",              "packing",   "packing_other"),  # NEW
        "BIP Cold Storage #1":  ("bip_cold_storage_1",      "storage",   "cold_storage"),  # NEW
        "BIP Cold Storage #2":  ("bip_cold_storage_2",      "storage",   "cold_storage"),  # NEW

        # ----- PACKING: Lettuce packhouse (parent=gh, farm=lettuce) -----
        "Lettuce PH":           ("lettuce_ph",              "packing",   "packing_room"),  # NEW
        "Lettuce Packing Room": ("lettuce_packing_room",    "packing",   "packing_room"),  # NEW
        "Lettuce PH Cold Storage":  ("lettuce_ph_cold_storage", "storage", "cold_storage"),  # NEW
        "Lettuce PH Utility Closet": ("lettuce_ph_utility_closet", "packing", "packing_other"),  # NEW
        "Lettuce Breezeway":    ("lettuce_breezeway",       "packing",   "packing_other"),  # NEW
        "Lettuce Dry side storage": ("lettuce_dry_side_storage", "storage", None),    # NEW
        "Lettuce Germination Room": ("lettuce_germination_room", "growing", "growing_room"),  # NEW: under gh

        # ----- STANDALONE: Lettuce lab buildings (housing/room, no parent) -----
        "Lettuce Lab/Office":   ("lettuce_lab_office",      "housing",   "room"),     # NEW: housing/room standalone
        "New Lab/Lettuce Office": ("new_lab_lettuce_office", "housing",  "room"),     # NEW: housing/room standalone

        # ----- HOUSING: Houses → existing Duplex site or new room sites -----
        "Duplex":                           ("duplex",                      "housing",  None),  # existing
        "Duplex - Downstairs Bathroom 1":   ("duplex_downstairs_bathroom_1", "housing", "room"),  # NEW
        "Duplex - Downstairs Bathroom 2":   ("duplex_downstairs_bathroom_2", "housing", "room"),  # NEW
        "Duplex - Downstairs Bedroom 1":    ("duplex_downstairs_bedroom_1",  "housing", "room"),  # NEW
        "Duplex - Downstairs Bedroom 2":    ("duplex_downstairs_bedroom_2",  "housing", "room"),  # NEW
        "Duplex - Exterior":                ("duplex_exterior",              "housing",  "housing_other"),  # NEW
        "Duplex - Living Room":             ("duplex_living_room",           "housing", "room"),  # NEW
        "Duplex - Downstairs Living Room":  ("duplex_downstairs_living_room", "housing", "room"),  # NEW
        "Duplex - Upstairs Living Room":    ("duplex_upstairs_living_room",   "housing", "room"),  # NEW
        "Duplex - Upstairs Bathroom 1":     ("duplex_upstairs_bathroom_1",   "housing", "room"),  # NEW
        "Duplex - Upstairs Bathroom 2":     ("duplex_upstairs_bathroom_2",   "housing", "room"),  # NEW
        "Duplex - Upstairs Bedroom 1":      ("duplex_upstairs_bedroom_1",    "housing", "room"),  # NEW
        "Duplex - Upstairs Bedroom 2":      ("duplex_upstairs_bedroom_2",    "housing", "room"),  # NEW
        "Duplex - Upstairs Bedroom 3":      ("duplex_upstairs_bedroom_3",    "housing", "room"),  # NEW
        "Duplex downstairs kitchen":        ("duplex_downstairs_kitchen",    "housing", "room"),  # NEW
        "Duplex upstairs kitchen":          ("duplex_upstairs_kitchen",      "housing", "room"),  # NEW
        "House#1":                  ("house_1",             "housing",      None),     # NEW
        "House#1 - Bathroom 1":     ("house_1_bathroom_1",  "housing",     "room"),    # NEW
        "House#1 - Bathroom 2":     ("house_1_bathroom_2",  "housing",     "room"),    # NEW
        "House#1 - Bedroom 1":      ("house_1_bedroom_1",   "housing",     "room"),    # NEW
        "House#1 - Bedroom 2":      ("house_1_bedroom_2",   "housing",     "room"),    # NEW
        "House#1 - Bedroom 3":      ("house_1_bedroom_3",   "housing",     "room"),    # NEW
        "House#1 - Bedroom 4":      ("house_1_bedroom_4",   "housing",     "room"),    # NEW
        "House#1 - Bedroom 5":      ("house_1_bedroom_5",   "housing",     "room"),    # NEW
        "House#1 - Exterior":       ("house_1_exterior",    "housing",     "housing_other"),  # NEW
        "House#1 - Garage":         ("house_1_garage",      "housing",     "room"),    # NEW
        "House#1 - Kitchen":        ("house_1_kitchen",     "housing",     "room"),    # NEW
        "House#1 - Living Room":    ("house_1_living_room", "housing",     "room"),    # NEW
        "House#2":                  ("house_2",             "housing",      None),     # NEW
        "House#2 - Bathroom 1":     ("house_2_bathroom_1",  "housing",     "room"),    # NEW
        "House#2 - Bathroom 2":     ("house_2_bathroom_2",  "housing",     "room"),    # NEW
        "House#2 - Bedroom 1":      ("house_2_bedroom_1",   "housing",     "room"),    # NEW
        "House#2 - Bedroom 2":      ("house_2_bedroom_2",   "housing",     "room"),    # NEW
        "House#2 - Bedroom 3":      ("house_2_bedroom_3",   "housing",     "room"),    # NEW
        "House#2 - Bedroom 4":      ("house_2_bedroom_4",   "housing",     "room"),    # NEW
        "House#2 - Exterior":       ("house_2_exterior",    "housing",     "housing_other"),  # NEW
        "House#2 - Garage":         ("house_2_garage",      "housing",     "room"),    # NEW
        "House#2 - Kitchen":        ("house_2_kitchen",     "housing",     "room"),    # NEW
        "House#2 - Living Room":    ("house_2_living_room", "housing",     "room"),    # NEW
        "House#3":                  ("house_3",             "housing",      None),     # NEW
        "House#3 - Bathroom 1":     ("house_3_bathroom_1",  "housing",     "room"),    # NEW
        "House#3 - Bedroom 1":      ("house_3_bedroom_1",   "housing",     "room"),    # NEW
        "House#3 - Bedroom 2":      ("house_3_bedroom_2",   "housing",     "room"),    # NEW
        "House#3 - Exterior":       ("house_3_exterior",    "housing",     "housing_other"),  # NEW
        "House#3 - Kitchen":        ("house_3_kitchen",     "housing",     "room"),    # NEW
        "House#3 - Living Room":    ("house_3_living_room", "housing",     "room"),    # NEW
        "House#4":                  ("house_4",             "housing",      None),     # NEW
        "House#4 - Bathroom 1":     ("house_4_bathroom_1",  "housing",     "room"),    # NEW
        "House#4 - Bedroom 1":      ("house_4_bedroom_1",   "housing",     "room"),    # NEW
        "House#4 - Bedroom 2":      ("house_4_bedroom_2",   "housing",     "room"),    # NEW
        "House#4 - Exterior":       ("house_4_exterior",    "housing",     "housing_other"),  # NEW
        "House#4 - Garage":         ("house_4_garage",      "housing",     "room"),    # NEW
        "House#4 - Kitchen":        ("house_4_kitchen",     "housing",     "room"),    # NEW
        "House#4 - Living Room":    ("house_4_living_room", "housing",     "room"),    # NEW
        "Ohana#1":                  ("ohana_1",             "housing",      None),     # NEW
        "Ohana#1 - Bathroom 1":     ("ohana_1_bathroom_1",  "housing",     "room"),    # NEW
        "Ohana#1 - Bedroom 1":      ("ohana_1_bedroom_1",   "housing",     "room"),    # NEW
        "Ohana#1 - Exterior":       ("ohana_1_exterior",    "housing",     "housing_other"),  # NEW
        "Ohana#1 - Living Room":    ("ohana_1_living_room", "housing",     "room"),    # NEW
        "Ohana #1 kitchen":         ("ohana_1_kitchen",     "housing",     "room"),    # NEW
        "Ohana#2":                  ("ohana_2",             "housing",      None),     # NEW
        "Ohana#2 - Bedroom 1":      ("ohana_2_bedroom_1",   "housing",     "room"),    # NEW
        "Ohana#2 - Living Room":    ("ohana_2_living_room", "housing",     "room"),    # NEW
        "Ohana#2 - Exterior":       ("ohana_2_exterior",    "housing",     "housing_other"),  # NEW
        "Ohana#3":                  ("ohana_3",             "housing",      None),     # NEW
        "Ohana#3 - Bedroom 1":      ("ohana_3_bedroom_1",   "housing",     "room"),    # NEW
        "Ohana#3 - Exterior":       ("ohana_3_exterior",    "housing",     "housing_other"),  # NEW
        "Farm Gym":                 ("farm_gym",            "other",        None),     # NEW
        "Manager housing":          ("manager_housing",     "other",        None),     # NEW

        # ----- STORAGE -----
        "Boneyard Container Racks":     ("boneyard_container_racks",    "storage",      None),     # NEW
        "Boneyard Containers":          ("boneyard_containers",         "storage",      None),     # NEW
        "Boneyard Parts Containers":    ("boneyard_parts_containers",   "storage",      None),     # NEW
        "Lettuce Cold Storage":         ("lettuce_cold_storage",        "storage",  "cold_storage"),  # NEW
        "Emergency 40\u00b4 Reefer Container": ("emergency_40_reefer_container", "storage", "cold_storage"),  # NEW
        "New 40\u00b4 Reefer Container": ("new_40_reefer_container",    "storage",  "cold_storage"),  # NEW
        "New 40ft Container":           ("new_40ft_container",          "storage",      None),     # NEW
        "Shop":                         ("shop",                        "growing",  "growing_other"),  # NEW

        # ----- OTHER -----
        "Grounds":                      ("grounds",                     "other",        None),     # NEW
        "Parade Float":                 ("parade_float",                "other",        None),     # NEW
        "Watanabe":                     ("watanabe_break_room",         "growing",  "growing_other"),  # NEW: parent=jtl
        "Watanabe Break Room":          ("watanabe_break_room",         "growing",  "growing_other"),  # NEW: parent=jtl
    }

    # =====================================================================
    # EQUIPMENT MAP — these go into org_equipment, not org_site
    # =====================================================================
    # Format: "Legacy SiteName" → (equipment_id, type, farm_id)
    #   type: vehicle, tool, machine, ppe, bag_pack_sprayer, fogger, tank
    # =====================================================================

    EQUIPMENT_MAP = {
        # ----- GROWING: Equipment -----
        "Lettuce Pond Pumps":           ("lettuce_pond_pumps",          "machine",  "lettuce"),
        "Lettuce Fert Meter":           ("lettuce_fert_meter",          "machine",  "lettuce"),
        "Earth Pot":                    ("earth_pot",                   "machine",  "lettuce"),
        "Pond Chillers":                ("pond_chillers",               "machine",  "lettuce"),
        "Earth pot vacuum system":      ("earth_pot_vacuum_system",     "machine",  "lettuce"),
        "Lettuce GH Fans":             ("lettuce_gh_fans",             "machine",  "lettuce"),
        "Lettuce GH PV system":        ("lettuce_gh_pv_system",        "machine",  "lettuce"),
        "Nursery air compressor":       ("nursery_air_compressor",      "machine",  "lettuce"),
        "Cravo Roof Back-up System":    ("cravo_roof_back_up_system",   "machine",  "lettuce"),

        # ----- PACKING: Cuke equipment -----
        "Cucumber Clamco East":         ("cucumber_clamco_east",        "machine",  "cuke"),
        "Cucumber Clamco Middle":       ("cucumber_clamco_middle",      "machine",  "cuke"),
        "Cucumber Clamco West":         ("cucumber_clamco_west",        "machine",  "cuke"),
        "BIP Tote Washer":             ("bip_tote_washer",             "machine",  "cuke"),

        # ----- PACKING: Lettuce equipment -----
        "Lettuce Board Conveyor (middle)": ("lettuce_board_conveyor_middle", "machine", "lettuce"),
        "Lettuce conveyor (Leading)":   ("lettuce_conveyor_leading",    "machine",  "lettuce"),
        "Proseal":                      ("proseal",                     "machine",  "lettuce"),
        "Metal Detector":               ("metal_detector",              "machine",  "lettuce"),
        "Harvester":                    ("harvester",                   "machine",  "lettuce"),
        "Seeder":                       ("seeder",                      "machine",  "lettuce"),
        "Dryer":                        ("dryer",                       "machine",  "cuke"),
        "Lettuce Dryer":                ("lettuce_dryer",               "machine",  "lettuce"),
        "Lettuce Fogger Machine":       ("lettuce_fogger_machine",      "fogger",   "lettuce"),
        "Lettuce Tote Washer":          ("lettuce_tote_washer",         "machine",  "lettuce"),
        "Lettuce PH Turntable":         ("lettuce_ph_turntable",        "machine",  "lettuce"),
        "Lettuce floor scrubber":       ("lettuce_floor_scrubber",      "machine",  "lettuce"),
        "Lettuce forklift":             ("lettuce_forklift",            "vehicle",  "lettuce"),
        "Lettuce pallet jack scale":    ("lettuce_pallet_jack_scale",   "machine",  "lettuce"),

        # ----- INFRASTRUCTURE: Water & filtration -----
        "Amiad Filter":                 ("amiad_filter",                "machine",  None),
        "JTL Incoming Water Filter":    ("jtl_incoming_water_filter",   "machine",  "cuke"),
        "Municipal Water System":       ("municipal_water_system",      "machine",  None),
        "Back Flow Prevention Valves":  ("back_flow_prevention_valves", "machine",  None),
        "bermad water meter":           ("bermad_water_meter",          "machine",  None),

        # ----- INFRASTRUCTURE: Power & climate -----
        "Air Comp/Dryer":               ("air_comp_dryer",              "machine",  None),
        "BIP Back Up Generator":        ("bip_back_up_generator",       "machine",  "cuke"),
        "O2 Generator":                 ("o2_generator",                "machine",  "lettuce"),
        "Ice Machine":                  ("ice_machine",                 "machine",  None),
        "Link 4":                       ("link_4",                      "machine",  "lettuce"),

        # ----- INFRASTRUCTURE: Tanks -----
        "Tank #1":                      ("tank_1",                      "tank",     "cuke"),
        "Tank #2":                      ("tank_2",                      "tank",     "cuke"),
        "Tank #3":                      ("tank_3",                      "tank",     "cuke"),

        # ----- VEHICLES -----
        "Large box truck":              ("large_box_truck",             "vehicle",  None),
        "Small Box Truck":              ("small_box_truck",             "vehicle",  None),

        # ----- MONITORING -----
        "Weather Station":              ("weather_station",             "machine",  "lettuce"),
        "Crodeon weather station":      ("crodeon_weather_station",     "machine",  "lettuce"),
        "Yellow sticky traps":          ("yellow_sticky_traps",         "tool",     "lettuce"),
    }

    # Get existing site IDs
    existing = supabase.table("org_site").select("id").execute()
    existing_ids = {s["id"] for s in existing.data}

    # Sites that need parent site and/or farm overrides
    SITE_OVERRIDES = {
        # -- BIP children (farm=cuke, parent=bip) --
        "fert_bip":                     {"site_id_parent": "bip", "farm_id": "cuke"},
        "bip_ph":                       {"site_id_parent": "bip", "farm_id": "cuke"},

        # -- BIP PH children (farm=cuke, parent=bip_ph) --
        "bip_breakroom":                {"site_id_parent": "bip_ph", "farm_id": "cuke"},
        "bip_office":                   {"site_id_parent": "bip_ph", "farm_id": "cuke"},
        "bip_cold_storage_1":           {"site_id_parent": "bip_ph", "farm_id": "cuke"},
        "bip_cold_storage_2":           {"site_id_parent": "bip_ph", "farm_id": "cuke"},

        # -- JTL children (farm=cuke, parent=jtl) --
        "fert_jtl":                     {"site_id_parent": "jtl", "farm_id": "cuke"},
        "gh_01_storage":                {"site_id_parent": "jtl", "farm_id": "cuke"},
        "watanabe_break_room":          {"site_id_parent": "jtl", "farm_id": "cuke"},
        "shop":                         {"site_id_parent": "jtl", "farm_id": "cuke"},
        "boneyard_container_racks":     {"site_id_parent": "jtl", "farm_id": "cuke"},
        "boneyard_containers":          {"site_id_parent": "jtl", "farm_id": "cuke"},
        "boneyard_parts_containers":    {"site_id_parent": "jtl", "farm_id": "cuke"},

        # -- GH children (farm=lettuce, parent=gh) --
        "lettuce_fert_station":         {"site_id_parent": "gh", "farm_id": "lettuce"},
        "lettuce_germination_room":     {"site_id_parent": "gh", "farm_id": "lettuce"},
        "lettuce_ph":                   {"site_id_parent": "gh", "farm_id": "lettuce"},

        # -- Lettuce PH children (farm=lettuce, parent=lettuce_ph) --
        "lettuce_packing_room":         {"site_id_parent": "lettuce_ph", "farm_id": "lettuce"},
        "lettuce_ph_cold_storage":      {"site_id_parent": "lettuce_ph", "farm_id": "lettuce"},
        "lettuce_ph_utility_closet":    {"site_id_parent": "lettuce_ph", "farm_id": "lettuce"},
        "lettuce_breezeway":            {"site_id_parent": "lettuce_ph", "farm_id": "lettuce"},
        "lettuce_dry_side_storage":     {"site_id_parent": "lettuce_ph", "farm_id": "lettuce"},
        "lettuce_cold_storage":         {"site_id_parent": "lettuce_ph", "farm_id": "lettuce"},
        "emergency_40_reefer_container": {"site_id_parent": "lettuce_ph", "farm_id": "lettuce"},
        "new_40_reefer_container":      {"site_id_parent": "lettuce_ph", "farm_id": "lettuce"},
        "new_40ft_container":           {"site_id_parent": "lettuce_ph", "farm_id": "lettuce"},

        # -- Housing children (parent=their house, no farm) --
        "duplex_downstairs_bathroom_1": {"site_id_parent": "duplex"},
        "duplex_downstairs_bathroom_2": {"site_id_parent": "duplex"},
        "duplex_downstairs_bedroom_1":  {"site_id_parent": "duplex"},
        "duplex_downstairs_bedroom_2":  {"site_id_parent": "duplex"},
        "duplex_exterior":              {"site_id_parent": "duplex"},
        "duplex_living_room":           {"site_id_parent": "duplex"},
        "duplex_downstairs_living_room": {"site_id_parent": "duplex"},
        "duplex_upstairs_living_room":  {"site_id_parent": "duplex"},
        "duplex_upstairs_bathroom_1":   {"site_id_parent": "duplex"},
        "duplex_upstairs_bathroom_2":   {"site_id_parent": "duplex"},
        "duplex_upstairs_bedroom_1":    {"site_id_parent": "duplex"},
        "duplex_upstairs_bedroom_2":    {"site_id_parent": "duplex"},
        "duplex_upstairs_bedroom_3":    {"site_id_parent": "duplex"},
        "duplex_downstairs_kitchen":    {"site_id_parent": "duplex"},
        "duplex_upstairs_kitchen":      {"site_id_parent": "duplex"},
        "house_1_bathroom_1":           {"site_id_parent": "house_1"},
        "house_1_bathroom_2":           {"site_id_parent": "house_1"},
        "house_1_bedroom_1":            {"site_id_parent": "house_1"},
        "house_1_bedroom_2":            {"site_id_parent": "house_1"},
        "house_1_bedroom_3":            {"site_id_parent": "house_1"},
        "house_1_bedroom_4":            {"site_id_parent": "house_1"},
        "house_1_bedroom_5":            {"site_id_parent": "house_1"},
        "house_1_exterior":             {"site_id_parent": "house_1"},
        "house_1_garage":               {"site_id_parent": "house_1"},
        "house_1_kitchen":              {"site_id_parent": "house_1"},
        "house_1_living_room":          {"site_id_parent": "house_1"},
        "house_2_bathroom_1":           {"site_id_parent": "house_2"},
        "house_2_bathroom_2":           {"site_id_parent": "house_2"},
        "house_2_bedroom_1":            {"site_id_parent": "house_2"},
        "house_2_bedroom_2":            {"site_id_parent": "house_2"},
        "house_2_bedroom_3":            {"site_id_parent": "house_2"},
        "house_2_bedroom_4":            {"site_id_parent": "house_2"},
        "house_2_exterior":             {"site_id_parent": "house_2"},
        "house_2_garage":               {"site_id_parent": "house_2"},
        "house_2_kitchen":              {"site_id_parent": "house_2"},
        "house_2_living_room":          {"site_id_parent": "house_2"},
        "house_3_bathroom_1":           {"site_id_parent": "house_3"},
        "house_3_bedroom_1":            {"site_id_parent": "house_3"},
        "house_3_bedroom_2":            {"site_id_parent": "house_3"},
        "house_3_exterior":             {"site_id_parent": "house_3"},
        "house_3_kitchen":              {"site_id_parent": "house_3"},
        "house_3_living_room":          {"site_id_parent": "house_3"},
        "house_4_bathroom_1":           {"site_id_parent": "house_4"},
        "house_4_bedroom_1":            {"site_id_parent": "house_4"},
        "house_4_bedroom_2":            {"site_id_parent": "house_4"},
        "house_4_exterior":             {"site_id_parent": "house_4"},
        "house_4_garage":               {"site_id_parent": "house_4"},
        "house_4_kitchen":              {"site_id_parent": "house_4"},
        "house_4_living_room":          {"site_id_parent": "house_4"},
        "ohana_1_bathroom_1":           {"site_id_parent": "ohana_1"},
        "ohana_1_bedroom_1":            {"site_id_parent": "ohana_1"},
        "ohana_1_exterior":             {"site_id_parent": "ohana_1"},
        "ohana_1_living_room":          {"site_id_parent": "ohana_1"},
        "ohana_1_kitchen":              {"site_id_parent": "ohana_1"},
        "ohana_2_bedroom_1":            {"site_id_parent": "ohana_2"},
        "ohana_2_living_room":          {"site_id_parent": "ohana_2"},
        "ohana_2_exterior":             {"site_id_parent": "ohana_2"},
        "ohana_3_bedroom_1":            {"site_id_parent": "ohana_3"},
        "ohana_3_exterior":             {"site_id_parent": "ohana_3"},
    }

    # Split into parent sites (no parent or parent already exists) and children
    parent_rows = []
    child_rows = []
    seen = set()
    for site_name, (site_id, category, subcategory) in SITE_MAP.items():
        if site_id in existing_ids or site_id in seen:
            continue
        seen.add(site_id)
        row = {
            "id": site_id,
            "org_id": ORG_ID,
            "name": site_name,
            "org_site_category_id": category,
            "created_by": AUDIT_USER,
            "updated_by": AUDIT_USER,
        }
        if subcategory:
            row["org_site_subcategory_id"] = subcategory
        if site_id in SITE_OVERRIDES:
            row.update(SITE_OVERRIDES[site_id])

        # If parent is a NEW site (not in existing_ids), this is a child
        parent = SITE_OVERRIDES.get(site_id, {}).get("site_id_parent")
        if parent and parent not in existing_ids:
            child_rows.append(row)
        else:
            parent_rows.append(row)

    insert_rows(supabase, "org_site", parent_rows)
    if child_rows:
        insert_rows(supabase, "org_site", child_rows)

    # Create org_equipment records
    existing_equip = supabase.table("org_equipment").select("id").execute()
    existing_equip_ids = {e["id"] for e in existing_equip.data}

    equip_rows = []
    seen_equip = set()
    for equip_name, (equip_id, equip_type, farm_id) in EQUIPMENT_MAP.items():
        if equip_id in existing_equip_ids or equip_id in seen_equip:
            continue
        seen_equip.add(equip_id)
        equip_rows.append({
            "id": equip_id,
            "org_id": ORG_ID,
            "farm_id": farm_id,
            "type": equip_type,
            "name": proper_case(equip_name),
            "created_by": AUDIT_USER,
            "updated_by": AUDIT_USER,
        })

    insert_rows(supabase, "org_equipment", equip_rows)

    # Return both mappings for use in maint_request migration
    return SITE_MAP, EQUIPMENT_MAP


def migrate_maint_request(supabase, client, site_map, equipment_map):
    """Migrate maintenance requests from maint_req sheet."""
    ws = client.open_by_key(SHEET_ID).worksheet("maint_req")
    records = ws.get_all_records()

    # Build employee email -> id lookup
    emp_result = supabase.table("hr_employee").select("id, company_email").execute()
    email_to_emp = {}
    for e in emp_result.data:
        if e.get("company_email"):
            email_to_emp[e["company_email"].lower()] = e["id"]
    FALLBACK_EMP = email_to_emp.get("data@hawaiifarming.com")

    # Build site -> farm_id and equipment -> farm_id lookups
    site_farm = {}
    for s in supabase.table("org_site").select("id, farm_id").execute().data:
        if s.get("farm_id"):
            site_farm[s["id"]] = s["farm_id"]
    equip_farm = {}
    for eq in supabase.table("org_equipment").select("id, farm_id").execute().data:
        if eq.get("farm_id"):
            equip_farm[eq["id"]] = eq["farm_id"]

    # Build site lookup from SITE_MAP: legacy name → org_site_id
    site_by_name = {}
    for legacy_name, (site_id, _cat, _sub) in site_map.items():
        site_by_name[legacy_name.lower()] = site_id

    # Build equipment lookup from EQUIPMENT_MAP: legacy name → org_equipment_id
    equip_by_name = {}
    for legacy_name, (equip_id, _type, _farm) in equipment_map.items():
        equip_by_name[legacy_name.lower()] = equip_id

    # Build item name -> id lookup
    item_result = supabase.table("invnt_item").select("id, name, burn_uom").execute()
    item_by_name = {}
    for it in item_result.data:
        item_by_name[it["name"].lower()] = it

    # Fixer mapping: first name in concatenated list
    FIXER_MAP = {
        "max": "von_keudell_maximillian",
        "jv": "van_housen_jason",
        "fritz": "borchert_frederic",
    }
    FIXER_FALLBACK = "batha_eric"

    def resolve_fixer(fixer_str):
        """Extract first fixer name and resolve to employee ID."""
        if not fixer_str:
            return None
        # Split on & and take first
        first = fixer_str.split("&")[0].strip().lower()
        return FIXER_MAP.get(first, FIXER_FALLBACK)

    # Status mapping
    STATUS_MAP = {
        "done": "done",
        "pending": "pending",
        "priority": "priority",
        "new": "new",
    }

    # Recurring mapping
    RECURRING_MAP = {
        "daily": "daily",
        "weekly": "weekly",
        "monthly": "monthly",
        "quarterly": "quarterly",
        "annually": "annually",
        "semi-annually": "semi_annually",
        "not recurring": None,
    }

    req_rows = []
    invnt_item_rows = []  # (req_index, row)
    photo_rows = []  # (req_index, row)

    for r_raw in records:
        r = {str(k).strip(): v for k, v in r_raw.items()}

        description = str(r.get("RequestDescription", "")).strip()
        requested_at = parse_timestamp(r.get("RequestDateTime", ""))
        if not requested_at:
            continue

        # Site or Equipment — check equipment first, then site
        site_name = str(r.get("SiteName", "")).strip()
        equipment_id = equip_by_name.get(site_name.lower())
        site_id = None if equipment_id else (site_by_name.get(site_name.lower()) or site_by_name.get(to_id(site_name)))

        # Status
        raw_status = str(r.get("Status", "")).strip().lower()
        status = STATUS_MAP.get(raw_status, "new")

        # Recurring
        raw_recurring = str(r.get("Recurring", "")).strip().lower()
        recurring = RECURRING_MAP.get(raw_recurring)

        # Due date
        due_date = parse_date(r.get("DueDate", ""))

        # Completed
        completed_at = parse_timestamp(r.get("CompletedDateTime", ""))

        # Fixer
        fixer_raw = str(r.get("Fixer", "")).strip()
        fixer_id = resolve_fixer(fixer_raw)

        # Fixer comments
        fixer_desc = str(r.get("FixerComments", "")).strip() or None

        # Requested by
        req_email = str(r.get("RequestedBy", "")).strip().lower()
        requested_by = email_to_emp.get(req_email) or FALLBACK_EMP

        # Derive farm_id from site or equipment
        farm_id = None
        if site_id:
            farm_id = site_farm.get(site_id)
        if not farm_id and equipment_id:
            farm_id = equip_farm.get(equipment_id)

        # Skip rows where neither site nor equipment is set (XOR constraint)
        if not site_id and not equipment_id:
            continue

        req = {
            "org_id": ORG_ID,
            "farm_id": farm_id,
            "site_id": site_id,
            "equipment_id": equipment_id,
            "status": status,
            "request_description": description or None,
            "recurring_frequency": recurring,
            "due_date": due_date,
            "completed_at": completed_at,
            "fixer_id": fixer_id,
            "fixer_description": fixer_desc,
            "requested_at": requested_at,
            "requested_by": requested_by,
            "created_at": requested_at,
            "created_by": req_email or AUDIT_USER,
            "updated_at": completed_at or requested_at,
            "updated_by": req_email or AUDIT_USER,
        }
        req_rows.append(req)
        req_index = len(req_rows) - 1

        # Inventory item used
        used_part = str(r.get("UsedPart", "")).strip().upper()
        if used_part == "TRUE":
            item_name = str(r.get("InventoryItemName", "")).strip()
            item = item_by_name.get(item_name.lower()) if item_name else None
            if item:
                qty = safe_numeric(r.get("QuantityUsed", ""))
                invnt_item_rows.append((req_index, {
                    "org_id": ORG_ID,
                    "invnt_item_id": item["id"],
                    "uom": item.get("burn_uom"),
                    "quantity_used": qty if qty else None,
                    "created_by": req_email or AUDIT_USER,
                    "updated_by": req_email or AUDIT_USER,
                }))

        # Photos — before
        for col in ["BeforePhoto01", "BeforePhoto02", "BeforePhoto03",
                     "BeforePhoto04", "BeforePhoto05", "BeforePhoto06"]:
            url = str(r.get(col, "")).strip()
            if url:
                photo_rows.append((req_index, {
                    "org_id": ORG_ID,
                    "photo_type": "before",
                    "photo_url": url,
                    "created_by": req_email or AUDIT_USER,
                    "updated_by": req_email or AUDIT_USER,
                }))

        # Photos — after
        for col in ["AfterPhoto01", "AfterPhoto02", "AfterPhoto03",
                     "AfterPhoto04", "AfterPhoto05", "AfterPhoto06"]:
            url = str(r.get(col, "")).strip()
            if url:
                photo_rows.append((req_index, {
                    "org_id": ORG_ID,
                    "photo_type": "after",
                    "photo_url": url,
                    "created_by": req_email or AUDIT_USER,
                    "updated_by": req_email or AUDIT_USER,
                }))

    # Insert requests and collect IDs
    print(f"\n--- maint_request ---")
    req_ids = []
    for i in range(0, len(req_rows), 100):
        batch = req_rows[i:i + 100]
        result = supabase.table("maint_request").insert(batch).execute()
        for row in result.data:
            req_ids.append(row["id"])
    print(f"  Inserted {len(req_ids)} rows")

    # Insert inventory items with resolved request IDs
    item_to_insert = []
    for req_idx, item_row in invnt_item_rows:
        if req_idx < len(req_ids):
            item_row["maint_request_id"] = req_ids[req_idx]
            item_to_insert.append(item_row)
    if item_to_insert:
        insert_rows(supabase, "maint_request_invnt_item", item_to_insert)

    # Insert photos with resolved request IDs
    photos_to_insert = []
    for req_idx, photo_row in photo_rows:
        if req_idx < len(req_ids):
            photo_row["maint_request_id"] = req_ids[req_idx]
            photos_to_insert.append(photo_row)
    if photos_to_insert:
        insert_rows(supabase, "maint_request_photo", photos_to_insert)


def migrate_house_inspections(supabase, client):
    """Migrate house inspections from maint_house_inspections sheet.

    Creates ops_task, ops_template (6 room-type templates),
    ops_template_question, ops_task_template, ops_task_tracker,
    and ops_template_result records.
    """
    ws = client.open_by_key(SHEET_ID).worksheet("maint_house_inspections")
    records = ws.get_all_records()

    # Build employee email -> id lookup
    emp_result = supabase.table("hr_employee").select("id, company_email").execute()
    email_to_emp = {}
    for e in emp_result.data:
        if e.get("company_email"):
            email_to_emp[e["company_email"].lower()] = e["id"]
    FALLBACK_EMP = email_to_emp.get("data@hawaiifarming.com")

    # Build site lookup: "house|room" -> org_site_id
    site_result = supabase.table("org_site").select("id, name, site_id_parent, org_site_category_id").eq("org_site_category_id", "housing").execute()
    # Build house name -> site_id and room combos
    site_by_id = {s["id"]: s for s in site_result.data}
    house_room_to_site = {}
    for s in site_result.data:
        if s.get("site_id_parent"):
            parent = site_by_id.get(s["site_id_parent"], {})
            parent_name = parent.get("name", "")
            # Build key like "ohana#2|bedroom 1"
            # Strip parent name prefix from child name if present
            child_name = s["name"]
            if child_name.startswith(parent_name):
                child_name = child_name[len(parent_name):].lstrip(" -")
            key = f"{parent_name.lower()}|{child_name.lower()}"
            house_room_to_site[key] = s["id"]
            # Also store with full child name
            house_room_to_site[f"{parent_name.lower()}|{s['name'].lower()}"] = s["id"]
    # Also map house-level (no room)
    for s in site_result.data:
        if not s.get("site_id_parent"):
            house_room_to_site[f"{s['name'].lower()}|"] = s["id"]

    # --- Define templates per room type ---
    TEMPLATES = {
        "exterior": {
            "name": "House Inspection - Exterior",
            "questions": [
                ("General cleanliness", "numeric", 1, 5),
                ("Roof intact with no missing shingles, leaks or loose flashing", "boolean", None, None),
                ("Gutters and downspouts are securely attached and free of clogs or leaks", "boolean", None, None),
                ("Driveway and walkways clear with no cracks or tripping hazards", "boolean", None, None),
                ("Security lights working", "boolean", None, None),
                ("Electrical outlets working", "boolean", None, None),
            ],
        },
        "bedroom": {
            "name": "House Inspection - Bedroom",
            "questions": [
                ("General cleanliness", "numeric", 1, 5),
                ("Doors are secure and locks functional", "boolean", None, None),
                ("Windows open and close properly and screens are intact", "boolean", None, None),
                ("Ceiling is intact with no signs of mold", "boolean", None, None),
                ("Electrical outlets working", "boolean", None, None),
                ("Flooring has no damage, water stains, or excessive wear", "boolean", None, None),
                ("Walls have no cracks, water damage, or peeling paint", "boolean", None, None),
                ("Faucets work with good water pressure", "boolean", None, None),
                ("Closets intact and doors track properly", "boolean", None, None),
            ],
        },
        "bathroom": {
            "name": "House Inspection - Bathroom",
            "questions": [
                ("General cleanliness", "numeric", 1, 5),
                ("Doors are secure and locks functional", "boolean", None, None),
                ("Windows open and close properly and screens are intact", "boolean", None, None),
                ("Ceiling is intact with no signs of mold", "boolean", None, None),
                ("Flooring has no damage, water stains, or excessive wear", "boolean", None, None),
                ("Walls have no cracks, water damage, or peeling paint", "boolean", None, None),
                ("Faucets work with good water pressure", "boolean", None, None),
                ("Toilet flushes properly, no leaks at base", "boolean", None, None),
                ("Shower head or tub faucet functional, no leaks", "boolean", None, None),
            ],
        },
        "kitchen": {
            "name": "House Inspection - Kitchen",
            "questions": [
                ("General cleanliness", "numeric", 1, 5),
                ("Doors are secure and locks functional", "boolean", None, None),
                ("Windows open and close properly and screens are intact", "boolean", None, None),
                ("Ceiling is intact with no signs of mold", "boolean", None, None),
                ("Electrical outlets working", "boolean", None, None),
                ("Appliances working", "boolean", None, None),
                ("Flooring has no damage, water stains, or excessive wear", "boolean", None, None),
                ("Walls have no cracks, water damage, or peeling paint", "boolean", None, None),
                ("Cabinets, drawers intact with doors and latches working", "boolean", None, None),
                ("Sink is clean and drain working properly with no clogs or leaks", "boolean", None, None),
                ("Faucets work with good water pressure", "boolean", None, None),
            ],
        },
        "living_room": {
            "name": "House Inspection - Living Room",
            "questions": [
                ("General cleanliness", "numeric", 1, 5),
                ("Doors are secure and locks functional", "boolean", None, None),
                ("Windows open and close properly and screens are intact", "boolean", None, None),
                ("Ceiling is intact with no signs of mold", "boolean", None, None),
                ("Electrical outlets working", "boolean", None, None),
                ("Appliances working", "boolean", None, None),
                ("Flooring has no damage, water stains, or excessive wear", "boolean", None, None),
                ("Walls have no cracks, water damage, or peeling paint", "boolean", None, None),
                ("Faucets work with good water pressure", "boolean", None, None),
            ],
        },
        "garage": {
            "name": "House Inspection - Garage",
            "questions": [
                ("General cleanliness", "numeric", 1, 5),
                ("Driveway and walkways clear with no cracks or tripping hazards", "boolean", None, None),
                ("Security lights working", "boolean", None, None),
                ("Doors are secure and locks functional", "boolean", None, None),
                ("Windows open and close properly and screens are intact", "boolean", None, None),
                ("Ceiling is intact with no signs of mold", "boolean", None, None),
                ("Electrical outlets working", "boolean", None, None),
                ("Flooring has no damage, water stains, or excessive wear", "boolean", None, None),
                ("Walls have no cracks, water damage, or peeling paint", "boolean", None, None),
                ("Faucets work with good water pressure", "boolean", None, None),
            ],
        },
    }

    # Room type classifier
    def classify_room(room_str):
        r = room_str.lower()
        if "exterior" in r:
            return "exterior"
        if "bedroom" in r:
            return "bedroom"
        if "bathroom" in r:
            return "bathroom"
        if "kitchen" in r:
            return "kitchen"
        if "living" in r:
            return "living_room"
        if "garage" in r:
            return "garage"
        return None

    # 1. Create ops_task (upsert — house_inspection may already exist as a
    # system task seeded by the org migration)
    task_id = "house_inspection"
    supabase.table("ops_task").upsert({
        "id": task_id,
        "org_id": ORG_ID,
        "name": "House Inspection",
        "description": "Periodic inspection of housing units and rooms",
        "created_by": AUDIT_USER,
        "updated_by": AUDIT_USER,
    }).execute()
    print("\n--- ops_task ---")
    print("  Upserted house_inspection task")

    # 2. Create ops_template + ops_template_question for each room type
    template_questions = {}  # room_type -> {question_text: question_id}
    for room_type, tmpl in TEMPLATES.items():
        tmpl_id = f"house_inspection_{room_type}"
        org_module_result = supabase.table("org_module").select("id").eq("sys_module_id", "maintenance").execute()
        org_module_id = org_module_result.data[0]["id"] if org_module_result.data else None

        supabase.table("ops_template").insert({
            "id": tmpl_id,
            "org_id": ORG_ID,
            "name": tmpl["name"],
            "org_module_id": org_module_id,
            "display_order": list(TEMPLATES.keys()).index(room_type) + 1,
            "created_by": AUDIT_USER,
            "updated_by": AUDIT_USER,
        }).execute()

        # Link task to template
        supabase.table("ops_task_template").insert({
            "org_id": ORG_ID,
            "ops_task_id": task_id,
            "ops_template_id": tmpl_id,
            "created_by": AUDIT_USER,
            "updated_by": AUDIT_USER,
        }).execute()

        # Create questions
        q_rows = []
        for i, (q_text, resp_type, min_val, max_val) in enumerate(tmpl["questions"]):
            q_row = {
                "org_id": ORG_ID,
                "ops_template_id": tmpl_id,
                "question_text": q_text,
                "response_type": resp_type,
                "is_required": True,
                "display_order": i + 1,
                "created_by": AUDIT_USER,
                "updated_by": AUDIT_USER,
            }
            if resp_type == "boolean":
                q_row["boolean_pass_value"] = True
            if min_val is not None:
                q_row["minimum_value"] = min_val
            if max_val is not None:
                q_row["maximum_value"] = max_val
            q_rows.append(q_row)

        inserted = insert_rows(supabase, "ops_template_question", q_rows)
        template_questions[room_type] = {}
        for q in inserted:
            template_questions[room_type][q["question_text"]] = q["id"]

    print("\n  Created 6 templates with questions")

    # 3. Migrate inspection records -> ops_task_tracker + ops_template_result
    tracker_rows = []
    result_rows = []  # list of (tracker_index, result_row)
    skipped = 0

    for r_raw in records:
        r = {str(k).strip(): v for k, v in r_raw.items()}

        house = str(r.get("House", "")).strip()
        room = str(r.get("Room", "")).strip()
        if not house or not room:
            skipped += 1
            continue

        room_type = classify_room(room)
        if not room_type:
            skipped += 1
            continue

        # Resolve site_id
        lookup_key = f"{house.lower()}|{room.lower()}"
        site_id = house_room_to_site.get(lookup_key)
        if not site_id:
            # Try just house for exterior
            if room_type == "exterior":
                # Look for house_exterior pattern
                house_id = to_id(house)
                site_id = house_room_to_site.get(f"{house.lower()}|exterior")
                if not site_id:
                    site_id = f"{house_id}_exterior"
            else:
                house_id = to_id(house)
                room_id = to_id(room)
                site_id = f"{house_id}_{room_id}"

        # Parse timestamps
        inspection_date = parse_timestamp(r.get("EntryDateTime", "")) or parse_timestamp(r.get("InspectionDate", ""))
        if not inspection_date:
            skipped += 1
            continue

        # Inspector
        inspector_email = str(r.get("InspectedBy", "")).strip().lower()
        inspector_id = email_to_emp.get(inspector_email) or FALLBACK_EMP

        tmpl_id = f"house_inspection_{room_type}"

        tracker = {
            "org_id": ORG_ID,
            "site_id": site_id,
            "ops_task_id": task_id,
            "start_time": inspection_date,
            "stop_time": inspection_date,
            "is_completed": True,
            "notes": str(r.get("Notes", "")).strip() or None,
            "created_at": inspection_date,
            "created_by": inspector_email or AUDIT_USER,
            "updated_at": inspection_date,
            "updated_by": inspector_email or AUDIT_USER,
        }
        tracker_rows.append(tracker)
        tracker_idx = len(tracker_rows) - 1

        # Build results for each question in this template
        q_map = template_questions.get(room_type, {})
        for q_text, q_id in q_map.items():
            val = r.get(q_text, "")
            if val == "" or val is None:
                continue

            result_row = {
                "org_id": ORG_ID,
                "ops_template_id": tmpl_id,
                "ops_template_question_id": q_id,
                "created_by": inspector_email or AUDIT_USER,
                "updated_by": inspector_email or AUDIT_USER,
            }

            if q_text == "General cleanliness":
                result_row["response_numeric"] = safe_numeric(val)
            else:
                result_row["response_boolean"] = str(val).strip().upper() == "TRUE"

            result_rows.append((tracker_idx, result_row))

    # Insert trackers in batches, collect IDs
    print(f"\n--- ops_task_tracker ---")
    tracker_ids = []
    for i in range(0, len(tracker_rows), 100):
        batch = tracker_rows[i:i + 100]
        result = supabase.table("ops_task_tracker").insert(batch).execute()
        for row in result.data:
            tracker_ids.append(row["id"])
    print(f"  Inserted {len(tracker_ids)} rows")
    if skipped:
        print(f"  Skipped {skipped} rows (missing house/room/date or unknown room type)")

    # Insert results with resolved tracker IDs
    all_results = []
    for tracker_idx, result_row in result_rows:
        if tracker_idx < len(tracker_ids):
            result_row["ops_task_tracker_id"] = tracker_ids[tracker_idx]
            all_results.append(result_row)

    insert_rows(supabase, "ops_template_result", all_results)


def main():
    if not SUPABASE_KEY:
        print("ERROR: Set SUPABASE_SERVICE_KEY in .env or environment")
        return

    supabase = create_client(SUPABASE_URL, SUPABASE_KEY)
    client = get_sheets()

    # Clear in reverse FK order
    print("Clearing tables...")
    for t in ["ops_template_result_photo", "ops_template_result", "ops_task_tracker",
              "ops_task_template", "ops_template_question", "ops_template",
              "ops_task",
              "maint_request_photo", "maint_request_invnt_item", "maint_request"]:
        try:
            supabase.table(t).delete().neq("org_id", "___never___").execute()
        except Exception:
            pass
    # Clear equipment created by this script
    try:
        supabase.table("org_equipment").delete().neq("id", "___never___").execute()
    except Exception:
        pass
    print("  All cleared")

    site_map, equipment_map = migrate_maint_sites(supabase)
    migrate_maint_request(supabase, client, site_map, equipment_map)
    migrate_house_inspections(supabase, client)

    print("\nMaintenance data migrated successfully")


if __name__ == "__main__":
    main()
