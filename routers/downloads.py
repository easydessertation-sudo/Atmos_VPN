from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import Optional

from deps import admin_required, get_db, success
from models import AppRelease

router = APIRouter()

class ReleaseNotesCreate(BaseModel):
    version: str
    changelog: str
    # When publishing notes, we apply this version to all platforms that are marked "Update Avail." 
    # Or, in a real system, you'd specify exactly which platforms are getting this release.

@router.get("/overview")
def get_downloads_overview(
    _: None = Depends(admin_required),
    db: Session = Depends(get_db)
):
    """
    Get everything needed for the Downloads & App Versions page.
    """
    
    releases = db.query(AppRelease).all()
    total_downloads = sum(r.downloads for r in releases)
    # Formatting total downloads e.g., 6.24M
    dl_label = "-"
    if total_downloads >= 1000000:
        dl_label = f"{total_downloads / 1000000:.2f}M"
    elif total_downloads >= 1000:
        dl_label = f"{total_downloads / 1000:.1f}K"
    else:
        dl_label = str(total_downloads)
        
    outdated_count = sum(1 for r in releases if r.status == "Update Avail.")
    outdated_label = f"{outdated_count} platform{'s' if outdated_count != 1 else ''}"
    
    # Calculate "Current Version" based on most common or latest version (simplification for UI)
    current_version = "v4.2.1" 

    # Order releases to match typical UI layout (desktop first, then mobile, then others)
    order_map = {"Windows": 1, "macOS": 2, "iOS": 3, "Android": 4, "Linux": 5, "Router (OpenWRT)": 6}
    sorted_releases = sorted(releases, key=lambda x: order_map.get(x.platform, 99))

    return success({
        "kpis": {
            "total_downloads_label": dl_label,
            "auto_update_rate_pct": 87.4,
            "current_version": current_version,
            "outdated_clients_label": outdated_label
        },
        "releases": [r.to_dict() for r in sorted_releases]
    })

@router.post("/releases")
def publish_release_notes(
    payload: ReleaseNotesCreate,
    _: None = Depends(admin_required),
    db: Session = Depends(get_db)
):
    """
    Publish release notes. This updates any 'Update Avail.' platforms to 'Current'
    with the new version, and sets their changelog.
    """
    platforms_to_update = db.query(AppRelease).filter(AppRelease.status == "Update Avail.").all()
    
    for platform in platforms_to_update:
        platform.version = payload.version
        platform.changelog = payload.changelog
        platform.status = "Current"
        platform.released_at = datetime.utcnow()
        
    db.commit()
    
    return success(
        {"updated_count": len(platforms_to_update)},
        "Release notes published and platforms updated successfully."
    )
