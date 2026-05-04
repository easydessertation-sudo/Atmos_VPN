import os
import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from dotenv import load_dotenv

load_dotenv()

# App URLs
APP_BASE_URL = os.environ.get("APP_BASE_URL", "http://localhost:5000")
FRONTEND_URL = os.environ.get("FRONTEND_URL", "http://localhost:3000")
SUPPORT_EMAIL = os.environ.get("SUPPORT_EMAIL", "support@atmosvpn.com")

# SMTP Configuration
SMTP_SERVER = os.environ.get("SMTP_SERVER", "")
SMTP_PORT = int(os.environ.get("SMTP_PORT", 587))
SMTP_USERNAME = os.environ.get("SMTP_USERNAME", "")
SMTP_PASSWORD = os.environ.get("SMTP_PASSWORD", "")


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

    if not SMTP_SERVER or not SMTP_USERNAME:
        print("\n" + "="*60)
        print("📨 [SMTP EMAIL SIMULATOR]")
        print(f"TO: {to_email}")
        print("SUBJECT: Reset Your Password")
        print("-" * 60)
        print(f"Reset Link: {reset_link}")
        print("="*60 + "\n")
        return True

    try:
        # Create message container
        msg = MIMEMultipart("alternative")
        msg["Subject"] = "Reset Your Password"
        msg["From"] = f"AtmosVPN <{SUPPORT_EMAIL}>"
        msg["To"] = to_email

        # Attach HTML content
        part = MIMEText(html_content, "html")
        msg.attach(part)

        # Connect to server and send
        with smtplib.SMTP(SMTP_SERVER, SMTP_PORT) as server:
            server.starttls()
            server.login(SMTP_USERNAME, SMTP_PASSWORD)
            server.sendmail(SUPPORT_EMAIL, to_email, msg.as_string())
            
        print(f"✅ Reset email successfully sent to {to_email} via SMTP")
        return True
    except Exception as e:
        print(f"⚠️ Failed to send SMTP reset email: {e}")
        return False
