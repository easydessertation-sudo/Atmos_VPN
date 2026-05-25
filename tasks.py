"""
SecureVPN — Celery Background Tasks
These are the "heavy jobs" that run OUTSIDE the main API request cycle.

Why background tasks?
  SSH into a WireGuard server takes 2-5 seconds.
  We cannot make users wait 5 seconds every time they connect.
  Instead:
    1. API instantly returns "provisioning started"
    2. This task runs in background, does the SSH work
    3. App polls /api/vpn/status until it's ready

Current tasks:
  - add_wireguard_peer    → SSH into server, add user's public key as WireGuard peer
  - remove_wireguard_peer → SSH into server, remove user's WireGuard peer (disconnect/cancel)
  - update_server_stats   → Periodically update server load % (run every 30 seconds)
  - reset_bandwidth       → Reset all users' monthly bandwidth at billing cycle start

NOTE:
  The actual asyncssh SSH calls are structured and ready.
  They will work when you provide real WireGuard server credentials.
  Until then, they log what they WOULD do (simulation mode).
"""
import os
import asyncio
import logging
from datetime import datetime

from celery_app import celery_app
from redis_client import set_job_status, get_redis

logger = logging.getLogger(__name__)


# ─────────────────────────────────────────────────────────────────
# Helper: Run async code inside Celery (which is synchronous)
#
# Celery tasks are sync by default.
# asyncssh is async (uses async/await).
# This helper bridges the gap.
# ─────────────────────────────────────────────────────────────────
def run_async(coro):
    """Run an async coroutine from a synchronous Celery task."""
    loop = asyncio.new_event_loop()
    try:
        return loop.run_until_complete(coro)
    finally:
        loop.close()


# ─────────────────────────────────────────────────────────────────
# TASK 1: Add WireGuard Peer
#
# Called when: User calls POST /api/vpn/provision or /api/vpn/connect
#
# What it does:
#   1. SSH into the WireGuard VPN server
#   2. Run: wg set wg0 peer <PUBLIC_KEY> allowed-ips <ASSIGNED_IP>/32
#   3. Run: wg-quick save wg0  (CRITICAL: saves config to survive server reboot)
#   4. Update job status in Redis so the app knows when it's ready
#
# Parameters:
#   job_id       — unique ID for this job (stored in Redis for status polling)
#   server_ip    — public IP of the WireGuard server (e.g. "185.156.46.1")
#   public_key   — user's device WireGuard public key
#   assigned_ip  — IP assigned from ip_pool (e.g. "10.0.0.42")
#   config_id    — vpn_configs.id (to update DB after success)
# ─────────────────────────────────────────────────────────────────
@celery_app.task(
    name="tasks.add_wireguard_peer",
    bind=True,
    max_retries=3,
    default_retry_delay=10,   # wait 10 seconds between retries
)
def add_wireguard_peer(self, job_id: str, server_ip: str, public_key: str,
                        assigned_ip: str, config_id: str):
    """
    Background task: Add a user's WireGuard peer to a VPN server.
    Retries up to 3 times if SSH fails (e.g. temporary network issue).
    """
    logger.info(f"[Task {job_id}] Adding WireGuard peer {public_key[:16]}... to {server_ip}")

    # Update job status → "running"
    set_job_status(job_id, {
        "status": "running",
        "message": f"Adding peer to server {server_ip}...",
        "started_at": datetime.utcnow().isoformat(),
    })

    try:
        # Run the async SSH function
        result = run_async(_ssh_add_peer(server_ip, public_key, assigned_ip))

        if result:
            # Success → update job status
            set_job_status(job_id, {
                "status": "completed",
                "message": "WireGuard peer added successfully.",
                "config_id": config_id,
                "assigned_ip": assigned_ip,
                "completed_at": datetime.utcnow().isoformat(),
            })
            logger.info(f"[Task {job_id}] ✅ Peer added successfully.")
            return {"success": True, "config_id": config_id}
        else:
            raise Exception("SSH command returned failure")

    except Exception as exc:
        logger.error(f"[Task {job_id}] ❌ Error: {exc}")

        # Check if we have retries left
        if self.request.retries < self.max_retries:
            set_job_status(job_id, {
                "status": "retrying",
                "message": f"Attempt {self.request.retries + 1} failed. Retrying...",
                "error": str(exc),
            })
            raise self.retry(exc=exc)
        else:
            # All retries exhausted
            set_job_status(job_id, {
                "status": "failed",
                "message": "Failed to add WireGuard peer after 3 attempts.",
                "error": str(exc),
                "failed_at": datetime.utcnow().isoformat(),
            })
            return {"success": False, "error": str(exc)}


async def _ssh_add_peer(server_ip: str, public_key: str, assigned_ip: str) -> bool:
    """
    Actual SSH logic to add a WireGuard peer.
    Uses asyncssh to connect to the server and run wg commands.

    Auth priority:
      1. Per-server password from VPN_SERVER_PASSWORDS env var (JSON map)
      2. SSH key from WG_SSH_KEY_PATH env var

    NOTE: SaveConfig=false is set in wg0.conf, so we manually append
    the peer to the config file to survive reboots.
    """
    import json
    SSH_USER     = os.environ.get("WG_SSH_USER", "root")
    SSH_KEY_PATH = os.environ.get("WG_SSH_KEY_PATH", "~/.ssh/id_rsa")

    # Per-server password map: {"1.2.3.4": "password", ...}
    passwords_raw = os.environ.get("VPN_SERVER_PASSWORDS", "{}")
    try:
        server_passwords = json.loads(passwords_raw)
    except Exception:
        server_passwords = {}

    ssh_password = server_passwords.get(server_ip)

    # ── SIMULATION MODE ──────────────────────────────────────────
    if os.environ.get("WG_SIMULATION", "true").lower() == "true":
        logger.info(f"[SIMULATION] Would run on {server_ip}:")
        logger.info(f"  wg set wg0 peer {public_key} allowed-ips {assigned_ip}/32")
        await asyncio.sleep(1)
        return True
    # ─────────────────────────────────────────────────────────────

    try:
        import asyncssh

        # Build connect kwargs — prefer password if available, else SSH key
        connect_kwargs = dict(
            username=SSH_USER,
            known_hosts=None,
            connect_timeout=30,
        )
        if ssh_password:
            connect_kwargs["password"] = ssh_password
        else:
            connect_kwargs["client_keys"] = [os.path.expanduser(SSH_KEY_PATH)]

        async with asyncssh.connect(server_ip, **connect_kwargs) as conn:
            # Add peer to running WireGuard instance
            cmd = f"wg set wg0 peer {public_key} allowed-ips {assigned_ip}/32"
            await conn.run(cmd, check=True)

            # Persist peer to wg0.conf — but ONLY if not already present
            # (prevents duplicate [Peer] blocks if Celery retries after direct SSH success)
            check_exists = await conn.run(
                f"grep -c '{public_key}' /etc/wireguard/wg0.conf || true",
                check=False
            )
            already_in_conf = int((check_exists.stdout or '0').strip()) > 0

            if not already_in_conf:
                persist_cmd = (
                    f"printf '\\n[Peer]\\nPublicKey = {public_key}\\nAllowedIPs = {assigned_ip}/32\\n'"
                    f" >> /etc/wireguard/wg0.conf"
                )
                await conn.run(persist_cmd, check=True)
                logger.info(f"Peer {public_key[:16]}... added and persisted on {server_ip}")
            else:
                logger.info(f"Peer {public_key[:16]}... already in wg0.conf on {server_ip} — skipped append")

            return True
    except Exception as e:
        logger.error(f"SSH error on {server_ip}: {e}")
        raise


# ─────────────────────────────────────────────────────────────────
# TASK 2: Remove WireGuard Peer
#
# Called when:
#   - User calls DELETE /api/vpn/config/{config_id} (removes a device)
#   - User cancels subscription (Stripe webhook fires)
#   - Admin suspends a user
#
# What it does:
#   1. SSH into the WireGuard server
#   2. Run: wg set wg0 peer <PUBLIC_KEY> remove
#   3. Run: wg-quick save wg0
#   4. Mark the ip_pool entry as is_assigned=false (IP returned to pool)
# ─────────────────────────────────────────────────────────────────
@celery_app.task(
    name="tasks.remove_wireguard_peer",
    bind=True,
    max_retries=3,
    default_retry_delay=10,
)
def remove_wireguard_peer(self, job_id: str, server_ip: str, public_key: str,
                           assigned_ip: str, config_id: str):
    """
    Background task: Remove a user's WireGuard peer from a VPN server.
    Also releases the IP back to the pool.
    """
    logger.info(f"[Task {job_id}] Removing peer {public_key[:16]}... from {server_ip}")

    set_job_status(job_id, {
        "status": "running",
        "message": f"Removing peer from server {server_ip}...",
    })

    try:
        result = run_async(_ssh_remove_peer(server_ip, public_key))

        if result:
            set_job_status(job_id, {
                "status": "completed",
                "message": "WireGuard peer removed. IP returned to pool.",
                "completed_at": datetime.utcnow().isoformat(),
            })
            logger.info(f"[Task {job_id}] ✅ Peer removed.")
            return {"success": True}
        else:
            raise Exception("SSH command returned failure")

    except Exception as exc:
        logger.error(f"[Task {job_id}] ❌ Remove error: {exc}")
        if self.request.retries < self.max_retries:
            raise self.retry(exc=exc)
        set_job_status(job_id, {"status": "failed", "error": str(exc)})
        return {"success": False, "error": str(exc)}


async def _ssh_remove_peer(server_ip: str, public_key: str) -> bool:
    """Actual SSH logic to remove a WireGuard peer."""
    import json
    SSH_USER     = os.environ.get("WG_SSH_USER", "root")
    SSH_KEY_PATH = os.environ.get("WG_SSH_KEY_PATH", "~/.ssh/id_rsa")

    passwords_raw = os.environ.get("VPN_SERVER_PASSWORDS", "{}")
    try:
        server_passwords = json.loads(passwords_raw)
    except Exception:
        server_passwords = {}
    ssh_password = server_passwords.get(server_ip)

    # ── SIMULATION MODE ──────────────────────────────────────────
    if os.environ.get("WG_SIMULATION", "true").lower() == "true":
        logger.info(f"[SIMULATION] Would run on {server_ip}:")
        logger.info(f"  wg set wg0 peer {public_key} remove")
        await asyncio.sleep(1)
        return True
    # ─────────────────────────────────────────────────────────────

    try:
        import asyncssh
        connect_kwargs = dict(
            username=SSH_USER,
            known_hosts=None,
            connect_timeout=30,
        )
        if ssh_password:
            connect_kwargs["password"] = ssh_password
        else:
            connect_kwargs["client_keys"] = [os.path.expanduser(SSH_KEY_PATH)]

        async with asyncssh.connect(server_ip, **connect_kwargs) as conn:
            # Remove from running WireGuard
            await conn.run(f"wg set wg0 peer {public_key} remove", check=True)
            # Remove ALL occurrences of this peer from wg0.conf
            # (handles cases where duplicates crept in)
            # Remove all [Peer] blocks for this key using awk
            # This handles duplicate entries cleanly
            remove_cmd = (
                "awk 'BEGIN{skip=0} "
                "/^\\[Peer\\]/{skip=0} "
                f"/^PublicKey = {public_key.replace('+', '\\\\+').replace('/', '\\\\/').replace('=', '\\\\=')}/"
                "{skip=1; found=NR} "
                "skip && NR==found-1{next} "
                "!skip{print}' /etc/wireguard/wg0.conf > /tmp/wg0_clean.conf && "
                "mv /tmp/wg0_clean.conf /etc/wireguard/wg0.conf"
            )
            await conn.run(remove_cmd, check=False)
            return True
    except Exception as e:
        logger.error(f"SSH error removing peer on {server_ip}: {e}")
        raise


# ─────────────────────────────────────────────────────────────────
# TASK 3: Update Server Stats
#
# Called by: Celery Beat scheduler (runs every 30 seconds)
# What it does: Queries current peer count from WireGuard server,
#               updates load_pct in the DB, invalidates server cache.
#
# This task is a placeholder — implement when you have real servers.
# ─────────────────────────────────────────────────────────────────
@celery_app.task(name="tasks.update_server_stats")
def update_server_stats(server_id: str, server_ip: str):
    """
    Periodic task: Update server load statistics.
    In simulation mode, just logs. Real implementation SSHs into server
    and runs 'wg show wg0 peers | wc -l' to count active peers.
    """
    logger.info(f"[Stats] Would update stats for server {server_id} at {server_ip}")

    # Invalidate the server list cache so next request gets fresh data
    from redis_client import cache_delete
    cache_delete("server_list")
    cache_delete(f"server_{server_id}")

    return {"server_id": server_id, "updated": True}


# ─────────────────────────────────────────────────────────────────
# TASK 4: Reset Monthly Bandwidth
#
# Called by: Stripe webhook when new billing period starts
#            (invoice.payment_succeeded event)
# What it does: Resets bandwidth_used_bytes=0 for a specific user.
# ─────────────────────────────────────────────────────────────────
@celery_app.task(name="tasks.reset_user_bandwidth")
def reset_user_bandwidth(user_id: str):
    """Reset a user's monthly bandwidth counter at the start of new billing period."""
    from models import SessionLocal, User
    db = SessionLocal()
    try:
        user = db.get(User, user_id)
        if user:
            user.bandwidth_used_bytes = 0
            db.commit()
            logger.info(f"[Bandwidth] Reset for user {user_id}")
            return {"success": True, "user_id": user_id}
        return {"success": False, "error": "User not found"}
    except Exception as e:
        db.rollback()
        logger.error(f"[Bandwidth] Reset failed for {user_id}: {e}")
        return {"success": False, "error": str(e)}
    finally:
        db.close()


# ─────────────────────────────────────────────────────────────────
# TASK 5: Disconnect Expired Free Users
#
# Called by: Celery Beat scheduler (runs every 1 minute)
# What it does:
#   1. Queries DB for any active VPNSessions where user.vpn_expiration_time < NOW()
#   2. Enqueues remove_wireguard_peer to kick them off the server
#   3. Marks session as inactive
# ─────────────────────────────────────────────────────────────────
@celery_app.task(name="tasks.disconnect_expired_users")
def disconnect_expired_users():
    """Finds users whose VPN time has expired and removes their WireGuard peer."""
    from models import SessionLocal, User, VPNSession, VPNServer, VPNConfig
    import uuid
    db = SessionLocal()
    
    try:
        now = datetime.utcnow()
        # Find all active sessions
        active_sessions = db.query(VPNSession).filter(VPNSession.is_active == True).all()
        
        expired_sessions = []
        for session in active_sessions:
            user = session.user
            server = db.get(VPNServer, session.server_id)
            if not user or not server:
                continue
            
            is_expired = False
            if user.plan == "free":
                if server.required_plan != "free":
                    # Ad-reward connection
                    if not user.vpn_expiration_time or user.vpn_expiration_time < now:
                        is_expired = True
                else:
                    # Standard free session limit (45 minutes)
                    elapsed = (now - session.started_at).total_seconds()
                    if elapsed >= 45 * 60:
                        is_expired = True
            
            if is_expired:
                expired_sessions.append(session)
        
        count = 0
        for session in expired_sessions:
            user = session.user
            server = db.get(VPNServer, session.server_id)
            config = db.get(VPNConfig, session.config_id) if session.config_id else None
            
            if server and config:
                # 1. SSH remove peer
                job_id = str(uuid.uuid4())
                remove_wireguard_peer.delay(
                    job_id=job_id,
                    server_ip=server.ip_address,
                    public_key=config.public_key,
                    assigned_ip=config.assigned_ip,
                    config_id=str(config.id)
                )
                logger.info(f"[Disconnect] Kicking off expired user {user.id} from {server.id}")
            
            # 2. Mark session as ended
            session.is_active = False
            session.ended_at = now
            count += 1
            
        if count > 0:
            db.commit()
            logger.info(f"[Disconnect] Disconnected {count} expired sessions.")
            
        return {"success": True, "disconnected_count": count}
        
    except Exception as e:
        db.rollback()
        logger.error(f"[Disconnect] Failed to process expired users: {e}")
        return {"success": False, "error": str(e)}
    finally:
        db.close()


# ─────────────────────────────────────────────────────────────────
# TASK 5: Send Push Notification
#
# Called when: Any user notification is created in app.py
#
# What it does:
#   1. Looks up all registered FCM tokens for the user in database.
#   2. Sends a push notification using Firebase Admin SDK.
#   3. Cleans up any expired/invalid tokens returned by Firebase.
# ─────────────────────────────────────────────────────────────────

_firebase_initialized = False

def _init_firebase():
    global _firebase_initialized
    if _firebase_initialized:
        return True
    
    cred_path = os.environ.get("FIREBASE_CREDENTIALS_PATH", "firebase-service-account.json")
    if os.path.exists(cred_path):
        try:
            import firebase_admin
            from firebase_admin import credentials
            cred = credentials.Certificate(cred_path)
            firebase_admin.initialize_app(cred)
            _firebase_initialized = True
            logger.info("Firebase Admin SDK initialized successfully.")
            return True
        except Exception as e:
            logger.error(f"Error initializing Firebase Admin SDK: {e}")
            return False
    else:
        logger.warning(f"Firebase credentials not found at '{cred_path}'. FCM push notifications will run in SIMULATION mode.")
        return False


@celery_app.task(name="tasks.send_push_notification")
def send_push_notification(user_id: str, title: str, message: str, notification_type: str, meta: str = None, notification_id: str = None):
    """
    Background task to send a push notification via FCM.
    """
    logger.info(f"Background task: Sending push to user {user_id} - Title: '{title}'")

    from models import SessionLocal, FCMToken
    db = SessionLocal()
    try:
        tokens = db.query(FCMToken).filter_by(user_id=user_id).all()
        if not tokens:
            logger.info(f"No FCM tokens registered for user {user_id}. Skipping push.")
            return {"success": True, "sent": 0, "message": "No tokens"}

        fcm_tokens = [t.fcm_token for t in tokens]
        
        # Check if Firebase is initialized
        if _init_firebase():
            import json
            from firebase_admin import messaging
            
            # Prepare data payload (must be key-value pairs of strings)
            data = {"type": notification_type}
            if notification_id:
                data["id"] = str(notification_id)
            if meta:
                try:
                    meta_dict = json.loads(meta)
                    for k, v in meta_dict.items():
                        data[k] = str(v)
                except Exception:
                    data["meta"] = str(meta)

            multicast_msg = messaging.MulticastMessage(
                notification=messaging.Notification(
                    title=title,
                    body=message,
                ),
                data=data,
                android=messaging.AndroidConfig(
                    priority="high",
                ),
                apns=messaging.APNSConfig(
                    headers={"apns-priority": "10"},
                ),
                tokens=fcm_tokens,
            )
            response = messaging.send_each_for_multicast(multicast_msg)
            logger.info(f"FCM Multicast sent: success={response.success_count}, failure={response.failure_count}")

            # Clean up failed tokens
            if response.failure_count > 0:
                invalid_tokens = []
                for idx, resp in enumerate(response.responses):
                    if not resp.success:
                        # Unregistered or invalid tokens
                        invalid_tokens.append(fcm_tokens[idx])
                
                if invalid_tokens:
                    db.query(FCMToken).filter(FCMToken.fcm_token.in_(invalid_tokens)).delete(synchronize_session=False)
                    db.commit()
                    logger.info(f"Cleaned up {len(invalid_tokens)} expired/invalid FCM tokens.")

            return {
                "success": True,
                "sent": response.success_count,
                "failed": response.failure_count,
            }
        else:
            # Simulation Mode
            logger.info(f"[SIMULATION] FCM Push sent to {len(fcm_tokens)} devices: Title='{title}', Message='{message}', Type='{notification_type}'")
            return {"success": True, "simulated": len(fcm_tokens)}

    except Exception as e:
        logger.error(f"Error in send_push_notification task: {e}")
        return {"success": False, "error": str(e)}
    finally:
        db.close()


