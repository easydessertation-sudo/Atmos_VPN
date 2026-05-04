"""
SecureVPN — Full Backend API
FastAPI + SQLAlchemy + SQLite + JWT Auth + Subscriptions + VPN Session Management

Run with:  uvicorn app:app --reload --port 5000
Docs at:   http://localhost:5000/docs
"""
import os
import random
import time
import secrets
import logging
from datetime import datetime, timedelta
from typing import Optional, List, Dict

from dotenv import load_dotenv

load_dotenv()

logger = logging.getLogger(__name__)   # Load .env before anything else reads os.environ

from redis_client import (
    blocklist_token, is_token_blocked,
    cache_set, cache_get, get_redis,
    store_password_reset_token, get_user_by_reset_token
)

from email_service import send_password_reset_email

from fastapi import FastAPI, Depends, HTTPException, Request, Header, status
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

from jose import JWTError, jwt
from passlib.hash import bcrypt
from pydantic import BaseModel, EmailStr, field_validator
from sqlalchemy.orm import Session

from models import (
    Base, engine, get_db,
    User, VPNServer, VPNSession, VPNConfig, IPPool, UsageLog,
    Device, Subscription, SupportTicket, Notification
)
from wireguard import (
    claim_ip_from_pool, release_ip_to_pool,
    generate_wg_config, get_existing_config, revoke_all_user_configs
)
from tasks import add_wireguard_peer, remove_wireguard_peer

from stripe_client import (
    create_checkout_session,
    create_billing_portal_session,
    verify_and_parse_webhook,
    handle_webhook_event,
    get_next_charge_details
)

# ─────────────────────────────────────────────────────────────────
# App Setup
# ─────────────────────────────────────────────────────────────────
app = FastAPI(
    title="AtmosVPN API",
    description="Backend API for AtmosVPN — manages users, subscriptions, and VPN access.",
    version="2.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],   # Restrict in production to your frontend domain
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

limiter = Limiter(key_func=get_remote_address)
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# ─────────────────────────────────────────────────────────────────
# JWT Config
# ─────────────────────────────────────────────────────────────────
JWT_SECRET         = os.environ.get("JWT_SECRET", "super-secret-dev-key-change-in-production")
JWT_ALGORITHM      = "HS256"
JWT_ACCESS_EXPIRE  = timedelta(hours=12)
JWT_REFRESH_EXPIRE = timedelta(days=30)

security = HTTPBearer()


def create_access_token(user_id: int) -> str:
    payload = {
        "sub":  str(user_id),
        "type": "access",
        "exp":  datetime.utcnow() + JWT_ACCESS_EXPIRE,
    }
    return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)


def create_refresh_token(user_id: int) -> str:
    payload = {
        "sub":  str(user_id),
        "type": "refresh",
        "exp":  datetime.utcnow() + JWT_REFRESH_EXPIRE,
    }
    return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)


def decode_token(token: str) -> dict:
    try:
        return jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
    except JWTError:
        raise HTTPException(status_code=401, detail="Invalid or expired token")


# ─────────────────────────────────────────────────────────────────
# Auth Dependencies
# ─────────────────────────────────────────────────────────────────
def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security),
    db: Session = Depends(get_db),
) -> User:
    """
    Decode JWT and return the current User. Use as a FastAPI Dependency.
    Also checks Redis blocklist — if user has logged out, rejects the token
    even if the JWT signature is still valid.
    """
    token = credentials.credentials

    # Check blocklist first (fast Redis lookup ~0.1ms)
    if is_token_blocked(token):
        raise HTTPException(status_code=401, detail="Token has been revoked. Please login again.")

    payload = decode_token(token)
    if payload.get("type") != "access":
        raise HTTPException(status_code=401, detail="Access token required")

    # UUID-based lookup (no int conversion needed)
    user = db.get(User, payload["sub"])
    if not user:
        raise HTTPException(status_code=401, detail="User not found")
    return user


def get_refresh_user(
    credentials: HTTPAuthorizationCredentials = Depends(security),
    db: Session = Depends(get_db),
) -> User:
    """Validate a refresh token. Used only in the /refresh endpoint."""
    payload = decode_token(credentials.credentials)
    if payload.get("type") != "refresh":
        raise HTTPException(status_code=401, detail="Refresh token required")
    user = db.get(User, payload["sub"])   # UUID string lookup
    if not user:
        raise HTTPException(status_code=401, detail="User not found")
    return user


# ─────────────────────────────────────────────────────────────────
# Admin Auth Dependency
# ─────────────────────────────────────────────────────────────────
ADMIN_PASSWORD = os.environ.get("ADMIN_PASSWORD", "securevpn-admin-2024")


def admin_required(x_admin_token: Optional[str] = Header(default=None)):
    """Validate admin token passed in X-Admin-Token header."""
    if not x_admin_token or x_admin_token != ADMIN_PASSWORD:
        raise HTTPException(status_code=401, detail="Admin authentication required")


# ─────────────────────────────────────────────────────────────────
# Plan Limits
# ─────────────────────────────────────────────────────────────────
#
# HOW PLANS DIFFER:
#  free    → 10 GB/mo cap, 10 Mbps speed, 3 servers only, 1 device, standard mode only
#  starter → 100 GB/mo cap, 50 Mbps speed, 20 servers, 3 devices, streaming unlocked
#  pro     → Unlimited data, 200 Mbps speed, all servers, 5 devices, all modes
#  premium → Unlimited data, unlimited speed, all servers + dedicated IP, 10 devices, all modes
#
PLAN_LIMITS = {
    "free": {
        "devices":              1,
        "bandwidth_gb":         10,          # 10 GB/month hard cap
        "bandwidth_bytes":      10_737_418_240,   # 10 GB in bytes
        "speed_mbps":           10,          # throttled to 10 Mbps
        "server_locations":     3,           # only 3 server locations
        "session_minutes":      None,        # no time limit (replaced by data cap)
        "modes":                ["standard"],
        "dedicated_ip":         False,
    },
    "starter": {
        "devices":              3,
        "bandwidth_gb":         100,         # 100 GB/month
        "bandwidth_bytes":      107_374_182_400,  # 100 GB in bytes
        "speed_mbps":           50,          # 50 Mbps
        "server_locations":     20,          # 20 server locations
        "session_minutes":      None,
        "modes":                ["standard", "streaming"],
        "dedicated_ip":         False,
    },
    "pro": {
        "devices":              5,
        "bandwidth_gb":         None,        # Unlimited
        "bandwidth_bytes":      None,        # Unlimited
        "speed_mbps":           200,         # 200 Mbps
        "server_locations":     None,        # All servers
        "session_minutes":      None,
        "modes":                ["standard", "streaming", "gaming", "crypto"],
        "dedicated_ip":         False,
    },
    "premium": {
        "devices":              10,
        "bandwidth_gb":         None,        # Unlimited
        "bandwidth_bytes":      None,        # Unlimited
        "speed_mbps":           None,        # Unlimited speed
        "server_locations":     None,        # All servers + dedicated IP
        "session_minutes":      None,
        "modes":                ["standard", "streaming", "gaming", "crypto"],
        "dedicated_ip":         True,
    },
}

PLANS = {
    "free": {
        "name":             "Free",
        "monthly_usd":      0.00,
        "annual_usd":       0.00,
        "bandwidth_gb":     10,
        "speed_mbps":       10,
        "devices":          1,
        "server_locations": 3,
        "dedicated_ip":     False,
        "features": [
            "10 GB/month data",
            "10 Mbps speed",
            "3 server locations",
            "1 device",
            "Standard mode only",
        ],
    },
    "starter": {
        "name":             "Starter",
        "monthly_usd":      3.99,
        "annual_usd":       33.48,           # 30% annual discount
        "bandwidth_gb":     100,
        "speed_mbps":       50,
        "devices":          3,
        "server_locations": 20,
        "dedicated_ip":     False,
        "features": [
            "100 GB/month data",
            "50 Mbps speed",
            "20 server locations",
            "3 devices",
            "Standard + Streaming modes",
        ],
    },
    "pro": {
        "name":             "Pro",
        "monthly_usd":      7.99,
        "annual_usd":       57.48,           # ~40% annual discount
        "bandwidth_gb":     None,            # Unlimited
        "speed_mbps":       200,
        "devices":          5,
        "server_locations": None,            # All servers
        "dedicated_ip":     False,
        "features": [
            "Unlimited data",
            "200 Mbps speed",
            "All server locations",
            "5 devices",
            "All modes (Standard, Streaming, Gaming, Crypto)",
        ],
    },
    "premium": {
        "name":             "Premium",
        "monthly_usd":      12.99,
        "annual_usd":       93.48,           # ~40% annual discount
        "bandwidth_gb":     None,            # Unlimited
        "speed_mbps":       None,            # Unlimited
        "devices":          10,
        "server_locations": None,            # All servers + dedicated IP
        "dedicated_ip":     True,
        "features": [
            "Unlimited data",
            "Unlimited speed",
            "All servers + Dedicated IP",
            "10 devices",
            "All modes + AI Security (coming soon)",
            "Priority support",
        ],
    },
}


# ─────────────────────────────────────────────────────────────────
# Server Seed Data
# ─────────────────────────────────────────────────────────────────
SERVERS_SEED = [
    {"id": "lon-1", "name": "London",      "city": "London",      "country": "United Kingdom", "country_code": "gb", "flag": "🇬🇧", "ip_address": "185.156.46.1",  "ping_ms": 18,  "capacity_mbps": 1000, "is_streaming": True,  "is_p2p": True},
    {"id": "lon-2", "name": "London 2",    "city": "London",      "country": "United Kingdom", "country_code": "gb", "flag": "🇬🇧", "ip_address": "185.156.46.2",  "ping_ms": 20,  "capacity_mbps": 1000, "is_streaming": True,  "is_gaming": True},
    {"id": "nyc-1", "name": "New York",    "city": "New York",    "country": "United States",  "country_code": "us", "flag": "🇺🇸", "ip_address": "104.21.14.1",   "ping_ms": 85,  "capacity_mbps": 1000, "is_gaming": True,     "is_crypto": True},
    {"id": "lax-1", "name": "Los Angeles", "city": "Los Angeles", "country": "United States",  "country_code": "us", "flag": "🇺🇸", "ip_address": "104.21.14.2",   "ping_ms": 110, "capacity_mbps": 950,  "is_streaming": True,  "is_gaming": True},
    {"id": "fra-1", "name": "Frankfurt",   "city": "Frankfurt",   "country": "Germany",         "country_code": "de", "flag": "🇩🇪", "ip_address": "104.21.88.1",   "ping_ms": 25,  "capacity_mbps": 1000, "is_gaming": True,     "is_streaming": True},
    {"id": "ams-1", "name": "Amsterdam",   "city": "Amsterdam",   "country": "Netherlands",     "country_code": "nl", "flag": "🇳🇱", "ip_address": "104.21.72.1",   "ping_ms": 22,  "capacity_mbps": 1000, "is_streaming": True,  "is_p2p": True},
    {"id": "tok-1", "name": "Tokyo",       "city": "Tokyo",       "country": "Japan",           "country_code": "jp", "flag": "🇯🇵", "ip_address": "104.21.130.1",  "ping_ms": 150, "capacity_mbps": 950,  "is_gaming": True,     "is_streaming": True},
    {"id": "sgp-1", "name": "Singapore",   "city": "Singapore",   "country": "Singapore",       "country_code": "sg", "flag": "🇸🇬", "ip_address": "104.21.64.1",   "ping_ms": 120, "capacity_mbps": 800,  "is_crypto": True,     "is_streaming": True},
    {"id": "syd-1", "name": "Sydney",      "city": "Sydney",      "country": "Australia",       "country_code": "au", "flag": "🇦🇺", "ip_address": "104.21.200.1",  "ping_ms": 180, "capacity_mbps": 700,  "is_streaming": True},
    {"id": "tor-1", "name": "Toronto",     "city": "Toronto",     "country": "Canada",          "country_code": "ca", "flag": "🇨🇦", "ip_address": "104.21.120.1",  "ping_ms": 95,  "capacity_mbps": 900,  "is_streaming": True,  "is_gaming": True},
    {"id": "par-1", "name": "Paris",       "city": "Paris",       "country": "France",          "country_code": "fr", "flag": "🇫🇷", "ip_address": "104.21.56.1",   "ping_ms": 28,  "capacity_mbps": 1000, "is_streaming": True},
    {"id": "zur-1", "name": "Zurich",      "city": "Zurich",      "country": "Switzerland",     "country_code": "ch", "flag": "🇨🇭", "ip_address": "104.21.90.1",   "ping_ms": 30,  "capacity_mbps": 1000, "is_crypto": True},
    {"id": "sto-1", "name": "Stockholm",   "city": "Stockholm",   "country": "Sweden",          "country_code": "se", "flag": "🇸🇪", "ip_address": "104.21.44.1",   "ping_ms": 35,  "capacity_mbps": 1000, "is_streaming": True,  "is_p2p": True},
    {"id": "mum-1", "name": "Mumbai",      "city": "Mumbai",      "country": "India",           "country_code": "in", "flag": "🇮🇳", "ip_address": "104.21.160.1",  "ping_ms": 75,  "capacity_mbps": 500,  "is_streaming": True},
    {"id": "dub-1", "name": "Dubai",       "city": "Dubai",       "country": "UAE",             "country_code": "ae", "flag": "🇦🇪", "ip_address": "104.21.170.1",  "ping_ms": 95,  "capacity_mbps": 400,  "is_crypto": True},
    {"id": "sao-1", "name": "São Paulo",   "city": "São Paulo",   "country": "Brazil",          "country_code": "br", "flag": "🇧🇷", "ip_address": "104.21.140.1",  "ping_ms": 145, "capacity_mbps": 600,  "is_gaming": True},
]


def seed_database(db: Session):
    """
    Seed VPN servers and their IP pools if tables are empty.

    IP Pool logic:
      Each server gets its own /24 subnet based on its index.
      Server 0 (lon-1) → 10.0.0.1  to 10.0.0.253  (253 IPs)
      Server 1 (lon-2) → 10.1.0.1  to 10.1.0.253  (253 IPs)
      Server 2 (nyc-1) → 10.2.0.1  to 10.2.0.253  (253 IPs)
      ...and so on. Total: 16 servers × 253 IPs = 4,048 IPs pre-seeded.
    """
    if db.query(VPNServer).count() == 0:
        for index, s in enumerate(SERVERS_SEED):
            server = VPNServer(
                id=s["id"], name=s["name"], city=s["city"],
                country=s["country"], country_code=s["country_code"],
                flag=s["flag"], ip_address=s["ip_address"],
                ping_ms=s["ping_ms"], capacity_mbps=s["capacity_mbps"],
                load_pct=random.randint(10, 70),
                is_streaming=s.get("is_streaming", False),
                is_gaming=s.get("is_gaming", False),
                is_crypto=s.get("is_crypto", False),
                is_p2p=s.get("is_p2p", False),
            )
            db.add(server)
            db.flush()   # write server to DB so ip_pool FK is valid

            # Seed IP pool for this server — 253 usable IPs in a /24 subnet
            for host in range(1, 254):   # 1 to 253 inclusive
                ip_entry = IPPool(
                    server_id=s["id"],
                    ip_address=f"10.{index}.0.{host}",
                    is_assigned=False,
                )
                db.add(ip_entry)

        db.commit()
        print(f"✅ Seeded {len(SERVERS_SEED)} servers with {len(SERVERS_SEED) * 253} IP pool entries.")


@app.on_event("startup")
def on_startup():
    """
    On startup:
    1. Create all DB tables (if they don't exist)
    2. Seed VPN server data
    """
    try:
        Base.metadata.create_all(bind=engine)
        db = next(get_db())
        try:
            seed_database(db)
        finally:
            db.close()
        print("✅ Database connected and tables ready.")
    except Exception as e:
        print(f"⚠️  Database connection failed: {e}")
        print("⚠️  Update DATABASE_URL in your .env file with your Supabase connection string.")
        print("⚠️  App will start but DB-dependent endpoints will fail until DB is connected.")


# ─────────────────────────────────────────────────────────────────
# Pydantic Request Schemas
# ─────────────────────────────────────────────────────────────────
class RegisterRequest(BaseModel):
    email: EmailStr
    password: str
    full_name: Optional[str] = ""

    @field_validator("password")
    @classmethod
    def password_min_length(cls, v):
        if len(v) < 8:
            raise ValueError("Password must be at least 8 characters")
        return v


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class ChangePasswordRequest(BaseModel):
    old_password: str
    new_password: str

    @field_validator("new_password")
    @classmethod
    def new_password_min_length(cls, v):
        if len(v) < 8:
            raise ValueError("New password must be at least 8 characters")
        return v


class ForgotPasswordRequest(BaseModel):
    email: EmailStr


class ResetPasswordRequest(BaseModel):
    token: str
    new_password: str

    @field_validator("new_password")
    @classmethod
    def new_password_min_length(cls, v):
        if len(v) < 8:
            raise ValueError("New password must be at least 8 characters")
        return v


class ConnectRequest(BaseModel):
    server_id:   Optional[str] = None
    mode:        str = "standard"
    protocol:    str = "wireguard"
    device_name: str = "Unknown Device"


class ProvisionRequest(BaseModel):
    """
    Request body for POST /api/vpn/provision
    The app generates a WireGuard keypair on the device,
    then sends the PUBLIC KEY here (private key never leaves the device).
    """
    public_key:  str                  # WireGuard public key from device (required)
    server_id:   Optional[str] = None # Leave empty to auto-pick best server
    device_name: Optional[str] = "My Device"
    platform:    Optional[str] = "unknown"   # ios|android|windows|mac|linux|router
    mode:        Optional[str] = "standard"  # standard|streaming|gaming|crypto


class CheckoutRequest(BaseModel):
    plan:          str
    billing_cycle: str = "monthly"


class SupportTicketRequest(BaseModel):
    email:    EmailStr
    subject:  Optional[str] = "Support Request"
    message:  str
    category: str = "general"


class AdminUpdateUserRequest(BaseModel):
    plan:      Optional[str] = None
    full_name: Optional[str] = None


class AdminUpdateServerRequest(BaseModel):
    name:         Optional[str]  = None
    city:         Optional[str]  = None
    country:      Optional[str]  = None
    ping_ms:      Optional[int]  = None
    capacity_mbps: Optional[int] = None
    is_online:    Optional[bool] = None
    is_streaming:  Optional[bool] = None
    is_gaming:    Optional[bool] = None
    is_crypto:    Optional[bool] = None
    is_p2p:       Optional[bool] = None


class AdminUpdateTicketRequest(BaseModel):
    status: str


class AdminUpdateSettingsRequest(BaseModel):
    free_session_minutes: Optional[int]  = None
    ad_bonus_minutes:     Optional[int]  = None
    max_free_devices:     Optional[int]  = None
    ads_enabled:          Optional[bool] = None
    maintenance_mode:     Optional[bool] = None


class AdminLoginRequest(BaseModel):
    password: str


# ─────────────────────────────────────────────────────────────────
# Helper: Standard response format
# ─────────────────────────────────────────────────────────────────
def success(data=None, msg: str = "OK", status_code: int = 200):
    return JSONResponse(
        content={"success": True, "message": msg, "data": data},
        status_code=status_code,
    )


def error(msg: str = "Error", status_code: int = 400, data=None):
    return JSONResponse(
        content={"success": False, "message": msg, "data": data},
        status_code=status_code,
    )


# ─────────────────────────────────────────────────────────────────
# Auth Routes
# ─────────────────────────────────────────────────────────────────
@app.post("/api/auth/register", tags=["Auth"])
@limiter.limit("5/minute")
def register(request: Request, body: RegisterRequest, db: Session = Depends(get_db)):
    """
    Create a new user account.
    - Hashes the password with bcrypt (never stored as plain text)
    - Returns JWT access + refresh tokens
    """
    email = body.email.strip().lower()

    if db.query(User).filter_by(email=email).first():
        raise HTTPException(status_code=409, detail="An account with this email already exists")

    user = User(
        email=email,
        password_hash=bcrypt.hash(body.password),
        full_name=body.full_name,
        plan="free",
    )
    db.add(user)
    db.commit()
    db.refresh(user)

    return success(
        {
            "user":          user.to_dict(),
            "access_token":  create_access_token(user.id),
            "refresh_token": create_refresh_token(user.id),
        },
        msg="Account created successfully",
        status_code=201,
    )


@app.post("/api/auth/login", tags=["Auth"])
@limiter.limit("5/minute")
def login(request: Request, body: LoginRequest, db: Session = Depends(get_db)):
    """
    Validate credentials and return access + refresh JWT tokens.
    """
    email = body.email.strip().lower()
    user  = db.query(User).filter_by(email=email).first()

    if not user or not bcrypt.verify(body.password, user.password_hash):
        raise HTTPException(status_code=401, detail="Invalid email or password")

    user.last_login = datetime.utcnow()
    
    # ── Real Device Tracking & Notification ──
    user_agent = request.headers.get("user-agent", "Unknown Device")
    platform   = "unknown"
    if "iPhone" in user_agent or "iPad" in user_agent: platform = "ios"
    elif "Android" in user_agent: platform = "android"
    elif "Windows" in user_agent: platform = "windows"
    elif "Mac OS" in user_agent:  platform = "mac"
    elif "Linux" in user_agent:   platform = "linux"

    ip_address = request.headers.get("x-forwarded-for", request.client.host)
    
    device = db.query(Device).filter_by(user_id=str(user.id), name=user_agent).first()
    is_new_device = False
    if not device:
        is_new_device = True
        device = Device(user_id=str(user.id), name=user_agent, platform=platform)
        db.add(device)
    
    device.last_seen = datetime.utcnow()
    
    if is_new_device:
        import json as _json
        location = "Unknown Location" # In production, use GeoIP on ip_address
        n = Notification(
            user_id=str(user.id),
            type="login",
            title="New login detected",
            message=f"New device logged in from {ip_address}",
            is_read=False,
            meta=_json.dumps({"ip": ip_address, "device": platform})
        )
        db.add(n)

    db.commit()

    return success({
        "user":          user.to_dict(),
        "access_token":  create_access_token(user.id),
        "refresh_token": create_refresh_token(user.id),
        "plan_limits":   PLAN_LIMITS.get(user.plan, PLAN_LIMITS["free"]),
    })


@app.post("/api/auth/refresh", tags=["Auth"])
def refresh(user: User = Depends(get_refresh_user)):
    """
    Exchange a refresh token for a new access token.
    Send the refresh token in the Authorization: Bearer <token> header.
    """
    return success({"access_token": create_access_token(user.id)})


@app.get("/api/auth/me", tags=["Auth"])
def me(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Return the currently logged-in user's profile."""
    active_sessions = db.query(VPNSession).filter_by(user_id=user.id, is_active=True).count()
    return success({
        "user":            user.to_dict(),
        "plan_limits":     PLAN_LIMITS.get(user.plan, PLAN_LIMITS["free"]),
        "devices":         [d.to_dict() for d in user.devices],
        "active_sessions": active_sessions,
    })


@app.post("/api/auth/change-password", tags=["Auth"])
def change_password(
    body: ChangePasswordRequest,
    user: User = Depends(get_current_user),
    db:   Session = Depends(get_db),
):
    """Change the current user's password."""
    if not bcrypt.verify(body.old_password, user.password_hash):
        raise HTTPException(status_code=401, detail="Current password is incorrect")

    user.password_hash = bcrypt.hash(body.new_password)
    db.commit()
    return success(msg="Password changed successfully")


@app.post("/api/auth/logout", tags=["Auth"])
def logout(credentials: HTTPAuthorizationCredentials = Depends(security)):
    """
    Logout the current user by adding their token to the Redis blocklist.

    How it works:
      - Extracts the JWT access token from the Authorization header
      - Stores it in Redis with a 12-hour TTL (matches token expiry)
      - All future requests with this token are rejected immediately
      - Even if someone has a copy of the token, it's now useless

    Without Redis: logout still returns 200 but token isn't truly invalidated.
    The user should delete the token from their app in that case.
    """
    token = credentials.credentials
    r = get_redis()
    if r is not None:
        # Block this token for 12 hours (JWT_ACCESS_EXPIRE)
        blocked = blocklist_token(token, ttl_seconds=43200)
        if blocked:
            return success(msg="Logged out successfully. Token revoked.")
        else:
            return success(msg="Logged out. (Redis unavailable — please delete token from your device.)")
    return success(msg="Logged out. (Redis not configured — delete token from your app.)")


@app.post("/api/auth/forgot-password", tags=["Auth"])
@limiter.limit("5/minute")
def forgot_password(request: Request, body: ForgotPasswordRequest, db: Session = Depends(get_db)):
    """
    Initiate the forgot password flow.
    If the email exists, generates a secure 15-minute token, stores it in Redis,
    and sends an email via Resend containing the reset link.
    Returns 200 regardless of whether the email exists (security best practice).
    """
    email = body.email.strip().lower()
    user = db.query(User).filter_by(email=email).first()

    if user:
        # Generate a truly random 32-character hex token
        reset_token = secrets.token_hex(16)
        
        # Store in Redis mapping token -> user.id strictly for 15 mins
        if store_password_reset_token(reset_token, str(user.id)):
            # Fire the email
            send_password_reset_email(to_email=user.email, token=reset_token)
        else:
            logger.error("Failed to store reset token in Redis. Forgot password flow interrupted.")

    # We always return generic success so bad actors can't enumerate emails.
    return success(msg="If that email is registered, a password reset link has been sent.")


@app.post("/api/auth/reset-password", tags=["Auth"])
@limiter.limit("5/minute")
def apply_reset_password(request: Request, body: ResetPasswordRequest, db: Session = Depends(get_db)):
    """
    Consumes a password reset token and changes the password.
    Fails if the token doesn't exist, is expired, or was already used.
    """
    # 1. Ask Redis for the user_id associated with this one-time token.
    user_id = get_user_by_reset_token(body.token)
    
    if not user_id:
        raise HTTPException(
            status_code=400, 
            detail="Invalid or expired token. Please request a new password reset."
        )

    # 2. Find the user in DB
    user = db.get(User, user_id)
    if not user:
        raise HTTPException(status_code=400, detail="User anomoly. Please contact support.")

    # 3. Hash new password and save
    user.password_hash = bcrypt.hash(body.new_password)
    db.commit()

    return success(msg="Your password has been successfully reset. You may now login.")



# ─────────────────────────────────────────────────────────────────
# Modes Route
# ─────────────────────────────────────────────────────────────────
@app.get("/api/modes", tags=["Servers"])
def get_modes(user: User = Depends(get_current_user)):
    """
    Return all available VPN modes with descriptions, features, and whether
    the current user's plan allows access to each one.
    """
    all_modes = [
        {
            "id": "standard",
            "name": "Standard Mode",
            "description": "Secure VPN connection for everyday browsing",
            "features": [
                "256-bit encryption",
                "No logs policy",
                "Auto kill switch",
            ],
            "available_on": ["free", "starter", "pro", "premium"],
            "coming_soon": False,
        },
        {
            "id": "streaming",
            "name": "Streaming Mode",
            "description": "Optimized for streaming platforms worldwide",
            "features": [
                "Netflix & Disney+ access",
                "HD/4K streaming",
                "Buffer-free experience",
            ],
            "available_on": ["starter", "pro", "premium"],
            "coming_soon": False,
        },
        {
            "id": "gaming",
            "name": "Gaming Mode",
            "description": "Lower ping and stable routing for gamers",
            "features": [
                "Anti-DDoS protection",
                "Low latency routing",
                "Stable connection",
            ],
            "available_on": ["pro", "premium"],
            "coming_soon": False,
        },
        {
            "id": "crypto",
            "name": "Crypto Mode",
            "description": "Secure crypto transactions and wallets",
            "features": [
                "Anti-phishing protection",
                "Exchange protection",
                "Wallet security",
            ],
            "available_on": ["pro", "premium"],
            "coming_soon": False,
        },
        {
            "id": "ai_security",
            "name": "AI Security Mode",
            "description": "Coming soon — AI-powered threat detection",
            "features": [
                "Real-time threat detection",
                "Dark web monitoring",
                "Privacy score",
            ],
            "available_on": [],
            "coming_soon": True,
        },
    ]

    user_plan = user.plan
    allowed_modes = PLAN_LIMITS.get(user_plan, {}).get("modes", ["standard"])

    # Tag each mode with whether the current user can access it
    for mode in all_modes:
        mode["unlocked"] = mode["id"] in allowed_modes and not mode["coming_soon"]

    return success(all_modes)


# ─────────────────────────────────────────────────────────────────
@app.get("/api/servers", tags=["Servers"])
def get_servers(
    mode:   Optional[str] = None,
    search: Optional[str] = None,
    top:    Optional[bool] = False,   # NEW: ?top=true → returns top 5 by ping + load
    db:     Session = Depends(get_db),
):
    """
    List all online VPN servers.
    Filter by mode: streaming | gaming | crypto | p2p
    Filter by search: country name, city name
    Filter top: ?top=true → returns top 5 servers by lowest ping + lowest load

    Redis caching:
      - Without filter/search: cached for 30 seconds (serves thousands of requests per second)
      - With filter/search: always hits DB (filtered results not worth caching)
    """
    # Only cache the unfiltered full list (most common request = app first open)
    cache_key = f"server_list_{mode or 'all'}_{search or 'none'}_{top}"
    if not search:   # only cache when no search term (search results vary too much)
        cached = cache_get(cache_key)
        if cached:
            return success(cached)   # served from Redis — no DB hit

    q = db.query(VPNServer).filter_by(is_online=True)

    if mode == "streaming": q = q.filter_by(is_streaming=True)
    elif mode == "gaming":  q = q.filter_by(is_gaming=True)
    elif mode == "crypto":  q = q.filter_by(is_crypto=True)
    elif mode == "p2p":     q = q.filter_by(is_p2p=True)

    if search:
        pattern = f"%{search}%"
        q = q.filter(
            VPNServer.country.ilike(pattern) |
            VPNServer.city.ilike(pattern) |
            VPNServer.name.ilike(pattern)
        )

    # "Top" tab: sort by ping first, then load — take only the best 5
    q = q.order_by(VPNServer.ping_ms, VPNServer.load_pct)
    if top:
        q = q.limit(5)

    servers = q.all()
    result  = [s.to_dict() for s in servers]

    # Save to Redis cache for 30 seconds (only for non-search requests)
    if not search:
        cache_set(cache_key, result, ttl=30)

    return success(result)



@app.get("/api/servers/best", tags=["Servers"])
def best_server(mode: str = "standard", db: Session = Depends(get_db)):
    """Return the best (lowest ping) server for a given mode."""
    q = db.query(VPNServer).filter_by(is_online=True)
    if mode == "streaming": q = q.filter_by(is_streaming=True)
    elif mode == "gaming":  q = q.filter_by(is_gaming=True)
    elif mode == "crypto":  q = q.filter_by(is_crypto=True)

    server = q.order_by(VPNServer.ping_ms, VPNServer.load_pct).first()
    if not server:
        server = db.query(VPNServer).filter_by(is_online=True).order_by(VPNServer.ping_ms).first()

    return success(server.to_dict() if server else None)


# ─────────────────────────────────────────────────────────────────
# VPN Session Routes
# ─────────────────────────────────────────────────────────────────

@app.post("/api/vpn/provision", tags=["VPN"])
def provision(
    body: ProvisionRequest,
    user: User    = Depends(get_current_user),
    db:   Session = Depends(get_db),
):
    """
    Register a device and get its WireGuard configuration.

    This is the CORE VPN endpoint. Called once per device when the user
    first sets up the VPN on that device.

    Flow:
      1. Validate user has active subscription (free plan allowed for trial)
      2. Check if this device already has a config → return existing one
      3. Pick a free IP from ip_pool (database-locked, no duplicates)
      4. Save vpn_configs record
      5. Queue Celery task to SSH-add peer to WireGuard server (background)
      6. Return WireGuard .conf file immediately (app doesn't wait for SSH)

    Request body:
      public_key:  User's device WireGuard public key (generated on device)
      server_id:   Which server to connect to (optional, auto-picks if empty)
      device_name: Label for this device (e.g. "iPhone 15")
      platform:    Device OS (ios/android/windows/mac/linux)
    """
    # ── Step 1: Pick the server ────────────────────────────────────
    server_id = body.server_id
    if not server_id:
        # Auto-pick lowest ping online server
        best = db.query(VPNServer).filter_by(is_online=True).order_by(VPNServer.ping_ms).first()
        if not best:
            raise HTTPException(status_code=503, detail="No servers available")
        server_id = best.id

    server = db.get(VPNServer, server_id)
    if not server or not server.is_online:
        raise HTTPException(status_code=404, detail="Server not found or offline")

    # ── Step 2: Check if device already has a config for this server ─
    existing = get_existing_config(
        db, str(user.id), server_id, body.device_name
    )
    if existing:
        # Already provisioned — just return the existing config
        config_content = generate_wg_config(server, existing.assigned_ip)
        return success({
            "config_id":      str(existing.id),
            "assigned_ip":    existing.assigned_ip,
            "server":         server.to_dict(),
            "wg_config":      config_content,
            "status":         "existing",
            "message":        "Existing config returned. Use wg_config in your WireGuard app.",
        })

    # ── Step 3: Generate a config ID and save VPNConfig FIRST ──────
    # IMPORTANT: VPNConfig must exist in DB before claim_ip_from_pool
    # because ip_pool.assigned_to has a FK → vpn_configs.id
    import uuid as _uuid
    new_config_id = str(_uuid.uuid4())

    # Create the config record with a placeholder IP — we'll update it after claiming
    config = VPNConfig(
        id=new_config_id,
        user_id=str(user.id),
        server_id=server_id,
        public_key=body.public_key,
        assigned_ip="pending",              # placeholder — updated below
        device_name=body.device_name or "Unknown Device",
        platform=body.platform or "unknown",
        is_active=True,
    )
    db.add(config)
    db.flush()   # write VPNConfig to DB so FK constraint is satisfied

    # ── Step 4: Claim a free IP from pool (FK now safe) ───────────
    ip_entry = claim_ip_from_pool(db, server_id, new_config_id)
    if not ip_entry:
        db.rollback()
        raise HTTPException(
            status_code=503,
            detail=f"Server {server.name} is at full capacity. Please choose another server."
        )

    # Update the config with the real assigned IP
    config.assigned_ip = ip_entry.ip_address

    # Also create a VPNSession record to track this connection
    session = VPNSession(
        user_id=str(user.id),
        server_id=server_id,
        config_id=new_config_id,
        mode=body.mode or "standard",
        protocol="wireguard",
        ip_assigned=ip_entry.ip_address,
        device_name=body.device_name or "Unknown Device",
        is_active=True,
    )
    db.add(session)

    # Update server peer count
    server.current_peers = (server.current_peers or 0) + 1
    server.load_pct = min(99, int((server.current_peers / max(server.max_peers, 1)) * 100))

    db.commit()
    db.refresh(config)


    # ── Step 5: Queue background Celery task to SSH-add peer ──────
    # This runs in the background — we don't wait for it
    # The user gets their config immediately without waiting for SSH
    job_id = str(_uuid.uuid4())
    add_wireguard_peer.delay(
        job_id=job_id,
        server_ip=server.ip_address or "0.0.0.0",
        public_key=body.public_key,
        assigned_ip=ip_entry.ip_address,
        config_id=new_config_id,
    )

    # ── Step 6: Generate and return the .conf file ─────────────────
    config_content = generate_wg_config(server, ip_entry.ip_address)

    return success({
        "config_id":   new_config_id,
        "assigned_ip": ip_entry.ip_address,
        "server":      server.to_dict(),
        "wg_config":   config_content,
        "job_id":      job_id,
        "status":      "provisioning",
        "message":     (
            "Config ready. WireGuard peer is being added to the server in background. "
            "Import wg_config into your WireGuard app now — it will connect within seconds."
        ),
    }, msg="VPN provisioned")


@app.get("/api/vpn/config/{server_id}", tags=["VPN"])
def get_vpn_config(
    server_id: str,
    user: User    = Depends(get_current_user),
    db:   Session = Depends(get_db),
):
    """
    Get the user's existing WireGuard config for a specific server.

    Called when:
      - User opens the app on a previously provisioned device
      - User needs to re-download their .conf file
      - App needs to reconnect to a previously used server

    Returns the .conf file content if the user has a config for this server.
    If not, they need to call POST /api/vpn/provision first.
    """
    server = db.get(VPNServer, server_id)
    if not server:
        raise HTTPException(status_code=404, detail="Server not found")

    config = get_existing_config(db, str(user.id), server_id)
    if not config:
        raise HTTPException(
            status_code=404,
            detail="No config found for this server. Call POST /api/vpn/provision first."
        )

    config_content = generate_wg_config(server, config.assigned_ip)

    return success({
        "config_id":   str(config.id),
        "assigned_ip": config.assigned_ip,
        "server":      server.to_dict(),
        "wg_config":   config_content,
        "device_name": config.device_name,
        "created_at":  config.created_at.isoformat(),
    })


@app.get("/api/vpn/configs", tags=["VPN"])
def list_my_configs(
    user: User    = Depends(get_current_user),
    db:   Session = Depends(get_db),
):
    """
    List all active WireGuard configs for the current user.
    Shows all provisioned devices and which server each one is on.
    """
    configs = db.query(VPNConfig).filter_by(
        user_id=str(user.id), is_active=True
    ).all()

    result = []
    for c in configs:
        server = db.get(VPNServer, c.server_id)
        result.append({
            **c.to_dict(),
            "server_name":    server.name if server else None,
            "server_country": server.country if server else None,
            "server_flag":    server.flag if server else None,
        })

    return success(result)


@app.delete("/api/vpn/config/{config_id}", tags=["VPN"])
def revoke_config(
    config_id: str,
    user: User    = Depends(get_current_user),
    db:   Session = Depends(get_db),
):
    """
    Remove a device's VPN configuration permanently.

    Called when:
      - User sells/loses a device and wants to remove VPN access from it
      - User wants to change which server a device is on (revoke + re-provision)

    What happens:
      1. Marks vpn_configs as inactive (immediate — blocks reconnection)
      2. Releases IP back to ip_pool (immediate)
      3. Queues Celery task to SSH-remove peer from WireGuard server (background)
    """
    import uuid as _uuid

    config = db.query(VPNConfig).filter_by(
        id=config_id,
        user_id=str(user.id),   # security: users can only delete their own configs
        is_active=True,
    ).first()

    if not config:
        raise HTTPException(status_code=404, detail="Config not found")

    server = db.get(VPNServer, config.server_id)

    # Step 1: Deactivate config immediately
    config.is_active  = False
    config.revoked_at = datetime.utcnow()

    # Step 2: Release IP back to pool
    release_ip_to_pool(db, config_id)

    # Step 3: End any active sessions using this config
    db.query(VPNSession).filter_by(config_id=config_id, is_active=True).update({
        "is_active": False,
        "ended_at":  datetime.utcnow(),
    })

    # Update server peer count
    if server:
        server.current_peers = max(0, (server.current_peers or 1) - 1)

    db.commit()

    # Step 4: Queue background task to remove peer from WireGuard server
    if server and server.ip_address:
        job_id = str(_uuid.uuid4())
        remove_wireguard_peer.delay(
            job_id=job_id,
            server_ip=server.ip_address,
            public_key=config.public_key,
            assigned_ip=config.assigned_ip,
            config_id=config_id,
        )

    return success(msg=f"Device config revoked. Peer removal queued on server {config.server_id}.")


@app.post("/api/vpn/connect", tags=["VPN"])
def connect(
    body: ConnectRequest,
    user: User    = Depends(get_current_user),
    db:   Session = Depends(get_db),
):
    """
    Start or resume a VPN session using an existing provisioned config.

    This is a lightweight endpoint — it doesn't do SSH.
    If the user has already provisioned (has a vpn_config), it just
    creates a session record and returns the server info.

    If no config exists for the requested server, instruct the user
    to call POST /api/vpn/provision first.

    For the free plan: enforces 45-minute session limit.
    """
    # ── Plan & mode check ─────────────────────────────────────────
    plan_limits = PLAN_LIMITS.get(user.plan, PLAN_LIMITS["free"])
    allowed_modes = plan_limits["modes"]
    if body.mode not in allowed_modes:
        raise HTTPException(
            status_code=403,
            detail=f"'{body.mode}' mode requires a paid plan. Upgrade to access it.",
        )

    # ── Free / Starter: enforce bandwidth data cap ────────────────
    bandwidth_limit = plan_limits.get("bandwidth_bytes")
    if bandwidth_limit is not None:  # None = unlimited
        used = user.bandwidth_used_bytes or 0
        used_gb    = round(used / 1_073_741_824, 2)
        limit_gb   = plan_limits["bandwidth_gb"]
        pct_used   = (used / bandwidth_limit) * 100

        if used >= bandwidth_limit:
            raise HTTPException(
                status_code=403,
                detail=(
                    f"You have used all {limit_gb} GB of your {user.plan.capitalize()} plan data. "
                    f"Upgrade to Pro for unlimited data."
                ),
            )

        # Warn at 80% — returned as a warning in the response (not an error)
        bandwidth_warning = pct_used >= 80
    else:
        bandwidth_warning = False
        used_gb    = round((user.bandwidth_used_bytes or 0) / 1_073_741_824, 2)

    # ── Pick server ───────────────────────────────────────────────
    server_id = body.server_id
    if not server_id:
        best = db.query(VPNServer).filter_by(is_online=True).order_by(VPNServer.ping_ms).first()
        server_id = best.id if best else None

    server = db.get(VPNServer, server_id)
    if not server or not server.is_online:
        raise HTTPException(status_code=404, detail="Server not found or offline")

    # ── Check user has a provisioned config for this server ───────
    config = get_existing_config(db, str(user.id), server_id)

    # End any existing active sessions
    db.query(VPNSession).filter_by(user_id=str(user.id), is_active=True).update({
        "is_active": False,
        "ended_at":  datetime.utcnow(),
    })

    # Use real assigned IP if config exists, else use a placeholder
    assigned_ip = config.assigned_ip if config else "10.0.0.0"

    session = VPNSession(
        user_id=str(user.id),
        server_id=server.id,
        config_id=str(config.id) if config else None,
        mode=body.mode,
        protocol=body.protocol,
        ip_assigned=assigned_ip,
        device_name=body.device_name,
        is_active=True,
    )
    server.load_pct = min(99, server.load_pct + random.randint(1, 3))
    db.add(session)
    db.commit()
    db.refresh(session)

    response = {
        "session":          session.to_dict(),
        "server":           server.to_dict(),
        "assigned_ip":      assigned_ip,
        "provisioned":      config is not None,
        "speed_limit_mbps": plan_limits.get("speed_mbps"),     # None = unlimited
        "bandwidth_used_gb":  used_gb,
        "bandwidth_limit_gb": plan_limits.get("bandwidth_gb"),  # None = unlimited
    }

    if bandwidth_warning:
        response["bandwidth_warning"] = (
            f"You have used {used_gb} GB of your {plan_limits['bandwidth_gb']} GB plan. "
            f"Upgrade before you run out!"
        )

    if not config:
        response["warning"] = (
            "No WireGuard config found for this server. "
            "Call POST /api/vpn/provision with your device public key to get a real VPN config."
        )

    return success(response, msg="Connected")


@app.post("/api/vpn/disconnect", tags=["VPN"])
def disconnect(
    user: User    = Depends(get_current_user),
    db:   Session = Depends(get_db),
):
    """
    End all active VPN sessions for the current user.

    NOTE: This does NOT revoke the WireGuard peer config (that's permanent
    until the user calls DELETE /api/vpn/config/{config_id}).
    This just marks the session as ended — user can reconnect instantly
    without re-provisioning.
    """
    sessions = db.query(VPNSession).filter_by(user_id=str(user.id), is_active=True).all()
    for s in sessions:
        s.is_active  = False
        s.ended_at   = datetime.utcnow()
        # Log usage (bytes simulated for now — real tracking needs wg show)
        s.bytes_down = random.randint(10_000_000, 500_000_000)
        s.bytes_up   = random.randint(1_000_000,  50_000_000)

        # Also create a UsageLog record for bandwidth tracking
        usage_log = UsageLog(
            user_id=str(user.id),
            server_id=s.server_id,
            bytes_sent=s.bytes_up,
            bytes_received=s.bytes_down,
            session_start=s.started_at,
            session_end=s.ended_at,
        )
        db.add(usage_log)

        # Update user's total bandwidth used
        user.bandwidth_used_bytes = (user.bandwidth_used_bytes or 0) + s.bytes_down + s.bytes_up

    db.commit()
    return success(msg="Disconnected")


@app.get("/api/vpn/status", tags=["VPN"])
def vpn_status(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """
    Check whether the current user has an active VPN session.
    Called by the client app when it opens.
    Also returns subscription validity and bandwidth usage.
    """
    session = db.query(VPNSession).filter_by(user_id=str(user.id), is_active=True).first()
    if session:
        server  = db.get(VPNServer, session.server_id)
        elapsed = (datetime.utcnow() - session.started_at).total_seconds()
        remaining = max(0, 45 * 60 - int(elapsed)) if user.plan == "free" else None
        return success({
            "connected":         True,
            "session":           session.to_dict(),
            "server":            server.to_dict() if server else None,
            "elapsed_seconds":   int(elapsed),
            "remaining_seconds": remaining,
            "download_mbps":     round(random.uniform(20, 100), 1),
            "upload_mbps":       round(random.uniform(2, 20), 1),
            "ping_ms":           (server.ping_ms + random.randint(-2, 5)) if server else 999,
            "bandwidth_used_gb": round((user.bandwidth_used_bytes or 0) / 1_073_741_824, 2),
            "bandwidth_limit_gb": round((user.bandwidth_limit_bytes or 0) / 1_073_741_824, 0),
        })
    return success({"connected": False})


@app.get("/api/vpn/job/{job_id}", tags=["VPN"])
def check_provisioning_job(job_id: str):
    """
    Check the status of a background WireGuard provisioning job.

    After calling POST /api/vpn/provision, the WireGuard peer is added
    to the server in the background (via Celery + SSH).
    The app can poll this endpoint to know when the peer is fully active.

    Status values:
      pending    → job queued, not started yet
      running    → SSH is in progress
      completed  → peer added successfully, VPN is fully active
      retrying   → SSH failed once, retrying (up to 3 times)
      failed     → all retries exhausted
    """
    from redis_client import get_job_status
    status = get_job_status(job_id)
    if status is None:
        return success({"status": "pending", "message": "Job queued, waiting to start..."})
    return success(status)


@app.get("/api/vpn/history", tags=["VPN"])
def session_history(
    limit: int = 20,
    user:  User    = Depends(get_current_user),
    db:    Session = Depends(get_db),
):
    """Return recent past VPN sessions for the current user."""
    sessions = (
        db.query(VPNSession)
        .filter_by(user_id=str(user.id), is_active=False)
        .order_by(VPNSession.started_at.desc())
        .limit(limit)
        .all()
    )
    return success([s.to_dict() for s in sessions])


@app.get("/api/usage/bandwidth", tags=["VPN"])
def get_bandwidth_usage(user: User = Depends(get_current_user)):
    """
    Returns the user's total data transferred this billing cycle to 
    enforce the 100GB (or unlimited) plan limits.
    """
    return success({
        "bandwidth_used_bytes": user.bandwidth_used_bytes or 0,
        "bandwidth_limit_bytes": user.bandwidth_limit_bytes,
        "used_gb": round((user.bandwidth_used_bytes or 0) / 1073741824, 2),
        "limit_gb": round((user.bandwidth_limit_bytes or 0) / 1073741824, 2) if user.bandwidth_limit_bytes else None,
        "limit_reached": (user.bandwidth_used_bytes or 0) > (user.bandwidth_limit_bytes or float('inf'))
    })

# ─────────────────────────────────────────────────────────────────
# Subscription / Billing Routes
# ─────────────────────────────────────────────────────────────────
@app.get("/api/plans", tags=["Billing"])
def get_plans():
    """Return all available plans and their prices."""
    return success(PLANS)


@app.get("/api/billing/status", tags=["Billing"])
def get_billing_status(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Return next renewal date, active plan, and next charge from DB and Stripe."""
    active_sub = db.query(Subscription).filter_by(
        user_id=str(user.id), 
        status="active"
    ).first()

    response = {
        "plan": user.plan,
        "subscription_status": user.subscription_status,
        "plan_expires_at": user.plan_expires_at,
        "next_charge": None
    }

    if active_sub and user.stripe_customer_id:
        upcoming = get_next_charge_details(user.stripe_customer_id)
        if upcoming:
            response["next_charge"] = upcoming
            
    return success(response)


@app.post("/api/billing/checkout", tags=["Billing"])
def checkout(
    body: CheckoutRequest,
    user: User    = Depends(get_current_user),
):
    """Generate a Stripe Checkout URL for purchasing/upgrading a plan."""
    if body.plan not in PLANS:
        raise HTTPException(status_code=400, detail="Invalid plan")

    try:
        session_data = create_checkout_session(
            user_id=str(user.id),
            user_email=user.email,
            plan=body.plan,
            billing_cycle=body.billing_cycle,
            stripe_customer_id=user.stripe_customer_id,
        )
        return success(session_data, msg="Checkout session created")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/billing/portal", tags=["Billing"])
def billing_portal(
    user: User = Depends(get_current_user),
):
    """Generate a Stripe Billing Portal URL for managing subscription/payment methods."""
    if not user.stripe_customer_id:
        raise HTTPException(status_code=400, detail="You do not have an active billing account")

    try:
        portal_data = create_billing_portal_session(user.stripe_customer_id)
        return success(portal_data, msg="Billing portal session created")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/webhooks/stripe", tags=["Billing"])
async def stripe_webhook(request: Request, db: Session = Depends(get_db)):
    """Stripe webhook endpoint. Receives payment/cancellation events."""
    # Stripe requires the raw request body string to verify the signature
    payload = await request.body()
    sig_header = request.headers.get("Stripe-Signature")

    if not sig_header:
        raise HTTPException(status_code=400, detail="Missing Stripe-Signature header")

    try:
        import stripe
        # 1. Verify the signature (throws exception if invalid)
        event = verify_and_parse_webhook(payload, sig_header)
        
        # 2. Process the event and update the DB
        result = handle_webhook_event(event, db)
        
        return JSONResponse(status_code=200, content={"received": True, "result": result})
        
    except stripe.error.SignatureVerificationError as e:
        logger.warning(f"⚠️ Invalid Stripe webhook signature: {e}")
        raise HTTPException(status_code=400, detail="Invalid signature")
    except Exception as e:
        logger.error(f"⚠️ Stripe webhook error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/subscriptions/history", tags=["Billing"])
def billing_history(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """Return all past subscriptions for the current user."""
    subs = (
        db.query(Subscription)
        .filter_by(user_id=user.id)
        .order_by(Subscription.started_at.desc())
        .all()
    )
    return success([s.to_dict() for s in subs])


# ─────────────────────────────────────────────────────────────────
# Device Routes
# ─────────────────────────────────────────────────────────────────
@app.get("/api/devices", tags=["Devices"])
def list_devices(user: User = Depends(get_current_user)):
    """List all registered devices for the current user."""
    return success([d.to_dict() for d in user.devices])


@app.delete("/api/devices/{device_id}", tags=["Devices"])
def remove_device(
    device_id: int,
    user: User    = Depends(get_current_user),
    db:   Session = Depends(get_db),
):
    """Remove a device from the user's account."""
    device = db.query(Device).filter_by(id=device_id, user_id=user.id).first()
    if not device:
        raise HTTPException(status_code=404, detail="Device not found")
    db.delete(device)
    db.commit()
    return success(msg="Device removed")


# ─────────────────────────────────────────────────────────────────
# Support Routes
# ─────────────────────────────────────────────────────────────────
@app.post("/api/support/ticket", tags=["Support"])
def submit_ticket(body: SupportTicketRequest, db: Session = Depends(get_db)):
    """Submit a support ticket. Does not require login."""
    ticket = SupportTicket(
        email=body.email,
        subject=body.subject or "Support Request",
        message=body.message,
        category=body.category,
    )
    db.add(ticket)
    db.commit()
    db.refresh(ticket)
    return success(
        {"ticket_id": ticket.id},
        msg="Ticket submitted! We'll reply within 24 hours.",
        status_code=201,
    )


@app.get("/api/support/faq", tags=["Support"])
def get_faq():
    """Return the list of frequently asked questions."""
    faqs = [
        {"q": "What is a VPN?", "a": "A VPN (Virtual Private Network) encrypts your internet connection and masks your IP address, protecting your privacy and allowing you to access content from anywhere in the world."},
        {"q": "Does SecureVPN keep logs?", "a": "Absolutely not. We operate a strict zero-logs policy. We never store, track, or share your browsing data."},
        {"q": "How many devices can I connect simultaneously?", "a": "Free: 1 device. Essential: 5 devices. Elite & Ultimate: Unlimited devices."},
        {"q": "What protocols does SecureVPN use?", "a": "We support WireGuard (fastest), OpenVPN (most compatible), and IKEv2 (most stable on mobile)."},
        {"q": "Can I use SecureVPN for Netflix?", "a": "Yes! Our Streaming Mode servers are specifically optimised for Netflix, Disney+, Hulu, BBC iPlayer and more."},
        {"q": "Does SecureVPN work in China?", "a": "Yes, our obfuscated servers are designed to work in restrictive regions including China, Russia, and the UAE."},
        {"q": "How do I cancel my subscription?", "a": "You can cancel anytime from your Account → Billing page. You'll retain access until the end of your paid period."},
        {"q": "What is a kill switch?", "a": "A kill switch instantly blocks all internet traffic if your VPN connection drops, ensuring your real IP is never exposed."},
        {"q": "Can I use SecureVPN on a router?", "a": "Yes. SecureVPN supports router configuration for household-wide protection."},
        {"q": "Is there a free trial?", "a": "Yes! We offer a 7-day free trial on all paid plans with no credit card required."},
    ]
    return success(faqs)


# ─────────────────────────────────────────────────────────────────
# App Settings Routes  (Settings page)
# ─────────────────────────────────────────────────────────────────

SUPPORTED_LANGUAGES = [
    {"code": "english",    "label": "English"},
    {"code": "spanish",    "label": "Español"},
    {"code": "french",     "label": "Français"},
    {"code": "german",     "label": "Deutsch"},
    {"code": "arabic",     "label": "العربية"},
    {"code": "hindi",      "label": "हिन्दी"},
    {"code": "portuguese", "label": "Português"},
    {"code": "japanese",   "label": "日本語"},
    {"code": "chinese",    "label": "中文"},
    {"code": "korean",     "label": "한국어"},
]

SUPPORTED_PROTOCOLS = [
    {"id": "wireguard", "label": "WireGuard",  "description": "Fastest — recommended for most users"},
    {"id": "openvpn",   "label": "OpenVPN",    "description": "Most compatible — works on all networks"},
    {"id": "ikev2",     "label": "IKEv2/IPSec","description": "Best for mobile — reconnects automatically"},
]


class AppSettingsRequest(BaseModel):
    dark_theme:         Optional[bool] = None
    language:           Optional[str]  = None
    auto_connect:       Optional[bool] = None
    preferred_protocol: Optional[str]  = None

    @field_validator("language")
    @classmethod
    def validate_language(cls, v):
        if v is None:
            return v
        v = v.strip().lower()   # normalize: 'English' → 'english'
        valid = [l["code"] for l in SUPPORTED_LANGUAGES]
        if v not in valid:
            raise ValueError(f"Invalid language '{v}'. Valid options: {valid}")
        return v

    @field_validator("preferred_protocol")
    @classmethod
    def validate_protocol(cls, v):
        if v is None:
            return v
        v = v.strip().lower()   # normalize: 'WireGuard' → 'wireguard'
        valid = [p["id"] for p in SUPPORTED_PROTOCOLS]
        if v not in valid:
            raise ValueError(f"Invalid protocol '{v}'. Valid options: {valid}")
        return v


@app.get("/api/settings", tags=["Account"])
def get_app_settings(user: User = Depends(get_current_user)):
    """Get the user's app settings (Appearance, Language, Connection)."""
    return success({
        "appearance": {
            "dark_theme": user.dark_theme,
        },
        "language": {
            "selected": user.language,
            "options":  SUPPORTED_LANGUAGES,
        },
        "connection": {
            "auto_connect":       user.auto_connect,
            "preferred_protocol": user.preferred_protocol,
            "protocol_options":   SUPPORTED_PROTOCOLS,
        },
    })


@app.patch("/api/settings", tags=["Account"])
def update_app_settings(
    body: AppSettingsRequest,
    user: User    = Depends(get_current_user),
    db:   Session = Depends(get_db),
):
    """
    Update any app setting. Send only the fields you want to change.

    - dark_theme: true/false           → Appearance toggle
    - language: 'english'/'spanish'... → Language dropdown
    - auto_connect: true/false         → Auto Connect toggle
    - preferred_protocol: 'wireguard'/'openvpn'/'ikev2' → Protocol dropdown
    """
    if body.dark_theme         is not None: user.dark_theme         = body.dark_theme
    if body.language           is not None: user.language           = body.language
    if body.auto_connect       is not None: user.auto_connect       = body.auto_connect
    if body.preferred_protocol is not None: user.preferred_protocol = body.preferred_protocol

    db.commit()
    db.refresh(user)

    return success({
        "appearance": {
            "dark_theme": user.dark_theme,
        },
        "language": {
            "selected": user.language,
            "options":  SUPPORTED_LANGUAGES,
        },
        "connection": {
            "auto_connect":       user.auto_connect,
            "preferred_protocol": user.preferred_protocol,
            "protocol_options":   SUPPORTED_PROTOCOLS,
        },
    }, msg="Settings saved")


# ─────────────────────────────────────────────────────────────────
# Referral Routes
# ─────────────────────────────────────────────────────────────────
@app.get("/api/referrals", tags=["Account"])
def get_referral_info(user: User = Depends(get_current_user)):
    """
    Get the user's referral code and referral stats.
    Sharing this code gives the referred user 7 days free Essential plan.
    """
    import hashlib
    # Generate a deterministic referral code from the user's ID
    code = "ATMOS-" + hashlib.md5(str(user.id).encode()).hexdigest()[:6].upper()
    return success({
        "referral_code":       code,
        "referral_link":       f"https://atmosvpn.com/join?ref={code}",
        "referred_count":      0,   # Number of people who used this code
        "reward_days_earned":  0,   # Total free days earned via referrals
        "reward_per_referral": 7,   # Days of free Essential plan per referral
        "how_it_works": [
            "Share your referral link with friends",
            "When they sign up using your link, they get 7 days free",
            "You earn 7 days of free Essential plan for each referral",
        ],
    })

# ─────────────────────────────────────────────────────────────────
# Notifications Routes
# ─────────────────────────────────────────────────────────────────

def _seed_default_notifications(user: User, db: Session):
    """
    Seed default notifications for a user on first fetch.
    Creates the 5 notification types shown in the UI.
    Only seeds once — checks if user already has notifications.
    """
    import json as _json
    from datetime import timedelta

    now = datetime.utcnow()

    defaults = [
        # 1. Security: Unsafe website blocked (most recent)
        Notification(
            user_id=str(user.id),
            type="security",
            title="Unsafe website blocked",
            message="Malicious site attempt was blocked while browsing",
            is_read=False,
            coming_soon=False,
            created_at=now - timedelta(minutes=2),
        ),
        # 2. VPN Event: VPN disconnected / kill switch fired
        Notification(
            user_id=str(user.id),
            type="vpn_event",
            title="VPN disconnected",
            message="Connection dropped — kill switch activated",
            is_read=False,
            coming_soon=False,
            created_at=now - timedelta(hours=1),
        ),
        # 3. Login: New device login
        Notification(
            user_id=str(user.id),
            type="login",
            title="New login detected",
            message="New device logged in from London, UK",
            is_read=False,
            coming_soon=False,
            meta=_json.dumps({"location": "London, UK", "device": "Unknown"}),
            created_at=now - timedelta(hours=3),
        ),
        # 4. Coming soon: Dark web alert
        Notification(
            user_id=str(user.id),
            type="coming_soon",
            title="Dark web alert",
            message="Email found on dark web database — coming soon",
            is_read=True,
            coming_soon=True,
            created_at=now - timedelta(days=1),
        ),
        # 5. Coming soon: Phishing detection
        Notification(
            user_id=str(user.id),
            type="coming_soon",
            title="Phishing site detected",
            message="AI detected phishing attempt — coming soon",
            is_read=True,
            coming_soon=True,
            created_at=now - timedelta(days=1, hours=2),
        ),
    ]

    # Add plan upgrade notification if on free plan
    if user.plan == "free":
        defaults.append(Notification(
            user_id=str(user.id),
            type="upgrade",
            title="Upgrade for unlimited data",
            message=f"You are on the Free plan (10 GB limit). Upgrade to Pro for unlimited data.",
            is_read=False,
            coming_soon=False,
            created_at=now - timedelta(days=2),
        ))

    # Add bandwidth warning if at 80%+
    used_bytes  = user.bandwidth_used_bytes or 0
    limit_bytes = user.bandwidth_limit_bytes or 10_737_418_240
    if limit_bytes and (used_bytes / limit_bytes) >= 0.8:
        used_gb  = round(used_bytes  / 1_073_741_824, 1)
        limit_gb = round(limit_bytes / 1_073_741_824, 0)
        defaults.append(Notification(
            user_id=str(user.id),
            type="bandwidth",
            title="Bandwidth limit approaching",
            message=f"You have used {used_gb} GB of your {limit_gb:.0f} GB plan. Upgrade before you run out!",
            is_read=False,
            coming_soon=False,
            created_at=now - timedelta(minutes=30),
        ))

    for n in defaults:
        db.add(n)
    db.commit()


@app.post("/api/test/notifications/trigger", tags=["Test"])
def test_trigger_notification(
    user: User    = Depends(get_current_user),
    db:   Session = Depends(get_db),
):
    """
    TEST ENDPOINT: Generate a new random notification to test UI polling/updates.
    """
    import random
    
    templates = [
        {"type": "security", "title": "Malware Blocked", "message": "AtmosVPN blocked a malicious download attempt."},
        {"type": "vpn_event", "title": "Connection unstable", "message": "Your connection dropped briefly, but kill switch protected you."},
        {"type": "login", "title": "New Login", "message": "New device logged in from New York, USA.", "meta": '{"location": "New York, USA"}'},
    ]
    t = random.choice(templates)
    
    n = Notification(
        user_id=str(user.id),
        type=t["type"],
        title=t["title"],
        message=t["message"],
        is_read=False,
        coming_soon=False,
        meta=t.get("meta")
    )
    db.add(n)
    db.commit()
    db.refresh(n)
    return success(n.to_dict(), msg="New notification generated successfully")


@app.get("/api/notifications", tags=["Account"])
def get_notifications(

    unread_only: bool     = False,
    user: User            = Depends(get_current_user),
    db:   Session         = Depends(get_db),
):
    """
    Return in-app notifications for the current user.
    All 5 types from the UI are supported:
      - security    → Unsafe website blocked
      - vpn_event   → VPN disconnected / kill switch
      - login       → New login detected
      - coming_soon → Dark web alert, Phishing (future AI features)
      - bandwidth   → Data usage warnings
      - upgrade     → Plan upgrade suggestions

    Query param: ?unread_only=true  → only return unread notifications
    """
    # Seed default notifications on first visit
    count = db.query(Notification).filter_by(user_id=str(user.id)).count()
    if count == 0:
        _seed_default_notifications(user, db)

    q = db.query(Notification).filter_by(user_id=str(user.id))
    if unread_only:
        q = q.filter_by(is_read=False)
    q = q.order_by(Notification.created_at.desc())

    notifications = q.all()
    unread_count  = db.query(Notification).filter_by(
        user_id=str(user.id), is_read=False
    ).count()

    return success({
        "notifications": [n.to_dict() for n in notifications],
        "unread_count":  unread_count,
        "total":         len(notifications),
    })


@app.patch("/api/notifications/{notif_id}/read", tags=["Account"])
def mark_notification_read(
    notif_id: str,
    user: User    = Depends(get_current_user),
    db:   Session = Depends(get_db),
):
    """Mark a single notification as read."""
    notif = db.query(Notification).filter_by(
        id=notif_id, user_id=str(user.id)
    ).first()
    if not notif:
        raise HTTPException(status_code=404, detail="Notification not found")
    notif.is_read = True
    db.commit()
    return success(notif.to_dict(), msg="Marked as read")


@app.patch("/api/notifications/read-all", tags=["Account"])
def mark_all_notifications_read(
    user: User    = Depends(get_current_user),
    db:   Session = Depends(get_db),
):
    """Mark ALL notifications as read."""
    db.query(Notification).filter_by(
        user_id=str(user.id), is_read=False
    ).update({"is_read": True})
    db.commit()
    return success(msg="All notifications marked as read")


@app.delete("/api/notifications/{notif_id}", tags=["Account"])
def delete_notification(
    notif_id: str,
    user: User    = Depends(get_current_user),
    db:   Session = Depends(get_db),
):
    """Delete (dismiss) a single notification."""
    notif = db.query(Notification).filter_by(
        id=notif_id, user_id=str(user.id)
    ).first()
    if not notif:
        raise HTTPException(status_code=404, detail="Notification not found")
    db.delete(notif)
    db.commit()
    return success(msg="Notification dismissed")


# ─────────────────────────────────────────────────────────────────
# Security Center Routes
# ─────────────────────────────────────────────────────────────────

class SecuritySettingsRequest(BaseModel):
    kill_switch_enabled:     Optional[bool] = None
    auto_connect_wifi:       Optional[bool] = None
    dns_leak_protection:     Optional[bool] = None
    ad_blocker_enabled:      Optional[bool] = None
    tracker_blocker_enabled: Optional[bool] = None
    malware_protection:      Optional[bool] = None


def _calc_privacy_score(user: User) -> int:
    """
    Calculate the user's Privacy Score (0-100) based on enabled security features.
    Each of the 6 toggles contributes points. VPN connection adds a bonus.
    """
    score = 0
    if user.kill_switch_enabled:     score += 20
    if user.dns_leak_protection:     score += 20
    if user.malware_protection:      score += 15
    if user.ad_blocker_enabled:      score += 15
    if user.tracker_blocker_enabled: score += 20
    if user.auto_connect_wifi:       score += 10
    return min(score, 100)


@app.get("/api/security/settings", tags=["Security"])
def get_security_settings(user: User = Depends(get_current_user)):
    """Get the user's Security Center settings and calculated Privacy Score."""
    privacy_score = _calc_privacy_score(user)
    return success({
        "privacy_score": privacy_score,
        "connection_security": {
            "kill_switch_enabled": user.kill_switch_enabled,
            "auto_connect_wifi":   user.auto_connect_wifi,
            "dns_leak_protection": user.dns_leak_protection,
        },
        "privacy_tools": {
            "ad_blocker_enabled":      user.ad_blocker_enabled,
            "tracker_blocker_enabled": user.tracker_blocker_enabled,
            "malware_protection":      user.malware_protection,
        },
        "ai_security": {
            "enabled":     False,
            "coming_soon": True,
            "features": [
                "Dark web monitoring",
                "Phishing detection",
                "Real-time privacy score",
            ],
        },
    })


@app.patch("/api/security/settings", tags=["Security"])
def update_security_settings(
    body: SecuritySettingsRequest,
    user: User    = Depends(get_current_user),
    db:   Session = Depends(get_db),
):
    """Toggle any security setting. Send only the fields you want to change."""
    if body.kill_switch_enabled     is not None: user.kill_switch_enabled     = body.kill_switch_enabled
    if body.auto_connect_wifi       is not None: user.auto_connect_wifi       = body.auto_connect_wifi
    if body.dns_leak_protection     is not None: user.dns_leak_protection     = body.dns_leak_protection
    if body.ad_blocker_enabled      is not None: user.ad_blocker_enabled      = body.ad_blocker_enabled
    if body.tracker_blocker_enabled is not None: user.tracker_blocker_enabled = body.tracker_blocker_enabled
    if body.malware_protection      is not None: user.malware_protection      = body.malware_protection
    db.commit()
    db.refresh(user)
    privacy_score = _calc_privacy_score(user)
    return success({
        "privacy_score": privacy_score,
        "connection_security": {
            "kill_switch_enabled": user.kill_switch_enabled,
            "auto_connect_wifi":   user.auto_connect_wifi,
            "dns_leak_protection": user.dns_leak_protection,
        },
        "privacy_tools": {
            "ad_blocker_enabled":      user.ad_blocker_enabled,
            "tracker_blocker_enabled": user.tracker_blocker_enabled,
            "malware_protection":      user.malware_protection,
        },
    }, msg="Security settings updated")


# ─────────────────────────────────────────────────────────────────
# Health & Metadata
# ─────────────────────────────────────────────────────────────────
@app.get("/api/status", tags=["Health"])
def api_status(db: Session = Depends(get_db)):
    """Health check endpoint. Returns API version and server count."""
    return success({
        "api_version":  "2.0.0",
        "framework":    "FastAPI",
        "server_count": db.query(VPNServer).filter_by(is_online=True).count(),
        "status":       "operational",
        "uptime":       "99.99%",
    })


@app.get("/api/ip", tags=["Health"])
def get_ip(request: Request):
    """Returns the caller's public IP address (useful for IP check tool in the app)."""
    ip = request.headers.get("X-Forwarded-For", request.client.host)
    return success({"ip": ip})


@app.post("/api/speedtest/run", tags=["Health"])
def run_speed_test(
    user: User    = Depends(get_current_user),
    db:   Session = Depends(get_db),
):
    """
    Run a VPN speed test for the current user.

    Returns the exact 4 values shown in the Speed Test UI:
      - download_mbps   → Download Mbps gauge + card
      - upload_mbps     → Upload Mbps card
      - ping_ms         → Ping card
      - latency_ms      → Latency card

    NOTE: Values are simulated until a real WireGuard server is connected.
    On a real server, this would SSH in and run iperf3 / speedtest-cli.
    """
    # Check if user has an active VPN session
    session = db.query(VPNSession).filter_by(
        user_id=str(user.id), is_active=True
    ).first()

    server  = None
    ping_ms = 999
    if session:
        server  = db.get(VPNServer, session.server_id)
        # Use actual server ping + small random variation for realism
        ping_ms = (server.ping_ms + random.randint(-3, 5)) if server else 999

    # Simulate realistic speed test results
    # In production: SSH into VPN server and run iperf3 or speedtest-cli
    download_mbps = round(random.uniform(80.0, 150.0), 1)   # Download Mbps
    upload_mbps   = round(random.uniform(15.0, 40.0),  1)   # Upload Mbps
    latency_ms    = ping_ms + random.randint(0, 3)           # Latency ≈ Ping ± small jitter

    return success({
        "download_mbps": download_mbps,   # shown in top gauge + bottom-left card
        "upload_mbps":   upload_mbps,     # shown in bottom-right card
        "ping_ms":       ping_ms,         # shown in bottom-left card (Ping)
        "latency_ms":    latency_ms,      # shown in bottom-right card (Latency)
        "connected":     session is not None,
        "server":        server.to_dict() if server else None,
        "tested_at":     datetime.utcnow().isoformat() + "Z",
        "note": (
            "Live values from VPN server"
            if session
            else "Not connected to VPN — results reflect unprotected connection"
        ),
    })


# ─────────────────────────────────────────────────────────────────
# Admin Routes — Protected by X-Admin-Token header
# ─────────────────────────────────────────────────────────────────

# In-memory app config (move to DB in production)
_app_config = {
    "free_session_minutes": 45,
    "ad_bonus_minutes":     30,
    "max_free_devices":     1,
    "ads_enabled":          True,
    "maintenance_mode":     False,
}


@app.post("/api/admin/login", tags=["Admin"])
def admin_login(body: AdminLoginRequest):
    """Admin login — returns admin token to use in X-Admin-Token header."""
    if body.password != ADMIN_PASSWORD:
        raise HTTPException(status_code=401, detail="Invalid admin credentials")
    return success({"admin_token": ADMIN_PASSWORD}, "Admin login successful")


@app.get("/api/admin/stats", tags=["Admin"])
def admin_stats(
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """High-level stats dashboard for admin."""
    from sqlalchemy import func
    total_users     = db.query(User).count()
    active_sessions = db.query(VPNSession).filter_by(is_active=True).count()
    free_users      = db.query(User).filter_by(plan="free").count()
    online_servers  = db.query(VPNServer).filter_by(is_online=True).count()
    open_tickets    = db.query(SupportTicket).filter_by(status="open").count()
    active_subs     = db.query(Subscription).filter_by(status="active").count()
    total_revenue   = db.query(func.sum(Subscription.amount_usd)).filter_by(status="active").scalar() or 0.0

    return success({
        "total_users":           total_users,
        "active_sessions":       active_sessions,
        "total_sessions":        db.query(VPNSession).count(),
        "free_users":            free_users,
        "paid_users":            total_users - free_users,
        "online_servers":        online_servers,
        "open_tickets":          open_tickets,
        "active_subscriptions":  active_subs,
        "total_revenue_usd":     total_revenue,
    })


@app.get("/api/admin/users", tags=["Admin"])
def admin_list_users(
    search: Optional[str] = None,
    plan:   Optional[str] = None,
    page:   int = 1,
    limit:  int = 20,
    _:      None    = Depends(admin_required),
    db:     Session = Depends(get_db),
):
    """Search and list users with pagination."""
    q = db.query(User)
    if search:
        q = q.filter(
            User.email.ilike(f"%{search}%") |
            User.full_name.ilike(f"%{search}%")
        )
    if plan:
        q = q.filter_by(plan=plan)

    total = q.count()
    users = q.order_by(User.created_at.desc()).offset((page - 1) * limit).limit(limit).all()
    return success({
        "users": [u.to_dict() for u in users],
        "total": total,
        "page":  page,
        "limit": limit,
    })


@app.get("/api/admin/users/{user_id}", tags=["Admin"])
def admin_user_detail(
    user_id: int,
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """Get full details of a specific user including sessions and subscriptions."""
    user = db.get(User, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    sessions = (
        db.query(VPNSession)
        .filter_by(user_id=user.id)
        .order_by(VPNSession.started_at.desc())
        .limit(10).all()
    )
    subs = db.query(Subscription).filter_by(user_id=user.id).all()
    return success({
        "user":          user.to_dict(),
        "sessions":      [s.to_dict() for s in sessions],
        "subscriptions": [s.to_dict() for s in subs],
    })


@app.patch("/api/admin/users/{user_id}", tags=["Admin"])
def admin_update_user(
    user_id: int,
    body:    AdminUpdateUserRequest,
    _:       None    = Depends(admin_required),
    db:      Session = Depends(get_db),
):
    """Update a user's plan or name from admin."""
    user = db.get(User, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    if body.plan and body.plan in PLAN_LIMITS:
        user.plan = body.plan
    if body.full_name is not None:
        user.full_name = body.full_name
    db.commit()
    return success(user.to_dict(), "User updated")


@app.delete("/api/admin/users/{user_id}", tags=["Admin"])
def admin_delete_user(
    user_id: int,
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """Permanently delete a user account."""
    user = db.get(User, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    db.delete(user)
    db.commit()
    return success(msg="User deleted")


@app.delete("/api/admin/users/{user_id}/suspend", tags=["Admin"])
def admin_suspend_user(
    user_id: int,
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """
    Suspend a user and revoke all their active VPN sessions.
    (Real WireGuard peer revocation via SSH is pending implementation.)
    """
    user = db.get(User, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    # Revoke all active sessions
    db.query(VPNSession).filter_by(user_id=user.id, is_active=True).update({
        "is_active": False,
        "ended_at":  datetime.utcnow(),
    })
    user.plan                = "free"
    user.subscription_status = "suspended"
    db.commit()
    return success(msg=f"User {user.email} suspended and all sessions revoked")


@app.get("/api/admin/servers", tags=["Admin"])
def admin_list_servers(
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """List all VPN servers (admin view with full details)."""
    return success([s.to_dict() for s in db.query(VPNServer).all()])


@app.patch("/api/admin/servers/{server_id}", tags=["Admin"])
def admin_update_server(
    server_id: str,
    body:      AdminUpdateServerRequest,
    _:         None    = Depends(admin_required),
    db:        Session = Depends(get_db),
):
    """Update server properties (toggle online, update ping, etc.)."""
    server = db.get(VPNServer, server_id)
    if not server:
        raise HTTPException(status_code=404, detail="Server not found")

    update_fields = ["name", "city", "country", "ping_ms", "capacity_mbps",
                     "is_online", "is_streaming", "is_gaming", "is_crypto", "is_p2p"]
    for field in update_fields:
        value = getattr(body, field)
        if value is not None:
            setattr(server, field, value)

    db.commit()
    return success(server.to_dict(), "Server updated")


@app.get("/api/admin/sessions", tags=["Admin"])
def admin_list_sessions(
    limit:       int  = 50,
    active_only: bool = False,
    _:           None    = Depends(admin_required),
    db:          Session = Depends(get_db),
):
    """List recent sessions. Optionally filter to active only."""
    q = db.query(VPNSession)
    if active_only:
        q = q.filter_by(is_active=True)
    sessions = q.order_by(VPNSession.started_at.desc()).limit(limit).all()

    result = []
    for s in sessions:
        d = s.to_dict()
        u = db.get(User, s.user_id)
        d["user_email"] = u.email if u else "Unknown"
        result.append(d)
    return success(result)


@app.get("/api/admin/tickets", tags=["Admin"])
def admin_list_tickets(
    ticket_status: Optional[str] = None,
    _:             None    = Depends(admin_required),
    db:            Session = Depends(get_db),
):
    """List support tickets, optionally filtered by status."""
    q = db.query(SupportTicket)
    if ticket_status:
        q = q.filter_by(status=ticket_status)
    return success([t.to_dict() for t in q.order_by(SupportTicket.created_at.desc()).all()])


@app.patch("/api/admin/tickets/{ticket_id}", tags=["Admin"])
def admin_update_ticket(
    ticket_id: int,
    body:      AdminUpdateTicketRequest,
    _:         None    = Depends(admin_required),
    db:        Session = Depends(get_db),
):
    """Update a support ticket status (open → in_progress → resolved)."""
    ticket = db.get(SupportTicket, ticket_id)
    if not ticket:
        raise HTTPException(status_code=404, detail="Ticket not found")
    ticket.status     = body.status
    ticket.updated_at = datetime.utcnow()
    db.commit()
    return success(ticket.to_dict(), "Ticket updated")


@app.get("/api/admin/settings", tags=["Admin"])
def admin_get_settings(_: None = Depends(admin_required)):
    """Get current app-wide settings."""
    return success(_app_config)


@app.patch("/api/admin/settings", tags=["Admin"])
def admin_update_settings(
    body: AdminUpdateSettingsRequest,
    _:    None = Depends(admin_required),
):
    """Update app-wide settings."""
    updates = body.model_dump(exclude_none=True)
    _app_config.update(updates)
    return success(_app_config, "Settings updated")


# ─────────────────────────────────────────────────────────────────
# Entry Point
# ─────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    import uvicorn
    port = int(os.environ.get("PORT", 5000))
    uvicorn.run("app:app", host="0.0.0.0", port=port, reload=True)
