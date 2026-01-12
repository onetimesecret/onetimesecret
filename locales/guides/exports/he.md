---
title: מדריך תרגום לעברית
description: מדריך מקיף לתרגום Onetime Secret לעברית המשלב את מילון המונחים והערות לשוניות
---

# Translation Guidance for Hebrew (עברית)

This document combines the glossary of standardized terms and language-specific translation notes for Hebrew translations of Onetime Secret. It serves as a comprehensive reference for translators working on the Hebrew locale to ensure consistency, accuracy, and natural phrasing.

## Overview

The Hebrew translation aims to:
- Maintain consistency across all application interfaces
- Use clear, natural phrasing for Hebrew-speaking audiences
- Follow technical accuracy for security-related terminology
- Apply appropriate voice and tone for different contexts
- Properly implement Right-to-Left (RTL) layout requirements
- Use Modern Hebrew without vowel points (niqqud)

---

## Core Terminology

### Basic Terms

| English | עברית (HE) | Context | Notes |
|---------|------------|---------|-------|
| secret (noun) | סוד | Central application concept | Masculine gender; appropriate for professional contexts |
| secret (adj) | סודי/מאובטח | Descriptive use | |
| passphrase | ביטוי סיסמה | Authentication method for secrets | Compound term distinguishing from account password |
| password | סיסמה | Account login credential | Standard term for account passwords |
| burn | מחיקה סופית | Action to delete a secret before viewing | Permanent deletion |
| view/reveal | צפייה/חשיפה | Action to access a secret | |
| link | קישור | URL providing access to a secret | |
| encrypt/encrypted | הצפנה/מוצפן | Security method | |
| secure | מאובטח | Protection state | |

### User Interface Elements

| English | עברית (HE) | Context | Notes |
|---------|------------|---------|-------|
| Share a secret | שיתוף סוד | Primary action | |
| Create Account | יצירת חשבון | Registration | |
| Sign In | התחברות | Authentication | |
| Dashboard | לוח בקרה | User's main page | |
| Settings | הגדרות | Configuration page | |
| Privacy Options | אפשרויות פרטיות | Secret configuration | |
| Feedback | משוב | User feedback | |

### Status Terms

| English | עברית (HE) | Context | Notes |
|---------|------------|---------|-------|
| received | התקבל | Secret has been viewed | |
| burned | נמחק סופית | Secret was deleted before viewing | |
| expired | פג תוקף | Secret no longer available due to time | |
| created | נוצר | Secret has been generated | |
| active | פעיל | Secret is available | |
| inactive | לא פעיל | Secret is not available | |

### Time-Related Terms

| English | עברית (HE) | Context |
|---------|------------|---------|
| expires in | פג תוקף בעוד | Time until secret becomes unavailable |
| day/days | יום/ימים | Time unit |
| hour/hours | שעה/שעות | Time unit |
| minute/minutes | דקה/דקות | Time unit |
| second/seconds | שנייה/שניות | Time unit |

### Security Features

| English | עברית (HE) | Context |
|---------|------------|---------|
| one-time access | גישה חד-פעמית | Core security feature |
| passphrase protection | הגנה בביטוי סיסמה | Additional security |
| encrypted in transit | מוצפן בהעברה | Data protection method |
| encrypted at rest | מוצפן במנוחה | Storage protection |

### Account-Related Terms

| English | עברית (HE) | Context | Notes |
|---------|------------|---------|-------|
| email | דואר אלקטרוני | User identifier | Can also use דוא״ל with gershayim |
| password | סיסמה | Account authentication | Feminine gender |
| account | חשבון | User profile | |
| subscription | מנוי | Paid service | |
| customer | לקוח | Paying user | |

### Domain-Related Terms

| English | עברית (HE) | Context |
|---------|------------|---------|
| custom domain | דומיין מותאם אישית | Premium feature |
| domain verification | אימות דומיין | Setup process |
| DNS record | רשומת DNS | Configuration |
| CNAME record | רשומת CNAME | DNS configuration |

### Error Messages

| English | עברית (HE) | Context |
|---------|------------|---------|
| error | שגיאה | Problem notification |
| warning | אזהרה | Caution notification |
| oops | אופס | Friendly error introduction |

### Buttons and Actions

| English | עברית (HE) | Context | Notes |
|---------|------------|---------|-------|
| submit | שליחה | Form action | |
| cancel | ביטול | Negative action | |
| confirm | אישור | Positive action | |
| copy to clipboard | העתקה ללוח | Utility action | |
| continue | המשך | Navigation | |
| back | חזרה | Navigation | |

### Marketing Terms

| English | עברית (HE) | Context |
|---------|------------|---------|
| secure links | קישורים מאובטחים | Product feature |
| privacy-first design | עיצוב בעדיפות פרטיות | Design philosophy |
| custom branding | מיתוג מותאם אישית | Premium feature |

---

## Translation Guidelines

### 1. Consistency

- Use the same translation for a term throughout the application
- Maintain standardized terminology from the glossary above
- Key distinctions to preserve:
  - `סיסמה` for account passwords
  - `ביטוי סיסמה` for secret protection
  - `סוד` as the core concept

### 2. Context Awareness

- Consider how the term is used in the application
- Account for surrounding UI elements and user flow
- Ensure translations make sense in their specific context

### 3. Cultural Adaptation

- Adapt terms to local conventions when necessary
- Use Modern Hebrew suitable for digital interfaces
- Use standard technical terms familiar to Hebrew-speaking users

### 4. Technical Accuracy

- Security-related terms must be translated accurately
- Prioritize precision over localization for technical terminology
- Use established Hebrew technical vocabulary

### 5. Voice and Tone

- Use masculine singular imperative for buttons (standard in Hebrew UI)
- Maintain professional but approachable language
- Ensure consistency in formality level across all interfaces

### 6. Hebrew Language Specifics

#### Right-to-Left (RTL) Layout
- Hebrew is written from right to left
- UI elements should be mirrored appropriately
- Numbers and Latin script remain LTR within RTL text
- Pay special attention to interface layout requirements

#### Modern Hebrew Without Niqqud
- Do not use vowel points (niqqud) except in very special cases
- Modern Hebrew text is written without diacritical marks
- Example: סוד (correct), not סוֹד (with niqqud - avoid)

#### Gender Agreement
- Hebrew has masculine and feminine genders
- Ensure adjectives and verbs agree with noun gender
- Important gender assignments:
  - סוד (masculine)
  - סיסמה (feminine)
  - הצפנה (feminine)
  - קישור (masculine)

#### Plural Forms
- Use appropriate plural forms
- Examples:
  - סוד/סודות (secret/secrets)
  - קישור/קישורים (link/links)
  - שעה/שעות (hour/hours)

#### Gershayim and Geresh
- Use gershayim (״) for Hebrew acronyms: דוא״ל, צה״ל
- Use geresh (׳) for single-letter abbreviations
- These are proper Hebrew punctuation marks

### 7. Clarity and Natural Phrasing

- Prioritize natural Hebrew expressions over literal translations
- Use standard phrases familiar to Hebrew speakers
- Ensure terminology is accessible and professional

### 8. Completeness

- Ensure all user-facing strings are translated
- Avoid leaving English text in the interface
- Translate help text, descriptions, and metadata

---

## Common Translation Patterns

### User Instructions
Use masculine singular imperative forms (standard in Hebrew UI)

### Status Descriptions
Use passive voice or past participles with correct gender agreement

### Help Text and Descriptions
Use declarative sentences with appropriate formality

### Error Messages
Use clear, direct language with professional tone

---

## Special Considerations

### The Term "Secret"
- Fundamental to the application - translate consistently as `סוד`
- Masculine gender
- Appropriate for professional contexts
- Emphasizes the confidential nature of the shared item

### Password vs. Passphrase
Critical distinction:
- **`סיסמה`** - for user account login credentials (feminine)
- **`ביטוי סיסמה`** - for protecting individual secrets

This distinction must be maintained throughout the application to avoid confusion.

### The Term "Burn"
- Translated as `מחיקה סופית` (permanent deletion)
- More natural in digital Hebrew context than literal translation
- Clearly conveys permanent deletion concept

### RTL Layout Implementation
- Hebrew requires complete right-to-left layout
- All text flows from right to left
- UI elements mirror horizontally
- Mixed content (Hebrew + numbers/Latin) requires careful handling
- Numbers and Latin text remain LTR within RTL flow

### No Vowel Points (Niqqud)
- Modern Hebrew interfaces never use niqqud
- Vowel points are only for religious texts, poetry, or children's books
- Always write unvocalized text: סוד, סיסמה, הצפנה

### Gender Agreement is Critical
- Hebrew verbs and adjectives must agree with noun gender
- Incorrect gender sounds unnatural to native speakers
- Examples:
  - הסוד נוצר (masculine - the secret was created)
  - הסיסמה נוצרה (feminine - the password was created)

### Hebrew Acronyms
- Use proper gershayim (״) for acronyms
- Example: דוא״ל (email) - short for דואר אלקטרוני
- Never use regular quotation marks for this purpose

### UI Element Conventions
- Follow platform conventions for Hebrew interfaces
- Use standard Hebrew terminology for common UI elements
- Maintain consistency with other Hebrew applications
- Buttons use masculine singular imperative as standard

### Technical Security Terms
- Prioritize accuracy over casual localization
- Use established Hebrew technical vocabulary
- Examples:
  - `הצפנה` (encryption)
  - `מוצפן` (encrypted)
  - `אימות` (verification/authentication)
  - `אבטחה` (security)

---

## Summary of Translation Principles

The Hebrew translation maintains:

1. **Terminology Consistency** - Standardized key terms throughout the application
2. **Grammatical Accuracy** - Proper use of gender agreement and plural forms
3. **Natural Phrasing** - Standard Hebrew expressions and idioms
4. **RTL Awareness** - Proper implementation of right-to-left layout
5. **Complete Coverage** - All user-facing strings translated
6. **Technical Accuracy** - Precise terminology for security concepts
7. **Clear Distinctions** - Especially between account passwords and secret passphrases
8. **Modern Hebrew** - No vowel points (niqqud) in standard text
9. **Proper Punctuation** - Correct use of gershayim (״) for acronyms

By following these guidelines, translators can ensure that the Hebrew version of Onetime Secret is accurate, consistent, and provides a natural user experience for Hebrew-speaking audiences.
