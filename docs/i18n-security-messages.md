# I18n Strategy for Security-Critical Authentication Messages

## Executive Summary

Authentication error messages require special handling because they must balance security (preventing information disclosure) with usability (helping legitimate users). This document proposes a robust i18n approach specifically for MFA and auth messages.

## Problem Statement

Unlike typical UI copy, security-critical error messages:
- **Must not leak information** about which credential failed, account existence, or precise timing
- **Cannot have creative translation** - semantic meaning must be identical across languages
- **Need security audit trail** - must be easy to review for compliance with OWASP/NIST guidelines
- **Require translator guidance** - translators need to understand WHY messages are generic

## Current State Analysis

```typescript
// Current approach in useMfa.ts (post-hardening):
error.value = 'Authentication failed. Please verify your credentials and try again.';
error.value = 'Too many attempts. Please try again later.';
```

### Existing i18n Structure
```json
{
  "web": {
    "auth": {
      "mfa": {
        "title": "Two-Factor Authentication",
        "invalid-code": "Invalid authentication code"  // ⚠️ Too specific!
      }
    }
  }
}
```

## Recommended Approach: Security Namespace with Semantic Keys

### 1. Create Dedicated Security Namespace

Use a special `web.auth.security.*` namespace that signals "these messages are security-critical":

```json
{
  "web": {
    "auth": {
      "security": {
        "_README": "⚠️ SECURITY-CRITICAL: These messages prevent information disclosure. Translations MUST maintain generic wording. See docs/i18n-security-messages.md",

        "authentication_failed": "Authentication failed. Please verify your credentials and try again.",
        "rate_limited": "Too many attempts. Please try again later.",
        "session_expired": "Session expired. Please log in again with your password.",
        "recovery_code_not_found": "Recovery code not found. Please verify you entered it correctly.",
        "recovery_code_used": "This recovery code has already been used. Each code can only be used once.",

        "_meta": {
          "authentication_failed": {
            "security_note": "MUST NOT reveal which credential failed (password, OTP, recovery code)",
            "owasp_ref": "ASVS 2.2.2 - Generic authentication failure messages"
          },
          "rate_limited": {
            "security_note": "MUST NOT reveal precise lockout duration or attempt count",
            "owasp_ref": "ASVS 2.2.1 - Account lockout not timing-based enumerable"
          }
        }
      },

      "mfa": {
        "title": "Two-Factor Authentication",
        "setup-title": "Set Up Two-Factor Authentication",

        "_format_guidance": {
          "otp_format": "OTP must be 6 digits",
          "recovery_code_format": "Recovery codes are 10 characters",
          "expected_behavior": "Codes expire every 30 seconds"
        }
      }
    }
  }
}
```

### 2. Update mapMfaError Helper

```typescript
// src/composables/helpers/mfaHelpers.ts

import { useI18n } from 'vue-i18n';

export function mapMfaError(statusCode: number, originalMessage?: string): string {
  const { t } = useI18n();

  switch (statusCode) {
    case 401:
      // Check if this is a session-specific message (safe to preserve)
      if (originalMessage?.toLowerCase().includes('session')) {
        return t('web.auth.security.session_expired');
      }
      // Generic authentication failure - don't reveal which credential failed
      return t('web.auth.security.authentication_failed');

    case 403:
      // Forbidden - same generic message, no hints about authorization vs authentication
      return t('web.auth.security.authentication_failed');

    case 404:
      // Recovery code not found - safe to indicate it's about recovery codes
      return t('web.auth.security.recovery_code_not_found');

    case 410:
      // Recovery code already used - safe expected behavior message
      return t('web.auth.security.recovery_code_used');

    case 429:
      // Rate limiting - DO NOT reveal precise timing ("wait 5 minutes")
      return t('web.auth.security.rate_limited');

    default:
      // For other status codes, return original message or generic error
      return originalMessage || t('web.COMMON.unexpected_error');
  }
}
```

### 3. Update useMfa.ts Composable

```typescript
// src/composables/useMfa.ts

import { useI18n } from 'vue-i18n';
import { mapMfaError } from './helpers/mfaHelpers';

export function useMfa() {
  const { t } = useI18n();
  const error = ref<string | null>(null);

  // Configure async handler for auth-specific pattern
  const { wrap } = useAsyncHandler({
    notify: false, // Don't auto-notify - MFA shows errors inline
    setLoading: (loading) => (isLoading.value = loading),
    onError: (err: ApplicationError) => {
      error.value = null;

      // Use the mapMfaError helper for security-hardened, i18n messages
      const statusCode = typeof err.code === 'number' ? err.code : null;
      if (statusCode) {
        error.value = mapMfaError(statusCode, err.message);
      } else {
        error.value = err.message;
      }
    },
  });

  // ... rest of composable
}
```

## Why This Approach?

### ✅ Advantages

1. **Clear Security Boundary**
   - `web.auth.security.*` namespace signals "special handling required"
   - `_README` and `_meta` fields document security requirements inline
   - Easy to audit which messages are security-critical

2. **Developer Experience**
   - Key names are semantic: `authentication_failed` vs `auth_fail_001`
   - Type safety with TypeScript + vue-i18n
   - Centralized in `mapMfaError()` helper
   - Easy to search codebase for security-critical messages

3. **Translator Guidance**
   - `_README` warns translators about special requirements
   - `_meta` explains WHY each message must be generic
   - OWASP references provide authoritative guidance
   - Separate `_format_guidance` for safe informational messages

4. **Maintainability**
   - All 30+ language files inherit same structure
   - Changes propagate through single source of truth
   - Translation validation can enforce security requirements
   - Git diffs show exact message changes

5. **Security Audit Trail**
   - Each message documents which information it must NOT reveal
   - OWASP/NIST references for compliance
   - Easy to review in security audits
   - Inline documentation survives refactoring

### ❌ Why NOT Use Full English as Key?

While `t("Authentication failed. Please verify your credentials and try again.")` works technically:

- **No semantic meaning** - can't tell what the key represents from code
- **Difficult to refactor** - changing English changes all translations
- **Hard to find usage** - can't grep for `authentication_failed`
- **No metadata** - can't attach security notes or OWASP refs
- **Harder to validate** - tooling can't check translation compliance

## Alternative Considered: Hybrid Full-English Keys

If you strongly prefer full-English keys for these specific messages:

```typescript
// Use English as key, but in security namespace
const SECURITY_MESSAGES = {
  'Authentication failed. Please verify your credentials and try again.': 'web.auth.security.generic',
  'Too many attempts. Please try again later.': 'web.auth.security.rate_limit',
  // ... etc
} as const;

export function mapMfaError(statusCode: number, originalMessage?: string): string {
  const { t } = useI18n();
  const englishMessage = getEnglishMessage(statusCode, originalMessage);

  // Use English message as key, falls back to English if translation missing
  return t(englishMessage, englishMessage);
}
```

**Pros**: English message is always visible in code
**Cons**: Loses semantic meaning, harder to maintain, no metadata

## Translation Guidelines Document

Create `docs/i18n-translation-guidelines.md`:

```markdown
# Translation Guidelines for Security Messages

## Security-Critical Messages (`web.auth.security.*`)

These messages are **security-critical** and must follow strict guidelines:

### DO NOT Translate These As
❌ "Wrong password" - reveals which credential failed
❌ "Invalid OTP code" - reveals which credential failed
❌ "Wait 5 minutes" - reveals precise timing
❌ "3 attempts remaining" - reveals attack progress

### MUST Translate As
✅ Generic authentication failure
✅ "Try again later" (no specific time)
✅ No mention of which credential failed
✅ No attempt counts or remaining attempts

### Why?
These restrictions prevent attackers from:
- Determining valid usernames/emails (enumeration)
- Knowing which credential to focus attacks on
- Timing attacks based on precise lockout durations
- Measuring attack progress via attempt counters

### Safe Information
You CAN provide:
- Format requirements ("OTP must be 6 digits")
- Expected behavior ("Codes expire every 30 seconds")
- Recovery instructions ("Use a recovery code instead")
- General guidance ("Check your authenticator app")
```

## Implementation Checklist

- [ ] Create `web.auth.security` namespace in `src/locales/en.json`
- [ ] Add `_README` and `_meta` documentation fields
- [ ] Update `mapMfaError()` to use `useI18n().t()`
- [ ] Update `useMfa.ts` to use i18n-enabled `mapMfaError()`
- [ ] Create `docs/i18n-translation-guidelines.md`
- [ ] Add i18n extraction script to CI (extract security keys)
- [ ] Create translation validation script (check for info disclosure)
- [ ] Update all 30+ language files with security namespace
- [ ] Add security message audit to PR review checklist

## Testing Strategy

```typescript
// src/tests/i18n/security-messages.spec.ts

describe('Security Message Compliance', () => {
  const forbiddenPatterns = [
    /password/i,
    /otp/i,
    /code/i,
    /wait \d+ (minute|second)/i,
    /\d+ attempt/i,
    /incorrect/i,
    /invalid/i,
    /wrong/i,
  ];

  it('should not reveal credential-specific information', () => {
    const securityMessages = getAllSecurityMessages();

    securityMessages.forEach(([key, message]) => {
      forbiddenPatterns.forEach(pattern => {
        expect(message).not.toMatch(pattern);
      }, `Message "${key}" contains forbidden pattern: ${message}`);
    });
  });

  it('should not reveal precise timing information', () => {
    const message = t('web.auth.security.rate_limited');
    expect(message).not.toMatch(/\d+\s*(minute|second|hour)/i);
  });
});
```

## Rollout Plan

### Phase 1: English Only (Current)
- Implement security namespace in `en.json`
- Update composables to use i18n
- Add tests for security compliance

### Phase 2: Translation Infrastructure
- Add extraction scripts
- Add validation scripts
- Document translation guidelines

### Phase 3: Translate
- Add security namespace to all 30+ language files
- Work with translators using guidelines
- Validate translations with automated checks

### Phase 4: Monitoring
- Log when security messages are shown (analytics)
- Monitor for suspicious patterns (rapid auth failures)
- Regular security audits of message content

## Conclusion

The **dedicated security namespace approach** (`web.auth.security.*`) provides the best balance of:
- Security audibility
- Developer experience
- Translator guidance
- Maintainability
- Type safety

It makes security requirements explicit, provides inline documentation, and creates a clear audit trail while maintaining the semantic clarity that dot-notation keys provide.
