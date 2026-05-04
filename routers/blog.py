from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel

from deps import admin_required, get_db, success
from models import BlogPost

router = APIRouter()

class BlogPostCreate(BaseModel):
    title: str
    author: str
    category: str
    content: str = ""
    status: str = "draft"

@router.get("/posts")
def get_blog_posts(
    _: None = Depends(admin_required),
    db: Session = Depends(get_db)
):
    """
    Get everything needed for the Blog Management > Posts table.
    """
    
    posts = db.query(BlogPost).order_by(BlogPost.created_at.desc()).all()
    return success(
        [p.to_dict() for p in posts]
    )

@router.post("/posts")
def create_post(
    payload: BlogPostCreate,
    _: None = Depends(admin_required),
    db: Session = Depends(get_db)
):
    """Create a new blog post."""
    post = BlogPost(
        title=payload.title,
        author=payload.author,
        category=payload.category,
        content=payload.content,
        status=payload.status,
        published_at=datetime.utcnow() if payload.status == "published" else None
    )
    db.add(post)
    db.commit()
    db.refresh(post)
    return success(post.to_dict())

@router.delete("/posts/{post_id}")
def delete_post(
    post_id: str,
    _: None = Depends(admin_required),
    db: Session = Depends(get_db)
):
    """Delete a blog post."""
    post = db.query(BlogPost).filter(BlogPost.id == post_id).first()
    if not post:
        raise HTTPException(status_code=404, detail="Post not found")
    
    db.delete(post)
    db.commit()
    return success({"message": "Post deleted successfully"})
