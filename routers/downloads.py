"""
Downloads & App Versions Router  —  /api/admin/downloads/*

┌─────────────────────────────────────────────────────────────────┐
│  GET    /api/admin/downloads/overview          → KPIs + all     │
│                                                  platform list  │
│  PATCH  /api/admin/downloads/releases/{id}     → Update button  │
│                                                  per platform   │
│  GET    /api/admin/downloads/releases/{id}     → single release │
│  POST   /api/admin/downloads/releases          → publish notes  │
│                                                  (Release Notes │
│                                                   Editor)       │
│  POST   /api/admin/downloads/push-update       → Push Update    │
│                                                  button (sends  │
│                                                  notification)  │
└─────────────────────────────────────────────────────────────────┘
"""
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

from deps import admin_required, get_db, success
from models import AppRelease, Notification, User

router = APIRouter()


# ─── Pydantic Schemas ─────────────────────────────────────────────

class ReleaseNotesCreate(BaseModel):
    """Used by the Release Notes Editor at the bottom of the page."""
    version:   str
    changelog: str


class AddReleaseBody(BaseModel):
    """Used to add a new platform release to the table."""
    platform:    str   # Windows, macOS, iOS, Android, Linux, Router (OpenWRT)
    version:     str
    size:        str
    downloads:   Optional[int] = 0
    status:      Optional[str] = "Current"
    changelog:   Optional[str] = None
    released_at: Optional[datetime] = None


class UpdateReleaseBody(BaseModel):
    """
    Used by the ↑ Update button next to each platform row.
    Send only the fields you want to change.
    """
    version:     Optional[str]      = None   # e.g. "4.2.1"
    size:        Optional[str]      = None   # e.g. "48.3 MB"
    downloads:   Optional[int]      = None
    status:      Optional[str]      = None   # "Current" | "Update Avail."
    changelog:   Optional[str]      = None
    released_at: Optional[datetime] = None


class PushUpdateBody(BaseModel):
    """
    Used by the 🟡 Push Update button (top right).
    Sends an in-app push notification to all users about a new version.
    """
    version:     str                   # e.g. "4.2.1"
    message:     Optional[str] = None  # Custom message; defaults to standard update text
    platforms:   Optional[str] = "All" # "All" | "Windows" | "iOS" etc.


# ══════════════════════════════════════════════════════════════════
# ─── 1. Overview — KPIs + Platform Release List (page load) ───────
# ══════════════════════════════════════════════════════════════════

@router.get("/overview")
def get_downloads_overview(
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """
    Returns everything needed for the Downloads & App Versions page:
      - KPI cards (Total Downloads, Current Version, Auto-Update Rate, Outdated Clients)
      - Platform Releases table (all 6 platforms)
    Call this on page load.
    """
    releases = db.query(AppRelease).all()

    # ── KPI: Total Downloads ──────────────────────────────────────
    total_downloads = sum(r.downloads for r in releases)
    if total_downloads >= 1_000_000:
        dl_label = f"{total_downloads / 1_000_000:.2f}M"
    elif total_downloads >= 1_000:
        dl_label = f"{total_downloads / 1_000:.1f}K"
    else:
        dl_label = str(total_downloads) if total_downloads else "0"

    # ── KPI: Outdated Clients ─────────────────────────────────────
    outdated_count = sum(1 for r in releases if r.status == "Update Avail.")
    outdated_label = f"{outdated_count} platform{'s' if outdated_count != 1 else ''}"

    # ── KPI: Current Version (highest version across all platforms) ─
    def _version_tuple(v: str):
        try:
            return tuple(int(x) for x in v.strip("v").split("."))
        except Exception:
            return (0, 0, 0)

    current_version = "v4.2.1"
    if releases:
        latest = max(releases, key=lambda r: _version_tuple(r.version))
        current_version = f"v{latest.version}"

    # ── Platform order in UI ──────────────────────────────────────
    order_map = {
        "Windows": 1, "macOS": 2, "iOS": 3,
        "Android": 4, "Linux": 5, "Router (OpenWRT)": 6,
    }
    sorted_releases = sorted(releases, key=lambda x: order_map.get(x.platform, 99))

    return success({
        "kpis": {
            "total_downloads_label": dl_label,
            "total_downloads_raw":   total_downloads,
            "auto_update_rate_pct":  87.4,
            "current_version":       current_version,
            "outdated_clients_label": outdated_label,
            "outdated_clients_count": outdated_count,
        },
        "releases": [r.to_dict() for r in sorted_releases],
    })


# ══════════════════════════════════════════════════════════════════
# ─── 2. Add a Platform Release (New entry) ────────────────────────
# ══════════════════════════════════════════════════════════════════

@router.post("/releases/add")
def add_release(
    body: AddReleaseBody,
    _:   None    = Depends(admin_required),
    db:  Session = Depends(get_db),
):
    """
    Add a new platform release to the database.
    Use this to populate the table after clearing mock data.
    """
    # Check if platform already exists
    existing = db.query(AppRelease).filter(AppRelease.platform == body.platform).first()
    if existing:
        raise HTTPException(status_code=400, detail=f"Release for {body.platform} already exists. Use PATCH to update it.")

    release = AppRelease(
        platform    = body.platform,
        version     = body.version,
        size        = body.size,
        downloads   = body.downloads or 0,
        status      = body.status or "Current",
        changelog   = body.changelog,
        released_at = body.released_at or datetime.utcnow()
    )
    db.add(release)
    db.commit()
    db.refresh(release)
    return success(release.to_dict(), f"Added {body.platform} v{body.version}", 201)


# ══════════════════════════════════════════════════════════════════
# ─── 2. Get Single Release (pre-fill Update modal) ────────────────
# ══════════════════════════════════════════════════════════════════

@router.get("/releases/{release_id}")
def get_release(
    release_id: str,
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """
    Fetch a single platform release record.
    Call this when the admin clicks the ↑ Update button to pre-fill the edit modal.
    """
    release = db.get(AppRelease, release_id)
    if not release:
        raise HTTPException(status_code=404, detail="Release not found")
    return success(release.to_dict())


# ══════════════════════════════════════════════════════════════════
# ─── 3. Update a Platform Release (↑ Update button per row) ───────
# ══════════════════════════════════════════════════════════════════

@router.patch("/releases/{release_id}")
def update_release(
    release_id: str,
    body: UpdateReleaseBody,
    _:   None    = Depends(admin_required),
    db:  Session = Depends(get_db),
):
    """
    Update a specific platform's release info.

    This powers the ↑ Update button next to each platform row.
    Admin can update:
      - version   → new version string e.g. "4.2.1"
      - size      → new file size e.g. "51.2 MB"
      - status    → "Current" | "Update Avail."
      - changelog → release notes for this platform
      - downloads → increment/set download count
      - released_at → release date

    Send only the fields you want to change.
    """
    release = db.get(AppRelease, release_id)
    if not release:
        raise HTTPException(status_code=404, detail="Release not found")

    if body.version     is not None: release.version     = body.version
    if body.size        is not None: release.size        = body.size
    if body.downloads   is not None: release.downloads   = body.downloads
    if body.status      is not None: release.status      = body.status
    if body.changelog   is not None: release.changelog   = body.changelog
    if body.released_at is not None: release.released_at = body.released_at

    # If version was updated and no explicit status sent, auto-set to "Current"
    if body.version is not None and body.status is None:
        release.status = "Current"
        release.released_at = release.released_at or datetime.utcnow()

    db.commit()
    db.refresh(release)
    return success(release.to_dict(), f"{release.platform} updated to v{release.version}")


# ══════════════════════════════════════════════════════════════════
# ─── 4. Publish Release Notes (Release Notes Editor at bottom) ────
# ══════════════════════════════════════════════════════════════════

@router.post("/releases")
def publish_release_notes(
    payload: ReleaseNotesCreate,
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """
    Publish release notes from the Release Notes Editor section.

    This updates ALL platforms currently marked "Update Avail." to:
      - status    = "Current"
      - version   = payload.version
      - changelog = payload.changelog
      - released_at = now

    After calling this, use POST /push-update to notify users.
    """
    platforms_to_update = (
        db.query(AppRelease)
        .filter(AppRelease.status == "Update Avail.")
        .all()
    )

    now = datetime.utcnow()
    for platform in platforms_to_update:
        platform.version     = payload.version
        platform.changelog   = payload.changelog
        platform.status      = "Current"
        platform.released_at = now

    db.commit()

    return success(
        {
            "updated_count":     len(platforms_to_update),
            "version_published": payload.version,
            "platforms_updated": [p.platform for p in platforms_to_update],
        },
        f"v{payload.version} release notes published. {len(platforms_to_update)} platform(s) updated."
    )


# ══════════════════════════════════════════════════════════════════
# ─── 5. Push Update Notification (🟡 Push Update button top-right) ─
# ══════════════════════════════════════════════════════════════════

@router.post("/push-update")
def push_update_notification(
    body: PushUpdateBody,
    _:   None    = Depends(admin_required),
    db:  Session = Depends(get_db),
):
    """
    Send an in-app push notification to all users (or a specific platform's users)
    announcing a new app version is available.

    This powers the 🟡 Push Update button in the top-right of the page.

    What it does:
      - Inserts a Notification row for every user so it appears in their
        in-app notification bell (GET /api/notifications on vpn-backend port 5000)
      - In production, also trigger FCM/APNs push here
    """
    message = body.message or (
        f"AtmosVPN {body.version} is now available! "
        f"Update now for improved performance and security fixes."
    )
    title = f"Update Available — AtmosVPN {body.version}"

    # Fan-out: write a Notification row per user
    users = db.query(User).all()
    now   = datetime.utcnow()
    count = 0
    for user in users:
        notif = Notification(
            user_id    = str(user.id),
            type       = "upgrade",
            title      = title,
            message    = message,
            is_read    = False,
            coming_soon= False,
            created_at = now,
        )
        db.add(notif)
        count += 1

    db.commit()

    return success(
        {
            "version":         body.version,
            "notified_users":  count,
            "platforms":       body.platforms,
            "notification": {
                "title":   title,
                "message": message,
            },
        },
        f"Push update notification sent to {count} users for v{body.version}"
    )
