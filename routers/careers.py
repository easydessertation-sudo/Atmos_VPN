from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import Optional

from deps import admin_required, get_db, success
from models import JobListing

router = APIRouter()

class JobListingCreate(BaseModel):
    position: str
    department: str
    job_type: str = "Full-time"
    status: str = "Open"

class JobListingUpdateStatus(BaseModel):
    status: str

@router.get("/jobs")
def get_job_listings(
    _: None = Depends(admin_required),
    db: Session = Depends(get_db)
):
    """
    Get everything needed for the Careers > Job listings table.
    """
    
    jobs = db.query(JobListing).order_by(JobListing.created_at.asc()).all()
    return success(
        [j.to_dict() for j in jobs]
    )

@router.post("/jobs")
def create_job_listing(
    payload: JobListingCreate,
    _: None = Depends(admin_required),
    db: Session = Depends(get_db)
):
    """Create a new job listing."""
    job = JobListing(
        position=payload.position,
        department=payload.department,
        job_type=payload.job_type,
        status=payload.status,
    )
    db.add(job)
    db.commit()
    db.refresh(job)
    return success(job.to_dict())

@router.patch("/jobs/{job_id}/status")
def update_job_status(
    job_id: str,
    payload: JobListingUpdateStatus,
    _: None = Depends(admin_required),
    db: Session = Depends(get_db)
):
    """Update job listing status (Open/closed)."""
    job = db.query(JobListing).filter(JobListing.id == job_id).first()
    if not job:
        raise HTTPException(status_code=404, detail="Job listing not found")
    
    if payload.status not in ["Open", "closed"]:
        raise HTTPException(status_code=400, detail="Invalid status. Must be 'Open' or 'closed'.")

    job.status = payload.status
    db.commit()
    db.refresh(job)
    return success(job.to_dict(), "Job status updated successfully")
