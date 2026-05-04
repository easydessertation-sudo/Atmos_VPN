from datetime import datetime
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import Optional

from deps import admin_required, get_db, success
from models import PushCampaign, User, Notification

router = APIRouter()

class CampaignCreate(BaseModel):
    title: str
    message: str
    target_segment: str
    scheduled_for: Optional[datetime] = None
    is_draft: bool = False

@router.get("/reach-estimate")
def estimate_reach(
    segment: str = Query("All Users", description="Target segment e.g. 'All Users', 'Free Users'"),
    _: None = Depends(admin_required),
    db: Session = Depends(get_db)
):
    """Calculate estimated reach and stats for the given segment"""
    total_users = db.query(User).count()
    if total_users == 0:
        total_users = 2840000

    targeted = total_users
    if "Free" in segment:
        targeted = int(total_users * 0.7)
    elif "Premium" in segment or "Paid" in segment:
        targeted = int(total_users * 0.3)

    if targeted >= 1000000:
        devices_targeted_label = f"{targeted / 1000000:.2f}M"
    elif targeted >= 1000:
        devices_targeted_label = f"{targeted / 1000:.1f}K"
    else:
        devices_targeted_label = str(targeted)

    return success({
        "devices_targeted_raw": targeted,
        "devices_targeted_label": devices_targeted_label,
        "avg_open_rate_pct": 38,
        "avg_ctr_pct": 12,
        "delivery_time_estimate": "< 60 seconds",
        "opt_out_rate_pct": 1.2
    })

@router.post("/campaigns")
def create_campaign(
    payload: CampaignCreate,
    _: None = Depends(admin_required),
    db: Session = Depends(get_db)
):
    """Create (and potentially send/schedule) a push notification campaign.
    When sent immediately (is_draft=False, no scheduled_for), fans out a
    Notification row to every targeted user so it appears in their inbox.
    """
    total_users = db.query(User).count() or 2840000
    targeted = total_users
    if "Free" in payload.target_segment:
        targeted = int(total_users * 0.7)
    elif "Premium" in payload.target_segment:
        targeted = int(total_users * 0.3)

    status = "draft"
    sent_at = None
    if not payload.is_draft:
        if payload.scheduled_for and payload.scheduled_for > datetime.utcnow():
            status = "scheduled"
        else:
            status = "sent"
            sent_at = datetime.utcnow()

    campaign = PushCampaign(
        title=payload.title,
        message=payload.message,
        target_segment=payload.target_segment,
        scheduled_for=payload.scheduled_for,
        status=status,
        devices_targeted=targeted,
        sent_at=sent_at
    )
    db.add(campaign)
    db.flush()  # Assign ID before fan-out

    # ── Fan-out: write a Notification row per targeted user ──────────
    # This makes admin broadcast campaigns appear in each user's inbox
    # at GET /api/notifications (vpn-backend port 5000)
    if status == "sent":
        user_query = db.query(User)
        if "Free" in payload.target_segment:
            user_query = user_query.filter(User.plan == "free")
        elif "Premium" in payload.target_segment or "Paid" in payload.target_segment:
            user_query = user_query.filter(User.plan != "free")
        # else: "All Users" - no filter

        now = datetime.utcnow()
        for user in user_query.all():
            notif = Notification(
                user_id=str(user.id),
                type="broadcast",
                title=payload.title,
                message=payload.message,
                is_read=False,
                coming_soon=False,
                created_at=now,
            )
            db.add(notif)

    db.commit()
    db.refresh(campaign)
    return success(campaign.to_dict())

@router.get("/campaigns")
def list_campaigns(
    status: Optional[str] = None,
    limit: int = 20,
    _: None = Depends(admin_required),
    db: Session = Depends(get_db)
):
    """List push campaigns (for History or Scheduled tabs)"""
    query = db.query(PushCampaign)
    if status:
        query = query.filter(PushCampaign.status == status)

    campaigns = query.order_by(PushCampaign.created_at.desc()).limit(limit).all()
    return success([c.to_dict() for c in campaigns])
