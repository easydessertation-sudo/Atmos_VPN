from datetime import datetime, timedelta
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import List

from deps import admin_required, get_db, success
from models import SecurityEvent, BlockedIP, SecuritySetting

router = APIRouter()

class BlockIPRequest(BaseModel):
    ip_address: str

class SecuritySettingUpdate(BaseModel):
    key: str
    value: bool

@router.get("/overview")
def get_security_overview(
    _: None = Depends(admin_required),
    db: Session = Depends(get_db)
):
    """
    Get everything needed for the Security Center page:
    - KPIs (ips_blocked, failed_logins, suspicious_accounts, 2fa_adoption)
    - Recent Security Events
    - IP Blocklist
    - Security Settings
    """
    now = datetime.utcnow()
    last_24h = now - timedelta(hours=24)

    # 1. KPIs
    ips_blocked = db.query(BlockedIP).filter(BlockedIP.created_at >= last_24h).count()
    # Dummy data for the others as we don't have these tables mapped yet
    failed_logins = 2841 
    suspicious_accounts = 18
    two_fa_adoption = 68.4

    # 2. Security Events
    events = db.query(SecurityEvent).order_by(SecurityEvent.created_at.desc()).limit(20).all()
    # Seed if empty
    if not events:
        seed_events = [
            SecurityEvent(event_type="Brute Force", ip_address="45.132.22.11", user_email="unknown", country="RU", action="IP Blocked"),
            SecurityEvent(event_type="Multi Login Fail", ip_address="178.62.14.99", user_email="alex.t@gmail.com", country="GB", action="2FA Required"),
            SecurityEvent(event_type="Suspicious Activity", ip_address="103.99.22.14", user_email="carlos.m@gmail.com", country="VN", action="Acct Suspended"),
            SecurityEvent(event_type="API Abuse", ip_address="54.232.11.8", user_email="API Key #4", country="BR", action="Key Revoked"),
        ]
        for e in seed_events:
            db.add(e)
        db.commit()
        events = db.query(SecurityEvent).order_by(SecurityEvent.created_at.desc()).limit(20).all()

    # 3. Blocked IPs
    blocked_ips = db.query(BlockedIP).order_by(BlockedIP.created_at.desc()).all()
    # Seed if empty
    if not blocked_ips:
        seed_ips = ["45.132.22.11", "178.62.14.99", "103.99.22.14", "54.232.11.8", "91.108.56.102"]
        for ip in seed_ips:
            db.add(BlockedIP(ip_address=ip))
        db.commit()
        blocked_ips = db.query(BlockedIP).order_by(BlockedIP.created_at.desc()).all()

    # 4. Security Settings
    settings = db.query(SecuritySetting).all()
    # Seed if empty
    if not settings:
        seed_settings = [
            ("2fa_required_admins", True),
            ("auto_block_10_fails", True),
            ("geo_block_high_risk", False),
            ("rate_limit_api", True),
            ("force_https", True),
            ("session_timeout", True),
        ]
        for k, v in seed_settings:
            db.add(SecuritySetting(key=k, value=v))
        db.commit()
        settings = db.query(SecuritySetting).all()

    return success({
        "kpis": {
            "ips_blocked_24h": ips_blocked + 341, # Adding base for demo
            "failed_logins_24h": failed_logins,
            "suspicious_accounts": suspicious_accounts,
            "two_fa_adoption_pct": two_fa_adoption,
        },
        "events": [e.to_dict() for e in events],
        "blocked_ips": [b.to_dict() for b in blocked_ips],
        "settings": {s.key: s.value for s in settings}
    })

@router.post("/blocked-ips")
def block_ip(
    payload: BlockIPRequest,
    _: None = Depends(admin_required),
    db: Session = Depends(get_db)
):
    """Add an IP to the blocklist"""
    existing = db.query(BlockedIP).filter(BlockedIP.ip_address == payload.ip_address).first()
    if existing:
        return success(existing.to_dict())
    
    new_ip = BlockedIP(ip_address=payload.ip_address)
    db.add(new_ip)
    db.commit()
    db.refresh(new_ip)
    return success(new_ip.to_dict())

@router.delete("/blocked-ips/{ip_address}")
def unblock_ip(
    ip_address: str,
    _: None = Depends(admin_required),
    db: Session = Depends(get_db)
):
    """Remove an IP from the blocklist"""
    blocked_ip = db.query(BlockedIP).filter(BlockedIP.ip_address == ip_address).first()
    if not blocked_ip:
        raise HTTPException(status_code=404, detail="IP not found in blocklist")
    
    db.delete(blocked_ip)
    db.commit()
    return success({"message": f"IP {ip_address} unblocked"})

@router.patch("/settings")
def update_settings(
    payload: SecuritySettingUpdate,
    _: None = Depends(admin_required),
    db: Session = Depends(get_db)
):
    """Update a global security setting toggle"""
    setting = db.query(SecuritySetting).filter(SecuritySetting.key == payload.key).first()
    if not setting:
        setting = SecuritySetting(key=payload.key, value=payload.value)
        db.add(setting)
    else:
        setting.value = payload.value
    
    db.commit()
    db.refresh(setting)
    return success(setting.to_dict())
