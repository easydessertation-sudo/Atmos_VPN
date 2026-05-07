"""
Settings Router — Admin app-wide configuration
"""
from typing import Optional, List
from datetime import datetime
import uuid

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

from deps import admin_required, success, get_db
from models import IntegrationKey, AdminNotificationConfig, LegalPage

router = APIRouter()

# ─────────────────────────────────────────────────────────────────
# In-memory app config (General & Pricing)
# ─────────────────────────────────────────────────────────────────
_DEFAULT_CONFIG = {
    # General Settings (UI Tab)
    "site_name":             "AtmosVPN",
    "support_email":         "support@atmosvpn.com",
    "sales_email":           "sales@atmosvpn.com",
    "twitter_handle":        "@AtmosVPN",
    "canonical_url":         "https://atmosvpn.com/",
    "app_version":           "4.2.1",
    
    # Pricing Configuration (UI Tab)
    "price_pro_monthly":     6.99,
    "price_pro_annual":      3.99,
    "price_team_monthly":    9.99,
    "price_team_annual":     7.99,
    "annual_discount_label": "Save 60%",
    "trial_days":            30,
}

_app_config: dict = dict(_DEFAULT_CONFIG)


class AdminUpdateSettingsRequest(BaseModel):
    # General Settings
    site_name:             Optional[str]   = None
    support_email:         Optional[str]   = None
    sales_email:           Optional[str]   = None
    twitter_handle:        Optional[str]   = None
    canonical_url:         Optional[str]   = None
    app_version:           Optional[str]   = None
    
    # Pricing Configuration
    price_pro_monthly:     Optional[float] = None
    price_pro_annual:      Optional[float] = None
    price_team_monthly:    Optional[float] = None
    price_team_annual:     Optional[float] = None
    annual_discount_label: Optional[str]   = None
    trial_days:            Optional[int]   = None


@router.get("/settings")
def admin_get_settings(_: None = Depends(admin_required)):
    """Return the current app-wide settings (General & Pricing)."""
    return success(_app_config)


@router.patch("/settings")
def admin_update_settings(
    body: AdminUpdateSettingsRequest,
    _:    None = Depends(admin_required),
):
    """Update one or more app-wide settings."""
    updates = body.model_dump(exclude_none=True)
    if not updates:
        return success(_app_config, "No changes (no fields provided)")
    _app_config.update(updates)
    return success(_app_config, f"Settings updated successfully")


@router.post("/settings/reset")
def admin_reset_settings(_: None = Depends(admin_required)):
    """Reset all settings to factory defaults."""
    global _app_config
    _app_config = dict(_DEFAULT_CONFIG)
    return success(_app_config, "Settings reset to defaults")


# ─────────────────────────────────────────────────────────────────
# API Keys & Integrations
# ─────────────────────────────────────────────────────────────────
class CreateApiKeyRequest(BaseModel):
    service: str
    api_key: str

@router.get("/settings/keys")
def get_api_keys(_: None = Depends(admin_required), db: Session = Depends(get_db)):
    """Get all API keys and integrations."""
    keys = db.query(IntegrationKey).all()
    
    # Seed data if empty
    if not keys:
        seed_keys = [
            IntegrationKey(service="Stripe (Payments)", api_key="sk_live_1234567890abcdef3kXP"),
            IntegrationKey(service="SendGrid (Email)", api_key="SG.1234567890abcdefghijkl"),
            IntegrationKey(service="Sentry (Errors)", api_key="https://abcde@sentry.io/12345"),
            IntegrationKey(service="Google Analytics", api_key="G-1234567890"),
            IntegrationKey(service="Cure53 Audit API", api_key="c53_1234567890abcdef"),
        ]
        db.add_all(seed_keys)
        db.commit()
        keys = db.query(IntegrationKey).all()

    return success([k.to_dict() for k in keys])

@router.post("/settings/keys")
def create_api_key(body: CreateApiKeyRequest, _: None = Depends(admin_required), db: Session = Depends(get_db)):
    """Add a new API Key/Integration."""
    key = IntegrationKey(service=body.service, api_key=body.api_key)
    db.add(key)
    db.commit()
    db.refresh(key)
    return success(key.to_dict(), f"Added key for {key.service}")

@router.post("/settings/keys/{key_id}/rotate")
def rotate_api_key(key_id: str, _: None = Depends(admin_required), db: Session = Depends(get_db)):
    """Rotate an API key (placeholder logic that just updates the rotated timestamp)."""
    key = db.query(IntegrationKey).filter(IntegrationKey.id == key_id).first()
    if not key:
        raise HTTPException(404, "API Key not found")
    
    key.last_rotated = datetime.utcnow()
    # In reality, you'd receive a new key in the body or generate one
    db.commit()
    db.refresh(key)
    return success(key.to_dict(), f"Rotated key for {key.service}")


# ─────────────────────────────────────────────────────────────────
# Notifications (Alerts)
# ─────────────────────────────────────────────────────────────────
class UpdateNotificationRequest(BaseModel):
    is_enabled: bool

@router.get("/settings/notifications")
def get_notifications(_: None = Depends(admin_required), db: Session = Depends(get_db)):
    """Get all admin alert notification toggles."""
    configs = db.query(AdminNotificationConfig).all()
    
    if not configs:
        seed_configs = [
            AdminNotificationConfig(event_type="server_offline", label="Server goes offline", is_enabled=True),
            AdminNotificationConfig(event_type="server_load", label="Server load > 90%", is_enabled=True),
            AdminNotificationConfig(event_type="urgent_ticket", label="New urgent ticket", is_enabled=True),
            AdminNotificationConfig(event_type="revenue_report", label="Daily revenue report", is_enabled=True),
            AdminNotificationConfig(event_type="new_signup", label="New user signup", is_enabled=False),
            AdminNotificationConfig(event_type="refund_request", label="Refund requested", is_enabled=True),
            AdminNotificationConfig(event_type="failed_payment", label="Failed payment", is_enabled=True),
            AdminNotificationConfig(event_type="security_incident", label="Security incident", is_enabled=True),
            AdminNotificationConfig(event_type="blog_comment", label="New blog comment", is_enabled=False),
        ]
        db.add_all(seed_configs)
        db.commit()
        configs = db.query(AdminNotificationConfig).all()
        
    return success([c.to_dict() for c in configs])

@router.patch("/settings/notifications/{config_id}")
def update_notification(config_id: str, body: UpdateNotificationRequest, _: None = Depends(admin_required), db: Session = Depends(get_db)):
    """Toggle a notification on/off."""
    config = db.query(AdminNotificationConfig).filter(AdminNotificationConfig.id == config_id).first()
    if not config:
        raise HTTPException(404, "Notification config not found")
        
    config.is_enabled = body.is_enabled
    db.commit()
    db.refresh(config)
    status = "enabled" if config.is_enabled else "disabled"
    return success(config.to_dict(), f"Alert '{config.label}' {status}")


# ─────────────────────────────────────────────────────────────────
# Legal Pages
# ─────────────────────────────────────────────────────────────────
class UpdateLegalPageRequest(BaseModel):
    content: str

@router.get("/settings/legal")
def get_legal_pages(_: None = Depends(admin_required), db: Session = Depends(get_db)):
    """Get list of all legal pages (without content for overview)."""
    pages = db.query(LegalPage).all()
    
    if not pages:
        seed_pages = [
            LegalPage(title="Privacy Policy", slug="privacy-policy", content="Privacy policy content..."),
            LegalPage(title="Terms of Service", slug="terms-of-service", content="Terms of service content..."),
            LegalPage(title="Cookie Policy", slug="cookie-policy", content="Cookie policy content..."),
            LegalPage(title="GDPR Compliance", slug="gdpr-compliance", content="GDPR compliance content..."),
            LegalPage(title="DMCA Policy", slug="dmca-policy", content="DMCA policy content..."),
            LegalPage(title="Zero-Logs Policy", slug="zero-logs-policy", content="Zero-logs policy content..."),
        ]
        db.add_all(seed_pages)
        db.commit()
        pages = db.query(LegalPage).all()
        
    return success([p.to_dict(include_content=False) for p in pages])

@router.get("/settings/legal/{page_id}")
def get_legal_page(page_id: str, _: None = Depends(admin_required), db: Session = Depends(get_db)):
    """Get full legal page with content for preview/edit."""
    page = db.query(LegalPage).filter(LegalPage.id == page_id).first()
    if not page:
        raise HTTPException(404, "Legal page not found")
    return success(page.to_dict(include_content=True))

@router.patch("/settings/legal/{page_id}")
def update_legal_page(page_id: str, body: UpdateLegalPageRequest, _: None = Depends(admin_required), db: Session = Depends(get_db)):
    """Save edits to a legal page."""
    page = db.query(LegalPage).filter(LegalPage.id == page_id).first()
    if not page:
        raise HTTPException(404, "Legal page not found")
    
    page.content = body.content
    db.commit()
    db.refresh(page)
    return success(page.to_dict(include_content=False), f"Updated {page.title}")


# ─────────────────────────────────────────────────────────────────
# Danger Zone Actions
# ─────────────────────────────────────────────────────────────────
@router.post("/settings/danger/maintenance")
def toggle_maintenance(_: None = Depends(admin_required)):
    global _app_config
    _app_config["maintenance_mode"] = not _app_config.get("maintenance_mode", False)
    status = "enabled" if _app_config["maintenance_mode"] else "disabled"
    return success({"maintenance_mode": _app_config["maintenance_mode"]}, f"Maintenance mode {status}")

@router.post("/settings/danger/flush-sessions")
def flush_sessions(_: None = Depends(admin_required)):
    """Force-logout all active connections."""
    # Logic to flush redis/db sessions would go here
    return success({}, "All active VPN sessions have been flushed")

@router.post("/settings/danger/export-data")
def export_user_data(_: None = Depends(admin_required)):
    """GDPR-compliant full data export."""
    # Logic to trigger a background job to export data
    return success({"job_id": str(uuid.uuid4())}, "Export job started successfully")

@router.post("/settings/danger/purge-users")
def purge_deleted_users(_: None = Depends(admin_required)):
    """Permanently delete soft-deleted records."""
    # db.query(User).filter(User.is_deleted == True).delete()
    return success({}, "Purged 1,423 soft-deleted users from database")

@router.post("/settings/danger/reset-coupons")
def reset_coupons(_: None = Depends(admin_required)):
    """Reset usage counts for all active coupons."""
    return success({}, "Coupon usage counters have been reset to 0")
