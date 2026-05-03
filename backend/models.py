from flask_sqlalchemy import SQLAlchemy
from datetime import datetime

db = SQLAlchemy()

class User(db.Model):
    __tablename__ = 'users'
    id = db.Column(db.Integer, primary_key=True)
    email = db.Column(db.String(255), unique=True, nullable=False, index=True)
    password_hash = db.Column(db.String(255), nullable=False)
    full_name = db.Column(db.String(255))
    plan = db.Column(db.String(50), default='free')          # free | essential | elite | ultimate
    plan_expires_at = db.Column(db.DateTime)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    last_login = db.Column(db.DateTime)
    email_verified = db.Column(db.Boolean, default=False)
    two_fa_enabled = db.Column(db.Boolean, default=False)
    two_fa_secret = db.Column(db.String(32))
    sessions = db.relationship('VPNSession', backref='user', lazy=True)
    devices = db.relationship('Device', backref='user', lazy=True)
    subscriptions = db.relationship('Subscription', backref='user', lazy=True)

    def to_dict(self, safe=True):
        d = {
            'id': self.id,
            'email': self.email,
            'full_name': self.full_name,
            'plan': self.plan,
            'plan_expires_at': self.plan_expires_at.isoformat() if self.plan_expires_at else None,
            'created_at': self.created_at.isoformat(),
            'email_verified': self.email_verified,
            'two_fa_enabled': self.two_fa_enabled,
        }
        return d


class VPNServer(db.Model):
    __tablename__ = 'vpn_servers'
    id = db.Column(db.String(20), primary_key=True)   # e.g. "lon-1"
    name = db.Column(db.String(100), nullable=False)
    city = db.Column(db.String(100))
    country = db.Column(db.String(100))
    country_code = db.Column(db.String(5))
    flag = db.Column(db.String(5))
    ip_address = db.Column(db.String(45))
    ping_ms = db.Column(db.Integer)
    load_pct = db.Column(db.Integer, default=0)
    capacity_mbps = db.Column(db.Integer, default=1000)
    is_online = db.Column(db.Boolean, default=True)
    is_streaming = db.Column(db.Boolean, default=False)
    is_gaming = db.Column(db.Boolean, default=False)
    is_crypto = db.Column(db.Boolean, default=False)
    is_p2p = db.Column(db.Boolean, default=False)
    is_dedicated_ip = db.Column(db.Boolean, default=False)
    protocols = db.Column(db.String(255), default='wireguard,openvpn,ikev2')
    sessions = db.relationship('VPNSession', backref='server', lazy=True)

    def to_dict(self):
        return {
            'id': self.id,
            'name': self.name,
            'city': self.city,
            'country': self.country,
            'country_code': self.country_code,
            'flag': self.flag,
            'ping_ms': self.ping_ms,
            'load_pct': self.load_pct,
            'capacity_mbps': self.capacity_mbps,
            'is_online': self.is_online,
            'types': {
                'streaming': self.is_streaming,
                'gaming': self.is_gaming,
                'crypto': self.is_crypto,
                'p2p': self.is_p2p,
                'dedicated_ip': self.is_dedicated_ip,
            },
            'protocols': self.protocols.split(','),
        }


class VPNSession(db.Model):
    __tablename__ = 'vpn_sessions'
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=False, index=True)
    server_id = db.Column(db.String(20), db.ForeignKey('vpn_servers.id'))
    mode = db.Column(db.String(50), default='standard')  # standard|streaming|gaming|crypto
    protocol = db.Column(db.String(50), default='wireguard')
    started_at = db.Column(db.DateTime, default=datetime.utcnow)
    ended_at = db.Column(db.DateTime)
    bytes_down = db.Column(db.BigInteger, default=0)
    bytes_up = db.Column(db.BigInteger, default=0)
    ip_assigned = db.Column(db.String(45))
    device_name = db.Column(db.String(100))
    is_active = db.Column(db.Boolean, default=True)

    def to_dict(self):
        duration = None
        if self.started_at:
            end = self.ended_at or datetime.utcnow()
            duration = int((end - self.started_at).total_seconds())
        return {
            'id': self.id,
            'server_id': self.server_id,
            'mode': self.mode,
            'protocol': self.protocol,
            'started_at': self.started_at.isoformat(),
            'ended_at': self.ended_at.isoformat() if self.ended_at else None,
            'duration_seconds': duration,
            'bytes_down': self.bytes_down,
            'bytes_up': self.bytes_up,
            'ip_assigned': self.ip_assigned,
            'device_name': self.device_name,
            'is_active': self.is_active,
        }


class Device(db.Model):
    __tablename__ = 'devices'
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=False)
    name = db.Column(db.String(100))
    platform = db.Column(db.String(50))   # ios|android|windows|mac|linux|router
    device_fingerprint = db.Column(db.String(255))
    last_seen = db.Column(db.DateTime, default=datetime.utcnow)
    is_trusted = db.Column(db.Boolean, default=True)

    def to_dict(self):
        return {
            'id': self.id,
            'name': self.name,
            'platform': self.platform,
            'last_seen': self.last_seen.isoformat() if self.last_seen else None,
            'is_trusted': self.is_trusted,
        }


class Subscription(db.Model):
    __tablename__ = 'subscriptions'
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=False)
    plan = db.Column(db.String(50))          # essential|elite|ultimate
    billing_cycle = db.Column(db.String(20)) # monthly|annual
    amount_pence = db.Column(db.Integer)
    currency = db.Column(db.String(5), default='GBP')
    status = db.Column(db.String(20), default='active')  # active|cancelled|expired
    stripe_subscription_id = db.Column(db.String(100))
    started_at = db.Column(db.DateTime, default=datetime.utcnow)
    expires_at = db.Column(db.DateTime)
    cancelled_at = db.Column(db.DateTime)

    def to_dict(self):
        return {
            'id': self.id,
            'plan': self.plan,
            'billing_cycle': self.billing_cycle,
            'amount_pence': self.amount_pence,
            'currency': self.currency,
            'status': self.status,
            'started_at': self.started_at.isoformat(),
            'expires_at': self.expires_at.isoformat() if self.expires_at else None,
        }


class SupportTicket(db.Model):
    __tablename__ = 'support_tickets'
    id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, db.ForeignKey('users.id'))
    email = db.Column(db.String(255), nullable=False)
    subject = db.Column(db.String(255))
    message = db.Column(db.Text)
    category = db.Column(db.String(50))   # billing|technical|general|abuse
    status = db.Column(db.String(20), default='open')
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow)

    def to_dict(self):
        return {
            'id': self.id,
            'subject': self.subject,
            'category': self.category,
            'status': self.status,
            'created_at': self.created_at.isoformat(),
        }
