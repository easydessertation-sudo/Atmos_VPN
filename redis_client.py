"""
SecureVPN — Redis Client
Handles all Redis operations:
  1. Token blocklist  — for the logout endpoint
  2. Cache helpers    — for server list caching
  3. Rate limit utils — (used later for login rate limiting)

Why Redis instead of PostgreSQL for these?
  - Token blocklist: Needs microsecond lookup on EVERY request. DB is too slow.
  - Caching: DB queries take ~5ms each. Redis takes ~0.1ms. 50x faster.
  - Redis auto-expires keys (TTL) — perfect for tokens and cache invalidation.
"""
import os
import json
import redis
from dotenv import load_dotenv

load_dotenv()

# ─────────────────────────────────────────────────────────────────
# Redis Connection
# ─────────────────────────────────────────────────────────────────
REDIS_URL = os.environ.get("REDIS_URL", "")

# _client is None if no Redis URL is set.
# All helper functions handle this gracefully (app still works without Redis,
# just without caching and logout blocklist).
_client = None


def get_redis():
    """
    Get the Redis client singleton.
    Returns None if Redis is not configured — app degrades gracefully.
    """
    global _client
    if _client is not None:
        return _client
    if not REDIS_URL:
        return None
    try:
        _client = redis.from_url(
            REDIS_URL,
            decode_responses=True,   # always return strings, not bytes
            socket_connect_timeout=3,
            socket_timeout=3,
        )
        _client.ping()   # test connection immediately
        print("✅ Redis connected.")
        return _client
    except Exception as e:
        print(f"⚠️  Redis connection failed: {e}")
        print("⚠️  Running without Redis — caching and logout blocklist disabled.")
        return None


# ─────────────────────────────────────────────────────────────────
# Feature 1: JWT Token Blocklist  (for logout)
#
# How it works:
#   When user logs out → we store their token in Redis with an expiry.
#   On every subsequent request → we check if the token is in the blocklist.
#   If yes → reject the request even if the JWT signature is valid.
#
# Why TTL = JWT expiry time?
#   Once the JWT naturally expires, it's already invalid.
#   No need to keep it in Redis after that. Redis auto-cleans it.
# ─────────────────────────────────────────────────────────────────
BLOCKLIST_PREFIX = "blocklist:"   # Redis key format: "blocklist:<token>"


def blocklist_token(token: str, ttl_seconds: int = 43200):
    """
    Add a JWT token to the blocklist.
    ttl_seconds = 43200 = 12 hours (matches JWT_ACCESS_EXPIRE in app.py)

    After ttl_seconds, Redis automatically deletes the key.
    """
    r = get_redis()
    if r is None:
        return False   # Redis not available — logout still works, just not 100% secure
    try:
        key = f"{BLOCKLIST_PREFIX}{token}"
        r.setex(key, ttl_seconds, "1")   # "1" is a dummy value, we only care about existence
        return True
    except Exception:
        return False


def is_token_blocked(token: str) -> bool:
    """
    Check if a token is in the blocklist.
    Called on EVERY protected request (must be fast — Redis makes this ~0.1ms).

    Returns True  → token is blocked → reject the request
    Returns False → token is clean   → allow the request
    """
    r = get_redis()
    if r is None:
        return False   # if Redis is down, we allow tokens (fail-open for availability)
    try:
        key = f"{BLOCKLIST_PREFIX}{token}"
        return r.exists(key) == 1
    except Exception:
        return False   # Redis error → allow request (availability over security)


# ─────────────────────────────────────────────────────────────────
# Feature 1.5: Password Reset Tokens
#
# Generates a quick 15-minute token allowing users to reset passwords.
# ─────────────────────────────────────────────────────────────────
RESET_PREFIX = "reset:"

def store_password_reset_token(token: str, user_id: str, ttl_seconds: int = 900) -> bool:
    """
    Store the token mapping to the user_id for 15 minutes (900s).
    """
    r = get_redis()
    if r is None:
        print("⚠️ Password reset requires Redis!")
        return False
    try:
        r.setex(f"{RESET_PREFIX}{token}", ttl_seconds, str(user_id))
        return True
    except Exception:
        return False

def get_user_by_reset_token(token: str) -> str:
    """
    Retrieves the user_id for a given reset token, then immediately deletes
    the token so it can only be used ONCE.
    Returns None if token is invalid or expired.
    """
    r = get_redis()
    if r is None:
        return None
    try:
        key = f"{RESET_PREFIX}{token}"
        user_id = r.get(key)
        if user_id:
            r.delete(key) # Invalidate single-use token
        return user_id
    except Exception:
        return None


# ─────────────────────────────────────────────────────────────────
# Feature 2: Generic Cache Helpers
#
# Usage example:
#   # Store server list for 30 seconds
#   cache_set("server_list", [{"id": "lon-1", ...}], ttl=30)
#
#   # Read it back (returns None if expired or not set)
#   servers = cache_get("server_list")
# ─────────────────────────────────────────────────────────────────
CACHE_PREFIX = "cache:"


def cache_set(key: str, value, ttl: int = 30):
    """
    Store any Python value in Redis cache.
    Value is JSON-serialised automatically.
    ttl = seconds until the cache expires and next request hits DB.
    """
    r = get_redis()
    if r is None:
        return
    try:
        r.setex(f"{CACHE_PREFIX}{key}", ttl, json.dumps(value))
    except Exception:
        pass   # cache failure is silent — request falls back to DB


def cache_get(key: str):
    """
    Retrieve a cached value. Returns None if not cached or expired.
    The calling code should then fetch from DB and re-cache.
    """
    r = get_redis()
    if r is None:
        return None
    try:
        raw = r.get(f"{CACHE_PREFIX}{key}")
        return json.loads(raw) if raw else None
    except Exception:
        return None


def cache_delete(key: str):
    """
    Manually invalidate a cache entry.
    Call this when you update data that's been cached.
    e.g. When admin changes a server → delete "server_list" cache.
    """
    r = get_redis()
    if r is None:
        return
    try:
        r.delete(f"{CACHE_PREFIX}{key}")
    except Exception:
        pass


# ─────────────────────────────────────────────────────────────────
# Feature 3: Store Celery Task Status
#
# When a background job (like WireGuard provisioning) is running,
# the frontend polls for its status. We store that here.
# ─────────────────────────────────────────────────────────────────
JOB_PREFIX = "job:"


def set_job_status(job_id: str, status: dict, ttl: int = 3600):
    """Store background job status (e.g. WireGuard provisioning progress)."""
    r = get_redis()
    if r is None:
        return
    try:
        r.setex(f"{JOB_PREFIX}{job_id}", ttl, json.dumps(status))
    except Exception:
        pass


def get_job_status(job_id: str):
    """Get the status of a background job by ID."""
    r = get_redis()
    if r is None:
        return None
    try:
        raw = r.get(f"{JOB_PREFIX}{job_id}")
        return json.loads(raw) if raw else None
    except Exception:
        return None
