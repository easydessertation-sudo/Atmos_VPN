"""
Admin Auth Router
POST /api/admin/login  → validate password, return admin token
"""
import os
from datetime import datetime, timedelta
import jwt
from passlib.context import CryptContext

from dotenv import load_dotenv
from fastapi import APIRouter, HTTPException, Request, Depends
from pydantic import BaseModel
from sqlalchemy.orm import Session
from slowapi import Limiter
from slowapi.util import get_remote_address

from deps import success, get_db, JWT_SECRET, JWT_ALGORITHM
from models import AdminUser

load_dotenv()

router  = APIRouter()
limiter = Limiter(key_func=get_remote_address)

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

class AdminLoginRequest(BaseModel):
    email: str
    password: str

class SuperAdminSetupRequest(BaseModel):
    name: str
    email: str
    password: str

@router.post("/setup-super-admin")
def setup_super_admin(body: SuperAdminSetupRequest, db: Session = Depends(get_db)):
    """
    One-time setup to create the first Super Admin.
    Fails if any Super Admin already exists.
    """
    existing_super = db.query(AdminUser).filter(AdminUser.role == "Super Admin").first()
    if existing_super:
        raise HTTPException(status_code=400, detail="A Super Admin already exists. Please use the Admin Team dashboard to add more users.")
    
    # bcrypt has a hard 72-byte limit — truncate to prevent ValueError on stricter bcrypt versions
    safe_password = body.password.encode("utf-8")[:72].decode("utf-8", errors="ignore")
    hashed_password = pwd_context.hash(safe_password)
    new_admin = AdminUser(
        name=body.name,
        email=body.email,
        password_hash=hashed_password,
        role="Super Admin",
        status="Active"
    )
    db.add(new_admin)
    db.commit()
    db.refresh(new_admin)
    
    return success(new_admin.to_dict(), "Super Admin created successfully. You can now login.")

@router.post("/login")
@limiter.limit("10/minute")
def admin_login(request: Request, body: AdminLoginRequest, db: Session = Depends(get_db)):
    """
    Admin login using email and password.
    Returns a JWT token to be used in the X-Admin-Token header.
    """
    admin_user = db.query(AdminUser).filter(AdminUser.email == body.email).first()
    
    # bcrypt has a hard 72-byte limit — truncate to prevent ValueError on stricter bcrypt versions
    safe_password = body.password.encode("utf-8")[:72].decode("utf-8", errors="ignore")
    
    if not admin_user or not pwd_context.verify(safe_password, admin_user.password_hash):
        raise HTTPException(status_code=401, detail="Invalid email or password")
        
    if admin_user.status != "Active":
        raise HTTPException(status_code=403, detail="Account is disabled")

    # Update last login
    admin_user.last_login = datetime.utcnow()
    db.commit()

    # Generate JWT
    payload = {
        "sub": str(admin_user.id),
        "email": admin_user.email,
        "role": admin_user.role,
        "exp": datetime.utcnow() + timedelta(hours=12) # Token valid for 12 hours
    }
    token = jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)

    return success(
        {
            "admin_token": token,
            "user": admin_user.to_dict()
        },
        "Admin login successful",
    )

@router.post("/logout")
def admin_logout():
    """
    Admin logout placeholder.
    Token-based admin auth is stateless — client should discard the token.
    """
    return success(msg="Logged out. Please discard your admin token.")
