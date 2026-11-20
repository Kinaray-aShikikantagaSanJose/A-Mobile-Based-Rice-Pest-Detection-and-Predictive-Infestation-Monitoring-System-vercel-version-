-- =====================================================
-- 006: OTP attempt counter  -  run on rice_pest_db2 as postgres
-- =====================================================
-- /auth/verify-otp now counts wrong guesses per code and deletes the code
-- after 5 (MAX_OTP_ATTEMPTS in app/auth.py). Run this BEFORE restarting the
-- API, or register / resend-otp / verify-otp fail with
-- "column otps.attempts does not exist". Safe to run more than once.

ALTER TABLE otps ADD COLUMN IF NOT EXISTS attempts INTEGER NOT NULL DEFAULT 0;
