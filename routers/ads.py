from typing import Optional
from datetime import datetime, timedelta
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import func

from deps import admin_required, success
from models import get_db, Ad, AdView
from pydantic import BaseModel

router = APIRouter()

class AdminCreateAdRequest(BaseModel):
    title:            str
    description:      Optional[str]  = None
    image_url:        Optional[str]  = None
    video_url:        Optional[str]  = None
    click_url:        Optional[str]  = None
    ad_type:          str            = "rewarded"
    duration_seconds: int            = 30
    reward_minutes:   int            = 30
    target_plans:     str            = "free"
    priority:         int            = 0
    is_active:        bool           = True

class AdminUpdateAdRequest(BaseModel):
    title:            Optional[str]  = None
    description:      Optional[str]  = None
    image_url:        Optional[str]  = None
    video_url:        Optional[str]  = None
    click_url:        Optional[str]  = None
    ad_type:          Optional[str]  = None
    duration_seconds: Optional[int]  = None
    reward_minutes:   Optional[int]  = None
    target_plans:     Optional[str]  = None
    priority:         Optional[int]  = None
    is_active:        Optional[bool] = None

@router.get("/ads")
def admin_list_ads(
    active_only: bool = False,
    _:           None    = Depends(admin_required),
    db:          Session = Depends(get_db),
):
    """List all ad creatives. Optionally filter to active only."""
    q = db.query(Ad)
    if active_only:
        q = q.filter_by(is_active=True)
    ads = q.order_by(Ad.priority.desc(), Ad.created_at.desc()).all()
    return success({"ads": [a.to_dict() for a in ads], "total": len(ads)})

@router.post("/ads")
def admin_create_ad(
    body: AdminCreateAdRequest,
    _:    None    = Depends(admin_required),
    db:   Session = Depends(get_db),
):
    """Create a new ad creative."""
    ad = Ad(
        title            = body.title,
        description      = body.description,
        image_url        = body.image_url,
        video_url        = body.video_url,
        click_url        = body.click_url,
        ad_type          = body.ad_type,
        duration_seconds = body.duration_seconds,
        reward_minutes   = body.reward_minutes,
        target_plans     = body.target_plans,
        priority         = body.priority,
        is_active        = body.is_active,
    )
    db.add(ad)
    db.commit()
    db.refresh(ad)
    return success(ad.to_dict(), "Ad created", status_code=201)

@router.patch("/ads/{ad_id}")
def admin_update_ad(
    ad_id: str,
    body:  AdminUpdateAdRequest,
    _:     None    = Depends(admin_required),
    db:    Session = Depends(get_db),
):
    """Update an existing ad creative."""
    ad = db.get(Ad, ad_id)
    if not ad:
        raise HTTPException(status_code=404, detail="Ad not found")

    update_fields = [
        "title", "description", "image_url", "video_url", "click_url",
        "ad_type", "duration_seconds", "reward_minutes",
        "target_plans", "priority", "is_active",
    ]
    for field in update_fields:
        value = getattr(body, field)
        if value is not None:
            setattr(ad, field, value)

    ad.updated_at = datetime.utcnow()
    db.commit()
    return success(ad.to_dict(), "Ad updated")

@router.delete("/ads/{ad_id}")
def admin_delete_ad(
    ad_id: str,
    _:     None    = Depends(admin_required),
    db:    Session = Depends(get_db),
):
    """Permanently delete an ad."""
    ad = db.get(Ad, ad_id)
    if not ad:
        raise HTTPException(status_code=404, detail="Ad not found")
    db.delete(ad)
    db.commit()
    return success(msg="Ad deleted")

@router.get("/ads/stats")
def admin_ads_stats(
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """Ad analytics for the admin dashboard."""
    now        = datetime.utcnow()
    today      = now.replace(hour=0, minute=0, second=0, microsecond=0)
    week_start = today - timedelta(days=7)

    total_views        = db.query(AdView).count()
    views_today        = db.query(AdView).filter(AdView.watched_at >= today).count()
    views_this_week    = db.query(AdView).filter(AdView.watched_at >= week_start).count()
    total_minutes      = db.query(func.sum(AdView.reward_minutes)).scalar() or 0
    minutes_today      = db.query(func.sum(AdView.reward_minutes)).filter(AdView.watched_at >= today).scalar() or 0
    unique_users_today = db.query(func.count(func.distinct(AdView.user_id))).filter(AdView.watched_at >= today).scalar() or 0

    per_ad = (
        db.query(Ad.id, Ad.title, func.count(AdView.id).label("views"), func.sum(AdView.reward_minutes).label("total_minutes"))
        .outerjoin(AdView, Ad.id == AdView.ad_id)
        .group_by(Ad.id, Ad.title)
        .all()
    )

    return success({
        "total_views":          total_views,
        "views_today":          views_today,
        "views_this_week":      views_this_week,
        "total_minutes_granted": total_minutes,
        "minutes_today":        minutes_today,
        "unique_users_today":   unique_users_today,
        "per_ad": [
            {
                "ad_id":         str(row.id),
                "title":         row.title,
                "total_views":   row.views,
                "total_minutes": row.total_minutes or 0,
            }
            for row in per_ad
        ],
    })
