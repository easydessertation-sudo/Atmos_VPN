"""
Alert Service — Admin Panel
===========================
Core utility that fires admin alerts when system events occur.

HOW IT WORKS:
  1. Any code (router, webhook, background task) calls fire_alert(event_type, ...)
  2. This service checks AdminNotificationConfig for that event_type
  3. If the admin has toggled it ON → inserts a row into admin_alerts table
  4. Admin panel bell icon reads from admin_alerts (GET /api/admin/alerts)

SUPPORTED EVENT TYPES (match AdminNotificationConfig.event_type exactly):
  - server_offline      → a VPN server was marked offline
  - server_load         → a server's load_pct crossed 90%
  - urgent_ticket       → a support ticket was created/updated with priority=urgent
  - revenue_report      → daily revenue digest (triggered by scheduler)
  - new_signup          → a new user registered on the VPN app
  - refund_request      → a refund was issued via Stripe
  - failed_payment      → a Stripe invoice.payment_failed event fired
  - security_incident   → a security incident was created in the admin panel
  - blog_comment        → a new blog comment was received (if enabled)
"""
import logging
from datetime import datetime
from sqlalchemy.orm import Session

from models import AdminNotificationConfig, AdminAlert

logger = logging.getLogger(__name__)


def fire_alert(
    event_type: str,
    title: str,
    message: str,
    db: Session,
    meta: dict = None,
) -> bool:
    """
    Fire an admin alert if the toggle for this event_type is enabled.

    Args:
        event_type: One of the event type strings (e.g. 'new_signup')
        title:      Short title shown in the bell dropdown (e.g. 'New User Registered')
        message:    Detail line (e.g. 'john@example.com just signed up.')
        db:         Active SQLAlchemy session
        meta:       Optional dict of extra info (stored as JSON string)

    Returns:
        True  → alert was fired (toggle was ON)
        False → alert was skipped (toggle was OFF or config not found)
    """
    try:
        config = (
            db.query(AdminNotificationConfig)
            .filter_by(event_type=event_type)
            .first()
        )

        if not config:
            # Config doesn't exist yet (maybe not seeded). Silently skip.
            logger.debug(f"[AlertService] No config for event_type='{event_type}' — skipping")
            return False

        if not config.is_enabled:
            logger.debug(f"[AlertService] Alert '{event_type}' is disabled — skipping")
            return False

        # Insert the alert record
        import json
        alert = AdminAlert(
            event_type = event_type,
            title      = title,
            message    = message,
            meta       = json.dumps(meta) if meta else None,
            is_read    = False,
            created_at = datetime.utcnow(),
        )
        db.add(alert)
        db.commit()

        logger.info(f"[AlertService] ✅ Alert fired: [{event_type}] {title}")
        return True

    except Exception as e:
        logger.error(f"[AlertService] ❌ Failed to fire alert '{event_type}': {e}")
        try:
            db.rollback()
        except Exception:
            pass
        return False


def get_unread_count(db: Session) -> int:
    """Return the count of unread alerts — for the bell badge number."""
    try:
        return db.query(AdminAlert).filter_by(is_read=False).count()
    except Exception:
        return 0
