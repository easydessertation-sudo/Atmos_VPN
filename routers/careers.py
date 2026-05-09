"""
Careers Router — Job Listings & Applicants Management
======================================================
GET    /api/admin/careers/jobs                      → list all jobs
POST   /api/admin/careers/jobs                      → post a new job
GET    /api/admin/careers/jobs/{id}                 → get single job detail
PATCH  /api/admin/careers/jobs/{id}                 → edit job (position, dept, type)
PATCH  /api/admin/careers/jobs/{id}/status          → open / close a job
DELETE /api/admin/careers/jobs/{id}                 → delete a job listing

GET    /api/admin/careers/jobs/{id}/applicants      → list applicants for a job
POST   /api/admin/careers/jobs/{id}/applicants      → add an applicant (or seed)
PATCH  /api/admin/careers/applicants/{id}           → update applicant status
DELETE /api/admin/careers/applicants/{id}           → remove an applicant
"""
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import Optional

from deps import admin_required, get_db, success
from models import JobListing, JobApplicant

router = APIRouter()

VALID_JOB_STATUSES       = ["Open", "closed"]
VALID_APPLICANT_STATUSES = ["new", "reviewing", "interview", "offer", "rejected"]


# ══════════════════════════════════════════════════════════════════
# Pydantic Schemas
# ══════════════════════════════════════════════════════════════════
class JobListingCreate(BaseModel):
    position:   str
    department: str
    job_type:   str = "Full-time"   # Full-time | Part-time | Contract | Remote
    status:     str = "Open"
    description: Optional[str] = None
    location:   Optional[str] = None

class JobListingUpdate(BaseModel):
    position:    Optional[str] = None
    department:  Optional[str] = None
    job_type:    Optional[str] = None
    description: Optional[str] = None
    location:    Optional[str] = None

class JobStatusUpdate(BaseModel):
    status: str  # "Open" | "closed"

class ApplicantCreate(BaseModel):
    name:       str
    email:      str
    phone:      Optional[str] = None
    resume_url: Optional[str] = None
    cover_note: Optional[str] = None
    status:     Optional[str] = "new"

class ApplicantStatusUpdate(BaseModel):
    status: str  # new | reviewing | interview | offer | rejected


# ══════════════════════════════════════════════════════════════════
# ─── JOB LISTINGS ────────────────────────────────────────────────
# ══════════════════════════════════════════════════════════════════

@router.get("/jobs")
def get_job_listings(
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """
    List all job listings for the Careers table.
    Returns applicant_count dynamically from the job_applicants table.
    """
    jobs = db.query(JobListing).order_by(JobListing.created_at.desc()).all()
    result = []
    for j in jobs:
        d = j.to_dict()
        # Always return live count from the real applicants table
        d["applicants_count"] = db.query(JobApplicant).filter_by(job_id=str(j.id)).count()
        result.append(d)
    return success(result)


@router.get("/jobs/{job_id}")
def get_job_detail(
    job_id: str,
    _:      None    = Depends(admin_required),
    db:     Session = Depends(get_db),
):
    """Get a single job listing with full details (for the edit modal)."""
    job = db.get(JobListing, job_id)
    if not job:
        raise HTTPException(status_code=404, detail="Job listing not found")
    d = job.to_dict()
    d["applicants_count"] = db.query(JobApplicant).filter_by(job_id=str(job.id)).count()
    return success(d)


@router.post("/jobs")
def create_job_listing(
    payload: JobListingCreate,
    _:       None    = Depends(admin_required),
    db:      Session = Depends(get_db),
):
    """Create a new job listing (the '+ Post Job' button)."""
    if payload.status not in VALID_JOB_STATUSES:
        raise HTTPException(400, f"status must be one of {VALID_JOB_STATUSES}")

    job = JobListing(
        position   = payload.position,
        department = payload.department,
        job_type   = payload.job_type,
        status     = payload.status,
    )
    db.add(job)
    db.commit()
    db.refresh(job)
    d = job.to_dict()
    d["applicants_count"] = 0
    return success(d, f"Job '{payload.position}' posted successfully", 201)


@router.patch("/jobs/{job_id}")
def update_job_listing(
    job_id:  str,
    payload: JobListingUpdate,
    _:       None    = Depends(admin_required),
    db:      Session = Depends(get_db),
):
    """Edit job listing details (position, department, type) — the pencil ✏️ button."""
    job = db.get(JobListing, job_id)
    if not job:
        raise HTTPException(status_code=404, detail="Job listing not found")

    updates = payload.model_dump(exclude_none=True)
    if not updates:
        raise HTTPException(400, "No fields provided to update")

    for field, value in updates.items():
        setattr(job, field, value)

    db.commit()
    db.refresh(job)
    d = job.to_dict()
    d["applicants_count"] = db.query(JobApplicant).filter_by(job_id=str(job.id)).count()
    return success(d, "Job updated successfully")


@router.patch("/jobs/{job_id}/status")
def update_job_status(
    job_id:  str,
    payload: JobStatusUpdate,
    _:       None    = Depends(admin_required),
    db:      Session = Depends(get_db),
):
    """Toggle job status: Open ↔ closed (Close / Reopen button)."""
    job = db.get(JobListing, job_id)
    if not job:
        raise HTTPException(status_code=404, detail="Job listing not found")

    if payload.status not in VALID_JOB_STATUSES:
        raise HTTPException(400, f"status must be one of {VALID_JOB_STATUSES}")

    job.status = payload.status
    db.commit()
    db.refresh(job)
    return success(job.to_dict(), f"Job '{job.position}' is now {payload.status}")


@router.delete("/jobs/{job_id}")
def delete_job_listing(
    job_id: str,
    _:      None    = Depends(admin_required),
    db:     Session = Depends(get_db),
):
    """Permanently delete a job listing (and all its applicants via CASCADE)."""
    job = db.get(JobListing, job_id)
    if not job:
        raise HTTPException(status_code=404, detail="Job listing not found")
    title = job.position
    db.delete(job)
    db.commit()
    return success({"id": job_id}, f"Job '{title}' deleted")


# ══════════════════════════════════════════════════════════════════
# ─── APPLICANTS ──────────────────────────────────────────────────
# ══════════════════════════════════════════════════════════════════

@router.get("/jobs/{job_id}/applicants")
def get_applicants(
    job_id:      str,
    status:      Optional[str] = None,
    search:      Optional[str] = None,
    page:        int = 1,
    limit:       int = 20,
    _:           None    = Depends(admin_required),
    db:          Session = Depends(get_db),
):
    """
    Get all applicants for a job listing (the 'Applicants' button).
    Supports filtering by status and searching by name/email.
    """
    job = db.get(JobListing, job_id)
    if not job:
        raise HTTPException(status_code=404, detail="Job listing not found")

    q = db.query(JobApplicant).filter(JobApplicant.job_id == job_id)

    if status:
        q = q.filter_by(status=status)
    if search:
        q = q.filter(
            JobApplicant.name.ilike(f"%{search}%") |
            JobApplicant.email.ilike(f"%{search}%")
        )

    total      = q.count()
    applicants = q.order_by(JobApplicant.applied_at.desc()).offset((page - 1) * limit).limit(limit).all()

    # Status summary counts
    counts = {s: db.query(JobApplicant).filter_by(job_id=job_id, status=s).count()
              for s in VALID_APPLICANT_STATUSES}

    return success({
        "job": {
            "id":         str(job.id),
            "position":   job.position,
            "department": job.department,
            "status":     job.status,
        },
        "applicants":  [a.to_dict() for a in applicants],
        "total":        total,
        "page":         page,
        "limit":        limit,
        "pages":        (total + limit - 1) // limit,
        "status_counts": counts,
    })


@router.post("/jobs/{job_id}/applicants")
def add_applicant(
    job_id:  str,
    payload: ApplicantCreate,
    _:       None    = Depends(admin_required),
    db:      Session = Depends(get_db),
):
    """
    Add an applicant to a job (admin manual add, or triggered by public apply form).
    Also increments the job's applicants_count.
    """
    job = db.get(JobListing, job_id)
    if not job:
        raise HTTPException(status_code=404, detail="Job listing not found")
    if job.status == "closed":
        raise HTTPException(400, "Cannot add applicant to a closed job")
    if payload.status not in VALID_APPLICANT_STATUSES:
        raise HTTPException(400, f"status must be one of {VALID_APPLICANT_STATUSES}")

    applicant = JobApplicant(
        job_id     = job_id,
        name       = payload.name,
        email      = payload.email,
        phone      = payload.phone,
        resume_url = payload.resume_url,
        cover_note = payload.cover_note,
        status     = payload.status or "new",
        applied_at = datetime.utcnow(),
        updated_at = datetime.utcnow(),
    )
    db.add(applicant)

    # Sync the count on the parent row
    job.applicants_count = (job.applicants_count or 0) + 1

    db.commit()
    db.refresh(applicant)
    return success(applicant.to_dict(), f"Applicant '{payload.name}' added", 201)


@router.patch("/applicants/{applicant_id}")
def update_applicant_status(
    applicant_id: str,
    payload:      ApplicantStatusUpdate,
    _:            None    = Depends(admin_required),
    db:           Session = Depends(get_db),
):
    """
    Move an applicant through the hiring pipeline:
    new → reviewing → interview → offer / rejected
    """
    applicant = db.get(JobApplicant, applicant_id)
    if not applicant:
        raise HTTPException(status_code=404, detail="Applicant not found")
    if payload.status not in VALID_APPLICANT_STATUSES:
        raise HTTPException(400, f"status must be one of {VALID_APPLICANT_STATUSES}")

    applicant.status     = payload.status
    applicant.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(applicant)
    return success(applicant.to_dict(), f"Applicant moved to '{payload.status}'")


@router.delete("/applicants/{applicant_id}")
def delete_applicant(
    applicant_id: str,
    _:            None    = Depends(admin_required),
    db:           Session = Depends(get_db),
):
    """Remove an applicant record and decrement the job's count."""
    applicant = db.get(JobApplicant, applicant_id)
    if not applicant:
        raise HTTPException(status_code=404, detail="Applicant not found")

    job = db.get(JobListing, str(applicant.job_id))
    db.delete(applicant)
    if job and job.applicants_count and job.applicants_count > 0:
        job.applicants_count -= 1
    db.commit()
    return success({"id": applicant_id}, "Applicant removed")
