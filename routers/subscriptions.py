"""
Subscriptions & Billing Router
GET    /api/admin/subscriptions/kpis         → 4 KPI cards (Active Pro, Team, Free, Pending Refunds)
GET    /api/admin/subscriptions              → Active tab — list subs (filter/paginate)
GET    /api/admin/subscriptions/refunds      → Refunds tab — past_due / refunded subs
GET    /api/admin/subscriptions/plans        → Plans tab — plan pricing + subscriber counts
GET    /api/admin/subscriptions/billing-history → Billing History tab — all transactions
GET    /api/admin/subscriptions/revenue      → Revenue breakdown (MRR by plan)
GET    /api/admin/subscriptions/{id}         → Single subscription detail
PATCH  /api/admin/subscriptions/{id}         → Manual update (status/plan/expires)
POST   /api/admin/subscriptions/{id}/cancel  → Cancel button
POST   /api/admin/subscriptions/{id}/refund  → Refund button
POST   /api/admin/subscriptions/{id}/upgrade → Upgrade button
"""
from datetime import datetime, timedelta
from typing import Optional
import csv
import io

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from sqlalchemy import func
from sqlalchemy.orm import Session

from deps import admin_required, get_db, success
from models import Subscription, User, Plan

router = APIRouter()

VALID_PLANS    = ["free", "starter", "pro", "premium"]
VALID_STATUSES = ["active", "cancelled", "expired", "past_due"]

# ─── Default plan seed data ────────────────────────────────────────────────
# This is used ONLY to seed the DB on first startup.
# After seeding, all values come from the DB and are editable via PATCH.
DEFAULT_PLANS = [
    {
        "key": "free", "label": "Free", "amount_usd": 0.0, "per": "mo",
        "description": "Get started with basic VPN protection.",
        "max_devices": 1, "bandwidth_gb": 10, "simultaneous": 1,
        "has_streaming": False, "has_p2p": False, "has_dedicated_ip": False,
        "has_ad_blocker": True, "has_kill_switch": True, "has_priority_support": False,
        "is_visible": True, "is_default": True,
    },
    {
        "key": "starter", "label": "Starter", "amount_usd": 3.99, "per": "mo",
        "description": "Perfect for individuals who want more.",
        "max_devices": 3, "bandwidth_gb": None, "simultaneous": 3,
        "has_streaming": True, "has_p2p": False, "has_dedicated_ip": False,
        "has_ad_blocker": True, "has_kill_switch": True, "has_priority_support": False,
        "is_visible": True, "is_default": False,
    },
    {
        "key": "pro", "label": "Pro", "amount_usd": 7.99, "per": "mo",
        "description": "Advanced features for power users.",
        "max_devices": 6, "bandwidth_gb": None, "simultaneous": 6,
        "has_streaming": True, "has_p2p": True, "has_dedicated_ip": True,
        "has_ad_blocker": True, "has_kill_switch": True, "has_priority_support": False,
        "is_visible": True, "is_default": False,
    },
    {
        "key": "premium", "label": "Team", "amount_usd": 7.99, "per": "seat",
        "description": "Secure your entire team. Billed per seat.",
        "max_devices": 10, "bandwidth_gb": None, "simultaneous": 10,
        "has_streaming": True, "has_p2p": True, "has_dedicated_ip": True,
        "has_ad_blocker": True, "has_kill_switch": True, "has_priority_support": True,
        "is_visible": True, "is_default": False,
    },
]


def seed_plans(db: Session):
    """Seed default plans into DB if they don't exist yet."""
    for p in DEFAULT_PLANS:
        if not db.get(Plan, p["key"]):
            db.add(Plan(**p))
    db.commit()

# ─── DB-backed plan config helper ────────────────────────────────────────
def _get_plan_cfg(plan_key: str, db: Session) -> dict:
    """
    Fetch plan display config from the DB (Plan table).
    Falls back to safe defaults if plan not found.
    Always reflects the latest admin edits.
    """
    seed_plans(db)  # ensure rows exist
    plan = db.get(Plan, plan_key)
    if plan:
        return {
            "label":        plan.label,
            "amount_label": plan.to_dict()["amount_label"],
            "amount_usd":   plan.amount_usd,
            "per":          plan.per,
            "description":  plan.description,
        }
    # fallback for unknown plan keys
    return {
        "label":        plan_key.capitalize(),
        "amount_label": f"${plan_key}",
        "amount_usd":   0.0,
        "per":          "mo",
        "description":  "",
    }


# ─── Helper ────────────────────────────────────────────────────────────────
def _enrich_sub(s: Subscription, db: Session) -> dict:
    """Add user info + UI-friendly fields to a subscription dict.
    All plan labels/prices come from DB so edits reflect instantly.
    """
    d    = s.to_dict()
    user = db.get(User, s.user_id)
    cfg  = _get_plan_cfg(s.plan, db)
    d["user_email"]    = user.email     if user else "Unknown"
    d["user_name"]     = user.full_name if user else "Unknown"
    d["user_plan"]     = user.plan      if user else "Unknown"
    d["plan_label"]    = cfg["label"]
    d["amount_label"]  = cfg["amount_label"]
    d["next_billing"]  = s.expires_at.strftime("%Y-%m-%d") if s.expires_at else None
    return d


# ─── 1. KPI Cards ─────────────────────────────────────────────────────────
@router.get("/subscriptions/kpis")
def billing_kpis(
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """
    4 KPI cards on the Subscriptions & Billing page:
      active_pro      → active subscriptions with plan = pro
      active_team     → active subscriptions with plan = premium (Team)
      free_plan       → users on free plan
      pending_refunds → subscriptions with status = past_due
    Also returns total MRR from all active paid subscriptions.
    """
    active_pro   = db.query(Subscription).filter_by(status="active", plan="pro").count()
    active_team  = db.query(Subscription).filter_by(status="active", plan="premium").count()
    active_start = db.query(Subscription).filter_by(status="active", plan="starter").count()
    free_users   = db.query(User).filter_by(plan="free").count()
    pending_refunds = db.query(Subscription).filter_by(status="past_due").count()

    mrr = float(
        db.query(func.sum(Subscription.amount_usd))
        .filter_by(status="active")
        .scalar() or 0.0
    )

    return success({
        "active_pro":       active_pro,
        "active_starter":   active_start,
        "active_team":      active_team,        # premium plan = "Team" in UI
        "free_plan":        free_users,
        "pending_refunds":  pending_refunds,
        "total_mrr_usd":    round(mrr, 2),
        "arr_usd":          round(mrr * 12, 2),
    })


# ─── 2. Active Tab — List Subscriptions ───────────────────────────────────
@router.get("/subscriptions")
def admin_list_subscriptions(
    status: Optional[str] = "active",   # default: Active tab
    plan:   Optional[str] = None,
    search: Optional[str] = None,
    page:   int = 1,
    limit:  int = 20,
    _:      None    = Depends(admin_required),
    db:     Session = Depends(get_db),
):
    """
    Main subscriptions table — default shows Active tab (status=active).
    Change status param to switch tabs:
      status=active    → Active tab
      status=cancelled → Cancelled subs
      status=past_due  → also used for refunds tab
      status=expired   → expired subs
    Includes: user name/email, plan, amount, next_billing date, status, actions.
    """
    q = db.query(Subscription)
    if status:
        q = q.filter_by(status=status)
    if plan:
        q = q.filter_by(plan=plan)
    if search:
        # Join with User to search by email/name
        q = q.join(User, Subscription.user_id == User.id).filter(
            User.email.ilike(f"%{search}%") |
            User.full_name.ilike(f"%{search}%")
        )

    total = q.count()
    subs  = q.order_by(Subscription.started_at.desc()).offset((page - 1) * limit).limit(limit).all()

    return success({
        "subscriptions": [_enrich_sub(s, db) for s in subs],
        "total":         total,
        "page":          page,
        "limit":         limit,
        "pages":         (total + limit - 1) // limit,
        "counts": {
            "active":    db.query(Subscription).filter_by(status="active").count(),
            "cancelled": db.query(Subscription).filter_by(status="cancelled").count(),
            "expired":   db.query(Subscription).filter_by(status="expired").count(),
            "past_due":  db.query(Subscription).filter_by(status="past_due").count(),
        },
    })


# ─── 3. Refunds Tab ───────────────────────────────────────────────────────
@router.get("/subscriptions/refunds")
def billing_refunds(
    page:  int = 1,
    limit: int = 20,
    _:     None    = Depends(admin_required),
    db:    Session = Depends(get_db),
):
    """
    Refunds tab — subscriptions with status=past_due.
    These are payments that failed or were disputed/charged-back.
    In production, wire up Stripe refund events to track actual refunds.
    """
    q = db.query(Subscription).filter_by(status="past_due")
    total = q.count()
    subs  = q.order_by(Subscription.started_at.desc()).offset((page - 1) * limit).limit(limit).all()

    return success({
        "refunds":       [_enrich_sub(s, db) for s in subs],
        "total":         total,
        "page":          page,
        "limit":         limit,
        "pages":         (total + limit - 1) // limit,
        "total_at_risk_usd": round(
            float(db.query(func.sum(Subscription.amount_usd)).filter_by(status="past_due").scalar() or 0.0), 2
        ),
    })


# ─── 4. Plans Tab ─────────────────────────────────────────────────────────
@router.get("/subscriptions/plans")
def billing_plans(
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """
    Plans tab — reads plan pricing directly from the Plan DB table.
    Reflects any edits made via PATCH /api/admin/plans/{key} immediately.
    """
    seed_plans(db)  # ensure rows exist on first call
    plans = db.query(Plan).order_by(Plan.amount_usd).all()
    plans_out = []
    for plan in plans:
        active_count = db.query(Subscription).filter_by(status="active", plan=plan.key).count()
        user_count   = db.query(User).filter_by(plan=plan.key).count()
        mrr = round(float(
            db.query(func.sum(Subscription.amount_usd))
            .filter_by(status="active", plan=plan.key)
            .scalar() or 0.0
        ), 2)
        plans_out.append({
            "plan":                 plan.key,
            "label":               plan.label,
            "description":         plan.description,
            "amount_label":        plan.to_dict()["amount_label"],
            "amount_usd":          plan.amount_usd,
            "per":                 plan.per,
            "active_subscriptions":active_count,
            "total_users":         user_count,
            "mrr_usd":             mrr,
            "limits":              plan.to_dict()["limits"],
            "features":            plan.to_dict()["features"],
            "is_visible":          plan.is_visible,
            "updated_at":          plan.updated_at.isoformat() if plan.updated_at else None,
        })

    return success(plans_out)


# ─── 5. Billing History Tab ───────────────────────────────────────────────
@router.get("/subscriptions/billing-history")
def billing_history(
    plan:  Optional[str] = None,
    days:  int  = 90,
    page:  int  = 1,
    limit: int  = 20,
    _:     None    = Depends(admin_required),
    db:    Session = Depends(get_db),
):
    """
    Billing History tab — all subscription records (any status) within the last N days.
    Each row = one payment/billing event.
    """
    since = datetime.utcnow() - timedelta(days=days)
    q = db.query(Subscription).filter(Subscription.started_at >= since)
    if plan:
        q = q.filter_by(plan=plan)

    total = q.count()
    subs  = q.order_by(Subscription.started_at.desc()).offset((page - 1) * limit).limit(limit).all()

    result = []
    for s in subs:
        d = _enrich_sub(s, db)
        d["transaction_date"] = s.started_at.strftime("%Y-%m-%d") if s.started_at else None
        result.append(d)

    total_collected = float(
        db.query(func.sum(Subscription.amount_usd))
        .filter(
            Subscription.started_at >= since,
            Subscription.status.in_(["active", "cancelled", "expired"]),
        )
        .scalar() or 0.0
    )

    return success({
        "history":              result,
        "total":                total,
        "page":                 page,
        "limit":                limit,
        "pages":                (total + limit - 1) // limit,
        "total_collected_usd":  round(total_collected, 2),
        "period_days":          days,
    })


@router.get("/subscriptions/billing-history/export")
def export_billing_history(
    plan:  Optional[str] = None,
    days:  int  = 90,
    _:     None    = Depends(admin_required),
    db:    Session = Depends(get_db),
):
    """
    Export Billing History as a CSV file.
    Follows the exact same query logic as the billing_history endpoint.
    """
    since = datetime.utcnow() - timedelta(days=days)
    q = db.query(Subscription).filter(Subscription.started_at >= since)
    if plan:
        q = q.filter_by(plan=plan)

    subs = q.order_by(Subscription.started_at.desc()).all()

    output = io.StringIO()
    writer = csv.writer(output)
    
    # CSV Header
    writer.writerow([
        "Transaction ID", 
        "Date", 
        "User Email", 
        "Plan", 
        "Billing Cycle", 
        "Amount (USD)", 
        "Status"
    ])

    # Pre-fetch users in bulk to avoid N+1 query problem
    user_ids = {s.user_id for s in subs if s.user_id}
    users = db.query(User).filter(User.id.in_(user_ids)).all() if user_ids else []
    user_map = {u.id: u.email for u in users}

    # CSV Rows
    for s in subs:
        email = user_map.get(s.user_id, "Unknown")
        writer.writerow([
            s.id,
            s.started_at.strftime("%Y-%m-%d %H:%M:%S") if s.started_at else "",
            email,
            s.plan,
            s.billing_cycle,
            s.amount_usd,
            s.status
        ])

    output.seek(0)
    response = StreamingResponse(iter([output.getvalue()]), media_type="text/csv")
    response.headers["Content-Disposition"] = f"attachment; filename=billing_history_{days}days.csv"
    return response


# ─── 6. Revenue Summary ───────────────────────────────────────────────────
@router.get("/subscriptions/revenue")
def admin_revenue_summary(
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """MRR + ARR + per-plan revenue breakdown.
    Reads plan keys from DB so new/edited plans are always reflected.
    """
    seed_plans(db)
    paid_plans = db.query(Plan).filter(Plan.amount_usd > 0).all()
    plans_out = {}
    total_mrr = 0.0
    for plan in paid_plans:
        amount = float(
            db.query(func.sum(Subscription.amount_usd))
            .filter_by(status="active", plan=plan.key)
            .scalar() or 0.0
        )
        count = db.query(Subscription).filter_by(status="active", plan=plan.key).count()
        plans_out[plan.key] = {
            "label":         plan.label,
            "amount_usd":    plan.amount_usd,
            "active_count":  count,
            "total_revenue": round(amount, 2),
        }
        total_mrr += amount

    return success({
        "total_mrr_usd":    round(total_mrr, 2),
        "total_arr_usd":    round(total_mrr * 12, 2),
        "plan_breakdown":   plans_out,
        "all_time_revenue": round(
            float(db.query(func.sum(Subscription.amount_usd)).scalar() or 0.0), 2
        ),
    })


# ─── 7. Single Subscription Detail ───────────────────────────────────────
@router.get("/subscriptions/{sub_id}")
def admin_subscription_detail(
    sub_id: str,
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """Full detail of a single subscription record."""
    sub = db.get(Subscription, sub_id)
    if not sub:
        raise HTTPException(status_code=404, detail="Subscription not found")
    return success(_enrich_sub(sub, db))


# ─── 8. Cancel Subscription (Cancel button) ───────────────────────────────
@router.post("/subscriptions/{sub_id}/cancel")
def admin_cancel_subscription(
    sub_id: str,
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """
    Cancel a subscription — triggered by 'Cancel' button.
    Sets status=cancelled, records cancelled_at timestamp,
    and downgrades the linked user to free plan.
    """
    sub = db.get(Subscription, sub_id)
    if not sub:
        raise HTTPException(status_code=404, detail="Subscription not found")
    if sub.status == "cancelled":
        raise HTTPException(status_code=409, detail="Subscription is already cancelled")

    sub.status       = "cancelled"
    sub.cancelled_at = datetime.utcnow()

    # Downgrade user to free
    user = db.get(User, sub.user_id)
    if user:
        user.plan                = "free"
        user.subscription_status = "cancelled"

    db.commit()
    db.refresh(sub)
    return success(
        _enrich_sub(sub, db),
        f"Subscription cancelled. User downgraded to free plan.",
    )


# ─── 9. Refund Subscription (Refund button) ───────────────────────────────
@router.post("/subscriptions/{sub_id}/refund")
def admin_refund_subscription(
    sub_id: str,
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """
    Mark a subscription as refunded (sets status=past_due).
    In production: call Stripe API to issue the actual refund,
    then update this record with the result.
    Currently marks as past_due which appears in the Refunds tab.
    """
    sub = db.get(Subscription, sub_id)
    if not sub:
        raise HTTPException(status_code=404, detail="Subscription not found")
    if sub.status in ["cancelled", "past_due"]:
        raise HTTPException(
            status_code=409,
            detail=f"Cannot refund a subscription with status: {sub.status}"
        )

    sub.status       = "past_due"    # marks for refund review
    sub.cancelled_at = datetime.utcnow()

    user = db.get(User, sub.user_id)
    if user:
        user.subscription_status = "past_due"

    db.commit()
    db.refresh(sub)
    return success(
        _enrich_sub(sub, db),
        "Subscription marked for refund. Process the actual refund via Stripe dashboard.",
    )


# ─── 10. Upgrade Subscription (Upgrade button) ────────────────────────────
@router.post("/subscriptions/{sub_id}/upgrade")
def admin_upgrade_subscription(
    sub_id: str,
    plan:   str,   # query param: ?plan=premium
    _:      None    = Depends(admin_required),
    db:     Session = Depends(get_db),
):
    """
    Upgrade a subscription's plan — triggered by 'Upgrade' button.
    Pass new plan as query param: POST /api/admin/subscriptions/{id}/upgrade?plan=premium
    Also updates the linked user's plan.
    """
    if plan not in VALID_PLANS:
        raise HTTPException(status_code=400, detail=f"Invalid plan. Must be one of: {VALID_PLANS}")

    sub = db.get(Subscription, sub_id)
    if not sub:
        raise HTTPException(status_code=404, detail="Subscription not found")

    old_plan = sub.plan
    sub.plan = plan

    # Update amount to match new plan
    sub.amount_usd = PLAN_CONFIG.get(plan, {}).get("amount_usd", sub.amount_usd)

    user = db.get(User, sub.user_id)
    if user:
        user.plan                = plan
        user.subscription_status = "active"

    sub.status = "active"
    db.commit()
    db.refresh(sub)
    return success(
        _enrich_sub(sub, db),
        f"Subscription upgraded from {old_plan} → {plan}",
    )


# ─── 11. Manual Update ────────────────────────────────────────────────────
@router.patch("/subscriptions/{sub_id}")
def admin_update_subscription(
    sub_id: str,
    body:   dict,
    _:      None    = Depends(admin_required),
    db:     Session = Depends(get_db),
):
    """
    Manual override — update any field (status, expires_at, plan, amount_usd).
    Body is a free-form dict; only recognised fields are applied.
    """
    sub = db.get(Subscription, sub_id)
    if not sub:
        raise HTTPException(status_code=404, detail="Subscription not found")

    allowed = ["status", "plan", "amount_usd", "billing_cycle", "expires_at", "cancelled_at"]
    for field in allowed:
        if field in body:
            value = body[field]
            # Parse datetime strings
            if field in ["expires_at", "cancelled_at"] and isinstance(value, str):
                value = datetime.fromisoformat(value)
            setattr(sub, field, value)

    # Sync user plan if plan changed
    if "plan" in body:
        user = db.get(User, sub.user_id)
        if user:
            user.plan = body["plan"]

    if "status" in body and body["status"] == "cancelled":
        sub.cancelled_at = sub.cancelled_at or datetime.utcnow()

    db.commit()
    db.refresh(sub)
    return success(_enrich_sub(sub, db), "Subscription updated successfully")


# ═══════════════════════════════════════════════════════════════════
# PLAN MANAGEMENT — Edit Plan Details (Plans Tab)
# ═══════════════════════════════════════════════════════════════════

class PlanUpdateBody(BaseModel):
    label:       Optional[str]   = None
    description: Optional[str]   = None
    amount_usd:  Optional[float] = None
    per:         Optional[str]   = None   # "mo" | "seat" | "year"
    currency:    Optional[str]   = None

    # Stripe price IDs
    stripe_price_id_monthly: Optional[str] = None
    stripe_price_id_yearly:  Optional[str] = None

    # Limits
    max_devices:  Optional[int]  = None
    bandwidth_gb: Optional[int]  = None   # pass null to set unlimited
    server_count: Optional[int]  = None
    simultaneous: Optional[int]  = None

    # Feature toggles
    has_streaming:        Optional[bool] = None
    has_p2p:              Optional[bool] = None
    has_dedicated_ip:     Optional[bool] = None
    has_ad_blocker:       Optional[bool] = None
    has_kill_switch:      Optional[bool] = None
    has_priority_support: Optional[bool] = None

    # Visibility
    is_visible: Optional[bool] = None


# ─── GET /plans — All plans with live subscriber counts ───────────
@router.get("/plans")
def get_all_plans(
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """
    Returns all 4 plans with their current DB config + live subscriber stats.
    Called when the Plans tab loads. Auto-seeds defaults on first call.
    """
    seed_plans(db)
    plans = db.query(Plan).order_by(Plan.amount_usd).all()
    result = []
    for p in plans:
        d = p.to_dict()
        # Enrich with live subscriber counts (same as billing_plans endpoint)
        d["active_subscriptions"] = db.query(Subscription).filter_by(status="active", plan=p.key).count()
        d["total_users"]  = db.query(User).filter_by(plan=p.key).count()
        d["mrr_usd"]      = round(float(
            db.query(func.sum(Subscription.amount_usd))
            .filter_by(status="active", plan=p.key)
            .scalar() or 0.0
        ), 2)
        result.append(d)
    return success(result)


# ─── GET /plans/{plan_key} — Single plan detail (for modal pre-fill) ──
@router.get("/plans/{plan_key}")
def get_plan_detail(
    plan_key: str,
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """
    Fetch full details of a single plan.
    Frontend: call this when admin clicks 'Edit Plan Details'
    to pre-fill the edit modal/form.
    """
    seed_plans(db)
    plan = db.get(Plan, plan_key)
    if not plan:
        raise HTTPException(status_code=404, detail=f"Plan '{plan_key}' not found")
    d = plan.to_dict()
    d["active_subscriptions"] = db.query(Subscription).filter_by(status="active", plan=plan_key).count()
    d["total_users"]  = db.query(User).filter_by(plan=plan_key).count()
    return success(d)


# ─── PATCH /plans/{plan_key} — Edit Plan Details (Save button) ────
@router.patch("/plans/{plan_key}")
def edit_plan_details(
    plan_key: str,
    body:     PlanUpdateBody,
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """
    Edit Plan Details — triggered by 'Save' button in the Edit Plan modal.
    Only fields included in the request body are updated (partial update).
    plan_key: free | starter | pro | premium
    """
    seed_plans(db)
    plan = db.get(Plan, plan_key)
    if not plan:
        raise HTTPException(status_code=404, detail=f"Plan '{plan_key}' not found")

    updatable = [
        "label", "description", "amount_usd", "per", "currency",
        "stripe_price_id_monthly", "stripe_price_id_yearly",
        "max_devices", "bandwidth_gb", "server_count", "simultaneous",
        "has_streaming", "has_p2p", "has_dedicated_ip",
        "has_ad_blocker", "has_kill_switch", "has_priority_support",
        "is_visible",
    ]
    updated_fields = []
    for field in updatable:
        value = getattr(body, field, None)
        if value is not None:
            setattr(plan, field, value)
            updated_fields.append(field)

    # Handle bandwidth_gb = null (explicit unlimited) separately
    if body.bandwidth_gb is None and "bandwidth_gb" in (body.model_fields_set if hasattr(body, "model_fields_set") else {}):
        plan.bandwidth_gb = None
        updated_fields.append("bandwidth_gb")

    plan.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(plan)

    d = plan.to_dict()
    d["active_subscriptions"] = db.query(Subscription).filter_by(status="active", plan=plan_key).count()
    d["total_users"]  = db.query(User).filter_by(plan=plan_key).count()
    d["updated_fields"] = updated_fields
    return success(d, f"Plan '{plan.label}' updated successfully.")
