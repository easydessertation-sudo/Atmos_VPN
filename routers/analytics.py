"""
Analytics Router — Dashboard Stats & Chart Data
GET /api/admin/dashboard              → all KPI cards + key metrics (single call)
GET /api/admin/stats                  → overview KPIs
GET /api/admin/analytics/mrr-trend    → 12-month monthly MRR chart
GET /api/admin/analytics/traffic-today → hourly bandwidth today (TB/hr)
GET /api/admin/analytics/plan-distribution → user count per plan (donut chart)
GET /api/admin/analytics/users        → daily user growth (N days)
GET /api/admin/analytics/revenue      → daily revenue (N days)
GET /api/admin/analytics/sessions     → daily sessions (N days)
GET /api/admin/analytics/bandwidth    → daily bandwidth (N days)
GET /api/admin/analytics/servers      → per-server load stats
GET /api/admin/search                 → global search (users, tickets, servers)
"""
from datetime import datetime, timedelta
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session
from sqlalchemy import func, case, text

from deps import admin_required, get_db, success
from models import (
    User, VPNSession, VPNServer, SupportTicket,
    Subscription, UsageLog
)

router = APIRouter()


# ─── helpers ───────────────────────────────────────────────────────────────
def _bytes_to_tb(b: int) -> float:
    return round(b / 1_099_511_627_776, 4)

def _bytes_to_gb(b: int) -> float:
    return round(b / 1_073_741_824, 3)

def _avg_session_seconds(db: Session) -> int:
    """Average duration of all completed VPN sessions in seconds."""
    rows = (
        db.query(VPNSession.started_at, VPNSession.ended_at)
        .filter(VPNSession.ended_at.isnot(None))
        .limit(5000)
        .all()
    )
    if not rows:
        return 0
    total = sum((r.ended_at - r.started_at).total_seconds() for r in rows)
    return int(total / len(rows))

def _avg_ticket_resolution_hours(db: Session) -> float:
    """Average hours from ticket created_at to updated_at (for resolved tickets)."""
    rows = (
        db.query(SupportTicket.created_at, SupportTicket.updated_at)
        .filter(SupportTicket.status.in_(["resolved", "closed"]))
        .filter(SupportTicket.updated_at.isnot(None))
        .limit(2000)
        .all()
    )
    if not rows:
        return 0.0
    total_h = sum(
        (r.updated_at - r.created_at).total_seconds() / 3600
        for r in rows
    )
    return round(total_h / len(rows), 1)


# ─── Dashboard (single call for the whole page) ────────────────────────────
@router.get("/dashboard")
def admin_dashboard(
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """
    Single endpoint that powers the entire Dashboard page.
    Returns KPI cards, key metrics, and chart-ready data so the
    frontend only needs ONE request on page load.

    Sections:
      kpi_cards       → 4 top cards
      key_metrics     → ARR, churn, avg session, bandwidth today etc.
      mrr_trend       → 12 monthly revenue points
      traffic_today   → 24 hourly TB/hr points
      plan_distribution → user counts per plan
    """
    now  = datetime.utcnow()
    today_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    this_month  = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    last_month  = (this_month - timedelta(days=1)).replace(day=1)

    # ── KPI: Total Users ──────────────────────────────────────────
    total_users      = db.query(User).count()
    users_this_month = db.query(User).filter(User.created_at >= this_month).count()
    users_last_month = db.query(User).filter(
        User.created_at >= last_month,
        User.created_at < this_month,
    ).count()
    user_growth_pct = (
        round(((users_this_month - users_last_month) / max(users_last_month, 1)) * 100, 1)
        if users_last_month else None
    )

    # ── KPI: MRR ─────────────────────────────────────────────────
    mrr_this_month = float(
        db.query(func.sum(Subscription.amount_usd))
        .filter_by(status="active")
        .scalar() or 0.0
    )
    mrr_last_month = float(
        db.query(func.sum(Subscription.amount_usd))
        .filter(
            Subscription.status.in_(["active", "cancelled"]),
            Subscription.started_at >= last_month,
            Subscription.started_at < this_month,
        )
        .scalar() or 0.0
    )
    mrr_delta = round(mrr_this_month - mrr_last_month, 2)

    # ── KPI: Servers ──────────────────────────────────────────────
    total_servers      = db.query(VPNServer).count()
    online_servers     = db.query(VPNServer).filter_by(is_online=True).count()
    maintenance_count  = total_servers - online_servers

    # ── KPI: Tickets ──────────────────────────────────────────────
    open_tickets   = db.query(SupportTicket).filter_by(status="open").count()
    # "urgent" = open billing or abuse tickets
    urgent_tickets = (
        db.query(SupportTicket)
        .filter(
            SupportTicket.status == "open",
            SupportTicket.category.in_(["billing", "abuse"]),
        )
        .count()
    )

    # ── Key Metrics ───────────────────────────────────────────────
    arr = round(mrr_this_month * 12, 2)

    # Churn: subscriptions cancelled this month / total active last month
    cancelled_this_month = (
        db.query(Subscription)
        .filter(
            Subscription.status == "cancelled",
            Subscription.cancelled_at >= this_month,
        )
        .count()
    )
    active_subs = db.query(Subscription).filter_by(status="active").count()
    churn_rate  = round((cancelled_this_month / max(active_subs, 1)) * 100, 1)

    # Trial→Paid conversion: paid users / total users
    paid_users        = db.query(User).filter(User.plan != "free").count()
    trial_paid_conv   = round((paid_users / max(total_users, 1)) * 100, 1)

    # Avg session duration
    avg_session_sec   = _avg_session_seconds(db)
    avg_session_hrs   = avg_session_sec // 3600
    avg_session_mins  = (avg_session_sec % 3600) // 60
    avg_session_label = f"{avg_session_hrs}h {avg_session_mins}m"

    # Bandwidth today
    bw_down_today = db.query(func.sum(VPNSession.bytes_down)).filter(
        VPNSession.started_at >= today_start
    ).scalar() or 0
    bw_up_today = db.query(func.sum(VPNSession.bytes_up)).filter(
        VPNSession.started_at >= today_start
    ).scalar() or 0
    bw_today_bytes = bw_down_today + bw_up_today
    bw_today_pb    = round(bw_today_bytes / 1_125_899_906_842_624, 2)  # PB

    # Avg ticket resolution time
    avg_ticket_res_h = _avg_ticket_resolution_hours(db)

    # Refund rate: no Stripe refund data → approximate as past_due / total subs
    past_due     = db.query(Subscription).filter_by(status="past_due").count()
    total_subs   = db.query(Subscription).count()
    refund_rate  = round((past_due / max(total_subs, 1)) * 100, 1)

    # ── MRR Trend (12 months) ─────────────────────────────────────
    mrr_trend = []
    for i in range(11, -1, -1):
        # Start of each month going back 12 months
        month_dt = (now.replace(day=1) - timedelta(days=i * 28)).replace(day=1)
        if i == 0:
            next_month = (month_dt + timedelta(days=32)).replace(day=1)
        else:
            next_month = (month_dt + timedelta(days=32)).replace(day=1)
        amount = float(
            db.query(func.sum(Subscription.amount_usd))
            .filter(
                Subscription.status == "active",
                Subscription.started_at < next_month,
            )
            .scalar() or 0.0
        )
        mrr_trend.append({
            "month":  month_dt.strftime("%b"),
            "year":   month_dt.year,
            "amount": round(amount, 2),
        })

    # ── Today's Traffic — single aggregated query (24 → 1 DB round-trip) ──
    # GROUP BY the hour extracted from started_at; only rows from today are included.
    # Each row: (hour_int, total_down, total_up)
    hourly_rows = (
        db.query(
            func.extract("hour", VPNSession.started_at).label("hr"),
            func.coalesce(func.sum(VPNSession.bytes_down), 0).label("down"),
            func.coalesce(func.sum(VPNSession.bytes_up),   0).label("up"),
        )
        .filter(VPNSession.started_at >= today_start)
        .group_by(func.extract("hour", VPNSession.started_at))
        .all()
    )
    # Build a lookup dict keyed by hour (0-23)
    hourly_lookup = {int(row.hr): (int(row.down), int(row.up)) for row in hourly_rows}

    traffic_today = []
    for hour in range(24):
        down, up = hourly_lookup.get(hour, (0, 0))
        total_bytes = down + up
        traffic_today.append({
            "hour":  f"{hour:02d}h",
            "tb":    _bytes_to_tb(total_bytes),
            "bytes": total_bytes,
        })

    # ── Plan Distribution ─────────────────────────────────────────
    plan_distribution = {}
    for plan in ["free", "starter", "pro", "premium"]:
        plan_distribution[plan] = db.query(User).filter_by(plan=plan).count()

    return success({
        "generated_at": now.isoformat() + "Z",
        "kpi_cards": {
            "total_users": {
                "value":        total_users,
                "growth_pct":   user_growth_pct,
                "new_this_month": users_this_month,
                "label":        "Total Users",
            },
            "mrr": {
                "value_usd":   round(mrr_this_month, 2),
                "delta_usd":   mrr_delta,
                "label":       "MRR",
            },
            "servers": {
                "online":      online_servers,
                "total":       total_servers,
                "maintenance": maintenance_count,
                "label":       "Active Servers",
            },
            "tickets": {
                "open":   open_tickets,
                "urgent": urgent_tickets,
                "label":  "Open Tickets",
            },
        },
        "key_metrics": {
            "arr_usd":          arr,
            "churn_rate_pct":   churn_rate,
            "trial_paid_conv_pct": trial_paid_conv,
            "avg_session":      avg_session_label,
            "avg_session_sec":  avg_session_sec,
            "refund_rate_pct":  refund_rate,
            "bandwidth_today_bytes": bw_today_bytes,
            "bandwidth_today_pb":    bw_today_pb,
            "avg_ticket_res_hrs":    avg_ticket_res_h,
            "avg_ticket_res_label":  f"{avg_ticket_res_h} hrs",
            "nps_score":        None,   # needs dedicated NPS survey table
        },
        "mrr_trend":        mrr_trend,
        "traffic_today":    traffic_today,
        "plan_distribution": plan_distribution,
    })


# ─── Stats (lightweight KPI-only) ─────────────────────────────────────────
@router.get("/stats")
def admin_stats(
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """Lightweight KPI summary — use /dashboard for the full dashboard payload."""
    now             = datetime.utcnow()
    this_month      = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    thirty_days_ago = now - timedelta(days=30)
    seven_days_ago  = now - timedelta(days=7)
    today_start     = now.replace(hour=0, minute=0, second=0, microsecond=0)

    total_users     = db.query(User).count()
    free_users      = db.query(User).filter_by(plan="free").count()
    active_sessions = db.query(VPNSession).filter_by(is_active=True).count()
    online_servers  = db.query(VPNServer).filter_by(is_online=True).count()
    total_servers   = db.query(VPNServer).count()
    open_tickets    = db.query(SupportTicket).filter_by(status="open").count()
    active_subs     = db.query(Subscription).filter_by(status="active").count()
    total_revenue   = float(
        db.query(func.sum(Subscription.amount_usd)).filter_by(status="active").scalar() or 0.0
    )

    new_users_30d   = db.query(User).filter(User.created_at >= thirty_days_ago).count()
    new_users_7d    = db.query(User).filter(User.created_at >= seven_days_ago).count()
    new_users_today = db.query(User).filter(User.created_at >= today_start).count()
    sessions_today  = db.query(VPNSession).filter(VPNSession.started_at >= today_start).count()

    total_bytes_down = int(db.query(func.sum(VPNSession.bytes_down)).scalar() or 0)
    total_bytes_up   = int(db.query(func.sum(VPNSession.bytes_up)).scalar()   or 0)

    plan_breakdown = {
        p: db.query(User).filter_by(plan=p).count()
        for p in ["free", "starter", "pro", "premium"]
    }

    return success({
        "overview": {
            "total_users":          total_users,
            "paid_users":           total_users - free_users,
            "free_users":           free_users,
            "active_sessions":      active_sessions,
            "total_sessions":       db.query(VPNSession).count(),
            "sessions_today":       sessions_today,
            "online_servers":       online_servers,
            "total_servers":        total_servers,
            "offline_servers":      total_servers - online_servers,
            "open_tickets":         open_tickets,
            "active_subscriptions": active_subs,
            "total_revenue_usd":    round(total_revenue, 2),
        },
        "growth": {
            "new_users_today": new_users_today,
            "new_users_7d":    new_users_7d,
            "new_users_30d":   new_users_30d,
        },
        "bandwidth": {
            "total_bytes_down": total_bytes_down,
            "total_bytes_up":   total_bytes_up,
            "total_bytes":      total_bytes_down + total_bytes_up,
            "total_gb":         _bytes_to_gb(total_bytes_down + total_bytes_up),
        },
        "plan_breakdown": plan_breakdown,
    })


# ─── MRR Trend — 12 months ────────────────────────────────────────────────
@router.get("/analytics/mrr-trend")
def analytics_mrr_trend(
    months: int = 12,
    _:      None    = Depends(admin_required),
    db:     Session = Depends(get_db),
):
    """
    Monthly MRR for the last N months (default 12).
    Powers the 'MRR Trend' line chart on the dashboard.
    Each point = cumulative active subscription revenue up to that month.
    """
    now    = datetime.utcnow()
    result = []
    for i in range(months - 1, -1, -1):
        month_start = (now.replace(day=1) - timedelta(days=i * 28)).replace(day=1)
        next_month  = (month_start + timedelta(days=32)).replace(day=1)
        amount = float(
            db.query(func.sum(Subscription.amount_usd))
            .filter(
                Subscription.status == "active",
                Subscription.started_at < next_month,
            )
            .scalar() or 0.0
        )
        result.append({
            "month":  month_start.strftime("%b"),
            "year":   month_start.year,
            "label":  month_start.strftime("%b %Y"),
            "amount": round(amount, 2),
        })
    return success(result)


# ─── Today's Traffic — hourly ─────────────────────────────────────────────
@router.get("/analytics/traffic-today")
def analytics_traffic_today(
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """
    Hourly bandwidth for today (00h–23h) in TB/hr.
    Powers the 'Today's Traffic' bar chart on the dashboard.
    """
    today_start = datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)
    # ── Today's Traffic — single aggregated query (24 → 1 DB round-trip) ──
    hourly_rows = (
        db.query(
            func.extract("hour", VPNSession.started_at).label("hr"),
            func.coalesce(func.sum(VPNSession.bytes_down), 0).label("down"),
            func.coalesce(func.sum(VPNSession.bytes_up),   0).label("up"),
        )
        .filter(VPNSession.started_at >= today_start)
        .group_by(func.extract("hour", VPNSession.started_at))
        .all()
    )
    hourly_lookup = {int(row.hr): (int(row.down), int(row.up)) for row in hourly_rows}

    result = []
    for hour in range(24):
        down, up = hourly_lookup.get(hour, (0, 0))
        total_bytes = down + up
        result.append({
            "hour":       f"{hour:02d}h",
            "tb":         _bytes_to_tb(total_bytes),
            "gb":         _bytes_to_gb(total_bytes),
            "bytes_down": down,
            "bytes_up":   up,
        })
    return success(result)


# ─── Plan Distribution ────────────────────────────────────────────────────
@router.get("/analytics/plan-distribution")
def analytics_plan_distribution(
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """
    User count per plan. Powers the 'Plan Distribution' donut chart.
    """
    total = db.query(User).count()
    plans = {}
    for plan in ["free", "starter", "pro", "premium"]:
        count = db.query(User).filter_by(plan=plan).count()
        plans[plan] = {
            "count": count,
            "pct":   round((count / max(total, 1)) * 100, 1),
        }
    return success({"total": total, "plans": plans})


# ─── User Growth — daily ──────────────────────────────────────────────────
@router.get("/analytics/users")
def analytics_user_growth(
    days: int = 30,
    _:    None    = Depends(admin_required),
    db:   Session = Depends(get_db),
):
    """Daily new user registrations for the last N days."""
    now    = datetime.utcnow()
    result = []
    for i in range(days - 1, -1, -1):
        day_start = (now - timedelta(days=i)).replace(hour=0, minute=0, second=0, microsecond=0)
        day_end   = day_start + timedelta(days=1)
        count = db.query(User).filter(
            User.created_at >= day_start,
            User.created_at <  day_end,
        ).count()
        result.append({"date": day_start.strftime("%Y-%m-%d"), "count": count})
    return success(result)


# ─── Revenue — daily ──────────────────────────────────────────────────────
@router.get("/analytics/revenue")
def analytics_revenue(
    days: int = 30,
    _:    None    = Depends(admin_required),
    db:   Session = Depends(get_db),
):
    """Daily new subscription revenue for the last N days."""
    now    = datetime.utcnow()
    result = []
    for i in range(days - 1, -1, -1):
        day_start = (now - timedelta(days=i)).replace(hour=0, minute=0, second=0, microsecond=0)
        day_end   = day_start + timedelta(days=1)
        amount = float(
            db.query(func.sum(Subscription.amount_usd))
            .filter(
                Subscription.started_at >= day_start,
                Subscription.started_at <  day_end,
                Subscription.status == "active",
            )
            .scalar() or 0.0
        )
        result.append({"date": day_start.strftime("%Y-%m-%d"), "amount_usd": round(amount, 2)})
    return success(result)


# ─── Sessions — daily ─────────────────────────────────────────────────────
@router.get("/analytics/sessions")
def analytics_sessions(
    days: int = 7,
    _:    None    = Depends(admin_required),
    db:   Session = Depends(get_db),
):
    """Daily VPN session counts for the last N days."""
    now    = datetime.utcnow()
    result = []
    for i in range(days - 1, -1, -1):
        day_start = (now - timedelta(days=i)).replace(hour=0, minute=0, second=0, microsecond=0)
        day_end   = day_start + timedelta(days=1)
        count = db.query(VPNSession).filter(
            VPNSession.started_at >= day_start,
            VPNSession.started_at <  day_end,
        ).count()
        result.append({"date": day_start.strftime("%Y-%m-%d"), "count": count})
    return success(result)


# ─── Bandwidth — daily ────────────────────────────────────────────────────
@router.get("/analytics/bandwidth")
def analytics_bandwidth(
    days: int = 7,
    _:    None    = Depends(admin_required),
    db:   Session = Depends(get_db),
):
    """Daily bandwidth totals for the last N days."""
    now    = datetime.utcnow()
    result = []
    for i in range(days - 1, -1, -1):
        day_start = (now - timedelta(days=i)).replace(hour=0, minute=0, second=0, microsecond=0)
        day_end   = day_start + timedelta(days=1)
        down = db.query(func.sum(VPNSession.bytes_down)).filter(
            VPNSession.started_at >= day_start,
            VPNSession.started_at <  day_end,
        ).scalar() or 0
        up = db.query(func.sum(VPNSession.bytes_up)).filter(
            VPNSession.started_at >= day_start,
            VPNSession.started_at <  day_end,
        ).scalar() or 0
        result.append({
            "date":        day_start.strftime("%Y-%m-%d"),
            "bytes_down":  down,
            "bytes_up":    up,
            "total_bytes": down + up,
            "total_gb":    _bytes_to_gb(down + up),
        })
    return success(result)


# ─── Per-Server Stats ─────────────────────────────────────────────────────
@router.get("/analytics/servers")
def analytics_servers(
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """Per-server session counts and load — for server health table."""
    servers = db.query(VPNServer).all()
    result  = []
    for s in servers:
        active = db.query(VPNSession).filter_by(server_id=s.id, is_active=True).count()
        total  = db.query(VPNSession).filter_by(server_id=s.id).count()
        result.append({
            "server_id":       s.id,
            "name":            s.name,
            "country":         s.country,
            "flag":            s.flag,
            "is_online":       s.is_online,
            "load_pct":        s.load_pct,
            "ping_ms":         s.ping_ms,
            "active_sessions": active,
            "total_sessions":  total,
            "current_peers":   s.current_peers,
            "max_peers":       s.max_peers,
        })
    result.sort(key=lambda x: x["active_sessions"], reverse=True)
    return success(result)


# ══════════════════════════════════════════════════════════════════════════
# ─── ANALYTICS PAGE — dedicated endpoints ─────────────────────────────────
# ══════════════════════════════════════════════════════════════════════════

@router.get("/analytics/overview")
def analytics_overview(
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """
    Single call that powers the entire Analytics & Traffic page.

    Returns:
      kpis              → 4 header cards (Concurrent Users, Bandwidth Today,
                          Peak Connections, Avg Session)
      traffic_by_hour   → 24-point bar chart (TB per hour, today)
      top_servers       → Top Servers by Load (sorted desc by load_pct)
      protocol_usage    → WireGuard / OpenVPN TCP / OpenVPN UDP / IKEv2 %
      user_growth_12m   → 12-month line chart (monthly new + cumulative users)
    """
    now         = datetime.utcnow()
    today_start = now.replace(hour=0, minute=0, second=0, microsecond=0)

    # ── KPI 1: Concurrent Users (active sessions right now) ───────────
    concurrent_users = db.query(VPNSession).filter_by(is_active=True).count()

    # ── KPI 2: Bandwidth Today ────────────────────────────────────────
    bw_down = db.query(func.sum(VPNSession.bytes_down)).filter(
        VPNSession.started_at >= today_start
    ).scalar() or 0
    bw_up = db.query(func.sum(VPNSession.bytes_up)).filter(
        VPNSession.started_at >= today_start
    ).scalar() or 0
    bw_today_bytes = bw_down + bw_up
    # Format: PB if ≥1PB, else TB, else GB
    pb = bw_today_bytes / 1_125_899_906_842_624
    tb = bw_today_bytes / 1_099_511_627_776
    gb = bw_today_bytes / 1_073_741_824
    if pb >= 1:
        bw_label = f"{pb:.2f} PB"
    elif tb >= 1:
        bw_label = f"{tb:.2f} TB"
    else:
        bw_label = f"{gb:.2f} GB"

    # ── KPI 3: Peak Connections (max active sessions on any single day) ─
    # Approximate: max sessions started on any calendar day in last 30 days
    peak_connections = 0
    for i in range(30):
        d_start = (now - timedelta(days=i)).replace(hour=0, minute=0, second=0, microsecond=0)
        d_end   = d_start + timedelta(days=1)
        day_count = db.query(VPNSession).filter(
            VPNSession.started_at >= d_start,
            VPNSession.started_at <  d_end,
        ).count()
        if day_count > peak_connections:
            peak_connections = day_count

    # ── KPI 4: Avg Session Duration ───────────────────────────────────
    avg_sec = _avg_session_seconds(db)
    avg_hrs  = avg_sec // 3600
    avg_mins = (avg_sec % 3600) // 60
    avg_session_label = f"{avg_hrs}h {avg_mins}m"

    # ── Traffic by Hour (24 bars) ─────────────────────────────────────
    # ── Traffic by Hour (24 bars) — single aggregated query ───────────
    hourly_rows = (
        db.query(
            func.extract("hour", VPNSession.started_at).label("hr"),
            func.coalesce(func.sum(VPNSession.bytes_down), 0).label("down"),
            func.coalesce(func.sum(VPNSession.bytes_up),   0).label("up"),
        )
        .filter(VPNSession.started_at >= today_start)
        .group_by(func.extract("hour", VPNSession.started_at))
        .all()
    )
    hourly_lookup = {int(row.hr): (int(row.down), int(row.up)) for row in hourly_rows}

    traffic_by_hour = []
    for hour in range(24):
        down, up = hourly_lookup.get(hour, (0, 0))
        total = down + up
        traffic_by_hour.append({
            "hour":  f"{hour:02d}h",
            "tb":    round(total / 1_099_511_627_776, 4),
            "gb":    round(total / 1_073_741_824, 3),
            "bytes": total,
        })

    # ── Top Servers by Load ───────────────────────────────────────────
    servers = db.query(VPNServer).order_by(VPNServer.load_pct.desc()).limit(10).all()
    top_servers = []
    for s in servers:
        top_servers.append({
            "server_id":    s.id,
            "name":         s.name,
            "city":         s.city,
            "country":      s.country,
            "country_code": s.country_code,
            "flag":         s.flag,
            "load_pct":     s.load_pct or 0,
            "status":       s.status or ("online" if s.is_online else "offline"),
            "current_peers": s.current_peers or 0,
            "max_peers":    s.max_peers or 500,
        })

    # ── Protocol Usage ────────────────────────────────────────────────
    # Count sessions per protocol (last 30 days for relevance)
    thirty_ago = now - timedelta(days=30)
    proto_counts = {}
    for proto in ["wireguard", "openvpn", "openvpn_tcp", "openvpn_udp", "ikev2"]:
        proto_counts[proto] = db.query(VPNSession).filter(
            VPNSession.protocol.ilike(proto.replace("_", "%")),
            VPNSession.started_at >= thirty_ago,
        ).count()

    # Merge openvpn into tcp/udp buckets if protocol stored as plain "openvpn"
    plain_openvpn = db.query(VPNSession).filter(
        VPNSession.protocol.ilike("openvpn"),
        VPNSession.started_at >= thirty_ago,
    ).count()
    total_sessions_30d = db.query(VPNSession).filter(
        VPNSession.started_at >= thirty_ago
    ).count() or 1

    wireguard_count   = db.query(VPNSession).filter(
        VPNSession.protocol.ilike("wireguard"),
        VPNSession.started_at >= thirty_ago,
    ).count()
    openvpn_tcp_count = db.query(VPNSession).filter(
        VPNSession.protocol.ilike("openvpn_tcp"),
        VPNSession.started_at >= thirty_ago,
    ).count()
    openvpn_udp_count = db.query(VPNSession).filter(
        VPNSession.protocol.ilike("openvpn_udp"),
        VPNSession.started_at >= thirty_ago,
    ).count()
    ikev2_count = db.query(VPNSession).filter(
        VPNSession.protocol.ilike("ikev2"),
        VPNSession.started_at >= thirty_ago,
    ).count()
    # If plain "openvpn" is stored, split 60/40 between tcp/udp
    openvpn_tcp_count += int(plain_openvpn * 0.6)
    openvpn_udp_count += int(plain_openvpn * 0.4)

    def pct(n): return round((n / total_sessions_30d) * 100, 1)

    protocol_usage = [
        {"protocol": "WireGuard",    "count": wireguard_count,   "pct": pct(wireguard_count)},
        {"protocol": "OpenVPN TCP",  "count": openvpn_tcp_count, "pct": pct(openvpn_tcp_count)},
        {"protocol": "OpenVPN UDP",  "count": openvpn_udp_count, "pct": pct(openvpn_udp_count)},
        {"protocol": "IKEv2",        "count": ikev2_count,       "pct": pct(ikev2_count)},
    ]
    protocol_usage.sort(key=lambda x: x["count"], reverse=True)

    # ── User Growth — 12 months (cumulative) ─────────────────────────
    user_growth_12m = []
    total_before = db.query(User).filter(
        User.created_at < (now.replace(day=1) - timedelta(days=11 * 28)).replace(day=1)
    ).count()
    running_total = total_before
    for i in range(11, -1, -1):
        month_start = (now.replace(day=1) - timedelta(days=i * 28)).replace(day=1)
        next_month  = (month_start + timedelta(days=32)).replace(day=1)
        new_users = db.query(User).filter(
            User.created_at >= month_start,
            User.created_at <  next_month,
        ).count()
        running_total += new_users
        user_growth_12m.append({
            "month":        month_start.strftime("%b"),
            "year":         month_start.year,
            "label":        month_start.strftime("%b %Y"),
            "new_users":    new_users,
            "total_users":  running_total,
        })

    return success({
        "generated_at": now.isoformat() + "Z",
        "kpis": {
            "concurrent_users":     concurrent_users,
            "bandwidth_today_bytes": bw_today_bytes,
            "bandwidth_today_label": bw_label,
            "peak_connections":     peak_connections,
            "avg_session_sec":      avg_sec,
            "avg_session_label":    avg_session_label,
        },
        "traffic_by_hour":  traffic_by_hour,
        "top_servers":      top_servers,
        "protocol_usage":   protocol_usage,
        "user_growth_12m":  user_growth_12m,
    })


@router.get("/analytics/top-servers")
def analytics_top_servers(
    limit: int = 10,
    _:     None    = Depends(admin_required),
    db:    Session = Depends(get_db),
):
    """
    Top servers by current load percentage.
    Powers the 'Top Servers by Load' section on the Analytics page.
    Sorted by load_pct descending.
    """
    servers = (
        db.query(VPNServer)
        .filter(VPNServer.load_pct.isnot(None))
        .order_by(VPNServer.load_pct.desc())
        .limit(limit)
        .all()
    )
    result = []
    for s in servers:
        active_sessions = db.query(VPNSession).filter_by(
            server_id=s.id, is_active=True
        ).count()
        result.append({
            "server_id":     s.id,
            "name":          s.name,
            "city":          s.city,
            "country":       s.country,
            "country_code":  s.country_code,
            "flag":          s.flag,
            "load_pct":      s.load_pct or 0,
            "status":        s.status or ("online" if s.is_online else "offline"),
            "current_peers": s.current_peers or 0,
            "max_peers":     s.max_peers or 500,
            "active_sessions": active_sessions,
        })
    return success(result)


@router.get("/analytics/protocol-usage")
def analytics_protocol_usage(
    days: int = 30,
    _:    None    = Depends(admin_required),
    db:   Session = Depends(get_db),
):
    """
    Protocol usage breakdown for the last N days.
    Powers the 'Protocol Usage' section on the Analytics page.
    Returns percentage split between WireGuard, OpenVPN TCP, OpenVPN UDP, IKEv2.
    """
    since = datetime.utcnow() - timedelta(days=days)
    total = db.query(VPNSession).filter(
        VPNSession.started_at >= since
    ).count() or 1

    def count_proto(pattern):
        return db.query(VPNSession).filter(
            VPNSession.protocol.ilike(pattern),
            VPNSession.started_at >= since,
        ).count()

    wireguard   = count_proto("wireguard")
    ovpn_tcp    = count_proto("openvpn_tcp")
    ovpn_udp    = count_proto("openvpn_udp")
    ikev2       = count_proto("ikev2")
    plain_ovpn  = count_proto("openvpn")   # stored without tcp/udp suffix

    # Split plain openvpn 60/40 tcp/udp
    ovpn_tcp += int(plain_ovpn * 0.6)
    ovpn_udp += int(plain_ovpn * 0.4)

    protocols = [
        {"protocol": "WireGuard",   "count": wireguard, "pct": round(wireguard / total * 100, 1)},
        {"protocol": "OpenVPN TCP", "count": ovpn_tcp,  "pct": round(ovpn_tcp  / total * 100, 1)},
        {"protocol": "OpenVPN UDP", "count": ovpn_udp,  "pct": round(ovpn_udp  / total * 100, 1)},
        {"protocol": "IKEv2",       "count": ikev2,     "pct": round(ikev2     / total * 100, 1)},
    ]
    protocols.sort(key=lambda x: x["count"], reverse=True)

    return success({
        "period_days":     days,
        "total_sessions":  total,
        "protocols":       protocols,
    })


@router.get("/analytics/user-growth-monthly")
def analytics_user_growth_monthly(
    months: int = 12,
    _:      None    = Depends(admin_required),
    db:     Session = Depends(get_db),
):
    """
    Monthly user growth for the last N months (default 12).
    Powers the 'User Growth (12 months)' line chart on the Analytics page.
    Returns both new users per month AND running cumulative total.
    """
    now   = datetime.utcnow()
    result = []
    running_total = db.query(User).filter(
        User.created_at < (now.replace(day=1) - timedelta(days=(months - 1) * 28)).replace(day=1)
    ).count()

    for i in range(months - 1, -1, -1):
        month_start = (now.replace(day=1) - timedelta(days=i * 28)).replace(day=1)
        next_month  = (month_start + timedelta(days=32)).replace(day=1)
        new_users = db.query(User).filter(
            User.created_at >= month_start,
            User.created_at <  next_month,
        ).count()
        running_total += new_users
        result.append({
            "month":       month_start.strftime("%b"),
            "year":        month_start.year,
            "label":       month_start.strftime("%b %Y"),
            "new_users":   new_users,
            "total_users": running_total,
        })

    return success(result)


# ─── Global Search ────────────────────────────────────────────────────────
@router.get("/search")
def admin_global_search(
    q:     str     = Query(..., min_length=2, description="Search query (min 2 chars)"),
    limit: int     = 5,
    _:     None    = Depends(admin_required),
    db:    Session = Depends(get_db),
):
    """
    Global search across users, tickets, and servers.
    Powers the top search bar on the admin panel.
    Returns up to `limit` results per category.
    """
    pattern = f"%{q}%"

    users = (
        db.query(User)
        .filter(
            User.email.ilike(pattern) |
            User.full_name.ilike(pattern)
        )
        .limit(limit).all()
    )

    tickets = (
        db.query(SupportTicket)
        .filter(
            SupportTicket.email.ilike(pattern) |
            SupportTicket.subject.ilike(pattern)
        )
        .limit(limit).all()
    )

    servers = (
        db.query(VPNServer)
        .filter(
            VPNServer.name.ilike(pattern) |
            VPNServer.country.ilike(pattern) |
            VPNServer.city.ilike(pattern)
        )
        .limit(limit).all()
    )

    return success({
        "query": q,
        "users": [
            {"id": str(u.id), "email": u.email, "full_name": u.full_name, "plan": u.plan}
            for u in users
        ],
        "tickets": [
            {"id": str(t.id), "email": t.email, "subject": t.subject, "status": t.status}
            for t in tickets
        ],
        "servers": [
            {"id": s.id, "name": s.name, "country": s.country, "flag": s.flag, "is_online": s.is_online}
            for s in servers
        ],
    })
