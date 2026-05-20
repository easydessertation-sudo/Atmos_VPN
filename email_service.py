import os
import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from dotenv import load_dotenv

load_dotenv()

# App URLs
APP_BASE_URL = os.environ.get("APP_BASE_URL", "http://localhost:5000")
FRONTEND_URL = os.environ.get("FRONTEND_URL", "http://localhost:3000")

# SMTP Configuration
SMTP_SERVER   = os.environ.get("SMTP_SERVER", "")
SMTP_PORT     = int(os.environ.get("SMTP_PORT", 587))
SMTP_USERNAME = os.environ.get("SMTP_USERNAME", "")
SMTP_PASSWORD = os.environ.get("SMTP_PASSWORD", "")

# Gmail prevents sending from a different address than the login account.
SUPPORT_EMAIL = os.environ.get("SUPPORT_EMAIL", SMTP_USERNAME or "atmosvpn00@gmail.com")


# ─── Internal helper ───────────────────────────────────────────────────────────
def _send_smtp(to_email: str, subject: str, html_content: str) -> bool:
    """Sends an HTML email via configured SMTP. Falls back to terminal simulation."""
    if not SMTP_SERVER or not SMTP_USERNAME:
        print(f"\n{'='*60}")
        print("SMTP EMAIL SIMULATOR")
        print(f"TO: {to_email}")
        print(f"SUBJECT: {subject}")
        print("-" * 60)
        print(html_content[:400])
        print(f"{'='*60}\n")
        return True
    try:
        msg = MIMEMultipart("alternative")
        msg["Subject"] = subject
        msg["From"]    = f"AtmosVPN <{SUPPORT_EMAIL}>"
        msg["To"]      = to_email
        msg.attach(MIMEText(html_content, "html"))
        with smtplib.SMTP(SMTP_SERVER, SMTP_PORT) as server:
            server.starttls()
            server.login(SMTP_USERNAME, SMTP_PASSWORD)
            server.sendmail(SUPPORT_EMAIL, to_email, msg.as_string())
        print(f"Email sent to {to_email}")
        return True
    except Exception as e:
        print(f"SMTP error sending to {to_email}: {e}")
        return False


# ─── Password Reset ────────────────────────────────────────────────────────────
def send_password_reset_email(to_email: str, token: str) -> bool:
    """
    Sends a beautifully formatted password reset email via SMTP.
    If SMTP_SERVER is not set, it simulates the email in the terminal
    so development can continue without a configured email provider.
    """
    reset_link = f"{FRONTEND_URL}/reset-password?token={token}"

    html_content = f"""
    <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; color: #333;">
        <h2 style="color: #2563eb;">AtmosVPN</h2>
        <p>Hello,</p>
        <p>We received a request to reset your password. Click the button below to choose a new one:</p>
        <p style="text-align: center; margin: 30px 0;">
            <a href="{reset_link}" style="background-color: #2563eb; color: white; padding: 12px 24px; text-decoration: none; border-radius: 6px; font-weight: bold;">Reset Password</a>
        </p>
        <p>Or copy this link into your browser:</p>
        <p><a href="{reset_link}" style="word-break: break-all;">{reset_link}</a></p>
        <p><em>Note: This link expires in 15 minutes. If you did not request this, please ignore this email.</em></p>
        <hr style="border: none; border-top: 1px solid #eaeaea; margin: 30px 0;" />
        <p style="font-size: 12px; color: #888; text-align: center;">© AtmosVPN. All rights reserved.</p>
    </div>
    """
    return _send_smtp(to_email, "Reset Your Password", html_content)


# ─── Contact Form: Auto-reply to user ─────────────────────────────────────────
def send_contact_confirmation_email(
    to_email: str, name: str, subject: str, ticket_id: str
) -> bool:
    """
    Sends an auto-reply to the user confirming their contact form was received.
    Includes a ticket reference number so they can track the issue.
    """
    html_content = f"""
    <div style="font-family:Arial,sans-serif;max-width:600px;margin:0 auto;color:#333;background:#f9f9f9;padding:30px;border-radius:8px;">
        <h2 style="color:#2563eb;margin-bottom:4px;">AtmosVPN Support</h2>
        <p style="color:#888;font-size:13px;margin-top:0;">We've received your message</p>
        <hr style="border:none;border-top:1px solid #eaeaea;" />
        <p>Hi <strong>{name}</strong>,</p>
        <p>Thank you for contacting us! We've received your message regarding <strong>"{subject}"</strong> and a member of our team will get back to you within <strong>2 hours</strong>.</p>
        <div style="background:#fff;border:1px solid #e0e0e0;border-radius:6px;padding:16px 20px;margin:20px 0;">
            <p style="margin:0;font-size:13px;color:#888;">Your ticket reference</p>
            <p style="margin:4px 0 0;font-size:22px;font-weight:bold;color:#2563eb;letter-spacing:2px;">#{ticket_id}</p>
        </div>
        <p>In the meantime, you may find your answer in our <a href="{FRONTEND_URL}/faq" style="color:#2563eb;">FAQ page</a>.</p>
        <p style="color:#888;">— The AtmosVPN Support Team</p>
        <hr style="border:none;border-top:1px solid #eaeaea;margin:30px 0;" />
        <p style="font-size:11px;color:#aaa;text-align:center;">© AtmosVPN. All rights reserved. | atmosvpn00@gmail.com</p>
    </div>
    """
    return _send_smtp(
        to_email,
        f"[#{ticket_id}] We received your message – AtmosVPN Support",
        html_content,
    )


# ─── Contact Form: Internal admin notification ─────────────────────────────────
def send_contact_admin_notification(
    ticket_id: str,
    name: str,
    email: str,
    subject: str,
    category: str,
    message: str,
) -> bool:
    """
    Sends an internal notification to the support inbox whenever a new contact
    form is submitted. Lets the support team act without logging into the admin panel.
    """
    html_content = f"""
    <div style="font-family:Arial,sans-serif;max-width:640px;margin:0 auto;color:#333;">
        <h2 style="color:#e53e3e;">New Support Ticket #{ticket_id}</h2>
        <table style="width:100%;border-collapse:collapse;font-size:14px;">
            <tr style="background:#f5f5f5;">
                <td style="padding:10px;font-weight:bold;width:140px;">Ticket ID</td>
                <td style="padding:10px;">#{ticket_id}</td>
            </tr>
            <tr>
                <td style="padding:10px;font-weight:bold;">Name</td>
                <td style="padding:10px;">{name}</td>
            </tr>
            <tr style="background:#f5f5f5;">
                <td style="padding:10px;font-weight:bold;">Email</td>
                <td style="padding:10px;"><a href="mailto:{email}">{email}</a></td>
            </tr>
            <tr>
                <td style="padding:10px;font-weight:bold;">Subject</td>
                <td style="padding:10px;">{subject}</td>
            </tr>
            <tr style="background:#f5f5f5;">
                <td style="padding:10px;font-weight:bold;">Category</td>
                <td style="padding:10px;">{category}</td>
            </tr>
        </table>
        <div style="margin-top:20px;padding:16px;background:#fefefe;border:1px solid #ddd;border-radius:6px;">
            <p style="margin:0;font-weight:bold;color:#555;">Message:</p>
            <p style="margin:8px 0 0;white-space:pre-wrap;">{message}</p>
        </div>
        <p style="margin-top:20px;">
            <a href="{APP_BASE_URL}/api/admin/tickets"
               style="background:#2563eb;color:white;padding:10px 20px;text-decoration:none;border-radius:5px;font-size:14px;">
               View in Admin Panel
            </a>
        </p>
    </div>
    """
    return _send_smtp(
        SUPPORT_EMAIL,
        f"[New Ticket #{ticket_id}] {subject} — from {name}",
        html_content,
    )

# ─── Status Page: Automated Alerts ─────────────────────────────────────────────
def send_status_alert(subject: str, message: str) -> None:
    """
    Blasts an email to all users subscribed to the Status Page alerts.
    """
    from models import SessionLocal, StatusSubscriber
    db = SessionLocal()
    try:
        subscribers = db.query(StatusSubscriber).all()
        if not subscribers:
            print("No status subscribers found.")
            return

        html_content = f"""
        <div style="font-family:Arial,sans-serif;max-width:600px;margin:0 auto;color:#333;background:#f9f9f9;padding:30px;border-radius:8px;">
            <h2 style="color:#e53e3e;margin-bottom:4px;">AtmosVPN Status Alert</h2>
            <hr style="border:none;border-top:1px solid #eaeaea;" />
            <p style="font-size:16px;">{message}</p>
            <hr style="border:none;border-top:1px solid #eaeaea;margin:30px 0;" />
            <p style="font-size:11px;color:#aaa;text-align:center;">You received this because you subscribed to AtmosVPN status alerts.</p>
        </div>
        """
        
        for sub in subscribers:
            _send_smtp(sub.email, f"⚠️ AtmosVPN Alert: {subject}", html_content)
            
        print(f"Status alert sent to {len(subscribers)} subscribers.")
    finally:
        db.close()

def send_status_welcome_email(to_email: str) -> bool:
    """
    Sends a confirmation email to the user when they first subscribe to status alerts.
    """
    html_content = f"""
    <div style="font-family:Arial,sans-serif;max-width:600px;margin:0 auto;color:#333;background:#f9f9f9;padding:30px;border-radius:8px;">
        <h2 style="color:#2563eb;margin-bottom:4px;">Subscription Confirmed</h2>
        <hr style="border:none;border-top:1px solid #eaeaea;" />
        <p>Hello,</p>
        <p>You have successfully subscribed to <strong>AtmosVPN Status Alerts</strong>.</p>
        <p>If any of our servers experience an unexpected outage or enter scheduled maintenance, you will be instantly notified right here in your inbox.</p>
        <p>Thank you for choosing AtmosVPN!</p>
        <hr style="border:none;border-top:1px solid #eaeaea;margin:30px 0;" />
        <p style="font-size:11px;color:#aaa;text-align:center;">© AtmosVPN. All rights reserved.</p>
    </div>
    """
    return _send_smtp(to_email, "Subscribed to AtmosVPN Status Alerts", html_content)

def send_verification_email(to_email: str, code: str) -> bool:
    """
    Sends a beautifully formatted email verification code to the user.
    """
    html_content = f"""
    <div style="font-family:Arial,sans-serif;max-width:600px;margin:0 auto;color:#333;background:#f9f9f9;padding:30px;border-radius:8px;">
        <h2 style="color:#2563eb;margin-bottom:4px;">AtmosVPN</h2>
        <p style="color:#888;font-size:13px;margin-top:0;">Verify Your Email Address</p>
        <hr style="border:none;border-top:1px solid #eaeaea;" />
        <p>Hello,</p>
        <p>Thank you for signing up for AtmosVPN! To complete your registration and activate your account, please enter the following verification code in the app:</p>
        <div style="background:#fff;border:1px solid #e0e0e0;border-radius:6px;padding:16px 20px;margin:20px 0;text-align:center;">
            <p style="margin:0;font-size:13px;color:#888;">Your verification code</p>
            <p style="margin:8px 0 0;font-size:32px;font-weight:bold;color:#2563eb;letter-spacing:4px;line-height:1;">{code}</p>
        </div>
        <p>This verification code is valid for the next 24 hours. If you did not sign up for AtmosVPN, please ignore this email.</p>
        <p style="color:#888;">— The AtmosVPN Team</p>
        <hr style="border:none;border-top:1px solid #eaeaea;margin:30px 0;" />
        <p style="font-size:11px;color:#aaa;text-align:center;">© AtmosVPN. All rights reserved. | support@atmosvpn.com</p>
    </div>
    """
    return _send_smtp(to_email, "Verify your AtmosVPN account", html_content)

