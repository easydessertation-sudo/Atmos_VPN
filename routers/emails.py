from datetime import datetime
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from deps import admin_required, get_db, success
from models import EmailCampaign

router = APIRouter()

@router.get("/overview")
def get_emails_overview(
    _: None = Depends(admin_required),
    db: Session = Depends(get_db)
):
    """
    Get everything needed for the Email Campaigns page:
    - KPIs (Total Sent 30D, Avg Open Rate, Avg Click Rate, Unsubscribe Rate)
    - List of email campaigns
    """
    
    campaigns = db.query(EmailCampaign).order_by(EmailCampaign.created_at.desc()).all()
    # Calculate KPIs
    # Sum of sent
    total_sent = sum(c.sent_count for c in campaigns)
    sent_label = "-"
    if total_sent >= 1000000:
        sent_label = f"{total_sent / 1000000:.2f}M"
    elif total_sent >= 1000:
        sent_label = f"{total_sent / 1000:.1f}K"
    else:
        sent_label = str(total_sent)

    # Averages
    active_campaigns = [c for c in campaigns if c.status != "Draft"]
    
    if active_campaigns:
        avg_open = sum(c.open_rate_pct for c in active_campaigns) / len(active_campaigns)
        avg_click = sum(c.click_rate_pct for c in active_campaigns) / len(active_campaigns)
        avg_unsub = sum(c.unsubscribe_rate_pct for c in active_campaigns) / len(active_campaigns)
    else:
        avg_open = avg_click = avg_unsub = 0

    return success({
        "kpis": {
            "sent_30d_label": sent_label,
            "avg_open_rate_pct": round(avg_open, 1),
            "avg_click_rate_pct": round(avg_click, 1),
            "unsubscribe_rate_pct": round(avg_unsub, 1)
        },
        "campaigns": [c.to_dict() for c in campaigns]
    })
