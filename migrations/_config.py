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


# ---------------------------------------------------------------------------
# Transient-error retry for postgrest execute()
# ---------------------------------------------------------------------------
# Every migration imports `_config`, so patching postgrest's sync request
# builders here gives all 26 migrations retry-with-backoff on Supabase edge
# hiccups (Cloudflare 502/503/504, network timeouts) without editing their
# individual insert_rows helpers. Retries are bounded (3 attempts after the
# first) with exponential backoff.

_TRANSIENT_HTTP_CODES = {500, 502, 503, 504}
_TRANSIENT_EXC_NAMES = {
    "ConnectError", "ReadError", "RemoteProtocolError",
    "TimeoutException", "ReadTimeout", "ConnectTimeout", "PoolTimeout",
}
_MAX_ATTEMPTS = 4


def _install_postgrest_retry():
    import functools
    import time

    try:
        from postgrest._sync import request_builder as rb
        from postgrest.exceptions import APIError
    except ImportError:
        return

    def _transient_api_error(err: "APIError") -> bool:
        try:
            code = int(err.code) if err.code is not None else None
        except (TypeError, ValueError):
            code = None
        return code in _TRANSIENT_HTTP_CODES

    def _wrap_execute(original):
        @functools.wraps(original)
        def retry_execute(self, *args, **kwargs):
            for attempt in range(_MAX_ATTEMPTS):
                try:
                    return original(self, *args, **kwargs)
                except APIError as e:
                    if _transient_api_error(e) and attempt < _MAX_ATTEMPTS - 1:
                        wait = 2 ** attempt
                        print(
                            f"  [retry] postgrest code={e.code}; "
                            f"retrying in {wait}s (attempt {attempt + 1}/{_MAX_ATTEMPTS - 1})"
                        )
                        time.sleep(wait)
                        continue
                    raise
                except Exception as e:
                    if type(e).__name__ in _TRANSIENT_EXC_NAMES and attempt < _MAX_ATTEMPTS - 1:
                        wait = 2 ** attempt
                        print(
                            f"  [retry] {type(e).__name__}; "
                            f"retrying in {wait}s (attempt {attempt + 1}/{_MAX_ATTEMPTS - 1})"
                        )
                        time.sleep(wait)
                        continue
                    raise
            # Unreachable — the loop either returns or raises.
            raise RuntimeError("retry loop exited without a return or raise")
        return retry_execute

    # Builders that define their own execute(): patch each in place.
    for cls_name in (
        "SyncQueryRequestBuilder",
        "SyncSingleRequestBuilder",
        "SyncMaybeSingleRequestBuilder",
        "SyncExplainRequestBuilder",
    ):
        cls = getattr(rb, cls_name, None)
        if cls is not None and "execute" in cls.__dict__:
            cls.execute = _wrap_execute(cls.execute)


_install_postgrest_retry()
