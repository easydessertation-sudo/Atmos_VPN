"""
AtmosVPN — Stripe Integration Module

Handles all Stripe API interactions:
  1. Checkout Session  — creates a hosted payment page URL
  2. Billing Portal    — creates a self-service management page URL
  3. Webhook handler   — processes Stripe events (payment/cancel etc.)

Architecture:
  User clicks "Upgrade"
    → POST /api/billing/checkout → creates Stripe Checkout Session
    → Returns checkout_url → App opens it in browser
    → User pays on Stripe's page (we never see card numbers)
    → Stripe fires POST /api/webhooks/stripe (the webhook)
    → We verify signature, update DB, activate VPN access

Stripe Price IDs:
  In Stripe Dashboard → Products → each plan needs:
    - A monthly price  → get the Price ID (price_xxx)
    - An annual price  → get the Price ID (price_yyy)
  Set these in .env as STRIPE_PRICE_*

Test mode:
  All sk_test_* keys work in Stripe test mode.
  Use card: 4242 4242 4242 4242 | Any future date | Any CVC
  Real charges only happen with sk_live_* keys.
"""
import os
import logging
from datetime import datetime, timedelta
from typing import Optional

import stripe
from dotenv import load_dotenv

load_dotenv()

logger = logging.getLogger(__name__)

# Import the admin alert service (fires alerts to admin panel bell icon)
try:
    from admin_alert_service import fire_admin_alert as _fire_admin_alert
except ImportError:
    def _fire_admin_alert(*args, **kwargs): pass  # Graceful fallback

# ─────────────────────────────────────────────────────────────────
# Stripe Configuration
# ─────────────────────────────────────────────────────────────────
stripe.api_key = os.environ.get("STRIPE_SECRET_KEY", "")
STRIPE_WEBHOOK_SECRET = os.environ.get("STRIPE_WEBHOOK_SECRET", "")

# App URLs — where Stripe redirects after payment
# Replace with your real app URLs when deploying
APP_BASE_URL       = os.environ.get("APP_BASE_URL", "http://localhost:5000")
STRIPE_SUCCESS_URL = "atmosvpn://app/payment-success"
STRIPE_CANCEL_URL  = "atmosvpn://app/payment-cancel"
STRIPE_PORTAL_URL  = f"{APP_BASE_URL}/account"

# ─────────────────────────────────────────────────────────────────
# Stripe Price ID Map
#
# In Stripe Dashboard → Products → create these products:
#   "AtmosVPN Essential" → monthly price ($3.99) + annual price ($35.88)
#   "AtmosVPN Elite"     → monthly price ($6.99) + annual price ($59.88)
#   "AtmosVPN Ultimate"  → monthly price ($11.99) + annual price ($91.80)
#
# Each price gets a Price ID like: price_1ABC123def456GHI
# Paste these into .env as STRIPE_PRICE_ESSENTIAL_MONTHLY etc.
# ─────────────────────────────────────────────────────────────────
STRIPE_PRICE_IDS = {
    # New plan names (starter / pro / premium)
    "starter": {
        "monthly": os.environ.get("STRIPE_PRICE_STARTER_MONTHLY", ""),
        "annual":  os.environ.get("STRIPE_PRICE_STARTER_ANNUAL",  ""),
    },
    "pro": {
        "monthly": os.environ.get("STRIPE_PRICE_PRO_MONTHLY", ""),
        "annual":  os.environ.get("STRIPE_PRICE_PRO_ANNUAL",  ""),
    },
    "premium": {
        "monthly": os.environ.get("STRIPE_PRICE_PREMIUM_MONTHLY", ""),
        "annual":  os.environ.get("STRIPE_PRICE_PREMIUM_ANNUAL",  ""),
    },
}

# How many days each billing cycle extends the subscription
BILLING_CYCLE_DAYS = {
    "monthly": 30,
    "annual":  365,
}


# ─────────────────────────────────────────────────────────────────
# FUNCTION 1: Create Stripe Checkout Session
#
# Called by: POST /api/billing/checkout
#
# Returns a URL that the app opens in a browser/webview.
# The user enters their card on Stripe's page — you never see it.
#
# Stripe handles:
#   - Card validation
#   - 3D Secure authentication
#   - Currency conversion
#   - Fraud detection
#   - Receipts/invoices
# ─────────────────────────────────────────────────────────────────
def create_checkout_session(
    user_id: str,
    user_email: str,
    plan: str,
    billing_cycle: str,
    stripe_customer_id: Optional[str] = None,
) -> dict:
    """
    Create a Stripe Checkout Session for a plan upgrade.

    Args:
        user_id:            User UUID (stored in Stripe metadata for webhook)
        user_email:         User email (pre-fills the payment form)
        plan:               'essential' | 'elite' | 'ultimate'
        billing_cycle:      'monthly' | 'annual'
        stripe_customer_id: If user already has a Stripe customer, reuse it

    Returns:
        { "checkout_url": "https://checkout.stripe.com/...", "session_id": "cs_..." }
    """
    if not stripe.api_key:
        raise ValueError("STRIPE_SECRET_KEY not configured in .env")

    price_id = STRIPE_PRICE_IDS.get(plan, {}).get(billing_cycle, "")
    if not price_id:
        raise ValueError(
            f"Stripe Price ID not configured for {plan}/{billing_cycle}. "
            f"Set STRIPE_PRICE_{plan.upper()}_{billing_cycle.upper()} in .env"
        )

    # Build params
    params = {
        "payment_method_types": ["card"],
        "line_items": [{"price": price_id, "quantity": 1}],
        "mode": "subscription",            # recurring payment (not one-time)
        "success_url": STRIPE_SUCCESS_URL, # redirect after successful payment
        "cancel_url":  STRIPE_CANCEL_URL,  # redirect if user cancels

        # IMPORTANT: store user_id and plan in metadata
        # The webhook reads these to know which user paid for which plan
        "metadata": {
            "user_id":       user_id,
            "plan":          plan,
            "billing_cycle": billing_cycle,
        },
        "subscription_data": {
            "metadata": {
                "user_id":       user_id,
                "plan":          plan,
                "billing_cycle": billing_cycle,
            }
        },
    }

    # If user already has a Stripe customer record → attach to it
    # This allows Stripe to pre-fill their saved payment methods
    if stripe_customer_id:
        params["customer"] = stripe_customer_id
    else:
        params["customer_email"] = user_email

    session = stripe.checkout.Session.create(**params)

    logger.info(f"Created checkout session {session.id} for user {user_id} → {plan}/{billing_cycle}")
    return {
        "checkout_url": session.url,
        "session_id":   session.id,
    }


# ─────────────────────────────────────────────────────────────────
# FUNCTION 2: Create Stripe Billing Portal Session
#
# Called by: POST /api/billing/portal
#
# The Billing Portal is a pre-built Stripe UI where users can:
#   - Update their credit card
#   - Cancel their subscription
#   - Download past invoices
#   - Switch between monthly/annual plans
#
# You don't build this UI — Stripe hosts it.
# Requires: user must have a stripe_customer_id (i.e. has paid before)
# ─────────────────────────────────────────────────────────────────
def create_billing_portal_session(stripe_customer_id: str) -> dict:
    """
    Create a Stripe Billing Portal session for self-service management.

    Args:
        stripe_customer_id: The user's Stripe customer ID (cus_...)

    Returns:
        { "portal_url": "https://billing.stripe.com/..." }
    """
    if not stripe.api_key:
        raise ValueError("STRIPE_SECRET_KEY not configured in .env")

    if not stripe_customer_id:
        raise ValueError("User has no Stripe customer record. They need to purchase first.")

    session = stripe.billing_portal.Session.create(
        customer=stripe_customer_id,
        return_url=STRIPE_PORTAL_URL,   # where to go when they close the portal
    )

    logger.info(f"Created billing portal session for customer {stripe_customer_id}")
    return {"portal_url": session.url}

# ─────────────────────────────────────────────────────────────────
# FUNCTION 2.5: Get Upcoming Invoice
#
# Called by: GET /api/billing/status
# Returns the precise date and amount of the next subscription charge
# ─────────────────────────────────────────────────────────────────
def get_next_charge_details(stripe_customer_id: str) -> dict:
    if not stripe.api_key:
        return None
    if not stripe_customer_id:
        return None
        
    try:
        upcoming = stripe.Invoice.create_preview(customer=stripe_customer_id)
        # Convert Unix Timestamp to a readable ISO Datetime string
        from datetime import datetime
        readable_date = datetime.utcfromtimestamp(upcoming.next_payment_attempt).isoformat() + "Z"
        
        return {
            "next_payment_date": readable_date,
            "amount_due_usd": upcoming.amount_due / 100.0, # Convert cents to dollars
            "currency": upcoming.currency
        }
    except stripe.error.InvalidRequestError:
        # Happens if they don't have an active subscription
        return None
    except Exception as e:
        logger.error(f"Failed to fetch upcoming invoice: {e}")
        return None


# ─────────────────────────────────────────────────────────────────
# FUNCTION 3: Verify and Parse Stripe Webhook
#
# Called by: POST /api/webhooks/stripe
#
# CRITICAL SECURITY: Always verify the webhook signature before
# processing ANY event. Without this, anyone can send fake events.
#
# How signature verification works:
#   1. Stripe computes HMAC-SHA256 of (timestamp + payload) using the webhook secret
#   2. Stripe sends this as the 'Stripe-Signature' header
#   3. You compute the same HMAC and compare
#   4. If they match → genuinely from Stripe → safe to process
#   5. If they don't match → reject with 400 → log the attempt
# ─────────────────────────────────────────────────────────────────
def verify_and_parse_webhook(payload: bytes, signature_header: str) -> stripe.Event:
    """
    Verify Stripe webhook signature and parse the event.

    Args:
        payload:           Raw request body bytes (must be raw — not parsed JSON)
        signature_header:  Value of 'Stripe-Signature' request header

    Returns:
        Stripe Event object if signature is valid

    Raises:
        stripe.error.SignatureVerificationError if signature is invalid
        ValueError if webhook secret is not configured
    """
    if not STRIPE_WEBHOOK_SECRET:
        raise ValueError(
            "STRIPE_WEBHOOK_SECRET not configured in .env. "
            "Get it from: Stripe Dashboard → Webhooks → your endpoint → Signing secret"
        )

    # This single line does ALL the security verification
    # It raises SignatureVerificationError if tampered/invalid
    event = stripe.Webhook.construct_event(
        payload=payload,
        sig_header=signature_header,
        secret=STRIPE_WEBHOOK_SECRET,
    )

    logger.info(f"Webhook verified: {event['type']} | ID: {event['id']}")
    return event


# ─────────────────────────────────────────────────────────────────
# FUNCTION 4: Handle Specific Webhook Events
#
# This function takes a verified event and does the DB updates.
# Keeps the webhook endpoint clean and this logic testable.
#
# Events we handle:
#
#   checkout.session.completed
#     → User completed payment on Stripe's page
#     → Activate subscription, save stripe_customer_id
#
#   invoice.payment_succeeded
#     → Monthly/annual renewal was charged successfully
#     → Extend plan_expires_at
#
#   invoice.payment_failed
#     → Payment method declined (card expired etc.)
#     → Log warning, send notification (email step 5)
#     → Stripe auto-retries for 7 days
#
#   customer.subscription.deleted
#     → User cancelled OR all payment retries failed
#     → Downgrade to free, revoke WireGuard configs
# ─────────────────────────────────────────────────────────────────
def handle_webhook_event(event: stripe.Event, db) -> dict:
    """
    Process a verified Stripe event and update the database accordingly.

    Args:
        event: Verified Stripe Event object
        db:    SQLAlchemy database session

    Returns:
        { "handled": True/False, "action": "what was done" }
    """
    from models import User, Subscription
    from wireguard import revoke_all_user_configs

    event_type = event["type"]
    data       = event["data"]["object"]

    # ── Event: Payment completed ───────────────────────────────────
    if event_type == "checkout.session.completed":
        return _handle_checkout_completed(data, db)

    # ── Event: Subscription renewed successfully ───────────────────
    elif event_type == "invoice.payment_succeeded":
        return _handle_payment_succeeded(data, db)

    # ── Event: Payment failed ──────────────────────────────────────
    elif event_type == "invoice.payment_failed":
        return _handle_payment_failed(data, db)

    # ── Event: Subscription cancelled or expired ───────────────────
    elif event_type == "customer.subscription.deleted":
        return _handle_subscription_deleted(data, db, revoke_all_user_configs)

    # ── Event: Plan upgraded/downgraded via billing portal ─────────
    elif event_type == "customer.subscription.updated":
        return _handle_subscription_updated(data, db)

    else:
        logger.info(f"Unhandled webhook event type: {event_type}")
        return {"handled": False, "action": "ignored"}


# ─────────────────────────────────────────────────────────────────
# Internal Event Handlers
# ─────────────────────────────────────────────────────────────────

def safe_get(obj, key, default=None):
    if hasattr(obj, "get") and callable(getattr(obj, "get")):
        return obj.get(key, default)
    return getattr(obj, key, default)

def _handle_checkout_completed(session_data, db) -> dict:
    """
    checkout.session.completed → User just paid for the first time.
    1. Get user_id and plan from metadata
    2. Save stripe_customer_id to users table
    3. Activate plan with expiry date
    4. Create subscription record
    """
    from models import User, Subscription

    metadata      = safe_get(session_data, "metadata") or {}
    user_id       = safe_get(metadata, "user_id")
    plan          = safe_get(metadata, "plan", "essential")
    billing_cycle = safe_get(metadata, "billing_cycle", "monthly")
    customer_id   = safe_get(session_data, "customer")
    subscription_id = safe_get(session_data, "subscription")

    if not user_id:
        logger.error("checkout.session.completed: no user_id in metadata!")
        return {"handled": False, "action": "missing user_id in metadata"}

    user = db.get(User, user_id)
    if not user:
        logger.error(f"checkout.session.completed: user {user_id} not found!")
        return {"handled": False, "action": "user not found"}

    days = BILLING_CYCLE_DAYS.get(billing_cycle, 30)

    # Read exact amount charged from Stripe (amount_total is in cents)
    amount_total = safe_get(session_data, "amount_total", 0)
    amount_usd = amount_total / 100.0

    # Update user record
    user.plan                  = plan
    user.plan_expires_at       = datetime.utcnow() + timedelta(days=days)
    user.subscription_status   = "active"
    user.stripe_customer_id    = customer_id
    user.bandwidth_used_bytes  = 0   # reset bandwidth on new plan

    # Create subscription record
    sub = Subscription(
        user_id=user_id,
        plan=plan,
        billing_cycle=billing_cycle,
        amount_usd=amount_usd,
        currency="USD",
        stripe_subscription_id=subscription_id,
        status="active",
        started_at=datetime.utcnow(),
        expires_at=datetime.utcnow() + timedelta(days=days),
    )
    db.add(sub)
    db.commit()

    logger.info(f"Activated {plan} for user {user_id} via checkout (expires in {days} days)")
    return {"handled": True, "action": f"activated_{plan}_plan", "user_id": user_id}


def _handle_payment_succeeded(invoice_data: dict, db) -> dict:
    """
    invoice.payment_succeeded → Monthly/annual renewal was charged.
    Extends the plan expiry date.
    """
    from models import User, Subscription

    customer_id     = safe_get(invoice_data, "customer")
    subscription_id = safe_get(invoice_data, "subscription")

    if not customer_id:
        return {"handled": False, "action": "no customer_id"}

    # Find user by Stripe customer ID
    user = db.query(User).filter_by(stripe_customer_id=customer_id).first()
    if not user:
        logger.warning(f"invoice.payment_succeeded: no user found for customer {customer_id}")
        return {"handled": False, "action": "user not found"}

    # Get billing cycle from subscription metadata
    try:
        sub_obj = stripe.Subscription.retrieve(subscription_id)
        metadata = sub_obj.get("metadata", {})
        billing_cycle = metadata.get("billing_cycle", "monthly")
    except Exception:
        billing_cycle = "monthly"

    days = BILLING_CYCLE_DAYS.get(billing_cycle, 30)

    # Extend expiry from today (handles late renewals correctly)
    user.plan_expires_at     = datetime.utcnow() + timedelta(days=days)
    user.subscription_status = "active"
    user.bandwidth_used_bytes = 0   # reset monthly bandwidth on renewal

    db.commit()
    logger.info(f"Renewed plan for user {user.id} (customer {customer_id}), +{days} days")
    return {"handled": True, "action": "plan_renewed", "user_id": str(user.id)}


def _handle_payment_failed(invoice_data: dict, db) -> dict:
    """
    invoice.payment_failed → Card declined or expired.
    Stripe will retry automatically for 7 days.
    We just log it for now. Email notification goes in Step 5.
    """
    from models import User
    customer_id = safe_get(invoice_data, "customer")
    user = db.query(User).filter_by(stripe_customer_id=customer_id).first()

    if user:
        logger.warning(
            f"Payment failed for user {user.id} (customer {customer_id}). "
            f"Stripe will retry. User keeps access during grace period."
        )
        # ── Fire admin alert: payment failed ──────────────────────────────
        _fire_admin_alert(
            event_type = "failed_payment",
            title      = "💳 Payment Failed",
            message    = f"Payment failed for {user.email}. Stripe will retry for 7 days.",
            db         = db,
            meta       = {"user_id": str(user.id), "email": user.email, "stripe_customer": customer_id},
        )
        return {"handled": True, "action": "payment_failed_logged", "user_id": str(user.id)}

    return {"handled": False, "action": "user not found"}


def _handle_subscription_deleted(subscription_data: dict, db, revoke_fn) -> dict:
    """
    customer.subscription.deleted → Subscription cancelled or all retries failed.
    1. Downgrade user to free plan immediately
    2. Revoke ALL WireGuard configs (kicks them off VPN)
    """
    from models import User, Subscription
    from datetime import datetime

    customer_id = safe_get(subscription_data, "customer")
    sub_id      = safe_get(subscription_data, "id")
    user = db.query(User).filter_by(stripe_customer_id=customer_id).first()

    if not user:
        logger.warning(f"subscription.deleted: no user for customer {customer_id}")
        return {"handled": False, "action": "user not found"}

    old_plan = user.plan

    # Downgrade to free immediately
    user.plan                = "free"
    user.subscription_status = "inactive"
    user.plan_expires_at     = None

    # Update Subscription history table
    sub_record = db.query(Subscription).filter_by(stripe_subscription_id=sub_id).first()
    if sub_record:
        sub_record.status = "cancelled"
        sub_record.cancelled_at = datetime.utcnow()

    # Revoke all WireGuard peer configs
    revoked = revoke_fn(db, str(user.id))
    db.commit()

    # ── Fire admin alert: refund / subscription cancelled ───────────────
    _fire_admin_alert(
        event_type = "refund_request",
        title      = "🔄 Subscription Cancelled",
        message    = f"{user.email} cancelled their {old_plan} subscription. {revoked} config(s) revoked.",
        db         = db,
        meta       = {"user_id": str(user.id), "email": user.email, "old_plan": old_plan, "configs_revoked": revoked},
    )

    logger.info(
        f"Subscription cancelled for user {user.id} — "
        f"downgraded from {old_plan} to free. "
        f"Revoked {revoked} WireGuard configs."
    )
    return {
        "handled": True,
        "action":  "subscription_cancelled",
        "user_id": str(user.id),
        "configs_revoked": revoked,
    }


def _handle_subscription_updated(subscription_data: dict, db) -> dict:
    """
    customer.subscription.updated → User changed plan via billing portal.
    Updates the plan in our DB to match what Stripe has.
    """
    from models import User, Subscription
    from datetime import datetime

    customer_id = safe_get(subscription_data, "customer")
    sub_id      = safe_get(subscription_data, "id")
    metadata    = safe_get(subscription_data, "metadata") or {}
    new_plan    = safe_get(metadata, "plan")
    cancel_at_period_end = safe_get(subscription_data, "cancel_at_period_end", False)
    cancel_at            = safe_get(subscription_data, "cancel_at")
    status               = safe_get(subscription_data, "status", "active")
    
    # It's considered cancelled if it's explicitly scheduled to cancel or already cancelled
    is_cancelled = cancel_at_period_end or (cancel_at is not None) or status in ["canceled", "unpaid", "past_due"]

    user = db.query(User).filter_by(stripe_customer_id=customer_id).first()
    if not user:
        return {"handled": False, "action": "missing user"}

    sub_record = db.query(Subscription).filter_by(stripe_subscription_id=sub_id).first()
    logger.info(f"DEBUG _handle_subscription_updated: sub_id={sub_id}, is_cancelled={is_cancelled}, status={status}, sub_record_found={sub_record is not None}")

    if is_cancelled:
        user.subscription_status = "cancelled"
        if sub_record:
            sub_record.status = "cancelled"
            if not sub_record.cancelled_at:
                sub_record.cancelled_at = datetime.utcnow()
    else:
        user.subscription_status = "active"
        if new_plan:
            user.plan = new_plan
        if sub_record:
            sub_record.status = "active"
            sub_record.cancelled_at = None
            
    db.commit()

    logger.info(f"Subscription updated for user {user.id} → plan: {user.plan}, status: {user.subscription_status}, sub_record_status: {sub_record.status if sub_record else 'None'}")
    return {"handled": True, "action": "subscription_updated", "user_id": str(user.id)}
