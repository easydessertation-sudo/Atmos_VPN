from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import Optional

from deps import admin_required, get_db, success
from models import PressCoverage, BrandAsset

router = APIRouter()

class PressCoverageCreate(BaseModel):
    publication: str
    headline: str
    url: str
    published_at: datetime

class BrandAssetUpdate(BaseModel):
    file_url: str

@router.get("/overview")
def get_press_overview(
    _: None = Depends(admin_required),
    db: Session = Depends(get_db)
):
    """
    Get everything needed for the Press & Media page.
    """
    
    coverage = db.query(PressCoverage).order_by(PressCoverage.published_at.desc()).all()
    assets = db.query(BrandAsset).order_by(BrandAsset.created_at.asc()).all()

    # Seed data if empty
    if not coverage and not assets:
        seed_coverage = [
            PressCoverage(publication="WIRED", headline="The Best VPNs for 2025: AtmosVPN Tops Our Ranking", url="https://wired.com", published_at=datetime.strptime("2025-10-15", "%Y-%m-%d")),
            PressCoverage(publication="FORBES", headline="Privacy Startup AtmosVPN Surpasses 2 Million Users", url="https://forbes.com", published_at=datetime.strptime("2025-08-05", "%Y-%m-%d")),
            PressCoverage(publication="TECHRADAR", headline="AtmosVPN Review: The Fastest VPN We've Tested", url="https://techradar.com", published_at=datetime.strptime("2025-06-20", "%Y-%m-%d")),
            PressCoverage(publication="THE VERGE", headline="AtmosVPN Offers the Best Value for Privacy-Focused Users", url="https://theverge.com", published_at=datetime.strptime("2025-03-10", "%Y-%m-%d")),
        ]
        seed_assets = [
            BrandAsset(name="AtmosVPN Logo (SVG)", file_url="/assets/logo.svg"),
            BrandAsset(name="AtmosVPN Logo (PNG)", file_url="/assets/logo.png"),
            BrandAsset(name="Brand Guidelines PDF", file_url="/assets/guidelines.pdf"),
            BrandAsset(name="Press Photos Pack", file_url="/assets/photos.zip"),
            BrandAsset(name="Product Screenshots", file_url="/assets/screenshots.zip"),
            BrandAsset(name="CEO Headshot", file_url="/assets/ceo.jpg"),
        ]
        for c in seed_coverage:
            db.add(c)
        for a in seed_assets:
            db.add(a)
        db.commit()
        
        coverage = db.query(PressCoverage).order_by(PressCoverage.published_at.desc()).all()
        assets = db.query(BrandAsset).order_by(BrandAsset.created_at.asc()).all()

    return success({
        "coverage": [c.to_dict() for c in coverage],
        "assets": [a.to_dict() for a in assets]
    })

@router.post("/coverage")
def create_press_coverage(
    payload: PressCoverageCreate,
    _: None = Depends(admin_required),
    db: Session = Depends(get_db)
):
    """Add a new press coverage link."""
    coverage = PressCoverage(
        publication=payload.publication,
        headline=payload.headline,
        url=payload.url,
        published_at=payload.published_at
    )
    db.add(coverage)
    db.commit()
    db.refresh(coverage)
    return success(coverage.to_dict())

@router.delete("/coverage/{coverage_id}")
def delete_press_coverage(
    coverage_id: str,
    _: None = Depends(admin_required),
    db: Session = Depends(get_db)
):
    """Delete a press coverage item."""
    coverage = db.query(PressCoverage).filter(PressCoverage.id == coverage_id).first()
    if not coverage:
        raise HTTPException(status_code=404, detail="Coverage not found")
    
    db.delete(coverage)
    db.commit()
    return success({"message": "Coverage deleted successfully"})

@router.put("/assets/{asset_id}")
def replace_brand_asset(
    asset_id: str,
    payload: BrandAssetUpdate,
    _: None = Depends(admin_required),
    db: Session = Depends(get_db)
):
    """Update/replace a brand asset file url."""
    asset = db.query(BrandAsset).filter(BrandAsset.id == asset_id).first()
    if not asset:
        raise HTTPException(status_code=404, detail="Brand asset not found")
    
    asset.file_url = payload.file_url
    db.commit()
    db.refresh(asset)
    return success(asset.to_dict(), "Brand asset updated successfully")
