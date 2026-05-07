"""
AtmosVPN — Admin Panel Backend API
FastAPI + SQLAlchemy — Dedicated admin service

Run with:  uvicorn app:app --reload --port 5001
Docs at:   http://localhost:5001/docs

This service is separate from the main VPN backend (port 5000).
It shares the same database (models.py) but exposes only admin endpoints.
All routes require X-Admin-Token header (set ADMIN_PASSWORD in .env).
"""
import os
from dotenv import load_dotenv

load_dotenv()

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded

from models import Base, engine

# ─── Routers ───────────────────────────────────────────────────────────────
from routers import auth, users, servers, sessions, tickets, settings, analytics, subscriptions, revenue, promotions, system_status, security, notifications, emails, blog, careers, press, downloads, admin_team, audit, support_content

# ─────────────────────────────────────────────────────────────────
# App Setup
# ─────────────────────────────────────────────────────────────────
app = FastAPI(
    title="AtmosVPN Admin API",
    description=(
        "Dedicated Admin Backend for AtmosVPN. "
        "All endpoints require X-Admin-Token header. "
        "Runs on port 5001 (main VPN API runs on 5000)."
    ),
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
)

# ─── CORS ──────────────────────────────────────────────────────────────────
# In production, restrict allow_origins to your admin panel domain only
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ─── Rate Limiting ─────────────────────────────────────────────────────────
limiter = Limiter(key_func=get_remote_address)
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# ─── Include Routers ───────────────────────────────────────────────────────
app.include_router(auth.router,          prefix="/api/admin", tags=["Auth"])
app.include_router(analytics.router,     prefix="/api/admin", tags=["Analytics"])
app.include_router(users.router,         prefix="/api/admin", tags=["Users"])
app.include_router(servers.router,       prefix="/api/admin", tags=["Servers"])
app.include_router(sessions.router,      prefix="/api/admin", tags=["Sessions"])
app.include_router(tickets.router,       prefix="/api/admin", tags=["Support Tickets"])
app.include_router(subscriptions.router, prefix="/api/admin", tags=["Subscriptions"])
app.include_router(settings.router,      prefix="/api/admin", tags=["Settings"])
app.include_router(revenue.router,       prefix="/api/admin", tags=["Revenue & Finance"])
app.include_router(promotions.router,    prefix="/api/admin", tags=["Promotions & Coupons"])
app.include_router(system_status.router, prefix="/api/admin/status", tags=["System Status"])
app.include_router(security.router,      prefix="/api/admin/security", tags=["Security Center"])
app.include_router(notifications.router, prefix="/api/admin/notifications", tags=["Push Notifications"])
app.include_router(emails.router,        prefix="/api/admin/emails", tags=["Email Campaigns"])
app.include_router(blog.router,          prefix="/api/admin/blog", tags=["Blog Management"])
app.include_router(careers.router,       prefix="/api/admin/careers", tags=["Careers"])
app.include_router(press.router,         prefix="/api/admin/press", tags=["Press & Media"])
app.include_router(downloads.router,     prefix="/api/admin/downloads", tags=["Downloads & Versions"])
app.include_router(admin_team.router,    prefix="/api/admin/team", tags=["Admin Team"])
app.include_router(audit.router,           prefix="/api/admin/audit",    tags=["Audit Log"])
app.include_router(support_content.router, prefix="/api/admin/support", tags=["Support Content"])


# ─── Startup ───────────────────────────────────────────────────────────────
@app.on_event("startup")
def on_startup():
    """Ensure all DB tables exist on startup (shared DB with main backend)."""
    try:
        Base.metadata.create_all(bind=engine)
        print("✅ Admin Panel: DB connected and tables verified.")
    except Exception as e:
        print(f"⚠️  Admin Panel: DB connection failed: {e}")


@app.get("/", tags=["Health"])
def health():
    return {"service": "AtmosVPN Admin API", "status": "running", "version": "1.0.0"}


# ─── Entry Point ───────────────────────────────────────────────────────────
if __name__ == "__main__":
    import uvicorn
    port = int(os.environ.get("ADMIN_PORT", 5001))
    uvicorn.run("app:app", host="0.0.0.0", port=port, reload=True)
