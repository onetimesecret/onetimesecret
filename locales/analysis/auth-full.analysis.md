# auth-full.json Key Structure Analysis

## File Overview

The `auth-full.json` file contains keys under `web.auth.*` organized into the following categories:

| Category | Key Path | Purpose |
|----------|----------|---------|
| MFA Page Headers | `web.auth.mfa_required`, `mfa_verification_required`, `complete_mfa_verification` | Top-level page content for MFA verification screens |
| Security Messages | `web.auth.security.*` | OWASP-compliant error messages with extensive metadata |
| Auth Methods | `web.auth.methods.*` | Authentication method labels (password, magicLink, webauthn) |
| Magic Link | `web.auth.magicLink.*` | Passwordless email authentication flow |
| WebAuthn | `web.auth.webauthn.*` | Biometric/passkey authentication |
| Account Lockout | `web.auth.lockout.*` | Brute-force protection messages |
| Sessions | `web.auth.sessions.*` | Active session management UI |
| MFA Setup | `web.auth.mfa.*` | Two-factor authentication setup/management |
| Recovery Codes | `web.auth.recovery-codes.*` | MFA recovery code management |

---

## Potentially Misplaced Keys

### 1. Sessions Management (`web.auth.sessions.*`)

**Current location:** `auth-full.json` under `web.auth.sessions`

**Issue:** Sessions management is an account management feature, not an authentication flow. It appears in the account settings area alongside other account management features.

**Recommended destination:** `account.json` under `web.settings.sessions` (note: `account.json` already has a stub at `web.settings.sessions` with 3 keys)

**Keys to move:**
- `sessions.title`
- `sessions.current`
- `sessions.other`
- `sessions.device`
- `sessions.location`
- `sessions.ip-address`
- `sessions.last-active`
- `sessions.created`
- `sessions.remove`
- `sessions.remove-all`
- `sessions.confirm-remove`
- `sessions.confirm-remove-all`
- `sessions.no-sessions`
- `sessions.removed-success`
- `sessions.removed-all-success`
- `sessions.link-title`

---

### 2. MFA Management (`web.auth.mfa.*` and `web.auth.recovery-codes.*`)

**Current location:** `auth-full.json` under `web.auth.mfa` and `web.auth.recovery-codes`

**Issue:** This file conflates two distinct contexts:
1. **MFA Verification** (during login) - belongs in auth flow
2. **MFA Setup/Management** (in account settings) - belongs in account/settings

**Recommended split:**

#### Keys that belong in auth (login-time verification):
- `mfa.title` (when used as login page title)
- `mfa.verify-code`
- `mfa.enter-code`
- `mfa.verify`
- `mfa.code-required`
- `mfa.invalid-code`
- `mfa.use-recovery-code`
- `mfa.back-to-code`
- `mfa.cancel`
- `mfa.enter-recovery-code`
- `mfa.recovery-code-label`
- `mfa.recovery-code-placeholder`
- `mfa.verify-recovery-code`
- `mfa.six-digit-code`
- `mfa.recovery-code-mode-active`
- `mfa.otp-mode-active`
- `mfa.enter-all-digits`
- `mfa.digit-of-count`

#### Keys that belong in `account.json` (settings-time management):
- `mfa.enabled`
- `mfa.disabled`
- `mfa.enable`
- `mfa.disable`
- `mfa.setup-title`
- `mfa.setup-description`
- `mfa.step-scan`
- `mfa.step-verify`
- `mfa.scan-qr`
- `mfa.manual-entry`
- `mfa.success-enabled`
- `mfa.success-disabled`
- `mfa.require-password`
- `mfa.password-confirmation`
- `mfa.password-reason`
- `mfa.last-used`
- `mfa.never-used`
- `mfa.loading-status`
- `mfa.protected-description`
- `mfa.enable-description`
- `mfa.benefit-*` (all benefit keys)
- `mfa.password-placeholder`
- `mfa.disabling`
- `mfa.disable-button`
- `mfa.generating-qr`
- `mfa.supported-apps`
- `mfa.continue-verification`
- `mfa.enter-code-description`
- `mfa.enable-and-continue`
- `mfa.complete-setup`
- All `recovery-codes.*` keys (these are settings, not login flow)

---

### 3. Account Lockout (`web.auth.lockout.*`)

**Current location:** `auth-full.json`

**Assessment:** Appropriately placed. Lockout messages appear during authentication attempts.

**No action needed.**

---

## Suggested Hierarchy Improvements

### 1. Flatten Top-Level MFA Keys

**Current:**
```json
"web.auth.mfa_required": "...",
"web.auth.mfa_verification_required": "...",
"web.auth.complete_mfa_verification": "..."
```

**Suggested:** Move under a proper namespace:
```json
"web.auth.mfa.page_title": "...",
"web.auth.mfa.page_subtitle": "...",
"web.auth.mfa.submit_button": "..."
```

This maintains consistency with the nested structure used elsewhere.

---

### 2. Security Metadata Structure

**Current:** The `web.auth.security._meta.*` structure contains extensive security documentation inline with the translations.

**Issue:** These `_meta`, `_translation_guidelines`, and `_safe_information` keys are documentation, not translations. They add ~40 lines of non-translatable content.

**Suggested:**
1. Extract security documentation to `src/locales/SECURITY-TRANSLATION-GUIDE.md` (which already exists and is referenced)
2. Keep only actual message keys in the JSON
3. Use `_context_*` prefix pattern for brief translator hints (already used elsewhere in file)

**Simplified structure:**
```json
"security": {
  "_README": "See SECURITY-TRANSLATION-GUIDE.md",
  "authentication_failed": "...",
  "rate_limited": "...",
  "session_expired": "...",
  "recovery_code_not_found": "...",
  "recovery_code_used": "...",
  "network_error": "...",
  "internal_error": "..."
}
```

---

### 3. Consistent Key Naming

**Issue:** Mixed naming conventions within the file:

| Pattern | Examples |
|---------|----------|
| snake_case | `mfa_required`, `mfa_verification_required` |
| camelCase | `magicLink`, `webauthn` |
| kebab-case | `attempts-remaining`, `account-locked`, `ip-address` |

**Recommended:** Standardize on kebab-case to match the majority of the codebase's locale files.

---

## New File Suggestions

### 1. Consider: `auth-security.json`

If the security-critical messages with their extensive metadata must stay together for audit purposes, extract them to a dedicated file:

**Path:** `src/locales/en/auth-security.json`

**Contents:**
- `web.auth.security.*` (all security messages)
- Associated `_meta` documentation (if retained)

**Rationale:** These messages follow strict OWASP/NIST guidelines and require special attention during translation review. Isolation makes auditing easier.

---

### 2. Consider: Merge remaining auth keys

After extracting sessions and MFA management to `account.json`, consider merging the remaining login-flow keys from `auth-full.json` into `auth.json`.

**Current state:**
- `auth.json` has: login, signup, verify, change-password, close-account, passwordReset, account info
- `auth-full.json` has: MFA verification, security messages, auth methods, magic link, webauthn, lockout

**Proposed structure in merged `auth.json`:**
```
web.login.*           (existing)
web.signup.*          (existing)
web.auth.verify.*     (existing)
web.auth.security.*   (from auth-full)
web.auth.methods.*    (from auth-full)
web.auth.magicLink.*  (from auth-full)
web.auth.webauthn.*   (from auth-full)
web.auth.lockout.*    (from auth-full)
web.auth.mfa.*        (login-time MFA verification only)
```

---

## Summary of Recommended Actions

| Priority | Action | Source | Destination |
|----------|--------|--------|-------------|
| High | Move sessions management keys | `auth-full.json` | `account.json` |
| High | Move MFA setup/management keys | `auth-full.json` | `account.json` |
| Medium | Move recovery-codes keys | `auth-full.json` | `account.json` |
| Medium | Flatten top-level MFA keys | `auth-full.json` | Restructure in place |
| Low | Standardize key naming to kebab-case | `auth-full.json` | In place |
| Low | Extract security metadata to docs | `auth-full.json` | `SECURITY-TRANSLATION-GUIDE.md` |
| Optional | Create `auth-security.json` | `auth-full.json` | New file |
| Optional | Merge with `auth.json` | `auth-full.json` | `auth.json` |

---

## File Statistics

- **Total keys:** ~85 translatable strings
- **Metadata/context keys:** ~35 (prefixed with `_`)
- **Categories:** 9 distinct feature areas
- **Naming inconsistencies:** 3 different conventions in use
