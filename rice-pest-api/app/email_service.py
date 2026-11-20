import os
import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

# ---- CONFIG: put YOUR sender Gmail + its 16-char App Password here ----
SMTP_HOST = "smtp.gmail.com"
SMTP_PORT = 587
SENDER_EMAIL = os.getenv("SMTP_USERNAME", "YOUR_PROJECT_GMAIL@gmail.com")
SENDER_APP_PASSWORD = os.getenv("SMTP_PASSWORD", "PASTE_16_CHAR_APP_PASSWORD_NO_SPACES")
# ------------------------------------------------------------------------


def send_otp_email(to_email: str, otp_code: str) -> None:
    """Sends the OTP to a real inbox via Gmail SMTP. Raises on failure."""
    msg = MIMEMultipart("alternative")
    msg["Subject"] = "Your Rice Pest Detection verification code"
    msg["From"] = f"Rice Pest Detection <{SENDER_EMAIL}>"
    msg["To"] = to_email

    text_body = (
        f"Your verification code is {otp_code}\n"
        "It expires in 10 minutes. If you did not request this, ignore this email."
    )
    html_body = f"""
    <div style="font-family:Arial,sans-serif;max-width:480px;margin:0 auto;
                border:1px solid #E5E0D8;border-radius:12px;padding:24px;">
      <h2 style="color:#1B4332;margin:0 0 8px;">Rice Pest Detection</h2>
      <p style="color:#5C6B5E;margin:0 0 16px;">
        Use this code to verify your account:
      </p>
      <div style="background:#D8F3DC;border-radius:8px;padding:16px;
                  text-align:center;font-size:28px;font-weight:bold;
                  letter-spacing:6px;color:#1B4332;">{otp_code}</div>
      <p style="color:#8E9E90;font-size:12px;margin:16px 0 0;">
        This code expires in 10 minutes. If you did not request it, ignore this email.
      </p>
    </div>
    """
    msg.attach(MIMEText(text_body, "plain"))
    msg.attach(MIMEText(html_body, "html"))

    with smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=20) as server:
        server.ehlo()
        server.starttls()
        server.ehlo()
        server.login(SENDER_EMAIL, SENDER_APP_PASSWORD)
        server.sendmail(SENDER_EMAIL, [to_email], msg.as_string())

def send_plain_email(to_email: str, subject: str, body: str) -> None:
    """Short plain-text notice (e.g. account approved). Raises on failure."""
    msg = MIMEText(body, "plain")
    msg["Subject"] = subject
    msg["From"] = f"Rice Pest Detection <{SENDER_EMAIL}>"
    msg["To"] = to_email
    with smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=20) as server:
        server.ehlo()
        server.starttls()
        server.ehlo()
        server.login(SENDER_EMAIL, SENDER_APP_PASSWORD)
        server.sendmail(SENDER_EMAIL, [to_email], msg.as_string())
