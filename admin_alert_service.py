"""
Admin Alert Service — VPN Backend (port 5000)
=============================================
Fires admin alerts from the VPN backend into the shared admin_alerts table.
Both the admin panel (port 5001) and VPN backend (port 5000) share the same
PostgreSQL DB, so we can write alert rows here and the admin panel reads them.

EVENTS FIRED FROM VPN BACKEND:
  - new_signup      → POST /api/auth/register
  - failed_payment  → Stripe webhook: invoice.payment_failed
  - refund_request  → Stripe webhook: customer.subscription.deleted (churned)
"""
import logging
import json
import os
from datetime import datetime

from sqlalchemy.orm import Session

logger = logging.getLogger(__name__)


def fire_admin_alert(
    event_type: str,
    title: str,
    message: str,
    db: Session,
    meta: dict = None,
) -> bool:
    """
    Fire an admin alert from within the VPN backend.

    Uses the same shared DB as the admin panel.
    Checks the admin_notification_configs table for the toggle state,
    then inserts a row into admin_alerts if enabled.

    Returns True if the alert was fired, False if skipped/disabled.
    """
    try:
        # Check the toggle using raw ORM on the shared DB
        # We use raw SQL to avoid importing admin-panel-specific models
        from sqlalchemy import text

        toggle_row = db.execute(
            text("SELECT is_enabled FROM admin_notification_configs WHERE event_type = :et LIMIT 1"),
            {"et": event_type}
        ).fetchone()

        if toggle_row is None:
            logger.debug(f"[AdminAlert] No config for '{event_type}' — skipping")
            return False

        is_enabled = toggle_row[0]
        if not is_enabled:
            logger.debug(f"[AdminAlert] Alert '{event_type}' is disabled — skipping")
            return False

        # Insert alert row
        meta_str = json.dumps(meta) if meta else None
        now      = datetime.utcnow()
        alert_id = str(__import__("uuid").uuid4())

        db.execute(
            text("""
                INSERT INTO admin_alerts (id, event_type, title, message, meta, is_read, created_at)
                VALUES (:id, :event_type, :title, :message, :meta, false, :created_at)
            """),
            {
                "id":         alert_id,
                "event_type": event_type,
                "title":      title,
                "message":    message,
                "meta":       meta_str,
                "created_at": now,
            }
        )
        db.commit()

        logger.info(f"[AdminAlert] ✅ Fired: [{event_type}] {title}")
        return True

    except Exception as e:
        logger.error(f"[AdminAlert] ❌ Failed to fire '{event_type}': {e}")
        try:
            db.rollback()
        except Exception:
            pass
        return False
