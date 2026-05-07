"""
SecureVPN — Celery Application
Celery is the background task worker.

Architecture:
  [FastAPI] → sends task to → [Redis Broker] → [Celery Worker] picks it up → runs it

Redis plays TWO roles here:
  1. Broker  — the "task queue". FastAPI puts tasks here, Celery reads from here.
  2. Backend — stores task results (so we can check if a task succeeded/failed).

SSL Note:
  Upstash uses rediss:// (TLS). Celery requires explicit ssl_cert_reqs settings.
  We use CERT_NONE because Upstash manages their own certificates — safe for cloud Redis.

To run the Celery worker (in a SEPARATE terminal from uvicorn):
  celery -A celery_app worker --loglevel=info --pool=solo

  --pool=solo is for Windows (Celery's default pool doesn't work on Windows).
  On Linux servers (Hetzner), use --pool=prefork instead.

To monitor tasks visually (Flower UI at http://localhost:5555):
  celery -A celery_app flower
"""
import os
import ssl
from celery import Celery
from dotenv import load_dotenv

load_dotenv()

REDIS_URL = os.environ.get("REDIS_URL", "redis://localhost:6379/0")

# ─────────────────────────────────────────────────────────────────
# SSL Configuration for Upstash (rediss://)
#
# Upstash Redis uses TLS (rediss://).
# Celery requires explicit ssl_cert_reqs when using rediss://.
# We use CERT_NONE because Upstash manages their own certs —
# this is safe for a managed cloud Redis service.
#
# If REDIS_URL starts with plain redis:// (local dev), no SSL needed.
# ─────────────────────────────────────────────────────────────────
_is_tls = REDIS_URL.startswith("rediss://")

_ssl_options = {
    "ssl_cert_reqs": ssl.CERT_NONE,
} if _is_tls else {}

# ─────────────────────────────────────────────────────────────────
# Create the Celery app
#
# broker  = where tasks are queued (Redis)
# backend = where task results are stored (Redis)
# ─────────────────────────────────────────────────────────────────
celery_app = Celery(
    "securevpn",
    broker=REDIS_URL,
    backend=REDIS_URL,
    include=["tasks"],   # tells Celery to load tasks from tasks.py
)

# ─────────────────────────────────────────────────────────────────
# Celery Configuration
# ─────────────────────────────────────────────────────────────────
celery_app.conf.update(
    # Task serialisation — use JSON (safe, readable)
    task_serializer="json",
    result_serializer="json",
    accept_content=["json"],

    # Timezone
    timezone="UTC",
    enable_utc=True,

    # Task result expiry — keep results for 1 hour, then auto-delete
    result_expires=3600,

    # Task acknowledgement — safer, only ack after task completes
    task_acks_late=True,
    worker_prefetch_multiplier=1,

    # Task routing — all tasks go to the "default" queue
    task_default_queue="default",

    # ── SSL for Upstash rediss:// connections ──────────────────────
    # broker_use_ssl:       SSL options for the task queue connection
    # redis_backend_use_ssl: SSL options for the result store connection
    # Only applied when REDIS_URL uses rediss:// (Upstash TLS)
    **({"broker_use_ssl": _ssl_options, "redis_backend_use_ssl": _ssl_options} if _is_tls else {}),

    # ── Periodic Tasks (Celery Beat) ───────────────────────────────
    beat_schedule={
        "disconnect_expired_users_every_minute": {
            "task": "tasks.disconnect_expired_users",
            "schedule": 60.0,  # runs every 60 seconds
        },
    },
)

