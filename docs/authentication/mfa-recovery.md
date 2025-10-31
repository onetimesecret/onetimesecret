# MFA Recovery Guide

**Status:** Active
**Version:** 2.0 (2025-10-23)
**Authentication Mode:** Advanced (Rodauth)

---

## Overview

This document describes the MFA (Multi-Factor Authentication) recovery mechanisms available when users cannot complete MFA verification due to lost authenticator access or invalidated OTP credentials.

### Problem Statement

Users can become stuck in MFA verification (`awaiting_mfa` state) when:
- Authenticator device is lost, stolen, or broken
- OTP keys are invalidated (e.g., server configuration changes to `otp_keys_use_hmac`)
- Recovery codes are lost or unavailable
- Authenticator app is uninstalled or factory reset

Without proper recovery mechanisms, these users face lockout scenarios requiring support intervention.

---

## Recovery Options

### 1. Recovery Codes (Primary Self-Service Method)

**When to use:** Lost authenticator but have recovery codes saved

Recovery codes are generated when MFA is first enabled. Each code can be used once.

**How it works:**
1. Start login with email/password
2. When prompted for MFA code, click "Use recovery code instead"
3. Enter one of your saved recovery codes
4. Access granted - code is consumed and cannot be reused

**Best Practices:**
- Save recovery codes when setting up MFA
- Store codes in a secure password manager (1Password, Bitwarden, etc.)
- Print codes and store in a secure physical location
- Never store codes in the same device as your authenticator

**After using a recovery code:**
- You should re-generate new recovery codes from account settings
- Consider setting up MFA on multiple devices for redundancy

---

### 2. Admin Console Recovery (Development/Support)

**When to use:** User lost both authenticator AND all recovery codes

This method requires console access and should only be used by administrators or support staff.

#### Console Method

```ruby
# Start console session
bin/ots console

# Disable MFA for the account
Auth::Operations::DisableMfa.call(email: 'user@example.com')
```

**Output:**
```
✅ Removed OTP key for: user@example.com
✅ Removed 10 recovery code(s) for: user@example.com
✅ MFA successfully disabled for: user@example.com
⚠️  User should re-enable MFA from account settings after login
```

**What it does:**
- Removes OTP keys from `account_otp_keys` table
- Removes all recovery codes from `account_recovery_codes` table
- Logs the operation for audit purposes
- User can now log in with email/password only

**Security notes:**
- Only use in console sessions (never expose via API)
- Email addresses not visible in shell history
- Logs all operations for audit trail
- User should re-enable MFA after regaining access

#### Alternative: Programmatic Usage

```ruby
# In a script or background job
operation = Auth::Operations::DisableMfa.new(email: 'user@example.com')
success = operation.call

if success
  # Send notification email to user
  # Log to audit system
end
```

---

### 3. Support Process (Production)

**When to use:** User contacts support, console access not available

For production environments without direct console access, establish a support verification process:

#### Support Email Template

```
Subject: MFA Recovery Request for {email}

We've received your MFA recovery request.

To verify your identity, please reply with:
1. The approximate date you created your account
2. The last secret you created (approximate date)
3. Any custom domain associated with your account (if applicable)

After identity verification (1-2 business days), we will:
- Disable MFA for your account
- Send you a confirmation email
- Require you to set a new password on next login
- Recommend immediate re-enabling of MFA

Security Note: We implement a 1-2 day verification window
to protect against account takeover attempts.
```

#### Verification Checklist

Before disabling MFA via support ticket:

- [ ] Email from registered account address
- [ ] Account creation date verified (±2 weeks acceptable)
- [ ] Recent account activity verified
- [ ] No recent password changes (red flag)
- [ ] No suspicious login attempts in logs
- [ ] Identity verification questions answered correctly

---

## Security Considerations

### Why No Email Recovery Flow?

**Problem:** If email access alone can disable MFA, then MFA provides zero additional security.

An attacker with email access can:
1. Reset password via email (standard flow)
2. OR bypass MFA via recovery email (same security level)

Either path leads to full account compromise with just email access, defeating the purpose of MFA.

### Industry Standard Approach

| Company | Primary Recovery | Fallback Recovery |
|---------|------------------|-------------------|
| GitHub | Recovery codes | Support process (identity verification) |
| Google | Recovery codes | Phone number + waiting period (7 days) |
| AWS | Recovery codes | Support case + identity verification |
| 1Password | Recovery codes | None (by design - zero knowledge) |

**None allow instant MFA disable via email alone.**

### MFA Lockout vs Security Trade-offs

| Aspect | OneTime Approach | Reasoning |
|--------|------------------|-----------|
| Failure limit | 10 attempts | Prevents brute force, reasonable for 6-digit codes |
| Lockout duration | Permanent (until recovery) | Protects high-value secrets |
| Recovery codes | Yes (10 codes) | Industry standard self-service recovery |
| Email recovery | No | Would undermine MFA security model |
| Support recovery | Yes (with verification) | Necessary escape hatch for edge cases |

---

## User-Facing Documentation

### What is MFA and Why Use It?

Multi-factor authentication adds a second layer of security beyond your password. Even if someone steals your password, they can't access your account without your authenticator device.

### How to Avoid Lockouts

**When setting up MFA:**
1. Save your recovery codes immediately
2. Store codes in a password manager or secure location
3. Consider setting up multiple authenticator devices
4. Test that codes work before closing the setup screen

**Recommended authenticator apps:**
- Google Authenticator (simple, widely supported)
- Authy (supports cloud backup and multiple devices)
- 1Password (integrated with password manager)
- Microsoft Authenticator (supports cloud backup)

### What to Do If Locked Out

**If you have recovery codes:**
1. Click "Use recovery code instead" on the MFA screen
2. Enter one of your saved recovery codes
3. Access granted - proceed to account settings
4. Immediately generate new recovery codes
5. Set up MFA again with your authenticator

**If you lost everything:**
1. Contact support at support@onetimesecret.com
2. Include: account email, approximate signup date, recent activity
3. Wait for identity verification (1-2 business days)
4. Support will guide you through recovery process

---

## Technical Reference

### Database Schema

```sql
-- OTP keys table (TOTP secrets)
CREATE TABLE account_otp_keys (
  account_id integer PRIMARY KEY,
  key text NOT NULL,
  num_failures integer DEFAULT 0,
  last_use timestamp
);

-- Recovery codes table (single-use backup codes)
CREATE TABLE account_recovery_codes (
  account_id integer NOT NULL,
  code text NOT NULL,
  PRIMARY KEY (account_id, code)
);
```

### Operations Class Reference

**Location:** `apps/web/auth/operations/disable_mfa.rb`

**Dependencies:**
- `Auth::Database` - Sequel database connection
- `Onetime::Customer` - Customer model for validation
- Rodauth tables (`accounts`, `account_otp_keys`, `account_recovery_codes`)

**Public Methods:**

```ruby
# Instance method
operation = Auth::Operations::DisableMfa.new(email: 'user@example.com')
success = operation.call  # Returns boolean

# Class method (convenience)
Auth::Operations::DisableMfa.call('user@example.com')
```

**Return values:**
- `true` - MFA successfully disabled
- `false` - Operation failed (customer not found, no MFA setup, database error)

**Side effects:**
- Deletes rows from `account_otp_keys`
- Deletes rows from `account_recovery_codes`
- Logs operation to application logs
- Prints status to stdout (for console usage)

---

## Changelog

### Version 2.0 (2025-10-23)

**Removed:**
- Email-based MFA recovery flow (security vulnerability)
- All frontend components for email recovery
- `mfa-recovery-request` and related backend routes

**Added:**
- `Auth::Operations::DisableMfa` service class
- Console-based MFA reset capability
- Support process documentation
- Security analysis and industry comparison

**Changed:**
- Recovery codes are now the primary self-service method
- Updated documentation to reflect security-first approach

### Version 1.0 (2025-10-23)

**Initial implementation:**
- Email-based recovery flow (later removed)
- Integration with Rodauth email_auth
- Frontend recovery UI components

---

## Related Documentation

- [Rodauth OTP Feature](http://rodauth.jeremyevans.net/rdoc/files/doc/otp_rdoc.html)
- [Rodauth Recovery Codes](http://rodauth.jeremyevans.net/rdoc/files/doc/recovery_codes_rdoc.html)
- [OWASP MFA Guidelines](https://cheatsheetseries.owasp.org/cheatsheets/Multifactor_Authentication_Cheat_Sheet.html)
- `apps/web/auth/README-rodauth.md` - Rodauth configuration
- `docs/authentication/magic-link-mfa-flow.md` - Magic link authentication
