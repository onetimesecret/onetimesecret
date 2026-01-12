# Locale Key Analysis: auth.json

## File Overview

The `auth.json` file contains 79 lines organized under `web.*` namespace with the following key categories:

| Category | Path | Key Count | Description |
|----------|------|-----------|-------------|
| Login | `web.login.*` | 6 | Sign-in form labels and navigation |
| Signup | `web.signup.*` | 5 | Account creation form and errors |
| Email Verification | `web.auth.verify.*` | 16 | Email verification flow messages |
| Password Change | `web.auth.change-password.*` | 5 | Password update form |
| Account Closure | `web.auth.close-account.*` | 5 | Account deletion confirmation |
| Password Reset | `web.auth.passwordReset.*` | 1 | Password reset email notification |
| Account Dashboard | `web.auth.account.*` | 16 | Account overview/info display |

## Potentially Misplaced Keys

### 1. Account Dashboard Section (`web.auth.account.*`)

**Current Location:** `auth.json` at `web.auth.account.*`

**Issue:** These keys describe account information display (dashboard), not authentication. The `account.json` file already exists with `web.account.*` and `web.settings.*` namespaces that handle account-related content.

**Recommended Destination:** `account.json`

| Key | Reasoning |
|-----|-----------|
| `web.auth.account.title` | Account info display, not auth flow |
| `web.auth.account.email` | User profile display |
| `web.auth.account.created` | Account metadata display |
| `web.auth.account.verified` | Status display (not verification action) |
| `web.auth.account.region` | Account setting display |
| `web.auth.account.not-verified` | Status indicator |
| `web.auth.account.verify-email` | Action link (could stay in auth) |
| `web.auth.account.mfa-status` | Security status display |
| `web.auth.account.mfa-enabled` | Status indicator |
| `web.auth.account.mfa-disabled` | Status indicator |
| `web.auth.account.active-sessions` | Session management display |
| `web.auth.account.session-count` | Display formatting |
| `web.auth.account.quick-actions` | UI section header |
| `web.auth.account.manage-mfa` | Navigation link |
| `web.auth.account.manage-sessions` | Navigation link |
| `web.auth.account.change-password` | Navigation link |
| `web.auth.account.close-account` | Navigation link |

**Migration Path:**
- Move to `account.json` under `web.account.overview.*` or `web.account.dashboard.*`
- Update references in Vue components

### 2. Close Account Section (`web.auth.close-account.*`)

**Current Location:** `auth.json`

**Issue:** Account closure is an account management action, not an authentication flow. Similar keys already exist in `account.json` under `web.account.*` (lines 42-55).

**Recommended Destination:** `account.json` under `web.account.close-account.*` or consolidate with existing deletion keys

**Duplicate Detection:**
- `account.json` already has: `delete-account`, `deactivate-account`, `confirm-account-deletion`, `permanently-delete-account`
- These overlap semantically with `auth.json`'s close-account section

### 3. Change Password Section (`web.auth.change-password.*`)

**Current Location:** `auth.json`

**Issue:** `account.json` already has `web.account.changePassword.*` (lines 20-27) and `web.settings.password.*` (lines 98-101).

**Recommended Action:** Consolidate into `account.json`. The form field labels in auth.json are more detailed; merge and deduplicate.

## Hierarchy Improvements

### Current Structure Issues

1. **Inconsistent Nesting Depth:**
   - `web.login.*` (2 levels)
   - `web.auth.verify.*` (3 levels)
   - `web.auth.account.*` (3 levels)

2. **Mixed Concerns Under `web.auth`:**
   - Email verification (auth-related)
   - Password reset (auth-related)
   - Account dashboard (not auth-related)
   - Account closure (not auth-related)

### Recommended Structure

```
auth.json (pure authentication concerns):
  web.auth.login.*          # Sign-in form
  web.auth.signup.*         # Account creation
  web.auth.verify.*         # Email verification
  web.auth.password-reset.* # Password reset flow
  web.auth.mfa.*            # Two-factor authentication flows
```

**Proposed Moves:**
| Current Path | New File | New Path |
|--------------|----------|----------|
| `web.login.*` | auth.json | `web.auth.login.*` |
| `web.signup.*` | auth.json | `web.auth.signup.*` |
| `web.auth.account.*` | account.json | `web.account.overview.*` |
| `web.auth.close-account.*` | account.json | `web.account.close-account.*` |
| `web.auth.change-password.*` | account.json | `web.account.change-password.*` |

## New File Suggestions

### Consider: `mfa.json` or `security.json`

If MFA (two-factor authentication) flows grow, consider:
- `web.mfa.setup.*` - Initial MFA configuration
- `web.mfa.verify.*` - MFA code entry during login
- `web.mfa.recovery.*` - Recovery code usage
- `web.mfa.disable.*` - Turning off MFA

Currently the MFA keys are scattered:
- `auth.json`: `web.auth.account.mfa-status`, `manage-mfa`, `mfa-enabled`, `mfa-disabled`
- `account.json`: `web.settings.security.*` (recovery codes, enable-mfa-recommendation)

A dedicated `security.json` could unify:
- MFA setup/management
- Recovery codes
- Session management
- Security score/recommendations

## Summary of Recommendations

| Priority | Action | Files Affected |
|----------|--------|----------------|
| High | Move `web.auth.account.*` to `account.json` | auth.json, account.json |
| High | Move `web.auth.close-account.*` to `account.json` | auth.json, account.json |
| Medium | Move `web.auth.change-password.*` to `account.json` | auth.json, account.json |
| Medium | Rename `web.login.*` to `web.auth.login.*` | auth.json |
| Medium | Rename `web.signup.*` to `web.auth.signup.*` | auth.json |
| Low | Consider `security.json` for MFA/session keys | New file |

## Duplicate Key Audit

Keys that exist in both files (semantic duplicates):

| auth.json | account.json | Resolution |
|-----------|--------------|------------|
| `web.auth.close-account.title` | `web.account.close-account` | Keep account.json |
| `web.auth.close-account.cancel` | (use common) | Move to `_common.json` |
| `web.auth.change-password.title` | `web.account.change-password` | Keep account.json |
| `web.auth.change-password.current-password` | `web.account.changePassword.currentPassword` | Consolidate |
| `web.auth.change-password.new-password` | `web.account.changePassword.newPassword` | Consolidate |
| `web.auth.change-password.confirm-password` | `web.account.changePassword.confirmPassword` | Consolidate |

## File Purpose After Cleanup

**auth.json should contain:**
- Login form (credentials entry, remember me, forgot password)
- Signup form (create account, terms acceptance)
- Email verification flow (success, error, resend)
- Password reset flow (request, email sent, reset form)
- Session authentication errors

**account.json should contain:**
- Account overview/dashboard display
- Profile settings
- Password change form
- Account deletion/closure
- Notification preferences
- API key management
