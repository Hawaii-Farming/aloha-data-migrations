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
    # External-lab chemistry results (lettuce ponds + water source)
    "chemistry": os.environ.get(
        "SHEET_CHEMISTRY", "1XwavjRPi3xMJClslOjuC_4ONrbdl8l_qw0_JallE2c0"
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
# Naming — the canonical proper_case() helper used across migrations
# ---------------------------------------------------------------------------
# Every text PK in the schema (display name) is run through this so we get
# consistent capitalization, preserved acronyms, and lowercase stop-words in
# the middle of phrases. Word boundaries handled: spaces, hyphens, slashes,
# and parens. Single-letter and digit-only tokens stay as-is.

import re

# Acronyms that must remain ALL-CAPS regardless of position. Add to this set
# as new domain-specific abbreviations turn up.
ACRONYMS = {
    # Site / facility codes
    "GH", "PH", "BIP", "JTL", "KO", "HK", "WA", "HI", "BB", "NE", "NW",
    # Workers comp / authorization codes
    "WFE", "FUERTE", "1099", "H1", "H2A", "H3",
    # Lab tests + sample types
    "APC", "TC", "LM", "ATP", "RLU", "EMP",
    # Tech / packaging
    "AC", "PV", "CRM", "PO", "HF", "HFA", "GTIN", "UPC", "FOB",
    # Common business / legal
    "USA", "USD", "QB", "OK", "FAQ", "PDF", "URL", "SKU", "CSV", "GH/PH",
    # Cuke product codes (sales_product short codes)
    "AF", "AR", "EF", "ER", "EW", "JF", "JR", "JW", "KF", "KR", "KW",
    "LF", "LR", "LW", "OE", "OJ", "OK", "WF", "WR",
    # Variety codes
    "GA", "GB", "GC", "GF", "GG", "GL", "GO", "GR", "MG", "MS", "MT",
    "RA", "RB", "RC", "RF", "RG", "RL", "RO", "RR", "TR", "WC",
    # Misc
    "TDI", "FIT", "SIT", "401K", "GET", "FSMA",
    # HR / time-off / safety
    "PTO", "PPE",
    # Inventory dimensions / units (omit IN — collides with the preposition "in")
    "OD", "ID", "OZ", "LB", "QT", "GAL", "ML", "KG", "MM", "CM", "FT",
    # Equipment / electrical
    "VDC", "VAC", "DC", "RPM", "PSI", "GPM", "GPH", "BTU", "LED",
    # Measurement abbreviations
    "PPM",
}

# Stop words that stay lowercase when they appear in the middle of a phrase
# (still capitalized at the start). Multi-letter words only — single letters
# in our domain are almost always abbreviations rather than articles.
_STOP_WORDS = {
    "and", "as", "at", "but", "by", "for", "from", "in", "of",
    "on", "or", "the", "to", "vs", "with",
}

# Word boundaries are spaces, hyphens, slashes, commas. Apostrophes and
# parentheses are NOT boundaries — "Pete's" stays one word, as does "Bird(s)".
# A "word" then has internal punctuation that must be preserved.
_WORD_SPLIT = re.compile(r"([\s\-/,]+)")


def _case_word(word, is_first):
    """Capitalize a single word, honouring acronyms, stop words, and
    internal punctuation like apostrophes or parentheses."""
    if not word or not any(c.isalnum() for c in word):
        return word
    # Strip alnum-only stem to compare against acronym/stopword sets.
    alnum = "".join(c for c in word if c.isalnum())
    if not alnum:
        return word
    upper_alnum = alnum.upper()
    if upper_alnum in ACRONYMS:
        # Map every alnum char to its upper-case form, leaving punctuation alone.
        return "".join(c.upper() if c.isalnum() else c for c in word)
    # Mixed alphanumeric part codes (e.g. "20A12Vdc"): preserve as-is. Heuristic:
    # has both digits and letters AND two or more uppercase letters in the input.
    has_digit = any(c.isdigit() for c in word)
    has_alpha = any(c.isalpha() for c in word)
    if has_digit and has_alpha and sum(1 for c in word if c.isupper()) >= 2:
        return word
    lower_alnum = alnum.lower()
    if not is_first and lower_alnum in _STOP_WORDS:
        return word.lower()
    # Title-case. Apostrophes mark sub-word boundaries (Hawaiian okina, e.g.,
    # "U'Ilani" -> "U'Ilani"). The English possessive ("Pete's", "po's") is the
    # exception: if the segment after an apostrophe is a single letter, treat
    # it as a suffix and lowercase it.
    segments = word.split("'")
    cased = []
    for i, seg in enumerate(segments):
        if not seg:
            cased.append(seg)
            continue
        if i > 0 and len(seg) <= 1:
            cased.append(seg.lower())
            continue
        out = []
        capitalized = False
        for c in seg:
            if not capitalized and c.isalpha():
                out.append(c.upper())
                capitalized = True
            else:
                out.append(c.lower() if c.isalpha() else c)
        cased.append("".join(out))
    return "'".join(cased)


def proper_case(value):
    """Convert a free-text label to the canonical Proper Case used as a PK.

    Rules:
      - Title-case every word, preserve acronyms in ACRONYMS as-is.
      - Lowercase multi-letter stop-words ("of", "and", "in", ...) in mid-phrase.
      - Single letters / digits are kept upper-case (likely abbreviations).
      - Preserve internal punctuation (hyphens, slashes, parens, apostrophes).
      - Trim outer whitespace; collapse internal whitespace runs to a single space.
      - Empty / None inputs return as-is.
    """
    if value is None:
        return None
    s = str(value).strip()
    if not s:
        return s
    s = re.sub(r"\s+", " ", s)
    parts = _WORD_SPLIT.split(s)
    out = []
    seen_word = False
    for p in parts:
        if any(c.isalnum() for c in p):
            out.append(_case_word(p, is_first=not seen_word))
            seen_word = True
        else:
            out.append(p)
    return "".join(out)


def slug_to_proper_case(slug):
    """Convert a slug like 'abraham_jason' or 'cuke_harvest_a' to proper case
    ('Abraham Jason', 'Cuke Harvest A'). Underscores become spaces.
    """
    if not slug:
        return slug
    return proper_case(str(slug).replace("_", " "))


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

    # Build a fake empty postgrest response so retry-after-write can return
    # cleanly when the server committed the original request but the client
    # got a network error mid-flight.
    class _FakeResponse:
        def __init__(self):
            self.data = []
            self.count = None

    def _wrap_execute(original):
        @functools.wraps(original)
        def retry_execute(self, *args, **kwargs):
            had_network_retry = False
            for attempt in range(_MAX_ATTEMPTS):
                try:
                    return original(self, *args, **kwargs)
                except APIError as e:
                    # 23505 = duplicate_key. If we just retried after a
                    # transient network error, the original request likely
                    # committed server-side — treat the dupe as success.
                    if had_network_retry and getattr(e, "code", None) == "23505":
                        print(
                            f"  [retry] swallowed duplicate_key after network "
                            f"retry — original write succeeded server-side"
                        )
                        return _FakeResponse()
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
                        had_network_retry = True
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
