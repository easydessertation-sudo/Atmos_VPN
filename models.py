"""
SecureVPN — Database Models
Plain SQLAlchemy — PostgreSQL (Supabase) | SQLite (local dev fallback)

Key design decisions:
  - UUIDs for all primary keys (security + multi-server scale)
  - ip_pool table prevents duplicate IP assignment (race-condition safe)
  - vpn_configs stores WireGuard device identities (permanent, per device)
  - usage_logs tracks bytes only — ZERO browsing/traffic logging (no-logs policy)
  - Indexes on all frequently queried columns (performance at scale)
"""
import os
import uuid
from datetime import datetime

from dotenv import load_dotenv
from sqlalchemy import (
    create_engine, Column, String, Boolean,
    DateTime, BigInteger, Text, ForeignKey,
    Integer, Index, UniqueConstraint, Float
)
from sqlalchemy.dialects.postgresql import UUID as PG_UUID
from sqlalchemy.orm import declarative_base, sessionmaker, relationship
from sqlalchemy.types import TypeDecorator, CHAR
import uuid as _uuid

# ─────────────────────────────────────────────────────────────────
# Load .env file
# ─────────────────────────────────────────────────────────────────
load_dotenv()

# ─────────────────────────────────────────────────────────────────
# Cross-database UUID type
# Works with PostgreSQL (native UUID) and SQLite (stored as CHAR(36))
# ─────────────────────────────────────────────────────────────────
class GUID(TypeDecorator):
    """
    Platform-independent UUID type.
    - PostgreSQL: Uses native UUID column
    - SQLite: Stores as CHAR(36) string

    This means our models work in BOTH environments without change.
    """
    impl = CHAR
    cache_ok = True

    def load_dialect_impl(self, dialect):
        if dialect.name == "postgresql":
            return dialect.type_descriptor(PG_UUID())
        return dialect.type_descriptor(CHAR(36))

    def process_bind_param(self, value, dialect):
        if value is None:
            return value
        if dialect.name == "postgresql":
            return str(value)
        if not isinstance(value, _uuid.UUID):
            return str(_uuid.UUID(value))
        return str(value)

    def process_result_value(self, value, dialect):
        if value is None:
            return value
        if not isinstance(value, _uuid.UUID):
            return _uuid.UUID(value)
        return value


def new_uuid():
    """Generate a new UUID. Used as the default for primary keys."""
    return str(uuid.uuid4())


# ─────────────────────────────────────────────────────────────────
# Database Setup
# ─────────────────────────────────────────────────────────────────
BASE_DIR     = os.path.dirname(os.path.abspath(__file__))
DATABASE_URL = os.environ.get(
    "DATABASE_URL",
    f"sqlite:///{os.path.join(BASE_DIR, 'securevpn.db')}"   # fallback for local dev only
)

# SQLite needs check_same_thread=False; PostgreSQL does NOT need it
_connect_args = {"check_same_thread": False} if DATABASE_URL.startswith("sqlite") else {"connect_timeout": 10}

# Connection pool settings (PostgreSQL / Supabase):
#   pool_size=10       — keep up to 10 warm connections (Supabase free tier allows ~20 total)
#   max_overflow=10    — allow 10 burst connections under heavy load  (total max 20)
#   pool_pre_ping=True — health-check every connection before use (drops stale sockets fast)
#   pool_recycle=120   — replace connections after 2 min; Supabase drops idle sockets at ~120s
#   pool_timeout=30    — raise after 30 s if no connection is available (prevents request hang)
_engine_kwargs = dict(connect_args=_connect_args)
if not DATABASE_URL.startswith("sqlite"):
    _engine_kwargs.update(
        pool_size=10,
        max_overflow=10,
        pool_pre_ping=True,
        pool_recycle=120,
        pool_timeout=30,
    )

engine       = create_engine(DATABASE_URL, **_engine_kwargs)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base         = declarative_base()


def get_db():
    """
    FastAPI dependency — yields a database session for each request.
    Always closes the session after the request finishes (even if it crashes).
    Usage:  db: Session = Depends(get_db)
    """
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


# ─────────────────────────────────────────────────────────────────
# TABLE 1: users
# Stores every registered user account
# ─────────────────────────────────────────────────────────────────
class User(Base):
    __tablename__ = "users"

    # UUID primary key — unpredictable, safe to expose in APIs
    id = Column(GUID, primary_key=True, default=new_uuid)

    # Core account fields
    email         = Column(String(255), unique=True, nullable=False, index=True)
    password_hash = Column(String(255), nullable=False)   # bcrypt hash ONLY — never plain text
    full_name     = Column(String(255))

    # Subscription plan
    # Values: "free" | "essential" | "elite" | "ultimate"
    plan            = Column(String(50), default="free")
    plan_expires_at = Column(DateTime)

    # Subscription status from Stripe
    # Values: "inactive" | "active" | "past_due" | "cancelled" | "suspended"
    subscription_status = Column(String(50), default="inactive")

    # Stripe integration — links this user to their Stripe customer record
    stripe_customer_id = Column(String(255), index=True)

    # Bandwidth tracking (document says 100GB default limit)
    # bandwidth_used_bytes is reset every billing period
    bandwidth_used_bytes  = Column(BigInteger, default=0)
    bandwidth_limit_bytes = Column(BigInteger, default=10_737_418_240)  # 10 GB default (free plan)

    # Security & account
    email_verified = Column(Boolean, default=False)
    two_fa_enabled = Column(Boolean, default=False)
    two_fa_secret  = Column(String(32))

    # Security Center settings (Security page toggles)
    kill_switch_enabled      = Column(Boolean, default=True)   # Block internet if VPN drops
    auto_connect_wifi        = Column(Boolean, default=False)  # Auto-connect on WiFi
    dns_leak_protection      = Column(Boolean, default=True)   # Prevent DNS leaks
    ad_blocker_enabled       = Column(Boolean, default=True)   # Block ads across all apps
    tracker_blocker_enabled  = Column(Boolean, default=False)  # Stop online tracking
    malware_protection       = Column(Boolean, default=True)   # Block malicious websites

    # App Settings (Settings page)
    dark_theme           = Column(Boolean, default=True)           # Dark / Light theme
    language             = Column(String(20), default="english")   # App language
    auto_connect         = Column(Boolean, default=False)          # Auto-connect on app open
    preferred_protocol   = Column(String(20), default="wireguard") # wireguard|openvpn|ikev2

    # Timestamps
    created_at   = Column(DateTime, default=datetime.utcnow)
    last_login   = Column(DateTime)
    last_seen_at = Column(DateTime)

    # Relationships — SQLAlchemy automatically loads related records
    # cascade="all, delete-orphan" means: if user is deleted, all their related records are deleted too
    vpn_configs   = relationship("VPNConfig",     back_populates="user", lazy="select", cascade="all, delete-orphan")
    sessions      = relationship("VPNSession",    back_populates="user", lazy="select", cascade="all, delete-orphan")
    usage_logs    = relationship("UsageLog",      back_populates="user", lazy="select", cascade="all, delete-orphan")
    devices       = relationship("Device",        back_populates="user", lazy="select", cascade="all, delete-orphan")
    subscriptions = relationship("Subscription",  back_populates="user", lazy="select", cascade="all, delete-orphan")
    tickets       = relationship("SupportTicket", back_populates="user", lazy="select")
    notifications = relationship("Notification",  back_populates="user", lazy="select", cascade="all, delete-orphan", order_by="Notification.created_at.desc()")

    def to_dict(self):
        return {
            "id":                    str(self.id),
            "email":                 self.email,
            "full_name":             self.full_name,
            "plan":                  self.plan,
            "plan_expires_at":       self.plan_expires_at.isoformat() if self.plan_expires_at else None,
            "subscription_status":   self.subscription_status,
            "stripe_customer_id":    self.stripe_customer_id,
            "bandwidth_used_bytes":  self.bandwidth_used_bytes,
            "bandwidth_limit_bytes": self.bandwidth_limit_bytes,
            "email_verified":        self.email_verified,
            "two_fa_enabled":        self.two_fa_enabled,
            "created_at":            self.created_at.isoformat(),
            "last_seen_at":          self.last_seen_at.isoformat() if self.last_seen_at else None,
            # Security Center toggles
            "kill_switch_enabled":     self.kill_switch_enabled,
            "auto_connect_wifi":       self.auto_connect_wifi,
            "dns_leak_protection":     self.dns_leak_protection,
            "ad_blocker_enabled":      self.ad_blocker_enabled,
            "tracker_blocker_enabled": self.tracker_blocker_enabled,
            "malware_protection":      self.malware_protection,
            # App Settings
            "dark_theme":          self.dark_theme,
            "language":            self.language,
            "auto_connect":        self.auto_connect,
            "preferred_protocol":  self.preferred_protocol,
        }


# ─────────────────────────────────────────────────────────────────
# TABLE 2: vpn_servers
# Stores VPN server locations (London, New York, etc.)
# NOTE: We keep String IDs like "lon-1" for servers (human readable)
#       because admins SSH into these servers and need readable names
# ─────────────────────────────────────────────────────────────────
class VPNServer(Base):
    __tablename__ = "vpn_servers"

    id           = Column(String(20), primary_key=True)   # e.g. "lon-1", "nyc-1"
    name         = Column(String(100), nullable=False)
    city         = Column(String(100))
    country      = Column(String(100))
    country_code = Column(String(5))                      # e.g. "gb", "us", "de"
    flag         = Column(String(10))                     # emoji flag e.g. "🇬🇧"
    ip_address   = Column(String(45))                     # server's public IP address

    # Performance metrics (updated regularly)
    ping_ms       = Column(Integer)
    load_pct      = Column(Integer, default=0)            # 0-100% current load
    capacity_mbps = Column(Integer, default=1000)
    is_online     = Column(Boolean, default=True)

    # 3-state status: "online" | "maintenance" | "offline"
    # Kept separate from is_online for backwards compat:
    #   online      → is_online=True
    #   maintenance → is_online=True  (server up but no new connections)
    #   offline     → is_online=False
    status        = Column(String(20), default="online")

    # Uptime percentage (set by monitoring agent, e.g. 99.98)
    uptime_pct    = Column(Float, default=100.0)

    # Server capability flags
    is_streaming  = Column(Boolean, default=False)        # Optimised for Netflix etc.
    is_gaming     = Column(Boolean, default=False)        # Low latency gaming
    is_crypto     = Column(Boolean, default=False)        # Crypto-friendly
    is_p2p        = Column(Boolean, default=False)        # Allows torrent/P2P
    is_dedicated_ip = Column(Boolean, default=False)

    # WireGuard configuration (per document Section 2 and 5)
    # wg_public_key: the server's WireGuard public key — sent to user's app
    # wg_port: the port WireGuard listens on (default 51820)
    wg_public_key = Column(Text)
    wg_port       = Column(Integer, default=51820)

    # Peer tracking
    max_peers     = Column(Integer, default=500)          # max 500 users per server
    current_peers = Column(Integer, default=0)            # current connected users

    # Hetzner cloud server ID (for auto-management via Hetzner API in future)
    hetzner_server_id = Column(String(100))

    protocols  = Column(String(255), default="wireguard,openvpn,ikev2")
    created_at = Column(DateTime, default=datetime.utcnow)

    # Relationships
    vpn_configs = relationship("VPNConfig",  back_populates="server", lazy="select")
    sessions    = relationship("VPNSession", back_populates="server", lazy="select")
    ip_pool     = relationship("IPPool",     back_populates="server", lazy="select", cascade="all, delete-orphan")
    usage_logs  = relationship("UsageLog",   back_populates="server", lazy="select")

    def to_dict(self):
        return {
            "id":            self.id,
            "name":          self.name,
            "city":          self.city,
            "country":       self.country,
            "country_code":  self.country_code,
            "flag":          self.flag,
            "ip_address":    self.ip_address,
            "ping_ms":       self.ping_ms,
            "load_pct":      self.load_pct,
            "capacity_mbps": self.capacity_mbps,
            "capacity_gbps": round(self.capacity_mbps / 1000, 1) if self.capacity_mbps else 0,
            "is_online":     self.is_online,
            "status":        self.status or ("online" if self.is_online else "offline"),
            "uptime_pct":    round(self.uptime_pct, 2) if self.uptime_pct is not None else 100.0,
            "wg_port":       self.wg_port,
            "max_peers":     self.max_peers,
            "current_peers": self.current_peers,
            "protocols": self.protocols.split(",") if self.protocols else [],
            "types": {
                "streaming":    self.is_streaming,
                "gaming":       self.is_gaming,
                "crypto":       self.is_crypto,
                "p2p":          self.is_p2p,
                "dedicated_ip": self.is_dedicated_ip,
            },
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }


# ─────────────────────────────────────────────────────────────────
# TABLE 3: vpn_configs  ← NEW TABLE (from document)
# Stores the WireGuard configuration for each user's device.
# This is the "identity card" of a device in our VPN system.
#
# Real flow:
#   1. User installs app on their iPhone
#   2. App generates WireGuard keypair ON THE DEVICE (private key never leaves the phone)
#   3. App sends the PUBLIC KEY to our API
#   4. We save it here, assign an IP, and add the peer to WireGuard server via SSH
#   5. We send back the server's public key + assigned IP for the .conf file
# ─────────────────────────────────────────────────────────────────
class VPNConfig(Base):
    __tablename__ = "vpn_configs"

    id        = Column(GUID, primary_key=True, default=new_uuid)
    user_id   = Column(GUID, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    server_id = Column(String(20), ForeignKey("vpn_servers.id"), nullable=False, index=True)

    # The user's DEVICE public key (WireGuard)
    # IMPORTANT: We NEVER store the private key — that stays on the device forever
    public_key = Column(Text, nullable=False)

    # The VPN IP assigned to this specific device on this server
    # e.g. "10.0.0.42" — picked from ip_pool table
    assigned_ip = Column(String(45), nullable=False)

    # Device metadata (helps user manage "which config is which device")
    device_name = Column(String(100))                     # e.g. "iPhone 15", "Work Laptop"
    platform    = Column(String(50))                      # ios|android|windows|mac|linux|router

    # Config state
    is_active  = Column(Boolean, default=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    revoked_at = Column(DateTime)    # set when user removes this device

    # Relationships
    user   = relationship("User",      back_populates="vpn_configs")
    server = relationship("VPNServer", back_populates="vpn_configs")

    def to_dict(self):
        return {
            "id":          str(self.id),
            "user_id":     str(self.user_id),
            "server_id":   self.server_id,
            "public_key":  self.public_key,
            "assigned_ip": self.assigned_ip,
            "device_name": self.device_name,
            "platform":    self.platform,
            "is_active":   self.is_active,
            "created_at":  self.created_at.isoformat(),
            "revoked_at":  self.revoked_at.isoformat() if self.revoked_at else None,
        }


# ─────────────────────────────────────────────────────────────────
# TABLE 4: ip_pool  ← NEW TABLE (from document)
# Pre-seeded pool of available VPN IP addresses per server.
#
# Why this exists:
#   Without this, two users could accidentally get the same IP address
#   at the same moment (race condition). This table + database locking
#   prevents that. It's like a parking lot — each IP is a parking space.
#
# How to seed it:
#   Each server gets a /24 subnet = 253 usable IPs (10.x.x.1 to 10.x.x.253)
#   When server "lon-1" is created, we insert 253 rows into this table.
#   The seed_database() function in app.py handles this automatically.
# ─────────────────────────────────────────────────────────────────
class IPPool(Base):
    __tablename__ = "ip_pool"

    id        = Column(GUID, primary_key=True, default=new_uuid)
    server_id = Column(String(20), ForeignKey("vpn_servers.id", ondelete="CASCADE"), nullable=False, index=True)

    # The actual IP address available for assignment
    # e.g. "10.0.0.42"
    ip_address = Column(String(45), nullable=False)

    # Whether this IP is currently in use
    is_assigned = Column(Boolean, default=False, index=True)

    # Which vpn_config is currently using this IP (null if free)
    assigned_to = Column(GUID, ForeignKey("vpn_configs.id", ondelete="SET NULL"), nullable=True)

    # Timestamps
    assigned_at = Column(DateTime)    # when was this IP last assigned
    released_at = Column(DateTime)    # when was this IP last released back to pool

    # Relationship
    server = relationship("VPNServer", back_populates="ip_pool")

    # Ensure no two rows have the same IP on the same server
    __table_args__ = (
        UniqueConstraint("server_id", "ip_address", name="uq_server_ip"),
        # Index for fast "find me a free IP on this server" query
        Index("idx_ip_pool_server_free", "server_id", "is_assigned"),
    )

    def to_dict(self):
        return {
            "id":          str(self.id),
            "server_id":   self.server_id,
            "ip_address":  self.ip_address,
            "is_assigned": self.is_assigned,
        }


# ─────────────────────────────────────────────────────────────────
# TABLE 5: usage_logs  ← NEW TABLE (from document)
# Records bandwidth used per session for billing enforcement.
#
# ZERO-LOGS POLICY:
#   We log ONLY bytes sent/received and session timing.
#   We do NOT log: websites visited, destination IPs,
#   DNS queries, browsing history, or any traffic content.
#   Violating this would be a GDPR violation and break user trust.
# ─────────────────────────────────────────────────────────────────
class UsageLog(Base):
    __tablename__ = "usage_logs"

    id        = Column(GUID, primary_key=True, default=new_uuid)
    user_id   = Column(GUID, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    server_id = Column(String(20), ForeignKey("vpn_servers.id"), nullable=True)

    # Bytes transferred (NOT what was transferred — just how much)
    bytes_sent     = Column(BigInteger, default=0)   # upload (user → internet)
    bytes_received = Column(BigInteger, default=0)   # download (internet → user)

    # Session timing
    session_start = Column(DateTime, nullable=False)
    session_end   = Column(DateTime)

    created_at = Column(DateTime, default=datetime.utcnow, index=True)

    # Relationships
    user   = relationship("User",      back_populates="usage_logs")
    server = relationship("VPNServer", back_populates="usage_logs")

    # Index for fast "how much did user X use this month" query
    __table_args__ = (
        Index("idx_usage_logs_user_date", "user_id", "created_at"),
    )

    def to_dict(self):
        duration = None
        if self.session_start and self.session_end:
            duration = int((self.session_end - self.session_start).total_seconds())
        return {
            "id":               str(self.id),
            "server_id":        self.server_id,
            "bytes_sent":       self.bytes_sent,
            "bytes_received":   self.bytes_received,
            "total_bytes":      self.bytes_sent + self.bytes_received,
            "session_start":    self.session_start.isoformat(),
            "session_end":      self.session_end.isoformat() if self.session_end else None,
            "duration_seconds": duration,
        }


# ─────────────────────────────────────────────────────────────────
# TABLE 6: vpn_sessions
# Tracks active and past VPN connections (connect/disconnect events)
# Think of this as the "log" — vpn_configs is the "identity"
# ─────────────────────────────────────────────────────────────────
class VPNSession(Base):
    __tablename__ = "vpn_sessions"

    id          = Column(GUID, primary_key=True, default=new_uuid)
    user_id     = Column(GUID, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    server_id   = Column(String(20), ForeignKey("vpn_servers.id"), nullable=True)
    config_id   = Column(GUID, ForeignKey("vpn_configs.id", ondelete="SET NULL"), nullable=True)

    mode        = Column(String(50), default="standard")   # standard|streaming|gaming|crypto
    protocol    = Column(String(50), default="wireguard")
    started_at  = Column(DateTime, default=datetime.utcnow, index=True)
    ended_at    = Column(DateTime)
    bytes_down  = Column(BigInteger, default=0)
    bytes_up    = Column(BigInteger, default=0)
    ip_assigned = Column(String(45))
    device_name = Column(String(100))
    is_active   = Column(Boolean, default=True)

    user   = relationship("User",      back_populates="sessions")
    server = relationship("VPNServer", back_populates="sessions")

    def to_dict(self):
        duration = None
        if self.started_at:
            end      = self.ended_at or datetime.utcnow()
            duration = int((end - self.started_at).total_seconds())
        return {
            "id":               str(self.id),
            "server_id":        self.server_id,
            "mode":             self.mode,
            "protocol":         self.protocol,
            "started_at":       self.started_at.isoformat(),
            "ended_at":         self.ended_at.isoformat() if self.ended_at else None,
            "duration_seconds": duration,
            "bytes_down":       self.bytes_down,
            "bytes_up":         self.bytes_up,
            "ip_assigned":      self.ip_assigned,
            "device_name":      self.device_name,
            "is_active":        self.is_active,
        }


# ─────────────────────────────────────────────────────────────────
# TABLE 7: devices
# Registered devices on the account (for device limit enforcement)
# Different from vpn_configs — this is about account access,
# vpn_configs is about WireGuard identity
# ─────────────────────────────────────────────────────────────────
class Device(Base):
    __tablename__ = "devices"

    id                 = Column(GUID, primary_key=True, default=new_uuid)
    user_id            = Column(GUID, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    name               = Column(String(100))
    platform           = Column(String(50))      # ios|android|windows|mac|linux|router
    device_fingerprint = Column(String(255))
    last_seen          = Column(DateTime, default=datetime.utcnow)
    is_trusted         = Column(Boolean, default=True)

    user = relationship("User", back_populates="devices")

    def to_dict(self):
        return {
            "id":         str(self.id),
            "name":       self.name,
            "platform":   self.platform,
            "last_seen":  self.last_seen.isoformat() if self.last_seen else None,
            "is_trusted": self.is_trusted,
        }


# ─────────────────────────────────────────────────────────────────
# TABLE 7.5: plans
# Subscription plans and feature toggles
# ─────────────────────────────────────────────────────────────────
class Plan(Base):
    __tablename__ = "plans"

    key = Column(String(50), primary_key=True) # free, starter, pro, premium
    label = Column(String(100), nullable=False)
    description = Column(String(255))
    amount_usd = Column(Float, default=0.0)
    per = Column(String(20), default="mo") # mo, year, seat
    currency = Column(String(10), default="USD")

    stripe_price_id_monthly = Column(String(100))
    stripe_price_id_yearly = Column(String(100))

    max_devices = Column(Integer, default=1)
    bandwidth_gb = Column(Integer, nullable=True) # null = unlimited
    server_count = Column(Integer, nullable=True)
    simultaneous = Column(Integer, default=1)

    has_streaming = Column(Boolean, default=False)
    has_p2p = Column(Boolean, default=False)
    has_dedicated_ip = Column(Boolean, default=False)
    has_ad_blocker = Column(Boolean, default=False)
    has_kill_switch = Column(Boolean, default=False)
    has_priority_support = Column(Boolean, default=False)

    is_visible = Column(Boolean, default=True)
    is_default = Column(Boolean, default=False)

    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    def to_dict(self):
        amount_label = "Free" if self.amount_usd == 0 else f"${self.amount_usd}/{self.per}"
        limits = {
            "devices": self.max_devices,
            "bandwidth_gb": self.bandwidth_gb,
            "servers": self.server_count,
            "simultaneous": self.simultaneous,
        }
        features = {
            "streaming": self.has_streaming,
            "p2p": self.has_p2p,
            "dedicated_ip": self.has_dedicated_ip,
            "ad_blocker": self.has_ad_blocker,
            "kill_switch": self.has_kill_switch,
            "priority_support": self.has_priority_support,
        }
        return {
            "key": self.key,
            "label": self.label,
            "description": self.description,
            "amount_usd": self.amount_usd,
            "per": self.per,
            "amount_label": amount_label,
            "limits": limits,
            "features": features,
            "is_visible": self.is_visible,
            "is_default": self.is_default,
        }


# ─────────────────────────────────────────────────────────────────
# TABLE 8: subscriptions
# Full billing history — every plan change, renewal, cancellation
# ─────────────────────────────────────────────────────────────────
class Subscription(Base):
    __tablename__ = "subscriptions"

    id      = Column(GUID, primary_key=True, default=new_uuid)
    user_id = Column(GUID, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)

    plan          = Column(String(50))           # essential|elite|ultimate
    billing_cycle = Column(String(20))           # monthly|annual
    amount_usd    = Column(Float)
    currency      = Column(String(5), default="USD")
    status        = Column(String(20), default="active")  # active|cancelled|expired|past_due

    # Stripe IDs — link this record to Stripe's system
    stripe_subscription_id = Column(String(100), index=True)
    stripe_invoice_id      = Column(String(100))

    started_at   = Column(DateTime, default=datetime.utcnow)
    expires_at   = Column(DateTime)
    cancelled_at = Column(DateTime)

    user = relationship("User", back_populates="subscriptions")

    def to_dict(self):
        return {
            "id":                     str(self.id),
            "plan":                   self.plan,
            "billing_cycle":          self.billing_cycle,
            "amount_usd":             self.amount_usd,
            "currency":               self.currency,
            "status":                 self.status,
            "stripe_subscription_id": self.stripe_subscription_id,
            "started_at":             self.started_at.isoformat(),
            "expires_at":             self.expires_at.isoformat() if self.expires_at else None,
            "cancelled_at":           self.cancelled_at.isoformat() if self.cancelled_at else None,
        }


# ─────────────────────────────────────────────────────────────────
# TABLE 9: support_tickets
# Customer support requests from users
# ─────────────────────────────────────────────────────────────────
class SupportTicket(Base):
    __tablename__ = "support_tickets"

    id      = Column(GUID, primary_key=True, default=new_uuid)
    user_id = Column(GUID, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)

    email    = Column(String(255), nullable=False)
    subject  = Column(String(255))
    message  = Column(Text)
    category = Column(String(50))   # billing|technical|general|abuse
    status   = Column(String(20), default="open")  # open|in_progress|resolved|closed
    priority = Column(String(20), default="medium") # urgent|high|medium|low
    agent_name = Column(String(100), nullable=True)

    created_at = Column(DateTime, default=datetime.utcnow, index=True)
    updated_at = Column(DateTime, default=datetime.utcnow)

    user = relationship("User", back_populates="tickets")

    def to_dict(self):
        return {
            "id":         str(self.id),
            "email":      self.email,
            "subject":    self.subject,
            "category":   self.category,
            "status":     self.status,
            "priority":   self.priority,
            "agent_name": self.agent_name,
            "created_at": self.created_at.isoformat(),
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
        }


# ─────────────────────────────────────────────────────────────────
# TABLE 10: notifications
# Stores per-user in-app notifications
# Types: security | vpn_event | login | bandwidth | upgrade | coming_soon
# ─────────────────────────────────────────────────────────────────
class Notification(Base):
    __tablename__ = "notifications"

    id      = Column(GUID, primary_key=True, default=new_uuid)
    user_id = Column(GUID, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)

    # Notification classification
    # security    → Unsafe website blocked, malware blocked
    # vpn_event   → VPN disconnected, kill switch fired
    # login       → New login detected on a new device
    # bandwidth   → 80% / 100% data usage warning
    # upgrade     → Plan upgrade suggestion
    # coming_soon → Dark web, phishing (future AI features)
    type    = Column(String(30), nullable=False)

    title   = Column(String(255), nullable=False)
    message = Column(Text,        nullable=False)
    is_read = Column(Boolean, default=False)

    # For "coming soon" notifications
    coming_soon = Column(Boolean, default=False)

    # Extra metadata (JSON string) — e.g. { "ip": "1.2.3.4", "location": "London" }
    meta = Column(Text, nullable=True)

    created_at = Column(DateTime, default=datetime.utcnow, index=True)

    user = relationship("User", back_populates="notifications")

    def to_dict(self):
        import json as _json
        return {
            "id":          str(self.id),
            "type":        self.type,
            "title":       self.title,
            "message":     self.message,
            "is_read":     self.is_read,
            "coming_soon": self.coming_soon,
            "meta":        _json.loads(self.meta) if self.meta else None,
            "created_at":  self.created_at.isoformat() + "Z",
            "time_ago":    _time_ago(self.created_at),
        }


def _time_ago(dt: datetime) -> str:
    """Human-readable time difference: '2 min ago', '3 hours ago', 'Yesterday'."""
    diff = datetime.utcnow() - dt
    seconds = int(diff.total_seconds())
    if seconds < 60:
        return "Just now"
    if seconds < 3600:
        mins = seconds // 60
        return f"{mins} min ago"
    if seconds < 86400:
        hrs = seconds // 3600
        return f"{hrs} hour{'s' if hrs > 1 else ''} ago"
    if seconds < 172800:
        return "Yesterday"
    days = seconds // 86400
    return f"{days} days ago"


# ─────────────────────────────────────────────────────────────────
# TABLE 11: coupon_codes
# Promo codes an admin creates. Users enter these at checkout.
# type: "percent" | "fixed"  (e.g. 50% off  or  $20 off)
# plan: which plan this code is valid for ("pro", "premium", etc. or null = all)
# use_limit: max total redemptions (null = unlimited)
# uses: how many times it has been redeemed (auto-incremented on validation)
# ─────────────────────────────────────────────────────────────────
class CouponCode(Base):
    __tablename__ = "coupon_codes"

    id   = Column(GUID, primary_key=True, default=new_uuid)
    code = Column(String(50), unique=True, nullable=False, index=True)   # e.g. "LAUNCH60"

    # Discount definition
    discount_type  = Column(String(10), nullable=False)  # "percent" | "fixed"
    discount_value = Column(Float,      nullable=False)  # 60 (meaning 60%) or 20.00 (meaning $20)

    # Restriction: which plan this coupon applies to (null = any plan)
    plan = Column(String(50), nullable=True)

    # Usage tracking
    uses      = Column(Integer, default=0)   # how many times redeemed so far
    use_limit = Column(Integer, nullable=True)  # null = unlimited

    # Lifecycle
    status     = Column(String(20), default="active")  # "active" | "inactive" | "expired"
    expires_at = Column(DateTime, nullable=True)        # null = never expires
    created_at = Column(DateTime, default=datetime.utcnow)
    created_by = Column(String(255), nullable=True)     # admin email who created it

    def to_dict(self):
        return {
            "id":             str(self.id),
            "code":           self.code,
            "discount_type":  self.discount_type,
            "discount_value": self.discount_value,
            "discount_label": (
                f"{int(self.discount_value)}% off"
                if self.discount_type == "percent"
                else f"${self.discount_value:.0f} off"
            ),
            "plan":           self.plan,
            "uses":           self.uses,
            "use_limit":      self.use_limit,
            "uses_display":   (
                f"{self.uses:,} / {self.use_limit:,}"
                if self.use_limit
                else f"{self.uses:,} / ∞"
            ),
            "status":         self.status,
            "expires_at":     self.expires_at.strftime("%Y-%m-%d") if self.expires_at else None,
            "created_at":     self.created_at.isoformat(),
            "created_by":     self.created_by,
        }


# ─────────────────────────────────────────────────────────────────
# TABLE 12: referrals
# One row per referral event.
# A referral happens when an existing user shares their referral link
# and a new user signs up via that link and then converts to a paid plan.
# ─────────────────────────────────────────────────────────────────
class Referral(Base):
    __tablename__ = "referrals"

    id = Column(GUID, primary_key=True, default=new_uuid)

    # The user who referred (sharer of the link)
    referrer_id = Column(GUID, ForeignKey("users.id", ondelete="SET NULL"), nullable=True, index=True)

    # The new user who signed up via the referral link
    referred_id = Column(GUID, ForeignKey("users.id", ondelete="SET NULL"), nullable=True)

    # Status of this referral
    # "pending"   → referred user signed up but hasn't paid yet
    # "converted" → referred user paid — commission is owed
    # "paid"      → commission has been paid to the referrer
    status = Column(String(20), default="pending")  # pending | converted | paid

    # Commission earned by the referrer for this referral
    commission_usd = Column(Float, default=0.0)

    # Timestamps
    signed_up_at   = Column(DateTime, default=datetime.utcnow)  # when referred user joined
    converted_at   = Column(DateTime, nullable=True)             # when they paid
    commission_paid_at = Column(DateTime, nullable=True)

    # Relationships
    referrer = relationship("User", foreign_keys=[referrer_id], lazy="select")
    referred = relationship("User", foreign_keys=[referred_id], lazy="select")

    def to_dict(self):
        return {
            "id":                  str(self.id),
            "referrer_id":         str(self.referrer_id) if self.referrer_id else None,
            "referred_id":         str(self.referred_id) if self.referred_id else None,
            "status":              self.status,
            "commission_usd":      self.commission_usd,
            "signed_up_at":        self.signed_up_at.isoformat() if self.signed_up_at else None,
            "converted_at":        self.converted_at.isoformat() if self.converted_at else None,
            "commission_paid_at":  self.commission_paid_at.isoformat() if self.commission_paid_at else None,
        }


# ─────────────────────────────────────────────────────────────────
# TABLE 13: affiliates
# Affiliate partners who promote AtmosVPN and earn a commission
# on every sale they generate (tracked via unique affiliate codes).
# ─────────────────────────────────────────────────────────────────
class Affiliate(Base):
    __tablename__ = "affiliates"

    id   = Column(GUID, primary_key=True, default=new_uuid)
    name = Column(String(255), nullable=False)         # affiliate's display name
    email = Column(String(255), unique=True, nullable=False, index=True)

    # Unique tracking code — used in affiliate URLs
    # e.g. atmosvpn.com/signup?ref=YOUTUBE_TECHGUY
    affiliate_code = Column(String(100), unique=True, nullable=False, index=True)

    # Status: "active" | "inactive" | "suspended"
    status = Column(String(20), default="active")

    # Commission configuration
    # commission_type: "percent" | "fixed"
    # commission_value: e.g. 30.0 (means 30% of each sale) or 5.00 (means $5 per sale)
    commission_type  = Column(String(10), default="percent")
    commission_value = Column(Float,      default=30.0)

    # Payout method: "paypal" | "crypto" | "bank"
    payout_method = Column(String(50), default="paypal")
    payout_details = Column(Text, nullable=True)   # JSON: {"paypal_email": "..."} etc.

    # Revenue stats (denormalised for speed — updated on each commission event)
    total_revenue_generated = Column(Float, default=0.0)   # total $ they generated for us
    total_commission_paid   = Column(Float, default=0.0)   # total $ we paid them
    total_conversions       = Column(Integer, default=0)   # how many paying users they brought

    # Timestamps
    joined_at    = Column(DateTime, default=datetime.utcnow)
    last_active  = Column(DateTime, nullable=True)

    def to_dict(self):
        return {
            "id":                      str(self.id),
            "name":                    self.name,
            "email":                   self.email,
            "affiliate_code":          self.affiliate_code,
            "status":                  self.status,
            "commission_type":         self.commission_type,
            "commission_value":        self.commission_value,
            "commission_label":        (
                f"{self.commission_value:.0f}%"
                if self.commission_type == "percent"
                else f"${self.commission_value:.2f}"
            ),
            "payout_method":           self.payout_method,
            "total_revenue_generated": round(self.total_revenue_generated, 2),
            "total_commission_paid":   round(self.total_commission_paid,   2),
            "total_conversions":       self.total_conversions,
            "joined_at":               self.joined_at.isoformat() if self.joined_at else None,
            "last_active":             self.last_active.isoformat() if self.last_active else None,
        }


# ─────────────────────────────────────────────────────────────────
# TABLE 14: service_health
# Track status of internal services (VPN Core, API Gateway, etc)
# ─────────────────────────────────────────────────────────────────
class ServiceHealth(Base):
    __tablename__ = "service_health"

    id           = Column(GUID, primary_key=True, default=new_uuid)
    service_name = Column(String(100), nullable=False, unique=True)
    status       = Column(String(20), default="online")  # "online" | "maint" | "offline"
    updated_at   = Column(DateTime, default=datetime.utcnow)

    def to_dict(self):
        return {
            "id":           str(self.id),
            "service_name": self.service_name,
            "status":       self.status,
            "updated_at":   self.updated_at.isoformat() if self.updated_at else None,
        }


# ─────────────────────────────────────────────────────────────────
# TABLE 15: system_incidents
# Track system-wide incidents (outages, maintenance, etc.)
# ─────────────────────────────────────────────────────────────────
class SystemIncident(Base):
    __tablename__ = "system_incidents"

    id               = Column(GUID, primary_key=True, default=new_uuid)
    incident_number  = Column(String(20), unique=True, index=True) # e.g., "INC-201"
    title            = Column(String(255), nullable=False)
    affected_services= Column(String(255))
    severity         = Column(String(20)) # "minor" | "major" | "critical"
    status           = Column(String(20), default="investigating") # "investigating" | "resolved"
    public_status_update = Column(Text)
    created_at       = Column(DateTime, default=datetime.utcnow)
    resolved_at      = Column(DateTime, nullable=True)

    def to_dict(self):
        return {
            "id":               str(self.id),
            "incident_number":  self.incident_number,
            "title":            self.title,
            "affected_services":self.affected_services,
            "severity":         self.severity,
            "status":           self.status,
            "public_status_update": self.public_status_update,
            "created_at":       self.created_at.isoformat(),
            "resolved_at":      self.resolved_at.isoformat() if self.resolved_at else None,
        }


# ─────────────────────────────────────────────────────────────────
# TABLE 16: security_events
# Track security-related incidents (brute force, API abuse, etc.)
# ─────────────────────────────────────────────────────────────────
class SecurityEvent(Base):
    __tablename__ = "security_events"

    id         = Column(GUID, primary_key=True, default=new_uuid)
    event_type = Column(String(50), nullable=False) # "Brute Force", "API Abuse", etc.
    ip_address = Column(String(45))
    user_email = Column(String(255))
    country    = Column(String(10)) # e.g. "RU", "GB"
    action     = Column(String(50)) # "IP Blocked", "2FA Required", etc.
    created_at = Column(DateTime, default=datetime.utcnow)

    def to_dict(self):
        return {
            "id":         str(self.id),
            "type":       self.event_type,
            "ip":         self.ip_address,
            "user":       self.user_email,
            "country":    self.country,
            "action":     self.action,
            "created_at": self.created_at.isoformat(),
        }


# ─────────────────────────────────────────────────────────────────
# TABLE 17: blocked_ips
# List of suspended IP addresses
# ─────────────────────────────────────────────────────────────────
class BlockedIP(Base):
    __tablename__ = "blocked_ips"

    ip_address = Column(String(45), primary_key=True)
    status     = Column(String(20), default="Suspended")
    created_at = Column(DateTime, default=datetime.utcnow)

    def to_dict(self):
        return {
            "ip":         self.ip_address,
            "status":     self.status,
            "created_at": self.created_at.isoformat(),
        }


# ─────────────────────────────────────────────────────────────────
# TABLE 18: security_settings
# Key-value store for global security configuration
# ─────────────────────────────────────────────────────────────────
class SecuritySetting(Base):
    __tablename__ = "security_settings"

    key   = Column(String(100), primary_key=True)
    value = Column(Boolean, default=False)

    def to_dict(self):
        return {
            "key":   self.key,
            "value": self.value,
        }


# ─────────────────────────────────────────────────────────────────
# TABLE 19: push_campaigns
# Broadcast push notifications to user segments
# ─────────────────────────────────────────────────────────────────
class PushCampaign(Base):
    __tablename__ = "push_campaigns"

    id             = Column(GUID, primary_key=True, default=new_uuid)
    title          = Column(String(255), nullable=False)
    message        = Column(Text, nullable=False)
    target_segment = Column(String(100), default="All Users")
    status         = Column(String(50), default="draft") # "draft" | "scheduled" | "sent"
    scheduled_for  = Column(DateTime, nullable=True) # null = send immediately
    
    # Analytics
    devices_targeted = Column(Integer, default=0)
    sent_at          = Column(DateTime, nullable=True)

    created_at = Column(DateTime, default=datetime.utcnow)

    def to_dict(self):
        return {
            "id":             str(self.id),
            "title":          self.title,
            "message":        self.message,
            "target_segment": self.target_segment,
            "status":         self.status,
            "scheduled_for":  self.scheduled_for.isoformat() if self.scheduled_for else None,
            "devices_targeted": self.devices_targeted,
            "sent_at":        self.sent_at.isoformat() if self.sent_at else None,
            "created_at":     self.created_at.isoformat(),
        }


# ─────────────────────────────────────────────────────────────────
# TABLE 20: email_campaigns
# Email newsletters, drip sequences, and automations
# ─────────────────────────────────────────────────────────────────
class EmailCampaign(Base):
    __tablename__ = "email_campaigns"

    id             = Column(GUID, primary_key=True, default=new_uuid)
    name           = Column(String(255), nullable=False)
    status         = Column(String(50), default="Draft") # "Sent" | "Draft" | "Automated"
    target_segment = Column(String(100), default="All Users")
    
    # Analytics
    sent_count       = Column(Integer, default=0)
    open_rate_pct    = Column(Float, default=0.0)
    click_rate_pct   = Column(Float, default=0.0)
    unsubscribe_rate_pct = Column(Float, default=0.0)

    date = Column(DateTime, nullable=True) # Send date or schedule date

    created_at = Column(DateTime, default=datetime.utcnow)

    def to_dict(self):
        # Format the numbers for the UI
        sent_label = "-"
        if self.sent_count > 0:
            if self.sent_count >= 1000000:
                sent_label = f"{self.sent_count / 1000000:.2f}M"
            elif self.sent_count >= 1000:
                sent_label = f"{self.sent_count / 1000:.1f}K"
            else:
                sent_label = str(self.sent_count)
        
        date_label = "Ongoing" if self.status == "Automated" else (self.date.strftime("%Y-%m-%d") if self.date else "-")

        return {
            "id":             str(self.id),
            "name":           self.name,
            "status":         self.status,
            "target_segment": self.target_segment,
            "sent_label":     sent_label,
            "open_rate_pct":  self.open_rate_pct if self.status != "Draft" else "-",
            "click_rate_pct": self.click_rate_pct if self.status != "Draft" else "-",
            "date":           date_label,
            "created_at":     self.created_at.isoformat(),
        }


# ─────────────────────────────────────────────────────────────────
# TABLE 21: blog_posts
# Blog Management and SEO metadata
# ─────────────────────────────────────────────────────────────────
class BlogPost(Base):
    __tablename__ = "blog_posts"

    id              = Column(GUID, primary_key=True, default=new_uuid)
    title           = Column(String(255), nullable=False)
    slug            = Column(String(255), nullable=True, unique=True, index=True)
    author          = Column(String(100), nullable=False)
    category        = Column(String(100), nullable=False)
    content         = Column(Text, nullable=True)
    excerpt         = Column(Text, nullable=True)
    tags            = Column(String(500), nullable=True)          # comma-separated
    featured_image  = Column(String(1000), nullable=True)
    read_time_min   = Column(Integer, default=3)
    status          = Column(String(50), default="draft")         # published | draft | archived
    views           = Column(Integer, default=0)

    # Per-post SEO fields
    meta_title       = Column(String(255), nullable=True)
    meta_description = Column(Text, nullable=True)
    og_image         = Column(String(1000), nullable=True)
    canonical_url    = Column(String(1000), nullable=True)
    robots           = Column(String(100), default="index, follow")

    published_at = Column(DateTime, nullable=True)
    created_at   = Column(DateTime, default=datetime.utcnow)
    updated_at   = Column(DateTime, nullable=True)

    def to_dict(self):
        date_to_show = self.published_at if self.published_at else self.created_at
        return {
            "id":               str(self.id),
            "title":            self.title,
            "slug":             self.slug,
            "author":           self.author,
            "category":         self.category,
            "content":          self.content,
            "excerpt":          self.excerpt,
            "tags":             self.tags.split(",") if self.tags else [],
            "featured_image":   self.featured_image,
            "read_time_min":    self.read_time_min,
            "status":           self.status,
            "views":            self.views,
            "meta_title":       self.meta_title,
            "meta_description": self.meta_description,
            "og_image":         self.og_image,
            "canonical_url":    self.canonical_url,
            "robots":           self.robots,
            "published_at":     self.published_at.isoformat() if self.published_at else None,
            "created_at":       self.created_at.isoformat() if self.created_at else None,
            "updated_at":       self.updated_at.isoformat() if self.updated_at else None,
            "date":             date_to_show.strftime("%Y-%m-%d") if date_to_show else None,
        }


# ─────────────────────────────────────────────────────────────────
# TABLE 22: job_listings
# Careers page: Job postings and applicant counts
# ─────────────────────────────────────────────────────────────────
class JobListing(Base):
    __tablename__ = "job_listings"

    id         = Column(GUID, primary_key=True, default=new_uuid)
    position   = Column(String(255), nullable=False)
    department = Column(String(100), nullable=False)
    job_type   = Column(String(50), default="Full-time") # Full-time, Part-time, Contract
    status     = Column(String(20), default="Open") # Open, closed
    
    applicants_count = Column(Integer, default=0)
    
    created_at = Column(DateTime, default=datetime.utcnow)

    def to_dict(self):
        return {
            "id":               str(self.id),
            "position":         self.position,
            "department":       self.department,
            "job_type":         self.job_type,
            "status":           self.status,
            "applicants_count": self.applicants_count,
            "created_at":       self.created_at.isoformat()
        }


# ─────────────────────────────────────────────────────────────────
# TABLE 23: press_coverage
# Press & Media: Press coverage links
# ─────────────────────────────────────────────────────────────────
class PressCoverage(Base):
    __tablename__ = "press_coverage"

    id           = Column(GUID, primary_key=True, default=new_uuid)
    publication  = Column(String(255), nullable=False) # e.g. "WIRED"
    headline     = Column(String(500), nullable=False)
    url          = Column(String(1000), nullable=True)
    published_at = Column(DateTime, nullable=False)
    created_at   = Column(DateTime, default=datetime.utcnow)

    def to_dict(self):
        return {
            "id":           str(self.id),
            "publication":  self.publication,
            "headline":     self.headline,
            "url":          self.url,
            "published_at": self.published_at.isoformat(),
            "display_date": self.published_at.strftime("%b %Y").upper(),
            "created_at":   self.created_at.isoformat()
        }

# ─────────────────────────────────────────────────────────────────
# TABLE 24: brand_assets
# Press & Media: Downloadable brand assets
# ─────────────────────────────────────────────────────────────────
class BrandAsset(Base):
    __tablename__ = "brand_assets"

    id         = Column(GUID, primary_key=True, default=new_uuid)
    name       = Column(String(255), nullable=False)
    file_url   = Column(String(1000), nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)

    def to_dict(self):
        return {
            "id":         str(self.id),
            "name":       self.name,
            "file_url":   self.file_url,
            "created_at": self.created_at.isoformat()
        }


# ─────────────────────────────────────────────────────────────────
# TABLE 25: app_releases
# Downloads & App Versions page
# ─────────────────────────────────────────────────────────────────
class AppRelease(Base):
    __tablename__ = "app_releases"

    id        = Column(GUID, primary_key=True, default=new_uuid)
    platform  = Column(String(50), nullable=False) # Windows, macOS, iOS, Android, Linux, Router (OpenWRT)
    version   = Column(String(20), nullable=False) # e.g. "4.2.1"
    size      = Column(String(20), nullable=False) # e.g. "48.3 MB"
    downloads = Column(Integer, default=0)
    released_at = Column(DateTime, default=datetime.utcnow)
    status    = Column(String(20), default="Current") # "Current" | "Update Avail."
    
    changelog = Column(Text, nullable=True)
    
    created_at = Column(DateTime, default=datetime.utcnow)

    def to_dict(self):
        dl_label = "-"
        if self.downloads > 0:
            if self.downloads >= 1000000:
                dl_label = f"{self.downloads / 1000000:.2f}M"
            elif self.downloads >= 1000:
                dl_label = f"{self.downloads / 1000:.0f}K"
            else:
                dl_label = str(self.downloads)

        return {
            "id":          str(self.id),
            "platform":    self.platform,
            "version":     self.version,
            "size":        self.size,
            "downloads_label": dl_label,
            "released_at": self.released_at.strftime("%Y-%m-%d") if self.released_at else "-",
            "status":      self.status,
            "changelog":   self.changelog,
        }


# ─────────────────────────────────────────────────────────────────
# TABLE 26: admin_users
# Admin Team page: Accounts, roles, permissions
# ─────────────────────────────────────────────────────────────────
class AdminUser(Base):
    __tablename__ = "admin_users"

    id         = Column(GUID, primary_key=True, default=new_uuid)
    name       = Column(String(100), nullable=False)
    email      = Column(String(255), nullable=False, unique=True)
    password_hash = Column(String(255), nullable=False)
    role       = Column(String(50), nullable=False) # Super Admin, Operations, Billing, Content
    two_fa_enabled = Column(Boolean, default=False)
    last_login = Column(DateTime, nullable=True)
    status     = Column(String(20), default="Active")
    
    created_at = Column(DateTime, default=datetime.utcnow)

    def to_dict(self):
        return {
            "id":             str(self.id),
            "name":           self.name,
            "email":          self.email,
            "role":           self.role,
            "two_fa_enabled": self.two_fa_enabled,
            "last_login":     self.last_login.strftime("%b %d %H:%M") if self.last_login else "-",
            "status":         self.status,
            "created_at":     self.created_at.isoformat()
        }


# ─────────────────────────────────────────────────────────────────
# TABLE 27: audit_logs
# Audit Log page: All admin actions
# ─────────────────────────────────────────────────────────────────
class AuditLog(Base):
    __tablename__ = "audit_logs"

    id         = Column(GUID, primary_key=True, default=new_uuid)
    admin_email = Column(String(255), nullable=False)
    action     = Column(String(1000), nullable=False)
    ip_address = Column(String(50), nullable=False)
    
    timestamp  = Column(DateTime, default=datetime.utcnow, index=True)

    def to_dict(self):
        return {
            "id":          str(self.id),
            "admin_email": self.admin_email,
            "action":      self.action,
            "ip_address":  self.ip_address,
            "timestamp":   self.timestamp.isoformat(),
            "display_time": self.timestamp.strftime("%b %d %H:%M")
        }



# ─────────────────────────────────────────────────────────────────
# TABLE 28: integration_keys
# Settings -> API Keys (Stripe, SendGrid, Sentry, etc.)
# ─────────────────────────────────────────────────────────────────
class IntegrationKey(Base):
    __tablename__ = "integration_keys"

    id          = Column(GUID, primary_key=True, default=new_uuid)
    service     = Column(String(100), nullable=False, unique=True)
    api_key     = Column(String(500), nullable=False)
    is_active   = Column(Boolean, default=True)
    last_rotated = Column(DateTime, default=datetime.utcnow)
    created_at  = Column(DateTime, default=datetime.utcnow)

    def to_dict(self):
        masked_key = self.api_key
        if len(masked_key) > 8:
            masked_key = masked_key[:4] + "••••••••••••••••" + masked_key[-4:]
        else:
            masked_key = "••••••••"

        return {
            "id":           str(self.id),
            "service":      self.service,
            "api_key_masked": masked_key,
            "is_active":    self.is_active,
            "last_rotated": self.last_rotated.isoformat(),
            "created_at":   self.created_at.isoformat(),
        }


# ─────────────────────────────────────────────────────────────────
# TABLE 29: admin_notification_configs
# Settings -> Notifications (Alert settings)
# ─────────────────────────────────────────────────────────────────
class AdminNotificationConfig(Base):
    __tablename__ = "admin_notification_configs"

    id          = Column(GUID, primary_key=True, default=new_uuid)
    event_type  = Column(String(100), nullable=False, unique=True)
    label       = Column(String(200), nullable=False)
    is_enabled  = Column(Boolean, default=True)
    updated_at  = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    def to_dict(self):
        return {
            "id":         str(self.id),
            "event_type": self.event_type,
            "label":      self.label,
            "is_enabled": self.is_enabled,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
        }


# ─────────────────────────────────────────────────────────────────
# TABLE 30: legal_pages
# Settings -> Legal
# ─────────────────────────────────────────────────────────────────
class LegalPage(Base):
    __tablename__ = "legal_pages"

    id          = Column(GUID, primary_key=True, default=new_uuid)
    title       = Column(String(200), nullable=False, unique=True)
    slug        = Column(String(200), nullable=False, unique=True)
    content     = Column(Text, nullable=False)
    last_updated = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    def to_dict(self, include_content=False):
        d = {
            "id":           str(self.id),
            "title":        self.title,
            "slug":         self.slug,
            "last_updated": self.last_updated.isoformat() if self.last_updated else None,
        }
        if include_content:
            d["content"] = self.content
        return d

# ─────────────────────────────────────────────────────────────────
# TABLE 32: seo_settings
# Global SEO configuration — single row, key="global"
# ─────────────────────────────────────────────────────────────────
class SeoSetting(Base):
    __tablename__ = "seo_settings"

    key                  = Column(String(50), primary_key=True)   # always "global"
    meta_title           = Column(String(255), default="SecureVPN — Fast & Private VPN")
    meta_description     = Column(Text, default="Stay private and secure online with SecureVPN.")
    og_image_url         = Column(String(500))
    canonical_url        = Column(String(500))
    robots               = Column(String(100), default="index, follow")
    og_site_name         = Column(String(100), default="SecureVPN")
    og_type              = Column(String(50), default="website")
    twitter_card         = Column(String(50), default="summary_large_image")
    twitter_site         = Column(String(100))
    google_analytics_id  = Column(String(50))
    google_search_console = Column(String(255))
    updated_at           = Column(DateTime, default=datetime.utcnow)

    def to_dict(self):
        return {
            "key":                  self.key,
            "meta_title":           self.meta_title,
            "meta_description":     self.meta_description,
            "og_image_url":         self.og_image_url,
            "canonical_url":        self.canonical_url,
            "robots":               self.robots,
            "og_site_name":         self.og_site_name,
            "og_type":              self.og_type,
            "twitter_card":         self.twitter_card,
            "twitter_site":         self.twitter_site,
            "google_analytics_id":  self.google_analytics_id,
            "google_search_console": self.google_search_console,
            "updated_at":           self.updated_at.isoformat() if self.updated_at else None,
        }


# ─────────────────────────────────────────────────────────────────
# TABLE 33: media_files
# Media Library — uploaded images, videos, documents
# ─────────────────────────────────────────────────────────────────
class MediaFile(Base):
    __tablename__ = "media_files"

    id          = Column(GUID, primary_key=True, default=new_uuid)
    name        = Column(String(255), nullable=False)
    url         = Column(String(1000), nullable=False)
    file_type   = Column(String(20), nullable=False)  # image | video | document
    mime_type   = Column(String(100))
    size_bytes  = Column(Integer, default=0)
    width       = Column(Integer)
    height      = Column(Integer)
    alt_text    = Column(String(500))
    folder      = Column(String(255), default="/")
    uploaded_by = Column(String(100))
    created_at  = Column(DateTime, default=datetime.utcnow, index=True)

    def to_dict(self):
        size = self.size_bytes or 0
        if size >= 1_048_576:
            size_label = f"{size / 1_048_576:.1f} MB"
        elif size >= 1024:
            size_label = f"{size / 1024:.0f} KB"
        else:
            size_label = f"{size} B"
        return {
            "id":          str(self.id),
            "name":        self.name,
            "url":         self.url,
            "file_type":   self.file_type,
            "mime_type":   self.mime_type,
            "size_bytes":  self.size_bytes,
            "size_label":  size_label,
            "width":       self.width,
            "height":      self.height,
            "alt_text":    self.alt_text,
            "folder":      self.folder,
            "uploaded_by": self.uploaded_by,
            "created_at":  self.created_at.isoformat() if self.created_at else None,
        }


# ─────────────────────────────────────────────────────────────────
# TABLE 34: help_articles
# Support Center — Help Articles tab
# ─────────────────────────────────────────────────────────────────
class HelpArticle(Base):
    __tablename__ = "help_articles"

    id           = Column(GUID, primary_key=True, default=new_uuid)
    title        = Column(String(255), nullable=False)
    slug         = Column(String(255), nullable=False, unique=True, index=True)
    content      = Column(Text, nullable=False)
    excerpt      = Column(Text)
    category     = Column(String(100), default="general")   # getting_started|account|billing|technical|security|general
    tags         = Column(String(500))                       # comma-separated
    status       = Column(String(20), default="draft")       # draft | published
    is_featured  = Column(Boolean, default=False)
    author_name  = Column(String(100), default="AtmosVPN Team")
    author_email = Column(String(255))
    views        = Column(Integer, default=0)
    helpful_yes  = Column(Integer, default=0)
    helpful_no   = Column(Integer, default=0)
    published_at = Column(DateTime)
    created_at   = Column(DateTime, default=datetime.utcnow, index=True)
    updated_at   = Column(DateTime)

    def to_dict(self, include_content=True):
        d = {
            "id":           str(self.id),
            "title":        self.title,
            "slug":         self.slug,
            "excerpt":      self.excerpt,
            "category":     self.category,
            "tags":         self.tags.split(",") if self.tags else [],
            "status":       self.status,
            "is_featured":  self.is_featured,
            "author_name":  self.author_name,
            "author_email": self.author_email,
            "views":        self.views,
            "helpful_yes":  self.helpful_yes,
            "helpful_no":   self.helpful_no,
            "published_at": self.published_at.isoformat() if self.published_at else None,
            "created_at":   self.created_at.isoformat() if self.created_at else None,
            "updated_at":   self.updated_at.isoformat() if self.updated_at else None,
        }
        if include_content:
            d["content"] = self.content
        return d


# ─────────────────────────────────────────────────────────────────
# TABLE 35: faqs
# Support Center — FAQ Management tab
# ─────────────────────────────────────────────────────────────────
class FAQ(Base):
    __tablename__ = "faqs"

    id          = Column(GUID, primary_key=True, default=new_uuid)
    question    = Column(Text, nullable=False)
    answer      = Column(Text, nullable=False)
    category    = Column(String(100), default="general")   # general|billing|technical|account|security
    tags        = Column(String(500))
    status      = Column(String(20), default="published")  # draft | published
    sort_order  = Column(Integer, default=0)
    is_featured = Column(Boolean, default=False)
    created_by  = Column(String(255))
    views       = Column(Integer, default=0)
    helpful_yes = Column(Integer, default=0)
    helpful_no  = Column(Integer, default=0)
    created_at  = Column(DateTime, default=datetime.utcnow, index=True)
    updated_at  = Column(DateTime)

    def to_dict(self):
        return {
            "id":          str(self.id),
            "question":    self.question,
            "answer":      self.answer,
            "category":    self.category,
            "tags":        self.tags.split(",") if self.tags else [],
            "status":      self.status,
            "sort_order":  self.sort_order,
            "is_featured": self.is_featured,
            "created_by":  self.created_by,
            "views":       self.views,
            "helpful_yes": self.helpful_yes,
            "helpful_no":  self.helpful_no,
            "created_at":  self.created_at.isoformat() if self.created_at else None,
            "updated_at":  self.updated_at.isoformat() if self.updated_at else None,
        }
