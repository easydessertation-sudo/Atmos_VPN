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
from sqlalchemy.pool import NullPool
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

# ─────────────────────────────────────────────────────────────────
# Connection pool strategy:
#
# Supabase port 6543 → PgBouncer in TRANSACTION mode.
#   In transaction mode, PgBouncer is the pooler — SQLAlchemy's own
#   connection pool conflicts with it, causing "server closed the
#   connection unexpectedly" errors when stale sockets are reused.
#   Fix: NullPool — SQLAlchemy opens/closes a real connection per
#   request; PgBouncer transparently pools them on its side.
#
# Supabase port 5432 → direct Postgres (session mode).
#   Here a regular pool_size + pool_pre_ping config is fine.
#
# SQLite (local dev) → no pool args at all.
# ─────────────────────────────────────────────────────────────────
_is_sqlite    = DATABASE_URL.startswith("sqlite")
_is_pgbouncer = ":6543" in DATABASE_URL   # Supabase transaction-mode pooler

if _is_sqlite:
    # SQLite needs check_same_thread=False; no pool config needed
    _connect_args  = {"check_same_thread": False}
    _engine_kwargs = dict(connect_args=_connect_args)

elif _is_pgbouncer:
    # Supabase PgBouncer (transaction mode)
    # NullPool opens/closes a connection on every request, which can cause
    # "timeout expired" errors under rapid requests or rate limits.
    # Instead, we use a small pool with pre_ping to keep connections alive
    # but drop them if the server closes them unexpectedly.
    _connect_args = {
        "connect_timeout": 15,
        "keepalives":          1,
        "keepalives_idle":     10,
        "keepalives_interval": 5,
        "keepalives_count":    3,
    }
    _engine_kwargs = dict(
        connect_args=_connect_args,
        pool_size=5,
        max_overflow=10,
        pool_pre_ping=True,
        pool_recycle=120,   # Supabase PgBouncer drops idle sockets quickly
        pool_timeout=30,
    )

else:
    # Direct Postgres (port 5432)
    _connect_args = {
        "connect_timeout": 15,
        "keepalives":          1,
        "keepalives_idle":     30,
        "keepalives_interval": 5,
        "keepalives_count":    3,
    }
    _engine_kwargs = dict(
        connect_args=_connect_args,
        pool_size=10,
        max_overflow=10,
        pool_pre_ping=True,
        pool_recycle=300,
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

    # Free tier VPN time tracking
    vpn_expiration_time   = Column(DateTime, nullable=True)

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

    # OAuth
    google_id    = Column(String(100), nullable=True, unique=True, index=True)
    apple_id     = Column(String(100), nullable=True, unique=True, index=True)
    avatar_url   = Column(String(500), nullable=True)
    auth_provider = Column(String(20), default="email")  # "email" | "google" | "apple"

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
            "avatar_url":            self.avatar_url,
            "auth_provider":         self.auth_provider or "email",
            "plan":                  self.plan,
            "plan_expires_at":       self.plan_expires_at.isoformat() if self.plan_expires_at else None,
            "subscription_status":   self.subscription_status,
            "stripe_customer_id":    self.stripe_customer_id,
            "bandwidth_used_bytes":  self.bandwidth_used_bytes,
            "bandwidth_limit_bytes": self.bandwidth_limit_bytes,
            "vpn_expiration_time":   self.vpn_expiration_time.isoformat() if self.vpn_expiration_time else None,
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
            "ping_ms":       self.ping_ms,
            "load_pct":      self.load_pct,
            "capacity_mbps": self.capacity_mbps,
            "is_online":     self.is_online,
            "wg_port":       self.wg_port,
            "max_peers":     self.max_peers,
            "current_peers": self.current_peers,
            "types": {
                "streaming":    self.is_streaming,
                "gaming":       self.is_gaming,
                "crypto":       self.is_crypto,
                "p2p":          self.is_p2p,
                "dedicated_ip": self.is_dedicated_ip,
            },
            "protocols": self.protocols.split(",") if self.protocols else [],
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


# ─────────────────────────────────────────────────────────────────
# TABLE 12: ads
# Ad creatives managed by the admin panel.
# Free-plan users watch these to earn bonus VPN minutes.
# ─────────────────────────────────────────────────────────────────
class Ad(Base):
    __tablename__ = "ads"

    id          = Column(GUID, primary_key=True, default=new_uuid)

    # Ad content
    title       = Column(String(255), nullable=False)
    description = Column(Text, nullable=True)
    image_url   = Column(String(500), nullable=True)   # banner / thumbnail
    video_url   = Column(String(500), nullable=True)   # optional rewarded video
    click_url   = Column(String(500), nullable=True)   # where to go on tap

    # Ad behaviour
    # ad_type: "banner" | "interstitial" | "rewarded"
    ad_type          = Column(String(20), default="rewarded")
    duration_seconds = Column(Integer, default=30)     # how long user must watch
    reward_minutes   = Column(Integer, default=30)     # VPN minutes credited on completion

    # Targeting
    # target_plans: comma-separated plan keys e.g. "free" or "free,starter"
    target_plans = Column(String(100), default="free")
    priority     = Column(Integer, default=0)          # higher = shown first

    # Admin control
    is_active  = Column(Boolean, default=True, index=True)
    created_at = Column(DateTime, default=datetime.utcnow, index=True)
    updated_at = Column(DateTime, default=datetime.utcnow)

    # Relationship
    views = relationship("AdView", back_populates="ad", lazy="select", cascade="all, delete-orphan")

    def to_dict(self):
        return {
            "id":               str(self.id),
            "title":            self.title,
            "description":      self.description,
            "image_url":        self.image_url,
            "video_url":        self.video_url,
            "click_url":        self.click_url,
            "ad_type":          self.ad_type,
            "duration_seconds": self.duration_seconds,
            "reward_minutes":   self.reward_minutes,
            "target_plans":     self.target_plans.split(",") if self.target_plans else ["free"],
            "priority":         self.priority,
            "is_active":        self.is_active,
            "created_at":       self.created_at.isoformat() if self.created_at else None,
            "updated_at":       self.updated_at.isoformat() if self.updated_at else None,
        }


# ─────────────────────────────────────────────────────────────────
# TABLE 13: ad_views
# Records every ad a user watches and the reward credited.
# Used for cooldown enforcement and audit/analytics.
# ─────────────────────────────────────────────────────────────────
class AdView(Base):
    __tablename__ = "ad_views"

    id      = Column(GUID, primary_key=True, default=new_uuid)
    user_id = Column(GUID, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    ad_id   = Column(GUID, ForeignKey("ads.id",   ondelete="CASCADE"), nullable=False, index=True)

    watched_at     = Column(DateTime, default=datetime.utcnow, index=True)  # when reward claimed
    reward_minutes = Column(Integer,  default=30)                           # minutes credited

    # Snapshot of vpn_expiration_time before and after — useful for support/debugging
    session_before = Column(DateTime, nullable=True)
    session_after  = Column(DateTime, nullable=True)

    # Relationships
    ad = relationship("Ad", back_populates="views")

    def to_dict(self):
        return {
            "id":             str(self.id),
            "user_id":        str(self.user_id),
            "ad_id":          str(self.ad_id),
            "watched_at":     self.watched_at.isoformat() + "Z",
            "reward_minutes": self.reward_minutes,
            "session_before": self.session_before.isoformat() + "Z" if self.session_before else None,
            "session_after":  self.session_after.isoformat()  + "Z" if self.session_after  else None,
        }

    __table_args__ = (
        Index("idx_ad_views_user_watched", "user_id", "watched_at"),
    )


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
# TABLE 11: plans
# Editable plan configuration — managed by admin panel (port 5001).
# vpn-backend reads from this table for GET /api/plans so that
# any admin price/feature edit reflects on the user-facing app too.
# ─────────────────────────────────────────────────────────────────
class Plan(Base):
    __tablename__ = "plans"

    key         = Column(String(50), primary_key=True)   # "free"|"starter"|"pro"|"premium"
    label       = Column(String(100), nullable=False)
    description = Column(Text, nullable=True)
    amount_usd  = Column(Float, default=0.0)
    per         = Column(String(20), default="mo")       # "mo" | "seat" | "year"
    currency    = Column(String(5), default="USD")

    stripe_price_id_monthly = Column(String(100), nullable=True)
    stripe_price_id_yearly  = Column(String(100), nullable=True)

    max_devices     = Column(Integer, default=1)
    bandwidth_gb    = Column(Integer, nullable=True)     # null = unlimited
    server_count    = Column(Integer, nullable=True)
    simultaneous    = Column(Integer, default=1)

    has_streaming        = Column(Boolean, default=False)
    has_p2p              = Column(Boolean, default=False)
    has_dedicated_ip     = Column(Boolean, default=False)
    has_ad_blocker       = Column(Boolean, default=True)
    has_kill_switch      = Column(Boolean, default=True)
    has_priority_support = Column(Boolean, default=False)

    is_visible  = Column(Boolean, default=True)
    is_default  = Column(Boolean, default=False)

    updated_at  = Column(DateTime, default=datetime.utcnow)
    created_at  = Column(DateTime, default=datetime.utcnow)

    def to_dict(self):
        return {
            "key":            self.key,
            "label":          self.label,
            "description":    self.description,
            "amount_usd":     self.amount_usd,
            "amount_label":   (
                f"${self.amount_usd:.2f}/{self.per}"
                if self.amount_usd > 0
                else f"$0/{self.per}"
            ),
            "per":            self.per,
            "currency":       self.currency,
            "stripe_price_id_monthly": self.stripe_price_id_monthly,
            "stripe_price_id_yearly":  self.stripe_price_id_yearly,
            "limits": {
                "max_devices":  self.max_devices,
                "bandwidth_gb": self.bandwidth_gb,
                "server_count": self.server_count,
                "simultaneous": self.simultaneous,
            },
            "features": {
                "streaming":        self.has_streaming,
                "p2p":              self.has_p2p,
                "dedicated_ip":     self.has_dedicated_ip,
                "ad_blocker":       self.has_ad_blocker,
                "kill_switch":      self.has_kill_switch,
                "priority_support": self.has_priority_support,
            },
            "is_visible": self.is_visible,
            "is_default": self.is_default,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }
