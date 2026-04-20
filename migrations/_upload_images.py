"""
Upload Drive image folders to Supabase storage.

Walks specified Google Drive folders, downloads each image, and uploads it
to the Supabase `images` bucket at the normalized path that matches the
current DB schema (e.g. legacy `images/hr_photo/X.jpg` -> `hr_employee/X.jpg`).

Designed to be re-runnable: for each file, it first checks whether the
destination already exists in Supabase and skips if so.

Usage:
    python migrations/_upload_images.py                     # all folders
    python migrations/_upload_images.py --only hr_employee  # one folder
    python migrations/_upload_images.py --only hr_employee,sales_product

Environment:
    Reads .env (via _config lightweight parser) for SUPABASE_URL,
    SUPABASE_SERVICE_KEY, and SUPABASE_DB_URL.
    Uses Google service account credentials.json for Drive access.
"""

import argparse
import io
import os
import sys
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

import psycopg2
from google.oauth2.service_account import Credentials
from googleapiclient.discovery import build
from googleapiclient.http import MediaIoBaseDownload
from supabase import create_client

from _config import SUPABASE_URL, require_supabase_key

BUCKET = "images"
MAX_WORKERS = 10

# ---------------------------------------------------------------------------
# Drive source folders -> destination subpath in the bucket
# ---------------------------------------------------------------------------
#
# Each entry is: (drive_folder_id, destination_subpath, optional_filename_router)
#
# filename_router: when set, a function(filename) -> destination subpath.
# Used for images/invnt/ which fans out to invnt_item/, invnt_po/,
# invnt_po_received/ depending on which DB table references the file.

DRIVE_FOLDER_IDS = {
    "hr_employee":               "1thD1kIvH8IZX6MwqZK9lpJhDF1F0-0Rn",
    "images_root":               "135MYo-Jvc8zm8bbKXtpuTwBxZ-cPqmf0",
    "grow_scouting_observations_Images": "1kMufL1xPVBLHUi_Df09kG0VuOrn1mNx2",
    "grow_scouting_Images":      "1VVKQG7FhC_k8aULHlCYjf3e9z8p9q693",
    "fsafe_log_pest_Images":     "1IiIQl9MzdhVeDUyQ9Oif6LtXIrOcEFCk",
    "proc_requests_Images":      "1FX50jz20CRCsh9E3k6AOOJPEW8mebMMd",
    "Orders_1":                  "1O-NIMdT_bAb6R113YIMlFmeOK3V9Wnmb",
    "Orders_2":                  "1OL5m82Ej0mKDtkic1EWbJ2846ohdUhTo",
    "Orders_3":                  "10Hlj3I24l819xseCgRBN_tQdFiHqVvwB",
}

# Subfolder IDs under images/ (discovered via list() call)
# name -> id discovered at runtime; see resolve_subfolders()
IMAGES_SUBFOLDERS = [
    # (subfolder_name_in_drive, destination_subpath, router_needed)
    ("hr_photo",               "hr_employee", False),
    ("sales_products",         "sales_product", False),
    ("sales_ext",              "sales_crm_store_visit", False),
    ("maint",                  "maint_request", False),
    ("pack_slife",             "pack_shelf_life", False),
    ("fsafe_foreign_material", "ops_template_result", False),
    ("grow_chem",              "grow_task/monitoring", False),
    # `invnt` fans out by filename — handled specially
    ("invnt",                  None, True),
]

# Standalone Drive folders (outside the images/ tree)
STANDALONE_FOLDERS = [
    # (drive_id, destination_subpath)
    ("1kMufL1xPVBLHUi_Df09kG0VuOrn1mNx2", "grow_task/scouting"),   # grow_scouting_observations_Images
    ("1VVKQG7FhC_k8aULHlCYjf3e9z8p9q693", "grow_task/scouting"),   # grow_scouting_Images
    ("1IiIQl9MzdhVeDUyQ9Oif6LtXIrOcEFCk", "fsafe_pest_result"),    # fsafe_log_pest_Images
    ("1FX50jz20CRCsh9E3k6AOOJPEW8mebMMd", "invnt_po"),             # proc_requests_Images
    ("1O-NIMdT_bAb6R113YIMlFmeOK3V9Wnmb", "invnt_po_received"),    # ORDERS
    ("1OL5m82Ej0mKDtkic1EWbJ2846ohdUhTo", "invnt_po_received"),    # Orders
    ("10Hlj3I24l819xseCgRBN_tQdFiHqVvwB", "invnt_po_received"),    # ORDERS (dup)
]


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def load_env():
    """Lightweight .env loader so we can run without extra deps."""
    try:
        with open(".env") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, _, v = line.partition("=")
                k, v = k.strip(), v.strip().strip('"').strip("'")
                if k and k not in os.environ:
                    os.environ[k] = v
    except FileNotFoundError:
        pass


def get_drive_service():
    creds = Credentials.from_service_account_file(
        "credentials.json", scopes=["https://www.googleapis.com/auth/drive.readonly"]
    )
    return build("drive", "v3", credentials=creds, cache_discovery=False)


def get_sb():
    return create_client(SUPABASE_URL, require_supabase_key())


# ---------------------------------------------------------------------------
# Thread-local client cache
# ---------------------------------------------------------------------------
# googleapiclient.build() returns a Resource that wraps an httplib2.Http
# instance, which is NOT thread-safe. Sharing one across ThreadPoolExecutor
# workers causes native segfaults on Linux (we hit this in the nightly).
# supabase-py's Client is also not documented as thread-safe for uploads.
# Give each worker thread its own clients via threading.local().

_thread_local = threading.local()


def get_thread_drive():
    if not hasattr(_thread_local, "drive"):
        _thread_local.drive = get_drive_service()
    return _thread_local.drive


def get_thread_sb():
    if not hasattr(_thread_local, "sb"):
        _thread_local.sb = get_sb()
    return _thread_local.sb


def list_drive_folder(drive, folder_id):
    """Return list of {id, name, mimeType, size} for all files (paginated)."""
    files = []
    page_token = None
    while True:
        resp = drive.files().list(
            q=f"'{folder_id}' in parents and trashed=false",
            fields="nextPageToken, files(id, name, size, mimeType)",
            pageSize=1000,
            pageToken=page_token,
            includeItemsFromAllDrives=True, supportsAllDrives=True,
        ).execute()
        files.extend(resp.get("files", []))
        page_token = resp.get("nextPageToken")
        if not page_token:
            break
    return files


def resolve_subfolder_id(drive, parent_id, name):
    """Find a subfolder by exact name under a parent."""
    resp = drive.files().list(
        q=f"'{parent_id}' in parents and name='{name}' and "
          f"mimeType='application/vnd.google-apps.folder' and trashed=false",
        fields="files(id, name)",
        includeItemsFromAllDrives=True, supportsAllDrives=True,
    ).execute()
    files = resp.get("files", [])
    return files[0]["id"] if files else None


def list_existing_destinations(sb, subpath):
    """Return set of filenames already in bucket under subpath."""
    existing = set()
    offset = 0
    limit = 1000
    while True:
        items = sb.storage.from_(BUCKET).list(subpath, {"limit": limit, "offset": offset})
        if not items:
            break
        existing.update(it["name"] for it in items)
        if len(items) < limit:
            break
        offset += limit
    return existing


def build_invnt_router(conn):
    """Build a filename -> destination_subpath router for images/invnt/.

    Queries the DB for every file that was a member of the old images/invnt/
    folder (now rewritten to images/invnt_item/, images/invnt_po/, or
    images/invnt_po_received/). Returns dict {bare_filename: subpath}.

    Falls back to invnt_item for any unknown filename.
    """
    filenames = {}

    def add(filename, subpath):
        # First writer wins — an invnt_po reference beats invnt_item for the
        # same filename because images shared across tables were stored under
        # images/invnt/ in the legacy source, but the DB reference determines
        # where the file logically belongs.
        filenames.setdefault(filename, subpath)

    cur = conn.cursor()
    # invnt_item.photos (jsonb array of text paths)
    cur.execute("""
        SELECT elem FROM invnt_item,
        LATERAL jsonb_array_elements_text(photos) elem
        WHERE photos IS NOT NULL AND jsonb_array_length(photos) > 0
    """)
    for (path,) in cur.fetchall():
        if path and path.startswith("images/invnt_item/"):
            add(path[len("images/invnt_item/"):], "invnt_item")

    cur.execute("""
        SELECT elem FROM invnt_po,
        LATERAL jsonb_array_elements_text(request_photos) elem
        WHERE request_photos IS NOT NULL AND jsonb_array_length(request_photos) > 0
    """)
    for (path,) in cur.fetchall():
        if path and path.startswith("images/invnt_po/"):
            add(path[len("images/invnt_po/"):], "invnt_po")

    cur.execute("""
        SELECT elem FROM invnt_po_received,
        LATERAL jsonb_array_elements_text(received_photos) elem
        WHERE received_photos IS NOT NULL AND jsonb_array_length(received_photos) > 0
    """)
    for (path,) in cur.fetchall():
        if path and path.startswith("images/invnt_po_received/"):
            add(path[len("images/invnt_po_received/"):], "invnt_po_received")
    cur.close()

    return filenames


def upload_one(file_meta, dest_subpath, stats, stats_lock):
    """Download one file from Drive and upload to Supabase.

    Resolves drive + supabase clients from thread-local storage so each
    worker thread gets its own instance — sharing one googleapiclient
    Resource across threads segfaults.
    """
    drive = get_thread_drive()
    sb = get_thread_sb()
    name = file_meta["name"]
    content_type = file_meta.get("mimeType") or "image/jpeg"
    try:
        req = drive.files().get_media(fileId=file_meta["id"])
        buf = io.BytesIO()
        downloader = MediaIoBaseDownload(buf, req)
        done = False
        while not done:
            _, done = downloader.next_chunk()
        sb.storage.from_(BUCKET).upload(
            path=f"{dest_subpath}/{name}",
            file=buf.getvalue(),
            file_options={"content-type": content_type, "upsert": "true"},
        )
        with stats_lock:
            stats["uploaded"] += 1
            if stats["uploaded"] % 100 == 0:
                print(f"    ... {stats['uploaded']} uploaded")
    except Exception as e:
        msg = str(e)
        with stats_lock:
            # 413 = Supabase bucket per-object size limit. Not a retryable
            # failure; the file is permanently too large for this bucket.
            # Bucket these separately so they don't pollute the failure list.
            if "'statusCode': 413" in msg or "Payload too large" in msg:
                stats["oversized"].append(name)
            else:
                stats["failed"].append((name, msg[:120]))


def process_folder(drive, sb, drive_folder_id, dest_subpath, router=None, label=None):
    """Process one Drive folder -> one (or many, via router) bucket subpath(s).

    The `drive` and `sb` passed in are used only on the main thread for the
    serial listing calls. Workers inside the ThreadPoolExecutor resolve their
    own thread-local clients via get_thread_drive() / get_thread_sb().
    """
    label = label or dest_subpath or "(router)"
    print(f"\n--- {label} ---")
    files = list_drive_folder(drive, drive_folder_id)
    print(f"  Drive source files: {len(files)}")

    if not files:
        return 0, 0

    # Group files by destination subpath (most folders map 1:1, but the
    # invnt/ router may split across several targets).
    by_dest = {}
    for f in files:
        dest = router(f["name"]) if router else dest_subpath
        if dest is None:
            continue  # router returned None — skip this file
        by_dest.setdefault(dest, []).append(f)

    total_uploaded = 0
    total_skipped = 0
    total_failed = []

    for dest, dest_files in by_dest.items():
        existing = list_existing_destinations(sb, dest)
        to_upload = [f for f in dest_files if f["name"] not in existing]
        skipped = len(dest_files) - len(to_upload)
        print(f"  -> {dest}: {len(to_upload)} to upload ({skipped} already present)")

        if not to_upload:
            total_skipped += skipped
            continue

        stats = {"uploaded": 0, "failed": [], "oversized": []}
        stats_lock = threading.Lock()
        with ThreadPoolExecutor(max_workers=MAX_WORKERS) as pool:
            futures = [
                pool.submit(upload_one, f, dest, stats, stats_lock)
                for f in to_upload
            ]
            for _ in as_completed(futures):
                pass

        parts = [f"{stats['uploaded']} uploaded"]
        if stats["oversized"]:
            parts.append(f"{len(stats['oversized'])} oversized (>bucket limit)")
        if stats["failed"]:
            parts.append(f"{len(stats['failed'])} failed")
        print(f"  -> {dest}: " + ", ".join(parts))
        total_uploaded += stats["uploaded"]
        total_skipped += skipped
        total_failed.extend([(dest, *err) for err in stats["failed"]])

    if total_failed:
        print(f"  ! {len(total_failed)} failures:")
        for err in total_failed[:5]:
            print(f"      {err}")
    return total_uploaded, total_skipped


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--only",
        help="Comma-separated list of destination subpaths to process "
             "(e.g. 'hr_employee,sales_product'). Default: all.",
    )
    args = parser.parse_args()

    load_env()
    only = set(a.strip() for a in args.only.split(",")) if args.only else None

    drive = get_drive_service()
    sb = get_sb()
    conn = psycopg2.connect(os.environ["SUPABASE_DB_URL"])
    conn.autocommit = True

    # Build invnt router
    invnt_router_map = build_invnt_router(conn)
    print(f"invnt router: {len(invnt_router_map)} known filenames -> "
          f"{set(invnt_router_map.values())}")

    def invnt_router(filename):
        return invnt_router_map.get(filename, "invnt_item")  # fallback

    # Resolve subfolder IDs under images/
    images_root_id = DRIVE_FOLDER_IDS["images_root"]
    tasks = []  # list of (drive_folder_id, dest_subpath, router, label)

    for sub_name, dest, use_router in IMAGES_SUBFOLDERS:
        sub_id = resolve_subfolder_id(drive, images_root_id, sub_name)
        if not sub_id:
            print(f"⚠ subfolder not found: images/{sub_name}")
            continue
        # dest is None when router is used
        label = f"images/{sub_name} -> " + (dest or "(routed)")
        if use_router:
            tasks.append((sub_id, None, invnt_router, label))
        else:
            tasks.append((sub_id, dest, None, label))

    # Standalone top-level folders
    standalone_labels = {
        "1kMufL1xPVBLHUi_Df09kG0VuOrn1mNx2": "grow_scouting_observations_Images -> grow_task/scouting",
        "1VVKQG7FhC_k8aULHlCYjf3e9z8p9q693": "grow_scouting_Images -> grow_task/scouting",
        "1IiIQl9MzdhVeDUyQ9Oif6LtXIrOcEFCk": "fsafe_log_pest_Images -> fsafe_pest_result",
        "1FX50jz20CRCsh9E3k6AOOJPEW8mebMMd": "proc_requests_Images -> invnt_po",
        "1O-NIMdT_bAb6R113YIMlFmeOK3V9Wnmb": "ORDERS -> invnt_po_received",
        "1OL5m82Ej0mKDtkic1EWbJ2846ohdUhTo": "Orders -> invnt_po_received",
        "10Hlj3I24l819xseCgRBN_tQdFiHqVvwB": "ORDERS(dup) -> invnt_po_received",
    }
    for drive_id, dest in STANDALONE_FOLDERS:
        tasks.append((drive_id, dest, None, standalone_labels.get(drive_id, dest)))

    # Filter by --only
    if only:
        def keeps(task):
            drive_id, dest, router, label = task
            if dest and dest in only:
                return True
            # For the routed invnt/ folder, include if any router target matches
            if router is not None and only & {"invnt_item", "invnt_po", "invnt_po_received"}:
                return True
            return False
        tasks = [t for t in tasks if keeps(t)]
        print(f"\nFilter --only: {only} -> {len(tasks)} folders to process")

    print("\n" + "=" * 60)
    print("IMAGE UPLOAD")
    print("=" * 60)

    grand_uploaded = 0
    grand_skipped = 0
    for drive_id, dest, router, label in tasks:
        # Build fresh main-thread clients for each folder. The drive client's
        # httplib2 socket can be closed by Google after long idle periods
        # while workers are uploading (a folder with thousands of images can
        # hold the main thread off a drive call for many minutes). Rebuilding
        # is cheap (~200ms) and avoids BrokenPipe/SSL errors mid-run.
        drive = get_drive_service()
        sb = get_sb()
        uploaded, skipped = process_folder(drive, sb, drive_id, dest, router=router, label=label)
        grand_uploaded += uploaded
        grand_skipped += skipped

    print("\n" + "=" * 60)
    print(f"DONE — {grand_uploaded} uploaded, {grand_skipped} skipped")
    print("=" * 60)

    conn.close()


if __name__ == "__main__":
    main()
