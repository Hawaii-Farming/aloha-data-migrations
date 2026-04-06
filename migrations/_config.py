"""
Shared configuration for all migration scripts.

Centralizes Supabase connection details, audit user, default org_id, and
Google Sheet IDs so they're not duplicated across every script. Migration
scripts should `from _config import ...` rather than redeclaring these.

All values can be overridden via environment variables or a .env file at
the repo root. The defaults match the dev/hosted Supabase project.
"""

import os

# ---------------------------------------------------------------------------
# Environment loading
# ---------------------------------------------------------------------------
# Lightweight .env parser. Loads only on first import. We don't use python-dotenv
# to keep the migration scripts dependency-free beyond what's already required.

_env_loaded = False


def _load_env_file():
    global _env_loaded
    if _env_loaded:
        return
    _env_loaded = True

    try:
        with open(".env") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, _, value = line.partition("=")
                key = key.strip()
                value = value.strip().strip('"').strip("'")
                # Only set if not already in environment (env wins)
                if key and key not in os.environ:
                    os.environ[key] = value
    except FileNotFoundError:
        pass


_load_env_file()


# ---------------------------------------------------------------------------
# Supabase connection
# ---------------------------------------------------------------------------

SUPABASE_URL = os.environ.get(
    "SUPABASE_URL", "https://kfwqtaazdankxmdlqdak.supabase.co"
)
SUPABASE_KEY = os.environ.get("SUPABASE_SERVICE_KEY")

# ---------------------------------------------------------------------------
# Tenant defaults
# ---------------------------------------------------------------------------

AUDIT_USER = os.environ.get("MIGRATION_AUDIT_USER", "data@hawaiifarming.com")
ORG_ID = os.environ.get("MIGRATION_ORG_ID", "hawaii_farming")

# ---------------------------------------------------------------------------
# Google Sheet IDs
# ---------------------------------------------------------------------------
# Each sheet ID can be overridden via environment variable for testing or
# pointing at a sandbox copy.

SHEET_IDS = {
    # Food safety lookup data + corrective actions
    "fsafe": os.environ.get(
        "SHEET_FSAFE", "1MbHJoJmq0w8hWz8rl9VXezmK-63MFmuK19lz3pu0dfc"
    ),
    # Food safety test results (EMP, water, test-and-hold)
    "fsafe_results": os.environ.get(
        "SHEET_FSAFE_RESULTS", "1MbHJoJmq0w8hWz8rl9VXezmK-63MFmuK19lz3pu0dfc"
    ),
    # Operations training records
    "ops_training": os.environ.get(
        "SHEET_OPS_TRAINING", "1MbHJoJmq0w8hWz8rl9VXezmK-63MFmuK19lz3pu0dfc"
    ),
}


def require_supabase_key():
    """Validate that SUPABASE_SERVICE_KEY is set, exit with a helpful error if not."""
    if not SUPABASE_KEY:
        raise SystemExit(
            "ERROR: Set SUPABASE_SERVICE_KEY in .env or environment\n"
            "  Get it from: Supabase Dashboard -> Settings -> API -> service_role key"
        )
    return SUPABASE_KEY
