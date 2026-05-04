from datetime import datetime, timedelta
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import Optional, List

from passlib.context import CryptContext

from deps import admin_required, get_db, success, RoleChecker
from models import AdminUser

router = APIRouter()
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

class AdminUserCreate(BaseModel):
    name: str
    email: str
    password: Optional[str] = None
    role: str
    two_fa_enabled: bool = False

@router.get("/overview")
def get_admin_team_overview(
    _: None = Depends(admin_required),
    db: Session = Depends(get_db)
):
    """
    Get everything needed for the Admin Team page (KPIs, Users, and Permissions Matrix).
    """
    
    admins = db.query(AdminUser).order_by(AdminUser.created_at.asc()).all()
    
    total_admins = len(admins)
    super_admins = sum(1 for a in admins if a.role == "Super Admin")
    two_fa_count = sum(1 for a in admins if a.two_fa_enabled)
    
    # Active sessions can just be mocked based on total_admins minus 1 for design accuracy 
    active_sessions = total_admins - 1 if total_admins > 0 else 0

    # Role Permissions Matrix (Static configuration)
    matrix = [
        {"permission": "User Management",   "super_admin": True, "operations": True,  "billing": False, "content": False},
        {"permission": "Server Management", "super_admin": True, "operations": True,  "billing": False, "content": False},
        {"permission": "Billing & Refunds", "super_admin": True, "operations": False, "billing": True,  "content": False},
        {"permission": "Coupons",           "super_admin": True, "operations": False, "billing": True,  "content": False},
        {"permission": "Blog & Content",    "super_admin": True, "operations": False, "billing": False, "content": True},
        {"permission": "Support Tickets",   "super_admin": True, "operations": True,  "billing": True,  "content": False},
        {"permission": "Push Notifications","super_admin": True, "operations": False, "billing": False, "content": True},
        {"permission": "Email Campaigns",   "super_admin": True, "operations": False, "billing": False, "content": True},
        {"permission": "Admin Team Mgmt",   "super_admin": True, "operations": False, "billing": False, "content": False},
        {"permission": "Audit Log",         "super_admin": True, "operations": True,  "billing": False, "content": False},
        {"permission": "Settings",          "super_admin": True, "operations": False, "billing": False, "content": False},
    ]

    return success({
        "kpis": {
            "total_admins": total_admins,
            "super_admins": super_admins,
            "active_sessions": active_sessions,
            "two_fa_enabled_label": f"{two_fa_count}/{total_admins}"
        },
        "users": [a.to_dict() for a in admins],
        "permissions_matrix": matrix
    })

@router.post("/members")
def add_admin_user(
    payload: AdminUserCreate,
    current_admin = Depends(RoleChecker(["Super Admin"])),
    db: Session = Depends(get_db)
):
    """Add a new admin user (Super Admin only)."""
    import secrets
    from deps import log_admin_action
    
    # Check if email exists
    existing = db.query(AdminUser).filter(AdminUser.email == payload.email).first()
    if existing:
        raise HTTPException(status_code=400, detail="An admin with this email already exists.")
        
    # Auto-generate a secure password if none provided
    raw_password = payload.password if payload.password else secrets.token_urlsafe(12)
    hashed_password = pwd_context.hash(raw_password)
    
    admin_user = AdminUser(
        name=payload.name,
        email=payload.email,
        password_hash=hashed_password,
        role=payload.role,
        two_fa_enabled=payload.two_fa_enabled,
        status="Active"
    )
    db.add(admin_user)
    db.commit()
    db.refresh(admin_user)
    
    # Write to Audit Log
    log_admin_action(
        db=db,
        admin_email=current_admin.email,
        action=f"Created new admin user: {payload.email} ({payload.role})"
    )
    
    result = admin_user.to_dict()
    if not payload.password:
        result["generated_password"] = raw_password
        
    return success(result)

@router.delete("/members/{admin_id}")
def delete_admin_user(
    admin_id: str,
    current_admin = Depends(RoleChecker(["Super Admin"])),
    db: Session = Depends(get_db)
):
    """Remove an admin user (Super Admin only)."""
    from deps import log_admin_action
    
    admin_user = db.query(AdminUser).filter(AdminUser.id == admin_id).first()
    if not admin_user:
        raise HTTPException(status_code=404, detail="Admin user not found")
        
    deleted_email = admin_user.email
    db.delete(admin_user)
    db.commit()
    
    # Write to Audit Log
    log_admin_action(
        db=db,
        admin_email=current_admin.email,
        action=f"Deleted admin user: {deleted_email}"
    )
    
    return success({"message": "Admin user deleted successfully"})
