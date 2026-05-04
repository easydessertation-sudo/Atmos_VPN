"""
Server Management Router  —  /api/admin/servers/*

┌─────────────────────────────────────────────────────────────────┐
│  GET    /api/admin/servers/overview      → KPI stats card data  │
│  GET    /api/admin/servers               → list (search/filter) │
│  POST   /api/admin/servers               → add new server       │
│  GET    /api/admin/servers/{id}          → single server detail │
│  PATCH  /api/admin/servers/{id}          → edit server          │
│  DELETE /api/admin/servers/{id}          → remove server        │
│  POST   /api/admin/servers/{id}/restart  → mark restart event   │
│  PATCH  /api/admin/servers/{id}/status   → online/maint/offline │
└─────────────────────────────────────────────────────────────────┘

UI elements mapped:
  Header KPIs  → /overview
  Grid cards   → /servers (with search, status, region filters)
  + Add Server → POST /servers
  Restart btn  → POST /servers/{id}/restart
  Edit btn     → PATCH /servers/{id}
  Delete btn   → DELETE /servers/{id}
  Status badge → PATCH /servers/{id}/status
"""
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy import func
from sqlalchemy.orm import Session

from deps import admin_required, get_db, success
from models import VPNServer, VPNSession

router = APIRouter()


# ══════════════════════════════════════════════════════════════════
# ─── Pydantic Schemas ─────────────────────────────────────────────
# ══════════════════════════════════════════════════════════════════

class CreateServerBody(BaseModel):
    id:             str   = Field(..., min_length=2, max_length=20,
                                  description="Human-readable ID e.g. 'nyc-1', 'lon-2'")
    name:           str
    city:           str
    country:        str
    country_code:   str   = Field(..., max_length=5,  description="2-letter code e.g. 'us', 'gb'")
    flag:           Optional[str]  = None              # emoji flag e.g. "🇺🇸"
    ip_address:     Optional[str]  = None
    ping_ms:        Optional[int]  = None
    load_pct:       Optional[int]  = 0
    capacity_mbps:  Optional[int]  = 1000
    uptime_pct:     Optional[float] = 100.0
    status:         Optional[str]  = "online"          # online | maintenance | offline
    max_peers:      Optional[int]  = 500
    wg_port:        Optional[int]  = 51820
    wg_public_key:  Optional[str]  = None
    hetzner_server_id: Optional[str] = None
    protocols:      Optional[str]  = "wireguard,openvpn,ikev2"
    is_streaming:   Optional[bool] = False
    is_gaming:      Optional[bool] = False
    is_crypto:      Optional[bool] = False
    is_p2p:         Optional[bool] = False
    is_dedicated_ip: Optional[bool] = False


class UpdateServerBody(BaseModel):
    name:           Optional[str]   = None
    city:           Optional[str]   = None
    country:        Optional[str]   = None
    country_code:   Optional[str]   = None
    flag:           Optional[str]   = None
    ip_address:     Optional[str]   = None
    ping_ms:        Optional[int]   = None
    capacity_mbps:  Optional[int]   = None
    load_pct:       Optional[int]   = None
    uptime_pct:     Optional[float] = None
    max_peers:      Optional[int]   = None
    wg_port:        Optional[int]   = None
    wg_public_key:  Optional[str]   = None
    hetzner_server_id: Optional[str] = None
    protocols:      Optional[str]   = None
    is_streaming:   Optional[bool]  = None
    is_gaming:      Optional[bool]  = None
    is_crypto:      Optional[bool]  = None
    is_p2p:         Optional[bool]  = None
    is_dedicated_ip: Optional[bool] = None


class ChangeStatusBody(BaseModel):
    status: str = Field(..., pattern="^(online|maintenance|offline)$")


# ══════════════════════════════════════════════════════════════════
# ─── Helper ───────────────────────────────────────────────────────
# ══════════════════════════════════════════════════════════════════

def _server_to_admin_dict(server: VPNServer, db: Session) -> dict:
    """Full admin representation of a server including live session counts."""
    d = server.to_dict()
    d["wg_public_key"]     = server.wg_public_key
    d["hetzner_server_id"] = server.hetzner_server_id
    d["active_sessions"]   = db.query(VPNSession).filter_by(
        server_id=server.id, is_active=True
    ).count()
    d["total_sessions"]    = db.query(VPNSession).filter_by(
        server_id=server.id
    ).count()
    return d


def _sync_is_online(server: VPNServer):
    """Keep legacy is_online Boolean in sync with the new 3-state status."""
    server.is_online = server.status in ("online", "maintenance")


# ══════════════════════════════════════════════════════════════════
# ─── OVERVIEW — header KPI cards ──────────────────────────────────
# ══════════════════════════════════════════════════════════════════

@router.get("/servers/overview")
def servers_overview(
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """
    Returns the 4 KPI cards shown at the top of the Server Management page:
      • Total Servers
      • Online count
      • Average Load %
      • Total Capacity (formatted as Tbps / Gbps)

    Also returns per-status counts and per-region breakdown for the
    filter dropdowns and any summary widgets.
    """
    all_servers = db.query(VPNServer).all()

    total        = len(all_servers)
    online_count = sum(1 for s in all_servers if (s.status or "online") == "online")
    maint_count  = sum(1 for s in all_servers if (s.status or "") == "maintenance")
    offline_count = total - online_count - maint_count

    avg_load = 0.0
    if all_servers:
        loads    = [s.load_pct or 0 for s in all_servers]
        avg_load = round(sum(loads) / len(loads), 1)

    # Total capacity in Mbps → format nicely
    total_capacity_mbps = sum(s.capacity_mbps or 0 for s in all_servers)
    capacity_tbps = round(total_capacity_mbps / 1_000_000, 1)
    capacity_label = (
        f"{capacity_tbps} Tbps"
        if capacity_tbps >= 1
        else f"{round(total_capacity_mbps / 1000, 1)} Gbps"
    )

    # Countries / regions for the "All Regions" dropdown
    regions = sorted({s.country for s in all_servers if s.country})

    # Active VPN sessions across all servers
    total_active_sessions = db.query(VPNSession).filter_by(is_active=True).count()

    return success({
        "generated_at": datetime.utcnow().isoformat() + "Z",
        "kpis": {
            "total_servers":          total,
            "online":                 online_count,
            "maintenance":            maint_count,
            "offline":                offline_count,
            "avg_load_pct":           avg_load,
            "total_capacity_mbps":    total_capacity_mbps,
            "total_capacity_label":   capacity_label,
            "total_active_sessions":  total_active_sessions,
        },
        "subtitle": (
            f"{online_count} online · "
            f"{maint_count} maintenance · "
            f"{offline_count} offline · "
            f"{len(regions)} countries"
        ),
        "regions": regions,
    })


# ══════════════════════════════════════════════════════════════════
# ─── LIST — grid / table view ─────────────────────────────────────
# ══════════════════════════════════════════════════════════════════

@router.get("/servers")
def list_servers(
    search:      Optional[str]  = Query(None, description="Search by name, city, country, IP or ID"),
    status:      Optional[str]  = Query(None, description="online | maintenance | offline"),
    region:      Optional[str]  = Query(None, description="Country name e.g. 'United States'"),
    country_code: Optional[str] = Query(None, description="2-letter code e.g. 'us'"),
    online_only: bool           = Query(False),
    page:        int            = Query(1, ge=1),
    limit:       int            = Query(50, ge=1, le=200),
    _:           None           = Depends(admin_required),
    db:          Session        = Depends(get_db),
):
    """
    List all VPN servers with live session counts.
    Supports search, status filter, region filter, and pagination.

    Used by both the Grid view and the Table view on the Server Management page.
    """
    q = db.query(VPNServer)

    # Filter: status
    if status:
        q = q.filter(VPNServer.status == status)
    elif online_only:
        q = q.filter(VPNServer.is_online == True)

    # Filter: region / country
    if region:
        q = q.filter(VPNServer.country.ilike(f"%{region}%"))
    if country_code:
        q = q.filter(VPNServer.country_code.ilike(country_code))

    # Filter: free-text search
    if search:
        pattern = f"%{search}%"
        q = q.filter(
            VPNServer.name.ilike(pattern)       |
            VPNServer.city.ilike(pattern)       |
            VPNServer.country.ilike(pattern)    |
            VPNServer.ip_address.ilike(pattern) |
            VPNServer.id.ilike(pattern)
        )

    total   = q.count()
    servers = (
        q.order_by(VPNServer.country, VPNServer.city)
         .offset((page - 1) * limit)
         .limit(limit)
         .all()
    )

    return success({
        "servers": [_server_to_admin_dict(s, db) for s in servers],
        "total":   total,
        "page":    page,
        "limit":   limit,
        "pages":   (total + limit - 1) // limit,
        "counts": {
            "online":      db.query(VPNServer).filter_by(status="online").count(),
            "maintenance": db.query(VPNServer).filter_by(status="maintenance").count(),
            "offline":     db.query(VPNServer).filter_by(status="offline").count(),
        },
    })


# ══════════════════════════════════════════════════════════════════
# ─── ADD SERVER ───────────────────────────────────────────────────
# ══════════════════════════════════════════════════════════════════

@router.post("/servers")
def add_server(
    body: CreateServerBody,
    _:   None    = Depends(admin_required),
    db:  Session = Depends(get_db),
):
    """
    Add a new VPN server.
    `id` must be unique and human-readable (e.g. 'nyc-2', 'lon-3').
    Triggered by the '+ Add Server' button on the page.
    """
    existing = db.get(VPNServer, body.id)
    if existing:
        raise HTTPException(
            status_code=409,
            detail=f"Server with ID '{body.id}' already exists."
        )

    server = VPNServer(
        id               = body.id,
        name             = body.name,
        city             = body.city,
        country          = body.country,
        country_code     = body.country_code.lower(),
        flag             = body.flag,
        ip_address       = body.ip_address,
        ping_ms          = body.ping_ms,
        load_pct         = body.load_pct     or 0,
        capacity_mbps    = body.capacity_mbps or 1000,
        uptime_pct       = body.uptime_pct   if body.uptime_pct is not None else 100.0,
        status           = body.status       or "online",
        is_online        = body.status in ("online", "maintenance") if body.status else True,
        max_peers        = body.max_peers    or 500,
        wg_port          = body.wg_port      or 51820,
        wg_public_key    = body.wg_public_key,
        hetzner_server_id = body.hetzner_server_id,
        protocols        = body.protocols    or "wireguard,openvpn,ikev2",
        is_streaming     = body.is_streaming  or False,
        is_gaming        = body.is_gaming     or False,
        is_crypto        = body.is_crypto     or False,
        is_p2p           = body.is_p2p        or False,
        is_dedicated_ip  = body.is_dedicated_ip or False,
    )
    db.add(server)
    db.commit()
    db.refresh(server)
    return success(_server_to_admin_dict(server, db), "Server added successfully", 201)


# ══════════════════════════════════════════════════════════════════
# ─── DETAIL ───────────────────────────────────────────────────────
# ══════════════════════════════════════════════════════════════════

@router.get("/servers/{server_id}")
def get_server(
    server_id: str,
    _:         None    = Depends(admin_required),
    db:        Session = Depends(get_db),
):
    """
    Full detail of a single VPN server, including the 20 most recent
    active sessions. Used when admin clicks a server card to inspect it.
    """
    server = db.get(VPNServer, server_id)
    if not server:
        raise HTTPException(status_code=404, detail="Server not found")

    recent_sessions = (
        db.query(VPNSession)
        .filter_by(server_id=server.id, is_active=True)
        .order_by(VPNSession.started_at.desc())
        .limit(20)
        .all()
    )

    d = _server_to_admin_dict(server, db)
    d["recent_sessions"] = [s.to_dict() for s in recent_sessions]
    return success(d)


# ══════════════════════════════════════════════════════════════════
# ─── EDIT — ✏️ Edit button ────────────────────────────────────────
# ══════════════════════════════════════════════════════════════════

@router.patch("/servers/{server_id}")
def update_server(
    server_id: str,
    body:      UpdateServerBody,
    _:         None    = Depends(admin_required),
    db:        Session = Depends(get_db),
):
    """
    Update server properties. Send only the fields you want to change.
    Triggered by the '✏️ Edit' button on each server card.
    """
    server = db.get(VPNServer, server_id)
    if not server:
        raise HTTPException(status_code=404, detail="Server not found")

    editable = [
        "name", "city", "country", "country_code", "flag", "ip_address",
        "ping_ms", "capacity_mbps", "load_pct", "uptime_pct",
        "max_peers", "wg_port", "wg_public_key", "hetzner_server_id",
        "protocols", "is_streaming", "is_gaming", "is_crypto",
        "is_p2p", "is_dedicated_ip",
    ]
    for field in editable:
        val = getattr(body, field)
        if val is not None:
            setattr(server, field, val)

    db.commit()
    db.refresh(server)
    return success(_server_to_admin_dict(server, db), "Server updated successfully")


# ══════════════════════════════════════════════════════════════════
# ─── DELETE — 🗑️ Delete button ───────────────────────────────────
# ══════════════════════════════════════════════════════════════════

@router.delete("/servers/{server_id}")
def delete_server(
    server_id: str,
    _:         None    = Depends(admin_required),
    db:        Session = Depends(get_db),
):
    """
    Permanently delete a VPN server.
    ⚠️  This also cascades to ip_pool rows (see model).
    Sessions referencing this server are NOT deleted — they remain for audit.
    Triggered by the red 🗑️ icon on each server card.
    """
    server = db.get(VPNServer, server_id)
    if not server:
        raise HTTPException(status_code=404, detail="Server not found")

    # Warn if server still has active sessions
    active = db.query(VPNSession).filter_by(server_id=server_id, is_active=True).count()
    if active > 0:
        # Don't block deletion — just inform caller
        pass

    db.delete(server)
    db.commit()
    return success(
        {"id": server_id, "had_active_sessions": active},
        f"Server '{server_id}' deleted successfully"
    )


# ══════════════════════════════════════════════════════════════════
# ─── RESTART — ↺ Restart button ──────────────────────────────────
# ══════════════════════════════════════════════════════════════════

@router.post("/servers/{server_id}/restart")
def restart_server(
    server_id: str,
    _:         None    = Depends(admin_required),
    db:        Session = Depends(get_db),
):
    """
    Marks a restart event for the server.

    In production this would trigger an SSH command or Hetzner API call
    to reboot the cloud instance. Right now it:
      1. Momentarily sets status → 'maintenance'
      2. Clears all active sessions (they'll reconnect after reboot)
      3. Resets load_pct to 0 (clean slate after restart)

    Triggered by the '↺ Restart' button on each server card.
    """
    server = db.get(VPNServer, server_id)
    if not server:
        raise HTTPException(status_code=404, detail="Server not found")

    if server.status == "offline":
        raise HTTPException(
            status_code=409,
            detail="Server is offline. Bring it online first before restarting."
        )

    # Clear active sessions — users will reconnect after the reboot
    active_sessions = (
        db.query(VPNSession)
        .filter_by(server_id=server_id, is_active=True)
        .all()
    )
    now = datetime.utcnow()
    for sess in active_sessions:
        sess.is_active = False
        sess.ended_at  = now

    # Set temporary maintenance state & reset load
    server.status    = "maintenance"
    server.is_online = True      # server is still reachable (rebooting)
    server.load_pct  = 0
    server.current_peers = 0

    db.commit()
    db.refresh(server)

    return success(
        {
            "server_id":              server_id,
            "status":                 server.status,
            "sessions_terminated":    len(active_sessions),
            "restarted_at":           now.isoformat() + "Z",
        },
        f"Server '{server.name}' restart initiated — {len(active_sessions)} sessions terminated"
    )


# ══════════════════════════════════════════════════════════════════
# ─── STATUS CHANGE ────────────────────────────────────────────────
# ══════════════════════════════════════════════════════════════════

@router.patch("/servers/{server_id}/status")
def change_server_status(
    server_id: str,
    body:      ChangeStatusBody,
    _:         None    = Depends(admin_required),
    db:        Session = Depends(get_db),
):
    """
    Change server status explicitly:
      online      → accepting new VPN connections
      maintenance → server is up but no new connections allowed
      offline     → server unreachable

    This is separate from ↺ Restart so admins can set planned
    maintenance windows without triggering a reboot.
    """
    server = db.get(VPNServer, server_id)
    if not server:
        raise HTTPException(status_code=404, detail="Server not found")

    old_status   = server.status
    server.status = body.status
    _sync_is_online(server)

    db.commit()
    db.refresh(server)
    return success(
        {
            "server_id":  server_id,
            "old_status": old_status,
            "new_status": server.status,
            "is_online":  server.is_online,
        },
        f"Server '{server.name}' status changed: {old_status} → {server.status}"
    )
