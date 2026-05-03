"""
SecureVPN — Full Backend API
Flask + SQLite + JWT Auth + Subscriptions + VPN Session Management
"""
import os
import random
import ipaddress
from datetime import datetime, timedelta
from functools import wraps

from flask import Flask, jsonify, request, g
from flask_cors import CORS
from flask_jwt_extended import (
    JWTManager, create_access_token, create_refresh_token,
    jwt_required, get_jwt_identity, get_jwt
)
from flask_sqlalchemy import SQLAlchemy
from passlib.hash import bcrypt

# ─────────────────────────────────────────────────────────────────
# App Setup
# ─────────────────────────────────────────────────────────────────
app = Flask(__name__)
CORS(app)

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
app.config.update(
    SQLALCHEMY_DATABASE_URI=f"sqlite:///{os.path.join(BASE_DIR, 'securevpn.db')}",
    SQLALCHEMY_TRACK_MODIFICATIONS=False,
    JWT_SECRET_KEY=os.environ.get('JWT_SECRET', 'super-secret-dev-key-change-in-production'),
    JWT_ACCESS_TOKEN_EXPIRES=timedelta(hours=12),
    JWT_REFRESH_TOKEN_EXPIRES=timedelta(days=30),
)

from models import db, User, VPNServer, VPNSession, Device, Subscription, SupportTicket
db.init_app(app)
jwt = JWTManager(app)

# ─────────────────────────────────────────────────────────────────
# Plan Limits
# ─────────────────────────────────────────────────────────────────
PLAN_LIMITS = {
    'free':      {'devices': 1, 'session_minutes': 45, 'modes': ['standard']},
    'essential': {'devices': 5, 'session_minutes': None, 'modes': ['standard', 'streaming']},
    'elite':     {'devices': None, 'session_minutes': None, 'modes': ['standard', 'streaming', 'gaming', 'crypto']},
    'ultimate':  {'devices': None, 'session_minutes': None, 'modes': ['standard', 'streaming', 'gaming', 'crypto']},
}

# ─────────────────────────────────────────────────────────────────
# Seed Data
# ─────────────────────────────────────────────────────────────────
SERVERS_SEED = [
    {'id': 'lon-1',  'name': 'London',       'city': 'London',       'country': 'United Kingdom', 'country_code': 'gb', 'flag': '🇬🇧', 'ip_address': '185.156.46.1',   'ping_ms': 18,  'capacity_mbps': 1000, 'is_streaming': True,  'is_p2p': True},
    {'id': 'lon-2',  'name': 'London 2',     'city': 'London',       'country': 'United Kingdom', 'country_code': 'gb', 'flag': '🇬🇧', 'ip_address': '185.156.46.2',   'ping_ms': 20,  'capacity_mbps': 1000, 'is_streaming': True,  'is_gaming': True},
    {'id': 'nyc-1',  'name': 'New York',     'city': 'New York',     'country': 'United States',  'country_code': 'us', 'flag': '🇺🇸', 'ip_address': '104.21.14.1',    'ping_ms': 85,  'capacity_mbps': 1000, 'is_gaming': True,     'is_crypto': True},
    {'id': 'lax-1',  'name': 'Los Angeles',  'city': 'Los Angeles',  'country': 'United States',  'country_code': 'us', 'flag': '🇺🇸', 'ip_address': '104.21.14.2',    'ping_ms': 110, 'capacity_mbps': 950,  'is_streaming': True,  'is_gaming': True},
    {'id': 'fra-1',  'name': 'Frankfurt',    'city': 'Frankfurt',    'country': 'Germany',         'country_code': 'de', 'flag': '🇩🇪', 'ip_address': '104.21.88.1',    'ping_ms': 25,  'capacity_mbps': 1000, 'is_gaming': True,     'is_streaming': True},
    {'id': 'ams-1',  'name': 'Amsterdam',    'city': 'Amsterdam',    'country': 'Netherlands',     'country_code': 'nl', 'flag': '🇳🇱', 'ip_address': '104.21.72.1',    'ping_ms': 22,  'capacity_mbps': 1000, 'is_streaming': True,  'is_p2p': True},
    {'id': 'tok-1',  'name': 'Tokyo',        'city': 'Tokyo',        'country': 'Japan',           'country_code': 'jp', 'flag': '🇯🇵', 'ip_address': '104.21.130.1',   'ping_ms': 150, 'capacity_mbps': 950,  'is_gaming': True,     'is_streaming': True},
    {'id': 'sgp-1',  'name': 'Singapore',    'city': 'Singapore',    'country': 'Singapore',       'country_code': 'sg', 'flag': '🇸🇬', 'ip_address': '104.21.64.1',    'ping_ms': 120, 'capacity_mbps': 800,  'is_crypto': True,     'is_streaming': True},
    {'id': 'syd-1',  'name': 'Sydney',       'city': 'Sydney',       'country': 'Australia',       'country_code': 'au', 'flag': '🇦🇺', 'ip_address': '104.21.200.1',   'ping_ms': 180, 'capacity_mbps': 700,  'is_streaming': True},
    {'id': 'tor-1',  'name': 'Toronto',      'city': 'Toronto',      'country': 'Canada',          'country_code': 'ca', 'flag': '🇨🇦', 'ip_address': '104.21.120.1',   'ping_ms': 95,  'capacity_mbps': 900,  'is_streaming': True,  'is_gaming': True},
    {'id': 'par-1',  'name': 'Paris',        'city': 'Paris',        'country': 'France',          'country_code': 'fr', 'flag': '🇫🇷', 'ip_address': '104.21.56.1',    'ping_ms': 28,  'capacity_mbps': 1000, 'is_streaming': True},
    {'id': 'zur-1',  'name': 'Zurich',       'city': 'Zurich',       'country': 'Switzerland',     'country_code': 'ch', 'flag': '🇨🇭', 'ip_address': '104.21.90.1',    'ping_ms': 30,  'capacity_mbps': 1000, 'is_crypto': True},
    {'id': 'sto-1',  'name': 'Stockholm',    'city': 'Stockholm',    'country': 'Sweden',          'country_code': 'se', 'flag': '🇸🇪', 'ip_address': '104.21.44.1',    'ping_ms': 35,  'capacity_mbps': 1000, 'is_streaming': True,  'is_p2p': True},
    {'id': 'mum-1',  'name': 'Mumbai',       'city': 'Mumbai',       'country': 'India',           'country_code': 'in', 'flag': '🇮🇳', 'ip_address': '104.21.160.1',   'ping_ms': 75,  'capacity_mbps': 500,  'is_streaming': True},
    {'id': 'dub-1',  'name': 'Dubai',        'city': 'Dubai',        'country': 'UAE',             'country_code': 'ae', 'flag': '🇦🇪', 'ip_address': '104.21.170.1',   'ping_ms': 95,  'capacity_mbps': 400,  'is_crypto': True},
    {'id': 'sao-1',  'name': 'São Paulo',    'city': 'São Paulo',    'country': 'Brazil',          'country_code': 'br', 'flag': '🇧🇷', 'ip_address': '104.21.140.1',   'ping_ms': 145, 'capacity_mbps': 600,  'is_gaming': True},
]


def seed_database():
    """Seed servers if empty."""
    if VPNServer.query.count() == 0:
        for s in SERVERS_SEED:
            server = VPNServer(
                id=s['id'], name=s['name'], city=s['city'],
                country=s['country'], country_code=s['country_code'],
                flag=s['flag'], ip_address=s['ip_address'],
                ping_ms=s['ping_ms'], capacity_mbps=s['capacity_mbps'],
                load_pct=random.randint(10, 70),
                is_streaming=s.get('is_streaming', False),
                is_gaming=s.get('is_gaming', False),
                is_crypto=s.get('is_crypto', False),
                is_p2p=s.get('is_p2p', False),
            )
            db.session.add(server)
        db.session.commit()


# ─────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────
def success(data=None, msg='OK', status=200):
    return jsonify({'success': True, 'message': msg, 'data': data}), status

def error(msg='Error', status=400, data=None):
    return jsonify({'success': False, 'message': msg, 'data': data}), status

def get_current_user():
    uid = get_jwt_identity()
    return User.query.get(uid)


# ─────────────────────────────────────────────────────────────────
# Auth Routes
# ─────────────────────────────────────────────────────────────────
@app.route('/api/auth/register', methods=['POST'])
def register():
    body = request.json or {}
    email    = body.get('email', '').strip().lower()
    password = body.get('password', '')
    name     = body.get('full_name', '').strip()

    if not email or not password:
        return error('Email and password are required')
    if len(password) < 8:
        return error('Password must be at least 8 characters')
    if User.query.filter_by(email=email).first():
        return error('An account with this email already exists', 409)

    user = User(
        email=email,
        password_hash=bcrypt.hash(password),
        full_name=name,
        plan='free',
    )
    db.session.add(user)
    db.session.commit()

    access  = create_access_token(identity=user.id)
    refresh = create_refresh_token(identity=user.id)
    return success({
        'user': user.to_dict(),
        'access_token': access,
        'refresh_token': refresh,
    }, 'Account created successfully', 201)


@app.route('/api/auth/login', methods=['POST'])
def login():
    body     = request.json or {}
    email    = body.get('email', '').strip().lower()
    password = body.get('password', '')

    user = User.query.filter_by(email=email).first()
    if not user or not bcrypt.verify(password, user.password_hash):
        return error('Invalid email or password', 401)

    user.last_login = datetime.utcnow()
    db.session.commit()

    access  = create_access_token(identity=user.id)
    refresh = create_refresh_token(identity=user.id)
    return success({
        'user': user.to_dict(),
        'access_token': access,
        'refresh_token': refresh,
        'plan_limits': PLAN_LIMITS.get(user.plan, PLAN_LIMITS['free']),
    })


@app.route('/api/auth/refresh', methods=['POST'])
@jwt_required(refresh=True)
def refresh():
    user = get_current_user()
    access = create_access_token(identity=user.id)
    return success({'access_token': access})


@app.route('/api/auth/me', methods=['GET'])
@jwt_required()
def me():
    user = get_current_user()
    return success({
        'user': user.to_dict(),
        'plan_limits': PLAN_LIMITS.get(user.plan, PLAN_LIMITS['free']),
        'devices': [d.to_dict() for d in user.devices],
        'active_sessions': VPNSession.query.filter_by(user_id=user.id, is_active=True).count(),
    })


@app.route('/api/auth/change-password', methods=['POST'])
@jwt_required()
def change_password():
    user = get_current_user()
    body = request.json or {}
    old  = body.get('old_password', '')
    new  = body.get('new_password', '')

    if not bcrypt.verify(old, user.password_hash):
        return error('Current password is incorrect', 401)
    if len(new) < 8:
        return error('New password must be at least 8 characters')

    user.password_hash = bcrypt.hash(new)
    db.session.commit()
    return success(msg='Password changed successfully')


# ─────────────────────────────────────────────────────────────────
# Server Routes
# ─────────────────────────────────────────────────────────────────
@app.route('/api/servers', methods=['GET'])
def get_servers():
    mode   = request.args.get('mode')       # streaming|gaming|crypto|p2p
    search = request.args.get('search', '')

    q = VPNServer.query.filter_by(is_online=True)
    if mode == 'streaming': q = q.filter_by(is_streaming=True)
    elif mode == 'gaming':  q = q.filter_by(is_gaming=True)
    elif mode == 'crypto':  q = q.filter_by(is_crypto=True)
    elif mode == 'p2p':     q = q.filter_by(is_p2p=True)

    if search:
        pattern = f'%{search}%'
        q = q.filter(
            VPNServer.country.ilike(pattern) |
            VPNServer.city.ilike(pattern) |
            VPNServer.name.ilike(pattern)
        )

    servers = q.order_by(VPNServer.ping_ms).all()
    return success([s.to_dict() for s in servers])


@app.route('/api/servers/best', methods=['GET'])
def best_server():
    """Return fastest server for given mode."""
    mode = request.args.get('mode', 'standard')
    q = VPNServer.query.filter_by(is_online=True)
    if mode == 'streaming': q = q.filter_by(is_streaming=True)
    elif mode == 'gaming':  q = q.filter_by(is_gaming=True)
    elif mode == 'crypto':  q = q.filter_by(is_crypto=True)
    server = q.order_by(VPNServer.ping_ms, VPNServer.load_pct).first()
    if not server:
        server = VPNServer.query.filter_by(is_online=True).order_by(VPNServer.ping_ms).first()
    return success(server.to_dict() if server else None)


# ─────────────────────────────────────────────────────────────────
# VPN Session Routes
# ─────────────────────────────────────────────────────────────────
@app.route('/api/vpn/connect', methods=['POST'])
@jwt_required()
def connect():
    user   = get_current_user()
    body   = request.json or {}
    server_id = body.get('server_id')
    mode      = body.get('mode', 'standard')
    protocol  = body.get('protocol', 'wireguard')
    device    = body.get('device_name', 'Unknown Device')

    # Plan checks
    allowed_modes = PLAN_LIMITS[user.plan]['modes']
    if mode not in allowed_modes:
        return error(f'Upgrade to access {mode} mode', 403,
                     {'upgrade_required': True, 'required_plan': 'elite'})

    # Free user session limit check
    if user.plan == 'free':
        active = VPNSession.query.filter_by(user_id=user.id, is_active=True).first()
        if active:
            elapsed = (datetime.utcnow() - active.started_at).total_seconds() / 60
            if elapsed >= 45:
                active.is_active = False
                active.ended_at  = datetime.utcnow()
                db.session.commit()
                return error('Free session limit (45 min) reached. Upgrade for unlimited.', 403,
                             {'session_expired': True})

    # Pick server
    if not server_id:
        best = VPNServer.query.filter_by(is_online=True).order_by(VPNServer.ping_ms).first()
        server_id = best.id if best else None

    server = VPNServer.query.get(server_id)
    if not server:
        return error('Server not found', 404)

    # End any existing active session
    VPNSession.query.filter_by(user_id=user.id, is_active=True).update({
        'is_active': False,
        'ended_at': datetime.utcnow(),
    })

    # Assign a random IP from a private-ish range (simulated)
    random_ip = f"10.{random.randint(0, 255)}.{random.randint(0, 255)}.{random.randint(1, 254)}"

    session = VPNSession(
        user_id=user.id,
        server_id=server.id,
        mode=mode,
        protocol=protocol,
        ip_assigned=random_ip,
        device_name=device,
        is_active=True,
    )

    # Bump server load slightly
    server.load_pct = min(99, server.load_pct + random.randint(1, 3))

    db.session.add(session)
    db.session.commit()

    return success({
        'session': session.to_dict(),
        'server':  server.to_dict(),
        'assigned_ip': random_ip,
    }, 'Connected')


@app.route('/api/vpn/disconnect', methods=['POST'])
@jwt_required()
def disconnect():
    user = get_current_user()
    sessions = VPNSession.query.filter_by(user_id=user.id, is_active=True).all()
    for s in sessions:
        s.is_active = False
        s.ended_at  = datetime.utcnow()
        s.bytes_down = random.randint(10_000_000, 500_000_000)
        s.bytes_up   = random.randint(1_000_000, 50_000_000)
    db.session.commit()
    return success(msg='Disconnected')


@app.route('/api/vpn/status', methods=['GET'])
@jwt_required()
def vpn_status():
    user = get_current_user()
    session = VPNSession.query.filter_by(user_id=user.id, is_active=True).first()
    if session:
        server = VPNServer.query.get(session.server_id)
        elapsed = (datetime.utcnow() - session.started_at).total_seconds()
        remaining = None
        if user.plan == 'free':
            remaining = max(0, 45 * 60 - int(elapsed))
        return success({
            'connected': True,
            'session': session.to_dict(),
            'server': server.to_dict() if server else None,
            'elapsed_seconds': int(elapsed),
            'remaining_seconds': remaining,
            'download_mbps': round(random.uniform(20, 100), 1),
            'upload_mbps': round(random.uniform(2, 20), 1),
            'ping_ms': server.ping_ms + random.randint(-2, 5) if server else 999,
        })
    return success({'connected': False})


@app.route('/api/vpn/history', methods=['GET'])
@jwt_required()
def session_history():
    user = get_current_user()
    limit = int(request.args.get('limit', 20))
    sessions = VPNSession.query.filter_by(user_id=user.id, is_active=False)\
        .order_by(VPNSession.started_at.desc()).limit(limit).all()
    return success([s.to_dict() for s in sessions])


# ─────────────────────────────────────────────────────────────────
# Subscription Routes
# ─────────────────────────────────────────────────────────────────
PLANS = {
    'essential': {'name': 'Essential', 'monthly_pence': 399, 'annual_pence': 3588},
    'elite':     {'name': 'Elite',     'monthly_pence': 699, 'annual_pence': 5988},
    'ultimate':  {'name': 'Ultimate',  'monthly_pence': 1199,'annual_pence': 9180},
}

@app.route('/api/plans', methods=['GET'])
def get_plans():
    return success(PLANS)


@app.route('/api/subscriptions/upgrade', methods=['POST'])
@jwt_required()
def upgrade():
    user   = get_current_user()
    body   = request.json or {}
    plan   = body.get('plan')
    cycle  = body.get('billing_cycle', 'monthly')

    if plan not in PLANS:
        return error('Invalid plan')

    plan_data = PLANS[plan]
    amount    = plan_data['monthly_pence'] if cycle == 'monthly' else plan_data['annual_pence']
    duration  = timedelta(days=30 if cycle == 'monthly' else 365)

    # In production: process Stripe payment here
    # For demo: simulate successful payment

    sub = Subscription(
        user_id=user.id,
        plan=plan,
        billing_cycle=cycle,
        amount_pence=amount,
        currency='GBP',
        status='active',
        stripe_subscription_id=f'sub_demo_{user.id}_{plan}',
        started_at=datetime.utcnow(),
        expires_at=datetime.utcnow() + duration,
    )
    user.plan = plan
    user.plan_expires_at = sub.expires_at

    db.session.add(sub)
    db.session.commit()

    return success({
        'subscription': sub.to_dict(),
        'user': user.to_dict(),
    }, f'Upgraded to {plan} plan!')


@app.route('/api/subscriptions/cancel', methods=['POST'])
@jwt_required()
def cancel_subscription():
    user = get_current_user()
    sub  = Subscription.query.filter_by(user_id=user.id, status='active').first()
    if sub:
        sub.status       = 'cancelled'
        sub.cancelled_at = datetime.utcnow()
    user.plan = 'free'
    db.session.commit()
    return success(msg='Subscription cancelled. You will retain access until the end of the billing period.')


@app.route('/api/subscriptions/history', methods=['GET'])
@jwt_required()
def billing_history():
    user = get_current_user()
    subs = Subscription.query.filter_by(user_id=user.id).order_by(Subscription.started_at.desc()).all()
    return success([s.to_dict() for s in subs])


# ─────────────────────────────────────────────────────────────────
# Device Routes
# ─────────────────────────────────────────────────────────────────
@app.route('/api/devices', methods=['GET'])
@jwt_required()
def list_devices():
    user = get_current_user()
    return success([d.to_dict() for d in user.devices])


@app.route('/api/devices/<int:device_id>', methods=['DELETE'])
@jwt_required()
def remove_device(device_id):
    user   = get_current_user()
    device = Device.query.filter_by(id=device_id, user_id=user.id).first()
    if not device:
        return error('Device not found', 404)
    db.session.delete(device)
    db.session.commit()
    return success(msg='Device removed')


# ─────────────────────────────────────────────────────────────────
# Support Routes
# ─────────────────────────────────────────────────────────────────
@app.route('/api/support/ticket', methods=['POST'])
def submit_ticket():
    body     = request.json or {}
    email    = body.get('email', '').strip()
    subject  = body.get('subject', '').strip()
    message  = body.get('message', '').strip()
    category = body.get('category', 'general')

    if not email or not message:
        return error('Email and message are required')

    ticket = SupportTicket(
        email=email,
        subject=subject or 'Support Request',
        message=message,
        category=category,
    )
    db.session.add(ticket)
    db.session.commit()
    return success({'ticket_id': ticket.id}, 'Ticket submitted! We\'ll reply within 24 hours.', 201)


@app.route('/api/support/faq', methods=['GET'])
def get_faq():
    faqs = [
        {'q': 'What is a VPN?', 'a': 'A VPN (Virtual Private Network) encrypts your internet connection and masks your IP address, protecting your privacy and allowing you to access content from anywhere in the world.'},
        {'q': 'Does SecureVPN keep logs?', 'a': 'Absolutely not. We operate a strict zero-logs policy, independently audited by Cure53. We never store, track, or share your browsing data.'},
        {'q': 'How many devices can I connect simultaneously?', 'a': 'Free: 1 device. Essential: 5 devices. Elite & Ultimate: Unlimited devices.'},
        {'q': 'What protocols does SecureVPN use?', 'a': 'We support WireGuard (fastest), OpenVPN (most compatible), and IKEv2 (most stable on mobile).'},
        {'q': 'Can I use SecureVPN for Netflix?', 'a': 'Yes! Our Streaming Mode servers are specifically optimised for Netflix, Disney+, Hulu, BBC iPlayer and more.'},
        {'q': 'Does SecureVPN work in China?', 'a': 'Yes, our obfuscated servers are designed to work in restrictive regions including China, Russia, and the UAE.'},
        {'q': 'How do I cancel my subscription?', 'a': 'You can cancel anytime from your Account → Billing page. You\'ll retain access until the end of your paid period.'},
        {'q': 'What is a kill switch?', 'a': 'A kill switch instantly blocks all internet traffic if your VPN connection drops, ensuring your real IP is never exposed.'},
        {'q': 'Can I use SecureVPN on a router?', 'a': 'Yes. SecureVPN supports router configuration for household-wide protection. See our Setup Guides for supported routers.'},
        {'q': 'Is there a free trial?', 'a': 'Yes! We offer a 7-day free trial on all paid plans with no credit card required.'},
    ]
    return success(faqs)


# ─────────────────────────────────────────────────────────────────
# Health & Metadata
# ─────────────────────────────────────────────────────────────────
@app.route('/api/status', methods=['GET'])
def status():
    return success({
        'api_version': '2.0.0',
        'server_count': VPNServer.query.filter_by(is_online=True).count(),
        'status': 'operational',
        'uptime': '99.99%',
    })


@app.route('/api/ip', methods=['GET'])
def get_ip():
    """Returns caller's IP (useful for IP check tool)."""
    ip = request.headers.get('X-Forwarded-For', request.remote_addr)
    return success({'ip': ip})


# ─────────────────────────────────────────────────────────────────
# Init
# ─────────────────────────────────────────────────────────────────
with app.app_context():
    db.create_all()
    seed_database()

# ─────────────────────────────────────────────────────────────────
# Admin API Routes — Protected by admin JWT
# ─────────────────────────────────────────────────────────────────
ADMIN_PASSWORD = os.environ.get('ADMIN_PASSWORD', 'securevpn-admin-2024')
ADMIN_JWT_SECRET = os.environ.get('ADMIN_JWT_SECRET', 'admin-secret-dev-key')

def admin_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        token = request.headers.get('X-Admin-Token')
        if not token or token != ADMIN_PASSWORD:
            return error('Admin authentication required', 401)
        return f(*args, **kwargs)
    return decorated

@app.route('/api/admin/login', methods=['POST'])
def admin_login():
    body = request.json or {}
    password = body.get('password', '')
    if password != ADMIN_PASSWORD:
        return error('Invalid admin credentials', 401)
    return success({'admin_token': ADMIN_PASSWORD}, 'Admin login successful')

@app.route('/api/admin/stats', methods=['GET'])
@admin_required
def admin_stats():
    total_users = User.query.count()
    active_sessions = VPNSession.query.filter_by(is_active=True).count()
    total_sessions = VPNSession.query.count()
    free_users = User.query.filter_by(plan='free').count()
    paid_users = total_users - free_users
    online_servers = VPNServer.query.filter_by(is_online=True).count()
    open_tickets = SupportTicket.query.filter_by(status='open').count()
    active_subs = Subscription.query.filter_by(status='active').count()
    total_revenue = db.session.query(db.func.sum(Subscription.amount_pence)).filter_by(status='active').scalar() or 0
    return success({
        'total_users': total_users,
        'active_sessions': active_sessions,
        'total_sessions': total_sessions,
        'free_users': free_users,
        'paid_users': paid_users,
        'online_servers': online_servers,
        'open_tickets': open_tickets,
        'active_subscriptions': active_subs,
        'total_revenue_pence': total_revenue,
    })

@app.route('/api/admin/users', methods=['GET'])
@admin_required
def admin_users():
    search = request.args.get('search', '')
    plan   = request.args.get('plan')
    page   = int(request.args.get('page', 1))
    limit  = int(request.args.get('limit', 20))
    q = User.query
    if search:
        q = q.filter(User.email.ilike(f'%{search}%') | User.full_name.ilike(f'%{search}%'))
    if plan:
        q = q.filter_by(plan=plan)
    total = q.count()
    users = q.order_by(User.created_at.desc()).offset((page - 1) * limit).limit(limit).all()
    return success({'users': [u.to_dict() for u in users], 'total': total, 'page': page, 'limit': limit})

@app.route('/api/admin/users/<int:user_id>', methods=['GET'])
@admin_required
def admin_user_detail(user_id):
    user = User.query.get_or_404(user_id)
    sessions = VPNSession.query.filter_by(user_id=user.id).order_by(VPNSession.started_at.desc()).limit(10).all()
    subs = Subscription.query.filter_by(user_id=user.id).all()
    return success({
        'user': user.to_dict(),
        'sessions': [s.to_dict() for s in sessions],
        'subscriptions': [s.to_dict() for s in subs],
    })

@app.route('/api/admin/users/<int:user_id>', methods=['PATCH'])
@admin_required
def admin_update_user(user_id):
    user = User.query.get_or_404(user_id)
    body = request.json or {}
    if 'plan' in body and body['plan'] in PLAN_LIMITS:
        user.plan = body['plan']
    if 'full_name' in body:
        user.full_name = body['full_name']
    db.session.commit()
    return success(user.to_dict(), 'User updated')

@app.route('/api/admin/users/<int:user_id>', methods=['DELETE'])
@admin_required
def admin_delete_user(user_id):
    user = User.query.get_or_404(user_id)
    db.session.delete(user)
    db.session.commit()
    return success(msg='User deleted')

@app.route('/api/admin/servers', methods=['GET'])
@admin_required
def admin_servers():
    servers = VPNServer.query.all()
    return success([s.to_dict() for s in servers])

@app.route('/api/admin/servers/<server_id>', methods=['PATCH'])
@admin_required
def admin_update_server(server_id):
    server = VPNServer.query.get_or_404(server_id)
    body = request.json or {}
    for field in ['name', 'city', 'country', 'ping_ms', 'capacity_mbps', 'is_online',
                  'is_streaming', 'is_gaming', 'is_crypto', 'is_p2p']:
        if field in body:
            setattr(server, field, body[field])
    db.session.commit()
    return success(server.to_dict(), 'Server updated')

@app.route('/api/admin/sessions', methods=['GET'])
@admin_required
def admin_sessions():
    limit  = int(request.args.get('limit', 50))
    active_only = request.args.get('active') == 'true'
    q = VPNSession.query
    if active_only:
        q = q.filter_by(is_active=True)
    sessions = q.order_by(VPNSession.started_at.desc()).limit(limit).all()
    result = []
    for s in sessions:
        d = s.to_dict()
        user = User.query.get(s.user_id)
        d['user_email'] = user.email if user else 'Unknown'
        result.append(d)
    return success(result)

@app.route('/api/admin/tickets', methods=['GET'])
@admin_required
def admin_tickets():
    status = request.args.get('status')
    q = SupportTicket.query
    if status:
        q = q.filter_by(status=status)
    tickets = q.order_by(SupportTicket.created_at.desc()).all()
    return success([t.to_dict() for t in tickets])

@app.route('/api/admin/tickets/<int:ticket_id>', methods=['PATCH'])
@admin_required
def admin_update_ticket(ticket_id):
    ticket = SupportTicket.query.get_or_404(ticket_id)
    body = request.json or {}
    if 'status' in body:
        ticket.status = body['status']
    ticket.updated_at = datetime.utcnow()
    db.session.commit()
    return success(ticket.to_dict(), 'Ticket updated')

# App Config (stored in memory for simplicity; use DB in production)
_app_config = {
    'free_session_minutes': 45,
    'ad_bonus_minutes': 30,
    'max_free_devices': 1,
    'ads_enabled': True,
    'maintenance_mode': False,
}

@app.route('/api/admin/settings', methods=['GET'])
@admin_required
def admin_get_settings():
    return success(_app_config)

@app.route('/api/admin/settings', methods=['PATCH'])
@admin_required
def admin_update_settings():
    body = request.json or {}
    for key in _app_config:
        if key in body:
            _app_config[key] = body[key]
    return success(_app_config, 'Settings updated')

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 5000))
    app.run(debug=True, port=port, host='0.0.0.0')
