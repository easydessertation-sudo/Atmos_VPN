"""
Users Router — Admin User Management page
GET    /api/admin/users                        → list users (search, filter, paginate)
POST   /api/admin/users                        → create new user (Add User button)
GET    /api/admin/users/export                 → export users as CSV
GET    /api/admin/users/{id}                   → user detail (modal)
PATCH  /api/admin/users/{id}                   → edit user (Edit button)
DELETE /api/admin/users/{id}                   → delete user
POST   /api/admin/users/{id}/suspend           → suspend user
POST   /api/admin/users/{id}/unsuspend         → unsuspend user
POST   /api/admin/users/{id}/upgrade-plan      → upgrade/change plan (Upgrade Plan button)
POST   /api/admin/users/{id}/reset-password    → admin-initiated password reset (Reset PW button)
GET    /api/admin/users/{id}/sessions          → user's VPN sessions
GET    /api/admin/users/{id}/devices           → user's registered devices
"""
import csv
import io
import secrets
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse
from passlib.hash import bcrypt
from pydantic import BaseModel, EmailStr
from sqlalchemy import func
from sqlalchemy.orm import Session

from deps import admin_required, get_db, success
from models import User, VPNSession, Subscription, Device, Notification

router = APIRouter()

VALID_PLANS = ["free", "starter", "pro", "premium"]


# ─── Helpers ───────────────────────────────────────────────────────────────
def _user_spend(user_id, db: Session) -> float:
    """Total amount paid by this user across all subscriptions."""
    total = (
        db.query(func.sum(Subscription.amount_usd))
        .filter_by(user_id=str(user_id))
        .scalar() or 0.0
    )
    return round(float(total), 2)


def _user_last_active(user, db: Session):
    """Return ISO timestamp of last VPN session start, or last_seen_at."""
    last_session = (
        db.query(VPNSession)
        .filter_by(user_id=user.id)
        .order_by(VPNSession.started_at.desc())
        .first()
    )
    if last_session:
        return last_session.started_at.isoformat()
    if user.last_seen_at:
        return user.last_seen_at.isoformat()
    if user.last_login:
        return user.last_login.isoformat()
    return None


def _format_user_id(uuid_val) -> str:
    """Return a short display ID like U-10021 from UUID."""
    # Use last 5 hex chars converted to int for a stable short ID
    short = int(str(uuid_val).replace("-", "")[-5:], 16) % 100000
    return f"U-{short:05d}"


def _build_user_row(u: User, db: Session) -> dict:
    """Build the enriched user dict used in both list and detail."""
    data = u.to_dict()
    data["display_id"]      = _format_user_id(u.id)
    data["spend"]           = _user_spend(u.id, db)
    data["last_active"]     = _user_last_active(u, db)
    data["device_count"]    = db.query(Device).filter_by(user_id=str(u.id)).count()
    data["active_sessions"] = db.query(VPNSession).filter_by(user_id=u.id, is_active=True).count()
    data["total_sessions"]  = db.query(VPNSession).filter_by(user_id=u.id).count()
    # country: no GeoIP in system — placeholder, wire up GeoIP in production
    data["country"]         = None
    data["country_code"]    = None
    return data


# ─── Request Schemas ───────────────────────────────────────────────────────
class AdminUpdateUserRequest(BaseModel):
    plan:           Optional[str]  = None
    full_name:      Optional[str]  = None
    email_verified: Optional[bool] = None


class AdminCreateUserRequest(BaseModel):
    email:     EmailStr
    password:  str
    full_name: Optional[str] = ""
    plan:      Optional[str] = "free"


class AdminUpgradePlanRequest(BaseModel):
    plan: str   # free | starter | pro | premium


class AdminResetPasswordRequest(BaseModel):
    new_password: str   # admin sets a specific password, or leave blank to auto-generate


# ─── 1. List Users ────────────────────────────────────────────────────────
@router.get("/users")
def admin_list_users(
    search: Optional[str] = None,
    plan:   Optional[str] = None,
    status: Optional[str] = None,
    page:   int = 1,
    limit:  int = 20,
    _:      None    = Depends(admin_required),
    db:     Session = Depends(get_db),
):
    """
    User Management list — powers the main table.
    Filters:
      search → matches email or full_name (case-insensitive)
      plan   → free | starter | pro | premium
      status → active | inactive | suspended | past_due | cancelled
    Pagination: page + limit
    Each row includes: display_id, email, full_name, plan, spend,
                       subscription_status, device_count, last_active, country
    """
    q = db.query(User)
    if search:
        q = q.filter(
            User.email.ilike(f"%{search}%") |
            User.full_name.ilike(f"%{search}%")
        )
    if plan:
        q = q.filter_by(plan=plan)
    if status:
        q = q.filter_by(subscription_status=status)

    total      = q.count()
    total_paid = db.query(User).filter(User.plan != "free").count()
    users      = q.order_by(User.created_at.desc()).offset((page - 1) * limit).limit(limit).all()

    return success({
        "users":       [_build_user_row(u, db) for u in users],
        "total":       total,
        "total_paid":  total_paid,
        "total_free":  total - total_paid,
        "page":        page,
        "limit":       limit,
        "pages":       (total + limit - 1) // limit,
    })


# ─── 2. Create User (Add User button) ────────────────────────────────────
@router.post("/users")
def admin_create_user(
    body: AdminCreateUserRequest,
    _:    None    = Depends(admin_required),
    db:   Session = Depends(get_db),
):
    """
    Admin creates a new user account directly (no email verification required).
    Used by the '+ Add User' button.
    """
    email = body.email.strip().lower()
    if db.query(User).filter_by(email=email).first():
        raise HTTPException(status_code=409, detail="A user with this email already exists")

    if body.plan not in VALID_PLANS:
        raise HTTPException(status_code=400, detail=f"Invalid plan. Must be one of: {VALID_PLANS}")

    if len(body.password) < 8:
        raise HTTPException(status_code=400, detail="Password must be at least 8 characters")

    user = User(
        email=email,
        password_hash=bcrypt.hash(body.password),
        full_name=body.full_name,
        plan=body.plan,
        email_verified=True,   # admin-created accounts skip verification
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return success(_build_user_row(user, db), "User created successfully", status_code=201)


# ─── 3. Export Users CSV ──────────────────────────────────────────────────
@router.get("/users/export")
def admin_export_users(
    plan:   Optional[str] = None,
    status: Optional[str] = None,
    _:      None    = Depends(admin_required),
    db:     Session = Depends(get_db),
):
    """
    Export filtered users as CSV. Triggered by the 'CSV' button.
    Returns a downloadable CSV file with key user fields.
    """
    q = db.query(User)
    if plan:
        q = q.filter_by(plan=plan)
    if status:
        q = q.filter_by(subscription_status=status)

    users = q.order_by(User.created_at.desc()).all()

    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow([
        "ID", "Display ID", "Email", "Full Name", "Plan",
        "Status", "Email Verified", "Bandwidth Used (GB)",
        "Joined", "Last Login", "Total Spend (USD)"
    ])
    for u in users:
        spend = _user_spend(u.id, db)
        writer.writerow([
            str(u.id),
            _format_user_id(u.id),
            u.email,
            u.full_name or "",
            u.plan,
            u.subscription_status or "inactive",
            u.email_verified,
            round((u.bandwidth_used_bytes or 0) / 1_073_741_824, 3),
            u.created_at.strftime("%Y-%m-%d") if u.created_at else "",
            u.last_login.strftime("%Y-%m-%d") if u.last_login else "",
            spend,
        ])

    output.seek(0)
    filename = f"users_export_{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}.csv"
    return StreamingResponse(
        iter([output.getvalue()]),
        media_type="text/csv",
        headers={"Content-Disposition": f"attachment; filename={filename}"},
    )


# ─── 4. User Detail (modal) ───────────────────────────────────────────────
@router.get("/users/{user_id}")
def admin_user_detail(
    user_id: str,
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """
    Full user detail — powers the 'User Details' modal.
    Returns everything needed for the modal + action buttons:
      display_id, name, email, country, joined, last_active,
      devices count, spend, plan, subscription_status,
      recent sessions, subscriptions, devices list, notifications.
    """
    user = db.get(User, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    sessions = (
        db.query(VPNSession)
        .filter_by(user_id=user.id)
        .order_by(VPNSession.started_at.desc())
        .limit(10).all()
    )
    subs    = db.query(Subscription).filter_by(user_id=str(user.id)).all()
    devices = db.query(Device).filter_by(user_id=str(user.id)).all()

    base = _build_user_row(user, db)

    return success({
        # Core user fields (for modal display)
        "id":                   str(user.id),
        "display_id":           base["display_id"],
        "full_name":            user.full_name,
        "email":                user.email,
        "plan":                 user.plan,
        "subscription_status":  user.subscription_status or "inactive",
        "email_verified":       user.email_verified,
        "country":              base["country"],
        "country_code":         base["country_code"],
        "joined":               user.created_at.strftime("%Y-%m-%d") if user.created_at else None,
        "last_active":          base["last_active"],
        "device_count":         base["device_count"],
        "spend":                base["spend"],
        "bandwidth_used_bytes": user.bandwidth_used_bytes,
        "bandwidth_used_gb":    round((user.bandwidth_used_bytes or 0) / 1_073_741_824, 3),
        "bandwidth_limit_bytes": user.bandwidth_limit_bytes,
        "two_fa_enabled":       user.two_fa_enabled,
        "active_sessions":      base["active_sessions"],
        "total_sessions":       base["total_sessions"],
        # Related data
        "sessions":      [s.to_dict() for s in sessions],
        "subscriptions": [s.to_dict() for s in subs],
        "devices":       [d.to_dict() for d in devices],
    })


# ─── 5. Edit User ─────────────────────────────────────────────────────────
@router.patch("/users/{user_id}")
def admin_update_user(
    user_id: str,
    body:    AdminUpdateUserRequest,
    _:       None    = Depends(admin_required),
    db:      Session = Depends(get_db),
):
    """
    Edit user — triggered by 'Edit' button in modal.
    Can update: full_name, plan, email_verified.
    """
    user = db.get(User, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    if body.plan is not None:
        if body.plan not in VALID_PLANS:
            raise HTTPException(status_code=400, detail=f"Invalid plan. Must be one of: {VALID_PLANS}")
        user.plan = body.plan

    if body.full_name is not None:
        user.full_name = body.full_name

    if body.email_verified is not None:
        user.email_verified = body.email_verified

    db.commit()
    db.refresh(user)
    return success(_build_user_row(user, db), "User updated successfully")


# ─── 6. Delete User ───────────────────────────────────────────────────────
@router.delete("/users/{user_id}")
def admin_delete_user(
    user_id: str,
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """
    Permanently delete a user and all their data.
    Triggered by 'Delete' button in modal.
    """
    user = db.get(User, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    email = user.email
    db.delete(user)
    db.commit()
    return success(msg=f"User {email} permanently deleted")


# ─── 7. Suspend User ──────────────────────────────────────────────────────
@router.post("/users/{user_id}/suspend")
def admin_suspend_user(
    user_id: str,
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """
    Suspend a user — triggered by 'Suspend' button in modal.
    Terminates all active VPN sessions and locks the account.
    """
    user = db.get(User, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    if user.subscription_status == "suspended":
        raise HTTPException(status_code=409, detail="User is already suspended")

    revoked = db.query(VPNSession).filter_by(user_id=user.id, is_active=True).update({
        "is_active": False,
        "ended_at":  datetime.utcnow(),
    })
    user.subscription_status = "suspended"
    db.commit()

    return success(
        {"revoked_sessions": revoked, "user": _build_user_row(user, db)},
        f"User {user.email} suspended. {revoked} active session(s) terminated.",
    )


# ─── 8. Unsuspend User ────────────────────────────────────────────────────
@router.post("/users/{user_id}/unsuspend")
def admin_unsuspend_user(
    user_id: str,
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """Restore a suspended user back to active status."""
    user = db.get(User, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    if user.subscription_status != "suspended":
        raise HTTPException(status_code=409, detail="User is not currently suspended")

    user.subscription_status = "inactive"
    db.commit()
    return success(_build_user_row(user, db), f"User {user.email} unsuspended successfully")


# ─── 9. Upgrade / Change Plan ─────────────────────────────────────────────
@router.post("/users/{user_id}/upgrade-plan")
def admin_upgrade_plan(
    user_id: str,
    body:    AdminUpgradePlanRequest,
    _:       None    = Depends(admin_required),
    db:      Session = Depends(get_db),
):
    """
    Change a user's plan — triggered by 'Upgrade Plan' button in modal.
    Accepts: free | starter | pro | premium
    """
    user = db.get(User, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    if body.plan not in VALID_PLANS:
        raise HTTPException(status_code=400, detail=f"Invalid plan. Must be one of: {VALID_PLANS}")

    old_plan = user.plan
    user.plan = body.plan

    # If upgrading to a paid plan, mark subscription as active
    if body.plan != "free":
        user.subscription_status = "active"
    else:
        user.subscription_status = "inactive"

    db.commit()
    db.refresh(user)
    return success(
        _build_user_row(user, db),
        f"Plan changed from {old_plan} → {body.plan}",
    )


# ─── 10. Reset Password (Admin) ───────────────────────────────────────────
@router.post("/users/{user_id}/reset-password")
def admin_reset_password(
    user_id: str,
    body:    AdminResetPasswordRequest,
    _:       None    = Depends(admin_required),
    db:      Session = Depends(get_db),
):
    """
    Admin-initiated password reset — triggered by 'Reset PW' button in modal.
    If new_password is provided, sets it directly.
    If new_password is empty, auto-generates a secure 12-char temp password
    and returns it in the response (admin can share with user).
    """
    user = db.get(User, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    if body.new_password and len(body.new_password) >= 8:
        new_pw = body.new_password
    else:
        # Auto-generate a secure temp password
        new_pw = secrets.token_urlsafe(12)

    user.password_hash = bcrypt.hash(new_pw)
    db.commit()

    return success(
        {
            "email":        user.email,
            "new_password": new_pw,   # Show to admin so they can share with user
            "note":         "Share this password with the user securely. They should change it on login.",
        },
        "Password reset successfully",
    )


# ─── 11. User's Sessions ──────────────────────────────────────────────────
@router.get("/users/{user_id}/sessions")
def admin_user_sessions(
    user_id:     str,
    active_only: bool = False,
    page:        int  = 1,
    limit:       int  = 20,
    _:           None    = Depends(admin_required),
    db:          Session = Depends(get_db),
):
    """List all VPN sessions for a specific user with pagination."""
    user = db.get(User, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    q = db.query(VPNSession).filter_by(user_id=user.id)
    if active_only:
        q = q.filter_by(is_active=True)

    total    = q.count()
    sessions = q.order_by(VPNSession.started_at.desc()).offset((page - 1) * limit).limit(limit).all()
    return success({
        "sessions": [s.to_dict() for s in sessions],
        "total":    total,
        "page":     page,
        "limit":    limit,
        "pages":    (total + limit - 1) // limit,
    })


# ─── 12. User's Devices ───────────────────────────────────────────────────
@router.get("/users/{user_id}/devices")
def admin_user_devices(
    user_id: str,
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """List all registered devices for a specific user."""
    user = db.get(User, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    devices = db.query(Device).filter_by(user_id=str(user.id)).all()
    return success([d.to_dict() for d in devices])
