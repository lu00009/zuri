import logging
import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from app.core.config import settings

logger = logging.getLogger(__name__)


def send_verification_email(to_email: str, code: str) -> bool:
    """
    Sends a 6-digit password reset verification code via Gmail SMTP.
    Falls back gracefully to logging if SMTP credentials are not configured.
    """
    smtp_user = settings.SMTP_USER
    smtp_password = settings.SMTP_PASSWORD
    from_email = settings.SMTP_FROM_EMAIL or smtp_user or "noreply@zuri.app"
    from_name = settings.SMTP_FROM_NAME or "Zuri"

    subject = f"Your Zuri Verification Code: {code}"

    html_content = f"""
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <title>Reset Your Password - Zuri</title>
      <style>
        body {{
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
          background-color: #0F172A;
          color: #F8FAFC;
          padding: 24px;
          margin: 0;
        }}
        .container {{
          max-width: 520px;
          margin: 0 auto;
          background-color: #1E293B;
          border-radius: 16px;
          padding: 32px;
          box-shadow: 0 10px 25px rgba(0,0,0,0.3);
          border: 1px solid #334155;
        }}
        .logo {{
          font-size: 24px;
          font-weight: 700;
          color: #38BDF8;
          text-align: center;
          margin-bottom: 24px;
        }}
        h2 {{
          color: #FFFFFF;
          margin-top: 0;
          font-size: 20px;
        }}
        p {{
          color: #94A3B8;
          line-height: 1.6;
          font-size: 15px;
        }}
        .code-box {{
          background: linear-gradient(135deg, #2563EB 0%, #1D4ED8 100%);
          color: #FFFFFF;
          font-size: 32px;
          font-weight: 800;
          letter-spacing: 6px;
          text-align: center;
          padding: 18px 24px;
          border-radius: 12px;
          margin: 28px 0;
          box-shadow: 0 4px 14px rgba(37, 99, 235, 0.4);
        }}
        .footer {{
          margin-top: 32px;
          border-top: 1px solid #334155;
          padding-top: 16px;
          font-size: 12px;
          color: #64748B;
          text-align: center;
        }}
      </style>
    </head>
    <body>
      <div class="container">
        <div class="logo">✦ Zuri</div>
        <h2>Password Reset Verification</h2>
        <p>Hello,</p>
        <p>We received a request to reset your password for your Zuri account. Use the verification code below to complete the reset:</p>
        <div class="code-box">{code}</div>
        <p>This code will expire in <strong>15 minutes</strong>.</p>
        <p>If you didn't request a password reset, you can safely ignore this email — your account remains secure.</p>
        <div class="footer">
          &copy; {from_name}. All rights reserved.
        </div>
      </div>
    </body>
    </html>
    """

    text_content = (
        f"Zuri Password Reset Verification Code: {code}\n\n"
        f"This code will expire in 15 minutes.\n"
        f"If you did not request this password reset, please ignore this email.\n"
    )

    if not smtp_user or not smtp_password:
        logger.warning(
            f"[SMTP NOT CONFIGURED] Verification code for {to_email} is: {code} "
            f"(Configure SMTP_USER and SMTP_PASSWORD in your environment to deliver via Gmail)."
        )
        return True

    try:
        msg = MIMEMultipart("alternative")
        msg["Subject"] = subject
        msg["From"] = f"{from_name} <{from_email}>"
        msg["To"] = to_email

        part1 = MIMEText(text_content, "plain")
        part2 = MIMEText(html_content, "html")
        msg.attach(part1)
        msg.attach(part2)

        with smtplib.SMTP(settings.SMTP_HOST, settings.SMTP_PORT, timeout=10) as server:
            server.ehlo()
            server.starttls()
            server.ehlo()
            server.login(smtp_user, smtp_password)
            server.sendmail(from_email, [to_email], msg.as_string())

        logger.info(f"Verification email successfully sent to {to_email}")
        return True
    except Exception as e:
        logger.error(f"Failed to send email to {to_email} via Gmail SMTP: {e}", exc_info=True)
        # Even if SMTP fails on network/credentials, we don't crash, we log it
        return False

