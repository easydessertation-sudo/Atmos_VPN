"""
Admin Alerts Router — /api/admin/alerts/*
Powers the admin panel notification bell icon.

GET    /api/admin/alerts          → list all alerts (unread first)
GET    /api/admin/alerts/count    → unread count for bell badge
PATCH  /api/admin/alerts/{id}     → mark single alert as read
POST   /api/admin/alerts/read-all → mark ALL as read
DELETE /api/admin/alerts/{id}     → delete a single alert
DELETE /api/admin/alerts          → clear all alerts
"""
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from deps import admin_required, get_db, success
from models import AdminAlert

router = APIRouter()


@router.get("/alerts/count")
def get_alert_count(
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """
    Returns the unread alert count for the bell badge number.
    Call this on every page load or on a short poll interval (e.g. every 30s).
    """
    unread = db.query(AdminAlert).filter_by(is_read=False).count()
    total  = db.query(AdminAlert).count()
    return success({"unread": unread, "total": total})


@router.get("/alerts")
def list_alerts(
    unread_only: bool    = False,
    limit:       int     = 50,
    _:           None    = Depends(admin_required),
    db:          Session = Depends(get_db),
):
    """
    List admin alerts for the bell dropdown.
    - unread_only=true  → only show unread
    - limit             → max number to return (default 50)
    Ordered: unread first, then by created_at desc.
    """
    q = db.query(AdminAlert)
    if unread_only:
        q = q.filter_by(is_read=False)
    alerts = q.order_by(AdminAlert.is_read.asc(), AdminAlert.created_at.desc()).limit(limit).all()

    unread_count = db.query(AdminAlert).filter_by(is_read=False).count()

    return success({
        "alerts":       [a.to_dict() for a in alerts],
        "unread_count": unread_count,
        "total":        q.count(),
    })


@router.patch("/alerts/{alert_id}")
def mark_alert_read(
    alert_id: str,
    _:        None    = Depends(admin_required),
    db:       Session = Depends(get_db),
):
    """Mark a single alert as read (clicking on it in the dropdown)."""
    alert = db.get(AdminAlert, alert_id)
    if not alert:
        raise HTTPException(status_code=404, detail="Alert not found")
    alert.is_read = True
    db.commit()
    return success(alert.to_dict(), "Alert marked as read")


@router.post("/alerts/read-all")
def mark_all_read(
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """Mark ALL unread alerts as read ('Mark all as read' button)."""
    updated = db.query(AdminAlert).filter_by(is_read=False).update({"is_read": True})
    db.commit()
    return success({"marked_read": updated}, f"Marked {updated} alerts as read")


@router.delete("/alerts/{alert_id}")
def delete_alert(
    alert_id: str,
    _:        None    = Depends(admin_required),
    db:       Session = Depends(get_db),
):
    """Delete a single alert (dismiss button)."""
    alert = db.get(AdminAlert, alert_id)
    if not alert:
        raise HTTPException(status_code=404, detail="Alert not found")
    db.delete(alert)
    db.commit()
    return success({"id": alert_id}, "Alert deleted")


@router.delete("/alerts")
def clear_all_alerts(
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """Clear ALL alerts ('Clear all' button)."""
    count = db.query(AdminAlert).count()
    db.query(AdminAlert).delete()
    db.commit()
    return success({"deleted": count}, f"Cleared {count} alerts")
