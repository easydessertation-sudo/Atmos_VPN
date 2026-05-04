"""
Settings Router — Admin app-wide configuration
GET   /api/admin/settings        → get current settings
PATCH /api/admin/settings        → update settings
POST  /api/admin/settings/reset  → reset to defaults
"""
from typing import Optional

from fastapi import APIRouter, Depends
from pydantic import BaseModel

from deps import admin_required, success

router = APIRouter()

# ─────────────────────────────────────────────────────────────────
# In-memory app config (shared across requests for this process).
# In production, persist these to a DB table or Redis so they
# survive restarts and work across multiple server instances.
# ─────────────────────────────────────────────────────────────────
_DEFAULT_CONFIG = {
    # General Settings (UI Tab)
    "site_name":             "AtmosVPN",
    "support_email":         "support@atmosvpn.com",
    "sales_email":           "sales@atmosvpn.com",
    "twitter_handle":        "@AtmosVPN",
    "canonical_url":         "https://atmosvpn.com/",
    "app_version":           "4.2.1",
    
    # General Toggles
    "maintenance_mode":      False,
    "free_plan_enabled":     True,
    "new_signups":           True,
    "show_pricing":          True,

    # Free plan session limits (Legacy)
    "free_session_minutes":  45,
    "ad_bonus_minutes":      30,
    "max_free_devices":      1,

    # Feature flags (Legacy)
    "ads_enabled":           True,
    "stripe_live_mode":      False,

    # Plan pricing overrides (Legacy)
    "price_starter_monthly": 3.99,
    "price_starter_annual":  33.48,
    "price_pro_monthly":     7.99,
    "price_pro_annual":      57.48,
    "price_premium_monthly": 12.99,
    "price_premium_annual":  93.48,

    # Support (Legacy)
    "max_support_tickets_per_day": 3,
}

_app_config: dict = dict(_DEFAULT_CONFIG)


class AdminUpdateSettingsRequest(BaseModel):
    # General Settings (UI Tab)
    site_name:                     Optional[str]   = None
    support_email:                 Optional[str]   = None
    sales_email:                   Optional[str]   = None
    twitter_handle:                Optional[str]   = None
    canonical_url:                 Optional[str]   = None
    app_version:                   Optional[str]   = None
    maintenance_mode:              Optional[bool]  = None
    free_plan_enabled:             Optional[bool]  = None
    new_signups:                   Optional[bool]  = None
    show_pricing:                  Optional[bool]  = None

    # Legacy fields
    free_session_minutes:          Optional[int]   = None
    ad_bonus_minutes:              Optional[int]   = None
    max_free_devices:              Optional[int]   = None
    ads_enabled:                   Optional[bool]  = None
    stripe_live_mode:              Optional[bool]  = None
    price_starter_monthly:         Optional[float] = None
    price_starter_annual:          Optional[float] = None
    price_pro_monthly:             Optional[float] = None
    price_pro_annual:              Optional[float] = None
    price_premium_monthly:         Optional[float] = None
    price_premium_annual:          Optional[float] = None
    max_support_tickets_per_day:   Optional[int]   = None


@router.get("/settings")
def admin_get_settings(_: None = Depends(admin_required)):
    """Return the current app-wide settings."""
    return success(_app_config)


@router.patch("/settings")
def admin_update_settings(
    body: AdminUpdateSettingsRequest,
    _:    None = Depends(admin_required),
):
    """
    Update one or more app-wide settings.
    Only fields that are provided (non-null) in the body are updated.
    """
    updates = body.model_dump(exclude_none=True)
    if not updates:
        return success(_app_config, "No changes (no fields provided)")
    _app_config.update(updates)
    return success(_app_config, f"Settings updated: {list(updates.keys())}")


@router.post("/settings/reset")
def admin_reset_settings(_: None = Depends(admin_required)):
    """Reset all settings to factory defaults."""
    global _app_config
    _app_config = dict(_DEFAULT_CONFIG)
    return success(_app_config, "Settings reset to defaults")
