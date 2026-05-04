from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import Optional

from deps import admin_required, get_db, success
from models import ServiceHealth, SystemIncident

router = APIRouter()

class IncidentCreate(BaseModel):
    title: str
    affected_services: str
    severity: str
    public_status_update: str

class IncidentUpdate(BaseModel):
    status: Optional[str] = None
    public_status_update: Optional[str] = None

class ServiceUpdate(BaseModel):
    status: str

@router.get("/overview")
def get_system_status_overview(
    _: None = Depends(admin_required),
    db: Session = Depends(get_db)
):
    """
    Get everything needed for the System Status page:
    - Active incident (if any)
    - Service health statuses
    - Recent incidents list
    """
    # 1. Get active incident
    active_incident = db.query(SystemIncident).filter(
        SystemIncident.status != "resolved"
    ).order_by(SystemIncident.created_at.desc()).first()

    # 2. Get services
    services = db.query(ServiceHealth).order_by(ServiceHealth.service_name.asc()).all()
    # Seed default services if the table is empty
    if not services:
        default_services = [
            "VPN Core (WireGuard)", "API Gateway", "User Portal",
            "Billing System", "DNS Servers", "Auth Service",
            "Amsterdam Cluster", "Zurich Server", "CDN / Web",
            "Monitoring & Alerts"
        ]
        for name in default_services:
            svc = ServiceHealth(service_name=name, status="online")
            db.add(svc)
        db.commit()
        services = db.query(ServiceHealth).order_by(ServiceHealth.service_name.asc()).all()

    # 3. Get incidents (latest 20)
    incidents = db.query(SystemIncident).order_by(SystemIncident.created_at.desc()).limit(20).all()

    return success({
        "active_incident": active_incident.to_dict() if active_incident else None,
        "services": [s.to_dict() for s in services],
        "incidents": [i.to_dict() for i in incidents]
    })

@router.post("/incidents")
def create_incident(
    payload: IncidentCreate,
    _: None = Depends(admin_required),
    db: Session = Depends(get_db)
):
    """Create a new incident (e.g. from the Post New Incident modal)"""
    # Generate sequential incident number e.g. INC-201
    last_incident = db.query(SystemIncident).order_by(SystemIncident.created_at.desc()).first()
    next_num = 1
    if last_incident and last_incident.incident_number and last_incident.incident_number.startswith("INC-"):
        try:
            next_num = int(last_incident.incident_number.split("-")[1]) + 1
        except ValueError:
            pass
    incident_number = f"INC-{next_num:03d}"

    incident = SystemIncident(
        incident_number=incident_number,
        title=payload.title,
        affected_services=payload.affected_services,
        severity=payload.severity,
        public_status_update=payload.public_status_update,
        status="investigating"
    )
    db.add(incident)
    db.commit()
    db.refresh(incident)
    return success(incident.to_dict())

@router.patch("/incidents/{incident_id}")
def update_incident(
    incident_id: str,
    payload: IncidentUpdate,
    _: None = Depends(admin_required),
    db: Session = Depends(get_db)
):
    """Update an incident (e.g. mark as resolved, or update the message)"""
    incident = db.query(SystemIncident).filter(SystemIncident.id == incident_id).first()
    if not incident:
        raise HTTPException(status_code=404, detail="Incident not found")

    if payload.status:
        incident.status = payload.status
        if payload.status == "resolved":
            incident.resolved_at = datetime.utcnow()
    
    if payload.public_status_update is not None:
        incident.public_status_update = payload.public_status_update

    db.commit()
    db.refresh(incident)
    return success(incident.to_dict())

@router.patch("/services/{service_id}")
def update_service_status(
    service_id: str,
    payload: ServiceUpdate,
    _: None = Depends(admin_required),
    db: Session = Depends(get_db)
):
    """Update the status of an individual service (online, maint, offline)"""
    service = db.query(ServiceHealth).filter(ServiceHealth.id == service_id).first()
    if not service:
        raise HTTPException(status_code=404, detail="Service not found")
    
    service.status = payload.status
    service.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(service)
    return success(service.to_dict())
