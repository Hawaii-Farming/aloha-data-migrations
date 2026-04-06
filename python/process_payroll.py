"""
Payroll Import Script
=====================
Reads payroll data from Excel/CSV files exported by the payroll processor (HRB/HF),
merges all tabs ($data, Hours, NetPay, PTOBank, WC, TDI), snapshots employee fields
from hr_employee, and inserts into hr_payroll in Supabase.

Usage:
    python process_payroll.py --org_id <org_id> --processor HRB --input <path_to_excel>

Input file must contain these sheets/tabs:
    - $data     : invoice-level summary per employee
    - Hours     : hours and pay breakdown per employee per check date
    - NetPay    : earnings, deductions, and net pay per employee
    - PTOBank   : YTD PTO hours accrued per employee
    - WC        : workers compensation amounts per employee
    - TDI       : temporary disability insurance per employee
"""

import argparse
import os
import re
import sys
from datetime import datetime, date

import pandas as pd
from supabase import create_client


# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

SUPABASE_URL = os.environ.get("SUPABASE_URL")
SUPABASE_KEY = os.environ.get("SUPABASE_SERVICE_KEY")

INVOICE_STANDARD_THRESHOLD = 5000  # total hours above this = standard run


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def norm_id(value) -> str:
    """Strip non-digit characters to normalize payroll IDs."""
    if value is None:
        return ""
    return re.sub(r"\D", "", str(value)).strip()


def extract_id_from_name(name: str, pattern: re.Pattern) -> str:
    """Extract a numeric ID embedded in an employee name string."""
    if not name:
        return ""
    m = pattern.search(str(name))
    return norm_id(m.group(1)) if m else ""


def safe_float(value, default=0.0) -> float:
    """Convert to float, returning default on failure."""
    try:
        return float(value) if pd.notna(value) else default
    except (ValueError, TypeError):
        return default


def parse_pay_period(pay_period_str: str):
    """Parse 'MM/DD/YYYY - MM/DD/YYYY' into (start_date, end_date)."""
    parts = str(pay_period_str).split(" - ")
    if len(parts) != 2:
        return None, None
    try:
        start = pd.to_datetime(parts[0].strip()).date()
        end = pd.to_datetime(parts[1].strip()).date()
        return start, end
    except Exception:
        return None, None


# ---------------------------------------------------------------------------
# Data loading
# ---------------------------------------------------------------------------

def load_sheets(input_path: str) -> dict:
    """Load all required sheets from an Excel file."""
    required = ["$data", "Hours", "NetPay", "PTOBank", "WC", "TDI"]
    sheets = {}
    xls = pd.ExcelFile(input_path)

    for name in required:
        if name in xls.sheet_names:
            df = pd.read_excel(xls, sheet_name=name)
            df.columns = df.columns.str.strip()
            sheets[name] = df
        else:
            print(f"WARNING: Sheet '{name}' not found in {input_path}")
            sheets[name] = pd.DataFrame()

    return sheets


# ---------------------------------------------------------------------------
# Lookup builders
# ---------------------------------------------------------------------------

def build_employee_register(supabase, org_id: str) -> dict:
    """Fetch hr_employee records for the org, keyed by payroll_id."""
    resp = supabase.table("hr_employee").select(
        "id, first_name, last_name, hr_department_id, wc, pay_structure, "
        "overtime_threshold, payroll_id"
    ).eq("org_id", org_id).eq("is_deleted", False).execute()

    register = {}
    for row in resp.data:
        pid = norm_id(row.get("payroll_id", ""))
        if pid:
            register[pid] = row
    return register


def build_hours_map(hours_df: pd.DataFrame) -> dict:
    """Key hours data by normalized emp_id + check_date."""
    hours_map = {}
    for _, row in hours_df.iterrows():
        emp_id = norm_id(row.get("EMPID", ""))
        check_date = pd.to_datetime(row.get("Check Date")).strftime("%Y-%m-%d") if pd.notna(row.get("Check Date")) else ""
        if emp_id and check_date:
            hours_map[f"{emp_id}_{check_date}"] = row
    return hours_map


def build_name_id_map(df: pd.DataFrame, pattern: re.Pattern) -> dict:
    """Build a map keyed by extracted ID from 'Employee Name' column."""
    result = {}
    for _, row in df.iterrows():
        name = str(row.get("Employee Name", ""))
        emp_id = extract_id_from_name(name, pattern)
        if emp_id:
            result[emp_id] = row
    return result


def build_invoice_summary(dollar_df: pd.DataFrame) -> dict:
    """Sum total hours per invoice number."""
    summary = {}
    for _, row in dollar_df.iterrows():
        inv = row.get("Inv No", "")
        hours = safe_float(row.get("Hours"))
        summary[inv] = summary.get(inv, 0) + hours
    return summary


# ---------------------------------------------------------------------------
# Main processing
# ---------------------------------------------------------------------------

def process_payroll(org_id: str, processor: str, input_path: str):
    """Process payroll data and insert into hr_payroll."""

    if not SUPABASE_URL or not SUPABASE_KEY:
        print("ERROR: Set SUPABASE_URL and SUPABASE_SERVICE_KEY environment variables")
        sys.exit(1)

    supabase = create_client(SUPABASE_URL, SUPABASE_KEY)

    # Load input data
    print(f"Loading payroll data from {input_path}...")
    sheets = load_sheets(input_path)
    dollar_df = sheets["$data"]
    hours_df = sheets["Hours"]
    netpay_df = sheets["NetPay"]
    ptobank_df = sheets["PTOBank"]
    wc_df = sheets["WC"]
    tdi_df = sheets["TDI"]

    if dollar_df.empty:
        print("ERROR: $data sheet is empty")
        sys.exit(1)

    # Build lookups
    print("Fetching employee register from Supabase...")
    register = build_employee_register(supabase, org_id)

    hours_map = build_hours_map(hours_df)
    netpay_map = build_name_id_map(netpay_df, re.compile(r"-(\d+)\s*$"))
    pto_map = build_name_id_map(ptobank_df, re.compile(r"EMPLOYEE:\s*(\d+)\s*-", re.I))
    tdi_map = build_name_id_map(tdi_df, re.compile(r"^(\d+)\s*-"))
    wc_map = build_name_id_map(wc_df, re.compile(r"^(\d+)\s*-"))
    inv_summary = build_invoice_summary(dollar_df)

    # Validate — check for missing employees
    missing = []
    seen = set()
    for _, row in dollar_df.iterrows():
        emp_id = norm_id(row.get("Emp ID", ""))
        if not emp_id:
            continue
        if emp_id not in register and emp_id not in seen:
            name = row.get("Full Name", "Unknown")
            missing.append(f"{name} ({emp_id})")
            seen.add(emp_id)

    if missing:
        print("ERROR: The following employees are in the payroll data but missing from hr_employee:")
        for m in missing:
            print(f"  - {m}")
        sys.exit(1)

    # Process each row in $data
    print(f"Processing {len(dollar_df)} payroll records...")
    records = []

    for _, d in dollar_df.iterrows():
        emp_id = norm_id(d.get("Emp ID", ""))
        if not emp_id:
            continue

        reg = register.get(emp_id, {})
        inv_no = d.get("Inv No", "")

        check_date = pd.to_datetime(d.get("Check Date"))
        check_date_str = check_date.strftime("%Y-%m-%d")
        check_key = f"{emp_id}_{check_date_str}"

        hr = hours_map.get(check_key, {})
        net = netpay_map.get(emp_id, {})
        pto = pto_map.get(emp_id, {})
        tdi_row = tdi_map.get(emp_id, {})
        wc_row = wc_map.get(emp_id, {})

        # Parse pay period
        pay_period_start, pay_period_end = parse_pay_period(d.get("Pay Period", ""))

        # Determine WC amount
        wc_amount = 0
        for col in ["WC 0008", "WC 8810", "WC 8742"]:
            val = safe_float(wc_row.get(col) if isinstance(wc_row, dict) else wc_row.get(col, 0) if hasattr(wc_row, 'get') else 0)
            if val > 0:
                wc_amount = val
                break

        # Get hours data (may be dict or Series)
        def get_hr(key, default=0):
            if isinstance(hr, dict):
                return safe_float(hr.get(key, default))
            return safe_float(hr.get(key, default) if hasattr(hr, 'get') else default)

        def get_net(key, default=0):
            if isinstance(net, dict):
                return safe_float(net.get(key, default))
            return safe_float(net.get(key, default) if hasattr(net, 'get') else default)

        record = {
            "org_id": org_id,
            "hr_employee_id": reg.get("id", ""),
            "payroll_id": emp_id,

            # Pay period
            "pay_period_start": str(pay_period_start) if pay_period_start else None,
            "pay_period_end": str(pay_period_end) if pay_period_end else None,
            "check_date": check_date_str,
            "invoice_number": str(inv_no) if inv_no else None,
            "payroll_processor": processor,
            "is_standard": (inv_summary.get(inv_no, 0) > INVOICE_STANDARD_THRESHOLD),

            # Employee snapshot
            "employee_name": d.get("Full Name", "ADJUSTMENT"),
            "hr_department_id": reg.get("hr_department_id"),
            "wc": reg.get("wc"),
            "pay_structure": reg.get("pay_structure"),
            "hourly_rate": get_net("Hourly Rate"),
            "overtime_threshold": safe_float(reg.get("overtime_threshold")),

            # Hours
            "regular_hours": get_hr("Regular Hours"),
            "overtime_hours": get_hr("Overtime Hours"),
            "holiday_hours": get_hr("Holiday Hours", 0),
            "pto_hours": get_hr("PTO Hours"),
            "sick_hours": get_hr("Sick Hours", 0),
            "funeral_hours": get_hr("Funeral Hours", 0),
            "total_hours": get_hr("Total Hours"),
            "pto_hours_accrued": safe_float(
                pto.get("Net YTD Hours Accrued", 0)
                if isinstance(pto, dict) else
                (pto.get("Net YTD Hours Accrued", 0) if hasattr(pto, 'get') else 0)
            ),

            # Earnings
            "regular_pay": get_hr("Regular Pay"),
            "overtime_pay": get_hr("Overtime Pay"),
            "holiday_pay": get_hr("Holiday Pay", 0),
            "pto_pay": get_hr("PTO Pay"),
            "sick_pay": get_hr("Sick Pay", 0),
            "funeral_pay": get_hr("Funeral Pay", 0),
            "other_pay": get_hr("Other Pay"),
            "bonus_pay": get_net("Bonus"),
            "auto_allowance": get_net("Auto Allowances"),
            "per_diem": get_net("Per Diem"),
            "salary": get_net("Salary"),
            "gross_wage": safe_float(d.get("Gross Wages")),

            # Employee deductions
            "fit": get_net("FIT"),
            "sit": get_net("SIT"),
            "social_security": get_net("Social Security"),
            "medicare": get_net("Medicare"),
            "comp_plus": get_net("Comp Plus"),
            "hds_dental": get_net("HDS Dental"),
            "pre_tax_401k": get_net("PreTax 401K"),
            "auto_deduction": get_net("Auto Deduction"),
            "child_support": get_net("Child Support"),
            "program_fees": get_net("Program Fees"),
            "net_pay": get_net("Net Pay"),

            # Employer costs
            "labor_tax": safe_float(d.get("Labor Fees")),
            "other_tax": safe_float(d.get("Other Tax")),
            "workers_compensation": safe_float(d.get("Workers Comp")),
            "health_benefits": safe_float(d.get("Health Benefits")),
            "other_health_charges": safe_float(d.get("Oth Health Chgs")),
            "admin_fees": safe_float(d.get("Admin Fees")),
            "hawaii_get": safe_float(d.get("Hawaii GET")),
            "other_charges": safe_float(d.get("Other Charges")),
            "tdi": safe_float(
                tdi_row.get("Employer TDI", 0)
                if isinstance(tdi_row, dict) else
                (tdi_row.get("Employer TDI", 0) if hasattr(tdi_row, 'get') else 0)
            ),
            "total_cost": safe_float(d.get("Total Cost")),
        }

        records.append(record)

    # Insert into Supabase
    if records:
        print(f"Inserting {len(records)} records into hr_payroll...")
        batch_size = 100
        for i in range(0, len(records), batch_size):
            batch = records[i:i + batch_size]
            supabase.table("hr_payroll").insert(batch).execute()
            print(f"  Inserted batch {i // batch_size + 1} ({len(batch)} records)")

    print(f"Payroll processing complete. {len(records)} records inserted.")
    return records


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Import payroll data into Supabase hr_payroll")
    parser.add_argument("--org_id", required=True, help="Organization ID")
    parser.add_argument("--processor", required=True, help="Payroll processor identifier (e.g. HRB, HF)")
    parser.add_argument("--input", required=True, help="Path to Excel file with payroll tabs")

    args = parser.parse_args()
    process_payroll(args.org_id, args.processor, args.input)
