"""
Promotions & Coupons Router  —  /api/admin/promotions/*

┌─────────────────────────────────────────────────────────────────┐
│  COUPON CODES                                                   │
│  GET    /api/admin/promotions/coupons            → list all     │
│  POST   /api/admin/promotions/coupons            → create       │
│  GET    /api/admin/promotions/coupons/{id}       → detail       │
│  PATCH  /api/admin/promotions/coupons/{id}       → update       │
│  DELETE /api/admin/promotions/coupons/{id}       → delete       │
│  POST   /api/admin/promotions/coupons/{id}/toggle→ activate /   │
│                                                     deactivate  │
│  POST   /api/admin/promotions/validate           → validate a   │
│                                                    coupon code  │
├─────────────────────────────────────────────────────────────────┤
│  REFERRAL PROGRAM                                               │
│  GET    /api/admin/promotions/referrals          → stats + list │
│  GET    /api/admin/promotions/referrals/config   → commission % │
│  PATCH  /api/admin/promotions/referrals/config   → update rate  │
├─────────────────────────────────────────────────────────────────┤
│  AFFILIATE PROGRAM                                              │
│  GET    /api/admin/promotions/affiliates         → list all     │
│  POST   /api/admin/promotions/affiliates         → add new      │
│  GET    /api/admin/promotions/affiliates/{id}    → detail       │
│  PATCH  /api/admin/promotions/affiliates/{id}    → update       │
│  DELETE /api/admin/promotions/affiliates/{id}    → remove       │
├─────────────────────────────────────────────────────────────────┤
│  OVERVIEW                                                       │
│  GET    /api/admin/promotions/overview           → full page    │
└─────────────────────────────────────────────────────────────────┘
"""
import json
import os
import string
import random
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, EmailStr, Field
from sqlalchemy import func
from sqlalchemy.orm import Session

from deps import admin_required, get_db, success
from models import CouponCode, Referral, Affiliate, User, Subscription

router = APIRouter()

# ─── Referral program config (stored in .env / DB-less for simplicity) ────
# In production move to a DB settings table. For now env-backed defaults.
REFERRAL_COMMISSION_RATE = float(os.environ.get("REFERRAL_COMMISSION_PCT", "30.0"))


# ══════════════════════════════════════════════════════════════════════════
# ─── Pydantic Schemas ─────────────────────────────────────────────────────
# ══════════════════════════════════════════════════════════════════════════

class CreateCouponBody(BaseModel):
    code:           str   = Field(..., min_length=2, max_length=50)
    discount_type:  str   = Field(..., pattern="^(percent|fixed)$")
    discount_value: float = Field(..., gt=0)
    plan:           Optional[str]  = None          # null = valid for all plans
    use_limit:      Optional[int]  = None          # null = unlimited
    expires_at:     Optional[str]  = None          # "YYYY-MM-DD" or null
    created_by:     Optional[str]  = None


class UpdateCouponBody(BaseModel):
    discount_type:  Optional[str]   = None
    discount_value: Optional[float] = None
    plan:           Optional[str]   = None
    use_limit:      Optional[int]   = None
    expires_at:     Optional[str]   = None
    status:         Optional[str]   = None


class ValidateCouponBody(BaseModel):
    code: str
    plan: Optional[str] = None   # check if coupon applies to this plan


class UpdateReferralConfigBody(BaseModel):
    commission_rate_pct: float = Field(..., ge=0, le=100)


class CreateAffiliateBody(BaseModel):
    name:             str
    email:            str
    affiliate_code:   Optional[str]  = None   # auto-generated if omitted
    commission_type:  Optional[str]  = "percent"
    commission_value: Optional[float] = 30.0
    payout_method:    Optional[str]  = "paypal"
    payout_details:   Optional[dict] = None


class UpdateAffiliateBody(BaseModel):
    name:             Optional[str]   = None
    status:           Optional[str]   = None
    commission_type:  Optional[str]   = None
    commission_value: Optional[float] = None
    payout_method:    Optional[str]   = None
    payout_details:   Optional[dict]  = None


# ══════════════════════════════════════════════════════════════════════════
# ─── Helpers ───────────────────────────────────────────────────────────────
# ══════════════════════════════════════════════════════════════════════════

def _parse_date(date_str: Optional[str]) -> Optional[datetime]:
    """Parse YYYY-MM-DD string → datetime. Returns None if input is None."""
    if not date_str:
        return None
    try:
        return datetime.strptime(date_str, "%Y-%m-%d")
    except ValueError:
        raise HTTPException(status_code=400, detail=f"Invalid date format: '{date_str}'. Use YYYY-MM-DD.")


def _auto_expire_coupons(db: Session):
    """Mark coupons whose expiry date has passed as 'expired'."""
    now = datetime.utcnow()
    expired = db.query(CouponCode).filter(
        CouponCode.expires_at != None,
        CouponCode.expires_at < now,
        CouponCode.status == "active",
    ).all()
    for c in expired:
        c.status = "expired"
    if expired:
        db.commit()


def _gen_affiliate_code(name: str) -> str:
    """Generate a unique-ish affiliate code from name + random suffix."""
    base = name.upper().replace(" ", "_")[:12]
    suffix = "".join(random.choices(string.digits, k=4))
    return f"{base}_{suffix}"


def _referral_stats(db: Session) -> dict:
    """Compute referral program aggregate stats from the referrals table."""
    total_referrers = db.query(Referral.referrer_id).distinct().count()
    total_referrals = db.query(Referral).count()
    conversions     = db.query(Referral).filter_by(status="converted").count() + \
                      db.query(Referral).filter_by(status="paid").count()
    commission_paid = float(
        db.query(func.sum(Referral.commission_usd))
        .filter(Referral.status == "paid")
        .scalar() or 0.0
    )
    return {
        "active_referrers":    total_referrers,
        "total_referrals":     total_referrals,
        "conversions":         conversions,
        "commission_paid_usd": round(commission_paid, 2),
        "commission_rate_pct": REFERRAL_COMMISSION_RATE,
        "commission_rate_label": f"{REFERRAL_COMMISSION_RATE:.0f}% of 1st payment",
    }


def _affiliate_stats(db: Session) -> dict:
    """Compute affiliate program aggregate stats."""
    active_count = db.query(Affiliate).filter_by(status="active").count()

    monthly_rev = float(
        db.query(func.sum(Affiliate.total_revenue_generated)).scalar() or 0.0
    )
    top_commission = float(
        db.query(func.max(Affiliate.total_commission_paid)).scalar() or 0.0
    )
    all_commissions = db.query(Affiliate.total_commission_paid).all()
    if all_commissions:
        vals = [r[0] for r in all_commissions if r[0] is not None]
        avg_commission = round(sum(vals) / len(vals), 2) if vals else 0.0
    else:
        avg_commission = 0.0

    payout_methods = set(
        r[0] for r in db.query(Affiliate.payout_method).distinct().all() if r[0]
    )

    return {
        "active_affiliates":     active_count,
        "affiliate_revenue_monthly_usd": round(monthly_rev, 2),
        "top_commission_usd":    round(top_commission, 2),
        "avg_commission_usd":    avg_commission,
        "payout_methods":        " / ".join(m.capitalize() for m in sorted(payout_methods)) or "PayPal / Crypto",
    }


# ══════════════════════════════════════════════════════════════════════════
# ─── OVERVIEW ─────────────────────────────────────────────────────────────
# ══════════════════════════════════════════════════════════════════════════

@router.get("/promotions/overview")
def promotions_overview(
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """
    Single call to populate the entire Promotions & Coupons page.
    Returns coupon list + referral stats + affiliate stats in one shot.
    Frontend can also hit the sub-endpoints independently for partial refreshes.
    """
    _auto_expire_coupons(db)

    coupons = db.query(CouponCode).order_by(CouponCode.created_at.desc()).all()
    affiliates = db.query(Affiliate).order_by(Affiliate.joined_at.desc()).all()

    return success({
        "generated_at":    datetime.utcnow().isoformat() + "Z",
        "coupon_codes":    [c.to_dict() for c in coupons],
        "referral_program": _referral_stats(db),
        "affiliate_program": {
            **_affiliate_stats(db),
            "affiliates": [a.to_dict() for a in affiliates],
        },
    })


# ══════════════════════════════════════════════════════════════════════════
# ─── COUPON CODES ─────────────────────────────────────────────────────────
# ══════════════════════════════════════════════════════════════════════════

@router.get("/promotions/coupons")
def list_coupons(
    status: Optional[str] = None,   # filter: active | inactive | expired
    plan:   Optional[str] = None,
    search: Optional[str] = None,
    page:   int = 1,
    limit:  int = 50,
    _:      None    = Depends(admin_required),
    db:     Session = Depends(get_db),
):
    """
    List all coupon codes. Supports filtering by status, plan, and code search.
    Auto-expires any coupons past their expiry date before returning.
    """
    _auto_expire_coupons(db)

    q = db.query(CouponCode)
    if status:
        q = q.filter_by(status=status)
    if plan:
        q = q.filter_by(plan=plan)
    if search:
        q = q.filter(CouponCode.code.ilike(f"%{search}%"))

    total   = q.count()
    coupons = q.order_by(CouponCode.created_at.desc()).offset((page - 1) * limit).limit(limit).all()

    return success({
        "coupons": [c.to_dict() for c in coupons],
        "total":   total,
        "page":    page,
        "limit":   limit,
        "pages":   (total + limit - 1) // limit,
        "counts": {
            "active":   db.query(CouponCode).filter_by(status="active").count(),
            "inactive": db.query(CouponCode).filter_by(status="inactive").count(),
            "expired":  db.query(CouponCode).filter_by(status="expired").count(),
        },
    })


@router.post("/promotions/coupons")
def create_coupon(
    body: CreateCouponBody,
    _:   None    = Depends(admin_required),
    db:  Session = Depends(get_db),
):
    """
    Create a new coupon code.
    - code must be unique (case-insensitive check)
    - discount_type: 'percent' or 'fixed'
    - expires_at: optional YYYY-MM-DD, null = never expires
    - use_limit:  optional int, null = unlimited
    """
    code_upper = body.code.upper().strip()

    existing = db.query(CouponCode).filter(
        func.upper(CouponCode.code) == code_upper
    ).first()
    if existing:
        raise HTTPException(status_code=409, detail=f"Coupon code '{code_upper}' already exists.")

    expires = _parse_date(body.expires_at)

    # Auto-set status to 'expired' if expiry is already in the past
    status = "active"
    if expires and expires < datetime.utcnow():
        status = "expired"

    coupon = CouponCode(
        code           = code_upper,
        discount_type  = body.discount_type,
        discount_value = body.discount_value,
        plan           = body.plan,
        use_limit      = body.use_limit,
        expires_at     = expires,
        status         = status,
        created_by     = body.created_by,
    )
    db.add(coupon)
    db.commit()
    db.refresh(coupon)
    return success(coupon.to_dict(), "Coupon created successfully", 201)


@router.get("/promotions/coupons/{coupon_id}")
def get_coupon(
    coupon_id: str,
    _:         None    = Depends(admin_required),
    db:        Session = Depends(get_db),
):
    """Get a single coupon by ID."""
    coupon = db.get(CouponCode, coupon_id)
    if not coupon:
        raise HTTPException(status_code=404, detail="Coupon not found")
    return success(coupon.to_dict())


@router.patch("/promotions/coupons/{coupon_id}")
def update_coupon(
    coupon_id: str,
    body:      UpdateCouponBody,
    _:         None    = Depends(admin_required),
    db:        Session = Depends(get_db),
):
    """Update an existing coupon (any editable field)."""
    coupon = db.get(CouponCode, coupon_id)
    if not coupon:
        raise HTTPException(status_code=404, detail="Coupon not found")

    if body.discount_type  is not None: coupon.discount_type  = body.discount_type
    if body.discount_value is not None: coupon.discount_value = body.discount_value
    if body.plan           is not None: coupon.plan           = body.plan
    if body.use_limit      is not None: coupon.use_limit      = body.use_limit
    if body.status         is not None: coupon.status         = body.status
    if body.expires_at     is not None: coupon.expires_at     = _parse_date(body.expires_at)

    db.commit()
    db.refresh(coupon)
    return success(coupon.to_dict(), "Coupon updated successfully")


@router.delete("/promotions/coupons/{coupon_id}")
def delete_coupon(
    coupon_id: str,
    _:         None    = Depends(admin_required),
    db:        Session = Depends(get_db),
):
    """Permanently delete a coupon code."""
    coupon = db.get(CouponCode, coupon_id)
    if not coupon:
        raise HTTPException(status_code=404, detail="Coupon not found")
    db.delete(coupon)
    db.commit()
    return success({"id": coupon_id}, "Coupon deleted successfully")


@router.post("/promotions/coupons/{coupon_id}/toggle")
def toggle_coupon_status(
    coupon_id: str,
    _:         None    = Depends(admin_required),
    db:        Session = Depends(get_db),
):
    """
    Toggle a coupon between active ↔ inactive.
    Expired coupons cannot be re-activated (update expires_at first).
    """
    coupon = db.get(CouponCode, coupon_id)
    if not coupon:
        raise HTTPException(status_code=404, detail="Coupon not found")

    if coupon.status == "expired":
        raise HTTPException(
            status_code=409,
            detail="Cannot toggle an expired coupon. Update the expiry date first."
        )

    coupon.status = "inactive" if coupon.status == "active" else "active"
    db.commit()
    db.refresh(coupon)
    return success(coupon.to_dict(), f"Coupon is now {coupon.status}")


@router.post("/promotions/validate")
def validate_coupon(
    body: ValidateCouponBody,
    _:   None    = Depends(admin_required),
    db:  Session = Depends(get_db),
):
    """
    Validate a coupon code at checkout.
    Checks: exists, active, not expired, plan restriction, use limit.
    Does NOT increment uses — call PATCH /coupons/{id} to apply it after payment.

    Frontend use: call this when user submits a coupon code on checkout page.
    """
    _auto_expire_coupons(db)

    code_upper = body.code.upper().strip()
    coupon = db.query(CouponCode).filter(
        func.upper(CouponCode.code) == code_upper
    ).first()

    if not coupon:
        raise HTTPException(status_code=404, detail="Coupon code not found")
    if coupon.status != "active":
        raise HTTPException(status_code=410, detail=f"Coupon is {coupon.status}")
    if coupon.use_limit and coupon.uses >= coupon.use_limit:
        raise HTTPException(status_code=410, detail="Coupon usage limit reached")
    if body.plan and coupon.plan and coupon.plan != body.plan:
        raise HTTPException(
            status_code=422,
            detail=f"Coupon is only valid for the '{coupon.plan}' plan"
        )

    return success({
        **coupon.to_dict(),
        "valid": True,
        "message": f"Coupon valid — {coupon.discount_value}{'%' if coupon.discount_type == 'percent' else '$'} off",
    }, "Coupon is valid")


# ══════════════════════════════════════════════════════════════════════════
# ─── REFERRAL PROGRAM ─────────────────────────────────────────────────────
# ══════════════════════════════════════════════════════════════════════════

@router.get("/promotions/referrals")
def referral_program(
    page:   int = 1,
    limit:  int = 20,
    status: Optional[str] = None,  # pending | converted | paid
    _:      None    = Depends(admin_required),
    db:     Session = Depends(get_db),
):
    """
    Referral Program section of the Promotions page.
    Returns aggregate stats + paginated list of individual referral events.
    Stats shown in UI: Active Referrers, Total Referrals, Conversions, Commission Paid, Rate.
    """
    stats = _referral_stats(db)

    q = db.query(Referral)
    if status:
        q = q.filter_by(status=status)

    total    = q.count()
    referrals = q.order_by(Referral.signed_up_at.desc()).offset((page - 1) * limit).limit(limit).all()

    enriched = []
    for r in referrals:
        d = r.to_dict()
        referrer = db.get(User, r.referrer_id) if r.referrer_id else None
        referred = db.get(User, r.referred_id) if r.referred_id else None
        d["referrer_email"] = referrer.email     if referrer else None
        d["referrer_name"]  = referrer.full_name if referrer else None
        d["referred_email"] = referred.email     if referred else None
        enriched.append(d)

    return success({
        "stats":     stats,
        "referrals": enriched,
        "total":     total,
        "page":      page,
        "limit":     limit,
        "pages":     (total + limit - 1) // limit,
    })


@router.get("/promotions/referrals/config")
def get_referral_config(
    _:  None = Depends(admin_required),
):
    """Get the current referral commission configuration."""
    return success({
        "commission_rate_pct":   REFERRAL_COMMISSION_RATE,
        "commission_rate_label": f"{REFERRAL_COMMISSION_RATE:.0f}% of 1st payment",
        "note": "Update via PATCH /promotions/referrals/config. "
                "Set REFERRAL_COMMISSION_PCT env var to persist across restarts.",
    })


@router.patch("/promotions/referrals/config")
def update_referral_config(
    body: UpdateReferralConfigBody,
    _:   None = Depends(admin_required),
):
    """
    Update the referral commission rate.
    NOTE: This updates the in-memory value for the running process.
    Set REFERRAL_COMMISSION_PCT in your .env to make it permanent.
    """
    global REFERRAL_COMMISSION_RATE
    REFERRAL_COMMISSION_RATE = body.commission_rate_pct
    return success({
        "commission_rate_pct":   REFERRAL_COMMISSION_RATE,
        "commission_rate_label": f"{REFERRAL_COMMISSION_RATE:.0f}% of 1st payment",
    }, f"Commission rate updated to {REFERRAL_COMMISSION_RATE:.0f}%")


# ══════════════════════════════════════════════════════════════════════════
# ─── AFFILIATE PROGRAM ────────────────────────────────────────────────────
# ══════════════════════════════════════════════════════════════════════════

@router.get("/promotions/affiliates")
def list_affiliates(
    status: Optional[str] = None,
    search: Optional[str] = None,
    page:   int = 1,
    limit:  int = 20,
    _:      None    = Depends(admin_required),
    db:     Session = Depends(get_db),
):
    """
    List all affiliate partners with their stats.
    Affiliate Program section of the Promotions page.
    Stats shown in UI: Active Affiliates, Rev/mo, Top Commission, Avg Commission, Payout.
    """
    q = db.query(Affiliate)
    if status:
        q = q.filter_by(status=status)
    if search:
        q = q.filter(
            Affiliate.name.ilike(f"%{search}%") |
            Affiliate.email.ilike(f"%{search}%") |
            Affiliate.affiliate_code.ilike(f"%{search}%")
        )

    total      = q.count()
    affiliates = q.order_by(Affiliate.joined_at.desc()).offset((page - 1) * limit).limit(limit).all()

    return success({
        "stats":      _affiliate_stats(db),
        "affiliates": [a.to_dict() for a in affiliates],
        "total":      total,
        "page":       page,
        "limit":      limit,
        "pages":      (total + limit - 1) // limit,
    })


@router.post("/promotions/affiliates")
def add_affiliate(
    body: CreateAffiliateBody,
    _:   None    = Depends(admin_required),
    db:  Session = Depends(get_db),
):
    """
    Add a new affiliate partner.
    affiliate_code is auto-generated if not provided.
    Email must be unique.
    """
    existing = db.query(Affiliate).filter_by(email=body.email).first()
    if existing:
        raise HTTPException(status_code=409, detail="An affiliate with this email already exists.")

    code = body.affiliate_code or _gen_affiliate_code(body.name)
    code_clash = db.query(Affiliate).filter_by(affiliate_code=code.upper()).first()
    if code_clash:
        code = _gen_affiliate_code(body.name)   # regenerate if collision

    affiliate = Affiliate(
        name             = body.name,
        email            = body.email,
        affiliate_code   = code.upper(),
        commission_type  = body.commission_type  or "percent",
        commission_value = body.commission_value if body.commission_value is not None else 30.0,
        payout_method    = body.payout_method    or "paypal",
        payout_details   = json.dumps(body.payout_details) if body.payout_details else None,
    )
    db.add(affiliate)
    db.commit()
    db.refresh(affiliate)
    return success(affiliate.to_dict(), "Affiliate added successfully", 201)


@router.get("/promotions/affiliates/{affiliate_id}")
def get_affiliate(
    affiliate_id: str,
    _:            None    = Depends(admin_required),
    db:           Session = Depends(get_db),
):
    """Get a single affiliate's detail and stats."""
    affiliate = db.get(Affiliate, affiliate_id)
    if not affiliate:
        raise HTTPException(status_code=404, detail="Affiliate not found")
    return success(affiliate.to_dict())


@router.patch("/promotions/affiliates/{affiliate_id}")
def update_affiliate(
    affiliate_id: str,
    body:         UpdateAffiliateBody,
    _:            None    = Depends(admin_required),
    db:           Session = Depends(get_db),
):
    """Update affiliate details (status, commission, payout method, etc.)."""
    affiliate = db.get(Affiliate, affiliate_id)
    if not affiliate:
        raise HTTPException(status_code=404, detail="Affiliate not found")

    if body.name             is not None: affiliate.name             = body.name
    if body.status           is not None: affiliate.status           = body.status
    if body.commission_type  is not None: affiliate.commission_type  = body.commission_type
    if body.commission_value is not None: affiliate.commission_value = body.commission_value
    if body.payout_method    is not None: affiliate.payout_method    = body.payout_method
    if body.payout_details   is not None: affiliate.payout_details   = json.dumps(body.payout_details)

    db.commit()
    db.refresh(affiliate)
    return success(affiliate.to_dict(), "Affiliate updated successfully")


@router.delete("/promotions/affiliates/{affiliate_id}")
def delete_affiliate(
    affiliate_id: str,
    _:            None    = Depends(admin_required),
    db:           Session = Depends(get_db),
):
    """Remove an affiliate partner."""
    affiliate = db.get(Affiliate, affiliate_id)
    if not affiliate:
        raise HTTPException(status_code=404, detail="Affiliate not found")
    db.delete(affiliate)
    db.commit()
    return success({"id": affiliate_id}, "Affiliate removed successfully")
