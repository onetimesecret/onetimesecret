---
title: Oversættelsesvejledning til dansk
description: Omfattende vejledning til oversættelse af Onetime Secret til dansk, der kombinerer ordliste og sproglige noter
---

# Translation Guidance for Danish (Dansk)

This document combines the glossary of standardized terms and language-specific translation notes for Danish translations of Onetime Secret. It serves as a comprehensive reference for translators working on the Danish locale to ensure consistency, accuracy, and natural phrasing.

## Overview

The Danish translation aims to:
- Maintain consistency across all application interfaces
- Use clear, natural phrasing for Danish-speaking audiences
- Follow technical accuracy for security-related terminology
- Apply appropriate voice and tone for different contexts
- Avoid inappropriate connotations through careful word choice

---

## Core Terminology

### Basic Terms

| English | Dansk (DA) | Context | Notes |
|---------|------------|---------|-------|
| secret (noun) | besked | Central application concept | Use "besked" (message) instead of "hemmelighed" to avoid childish/personal connotations |
| secret (adj) | hemmelig/sikker | Descriptive use | |
| passphrase | adgangssætning | Authentication method for secrets | Distinct compound term for secret protection |
| password | adgangskode | Account login credential | Standard term for account passwords only |
| burn | ødelæg | Action to delete a secret before viewing | Permanent deletion action |
| view/reveal | vis/åben | Action to access a secret | Display/show content |
| link | link | URL providing access to a secret | |
| encrypt/encrypted | krypter/krypteret | Security method | |
| secure | sikker | Protection state | |

### User Interface Elements

| English | Dansk (DA) | Context | Notes |
|---------|------------|---------|-------|
| Share a secret | Del en besked | Primary action | |
| Create Account | Opret konto | Registration | |
| Sign In | Log ind | Authentication | |
| Dashboard | Oversigt | User's main page | |
| Settings | Indstillinger | Configuration page | |
| Privacy Options | Privatlivsindstillinger | Secret configuration | |
| Feedback | Feedback | User feedback | |

### Status Terms

| English | Dansk (DA) | Context | Notes |
|---------|------------|---------|-------|
| received | modtaget | Secret has been viewed | Past participle for status |
| burned | ødelagt | Secret was deleted before viewing | Past participle for status |
| expired | udløbet | Secret no longer available due to time | Past participle for status |
| created | oprettet | Secret has been generated | Past participle for status |
| active | aktiv | Secret is available | |
| inactive | inaktiv | Secret is not available | |

### Time-Related Terms

| English | Dansk (DA) | Context |
|---------|------------|---------|
| expires in | udløber om | Time until secret becomes unavailable |
| day/days | dag/dage | Time unit |
| hour/hours | time/timer | Time unit |
| minute/minutes | minut/minutter | Time unit |
| second/seconds | sekund/sekunder | Time unit |

### Security Features

| English | Dansk (DA) | Context |
|---------|------------|---------|
| one-time access | engangsadgang | Core security feature |
| passphrase protection | adgangssætningsbeskyttelse | Additional security |
| encrypted in transit | krypteret under overførsel | Data protection method |
| encrypted at rest | krypteret under lagring | Storage protection |

### Account-Related Terms

| English | Dansk (DA) | Context |
|---------|------------|---------|
| email | e-mail | User identifier |
| password | adgangskode | Account authentication |
| account | konto | User profile |
| subscription | abonnement | Paid service |
| customer | kunde | Paying user |

### Domain-Related Terms

| English | Dansk (DA) | Context |
|---------|------------|---------|
| custom domain | brugerdefineret domæne | Premium feature |
| domain verification | domænebekræftelse | Setup process |
| DNS record | DNS-post | Configuration |
| CNAME record | CNAME-post | DNS configuration |

### Error Messages

| English | Dansk (DA) | Context |
|---------|------------|---------|
| error | fejl | Problem notification |
| warning | advarsel | Caution notification |
| oops | ups | Friendly error introduction |

### Buttons and Actions

| English | Dansk (DA) | Context | Notes |
|---------|------------|---------|-------|
| submit | send | Form action | Imperative form |
| cancel | annuller | Negative action | Imperative form |
| confirm | bekræft | Positive action | Imperative form |
| copy to clipboard | kopier til udklipsholder | Utility action | Imperative form |
| continue | fortsæt | Navigation | Imperative form |
| back | tilbage | Navigation | |
| create | opret | Imperative form for buttons | |
| save | gem | Imperative form for buttons | |
| saved | gemt | Past participle for status | |
| share | del | Share/distribute | Imperative form |

### Marketing Terms

| English | Dansk (DA) | Context |
|---------|------------|---------|
| secure links | sikre links | Product feature |
| privacy-first design | privatlivs-først design | Design philosophy |
| custom branding | brugerdefineret branding | Premium feature |

---

## Translation Guidelines

### 1. Consistency

- Use the same translation for a term throughout the application
- Maintain standardized terminology from the glossary above
- Key distinctions to preserve:
  - `adgangskode` for account passwords
  - `adgangssætning` for secret protection
  - `besked` as the core concept (not "hemmelighed")

### 2. Context Awareness

- Consider how the term is used in the application
- Account for surrounding UI elements and user flow
- Ensure translations make sense in their specific context

### 3. Cultural Adaptation

- Adapt terms to local conventions when necessary
- Use standard Danish that works across regions
- Use standard technical terms familiar to Danish-speaking users

### 4. Technical Accuracy

- Security-related terms must be translated accurately
- Prioritize precision over localization for technical terminology
- Use established Danish technical vocabulary

### 5. Voice and Tone

#### Imperative Voice (for Actions)
Use imperative voice for buttons, links, and user actions:
- `Opret besked` (Create secret)
- `Kopier til udklipsholder` (Copy to clipboard)
- `Opret konto` (Create account)
- `Gem` (Save)
- `Del` (Share)

#### Passive/Declarative Voice (for Information)
Use passive voice or past participles for informational text, status messages, and descriptions:
- `Besked oprettet` (Secret created - status)
- `Din sikre besked vises nedenfor.` (Your secure message is shown below.)
- `Beskeden blev ødelagt manuelt...` (The secret was manually destroyed...)
- `Gemt` (Saved - status message)

### 6. Direct Address

- Use informal address consistently when addressing users
- Examples:
  - `Indtast din adgangskode` (Enter your password)
  - `Din sikre besked` (Your secure message)
- Danish naturally flows with direct address in most contexts

### 7. Clarity and Natural Phrasing

- Prioritize natural Danish expressions over literal translations
- Use standard phrases familiar to Danish speakers
- Avoid literal translations that sound awkward in Danish

### 8. Completeness

- Ensure all user-facing strings are translated
- Avoid leaving English text in the interface
- Translate help text, descriptions, and metadata

### 9. Compound Words with English Loanwords

When creating compound words that include English loanwords, use hyphens:
- ✓ `besked-apps` (hyphenated)
- ✗ `besked apps` (separate words)
- ✓ `API-nøgle` (hyphenated)
- ✗ `API nøgle` (separate words)

---

## Common Translation Patterns

### User Instructions
Use imperative forms:
- `Indtast din adgangskode` (Enter your password)
- `Kopier til udklipsholder` (Copy to clipboard)
- `Indtast adgangssætningen her` (Enter the passphrase here)

### Status Descriptions
Use passive voice or past participles:
- `Kopieret til udklipsholder` (Copied to clipboard)
- `Besked oprettet` (Secret created)
- `Gemt` (Saved)
- `Oprettet` (Created)

### Help Text and Descriptions
Use declarative sentences:
- `Du ser det sikre indhold` (You are viewing the secure content)
- `Dette indhold vises kun én gang` (This content is shown only once)

### Error Messages
Use clear, direct language:
- `Forkert adgangssætning` (Incorrect passphrase)
- `Der opstod en fejl` (An error occurred)

---

## Special Considerations

### The Term "Secret" - Critical Rule

**ALWAYS use "besked" (message), NEVER use "hemmelighed" (secret)**

The Danish word "hemmelighed" carries inappropriate connotations:
- Personal or private secrets (gossip, hidden information)
- Childish or trivial usage
- Meanings that sound unprofessional in a business context

Native speaker feedback confirms that "hemmelighed" evokes associations with personal secrets rather than business security.

Examples:
- ✓ `Du har 3 nye beskeder` (You have 3 new messages)
- ✗ `Du har 3 nye hemmeligheder` (You have 3 new secrets)
- ✓ `Opret en besked` (Create a secret)
- ✗ `Opret en hemmelighed` (Create a secret)

### Password vs. Passphrase
**Critical distinction that must be maintained:**
- **`adgangskode`** - for user account login credentials ONLY
- **`adgangssætning`** - for protecting individual secrets

This distinction must be maintained throughout the application to avoid confusion.

Examples:
- ✓ `Indtast din adgangskode` (Enter your password - account login)
- ✗ `Indtast din adgangssætning` (Enter your passphrase - account login)
- ✓ `Beskyt med adgangssætning` (Protect with passphrase - secret protection)
- ✗ `Beskyt med adgangskode` (Protect with password - secret protection)

### The Term "Burn"
Consistently translated as **`ødelæg`** (verb) / **`ødelagt`** (past participle):
- Conveys the permanent, irreversible nature of deletion
- Examples:
  - `Ødelæg denne besked` (Burn this secret - button)
  - `Beskeden er ødelagt` (The secret is burned - status)

### UI Element Conventions
- Follow platform conventions for the target language
- Use standard Danish terminology for common UI elements
- Maintain consistency with other Danish applications

### Technical Security Terms
- Prioritize accuracy over casual localization
- Use established Danish technical vocabulary
- Examples:
  - `krypteret` (encrypted)
  - `krypter` (to encrypt)
  - `bekræftelse` (verification)
  - `godkendelse` (authentication)

---

## Critical Translation Rules

| Rule | Correct | Incorrect | Example |
|------|---------|-----------|---------|
| "Secret" → "Besked" (NOT "Hemmelighed") | besked | hemmelighed | ✓ Du har 3 nye beskeder; ✗ Du har 3 nye hemmeligheder |
| Password vs. Passphrase | adgangskode (login), adgangssætning (secret) | Mixed usage | ✓ Indtast din adgangskode (login); ✗ Indtast din adgangssætning (login) |
| Buttons: Imperative | Opret, Del, Gem | Noun forms | ✓ Opret besked (button); ✗ Oprettelse af besked (button) |
| Status: Passive form | Oprettet, Gemt | Imperative in status | ✓ Besked oprettet (status); ✗ Opret besked (status) |
| Compound words with English loanwords | besked-apps, API-nøgle | besked apps, API nøgle | ✓ besked-apps (hyphenated); ✗ besked apps (separate words) |

---

## Rationale for Danish-Specific Adjustments

The Danish translation requires special attention to:

1. **"Besked" instead of "Hemmelighed"**: The word "hemmelighed" has childish/personal connotations in everyday Danish that undermine the professional/security context. Using "besked" maintains a business-appropriate tone.

2. **Clear Password/Passphrase Distinction**: Using "adgangskode" for account login and "adgangssætning" for secret protection ensures users understand the different security contexts.

3. **Imperative for Actions, Passive for Status**: Danish UI conventions strongly favor imperative forms for buttons and passive/past participle forms for status messages.

4. **Compound Word Hyphenation**: When combining Danish words with English loanwords, hyphens are necessary for proper Danish orthography.

---

## Summary of Translation Principles

The Danish translation maintains:

1. **Terminology Consistency** - Standardized key terms throughout the application
2. **Appropriate Voice** - Imperative for actions, passive/past participles for information
3. **Natural Phrasing** - Standard Danish expressions and sentence structures
4. **Consistent Address** - Direct address when addressing users
5. **Complete Coverage** - All user-facing strings translated
6. **Technical Accuracy** - Precise terminology for security concepts
7. **Clear Distinctions** - Especially:
   - Account passwords (`adgangskode`) and secret passphrases (`adgangssætning`)
   - Using `besked` (message) instead of `hemmelighed` (secret)
   - Action verbs (imperative) and status messages (passive/past participle)
8. **Proper Orthography** - Hyphenated compound words with English loanwords

By following these guidelines, translators can ensure that the Danish version of Onetime Secret is accurate, consistent, professional, and provides a natural user experience for Danish-speaking audiences.
