"""
Stripe Plan Recovery Script
============================
Fixes users who paid successfully on Stripe but whose plan was NOT upgraded
due to the webhook delivery failure (expired ngrok URL).

Run with: python recover_stripe_plans.py

What it does:
  1. Fetches all completed Stripe checkout sessions
  2. For each session, reads user_id and plan from metadata
  3. Checks if that user's plan in DB is still 'free'
  4. If yes → upgrades their plan + activates subscription
"""
import os
import sys
sys.stdout.reconfigure(encoding='utf-8')

from datetime import datetime, timedelta
from dotenv import load_dotenv

load_dotenv()

import stripe
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker

# ── Setup ──────────────────────────────────────────────────────────
stripe.api_key = os.environ.get("STRIPE_SECRET_KEY", "")
DATABASE_URL    = os.environ.get("DATABASE_URL", "")

if not stripe.api_key:
    print("ERROR: STRIPE_SECRET_KEY not set in .env")
    sys.exit(1)

if not DATABASE_URL:
    print("ERROR: DATABASE_URL not set in .env")
    sys.exit(1)

engine = create_engine(DATABASE_URL)
Session = sessionmaker(bind=engine)
db = Session()

BILLING_CYCLE_DAYS = {"monthly": 30, "annual": 365}

fixed_count   = 0
skipped_count = 0
error_count   = 0

print("=" * 60)
print("  AtmosVPN — Stripe Plan Recovery Script")
print("=" * 60)
print(f"  Stripe key prefix: {stripe.api_key[:12]}...")
print("=" * 60)

# ── Step 1: Fetch all completed checkout sessions from Stripe ──────
print("\nFetching completed checkout sessions from Stripe...")
sessions = stripe.checkout.Session.list(
    limit=100,   # Increase if you have more than 100 payments
    expand=["data.line_items"],
)

print(f"Found {len(sessions.data)} checkout session(s) from Stripe.\n")

for session in sessions.data:
    # Only process fully paid sessions
    if session.payment_status != "paid":
        print(f"  SKIP [not paid]: session {session.id}")
        skipped_count += 1
        continue

    metadata      = session.metadata or {}
    user_id       = metadata.get("user_id")
    plan          = metadata.get("plan")
    billing_cycle = metadata.get("billing_cycle", "monthly")
    customer_id   = session.customer
    subscription_id = session.subscription

    if not user_id or not plan:
        print(f"  SKIP [no metadata]: session {session.id}")
        skipped_count += 1
        continue

    print(f"  Checking user_id={user_id}, plan={plan}, billing_cycle={billing_cycle}...")

    try:
        # Look up user in DB
        row = db.execute(
            text("SELECT id, email, plan, subscription_status FROM users WHERE id = :uid"),
            {"uid": user_id}
        ).fetchone()

        if not row:
            print(f"  ERROR: user {user_id} not found in DB")
            error_count += 1
            continue

        db_id, email, current_plan, current_status = row

        # Only fix users whose plan is still 'free' despite paying
        if current_plan != "free":
            print(f"  SKIP: user {email} already on plan '{current_plan}' — no fix needed")
            skipped_count += 1
            continue

        # Fix the plan
        print(f"  FIXING: {email} — upgrading from 'free' to '{plan}'...")

        days       = BILLING_CYCLE_DAYS.get(billing_cycle, 30)
        expires_at = datetime.utcnow() + timedelta(days=days)

        # Update users table
        db.execute(
            text("""
                UPDATE users
                SET plan                = :plan,
                    plan_expires_at     = :expires_at,
                    subscription_status = 'active',
                    stripe_customer_id  = :customer_id
                WHERE id = :uid
            """),
            {
                "plan":        plan,
                "expires_at":  expires_at,
                "customer_id": customer_id,
                "uid":         user_id,
            }
        )

        # Check if subscription record already exists
        existing_sub = db.execute(
            text("SELECT id FROM subscriptions WHERE stripe_subscription_id = :sub_id"),
            {"sub_id": subscription_id}
        ).fetchone()

        if not existing_sub:
            # Create subscription record
            db.execute(
                text("""
                    INSERT INTO subscriptions
                        (user_id, plan, billing_cycle, amount_usd, currency,
                         stripe_subscription_id, status, started_at, expires_at)
                    VALUES
                        (:user_id, :plan, :billing_cycle, 0, 'USD',
                         :sub_id, 'active', :started_at, :expires_at)
                """),
                {
                    "user_id":       user_id,
                    "plan":          plan,
                    "billing_cycle": billing_cycle,
                    "sub_id":        subscription_id,
                    "started_at":    datetime.utcnow(),
                    "expires_at":    expires_at,
                }
            )
            print(f"  CREATED subscription record for {email}")
        else:
            print(f"  Subscription record already exists for {email}, skipping insert")

        db.commit()
        print(f"  SUCCESS: {email} upgraded to '{plan}' (expires {expires_at.date()})")
        fixed_count += 1

    except Exception as e:
        db.rollback()
        print(f"  ERROR processing user {user_id}: {e}")
        error_count += 1

# ── Summary ─────────────────────────────────────────────────────────
db.close()

print("\n" + "=" * 60)
print("  Recovery Script Complete")
print("=" * 60)
print(f"  Fixed:   {fixed_count} user(s) upgraded successfully")
print(f"  Skipped: {skipped_count} (already correct or no metadata)")
print(f"  Errors:  {error_count}")
print("=" * 60)

if fixed_count > 0:
    print(f"\nNOTE: {fixed_count} user(s) were upgraded. They should now see their correct plan.")
    print("      Ask them to log out and log back in to see the updated plan.")
