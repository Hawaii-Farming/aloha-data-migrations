"""
Reset an auth.users password by email.

Env vars (all required):
    SUPABASE_URL            Project URL, e.g. https://<ref>.supabase.co
    SUPABASE_SERVICE_KEY    service_role key
    RESET_EMAIL             Email of the account to reset
    RESET_PASSWORD          New plaintext password

Looks the user up by email via the admin API, then PUTs the new password.
Errors out (non-zero exit) if no user matches.
"""
import json
import os
import sys
import urllib.error
import urllib.request

SUPABASE_URL = os.environ["SUPABASE_URL"].rstrip("/")
SERVICE_KEY = os.environ["SUPABASE_SERVICE_KEY"]
EMAIL = os.environ["RESET_EMAIL"].strip().lower()
PASSWORD = os.environ["RESET_PASSWORD"]

HEADERS = {
    "apikey": SERVICE_KEY,
    "Authorization": f"Bearer {SERVICE_KEY}",
    "Content-Type": "application/json",
}


def _request(method, url, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers=HEADERS)
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


def find_user(email):
    _status, data = _request("GET", f"{SUPABASE_URL}/auth/v1/admin/users?per_page=1000")
    for u in data.get("users", []):
        if (u.get("email") or "").lower() == email:
            return u
    return None


def main():
    print(f"Target: {SUPABASE_URL}")
    user = find_user(EMAIL)
    if not user:
        print(f"  No auth user with email={EMAIL}", file=sys.stderr)
        sys.exit(1)
    uid = user["id"]
    _request("PUT", f"{SUPABASE_URL}/auth/v1/admin/users/{uid}", body={"password": PASSWORD})
    print(f"  Reset password for {EMAIL} (user_id={uid})")


if __name__ == "__main__":
    main()
