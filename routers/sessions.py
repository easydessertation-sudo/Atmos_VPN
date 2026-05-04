"""
Sessions Router — Admin VPN session management
GET    /api/admin/sessions            → list sessions (active/all, paginated)
GET    /api/admin/sessions/{id}       → session detail
DELETE /api/admin/sessions/{id}/terminate → force-terminate an active session
"""
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from deps import admin_required, get_db, success
from models import VPNSession, User, VPNServer

router = APIRouter()


@router.get("/sessions")
def admin_list_sessions(
    active_only: bool = False,
    server_id:   Optional[str] = None,
    page:        int  = 1,
    limit:       int  = 50,
    _:           None    = Depends(admin_required),
    db:          Session = Depends(get_db),
):
    """
    List VPN sessions with optional filters:
    - active_only: only return currently connected sessions
    - server_id:   filter by a specific server
    - page/limit:  pagination
    """
    q = db.query(VPNSession)
    if active_only:
        q = q.filter_by(is_active=True)
    if server_id:
        q = q.filter_by(server_id=server_id)

    total    = q.count()
    sessions = q.order_by(VPNSession.started_at.desc()).offset((page - 1) * limit).limit(limit).all()

    result = []
    for s in sessions:
        d = s.to_dict()
        user = db.get(User, s.user_id)
        srv  = db.get(VPNServer, s.server_id) if s.server_id else None
        d["user_email"]   = user.email   if user else "Unknown"
        d["user_plan"]    = user.plan    if user else "Unknown"
        d["server_name"]  = srv.name     if srv  else "Unknown"
        d["server_flag"]  = srv.flag     if srv  else ""
        result.append(d)

    return success({
        "sessions": result,
        "total":    total,
        "page":     page,
        "limit":    limit,
        "pages":    (total + limit - 1) // limit,
    })


@router.get("/sessions/{session_id}")
def admin_session_detail(
    session_id: str,
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """Full detail of a specific VPN session including user and server info."""
    session = db.get(VPNSession, session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")

    user = db.get(User, session.user_id)
    srv  = db.get(VPNServer, session.server_id) if session.server_id else None

    data = session.to_dict()
    data["user_email"]  = user.email  if user else "Unknown"
    data["user_plan"]   = user.plan   if user else "Unknown"
    data["server_name"] = srv.name    if srv  else "Unknown"
    data["server_flag"] = srv.flag    if srv  else ""

    return success(data)


@router.delete("/sessions/{session_id}/terminate")
def admin_terminate_session(
    session_id: str,
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """
    Force-terminate an active VPN session.
    Sets is_active=False and records ended_at timestamp.
    NOTE: This marks the session as ended in the database.
    For real WireGuard peer disconnection, SSH peer removal is required.
    """
    session = db.get(VPNSession, session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    if not session.is_active:
        raise HTTPException(status_code=409, detail="Session is already inactive")

    session.is_active = False
    session.ended_at  = datetime.utcnow()
    db.commit()

    return success(
        {"session_id": session_id, "ended_at": session.ended_at.isoformat()},
        "Session terminated successfully",
    )
