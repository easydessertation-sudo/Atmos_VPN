"""
Shared dependencies for all admin routers.
  - admin_required  → validates X-Admin-Token header
  - get_db          → yields a DB session (re-exported from models)
  - success / error → standard JSON response helpers (Decimal-safe)
"""
import os
import json
import uuid
import jwt
from decimal import Decimal
from datetime import date, datetime
from typing import Optional

from dotenv import load_dotenv
from fastapi import Header, HTTPException, Depends
from fastapi.responses import Response
from sqlalchemy.orm import Session

# Re-export DB dependency
from models import get_db, AdminUser

load_dotenv()

JWT_SECRET = os.environ.get("JWT_SECRET", "super-secret-jwt-key")
JWT_ALGORITHM = "HS256"


# ─── JSON Encoder: handles Decimal, datetime, UUID ────────────────────────
class _SafeEncoder(json.JSONEncoder):
    """
    Extends the default JSON encoder to handle types that PostgreSQL / SQLAlchemy
    commonly returns but Python's built-in json module cannot serialize:
      - Decimal  → float  (SUM, AVG, NUMERIC columns)
      - datetime → ISO 8601 string
      - date     → ISO 8601 string
      - UUID     → str
    """
    def default(self, obj):
        if isinstance(obj, Decimal):
            return float(obj)
        if isinstance(obj, (datetime, date)):
            return obj.isoformat()
        if isinstance(obj, uuid.UUID):
            return str(obj)
        return super().default(obj)


def _json_response(payload: dict, status_code: int = 200) -> Response:
    """Serialize payload using _SafeEncoder and return a JSON Response."""
    body = json.dumps(payload, cls=_SafeEncoder, separators=(",", ":"))
    return Response(
        content=body,
        status_code=status_code,
        media_type="application/json",
    )


# ─── Auth Guard ────────────────────────────────────────────────────────────
def admin_required(
    x_admin_token: Optional[str] = Header(default=None),
    db: Session = Depends(get_db),
) -> AdminUser:
    """
    Dependency injected into every protected route.
    Frontend must pass:  X-Admin-Token: <JWT_TOKEN>
    Returns the current AdminUser object.
    """
    if not x_admin_token:
        raise HTTPException(status_code=401, detail="Admin token required")

    try:
        payload = jwt.decode(x_admin_token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
        admin_id = payload.get("sub")
        if not admin_id:
            raise HTTPException(status_code=401, detail="Invalid admin token")

        admin_user = db.query(AdminUser).filter(AdminUser.id == admin_id).first()
        if not admin_user:
            raise HTTPException(status_code=401, detail="Admin user not found")

        return admin_user
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Admin token expired")
    except jwt.InvalidTokenError:
        # Fallback: accept raw ADMIN_PASSWORD for local testing
        if x_admin_token == os.environ.get("ADMIN_PASSWORD", "securevpn-admin-2024"):
            mock_admin = db.query(AdminUser).filter(AdminUser.role == "Super Admin").first()
            if mock_admin:
                return mock_admin
        raise HTTPException(status_code=401, detail="Invalid admin token")


class RoleChecker:
    def __init__(self, allowed_roles: list):
        self.allowed_roles = allowed_roles

    def __call__(self, current_admin: AdminUser = Depends(admin_required)):
        if current_admin.role not in self.allowed_roles and current_admin.role != "Super Admin":
            raise HTTPException(
                status_code=403,
                detail=f"Operation not permitted. Required roles: {self.allowed_roles}",
            )
        return current_admin


def log_admin_action(
    db: Session,
    admin_email: str,
    action: str,
    ip_address: str = "127.0.0.1",
):
    """Helper function to automatically insert an Audit Log entry."""
    from models import AuditLog

    log = AuditLog(
        admin_email=admin_email,
        action=action,
        ip_address=ip_address,
        timestamp=datetime.utcnow(),
    )
    db.add(log)
    db.commit()


# ─── Response Helpers ──────────────────────────────────────────────────────
def success(data=None, msg: str = "OK", status_code: int = 200):
    return _json_response(
        {"success": True, "message": msg, "data": data},
        status_code=status_code,
    )


def error(msg: str = "Error", status_code: int = 400, data=None):
    return _json_response(
        {"success": False, "message": msg, "data": data},
        status_code=status_code,
    )
