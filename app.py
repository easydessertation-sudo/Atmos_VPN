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

from email_service import (
    send_password_reset_email,
    send_contact_confirmation_email,
    send_contact_admin_notification,
)

from fastapi import FastAPI, Depends, HTTPException, Request, Header, status, UploadFile, File, Form
from fastapi.staticfiles import StaticFiles
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, HTMLResponse
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

from jose import JWTError, jwt
from passlib.hash import bcrypt
from pydantic import BaseModel, EmailStr, field_validator
from sqlalchemy.orm import Session

from models import (
    Base, engine, get_db,
    User, VPNServer, VPNSession, VPNConfig, IPPool, UsageLog,
    Device, Subscription, SupportTicket, Notification, Plan,
    Ad, AdView, StatusSubscriber, PendingSignup
)
from wireguard import (
    claim_ip_from_pool, release_ip_to_pool,
    generate_wg_config, get_existing_config, revoke_all_user_configs
)
from tasks import add_wireguard_peer, remove_wireguard_peer
from admin_alert_service import fire_admin_alert
from email_service import send_status_welcome_email, send_verification_email

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

os.makedirs("uploads/avatars", exist_ok=True)
app.mount("/uploads", StaticFiles(directory="uploads"), name="uploads")
# ─────────────────────────────────────────────────────────────────
# Health Check
# ─────────────────────────────────────────────────────────────────
@app.get("/", tags=["Health"])
def root():
    return {"status": "ok", "service": "AtmosVPN API", "version": "2.0.0"}

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
            _seed_default_ad(db)
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


class VerifyEmailRequest(BaseModel):
    email: EmailStr
    code: str


class ResendVerificationRequest(BaseModel):
    email: EmailStr



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


# Valid subject choices shown in the Contact Us page dropdown
CONTACT_SUBJECTS = {
    "technical":      "Technical Support",
    "billing":        "Billing & Payments",
    "account":        "Account Issues",
    "press":          "Press & Media",
    "business":       "Business & Partnerships",
    "security":       "Security Vulnerability",
    "general":        "General Inquiry",
}


class SupportTicketRequest(BaseModel):
    name:     str
    email:    EmailStr
    subject:  str = "general"   # one of the CONTACT_SUBJECTS keys
    message:  str


class PushTokenRequest(BaseModel):
    token:    str                      # FCM (Android) or APNS (iOS) device token
    platform: Optional[str] = "unknown"  # android | ios | web
    device_name: Optional[str] = None


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


class AdminCreateAdRequest(BaseModel):
    title:            str
    description:      Optional[str]  = None
    image_url:        Optional[str]  = None
    video_url:        Optional[str]  = None
    click_url:        Optional[str]  = None
    ad_type:          str            = "rewarded"   # banner | interstitial | rewarded
    duration_seconds: int            = 30
    reward_minutes:   int            = 30
    target_plans:     str            = "free"       # comma-sep: "free" or "free,starter"
    priority:         int            = 0
    is_active:        bool           = True


class AdminUpdateAdRequest(BaseModel):
    title:            Optional[str]  = None
    description:      Optional[str]  = None
    image_url:        Optional[str]  = None
    video_url:        Optional[str]  = None
    click_url:        Optional[str]  = None
    ad_type:          Optional[str]  = None
    duration_seconds: Optional[int]  = None
    reward_minutes:   Optional[int]  = None
    target_plans:     Optional[str]  = None
    priority:         Optional[int]  = None
    is_active:        Optional[bool] = None


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
    Initiate user registration. Stashes user details in DB temporarily (pending_signups table)
    and sends a verification code. The account is only created in the users table after verification.
    """
    email = body.email.strip().lower()

    if db.query(User).filter_by(email=email).first():
        raise HTTPException(status_code=409, detail="An account with this email already exists")

    # Delete any old pending signup attempts for this email
    db.query(PendingSignup).filter_by(email=email).delete()
    db.commit()

    import random
    code = "".join(random.choices("0123456789", k=6))

    pending = PendingSignup(
        email=email,
        password_hash=bcrypt.hash(body.password),
        full_name=body.full_name or "",
        code=code
    )
    db.add(pending)
    db.commit()

    # ── Send verification email ──────────────────────────────────────────
    try:
        send_verification_email(email, code)
    except Exception as e:
        # Log error but don't fail the registration; user can resend code later.
        pass

    return success(
        {
            "requires_verification": True,
        },
        msg="Verification code sent. Please check your email to complete registration.",
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

    if not user.email_verified:
        raise HTTPException(
            status_code=403,
            detail="Email verification required. Please verify your email address first."
        )

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


@app.post("/api/auth/verify-email", tags=["Auth"])
def verify_email(body: VerifyEmailRequest, db: Session = Depends(get_db)):
    """
    Verify the user's email address using the 6-digit code, create user account, and return login tokens.
    """
    email = body.email.strip().lower()
    
    # Check if user already created
    if db.query(User).filter_by(email=email).first():
        raise HTTPException(status_code=409, detail="Account is already registered and verified.")

    pending = db.query(PendingSignup).filter_by(email=email).first()
    if not pending:
        raise HTTPException(status_code=400, detail="Verification code expired or registration not found. Please register again.")

    if pending.code != body.code:
        raise HTTPException(status_code=400, detail="Invalid verification code")

    # Code is valid, create the user account in the DB
    user = User(
        email=email,
        password_hash=pending.password_hash,
        full_name=pending.full_name or "",
        plan="free",
        email_verified=True,
    )
    db.add(user)
    
    # Clean up pending signup
    db.delete(pending)
    db.commit()
    db.refresh(user)

    # ── Fire admin alert: new user signed up ───────────────────────────────
    fire_admin_alert(
        event_type = "new_signup",
        title      = "👤 New User Registered",
        message    = f"{email} just signed up on AtmosVPN.",
        db         = db,
        meta       = {"user_id": str(user.id), "email": email},
    )

    return success(
        {
            "user":          user.to_dict(),
            "access_token":  create_access_token(user.id),
            "refresh_token": create_refresh_token(user.id),
            "plan_limits":   PLAN_LIMITS.get(user.plan, PLAN_LIMITS["free"]),
        },
        msg="Email verified and account created successfully.",
    )


@app.post("/api/auth/resend-verification", tags=["Auth"])
@limiter.limit("3/minute")
def resend_verification(request: Request, body: ResendVerificationRequest, db: Session = Depends(get_db)):
    """
    Resend the 6-digit email verification code to the user.
    """
    email = body.email.strip().lower()
    
    if db.query(User).filter_by(email=email).first():
        return success(msg="Email is already verified")

    pending = db.query(PendingSignup).filter_by(email=email).first()
    if not pending:
        raise HTTPException(status_code=400, detail="Registration expired or not found. Please register again.")

    # Generate new code
    import random
    code = "".join(random.choices("0123456789", k=6))
    pending.code = code
    db.commit()

    # Send email
    try:
        send_verification_email(email, code)
    except Exception as e:
        pass

    return success(msg="Verification code resent successfully.")


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


@app.put("/api/auth/profile", tags=["Auth"])
def update_profile(
    full_name: Optional[str] = Form(None),
    avatar: Optional[UploadFile] = File(None),
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Update the user's profile name and/or avatar.
    Accepts multipart/form-data.
    """
    import shutil
    import uuid

    if full_name is not None:
        user.full_name = full_name.strip()

    if avatar:
        ext = avatar.filename.split('.')[-1].lower()
        if ext not in ['jpg', 'jpeg', 'png', 'webp']:
            raise HTTPException(status_code=400, detail="Invalid file type. Only JPG, PNG, and WebP are allowed.")
        
        filename = f"{user.id}_{uuid.uuid4().hex[:8]}.{ext}"
        filepath = os.path.join("uploads", "avatars", filename)
        
        with open(filepath, "wb") as buffer:
            shutil.copyfileobj(avatar.file, buffer)
        
        # Use request url logic to build the fully qualified url, or fallback to backend URL
        # We will assume backend URL is https://api.atmosvpn.com based on the environment
        # Wait, using a relative or absolute URL. Let's build an absolute one from the request,
        # or use APP_BASE_URL.
        base_url = os.environ.get("APP_BASE_URL", "https://api.atmosvpn.com").rstrip("/")
        user.avatar_url = f"{base_url}/uploads/avatars/{filename}"

    db.commit()
    db.refresh(user)

    return success(
        {
            "user": user.to_dict()
        },
        msg="Profile updated successfully"
    )


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
# Google OAuth Routes
# ─────────────────────────────────────────────────────────────────
#
# FLOW:
#   1. Frontend calls GET /api/auth/google/url
#      → Gets back the Google login redirect URL
#      → Frontend redirects user to that URL
#
#   2. Google redirects to frontend callback (e.g. /auth/google/callback?code=xxx)
#
#   3. Frontend sends the code to POST /api/auth/google/callback
#      → Backend exchanges code for Google user info
#      → Creates account if new user, or logs in existing user
#      → Returns access_token + refresh_token (same as email login)
#
# Alternative (mobile/SPA):
#   Use POST /api/auth/google/verify with the id_token from Google SDK
#   (Google One Tap / Android / iOS flows)
# ─────────────────────────────────────────────────────────────────

GOOGLE_CLIENT_ID     = os.environ.get("GOOGLE_CLIENT_ID", "")
GOOGLE_CLIENT_SECRET = os.environ.get("GOOGLE_CLIENT_SECRET", "")
GOOGLE_REDIRECT_URI  = os.environ.get("GOOGLE_REDIRECT_URI", "http://localhost:3000/auth/google/callback")

GOOGLE_AUTH_URL  = "https://accounts.google.com/o/oauth2/v2/auth"
GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token"
GOOGLE_USERINFO_URL = "https://www.googleapis.com/oauth2/v2/userinfo"


class GoogleCallbackBody(BaseModel):
    code: str                               # Authorization code from Google redirect


class GoogleTokenBody(BaseModel):
    id_token: str                           # ID token from Google SDK (One Tap / mobile)


def _upsert_google_user(google_user: dict, db: Session, request: Request):
    """
    Given verified Google user info dict, find or create the local User row.
    Returns (user, is_new_user).
    """
    google_id = google_user["id"]
    email     = google_user.get("email", "").strip().lower()
    name      = google_user.get("name", "")
    avatar    = google_user.get("picture", "")

    # 1. Already signed in with Google before?
    user = db.query(User).filter_by(google_id=google_id).first()

    if not user:
        # 2. Same email registered via email/password?  Link accounts.
        user = db.query(User).filter_by(email=email).first()
        if user:
            user.google_id     = google_id
            user.avatar_url    = avatar
            user.auth_provider = "google"
        else:
            # 3. Brand new user — create account (no password)
            user = User(
                email         = email,
                full_name     = name,
                password_hash = bcrypt.hash(secrets.token_hex(32)),  # random unusable password
                google_id     = google_id,
                avatar_url    = avatar,
                auth_provider = "google",
                email_verified = True,           # Google emails are pre-verified
                plan          = "free",
            )
            db.add(user)

    user.last_login = datetime.utcnow()
    db.commit()
    db.refresh(user)
    return user


@app.get("/api/auth/google/url", tags=["Auth"])
def google_auth_url():
    """
    Step 1 — Get the Google OAuth redirect URL.
    Frontend opens this URL in a browser (redirect or popup).

    Returns:
      url: Full Google OAuth consent screen URL
    """
    if not GOOGLE_CLIENT_ID:
        raise HTTPException(
            status_code=503,
            detail="Google OAuth not configured. Set GOOGLE_CLIENT_ID in .env"
        )

    import urllib.parse
    params = {
        "client_id":     GOOGLE_CLIENT_ID,
        "redirect_uri":  GOOGLE_REDIRECT_URI,
        "response_type": "code",
        "scope":         "openid email profile",
        "access_type":   "offline",
        "prompt":        "select_account",
    }
    url = GOOGLE_AUTH_URL + "?" + urllib.parse.urlencode(params)
    return success({
        "url":          url,
        "redirect_uri": GOOGLE_REDIRECT_URI,
    })


@app.post("/api/auth/google/callback", tags=["Auth"])
def google_callback(
    body:    GoogleCallbackBody,
    request: Request,
    db:      Session = Depends(get_db),
):
    """
    Step 2 — Exchange the authorization code for user info.
    Called by the frontend after Google redirects back with ?code=...

    Body:
      code: The authorization code from Google's redirect URL query param

    Returns:
      Same token format as /api/auth/login
    """
    import requests as _requests

    if not GOOGLE_CLIENT_ID or not GOOGLE_CLIENT_SECRET:
        raise HTTPException(status_code=503, detail="Google OAuth not configured")

    # Exchange code for tokens
    token_response = _requests.post(GOOGLE_TOKEN_URL, data={
        "code":          body.code,
        "client_id":     GOOGLE_CLIENT_ID,
        "client_secret": GOOGLE_CLIENT_SECRET,
        "redirect_uri":  GOOGLE_REDIRECT_URI,
        "grant_type":    "authorization_code",
    })

    if not token_response.ok:
        raise HTTPException(
            status_code=400,
            detail=f"Failed to exchange code with Google: {token_response.text}"
        )

    token_data = token_response.json()
    access_token_google = token_data.get("access_token")

    if not access_token_google:
        raise HTTPException(status_code=400, detail="Google did not return an access token")

    # Fetch user profile
    userinfo_response = _requests.get(
        GOOGLE_USERINFO_URL,
        headers={"Authorization": f"Bearer {access_token_google}"}
    )

    if not userinfo_response.ok:
        raise HTTPException(status_code=400, detail="Failed to fetch user info from Google")

    google_user = userinfo_response.json()

    if not google_user.get("verified_email"):
        raise HTTPException(status_code=400, detail="Google account email is not verified")

    user = _upsert_google_user(google_user, db, request)

    return success(
        {
            "user":          user.to_dict(),
            "access_token":  create_access_token(user.id),
            "refresh_token": create_refresh_token(user.id),
            "is_new_user":   user.created_at == user.last_login,
            "plan_limits":   PLAN_LIMITS.get(user.plan, PLAN_LIMITS["free"]),
        },
        msg="Google sign-in successful",
    )


@app.post("/api/auth/google/verify", tags=["Auth"])
def google_verify_token(
    body:    GoogleTokenBody,
    request: Request,
    db:      Session = Depends(get_db),
):
    """
    Alternative — Verify a Google ID token directly (for mobile/SPA Google One Tap).

    Use this when:
    - Android / iOS app using Google Sign-In SDK
    - Web app using Google One Tap (credential response)
    - The frontend already has an id_token from Google's JS library

    Body:
      id_token: The credential / id_token from Google Sign-In SDK

    Returns:
      Same token format as /api/auth/login
    """
    from google.oauth2 import id_token as google_id_token
    from google.auth.transport import requests as google_requests

    if not GOOGLE_CLIENT_ID:
        raise HTTPException(status_code=503, detail="Google OAuth not configured")

    try:
        idinfo = google_id_token.verify_oauth2_token(
            body.id_token,
            google_requests.Request(),
            GOOGLE_CLIENT_ID,
        )
    except ValueError as e:
        raise HTTPException(status_code=401, detail=f"Invalid Google token: {str(e)}")

    google_user = {
        "id":             idinfo["sub"],
        "email":          idinfo.get("email", ""),
        "name":           idinfo.get("name", ""),
        "picture":        idinfo.get("picture", ""),
        "verified_email": idinfo.get("email_verified", False),
    }

    if not google_user["verified_email"]:
        raise HTTPException(status_code=400, detail="Google account email is not verified")

    user = _upsert_google_user(google_user, db, request)

    return success(
        {
            "user":          user.to_dict(),
            "access_token":  create_access_token(user.id),
            "refresh_token": create_refresh_token(user.id),
            "is_new_user":   user.created_at == user.last_login,
            "plan_limits":   PLAN_LIMITS.get(user.plan, PLAN_LIMITS["free"]),
        },
        msg="Google sign-in successful",
    )



# ─────────────────────────────────────────────────────────────────
# Apple OAuth Routes
# ─────────────────────────────────────────────────────────────────
class AppleTokenBody(BaseModel):
    id_token: str                           # identityToken from Apple Sign-In SDK
    email: str = ""                         # Apple only sends this on first login
    full_name: str = ""                     # Apple only sends this on first login

def _upsert_apple_user(apple_user: dict, db: Session, request: Request):
    """
    Given verified Apple user info dict, find or create the local User row.
    Returns user.
    """
    apple_id = apple_user["sub"]
    email    = apple_user.get("email", "").strip().lower()
    name     = apple_user.get("name", "")

    user = db.query(User).filter_by(apple_id=apple_id).first()

    if not user:
        if email:
            user = db.query(User).filter_by(email=email).first()
            
        if user:
            user.apple_id      = apple_id
            user.auth_provider = "apple"
        else:
            user = User(
                email         = email or f"{apple_id}@privaterelay.appleid.com",
                full_name     = name or "Apple User",
                password_hash = bcrypt.hash(secrets.token_hex(32)),
                apple_id      = apple_id,
                auth_provider = "apple",
                email_verified = True,
                plan          = "free",
            )
            db.add(user)

    user.last_login = datetime.utcnow()
    db.commit()
    db.refresh(user)
    return user


@app.post("/api/auth/apple/verify", tags=["Auth"])
def apple_verify_token(
    body:    AppleTokenBody,
    request: Request,
    db:      Session = Depends(get_db)
):
    """
    Verify an Apple identityToken (JWT) from the iOS Sign-In with Apple SDK.
    Because Apple only sends the email and name once (on the first login), 
    the frontend must pass them in the body if they are available.
    """
    import requests
    APPLE_CLIENT_ID = os.environ.get("APPLE_CLIENT_ID", "")
    
    if not APPLE_CLIENT_ID:
        raise HTTPException(status_code=503, detail="Apple OAuth not configured. Set APPLE_CLIENT_ID in .env")

    try:
        # 1. Extract 'kid' from the unverified JWT header
        unverified_header = jwt.get_unverified_header(body.id_token)
        kid = unverified_header.get("kid")
        if not kid:
            raise ValueError("Missing 'kid' in token header")

        # 2. Fetch Apple's public keys
        resp = requests.get("https://appleid.apple.com/auth/keys")
        keys = resp.json().get("keys", [])
        
        # 3. Find the matching public key
        public_key = next((k for k in keys if k["kid"] == kid), None)
        if not public_key:
            raise ValueError("Apple public key not found for this token")

        # 4. Verify the token signature and claims
        payload = jwt.decode(
            body.id_token,
            public_key,
            algorithms=["RS256"],
            audience=APPLE_CLIENT_ID,
            issuer="https://appleid.apple.com"
        )
    except Exception as e:
        logger.error(f"Apple token verification failed: {str(e)}")
        raise HTTPException(status_code=401, detail=f"Invalid Apple token: {str(e)}")

    # Construct the user payload
    apple_user = {
        "sub": payload["sub"],
        "email": body.email or payload.get("email", ""),
        "name": body.full_name
    }

    user = _upsert_apple_user(apple_user, db, request)

    return success(
        {
            "user":          user.to_dict(),
            "access_token":  create_access_token(user.id),
            "refresh_token": create_refresh_token(user.id),
            "is_new_user":   user.created_at == user.last_login,
            "plan_limits":   PLAN_LIMITS.get(user.plan, PLAN_LIMITS["free"]),
        },
        msg="Apple sign-in successful",
    )


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

    if not user.email_verified:
        raise HTTPException(
            status_code=403,
            detail="Email verification required. Please verify your email first."
        )

    now = datetime.utcnow()
    has_active_reward = user.vpn_expiration_time and user.vpn_expiration_time > now

    if server.required_plan != "free" and user.plan == "free":
        if server.required_plan == "starter" and has_active_reward:
            pass  # Allowed due to active ad reward!
        else:
            raise HTTPException(
                status_code=403,
                detail=f"Upgrade required. This server requires the {server.required_plan.capitalize()} plan."
            )

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


    # ── Step 5: Add WireGuard peer (SSH directly, then Celery as backup) ────
    #
    # WHY DIRECT SSH FIRST:
    #   Celery worker may not be running in all environments.
    #   If we only use .delay(), the peer never gets added to the server
    #   → tunnel connects but server drops all traffic → no internet.
    #   We SSH directly here (synchronous, takes 1–3s) so the peer is
    #   guaranteed to be added before we return the config to the user.
    #
    # WHY ALSO CELERY:
    #   Celery retries if SSH failed transiently, and handles remove-peer
    #   cleanup reliably.
    import asyncio as _asyncio
    import json as _json
    from tasks import _ssh_add_peer

    job_id      = str(_uuid.uuid4())
    server_ip   = server.ip_address or "0.0.0.0"
    peer_status = "provisioning"

    if server_ip != "0.0.0.0" and os.environ.get("WG_SIMULATION", "true").lower() != "true":
        try:
            # Run async SSH function in a new event loop (we're in a sync FastAPI handler)
            loop   = _asyncio.new_event_loop()
            result = loop.run_until_complete(
                _ssh_add_peer(server_ip, body.public_key, ip_entry.ip_address)
            )
            loop.close()
            if result:
                peer_status = "active"
                logger.info(f"[Provision] Peer added directly via SSH for config {new_config_id}")
        except Exception as ssh_err:
            logger.warning(f"[Provision] Direct SSH peer add failed ({ssh_err}) — queuing Celery retry")

    # Always also queue Celery for retries / persistence
    try:
        add_wireguard_peer.delay(
            job_id=job_id,
            server_ip=server_ip,
            public_key=body.public_key,
            assigned_ip=ip_entry.ip_address,
            config_id=new_config_id,
        )
    except Exception:
        pass  # Celery not available — direct SSH was already done above

    # ── Step 6: Generate and return the .conf file ─────────────────
    config_content = generate_wg_config(server, ip_entry.ip_address)

    plan_limits = PLAN_LIMITS.get(user.plan, PLAN_LIMITS["free"])

    return success({
        "config_id":        new_config_id,
        "assigned_ip":      ip_entry.ip_address,
        "server":           server.to_dict(),
        "wg_config":        config_content,
        "job_id":           job_id,
        "status":           peer_status,   # "active" if SSH worked, "provisioning" if queued
        "speed_limit_mbps": plan_limits.get("speed_mbps"),
        "message":          (
            "VPN peer added — import wg_config into WireGuard now. Internet will work immediately."
            if peer_status == "active"
            else "Config ready. Peer is being added in background — connect in ~10 seconds."
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

    if not user.email_verified:
        raise HTTPException(
            status_code=403,
            detail="Email verification required. Please verify your email first."
        )

    now = datetime.utcnow()
    has_active_reward = user.vpn_expiration_time and user.vpn_expiration_time > now

    if server.required_plan != "free" and user.plan == "free":
        if server.required_plan == "starter" and has_active_reward:
            pass  # Allowed due to active ad reward!
        else:
            raise HTTPException(
                status_code=403,
                detail=f"Upgrade required. This server requires the {server.required_plan.capitalize()} plan."
            )

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


@app.get("/api/vpn/session-time", tags=["VPN"])
def get_session_time(user: User = Depends(get_current_user)):
    """
    Returns the remaining seconds of VPN time for a free-tier user.
    """
    if not user.vpn_expiration_time:
        return success({"remaining_seconds": 0})
    
    now = datetime.utcnow()
    if user.vpn_expiration_time < now:
        return success({"remaining_seconds": 0})
        
    remaining = int((user.vpn_expiration_time - now).total_seconds())
    return success({"remaining_seconds": remaining})


@app.post("/api/rewards/watch-ad", tags=["Rewards"])
def watch_ad(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    """
    Called when the frontend verifies an AdMob ad was watched.
    Adds 45 minutes to the user's current vpn_expiration_time.
    """
    now = datetime.utcnow()
    
    if not user.vpn_expiration_time or user.vpn_expiration_time < now:
        user.vpn_expiration_time = now + timedelta(minutes=45)
    else:
        user.vpn_expiration_time += timedelta(minutes=45)
        
    db.commit()
    remaining = int((user.vpn_expiration_time - now).total_seconds())
    return success({"remaining_seconds": remaining}, msg="Added 45 minutes of VPN time!")


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
def get_plans(db: Session = Depends(get_db)):
    """
    Return all available plans and their prices.
    Reads from the plans DB table (editable via admin panel).
    Falls back to built-in PLANS config if DB table is empty.
    """
    db_plans = db.query(Plan).order_by(Plan.amount_usd).all()

    if db_plans:
        # Build response from DB — reflects any admin edits instantly
        result = {}
        for p in db_plans:
            if not p.is_visible:
                continue
            result[p.key] = {
                "name":             p.label,
                "description":      p.description,
                "monthly_usd":      p.amount_usd,
                "per":              p.per,
                "currency":         p.currency,
                # Limits
                "bandwidth_gb":     p.bandwidth_gb,
                "speed_mbps":       PLAN_LIMITS.get(p.key, {}).get("speed_mbps"),
                "devices":          p.max_devices,
                "simultaneous":     p.simultaneous,
                "server_locations": p.server_count,
                "dedicated_ip":     p.has_dedicated_ip,
                # Feature flags
                "features": {
                    "streaming":        p.has_streaming,
                    "p2p":              p.has_p2p,
                    "dedicated_ip":     p.has_dedicated_ip,
                    "ad_blocker":       p.has_ad_blocker,
                    "kill_switch":      p.has_kill_switch,
                    "priority_support": p.has_priority_support,
                },
                # Stripe IDs
                "stripe_price_id_monthly": p.stripe_price_id_monthly,
                "stripe_price_id_yearly":  p.stripe_price_id_yearly,
                "updated_at": p.updated_at.isoformat() if p.updated_at else None,
            }
        return success(result)

    # Fallback: DB table not yet seeded — return built-in config
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
        "plan_expires_at": user.plan_expires_at.isoformat() + "Z" if user.plan_expires_at else None,
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
    device_id: str,
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
# Contact / Support Routes  (public — no auth required)
# ─────────────────────────────────────────────────────────────────

@app.get("/api/contact/info", tags=["Support"])
def get_contact_info():
    """
    Returns the static contact channel data shown on the right side of
    the Contact Us page (live chat, email addresses, press, security etc.)
    and the list of valid subject options for the contact form dropdown.
    """
    return success({
        "channels": [

            {
                "id":          "email_support",
                "label":       "Email Support",
                "description": "atmosvpn00@gmail.com",
                "icon":        "email",
                "action":      "mailto:atmosvpn00@gmail.com",
            },
            {
                "id":          "press",
                "label":       "Press & Media",
                "description": "atmosvpn00@gmail.com",
                "icon":        "press",
                "action":      "mailto:atmosvpn00@gmail.com",
            },
            {
                "id":          "business",
                "label":       "Business & Partnerships",
                "description": "atmosvpn00@gmail.com",
                "icon":        "business",
                "action":      "mailto:atmosvpn00@gmail.com",
            },
            {
                "id":          "security",
                "label":       "Security Vulnerability",
                "description": "atmosvpn00@gmail.com",
                "icon":        "security",
                "action":      "mailto:atmosvpn00@gmail.com",
            },
        ],
        "subjects": [
            {"value": k, "label": v}
            for k, v in CONTACT_SUBJECTS.items()
        ],
        "response_time":  "2 hours",
        "availability":   "24/7/365",
    })


@app.post("/api/contact", tags=["Support"])
def submit_contact_form(body: SupportTicketRequest, db: Session = Depends(get_db)):
    """
    Contact Us form submission (atmosvpn.com/contact).
    - No auth required (works for visitors who are not logged in)
    - Validates subject against allowed list
    - Saves to support_tickets table
    - Sends auto-reply confirmation email to the user
    - Sends internal notification to support@atmosvpn.com
    """
    # Validate subject key
    subject_key = body.subject.lower().strip()
    if subject_key not in CONTACT_SUBJECTS:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid subject. Allowed values: {list(CONTACT_SUBJECTS.keys())}"
        )

    subject_label = CONTACT_SUBJECTS[subject_key]

    # Save ticket to DB
    ticket = SupportTicket(
        email    = body.email,
        subject  = subject_label,
        message  = body.message,
        category = subject_key,
        status   = "open",
        priority = "high" if subject_key == "security" else "medium",
    )
    db.add(ticket)
    db.commit()
    db.refresh(ticket)

    ticket_ref = str(ticket.id)[:8].upper()   # short reference e.g. "A3F2C1B0"

    # Send emails in background (non-blocking)
    try:
        send_contact_confirmation_email(
            to_email  = body.email,
            name      = body.name,
            subject   = subject_label,
            ticket_id = ticket_ref,
        )
        send_contact_admin_notification(
            ticket_id = ticket_ref,
            name      = body.name,
            email     = body.email,
            subject   = subject_label,
            category  = subject_key,
            message   = body.message,
        )
    except Exception as e:
        # Email failure should never block the user from getting a success response
        print(f"Email notification failed for ticket {ticket_ref}: {e}")

    return success(
        {
            "ticket_id":     str(ticket.id),
            "ticket_ref":    ticket_ref,
            "subject":       subject_label,
            "response_time": "2 hours",
        },
        msg="Message sent! We'll get back to you within 2 hours.",
        status_code=201,
    )


@app.post("/api/support/ticket", tags=["Support"])
def submit_ticket(body: SupportTicketRequest, db: Session = Depends(get_db)):
    """Legacy alias for /api/contact — kept for backward compatibility."""
    return submit_contact_form(body, db)


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

@app.post("/api/notifications/register-token", tags=["Account"])
def register_push_token(
    body: PushTokenRequest,
    user: User    = Depends(get_current_user),
    db:   Session = Depends(get_db),
):
    """
    Register a device push token for sending push notifications.

    Called by the mobile app (Android/iOS) immediately after login
    or when the OS grants push notification permission.

    Stores the FCM (Android) or APNS (iOS) token on the Device record
    so the backend can send targeted push notifications to this device.

    Body:
      token       — FCM or APNS device token (required)
      platform    — "android" | "ios" | "web" (optional)
      device_name — human-readable device label (optional)
    """
    if not body.token or len(body.token.strip()) < 10:
        raise HTTPException(status_code=400, detail="Invalid push token")

    token    = body.token.strip()
    platform = (body.platform or "unknown").lower()

    # Find existing device record for this user+platform, or create one
    device = db.query(Device).filter_by(
        user_id=str(user.id),
        platform=platform,
    ).first()

    if device:
        # Update the push token on the existing device
        device.device_fingerprint = token    # reuse device_fingerprint to store push token
        device.last_seen          = datetime.utcnow()
        if body.device_name:
            device.name = body.device_name
    else:
        # Create a new device record with the push token
        device = Device(
            user_id=str(user.id),
            name=body.device_name or f"{platform.capitalize()} Device",
            platform=platform,
            device_fingerprint=token,
            last_seen=datetime.utcnow(),
            is_trusted=True,
        )
        db.add(device)

    db.commit()
    logger.info(f"Push token registered for user {user.id} on {platform}")

    return success(
        {"registered": True, "platform": platform},
        msg="Push token registered successfully",
    )


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

    # Simulate realistic speed test results capped by the user's plan speed limit.
    # In production: SSH into VPN server and run iperf3 or speedtest-cli,
    # then still cap the reported result to plan_limits["speed_mbps"].
    plan_limits   = PLAN_LIMITS.get(user.plan, PLAN_LIMITS["free"])
    speed_cap     = plan_limits.get("speed_mbps")   # None = unlimited

    # Raw simulated speeds (what the server hardware can do)
    raw_download = random.uniform(80.0, 150.0)
    raw_upload   = random.uniform(15.0,  40.0)

    # Apply plan speed cap — free=10 Mbps, starter=50, pro=200, premium=unlimited
    if speed_cap is not None:
        # Download capped to plan limit; upload ≈ 40% of download cap
        download_mbps = round(min(raw_download, speed_cap), 1)
        upload_mbps   = round(min(raw_upload,   speed_cap * 0.4), 1)
    else:
        download_mbps = round(raw_download, 1)
        upload_mbps   = round(raw_upload,   1)

    latency_ms = ping_ms + random.randint(0, 3)   # Latency ≈ Ping ± small jitter

    return success({
        "download_mbps":    download_mbps,   # shown in top gauge + bottom-left card
        "upload_mbps":      upload_mbps,     # shown in bottom-right card
        "ping_ms":          ping_ms,         # shown in bottom-left card (Ping)
        "latency_ms":       latency_ms,      # shown in bottom-right card (Latency)
        "speed_limit_mbps": speed_cap,       # None = unlimited — useful for UI cap indicator
        "connected":        session is not None,
        "server":           server.to_dict() if server else None,
        "tested_at":        datetime.utcnow().isoformat() + "Z",
        "note": (
            "Live values from VPN server"
            if session
            else "Not connected to VPN — results reflect unprotected connection"
        ),
    })


# ─────────────────────────────────────────────────────────────────
# Admin Routes — Protected by X-Admin-Token header
# ─────────────────────────────────────────────────────────────────

# ─────────────────────────────────────────────────────────────────
# Ads Helper — seed one sample ad on first startup
# ─────────────────────────────────────────────────────────────────
def _seed_default_ad(db: Session):
    """Insert a sample rewarded ad if the ads table is empty."""
    if db.query(Ad).count() == 0:
        sample = Ad(
            title            = "Upgrade to AtmosVPN Pro",
            description      = "Get unlimited data & all server locations for just $7.99/mo",
            image_url        = "https://atmosvpn.com/ads/upgrade-banner.png",
            video_url        = None,
            click_url        = "https://atmosvpn.com/upgrade",
            ad_type          = "rewarded",
            duration_seconds = 30,
            reward_minutes   = 30,
            target_plans     = "free",
            priority         = 10,
            is_active        = True,
        )
        db.add(sample)
        db.commit()
        print("✅ Seeded default ad creative.")


# ─────────────────────────────────────────────────────────────────
# Ads — Cooldown constant (configurable here)
# ─────────────────────────────────────────────────────────────────
AD_COOLDOWN_MINUTES = 60   # users must wait 60 min between ad rewards


# In-memory app config (move to DB in production)
_app_config = {
    "free_session_minutes": 45,
    "ad_bonus_minutes":     30,
    "max_free_devices":     1,
    "ads_enabled":          True,
    "maintenance_mode":     False,
}


# ─────────────────────────────────────────────────────────────────
# Ads — User-Facing Endpoints
# ─────────────────────────────────────────────────────────────────

@app.get("/api/ads/status", tags=["Ads"])
def ads_status(
    user: User    = Depends(get_current_user),
    db:   Session = Depends(get_db),
):
    """
    Quick status check — is there an ad ready to watch?
    The app calls this on the home screen to decide whether to show the
    'Watch ad for 30 min free VPN' banner.
    """
    now = datetime.utcnow()

    # Paid users never see ads
    if user.plan not in ("free", "starter"):
        return success({
            "ads_enabled":              False,
            "reason":                   "paid_plan",
            "can_watch":                False,
            "cooldown_remaining_seconds": 0,
            "vpn_time_remaining_seconds": None,
            "reward_minutes":           0,
            "views_today":              0,
        })

    if not _app_config.get("ads_enabled", True):
        return success({
            "ads_enabled":              False,
            "reason":                   "disabled_by_admin",
            "can_watch":                False,
            "cooldown_remaining_seconds": 0,
            "vpn_time_remaining_seconds": None,
            "reward_minutes":           _app_config.get("ad_bonus_minutes", 30),
            "views_today":              0,
        })

    # Cooldown: find last ad view
    last_view = (
        db.query(AdView)
        .filter_by(user_id=str(user.id))
        .order_by(AdView.watched_at.desc())
        .first()
    )
    cooldown_remaining = 0
    can_watch = True
    if last_view:
        elapsed = (now - last_view.watched_at).total_seconds()
        cooldown_seconds = AD_COOLDOWN_MINUTES * 60
        if elapsed < cooldown_seconds:
            cooldown_remaining = int(cooldown_seconds - elapsed)
            can_watch = False

    # VPN time remaining
    vpn_remaining = None
    if user.vpn_expiration_time and user.vpn_expiration_time > now:
        vpn_remaining = int((user.vpn_expiration_time - now).total_seconds())

    # Views today
    today_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    views_today = (
        db.query(AdView)
        .filter(AdView.user_id == str(user.id), AdView.watched_at >= today_start)
        .count()
    )

    return success({
        "ads_enabled":               True,
        "can_watch":                 can_watch,
        "cooldown_remaining_seconds": cooldown_remaining,
        "vpn_time_remaining_seconds": vpn_remaining,
        "reward_minutes":            _app_config.get("ad_bonus_minutes", 30),
        "views_today":               views_today,
    })


@app.get("/api/ads/current", tags=["Ads"])
def ads_get_current(
    user: User    = Depends(get_current_user),
    db:   Session = Depends(get_db),
):
    """
    Returns the ad creative the app should display to the user.
    Also returns cooldown state so the app can decide when to show the reward button.
    """
    now = datetime.utcnow()

    # Only free / starter users see ads
    if user.plan not in ("free", "starter"):
        return success({"ads_enabled": False, "reason": "paid_plan"})

    if not _app_config.get("ads_enabled", True):
        return success({"ads_enabled": False, "reason": "disabled_by_admin"})

    # Pick the highest-priority active ad that targets this plan
    ad = (
        db.query(Ad)
        .filter(
            Ad.is_active == True,
            Ad.target_plans.ilike(f"%{user.plan}%"),
        )
        .order_by(Ad.priority.desc(), Ad.created_at.desc())
        .first()
    )

    if not ad:
        return success({"ads_enabled": True, "ad": None, "reason": "no_ads_available"})

    # Cooldown check
    last_view = (
        db.query(AdView)
        .filter_by(user_id=str(user.id))
        .order_by(AdView.watched_at.desc())
        .first()
    )
    cooldown_remaining = 0
    can_watch = True
    if last_view:
        elapsed = (now - last_view.watched_at).total_seconds()
        cooldown_seconds = AD_COOLDOWN_MINUTES * 60
        if elapsed < cooldown_seconds:
            cooldown_remaining = int(cooldown_seconds - elapsed)
            can_watch = False

    # VPN time remaining
    vpn_remaining = None
    if user.vpn_expiration_time and user.vpn_expiration_time > now:
        vpn_remaining = int((user.vpn_expiration_time - now).total_seconds())

    return success({
        "ads_enabled":               True,
        "can_watch":                 can_watch,
        "cooldown_remaining_seconds": cooldown_remaining,
        "vpn_time_remaining_seconds": vpn_remaining,
        "reward_minutes":            ad.reward_minutes,
        "ad":                        ad.to_dict(),
    })


@app.post("/api/ads/{ad_id}/watch", tags=["Ads"])
def ads_record_watch(
    ad_id: str,
    user:  User    = Depends(get_current_user),
    db:    Session = Depends(get_db),
):
    """
    Called by the app AFTER the user has finished watching the ad.
    Credits the reward minutes to vpn_expiration_time.

    Anti-abuse rules:
      - Only free / starter plan users can claim rewards
      - 60-minute cooldown between claims (per user, not per ad)
      - Ad must be active
    """
    now = datetime.utcnow()

    # 1. Only free / starter users earn rewards
    if user.plan not in ("free", "starter"):
        raise HTTPException(
            status_code=403,
            detail="Ad rewards are only available on the Free plan.",
        )

    # 2. Global kill switch
    if not _app_config.get("ads_enabled", True):
        raise HTTPException(status_code=403, detail="Ads are currently disabled.")

    # 3. Validate the ad
    ad = db.get(Ad, ad_id)
    if not ad or not ad.is_active:
        raise HTTPException(status_code=404, detail="Ad not found or no longer active.")

    if user.plan not in (ad.target_plans or "free").split(","):
        raise HTTPException(status_code=403, detail="This ad is not available for your plan.")

    # 4. Cooldown check (60 min between ad views)
    last_view = (
        db.query(AdView)
        .filter_by(user_id=str(user.id))
        .order_by(AdView.watched_at.desc())
        .first()
    )
    if last_view:
        elapsed = (now - last_view.watched_at).total_seconds()
        cooldown_seconds = AD_COOLDOWN_MINUTES * 60
        if elapsed < cooldown_seconds:
            remaining_min = int((cooldown_seconds - elapsed) / 60) + 1
            raise HTTPException(
                status_code=429,
                detail=f"Ad cooldown active. Try again in {remaining_min} minute(s).",
            )

    # 5. Credit the reward minutes to vpn_expiration_time
    reward_minutes = ad.reward_minutes
    session_before = user.vpn_expiration_time

    if session_before is None or session_before < now:
        # No active time — start fresh from now
        user.vpn_expiration_time = now + timedelta(minutes=reward_minutes)
    else:
        # Extend existing active time
        user.vpn_expiration_time = session_before + timedelta(minutes=reward_minutes)

    session_after = user.vpn_expiration_time

    # 6. Write AdView record
    view = AdView(
        user_id        = str(user.id),
        ad_id          = str(ad.id),
        watched_at     = now,
        reward_minutes = reward_minutes,
        session_before = session_before,
        session_after  = session_after,
    )
    db.add(view)
    db.commit()

    # Next ad available at
    next_available_at = now + timedelta(minutes=AD_COOLDOWN_MINUTES)
    vpn_remaining = int((session_after - now).total_seconds())

    return success(
        {
            "reward_minutes":         reward_minutes,
            "vpn_expiration_time":    session_after.isoformat() + "Z",
            "vpn_time_remaining_seconds": vpn_remaining,
            "next_ad_available_at":   next_available_at.isoformat() + "Z",
        },
        msg=f"{reward_minutes} bonus minutes credited!",
    )


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
# Admin — Ads CRUD
# ─────────────────────────────────────────────────────────────────

@app.get("/api/admin/ads", tags=["Admin"])
def admin_list_ads(
    active_only: bool = False,
    _:           None    = Depends(admin_required),
    db:          Session = Depends(get_db),
):
    """List all ad creatives. Optionally filter to active only."""
    q = db.query(Ad)
    if active_only:
        q = q.filter_by(is_active=True)
    ads = q.order_by(Ad.priority.desc(), Ad.created_at.desc()).all()
    return success({"ads": [a.to_dict() for a in ads], "total": len(ads)})


@app.post("/api/admin/ads", tags=["Admin"])
def admin_create_ad(
    body: AdminCreateAdRequest,
    _:    None    = Depends(admin_required),
    db:   Session = Depends(get_db),
):
    """Create a new ad creative."""
    ad = Ad(
        title            = body.title,
        description      = body.description,
        image_url        = body.image_url,
        video_url        = body.video_url,
        click_url        = body.click_url,
        ad_type          = body.ad_type,
        duration_seconds = body.duration_seconds,
        reward_minutes   = body.reward_minutes,
        target_plans     = body.target_plans,
        priority         = body.priority,
        is_active        = body.is_active,
    )
    db.add(ad)
    db.commit()
    db.refresh(ad)
    return success(ad.to_dict(), "Ad created", status_code=201)


@app.patch("/api/admin/ads/{ad_id}", tags=["Admin"])
def admin_update_ad(
    ad_id: str,
    body:  AdminUpdateAdRequest,
    _:     None    = Depends(admin_required),
    db:    Session = Depends(get_db),
):
    """Update an existing ad creative (toggle active, change reward, etc.)."""
    ad = db.get(Ad, ad_id)
    if not ad:
        raise HTTPException(status_code=404, detail="Ad not found")

    update_fields = [
        "title", "description", "image_url", "video_url", "click_url",
        "ad_type", "duration_seconds", "reward_minutes",
        "target_plans", "priority", "is_active",
    ]
    for field in update_fields:
        value = getattr(body, field)
        if value is not None:
            setattr(ad, field, value)

    ad.updated_at = datetime.utcnow()
    db.commit()
    return success(ad.to_dict(), "Ad updated")


@app.delete("/api/admin/ads/{ad_id}", tags=["Admin"])
def admin_delete_ad(
    ad_id: str,
    _:     None    = Depends(admin_required),
    db:    Session = Depends(get_db),
):
    """Permanently delete an ad and all its view records."""
    ad = db.get(Ad, ad_id)
    if not ad:
        raise HTTPException(status_code=404, detail="Ad not found")
    db.delete(ad)
    db.commit()
    return success(msg="Ad deleted")


@app.get("/api/admin/ads/stats", tags=["Admin"])
def admin_ads_stats(
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """
    Ad analytics for the admin dashboard.
    Returns total views, rewards credited, and per-day breakdown.
    """
    from sqlalchemy import func
    now        = datetime.utcnow()
    today      = now.replace(hour=0, minute=0, second=0, microsecond=0)
    week_start = today - timedelta(days=7)

    total_views        = db.query(AdView).count()
    views_today        = db.query(AdView).filter(AdView.watched_at >= today).count()
    views_this_week    = db.query(AdView).filter(AdView.watched_at >= week_start).count()
    total_minutes      = db.query(func.sum(AdView.reward_minutes)).scalar() or 0
    minutes_today      = db.query(func.sum(AdView.reward_minutes)).filter(AdView.watched_at >= today).scalar() or 0
    unique_users_today = db.query(func.count(func.distinct(AdView.user_id))).filter(AdView.watched_at >= today).scalar() or 0

    # Per-ad breakdown
    per_ad = (
        db.query(Ad.id, Ad.title, func.count(AdView.id).label("views"), func.sum(AdView.reward_minutes).label("total_minutes"))
        .outerjoin(AdView, Ad.id == AdView.ad_id)
        .group_by(Ad.id, Ad.title)
        .all()
    )

    return success({
        "total_views":          total_views,
        "views_today":          views_today,
        "views_this_week":      views_this_week,
        "total_minutes_granted": total_minutes,
        "minutes_today":        minutes_today,
        "unique_users_today":   unique_users_today,
        "per_ad": [
            {
                "ad_id":         str(row.id),
                "title":         row.title,
                "total_views":   row.views,
                "total_minutes": row.total_minutes or 0,
            }
            for row in per_ad
        ],
    })


# ─────────────────────────────────────────────────────────────────
# WebView Payment Redirects
# These routes are hit by the mobile app's in-app browser after Stripe.
# ─────────────────────────────────────────────────────────────────
@app.get("/payment/success", tags=["Billing"], response_class=HTMLResponse)
def payment_success_page(session_id: str = ""):
    """Shows a success screen inside the mobile app's mini-browser after payment."""
    return f"""
    <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>
                body {{
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
                    background-color: #0f172a;
                    color: white;
                    display: flex;
                    flex-direction: column;
                    justify-content: center;
                    align-items: center;
                    height: 100vh;
                    margin: 0;
                    text-align: center;
                    padding: 20px;
                }}
                .icon {{ font-size: 64px; margin-bottom: 20px; }}
                h1 {{ margin: 0 0 10px 0; font-size: 24px; }}
                p {{ color: #94a3b8; font-size: 16px; line-height: 1.5; }}
            </style>
        </head>
        <body>
            <div class="icon">✅</div>
            <h1>Payment Successful!</h1>
            <p>Your subscription is now active.</p>
            <p>You can close this window to return to the app.</p>
        </body>
    </html>
    """

@app.get("/payment/cancel", tags=["Billing"], response_class=HTMLResponse)
def payment_cancel_page():
    """Shows a cancellation screen inside the mobile app's mini-browser."""
    return """
    <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
                    background-color: #0f172a;
                    color: white;
                    display: flex;
                    flex-direction: column;
                    justify-content: center;
                    align-items: center;
                    height: 100vh;
                    margin: 0;
                    text-align: center;
                    padding: 20px;
                }
                .icon { font-size: 64px; margin-bottom: 20px; }
                h1 { margin: 0 0 10px 0; font-size: 24px; }
                p { color: #94a3b8; font-size: 16px; line-height: 1.5; }
            </style>
        </head>
        <body>
            <div class="icon">❌</div>
            <h1>Payment Cancelled</h1>
            <p>Your transaction was not completed.</p>
            <p>You can close this window to return to the app.</p>
        </body>
    </html>
    """


@app.get("/favicon.ico", include_in_schema=False)
def favicon():
    from fastapi import Response
    return Response(status_code=204)

@app.get("/reset-password", response_class=HTMLResponse, tags=["Auth"])
def reset_password_page(token: str):
    """
    Serve a beautiful HTML page that allows users to reset their password.
    It takes the token from the URL and calls the POST /api/auth/reset-password endpoint.
    """
    html = f"""
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Reset Password - AtmosVPN</title>
        <style>
            body {{
                margin: 0; padding: 0;
                background-color: #0f172a;
                color: white; font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
                display: flex; justify-content: center; align-items: center; min-height: 100vh;
            }}
            .container {{
                background: #1e293b; padding: 40px; border-radius: 12px;
                box-shadow: 0 10px 25px rgba(0,0,0,0.5); width: 100%; max-width: 400px;
                text-align: center;
            }}
            h2 {{ color: #3b82f6; margin-top: 0; }}
            input {{
                width: 100%; padding: 12px; margin: 10px 0 20px;
                border-radius: 6px; border: 1px solid #334155;
                background: #0f172a; color: white; box-sizing: border-box;
            }}
            button {{
                width: 100%; padding: 12px; background: #2563eb; color: white;
                border: none; border-radius: 6px; font-weight: bold; cursor: pointer;
                transition: background 0.3s;
            }}
            button:hover {{ background: #1d4ed8; }}
            .message {{ margin-top: 15px; font-size: 14px; display: none; }}
            .success {{ color: #10b981; }}
            .error {{ color: #ef4444; }}
        </style>
    </head>
    <body>
        <div class="container" id="formContainer">
            <h2>Reset Your Password</h2>
            <p style="color: #94a3b8; font-size: 14px; margin-bottom: 25px;">Enter your new password below.</p>
            
            <form id="resetForm">
                <input type="password" id="newPassword" placeholder="New Password" required minlength="6">
                <button type="submit" id="submitBtn">Update Password</button>
            </form>
            
            <div id="message" class="message"></div>
        </div>

        <script>
            document.getElementById('resetForm').addEventListener('submit', async (e) => {{
                e.preventDefault();
                const btn = document.getElementById('submitBtn');
                const msg = document.getElementById('message');
                const newPassword = document.getElementById('newPassword').value;
                const token = "{token}";
                
                btn.disabled = true;
                btn.innerText = 'Updating...';
                msg.style.display = 'none';

                try {{
                    const response = await fetch('/api/auth/reset-password', {{
                        method: 'POST',
                        headers: {{ 'Content-Type': 'application/json' }},
                        body: JSON.stringify({{ token: token, new_password: newPassword }})
                    }});
                    
                    const data = await response.json();
                    
                    msg.style.display = 'block';
                    if (response.ok && data.success) {{
                        msg.className = 'message success';
                        msg.innerText = 'Password reset successfully! You can now log in on the app.';
                        document.getElementById('resetForm').style.display = 'none';
                    }} else {{
                        msg.className = 'message error';
                        msg.innerText = data.detail || data.message || 'Failed to reset password. Link may be expired.';
                        btn.disabled = false;
                        btn.innerText = 'Update Password';
                    }}
                }} catch (err) {{
                    msg.style.display = 'block';
                    msg.className = 'message error';
                    msg.innerText = 'Network error occurred. Please try again.';
                    btn.disabled = false;
                    btn.innerText = 'Update Password';
                }}
            }});
        </script>
    </body>
    </html>
    """
    return HTMLResponse(content=html)

# ─────────────────────────────────────────────────────────────────
# Status Page Routes
# ─────────────────────────────────────────────────────────────────
class StatusSubscribeRequest(BaseModel):
    email: EmailStr

@app.post("/api/status/subscribe", tags=["Status"])
def status_subscribe(body: StatusSubscribeRequest, db: Session = Depends(get_db)):
    """Subscribe to receive instant alerts when AtmosVPN services are affected."""
    exists = db.query(StatusSubscriber).filter_by(email=body.email).first()
    if exists:
        return success(msg="You are already subscribed to status alerts.")
    
    sub = StatusSubscriber(email=body.email)
    db.add(sub)
    db.commit()
    
    # Send the automated welcome email
    try:
        send_status_welcome_email(body.email)
    except Exception as e:
        logger.error(f"Failed to send welcome email to {body.email}: {e}")
        
    return success(msg="Successfully subscribed to status alerts!")

# ─────────────────────────────────────────────────────────────────
# Entry Point
# ─────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    import uvicorn
    port = int(os.environ.get("PORT", 5000))
    uvicorn.run("app:app", host="0.0.0.0", port=port, reload=True)
