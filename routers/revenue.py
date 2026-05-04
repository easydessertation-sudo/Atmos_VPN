"""
Revenue & Finance Router
GET /api/admin/revenue/overview        → full page payload (single call)
GET /api/admin/revenue/kpis            → 4 KPI cards (MRR, ARR, Churn, Avg LTV)
GET /api/admin/revenue/mrr-growth      → 12-month MRR growth chart
GET /api/admin/revenue/by-plan         → Revenue by Plan section
GET /api/admin/revenue/payment-methods → Payment Methods breakdown
"""
from datetime import datetime, timedelta
from fastapi import APIRouter, Depends
from sqlalchemy import func
from sqlalchemy.orm import Session

from deps import admin_required, get_db, success
from models import Subscription, User, VPNSession

router = APIRouter()

# ─── Plan config (UI labels) ───────────────────────────────────────────────
PLAN_CONFIG = {
    "free":    {"label": "Free",    "price_label": "$0/mo",      "price": 0.00},
    "starter": {"label": "Starter", "price_label": "$3.99/mo",   "price": 3.99},
    "pro":     {"label": "Pro",     "price_label": "$3.99/mo",   "price": 3.99},
    "premium": {"label": "Team",    "price_label": "$7.99/seat", "price": 7.99},
}


# ─── Helpers ────────────────────────────────────────────────────────────────
def _get_mrr(db: Session, reference_date: datetime = None) -> float:
    """Total MRR from active subscriptions. If reference_date given, use subs active at that date."""
    q = db.query(func.sum(Subscription.amount_usd)).filter_by(status="active")
    if reference_date:
        q = db.query(func.sum(Subscription.amount_usd)).filter(
            Subscription.status == "active",
            Subscription.started_at <= reference_date,
        )
    return float(q.scalar() or 0.0)


def _get_churn_rate(db: Session) -> tuple:
    """
    Churn rate = subscriptions cancelled this month / active subs at start of month.
    Returns (churn_pct, delta_vs_last_month_pct)
    """
    now        = datetime.utcnow()
    this_month = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    last_month = (this_month - timedelta(days=1)).replace(day=1)

    cancelled_this_month = db.query(Subscription).filter(
        Subscription.status == "cancelled",
        Subscription.cancelled_at >= this_month,
    ).count()
    cancelled_last_month = db.query(Subscription).filter(
        Subscription.status == "cancelled",
        Subscription.cancelled_at >= last_month,
        Subscription.cancelled_at < this_month,
    ).count()

    active_subs = max(db.query(Subscription).filter_by(status="active").count(), 1)

    churn_this = round((cancelled_this_month / active_subs) * 100, 1)
    churn_last = round((cancelled_last_month / active_subs) * 100, 1)
    delta      = round(churn_this - churn_last, 1)

    return churn_this, delta


def _get_avg_ltv(db: Session) -> float:
    """
    Avg LTV (Lifetime Value) = total all-time subscription revenue / total unique paying users.
    """
    total_revenue = float(db.query(func.sum(Subscription.amount_usd)).scalar() or 0.0)
    paying_users  = db.query(Subscription.user_id).distinct().count()
    if paying_users == 0:
        return 0.0
    return round(total_revenue / paying_users, 2)


def _build_mrr_growth(db: Session, months: int = 12) -> list:
    """Build monthly MRR data points for the last N months."""
    now    = datetime.utcnow()
    result = []
    for i in range(months - 1, -1, -1):
        # Start of each calendar month going back
        month_start = (now.replace(day=1) - timedelta(days=i * 28)).replace(day=1)
        next_month  = (month_start + timedelta(days=32)).replace(day=1)

        # New revenue added this month
        new_revenue = float(
            db.query(func.sum(Subscription.amount_usd)).filter(
                Subscription.status.in_(["active", "cancelled", "expired"]),
                Subscription.started_at >= month_start,
                Subscription.started_at <  next_month,
            ).scalar() or 0.0
        )
        # Cumulative active MRR at end of this month
        cumulative = float(
            db.query(func.sum(Subscription.amount_usd)).filter(
                Subscription.status == "active",
                Subscription.started_at < next_month,
            ).scalar() or 0.0
        )

        result.append({
            "month":      month_start.strftime("%b"),
            "year":       month_start.year,
            "label":      month_start.strftime("%b %Y"),
            "mrr":        round(cumulative, 2),
            "new_revenue": round(new_revenue, 2),
        })
    return result


def _build_revenue_by_plan(db: Session) -> list:
    """Revenue breakdown per plan with user counts, MRR, and % of total MRR."""
    total_mrr = _get_mrr(db)
    plans_out = []

    for plan_key, cfg in PLAN_CONFIG.items():
        active_subs = db.query(Subscription).filter_by(status="active", plan=plan_key).count()
        user_count  = db.query(User).filter_by(plan=plan_key).count()
        plan_mrr    = float(
            db.query(func.sum(Subscription.amount_usd))
            .filter_by(status="active", plan=plan_key)
            .scalar() or 0.0
        )
        mrr_pct = round((plan_mrr / total_mrr * 100), 1) if total_mrr > 0 else 0.0

        plans_out.append({
            "plan":            plan_key,
            "label":           cfg["label"],
            "price_label":     cfg["price_label"],
            "user_count":      user_count,
            "active_subs":     active_subs,
            "mrr_usd":         round(plan_mrr, 2),
            "mrr_pct":         mrr_pct,
            "mrr_label":       f"${plan_mrr/1_000_000:.2f}M" if plan_mrr >= 1_000_000 else f"${plan_mrr:,.0f}",
        })

    # Sort by MRR descending
    plans_out.sort(key=lambda x: x["mrr_usd"], reverse=True)
    return plans_out


# ─── 1. Full Page Overview (single call) ──────────────────────────────────
@router.get("/revenue/overview")
def revenue_overview(
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """
    Single endpoint for the entire Revenue & Finance page.
    Returns KPI cards, MRR growth chart, revenue by plan, and payment methods.
    """
    now            = datetime.utcnow()
    this_month     = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    last_month_end = this_month - timedelta(seconds=1)
    last_year      = now - timedelta(days=365)

    # ── MRR ──────────────────────────────────────────────────────
    mrr_now       = _get_mrr(db)
    mrr_last_month = _get_mrr(db, reference_date=last_month_end)
    mrr_delta_usd = round(mrr_now - mrr_last_month, 2)
    mrr_delta_pct = round(
        ((mrr_now - mrr_last_month) / max(mrr_last_month, 1)) * 100, 1
    )

    # ── ARR ──────────────────────────────────────────────────────
    arr_now      = mrr_now * 12
    arr_last_year = _get_mrr(db, reference_date=last_year) * 12
    arr_yoy_pct  = round(
        ((arr_now - arr_last_year) / max(arr_last_year, 1)) * 100, 1
    )

    # ── Churn ────────────────────────────────────────────────────
    churn_rate, churn_delta = _get_churn_rate(db)

    # ── Avg LTV ──────────────────────────────────────────────────
    avg_ltv = _get_avg_ltv(db)

    # ── Charts ───────────────────────────────────────────────────
    mrr_growth       = _build_mrr_growth(db, months=12)
    revenue_by_plan  = _build_revenue_by_plan(db)

    return success({
        "generated_at": now.isoformat() + "Z",
        "kpis": {
            "mrr": {
                "value_usd":   round(mrr_now, 2),
                "delta_usd":   mrr_delta_usd,
                "delta_pct":   mrr_delta_pct,
                "label":       "MRR",
                "note":        "vs Last month",
            },
            "arr": {
                "value_usd":  round(arr_now, 2),
                "yoy_pct":    arr_yoy_pct,
                "label":      "ARR",
                "note":       "YoY",
            },
            "churn_rate": {
                "value_pct":  churn_rate,
                "delta_pct":  churn_delta,
                "label":      "Churn Rate",
                "improved":   churn_delta < 0,
            },
            "avg_ltv": {
                "value_usd":  avg_ltv,
                "label":      "Avg LTV",
            },
        },
        "mrr_growth":      mrr_growth,
        "revenue_by_plan": revenue_by_plan,
        "payment_methods": {
            "note": "Payment method breakdown requires Stripe integration. Wire up Stripe charge data to populate real percentages.",
            "data": None,
        },
    })


# ─── 2. KPI Cards only ────────────────────────────────────────────────────
@router.get("/revenue/kpis")
def revenue_kpis(
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """4 KPI cards: MRR, ARR, Churn Rate, Avg LTV."""
    now            = datetime.utcnow()
    this_month     = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    last_month_end = this_month - timedelta(seconds=1)
    last_year      = now - timedelta(days=365)

    mrr_now        = _get_mrr(db)
    mrr_last_month = _get_mrr(db, reference_date=last_month_end)
    arr_now        = mrr_now * 12
    arr_last_year  = _get_mrr(db, reference_date=last_year) * 12
    churn_rate, churn_delta = _get_churn_rate(db)
    avg_ltv = _get_avg_ltv(db)

    return success({
        "mrr": {
            "value_usd":  round(mrr_now, 2),
            "delta_usd":  round(mrr_now - mrr_last_month, 2),
            "delta_pct":  round(((mrr_now - mrr_last_month) / max(mrr_last_month, 1)) * 100, 1),
        },
        "arr": {
            "value_usd": round(arr_now, 2),
            "yoy_pct":   round(((arr_now - arr_last_year) / max(arr_last_year, 1)) * 100, 1),
        },
        "churn_rate": {
            "value_pct": churn_rate,
            "delta_pct": churn_delta,
            "improved":  churn_delta < 0,
        },
        "avg_ltv": {
            "value_usd": avg_ltv,
        },
    })


# ─── 3. MRR Growth Chart ──────────────────────────────────────────────────
@router.get("/revenue/mrr-growth")
def revenue_mrr_growth(
    months: int = 12,
    _:      None    = Depends(admin_required),
    db:     Session = Depends(get_db),
):
    """
    12-month MRR growth chart data.
    Each point has: month label, cumulative MRR, new revenue added that month.
    """
    return success(_build_mrr_growth(db, months=months))


# ─── 4. Revenue by Plan ───────────────────────────────────────────────────
@router.get("/revenue/by-plan")
def revenue_by_plan(
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """
    Revenue breakdown per plan.
    Returns user count, active subs, MRR amount, and % share of total MRR.
    """
    total_mrr = _get_mrr(db)
    return success({
        "total_mrr_usd": round(total_mrr, 2),
        "plans": _build_revenue_by_plan(db),
    })


# ─── 5. Payment Methods ───────────────────────────────────────────────────
@router.get("/revenue/payment-methods")
def revenue_payment_methods(
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """
    Payment method breakdown.
    NOTE: Real data requires Stripe integration (charge objects have payment_method_details).
    Currently returns null — wire up Stripe charge list API to populate.

    To enable real data:
      1. Call Stripe API: stripe.Charge.list(limit=1000)
      2. Group by charge.payment_method_details.type
      3. Calculate percentages
      4. Cache result in Redis with 1-hour TTL
    """
    return success({
        "note":     "Requires Stripe integration. See endpoint docstring for implementation guide.",
        "methods":  None,
        "stripe_integration_required": True,
    })
