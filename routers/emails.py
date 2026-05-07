"""
Email Campaigns Router  —  /api/admin/emails/*

┌─────────────────────────────────────────────────────────────────┐
│  CAMPAIGNS TAB                                                  │
│  GET    /api/admin/emails/overview        → KPIs + campaign list│
│  GET    /api/admin/emails/campaigns       → paginated list      │
│  POST   /api/admin/emails/campaigns       → create campaign     │
│  GET    /api/admin/emails/campaigns/{id}  → single detail       │
│  PATCH  /api/admin/emails/campaigns/{id}  → edit campaign       │
│  DELETE /api/admin/emails/campaigns/{id}  → delete campaign     │
│  GET    /api/admin/emails/campaigns/{id}/stats → stats detail   │
│  POST   /api/admin/emails/campaigns/{id}/send  → trigger send   │
│                                                                 │
│  AUTOMATED FLOWS TAB                                            │
│  GET    /api/admin/emails/flows           → list flows          │
│  POST   /api/admin/emails/flows           → create flow         │
│  PATCH  /api/admin/emails/flows/{id}      → edit flow           │
│  DELETE /api/admin/emails/flows/{id}      → delete flow         │
│  PATCH  /api/admin/emails/flows/{id}/toggle → enable/disable    │
│                                                                 │
│  TEMPLATES TAB                                                  │
│  GET    /api/admin/emails/templates       → list templates      │
│  POST   /api/admin/emails/templates       → create template     │
│  PATCH  /api/admin/emails/templates/{id}  → edit template       │
│  DELETE /api/admin/emails/templates/{id}  → delete template     │
│                                                                 │
│  SETTINGS TAB                                                   │
│  GET    /api/admin/emails/settings        → get email settings  │
│  PATCH  /api/admin/emails/settings        → update settings     │
└─────────────────────────────────────────────────────────────────┘
"""
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, EmailStr
from sqlalchemy import func
from sqlalchemy.orm import Session

from deps import admin_required, get_db, success
from models import EmailCampaign, Base, engine

router = APIRouter()


# ══════════════════════════════════════════════════════════════════
# ─── In-memory stores for Flows, Templates, Settings ─────────────
# (These use the DB via extra tables seeded below)
# ══════════════════════════════════════════════════════════════════

# ─── Pydantic Schemas ─────────────────────────────────────────────

class CreateCampaignBody(BaseModel):
    name:           str
    status:         Optional[str]  = "Draft"   # Draft | Sent | Automated
    target_segment: Optional[str]  = "All Users"
    sent_count:     Optional[int]  = 0
    open_rate_pct:  Optional[float] = 0.0
    click_rate_pct: Optional[float] = 0.0
    unsubscribe_rate_pct: Optional[float] = 0.0
    date:           Optional[str]  = None      # ISO date string "2026-05-01"
    subject:        Optional[str]  = None
    body_html:      Optional[str]  = None
    tag:            Optional[str]  = None      # PRODUCT | NEWSLETTER | PROMO


class UpdateCampaignBody(BaseModel):
    name:           Optional[str]   = None
    status:         Optional[str]   = None
    target_segment: Optional[str]   = None
    sent_count:     Optional[int]   = None
    open_rate_pct:  Optional[float] = None
    click_rate_pct: Optional[float] = None
    unsubscribe_rate_pct: Optional[float] = None
    date:           Optional[str]   = None
    subject:        Optional[str]   = None
    body_html:      Optional[str]   = None
    tag:            Optional[str]   = None


# ══════════════════════════════════════════════════════════════════
# ─── CAMPAIGNS TAB ────────────────────────────────────────────────
# ══════════════════════════════════════════════════════════════════

# ─── 1. Overview — KPIs + full list (page load) ───────────────────
@router.get("/overview")
def get_emails_overview(
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """
    Returns KPI cards + full campaign list.
    Called on page load (Campaigns tab default view).
    KPIs: Total Sent, Avg Open Rate, Avg Click Rate, Unsubscribe Rate.
    """
    campaigns = db.query(EmailCampaign).order_by(EmailCampaign.created_at.desc()).all()

    total_sent = sum(c.sent_count for c in campaigns)
    if total_sent >= 1_000_000:
        sent_label = f"{total_sent / 1_000_000:.2f}M"
    elif total_sent >= 1_000:
        sent_label = f"{total_sent / 1_000:.1f}K"
    else:
        sent_label = str(total_sent) if total_sent else "0"

    active = [c for c in campaigns if c.status != "Draft"]
    if active:
        avg_open  = sum(c.open_rate_pct  for c in active) / len(active)
        avg_click = sum(c.click_rate_pct for c in active) / len(active)
        avg_unsub = sum(c.unsubscribe_rate_pct for c in active) / len(active)
    else:
        avg_open = avg_click = avg_unsub = 0.0

    return success({
        "kpis": {
            "total_campaigns":       len(campaigns),
            "sent_30d_label":        sent_label,
            "total_sent":            total_sent,
            "avg_open_rate_pct":     round(avg_open, 1),
            "avg_click_rate_pct":    round(avg_click, 1),
            "unsubscribe_rate_pct":  round(avg_unsub, 2),
        },
        "campaigns": [c.to_dict() for c in campaigns],
    })


# ─── 2. List Campaigns (paginated + filtered) ─────────────────────
@router.get("/campaigns")
def list_campaigns(
    status:  Optional[str] = Query(None, description="Draft | Sent | Automated"),
    search:  Optional[str] = Query(None),
    segment: Optional[str] = Query(None),
    page:    int = Query(1, ge=1),
    limit:   int = Query(20, ge=1, le=100),
    _:       None    = Depends(admin_required),
    db:      Session = Depends(get_db),
):
    """
    Paginated, filterable campaign list.
    Used when switching between status tabs (All / Sent / Draft / Automated).
    """
    q = db.query(EmailCampaign)
    if status:
        q = q.filter(EmailCampaign.status == status)
    if segment:
        q = q.filter(EmailCampaign.target_segment.ilike(f"%{segment}%"))
    if search:
        q = q.filter(EmailCampaign.name.ilike(f"%{search}%"))

    total = q.count()
    items = q.order_by(EmailCampaign.created_at.desc()).offset((page - 1) * limit).limit(limit).all()

    return success({
        "campaigns": [c.to_dict() for c in items],
        "total":     total,
        "page":      page,
        "limit":     limit,
        "pages":     (total + limit - 1) // limit,
        "counts": {
            "all":       db.query(EmailCampaign).count(),
            "sent":      db.query(EmailCampaign).filter_by(status="Sent").count(),
            "draft":     db.query(EmailCampaign).filter_by(status="Draft").count(),
            "automated": db.query(EmailCampaign).filter_by(status="Automated").count(),
        },
    })


# ─── 3. Create Campaign (+ New Campaign button) ───────────────────
@router.post("/campaigns")
def create_campaign(
    body: CreateCampaignBody,
    _:   None    = Depends(admin_required),
    db:  Session = Depends(get_db),
):
    """
    Create a new email campaign.
    Triggered by '+ New Campaign' button.
    status defaults to 'Draft' — use POST /campaigns/{id}/send to mark as Sent.
    """
    send_date = None
    if body.date:
        try:
            send_date = datetime.fromisoformat(body.date)
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid date format. Use ISO: 2026-05-01")

    campaign = EmailCampaign(
        name                 = body.name,
        status               = body.status or "Draft",
        target_segment       = body.target_segment or "All Users",
        sent_count           = body.sent_count or 0,
        open_rate_pct        = body.open_rate_pct or 0.0,
        click_rate_pct       = body.click_rate_pct or 0.0,
        unsubscribe_rate_pct = body.unsubscribe_rate_pct or 0.0,
        date                 = send_date,
    )
    db.add(campaign)
    db.commit()
    db.refresh(campaign)
    return success(campaign.to_dict(), "Campaign created successfully", 201)


# ─── 4. Get Single Campaign ───────────────────────────────────────
@router.get("/campaigns/{campaign_id}")
def get_campaign(
    campaign_id: str,
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """Fetch full detail of a single campaign. Used to pre-fill Edit modal."""
    c = db.get(EmailCampaign, campaign_id)
    if not c:
        raise HTTPException(status_code=404, detail="Campaign not found")
    return success(c.to_dict())


# ─── 5. Edit Campaign (✏️ Edit button) ───────────────────────────
@router.patch("/campaigns/{campaign_id}")
def update_campaign(
    campaign_id: str,
    body: UpdateCampaignBody,
    _:   None    = Depends(admin_required),
    db:  Session = Depends(get_db),
):
    """
    Update a campaign. Send only the fields to change.
    Triggered by the '✏️ Edit' button in the Actions column.
    """
    c = db.get(EmailCampaign, campaign_id)
    if not c:
        raise HTTPException(status_code=404, detail="Campaign not found")

    if body.name           is not None: c.name                 = body.name
    if body.status         is not None: c.status               = body.status
    if body.target_segment is not None: c.target_segment       = body.target_segment
    if body.sent_count     is not None: c.sent_count           = body.sent_count
    if body.open_rate_pct  is not None: c.open_rate_pct        = body.open_rate_pct
    if body.click_rate_pct is not None: c.click_rate_pct       = body.click_rate_pct
    if body.unsubscribe_rate_pct is not None:
        c.unsubscribe_rate_pct = body.unsubscribe_rate_pct
    if body.date is not None:
        try:
            c.date = datetime.fromisoformat(body.date)
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid date format. Use ISO: 2026-05-01")

    db.commit()
    db.refresh(c)
    return success(c.to_dict(), "Campaign updated successfully")


# ─── 6. Delete Campaign ───────────────────────────────────────────
@router.delete("/campaigns/{campaign_id}")
def delete_campaign(
    campaign_id: str,
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """Delete a campaign permanently."""
    c = db.get(EmailCampaign, campaign_id)
    if not c:
        raise HTTPException(status_code=404, detail="Campaign not found")
    name = c.name
    db.delete(c)
    db.commit()
    return success({"id": campaign_id}, f"Campaign '{name}' deleted")


# ─── 7. Campaign Stats (📊 Stats button) ─────────────────────────
@router.get("/campaigns/{campaign_id}/stats")
def campaign_stats(
    campaign_id: str,
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """
    Detailed stats for a single campaign.
    Triggered by the '📊 Stats' button in the Actions column.
    Returns open rate, click rate, unsubscribe rate with breakdowns.
    """
    c = db.get(EmailCampaign, campaign_id)
    if not c:
        raise HTTPException(status_code=404, detail="Campaign not found")

    # Derived stats
    opened  = int(c.sent_count * c.open_rate_pct / 100) if c.sent_count else 0
    clicked = int(c.sent_count * c.click_rate_pct / 100) if c.sent_count else 0
    unsubs  = int(c.sent_count * c.unsubscribe_rate_pct / 100) if c.sent_count else 0
    bounced = max(0, int(c.sent_count * 0.012))   # ~1.2% bounce estimate

    return success({
        "id":             str(c.id),
        "name":           c.name,
        "status":         c.status,
        "target_segment": c.target_segment,
        "send_date":      c.date.strftime("%Y-%m-%d") if c.date else None,
        "metrics": {
            "sent":              c.sent_count,
            "delivered":         c.sent_count - bounced,
            "opened":            opened,
            "clicked":           clicked,
            "unsubscribed":      unsubs,
            "bounced":           bounced,
            "open_rate_pct":     c.open_rate_pct,
            "click_rate_pct":    c.click_rate_pct,
            "unsubscribe_rate_pct": c.unsubscribe_rate_pct,
            "bounce_rate_pct":   round(bounced / c.sent_count * 100, 2) if c.sent_count else 0,
            "click_to_open_pct": round(c.click_rate_pct / c.open_rate_pct * 100, 1) if c.open_rate_pct else 0,
        },
    })


# ─── 8. Send / Schedule Campaign ─────────────────────────────────
@router.post("/campaigns/{campaign_id}/send")
def send_campaign(
    campaign_id: str,
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """
    Mark campaign as Sent and record the send timestamp.
    In production: trigger your email sending service (SendGrid / SES / Mailgun).
    """
    c = db.get(EmailCampaign, campaign_id)
    if not c:
        raise HTTPException(status_code=404, detail="Campaign not found")
    if c.status == "Sent":
        raise HTTPException(status_code=409, detail="Campaign already sent")

    c.status = "Sent"
    c.date   = datetime.utcnow()
    db.commit()
    db.refresh(c)
    return success(c.to_dict(), f"Campaign '{c.name}' marked as sent")


# ══════════════════════════════════════════════════════════════════
# ─── AUTOMATED FLOWS TAB ──────────────────────────────────────────
# Stored in-memory (no separate DB table needed for MVP)
# Use a simple JSON-backed approach via a key-value settings table
# ══════════════════════════════════════════════════════════════════

# In-memory flow store (persists per server process; for production add a DB table)
_FLOWS_STORE = [
    {
        "id": "flow-welcome",
        "name": "Welcome Series",
        "trigger": "User Signup",
        "steps": 3,
        "enrolled": 0,
        "completed": 0,
        "avg_open_rate_pct": 0.0,
        "status": "active",
        "created_at": "2026-01-01T00:00:00",
    },
    {
        "id": "flow-churn",
        "name": "Churn Prevention",
        "trigger": "Subscription Cancelled",
        "steps": 4,
        "enrolled": 0,
        "completed": 0,
        "avg_open_rate_pct": 0.0,
        "status": "active",
        "created_at": "2026-01-01T00:00:00",
    },
    {
        "id": "flow-upgrade",
        "name": "Free → Pro Upgrade Nudge",
        "trigger": "7 Days After Signup",
        "steps": 2,
        "enrolled": 0,
        "completed": 0,
        "avg_open_rate_pct": 0.0,
        "status": "active",
        "created_at": "2026-01-01T00:00:00",
    },
]


@router.get("/flows")
def list_flows(_: None = Depends(admin_required)):
    """Automated Flows tab — list all drip/automation flows."""
    return success(_FLOWS_STORE)


@router.post("/flows")
def create_flow(body: dict, _: None = Depends(admin_required)):
    """
    Create a new automated flow.
    Body: { "name": "...", "trigger": "...", "steps": 3 }
    """
    import uuid
    flow = {
        "id":               f"flow-{uuid.uuid4().hex[:8]}",
        "name":             body.get("name", "New Flow"),
        "trigger":          body.get("trigger", "Manual"),
        "steps":            body.get("steps", 1),
        "enrolled":         0,
        "completed":        0,
        "avg_open_rate_pct": 0.0,
        "status":           "active",
        "created_at":       datetime.utcnow().isoformat(),
    }
    _FLOWS_STORE.append(flow)
    return success(flow, "Flow created", 201)


@router.patch("/flows/{flow_id}")
def update_flow(flow_id: str, body: dict, _: None = Depends(admin_required)):
    """Edit a flow's name, trigger, steps, or status."""
    flow = next((f for f in _FLOWS_STORE if f["id"] == flow_id), None)
    if not flow:
        raise HTTPException(status_code=404, detail="Flow not found")
    for field in ["name", "trigger", "steps", "status"]:
        if field in body:
            flow[field] = body[field]
    return success(flow, "Flow updated")


@router.patch("/flows/{flow_id}/toggle")
def toggle_flow(flow_id: str, _: None = Depends(admin_required)):
    """Enable / disable a flow toggle."""
    flow = next((f for f in _FLOWS_STORE if f["id"] == flow_id), None)
    if not flow:
        raise HTTPException(status_code=404, detail="Flow not found")
    flow["status"] = "paused" if flow["status"] == "active" else "active"
    return success(flow, f"Flow {'paused' if flow['status'] == 'paused' else 'activated'}")


@router.delete("/flows/{flow_id}")
def delete_flow(flow_id: str, _: None = Depends(admin_required)):
    """Delete an automated flow."""
    global _FLOWS_STORE
    before = len(_FLOWS_STORE)
    _FLOWS_STORE = [f for f in _FLOWS_STORE if f["id"] != flow_id]
    if len(_FLOWS_STORE) == before:
        raise HTTPException(status_code=404, detail="Flow not found")
    return success({"id": flow_id}, "Flow deleted")


# ══════════════════════════════════════════════════════════════════
# ─── TEMPLATES TAB ────────────────────────────────────────────────
# ══════════════════════════════════════════════════════════════════

_TEMPLATES_STORE = [
    {
        "id": "tpl-welcome",
        "name": "Welcome Email",
        "category": "Onboarding",
        "subject": "Welcome to AtmosVPN 🎉",
        "preview_text": "Your account is ready. Here's how to get started.",
        "html": "<h1>Welcome!</h1><p>Your AtmosVPN account is ready.</p>",
        "last_used": None,
        "created_at": "2026-01-01T00:00:00",
    },
    {
        "id": "tpl-upgrade",
        "name": "Upgrade Nudge",
        "category": "Conversion",
        "subject": "Unlock unlimited VPN — upgrade to Pro",
        "preview_text": "You're on the free plan. Here's what you're missing.",
        "html": "<h2>Go Pro</h2><p>Unlimited data, 200Mbps speed.</p>",
        "last_used": None,
        "created_at": "2026-01-01T00:00:00",
    },
    {
        "id": "tpl-renewal",
        "name": "Renewal Reminder",
        "category": "Billing",
        "subject": "Your AtmosVPN subscription renews soon",
        "preview_text": "Your plan renews in 3 days. No action needed.",
        "html": "<p>Your subscription renews on {{renewal_date}}.</p>",
        "last_used": None,
        "created_at": "2026-01-01T00:00:00",
    },
]


@router.get("/templates")
def list_templates(_: None = Depends(admin_required)):
    """Templates tab — list all email templates."""
    return success(_TEMPLATES_STORE)


@router.post("/templates")
def create_template(body: dict, _: None = Depends(admin_required)):
    """
    Create a new email template.
    Body: { "name": "...", "category": "...", "subject": "...", "html": "..." }
    """
    import uuid
    tpl = {
        "id":           f"tpl-{uuid.uuid4().hex[:8]}",
        "name":         body.get("name", "New Template"),
        "category":     body.get("category", "General"),
        "subject":      body.get("subject", ""),
        "preview_text": body.get("preview_text", ""),
        "html":         body.get("html", ""),
        "last_used":    None,
        "created_at":   datetime.utcnow().isoformat(),
    }
    _TEMPLATES_STORE.append(tpl)
    return success(tpl, "Template created", 201)


@router.patch("/templates/{template_id}")
def update_template(template_id: str, body: dict, _: None = Depends(admin_required)):
    """Edit a template's name, subject, html, or category."""
    tpl = next((t for t in _TEMPLATES_STORE if t["id"] == template_id), None)
    if not tpl:
        raise HTTPException(status_code=404, detail="Template not found")
    for field in ["name", "category", "subject", "preview_text", "html"]:
        if field in body:
            tpl[field] = body[field]
    return success(tpl, "Template updated")


@router.delete("/templates/{template_id}")
def delete_template(template_id: str, _: None = Depends(admin_required)):
    """Delete an email template."""
    global _TEMPLATES_STORE
    before = len(_TEMPLATES_STORE)
    _TEMPLATES_STORE = [t for t in _TEMPLATES_STORE if t["id"] != template_id]
    if len(_TEMPLATES_STORE) == before:
        raise HTTPException(status_code=404, detail="Template not found")
    return success({"id": template_id}, "Template deleted")


# ══════════════════════════════════════════════════════════════════
# ─── SETTINGS TAB ─────────────────────────────────────────────────
# ══════════════════════════════════════════════════════════════════

_EMAIL_SETTINGS = {
    "sender_name":      "AtmosVPN",
    "sender_email":     "noreply@atmosvpn.com",
    "reply_to":         "support@atmosvpn.com",
    "provider":         "sendgrid",          # sendgrid | ses | mailgun | smtp
    "daily_send_limit": 50000,
    "unsubscribe_link": True,
    "track_opens":      True,
    "track_clicks":     True,
    "footer_text":      "AtmosVPN · Privacy-first VPN · Unsubscribe",
    "smtp_host":        None,
    "smtp_port":        587,
    "smtp_user":        None,
}


@router.get("/settings")
def get_email_settings(_: None = Depends(admin_required)):
    """Settings tab — email provider config, sender details, tracking toggles."""
    return success(_EMAIL_SETTINGS)


@router.patch("/settings")
def update_email_settings(body: dict, _: None = Depends(admin_required)):
    """
    Update email settings. Send only the fields to change.
    Allowed fields: sender_name, sender_email, reply_to, provider,
    daily_send_limit, unsubscribe_link, track_opens, track_clicks,
    footer_text, smtp_host, smtp_port, smtp_user.
    """
    allowed = [
        "sender_name", "sender_email", "reply_to", "provider",
        "daily_send_limit", "unsubscribe_link", "track_opens",
        "track_clicks", "footer_text", "smtp_host", "smtp_port", "smtp_user",
    ]
    updated = []
    for field in allowed:
        if field in body:
            _EMAIL_SETTINGS[field] = body[field]
            updated.append(field)

    return success(_EMAIL_SETTINGS, f"Settings updated: {', '.join(updated)}")


# ─── Send Product Update / Newsletter (quick-send endpoint) ───────
@router.post("/send-product-update")
def send_product_update(body: dict, _: None = Depends(admin_required), db: Session = Depends(get_db)):
    """
    Quick broadcast to opted-in users.
    Body: { "subject": "...", "body": "<html>...", "tag": "PRODUCT" }
    Creates a campaign record and marks it as Sent.
    """
    import uuid
    subject = body.get("subject", "Product Update")
    tag     = body.get("tag", "PRODUCT")

    # Create a campaign record for history tracking
    campaign = EmailCampaign(
        name           = subject[:100],
        status         = "Sent",
        target_segment = "All Users",
        sent_count     = 0,   # update with real count after send
        date           = datetime.utcnow(),
    )
    db.add(campaign)
    db.commit()
    db.refresh(campaign)

    campaign_id = str(campaign.id)
    # In production: call SendGrid/SES/Mailgun here with body["body"] as HTML

    return success({
        "message":     f"Product update queued.",
        "campaign_id": campaign_id,
        "sent_count":  0,
        "status":      "sent",
        "tag":         tag,
    })
