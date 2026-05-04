from datetime import datetime, timedelta
from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session
from sqlalchemy import desc
from typing import Optional

from deps import admin_required, get_db, success
from models import AuditLog

router = APIRouter()

@router.get("/logs")
def get_audit_logs(
    search: Optional[str] = None,
    admin: Optional[str] = None,
    date: Optional[str] = None,
    _: None = Depends(admin_required),
    db: Session = Depends(get_db)
):
    """
    Get audit logs with optional filtering by search term (action), admin email, and date.
    """
    
    logs_query = db.query(AuditLog)
    


    # Get distinct admins for the dropdown BEFORE filtering
    all_logs = db.query(AuditLog).all()
    distinct_admins = list(set([l.admin_email for l in all_logs]))
    
    # Apply filters
    if search:
        logs_query = logs_query.filter(AuditLog.action.ilike(f"%{search}%"))
    if admin and admin != "All Admins":
        logs_query = logs_query.filter(AuditLog.admin_email == admin)
    if date:
        try:
            # Parse DD-MM-YYYY or YYYY-MM-DD
            if "-" in date:
                parts = date.split("-")
                if len(parts[0]) == 4:
                    filter_date = datetime.strptime(date, "%Y-%m-%d").date()
                else:
                    filter_date = datetime.strptime(date, "%d-%m-%Y").date()
            
                logs_query = logs_query.filter(
                    db.func.date(AuditLog.timestamp) == filter_date
                )
        except Exception:
            pass

    logs = logs_query.order_by(desc(AuditLog.timestamp)).limit(500).all()

    return success({
        "filters": {
            "admins": distinct_admins
        },
        "logs": [l.to_dict() for l in logs]
    })
