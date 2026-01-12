# UX Translation Guide

Guidelines for translating UI text while maintaining excellent user experience across languages.

## Guideline Priority Framework

### Requirement Levels (RFC 2119)

- **MUST/REQUIRED**: Mandatory, no exceptions
- **SHOULD/RECOMMENDED**: Best practice, may deviate with documented reason
- **MAY/OPTIONAL**: Suggested, use judgment

### Priority Hierarchy

When guidelines conflict, apply in order:

1. **[P0] Security & Privacy** - See `SECURITY-TRANSLATION-GUIDE.md`
   - Generic auth errors MUST NOT reveal credential details
   - Rate limit messages MUST NOT expose timing/attempt counts

2. **[P1] Accessibility** - WCAG 2.1 AA compliance
   - Destructive actions MUST include object ("Delete Account" not "Delete")
   - Button labels MUST be descriptive in context

3. **[P2] Functional Accuracy**
   - Variables MUST be preserved exactly
   - Pluralization MUST use vue-i18n syntax

4. **[P3] User Experience**
   - Button text SHOULD respect character limits
   - Context SHOULD clarify action

5. **[P4] Style & Brand**
   - Voice SHOULD follow style guide
   - Terminology SHOULD be consistent

### Conflict Resolution Examples

**Security vs Clarity:**
```
Conflict: Specific error ("Wrong password") vs generic ("Authentication failed")
Resolution: P0 > P3 → Use generic error + safe contextual help
Example: "Authentication failed. Please verify your credentials."
```

**Character Limit vs Clarity:**
```
Conflict: "Permanently Close Account" (too long) vs clarity
Resolution: P3 pattern → Use heading + concise button
Example: Heading "Close Account" + warning text + button "Close Account"
```

**Abbreviation vs First-time Users:**
```
Conflict: "Enable MFA" (short) vs "Enable Two-Factor Authentication" (clear)
Resolution: P3 context → Use full term in heading, abbreviation in button
Example: Section titled "Two-Factor Authentication" + button "Enable MFA"
```

## Button Text Strategy

### Core Principle: Context + Concise Action

Use surrounding UI elements (headings, descriptions, icons) to provide context, allowing shorter, more translatable button text.

**Pattern:**
```
Section Heading: "Close Account"
Description: "This action cannot be undone. All your secrets will be permanently deleted."
Button: "Close Account"
```

Not:
```
Button alone: "Permanently Close Account"
```

### Button Text Length Guidelines

**Target lengths (English):**
- Primary actions: 8-15 characters
- Secondary actions: 10-20 characters
- Destructive actions: Include object (10-20 chars)

**Translation expansion estimates:**
- German/Russian: +30-35%
- French/Spanish: +15-20%
- Japanese/Chinese: -10-30% (contraction)

### Critical vs Generic Actions

**Destructive/irreversible actions MUST include object:**
- "Delete Account" not "Delete"
- "Close Account" not "Close"
- "Remove All Sessions" not "Remove All"

**Data operations SHOULD include object:**
- "Save Changes" not "Save"
- "Export Data" not "Export"

**Generic actions MAY be used when context is clear:**
- Multi-step flows: "Continue", "Next", "Back"
- Modal confirmations: "Confirm", "Cancel"
- Simple toggles: "Enable", "Disable" (when in titled section)

## Recommended Button Text Patterns

### Authentication & Account Actions

| Context | Original | Recommended | Reasoning |
|---------|----------|-------------|-----------|
| Account closure modal | "Permanently Close Account" | "Close Account" | Modal heading + warning provide permanence context |
| MFA verification step | "Complete MFA Verification" | "Verify and Continue" | Step flow provides context |
| MFA settings section | "Manage Two-Factor Authentication" | "Manage 2FA" | Within 2FA section, abbreviation clear |
| Recovery codes section | "Generate New Codes" | "Generate Codes" | "New" implied by regenerate action |
| Password change form | "Change Password" | "Change Password" | ✓ Clear and concise |
| Session management | "Logout All Other Sessions" | "Remove All Sessions" | Action-oriented, "other" implied |

### Form Actions

**Standard pattern:**
- Primary: Specific action verb + object ("Save Changes", "Create Secret")
- Secondary: "Cancel"
- Tertiary: Context-appropriate ("Reset", "Clear Form")

### Navigation & Links

**Links can be more descriptive** (not constrained by button sizing):
- "Manage Two-Factor Authentication" ✓
- "View Active Sessions" ✓
- "Download Recovery Codes" ✓

## Character Limits by Component

### Strict Limits
- Toast notifications: 60 characters
- Mobile menu items: 20 characters
- Tab labels: 15 characters
- Button text (mobile): 15 characters

### Flexible Limits
- Button text (desktop): 25 characters
- Form labels: 30 characters
- Card titles: 40 characters
- Section headings: 50 characters

## Pluralization

**Countable items MUST use vue-i18n pipe syntax:**

```json
// ❌ Wrong - cannot translate to languages with multiple plural forms
"session-count": "{count} active session(s)"

// ✅ Correct - supports all language plural rules
"session-count": "{count} active session | {count} active sessions"
```

**Languages affected:**
- Russian: 3 forms (one, few, many)
- Arabic: 6 forms (zero, one, two, few, many, other)
- Polish: 3 forms (one, few, many)

## Abbreviation Usage

### When to Abbreviate

**Abbreviations MAY be used:**
- In button text when space-constrained: "Manage 2FA"
- In technical contexts: "MFA status", "OTP code"
- Within titled sections using full term

**Full terms SHOULD be used:**
- First use in new context: "Two-Factor Authentication (2FA)"
- Primary headings: "Two-Factor Authentication"
- Descriptions and help text
- Error messages

### Standard Abbreviations

| Term | Abbreviation | First Use | Subsequent |
|------|--------------|-----------|------------|
| Two-Factor Authentication | 2FA or MFA | Spell out | Abbreviate in buttons/labels |
| One-Time Password | OTP | Spell out | Abbreviate in technical contexts |
| Multi-Factor Authentication | MFA | Spell out | Abbreviate in buttons/labels |

**Note:** Choose either "2FA" or "MFA" and use consistently throughout the application. Current codebase uses "MFA" in keys, recommend standardizing on "MFA".

## Voice and Tone

### Button Labels SHOULD use active/imperative voice
- "Sign In" (imperative)
- "Delete Account" (imperative)
- "Send Login Link" (imperative)

### Status Messages SHOULD use passive/declarative voice
- "Account verified successfully"
- "Session removed"
- "Changes saved"

### Error Messages SHOULD use declarative voice
- "Authentication failed. Please verify your credentials."
- "Invalid verification code"
- "Session expired. Please log in again."

## Context for Translators

### Include Usage Context

**Add description comments for ambiguous strings:**

```json
// ❌ Insufficient context
"required": "Required"

// ✅ Clear context
"field-required": "Required", // Form validation - appears next to input field
"mfa-required": "Two-factor authentication required" // Page title - user must verify MFA
```

### Security-Critical Messages (P0)

Security messages MUST remain generic to prevent information disclosure. See `SECURITY-TRANSLATION-GUIDE.md` for:
- Authentication failures (MUST NOT reveal which credential failed)
- Rate limiting (MUST NOT expose timing/attempt counts)
- Account enumeration prevention

## Testing Translations

### Visual Testing Checklist

- [ ] Button text fits on mobile screens
- [ ] No text overflow in form labels
- [ ] Multi-line text properly formatted
- [ ] Icon + text alignment maintained
- [ ] Modal widths accommodate longer text
- [ ] Navigation items don't wrap awkwardly

### Languages to Test

**Priority 1 (longest expansions):**
- German (de)
- Russian (ru)

**Priority 2 (moderate expansions):**
- French (fr)
- Spanish (es)

**Priority 3 (contractions):**
- Japanese (ja)
- Chinese (zh)

## Resources

- **Security guidance:** `SECURITY-TRANSLATION-GUIDE.md`
- **General translation style:** See `~/.claude/skills/saas-translator/references/translation-guide.md`
- **Locale conventions:** See `~/.claude/skills/saas-translator/references/locale-conventions.md`
