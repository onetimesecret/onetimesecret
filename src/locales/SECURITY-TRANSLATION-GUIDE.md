# Security-Critical Message Translation Guide

**⚠️ IMPORTANT**: This guide is for translating authentication error messages in the `web.auth.security.*` namespace. These messages are different from normal UI text because they must prevent information disclosure to attackers.

## About This Document

- **This guide itself**: Keep in **English** (canonical version). Translation teams may create localized copies (e.g., `SECURITY-TRANSLATION-GUIDE.es.md`) if helpful, but English is the authoritative source.
- **Status**: English is canonical; translations are optional and at team discretion.

## Why These Messages Are Special

Unlike regular UI copy, security-critical authentication messages:
- **Must NOT reveal** which credential failed (password, OTP, recovery code)
- **Must NOT reveal** precise timing (e.g., "wait 5 minutes")
- **Must NOT reveal** attempt counts (e.g., "3 attempts remaining")
- **Must NOT reveal** account existence
- **Cannot be creatively reworded** - semantic meaning must be identical across languages

**These restrictions follow OWASP/NIST security guidelines to prevent:**
- **Credential enumeration** - attackers determining valid usernames/emails
- **Timing attacks** - using precise lockout durations to probe accounts
- **Progress tracking** - measuring attack progress via attempt counters

## Security Messages in This Project

All security-critical messages are in the `web.auth.security.*` namespace with inline documentation:

```json
{
  "web": {
    "auth": {
      "security": {
        "_README": "⚠️ SECURITY-CRITICAL: See src/locales/SECURITY-TRANSLATION-GUIDE.md",

        "authentication_failed": "Authentication failed. Please verify your credentials and try again.",
        "rate_limited": "Too many attempts. Please try again later.",
        "session_expired": "Session expired. Please log in again.",

        "_meta": {
          "authentication_failed": {
            "security_note": "MUST NOT reveal which credential failed",
            "owasp_ref": "ASVS 2.2.2"
          }
        }
      }
    }
  }
}
```

### ⚠️ DO NOT Translate Keys Starting with Underscore

Keys prefixed with `_` are **metadata for documentation only**:
- `_README` - Warning for translators (keep in English)
- `_meta` - Security notes with OWASP references (keep in English)
- `_translation_guidelines` - Rules for translators (keep in English)
- `_safe_information` - Documentation (keep in English)

**These are NOT displayed to users.** Leave them in English in all locale files. Vue-i18n ignores these keys by convention.

## Translation Rules

### ❌ DO NOT Translate As

These translations would reveal information to attackers:

| **NEVER Say** | **Why It's Dangerous** |
|---------------|------------------------|
| "Wrong password" | Reveals which credential failed |
| "Invalid OTP code" | Reveals which credential failed |
| "Incorrect recovery code" | Reveals which credential failed |
| "Wait 5 minutes" | Reveals precise lockout timing |
| "Try again in 15 minutes" | Enables timing attacks |
| "3 attempts remaining" | Shows attack progress |
| "Account locked for 30 minutes" | Reveals timing and confirms account |
| "Account does not exist" | Enables account enumeration |
| "Email not found" | Enables account enumeration |

### ✅ MUST Translate As

Keep translations **generic and helpful**:

| **English** | **Translation Principle** |
|-------------|---------------------------|
| "Authentication failed. Please verify your credentials and try again." | Generic failure - no credential specifics |
| "Too many attempts. Please try again later." | Rate limit - no precise timing |
| "Session expired. Please log in again." | Session timeout - safe to indicate |
| "Recovery code not found. Please verify you entered it correctly." | Recovery code validation - no existence confirmation |
| "This recovery code has already been used." | Expected behavior - educates user |

### ✅ Safe Information You CAN Include

Some information is **safe and helpful** to provide:

- **Format requirements**: "OTP must be 6 digits"
- **Expected behavior**: "Codes expire every 30 seconds"
- **Recovery options**: "Use a recovery code instead"
- **General guidance**: "Check your authenticator app"
- **How features work**: "Each recovery code can only be used once"

These don't reveal attack-relevant information but help legitimate users.

## Examples by Language

### Good Translations (Generic)

**Spanish:**
```json
"authentication_failed": "La autenticación falló. Por favor verifica tus credenciales e intenta de nuevo."
```

**French:**
```json
"authentication_failed": "L'authentification a échoué. Veuillez vérifier vos identifiants et réessayer."
```

**German:**
```json
"authentication_failed": "Authentifizierung fehlgeschlagen. Bitte überprüfen Sie Ihre Anmeldedaten und versuchen Sie es erneut."
```

### Bad Translations (Too Specific) ❌

**Spanish (BAD):**
```json
"authentication_failed": "Contraseña incorrecta"  // ❌ Reveals password failed
```

**French (BAD):**
```json
"rate_limited": "Trop de tentatives. Attendez 5 minutes."  // ❌ Reveals timing
```

**German (BAD):**
```json
"authentication_failed": "Falscher OTP-Code"  // ❌ Reveals OTP failed
```

## Message-by-Message Guide

### `authentication_failed`
**English:** "Authentication failed. Please verify your credentials and try again."

**Rules:**
- ✅ Say "authentication" or "login" failed
- ✅ Suggest verifying "credentials" (generic)
- ❌ Do NOT mention password, OTP, code, or any specific credential
- ❌ Do NOT say "incorrect", "wrong", or "invalid"

**Why:** Used for both password AND OTP failures. Must not reveal which one failed.

---

### `rate_limited`
**English:** "Too many attempts. Please try again later."

**Rules:**
- ✅ Say "too many attempts" or "rate limited"
- ✅ Say "later" or "shortly" (vague time)
- ❌ Do NOT include numbers (5 minutes, 15 minutes, etc.)
- ❌ Do NOT say "wait X time" with specific duration

**Why:** Precise timing enables attack synchronization and timing attacks.

---

### `session_expired`
**English:** "Session expired. Please log in again."

**Rules:**
- ✅ Safe to say "session expired" or "session timeout"
- ✅ Direct user to log in again
- ❌ Do NOT mention specific credentials needed

**Why:** Session expiration doesn't reveal credential information.

---

### `recovery_code_not_found`
**English:** "Recovery code not found. Please verify you entered it correctly."

**Rules:**
- ✅ Safe to mention "recovery code" (user selected this method)
- ✅ Suggest verifying input for typos
- ❌ Do NOT say "does not exist" or "invalid code"
- ❌ Do NOT confirm whether code is in system

**Why:** User explicitly chose recovery code auth, but we don't confirm existence.

---

### `recovery_code_used`
**English:** "This recovery code has already been used. Each code can only be used once."

**Rules:**
- ✅ Safe to explain single-use behavior
- ✅ Safe to educate about recovery code rules
- ❌ Do NOT reveal how many codes remain

**Why:** Explaining expected behavior helps legitimate users without aiding attackers.

## Validation

Your translations will be validated by automated tests that check for:
- Forbidden patterns (password, otp, specific timing)
- Attack progress indicators (attempt counts)
- Account enumeration risks (existence confirmation)

Run the validation:
```bash
pnpm test:unit security-messages
```

## Questions?

If you're unsure about a translation:

1. **Check the `_meta` field** in the JSON for that specific message
2. **When in doubt, be MORE generic** - safer to be vague than specific
3. **Ask maintainers** before publishing if you need clarification

## Key Principle

**"Generic enough to prevent attacks, specific enough to help users."**

If your translation would help an attacker distinguish between:
- Valid vs. invalid accounts
- Which credential failed
- When to retry an attack
- How many attempts they have left

...then it's too specific. Make it more generic.

## References

- OWASP ASVS 2.2.2 - Generic authentication failure messages
- OWASP ASVS 2.2.1 - Account lockout not timing-based enumerable
- NIST SP 800-63B - Authentication and Lifecycle Management

---

**Remember:** These messages protect user accounts from attackers. Thank you for helping keep our users secure! 🔒
