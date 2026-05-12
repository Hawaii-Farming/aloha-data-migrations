"""
One-shot: create auth.users + link hr_employee.user_id for new HF employees.

Idempotent: if an auth user already exists for the email we skip the create
and just (re)link hr_employee.user_id. Safe to re-run.

Env vars (all required):
    SUPABASE_URL                Project URL, e.g. https://<ref>.supabase.co
    SUPABASE_SERVICE_KEY        service_role key (admin auth + DB write)
    INITIAL_PASSWORD            Plaintext password set on every new account
"""
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

# (hr_employee.id, email, friendly label for logs)
EMPLOYEES = [
    ("alcantara_maria",  "maju@hawaiifarming.com",   "Maria Alcantara (Maju)"),
    ("soares_victoria",  "vicky@hawaiifarming.com",  "Victoria Soares (Vicky)"),
    ("javillonar_maria", "maria@hawaiifarming.com",  "Maria Javillonar"),
    ("minor_childers",   "minor.childers@gmail.com", "Minor Childers"),
]
ORG_ID = "hawaii_farming"

SUPABASE_URL = os.environ["SUPABASE_URL"].rstrip("/")
SERVICE_KEY = os.environ["SUPABASE_SERVICE_KEY"]
PASSWORD = os.environ["INITIAL_PASSWORD"]

HEADERS = {
    "apikey": SERVICE_KEY,
    "Authorization": f"Bearer {SERVICE_KEY}",
    "Content-Type": "application/json",
}


def _request(method, url, body=None, extra_headers=None):
    headers = dict(HEADERS, **(extra_headers or {}))
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            raw = r.read()
            return r.status, json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            payload = json.loads(raw)
        except Exception:
            payload = raw.decode(errors="replace")
        raise SystemExit(f"{method} {url} -> {e.code}: {payload}")


def find_auth_user_by_email(email):
    # Small project — list-and-grep is fine.
    _status, data = _request("GET", f"{SUPABASE_URL}/auth/v1/admin/users?per_page=1000")
    for u in data.get("users", []):
        if (u.get("email") or "").lower() == email.lower():
            return u
    return None


def create_auth_user(email):
    body = {"email": email, "password": PASSWORD, "email_confirm": True}
    _status, data = _request("POST", f"{SUPABASE_URL}/auth/v1/admin/users", body)
    return data


def link_hr_employee(emp_id, user_uuid):
    qs = urllib.parse.urlencode({"id": f"eq.{emp_id}", "org_id": f"eq.{ORG_ID}"})
    url = f"{SUPABASE_URL}/rest/v1/hr_employee?{qs}"
    _request("PATCH", url, body={"user_id": user_uuid}, extra_headers={"Prefer": "return=minimal"})


def main():
    print(f"Target: {SUPABASE_URL}")
    for emp_id, email, label in EMPLOYEES:
        existing = find_auth_user_by_email(email)
        if existing:
            user_uuid = existing["id"]
            print(f"  [{label}] auth user already exists ({user_uuid}); relinking only")
        else:
            created = create_auth_user(email)
            user_uuid = created["id"]
            print(f"  [{label}] created auth user {user_uuid}")
        link_hr_employee(emp_id, user_uuid)
        print(f"  [{label}] linked hr_employee.user_id={user_uuid} on {emp_id}")
    print("Done.")


if __name__ == "__main__":
    main()
