"""
Support Content Router — Help Articles & FAQ Management
/api/admin/support/*

┌─────────────────────────────────────────────────────────────────────┐
│  HELP ARTICLES TAB                                                   │
│  GET    /api/admin/support/articles           → list (filtered)     │
│  POST   /api/admin/support/articles           → create article      │
│  GET    /api/admin/support/articles/{id}      → single detail       │
│  PATCH  /api/admin/support/articles/{id}      → edit article        │
│  DELETE /api/admin/support/articles/{id}      → delete article      │
│  POST   /api/admin/support/articles/{id}/publish  → publish draft   │
│  POST   /api/admin/support/articles/{id}/helpful  → record feedback │
│                                                                      │
│  FAQ MANAGEMENT TAB                                                  │
│  GET    /api/admin/support/faqs               → list (filtered)     │
│  POST   /api/admin/support/faqs               → create FAQ          │
│  GET    /api/admin/support/faqs/{id}          → single detail       │
│  PATCH  /api/admin/support/faqs/{id}          → edit FAQ            │
│  DELETE /api/admin/support/faqs/{id}          → delete FAQ          │
│  PATCH  /api/admin/support/faqs/reorder       → update sort order   │
│  POST   /api/admin/support/faqs/{id}/helpful  → record feedback     │
│                                                                      │
│  SHARED                                                              │
│  GET    /api/admin/support/overview           → KPIs for both tabs  │
└─────────────────────────────────────────────────────────────────────┘
"""
import re
from datetime import datetime
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy.orm import Session

from deps import admin_required, get_db, success
from models import HelpArticle, FAQ

router = APIRouter()


# ══════════════════════════════════════════════════════════════════
# ─── Helpers ──────────────────────────────────────────────────────
# ══════════════════════════════════════════════════════════════════

def _slugify(text: str) -> str:
    """Convert title to a URL-safe slug, e.g. 'How to Connect' → 'how-to-connect'."""
    text = text.lower().strip()
    text = re.sub(r"[^\w\s-]", "", text)
    text = re.sub(r"[\s_]+", "-", text)
    return re.sub(r"-+", "-", text)


def _ensure_unique_slug(slug: str, db: Session, exclude_id: str = None) -> str:
    """Append a counter suffix if the slug already exists."""
    base = slug
    counter = 1
    while True:
        q = db.query(HelpArticle).filter(HelpArticle.slug == slug)
        if exclude_id:
            q = q.filter(HelpArticle.id != exclude_id)
        if not q.first():
            return slug
        slug = f"{base}-{counter}"
        counter += 1


ARTICLE_CATEGORIES = ["getting_started", "account", "billing", "technical", "security", "general"]
FAQ_CATEGORIES     = ["general", "billing", "technical", "account", "security"]


# ══════════════════════════════════════════════════════════════════
# ─── Pydantic Schemas ─────────────────────────────────────────────
# ══════════════════════════════════════════════════════════════════

class CreateArticleBody(BaseModel):
    title:        str
    content:      str
    excerpt:      Optional[str]  = None
    category:     Optional[str]  = "general"
    tags:         Optional[str]  = None           # comma-separated, e.g. "vpn,setup,windows"
    status:       Optional[str]  = "draft"        # draft | published
    is_featured:  Optional[bool] = False
    author_name:  Optional[str]  = "AtmosVPN Team"
    author_email: Optional[str]  = None


class UpdateArticleBody(BaseModel):
    title:        Optional[str]  = None
    content:      Optional[str]  = None
    excerpt:      Optional[str]  = None
    category:     Optional[str]  = None
    tags:         Optional[str]  = None
    status:       Optional[str]  = None
    is_featured:  Optional[bool] = None
    author_name:  Optional[str]  = None
    author_email: Optional[str]  = None


class CreateFAQBody(BaseModel):
    question:    str
    answer:      str
    category:    Optional[str]  = "general"
    tags:        Optional[str]  = None
    status:      Optional[str]  = "published"     # draft | published
    sort_order:  Optional[int]  = 0
    is_featured: Optional[bool] = False
    created_by:  Optional[str]  = None            # admin email


class UpdateFAQBody(BaseModel):
    question:    Optional[str]  = None
    answer:      Optional[str]  = None
    category:    Optional[str]  = None
    tags:        Optional[str]  = None
    status:      Optional[str]  = None
    sort_order:  Optional[int]  = None
    is_featured: Optional[bool] = None


class ReorderFAQBody(BaseModel):
    """List of { id, sort_order } pairs — call after drag-and-drop reorder."""
    items: List[dict]   # [{ "id": "uuid", "sort_order": 0 }, ...]


class HelpfulBody(BaseModel):
    helpful: bool       # true = 👍, false = 👎


# ══════════════════════════════════════════════════════════════════
# ─── SHARED: Overview KPIs ────────────────────────────────────────
# ══════════════════════════════════════════════════════════════════

@router.get("/overview")
def support_content_overview(
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """
    KPI cards for the Support Center content tabs.
    Called once on page load to populate both the Help Articles
    and FAQ Management summary panels.
    """
    total_articles   = db.query(HelpArticle).count()
    pub_articles     = db.query(HelpArticle).filter_by(status="published").count()
    draft_articles   = db.query(HelpArticle).filter_by(status="draft").count()
    total_views_art  = db.query(HelpArticle).with_entities(
        HelpArticle.views
    ).all()
    article_views    = sum(v[0] or 0 for v in total_views_art)

    total_faqs       = db.query(FAQ).count()
    pub_faqs         = db.query(FAQ).filter_by(status="published").count()
    draft_faqs       = db.query(FAQ).filter_by(status="draft").count()
    total_views_faq  = db.query(FAQ).with_entities(FAQ.views).all()
    faq_views        = sum(v[0] or 0 for v in total_views_faq)

    # Category breakdown for articles
    art_by_cat = {}
    for cat in ARTICLE_CATEGORIES:
        art_by_cat[cat] = db.query(HelpArticle).filter_by(category=cat).count()

    faq_by_cat = {}
    for cat in FAQ_CATEGORIES:
        faq_by_cat[cat] = db.query(FAQ).filter_by(category=cat).count()

    return success({
        "articles": {
            "total":        total_articles,
            "published":    pub_articles,
            "draft":        draft_articles,
            "total_views":  article_views,
            "by_category":  art_by_cat,
        },
        "faqs": {
            "total":       total_faqs,
            "published":   pub_faqs,
            "draft":       draft_faqs,
            "total_views": faq_views,
            "by_category": faq_by_cat,
        },
    })


# ══════════════════════════════════════════════════════════════════
# ─── HELP ARTICLES TAB ────────────────────────────────────────────
# ══════════════════════════════════════════════════════════════════

# ─── 1. List Articles ─────────────────────────────────────────────
@router.get("/articles")
def list_articles(
    search:      Optional[str] = Query(None,  description="Search in title or excerpt"),
    category:    Optional[str] = Query(None,  description="getting_started|account|billing|technical|security|general"),
    status:      Optional[str] = Query(None,  description="draft | published"),
    is_featured: Optional[bool]= Query(None,  description="true = featured only"),
    page:        int = Query(1,  ge=1),
    limit:       int = Query(20, ge=1, le=100),
    _:   None    = Depends(admin_required),
    db:  Session = Depends(get_db),
):
    """
    Paginated, filterable list of Help Articles.
    Content body is excluded from list view (use GET /articles/{id} for full content).
    """
    q = db.query(HelpArticle)

    if search:
        q = q.filter(
            HelpArticle.title.ilike(f"%{search}%") |
            HelpArticle.excerpt.ilike(f"%{search}%") |
            HelpArticle.tags.ilike(f"%{search}%")
        )
    if category:
        q = q.filter(HelpArticle.category == category)
    if status:
        q = q.filter(HelpArticle.status == status)
    if is_featured is not None:
        q = q.filter(HelpArticle.is_featured == is_featured)

    total = q.count()
    # Featured articles float to top; then sort by newest
    items = (
        q.order_by(HelpArticle.is_featured.desc(), HelpArticle.created_at.desc())
         .offset((page - 1) * limit)
         .limit(limit)
         .all()
    )

    return success({
        "articles": [a.to_dict(include_content=False) for a in items],
        "total":    total,
        "page":     page,
        "limit":    limit,
        "pages":    (total + limit - 1) // limit,
        "counts": {
            "all":       db.query(HelpArticle).count(),
            "published": db.query(HelpArticle).filter_by(status="published").count(),
            "draft":     db.query(HelpArticle).filter_by(status="draft").count(),
            "featured":  db.query(HelpArticle).filter_by(is_featured=True).count(),
        },
    })


# ─── 2. Create Article ────────────────────────────────────────────
@router.post("/articles", status_code=201)
def create_article(
    body: CreateArticleBody,
    _:   None    = Depends(admin_required),
    db:  Session = Depends(get_db),
):
    """
    Create a new Help Article.
    If status='published', published_at is set automatically.
    A URL slug is auto-generated from the title (guaranteed unique).
    """
    if body.category and body.category not in ARTICLE_CATEGORIES:
        raise HTTPException(400, f"Invalid category. Must be one of: {ARTICLE_CATEGORIES}")
    if body.status and body.status not in ("draft", "published"):
        raise HTTPException(400, "status must be 'draft' or 'published'")

    slug = _ensure_unique_slug(_slugify(body.title), db)

    article = HelpArticle(
        title        = body.title,
        slug         = slug,
        content      = body.content,
        excerpt      = body.excerpt or body.content[:200].rstrip() + "…",
        category     = body.category or "general",
        tags         = body.tags,
        status       = body.status or "draft",
        is_featured  = body.is_featured or False,
        author_name  = body.author_name or "AtmosVPN Team",
        author_email = body.author_email,
        published_at = datetime.utcnow() if (body.status == "published") else None,
    )
    db.add(article)
    db.commit()
    db.refresh(article)
    return success(article.to_dict(), "Article created successfully")


# ─── 3. Get Single Article ────────────────────────────────────────
@router.get("/articles/{article_id}")
def get_article(
    article_id: str,
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """Full detail of a single article including content body. Used to pre-fill Edit modal."""
    a = db.get(HelpArticle, article_id)
    if not a:
        raise HTTPException(404, "Article not found")
    # Increment view counter
    a.views = (a.views or 0) + 1
    db.commit()
    db.refresh(a)
    return success(a.to_dict(include_content=True))


# ─── 4. Edit Article ──────────────────────────────────────────────
@router.patch("/articles/{article_id}")
def update_article(
    article_id: str,
    body: UpdateArticleBody,
    _:   None    = Depends(admin_required),
    db:  Session = Depends(get_db),
):
    """
    Update any fields of a Help Article.
    Send only the fields you want to change.
    If status changes to 'published', published_at is set automatically.
    """
    a = db.get(HelpArticle, article_id)
    if not a:
        raise HTTPException(404, "Article not found")

    if body.category and body.category not in ARTICLE_CATEGORIES:
        raise HTTPException(400, f"Invalid category. Must be one of: {ARTICLE_CATEGORIES}")
    if body.status and body.status not in ("draft", "published"):
        raise HTTPException(400, "status must be 'draft' or 'published'")

    if body.title        is not None:
        a.title = body.title
        # Regenerate slug when title changes
        a.slug  = _ensure_unique_slug(_slugify(body.title), db, exclude_id=article_id)
    if body.content      is not None: a.content      = body.content
    if body.excerpt      is not None: a.excerpt       = body.excerpt
    if body.category     is not None: a.category      = body.category
    if body.tags         is not None: a.tags          = body.tags
    if body.is_featured  is not None: a.is_featured   = body.is_featured
    if body.author_name  is not None: a.author_name   = body.author_name
    if body.author_email is not None: a.author_email  = body.author_email
    if body.status       is not None:
        if body.status == "published" and a.status != "published":
            a.published_at = datetime.utcnow()
        a.status = body.status

    a.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(a)
    return success(a.to_dict(), "Article updated successfully")


# ─── 5. Publish Draft Article ─────────────────────────────────────
@router.post("/articles/{article_id}/publish")
def publish_article(
    article_id: str,
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """
    One-click publish a draft article.
    Sets status='published' and records published_at timestamp.
    """
    a = db.get(HelpArticle, article_id)
    if not a:
        raise HTTPException(404, "Article not found")
    if a.status == "published":
        raise HTTPException(409, "Article is already published")
    a.status       = "published"
    a.published_at = datetime.utcnow()
    a.updated_at   = datetime.utcnow()
    db.commit()
    db.refresh(a)
    return success(a.to_dict(include_content=False), f"Article '{a.title}' published")


# ─── 6. Helpful Feedback ──────────────────────────────────────────
@router.post("/articles/{article_id}/helpful")
def article_helpful(
    article_id: str,
    body: HelpfulBody,
    _:   None    = Depends(admin_required),
    db:  Session = Depends(get_db),
):
    """
    Record a 👍 / 👎 vote on an article.
    Body: { "helpful": true }  or  { "helpful": false }
    """
    a = db.get(HelpArticle, article_id)
    if not a:
        raise HTTPException(404, "Article not found")
    if body.helpful:
        a.helpful_yes = (a.helpful_yes or 0) + 1
    else:
        a.helpful_no  = (a.helpful_no  or 0) + 1
    db.commit()
    db.refresh(a)
    return success({
        "helpful_yes":   a.helpful_yes,
        "helpful_no":    a.helpful_no,
        "helpful_total": (a.helpful_yes or 0) + (a.helpful_no or 0),
    }, "Feedback recorded")


# ─── 7. Delete Article ────────────────────────────────────────────
@router.delete("/articles/{article_id}")
def delete_article(
    article_id: str,
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """Permanently delete a Help Article."""
    a = db.get(HelpArticle, article_id)
    if not a:
        raise HTTPException(404, "Article not found")
    title = a.title
    db.delete(a)
    db.commit()
    return success({"id": article_id}, f"Article '{title}' deleted")


# ══════════════════════════════════════════════════════════════════
# ─── FAQ MANAGEMENT TAB ───────────────────────────────────────────
# ══════════════════════════════════════════════════════════════════

# ─── 1. List FAQs ────────────────────────────────────────────────
@router.get("/faqs")
def list_faqs(
    search:      Optional[str] = Query(None,  description="Search in question or answer"),
    category:    Optional[str] = Query(None,  description="general|billing|technical|account|security"),
    status:      Optional[str] = Query(None,  description="draft | published"),
    is_featured: Optional[bool]= Query(None),
    page:        int = Query(1,  ge=1),
    limit:       int = Query(50, ge=1, le=200),
    _:   None    = Depends(admin_required),
    db:  Session = Depends(get_db),
):
    """
    Paginated, filterable list of FAQs.
    Results are sorted by sort_order ASC (lower = first),
    with featured FAQs pinned to the top.
    """
    q = db.query(FAQ)

    if search:
        q = q.filter(
            FAQ.question.ilike(f"%{search}%") |
            FAQ.answer.ilike(f"%{search}%") |
            FAQ.tags.ilike(f"%{search}%")
        )
    if category:
        q = q.filter(FAQ.category == category)
    if status:
        q = q.filter(FAQ.status == status)
    if is_featured is not None:
        q = q.filter(FAQ.is_featured == is_featured)

    total = q.count()
    items = (
        q.order_by(FAQ.is_featured.desc(), FAQ.sort_order.asc(), FAQ.created_at.desc())
         .offset((page - 1) * limit)
         .limit(limit)
         .all()
    )

    return success({
        "faqs":  [f.to_dict() for f in items],
        "total": total,
        "page":  page,
        "limit": limit,
        "pages": (total + limit - 1) // limit,
        "counts": {
            "all":       db.query(FAQ).count(),
            "published": db.query(FAQ).filter_by(status="published").count(),
            "draft":     db.query(FAQ).filter_by(status="draft").count(),
            "featured":  db.query(FAQ).filter_by(is_featured=True).count(),
        },
    })


# ─── 2. Create FAQ ────────────────────────────────────────────────
@router.post("/faqs", status_code=201)
def create_faq(
    body: CreateFAQBody,
    _:   None    = Depends(admin_required),
    db:  Session = Depends(get_db),
):
    """
    Create a new FAQ entry.
    sort_order defaults to 0 — set a higher value to push it lower in the list.
    """
    if body.category and body.category not in FAQ_CATEGORIES:
        raise HTTPException(400, f"Invalid category. Must be one of: {FAQ_CATEGORIES}")
    if body.status and body.status not in ("draft", "published"):
        raise HTTPException(400, "status must be 'draft' or 'published'")

    faq = FAQ(
        question    = body.question,
        answer      = body.answer,
        category    = body.category or "general",
        tags        = body.tags,
        status      = body.status or "published",
        sort_order  = body.sort_order or 0,
        is_featured = body.is_featured or False,
        created_by  = body.created_by,
    )
    db.add(faq)
    db.commit()
    db.refresh(faq)
    return success(faq.to_dict(), "FAQ created successfully")


# ─── 3. Get Single FAQ ───────────────────────────────────────────
@router.get("/faqs/{faq_id}")
def get_faq(
    faq_id: str,
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """Full detail of a single FAQ. Increments view counter."""
    f = db.get(FAQ, faq_id)
    if not f:
        raise HTTPException(404, "FAQ not found")
    f.views = (f.views or 0) + 1
    db.commit()
    db.refresh(f)
    return success(f.to_dict())


# ─── 4. Edit FAQ ─────────────────────────────────────────────────
@router.patch("/faqs/{faq_id}")
def update_faq(
    faq_id: str,
    body: UpdateFAQBody,
    _:   None    = Depends(admin_required),
    db:  Session = Depends(get_db),
):
    """
    Update any fields of a FAQ.
    Send only the fields you want to change.
    """
    f = db.get(FAQ, faq_id)
    if not f:
        raise HTTPException(404, "FAQ not found")

    if body.category and body.category not in FAQ_CATEGORIES:
        raise HTTPException(400, f"Invalid category. Must be one of: {FAQ_CATEGORIES}")
    if body.status and body.status not in ("draft", "published"):
        raise HTTPException(400, "status must be 'draft' or 'published'")

    if body.question    is not None: f.question    = body.question
    if body.answer      is not None: f.answer      = body.answer
    if body.category    is not None: f.category    = body.category
    if body.tags        is not None: f.tags        = body.tags
    if body.status      is not None: f.status      = body.status
    if body.sort_order  is not None: f.sort_order  = body.sort_order
    if body.is_featured is not None: f.is_featured = body.is_featured

    f.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(f)
    return success(f.to_dict(), "FAQ updated successfully")


# ─── 5. Bulk Reorder FAQs ────────────────────────────────────────
@router.patch("/faqs/reorder")
def reorder_faqs(
    body: ReorderFAQBody,
    _:   None    = Depends(admin_required),
    db:  Session = Depends(get_db),
):
    """
    Update sort_order for multiple FAQs at once.
    Called after drag-and-drop reorder in the UI.
    Body: { "items": [{ "id": "uuid", "sort_order": 0 }, ...] }
    """
    updated = []
    for item in body.items:
        faq_id     = item.get("id")
        sort_order = item.get("sort_order")
        if faq_id is None or sort_order is None:
            continue
        f = db.get(FAQ, faq_id)
        if f:
            f.sort_order = sort_order
            updated.append(str(f.id))
    db.commit()
    return success({"updated_ids": updated, "count": len(updated)}, "FAQ order updated")


# ─── 6. Helpful Feedback ─────────────────────────────────────────
@router.post("/faqs/{faq_id}/helpful")
def faq_helpful(
    faq_id: str,
    body: HelpfulBody,
    _:   None    = Depends(admin_required),
    db:  Session = Depends(get_db),
):
    """
    Record a 👍 / 👎 vote on a FAQ.
    Body: { "helpful": true }  or  { "helpful": false }
    """
    f = db.get(FAQ, faq_id)
    if not f:
        raise HTTPException(404, "FAQ not found")
    if body.helpful:
        f.helpful_yes = (f.helpful_yes or 0) + 1
    else:
        f.helpful_no  = (f.helpful_no  or 0) + 1
    db.commit()
    db.refresh(f)
    return success({
        "helpful_yes":   f.helpful_yes,
        "helpful_no":    f.helpful_no,
        "helpful_total": (f.helpful_yes or 0) + (f.helpful_no or 0),
    }, "Feedback recorded")


# ─── 7. Delete FAQ ───────────────────────────────────────────────
@router.delete("/faqs/{faq_id}")
def delete_faq(
    faq_id: str,
    _:  None    = Depends(admin_required),
    db: Session = Depends(get_db),
):
    """Permanently delete a FAQ entry."""
    f = db.get(FAQ, faq_id)
    if not f:
        raise HTTPException(404, "FAQ not found")
    question = f.question[:60]
    db.delete(f)
    db.commit()
    return success({"id": faq_id}, f"FAQ deleted: '{question}...'")
