"""
Blog Management Router  —  /api/admin/blog/*

┌─────────────────────────────────────────────────────────────────┐
│  POSTS TAB                                                      │
│  GET    /api/admin/blog/posts            → list (filter/search) │
│  POST   /api/admin/blog/posts            → create post          │
│  GET    /api/admin/blog/posts/{id}       → single post detail   │
│  PATCH  /api/admin/blog/posts/{id}       → edit post            │
│  DELETE /api/admin/blog/posts/{id}       → delete post          │
│  POST   /api/admin/blog/posts/{id}/publish   → publish draft    │
│  POST   /api/admin/blog/posts/{id}/unpublish → revert to draft  │
│                                                                 │
│  SEO SETTINGS TAB                                               │
│  GET    /api/admin/blog/seo              → get global SEO data  │
│  PATCH  /api/admin/blog/seo              → save SEO settings    │
│                                                                 │
│  MEDIA LIBRARY TAB                                              │
│  GET    /api/admin/blog/media            → list media files     │
│  POST   /api/admin/blog/media            → add media record     │
│  PATCH  /api/admin/blog/media/{id}       → update alt text etc  │
│  DELETE /api/admin/blog/media/{id}       → delete media record  │
└─────────────────────────────────────────────────────────────────┘
"""
from datetime import datetime
from typing import Optional
import re

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy.orm import Session

from deps import admin_required, get_db, success
from models import BlogPost, SeoSetting, MediaFile

router = APIRouter()


# ══════════════════════════════════════════════════════════════════
# ─── Helpers ──────────────────────────────────────────────────────
# ══════════════════════════════════════════════════════════════════

def _slugify(text: str) -> str:
    """Convert title to URL-safe slug: 'Hello World' → 'hello-world'"""
    text = text.lower().strip()
    text = re.sub(r"[^\w\s-]", "", text)
    text = re.sub(r"[\s_]+", "-", text)
    return text


def _ensure_seo_row(db: Session) -> SeoSetting:
    """Ensure the global SEO row exists; seed defaults if not."""
    row = db.get(SeoSetting, "global")
    if not row:
        row = SeoSetting(key="global")
        db.add(row)
        db.commit()
        db.refresh(row)
    return row


# ══════════════════════════════════════════════════════════════════
# ─── POSTS TAB ────────────────────────────────────────────────────
# ══════════════════════════════════════════════════════════════════

class CreatePostBody(BaseModel):
    title:           str
    author:          str
    category:        str
    content:         Optional[str]  = ""
    excerpt:         Optional[str]  = None
    tags:            Optional[str]  = None   # comma-separated: "vpn,privacy,security"
    featured_image:  Optional[str]  = None
    read_time_min:   Optional[int]  = 3
    status:          Optional[str]  = "draft"   # draft | published | archived
    # Per-post SEO
    meta_title:       Optional[str]  = None
    meta_description: Optional[str]  = None
    og_image:         Optional[str]  = None
    canonical_url:    Optional[str]  = None
    robots:           Optional[str]  = "index, follow"


class UpdatePostBody(BaseModel):
    title:            Optional[str]  = None
    author:           Optional[str]  = None
    category:         Optional[str]  = None
    content:          Optional[str]  = None
    excerpt:          Optional[str]  = None
    tags:             Optional[str]  = None
    featured_image:   Optional[str]  = None
    read_time_min:    Optional[int]  = None
    status:           Optional[str]  = None
    meta_title:       Optional[str]  = None
    meta_description: Optional[str]  = None
    og_image:         Optional[str]  = None
    canonical_url:    Optional[str]  = None
    robots:           Optional[str]  = None


# ─── 1. List Posts ────────────────────────────────────────────────
@router.get("/posts")
def list_posts(
    status:   Optional[str] = Query(None, description="draft | published | archived"),
    category: Optional[str] = Query(None),
    search:   Optional[str] = Query(None),
    page:     int = Query(1, ge=1),
    limit:    int = Query(20, ge=1, le=100),
    _:        None    = Depends(admin_required),
    db:       Session = Depends(get_db),
):
    """
    Posts tab — paginated list with filters.
    Also returns KPI summary counts and category list for filter dropdowns.
    """
    q = db.query(BlogPost)
    if status:
        q = q.filter(BlogPost.status == status)
    if category:
        q = q.filter(BlogPost.category.ilike(f"%{category}%"))
    if search:
        q = q.filter(BlogPost.title.ilike(f"%{search}%") | BlogPost.author.ilike(f"%{search}%"))

    total = q.count()
    posts = q.order_by(BlogPost.created_at.desc()).offset((page - 1) * limit).limit(limit).all()

    # Category list for dropdown
    all_cats = [r[0] for r in db.query(BlogPost.category).distinct().all() if r[0]]

    return success({
        "posts": [p.to_dict() for p in posts],
        "total": total,
        "page":  page,
        "limit": limit,
        "pages": (total + limit - 1) // limit,
        "counts": {
            "all":       db.query(BlogPost).count(),
            "published": db.query(BlogPost).filter_by(status="published").count(),
            "draft":     db.query(BlogPost).filter_by(status="draft").count(),
            "archived":  db.query(BlogPost).filter_by(status="archived").count(),
        },
        "categories": sorted(all_cats),
    })


# ─── 2. Create Post (+ New Post button) ──────────────────────────
@router.post("/posts")
def create_post(
    body: CreatePostBody,
    _:   None    = Depends(admin_required),
    db:  Session = Depends(get_db),
):
    """
    Create a new blog post.
    - status='draft'     → saved, not live
    - status='published' → live immediately, sets published_at = now
    - slug is auto-generated from title if not provided
    """
    # Auto-generate unique slug
    base_slug = _slugify(body.title)
    slug = base_slug
    counter = 1
    while db.query(BlogPost).filter_by(slug=slug).first():
        slug = f"{base_slug}-{counter}"
        counter += 1

    post = BlogPost(
        title            = body.title,
        slug             = slug,
        author           = body.author,
        category         = body.category,
        content          = body.content or "",
        excerpt          = body.excerpt,
        tags             = body.tags,
        featured_image   = body.featured_image,
        read_time_min    = body.read_time_min or 3,
        status           = body.status or "draft",
        meta_title       = body.meta_title,
        meta_description = body.meta_description,
        og_image         = body.og_image,
        canonical_url    = body.canonical_url,
        robots           = body.robots or "index, follow",
        published_at     = datetime.utcnow() if body.status == "published" else None,
    )
    db.add(post)
    db.commit()
    db.refresh(post)
    return success(post.to_dict(), "Post created successfully", 201)


# ─── 3. Get Single Post (pre-fill Edit form) ─────────────────────
@router.get("/posts/{post_id}")
def get_post(
    post_id: str,
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """Get full detail of one post. Call this when admin clicks Edit."""
    post = db.query(BlogPost).filter(BlogPost.id == post_id).first()
    if not post:
        raise HTTPException(status_code=404, detail="Post not found")
    return success(post.to_dict())


# ─── 4. Edit Post (✏️ Edit button → Save) ────────────────────────
@router.patch("/posts/{post_id}")
def update_post(
    post_id: str,
    body:    UpdatePostBody,
    _:       None    = Depends(admin_required),
    db:      Session = Depends(get_db),
):
    """
    Edit a blog post. Send only fields to change.
    If status changes to 'published' and published_at was null → sets published_at = now.
    """
    post = db.query(BlogPost).filter(BlogPost.id == post_id).first()
    if not post:
        raise HTTPException(status_code=404, detail="Post not found")

    if body.title           is not None:
        post.title = body.title
        # Re-generate slug when title changes (keep old one if conflict)
        new_slug = _slugify(body.title)
        if not db.query(BlogPost).filter(BlogPost.slug == new_slug, BlogPost.id != post_id).first():
            post.slug = new_slug

    if body.author           is not None: post.author           = body.author
    if body.category         is not None: post.category         = body.category
    if body.content          is not None: post.content          = body.content
    if body.excerpt          is not None: post.excerpt          = body.excerpt
    if body.tags             is not None: post.tags             = body.tags
    if body.featured_image   is not None: post.featured_image   = body.featured_image
    if body.read_time_min    is not None: post.read_time_min    = body.read_time_min
    if body.meta_title       is not None: post.meta_title       = body.meta_title
    if body.meta_description is not None: post.meta_description = body.meta_description
    if body.og_image         is not None: post.og_image         = body.og_image
    if body.canonical_url    is not None: post.canonical_url    = body.canonical_url
    if body.robots           is not None: post.robots           = body.robots

    # Handle status change
    if body.status is not None and body.status != post.status:
        post.status = body.status
        if body.status == "published" and not post.published_at:
            post.published_at = datetime.utcnow()
        elif body.status in ("draft", "archived"):
            post.published_at = None

    post.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(post)
    return success(post.to_dict(), "Post updated successfully")


# ─── 5. Publish Post ─────────────────────────────────────────────
@router.post("/posts/{post_id}/publish")
def publish_post(
    post_id: str,
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """Publish a draft post. Sets status=published, published_at=now."""
    post = db.query(BlogPost).filter(BlogPost.id == post_id).first()
    if not post:
        raise HTTPException(status_code=404, detail="Post not found")
    if post.status == "published":
        raise HTTPException(status_code=409, detail="Post is already published")
    post.status       = "published"
    post.published_at = datetime.utcnow()
    post.updated_at   = datetime.utcnow()
    db.commit()
    db.refresh(post)
    return success(post.to_dict(), f"Post '{post.title}' published")


# ─── 6. Unpublish Post (back to Draft) ───────────────────────────
@router.post("/posts/{post_id}/unpublish")
def unpublish_post(
    post_id: str,
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """Revert a published post to draft."""
    post = db.query(BlogPost).filter(BlogPost.id == post_id).first()
    if not post:
        raise HTTPException(status_code=404, detail="Post not found")
    post.status       = "draft"
    post.published_at = None
    post.updated_at   = datetime.utcnow()
    db.commit()
    db.refresh(post)
    return success(post.to_dict(), f"Post reverted to draft")


# ─── 7. Delete Post ───────────────────────────────────────────────
@router.delete("/posts/{post_id}")
def delete_post(
    post_id: str,
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """Permanently delete a blog post."""
    post = db.query(BlogPost).filter(BlogPost.id == post_id).first()
    if not post:
        raise HTTPException(status_code=404, detail="Post not found")
    title = post.title
    db.delete(post)
    db.commit()
    return success({"id": post_id}, f"Post '{title}' deleted")


# ══════════════════════════════════════════════════════════════════
# ─── SEO SETTINGS TAB ─────────────────────────────────────────────
# ══════════════════════════════════════════════════════════════════

class SeoSettingsBody(BaseModel):
    meta_title:            Optional[str] = None
    meta_description:      Optional[str] = None
    og_image_url:          Optional[str] = None
    canonical_url:         Optional[str] = None
    robots:                Optional[str] = None
    og_site_name:          Optional[str] = None
    og_type:               Optional[str] = None
    twitter_card:          Optional[str] = None
    twitter_site:          Optional[str] = None
    google_analytics_id:   Optional[str] = None
    google_search_console: Optional[str] = None


# ─── 8. Get Global SEO Settings ──────────────────────────────────
@router.get("/seo")
def get_seo_settings(
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """
    SEO Settings tab — load current global SEO metadata.
    Auto-seeds defaults on first call.
    """
    row = _ensure_seo_row(db)
    return success(row.to_dict())


# ─── 9. Save SEO Settings (Save SEO button) ──────────────────────
@router.patch("/seo")
def save_seo_settings(
    body: SeoSettingsBody,
    _:   None    = Depends(admin_required),
    db:  Session = Depends(get_db),
):
    """
    Save global SEO metadata.
    Send only the fields you want to update (partial update).
    Triggered by the '✓ Save SEO' button.
    """
    row = _ensure_seo_row(db)

    fields = [
        "meta_title", "meta_description", "og_image_url", "canonical_url",
        "robots", "og_site_name", "og_type", "twitter_card", "twitter_site",
        "google_analytics_id", "google_search_console",
    ]
    updated = []
    for f in fields:
        val = getattr(body, f, None)
        if val is not None:
            setattr(row, f, val)
            updated.append(f)

    row.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(row)
    return success(row.to_dict(), f"SEO settings saved: {', '.join(updated) if updated else 'no changes'}")


# ══════════════════════════════════════════════════════════════════
# ─── MEDIA LIBRARY TAB ────────────────────────────────────────────
# ══════════════════════════════════════════════════════════════════

class AddMediaBody(BaseModel):
    name:        str
    url:         str
    file_type:   str              # image | video | document
    mime_type:   Optional[str] = None
    size_bytes:  Optional[int] = 0
    width:       Optional[int] = None
    height:      Optional[int] = None
    alt_text:    Optional[str] = None
    folder:      Optional[str] = "/"
    uploaded_by: Optional[str] = None


class UpdateMediaBody(BaseModel):
    alt_text: Optional[str] = None
    name:     Optional[str] = None
    folder:   Optional[str] = None


# ─── 10. List Media Files ─────────────────────────────────────────
@router.get("/media")
def list_media(
    file_type: Optional[str] = Query(None, description="image | video | document"),
    folder:    Optional[str] = Query(None),
    search:    Optional[str] = Query(None),
    page:      int = Query(1, ge=1),
    limit:     int = Query(30, ge=1, le=100),
    _:         None    = Depends(admin_required),
    db:        Session = Depends(get_db),
):
    """
    Media Library tab — paginated list of uploaded files.
    Filterable by file type (image / video / document) and folder.
    """
    q = db.query(MediaFile)
    if file_type:
        q = q.filter(MediaFile.file_type == file_type)
    if folder:
        q = q.filter(MediaFile.folder == folder)
    if search:
        q = q.filter(MediaFile.name.ilike(f"%{search}%"))

    total = q.count()
    files = q.order_by(MediaFile.created_at.desc()).offset((page - 1) * limit).limit(limit).all()

    # Total storage used
    total_bytes = sum(f.size_bytes or 0 for f in db.query(MediaFile).all())
    if total_bytes >= 1_073_741_824:
        storage_label = f"{total_bytes / 1_073_741_824:.1f} GB"
    elif total_bytes >= 1_048_576:
        storage_label = f"{total_bytes / 1_048_576:.1f} MB"
    else:
        storage_label = f"{total_bytes / 1024:.0f} KB"

    return success({
        "files": [f.to_dict() for f in files],
        "total": total,
        "page":  page,
        "limit": limit,
        "pages": (total + limit - 1) // limit,
        "counts": {
            "all":      db.query(MediaFile).count(),
            "image":    db.query(MediaFile).filter_by(file_type="image").count(),
            "video":    db.query(MediaFile).filter_by(file_type="video").count(),
            "document": db.query(MediaFile).filter_by(file_type="document").count(),
        },
        "storage_used": storage_label,
        "storage_bytes": total_bytes,
    })


# ─── 11. Add Media Record (after file upload to CDN/S3) ──────────
@router.post("/media")
def add_media(
    body: AddMediaBody,
    _:   None    = Depends(admin_required),
    db:  Session = Depends(get_db),
):
    """
    Register a media file after it has been uploaded to your CDN/S3.
    The frontend uploads the file first, gets a URL back, then calls
    this endpoint to store the record in the DB.
    """
    file = MediaFile(
        name        = body.name,
        url         = body.url,
        file_type   = body.file_type,
        mime_type   = body.mime_type,
        size_bytes  = body.size_bytes or 0,
        width       = body.width,
        height      = body.height,
        alt_text    = body.alt_text,
        folder      = body.folder or "/",
        uploaded_by = body.uploaded_by,
    )
    db.add(file)
    db.commit()
    db.refresh(file)
    return success(file.to_dict(), "Media file registered", 201)


# ─── 12. Update Media (alt text / rename / move folder) ──────────
@router.patch("/media/{file_id}")
def update_media(
    file_id: str,
    body:    UpdateMediaBody,
    _:       None    = Depends(admin_required),
    db:      Session = Depends(get_db),
):
    """Update alt text, filename, or folder of a media file."""
    file = db.query(MediaFile).filter(MediaFile.id == file_id).first()
    if not file:
        raise HTTPException(status_code=404, detail="Media file not found")
    if body.alt_text is not None: file.alt_text = body.alt_text
    if body.name     is not None: file.name     = body.name
    if body.folder   is not None: file.folder   = body.folder
    db.commit()
    db.refresh(file)
    return success(file.to_dict(), "Media updated")


# ─── 13. Delete Media Record ──────────────────────────────────────
@router.delete("/media/{file_id}")
def delete_media(
    file_id: str,
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """Delete a media record from DB (does NOT delete from CDN/S3)."""
    file = db.query(MediaFile).filter(MediaFile.id == file_id).first()
    if not file:
        raise HTTPException(status_code=404, detail="Media file not found")
    name = file.name
    db.delete(file)
    db.commit()
    return success({"id": file_id}, f"Media '{name}' deleted from library")
