---
title: Průvodce překladem pro češtinu
description: Komplexní průvodce pro překlad Onetime Secret do češtiny, který kombinuje glosář termínů a jazykové poznámky
---

# Translation Guidance for Czech (Čeština)

This document combines the glossary of standardized terms and language-specific translation notes for Czech translations of Onetime Secret. It serves as a comprehensive reference for translators working on the Czech locale to ensure consistency, accuracy, and natural phrasing.

## Overview

The Czech translation aims to:
- Maintain consistency across all application interfaces
- Use clear, natural phrasing for Czech-speaking audiences
- Follow technical accuracy for security-related terminology
- Apply appropriate voice and tone for different contexts
- Properly handle Czech grammatical cases, plural forms, and diacritics

---

## Core Terminology

### Basic Terms

| English | Čeština (CS) | Context | Notes |
|---------|-------------|---------|-------|
| secret (noun) | tajemství | Central application concept | Neuter gender; appropriate for professional contexts |
| secret (adj) | tajný/bezpečný | Descriptive use | |
| passphrase | přístupová fráze | Authentication method for secrets | Compound term distinguishing from account password |
| password | heslo | Account login credential | Standard term for account passwords |
| burn | trvale smazat | Action to delete a secret before viewing | Permanently delete |
| view/reveal | zobrazit/odhalit | Action to access a secret | |
| link | odkaz | URL providing access to a secret | Masculine gender |
| encrypt/encrypted | šifrovat/šifrovaný | Security method | |
| secure | bezpečný | Protection state | |

### User Interface Elements

| English | Čeština (CS) | Context | Notes |
|---------|-------------|---------|-------|
| Share a secret | Sdílet tajemství | Primary action | |
| Create Account | Vytvořit účet | Registration | |
| Sign In | Přihlásit se | Authentication | |
| Dashboard | Přehled | User's main page | |
| Settings | Nastavení | Configuration page | |
| Privacy Options | Možnosti soukromí | Secret configuration | |
| Feedback | Zpětná vazba | User feedback | |

### Status Terms

| English | Čeština (CS) | Context | Notes |
|---------|-------------|---------|-------|
| received | přijato | Secret has been viewed | |
| burned | trvale smazáno | Secret was deleted before viewing | |
| expired | vypršelo | Secret no longer available due to time | |
| created | vytvořeno | Secret has been generated | |
| active | aktivní | Secret is available | |
| inactive | neaktivní | Secret is not available | |

### Time-Related Terms

| English | Čeština (CS) | Context | Notes |
|---------|-------------|---------|-------|
| expires in | vyprší za | Time until secret becomes unavailable | |
| day/days | den/dny/dnů | Time unit | 1 den, 2-4 dny, 5+ dnů |
| hour/hours | hodina/hodiny/hodin | Time unit | 1 hodina, 2-4 hodiny, 5+ hodin |
| minute/minutes | minuta/minuty/minut | Time unit | 1 minuta, 2-4 minuty, 5+ minut |
| second/seconds | sekunda/sekundy/sekund | Time unit | 1 sekunda, 2-4 sekundy, 5+ sekund |

### Security Features

| English | Čeština (CS) | Context |
|---------|-------------|---------|
| one-time access | jednorázový přístup | Core security feature |
| passphrase protection | ochrana přístupovou frází | Additional security |
| encrypted in transit | šifrováno při přenosu | Data protection method |
| encrypted at rest | šifrováno při uložení | Storage protection |

### Account-Related Terms

| English | Čeština (CS) | Context |
|---------|-------------|---------|
| email | e-mail | User identifier |
| password | heslo | Account authentication |
| account | účet | User profile |
| subscription | předplatné | Paid service |
| customer | zákazník | Paying user |

### Domain-Related Terms

| English | Čeština (CS) | Context |
|---------|-------------|---------|
| custom domain | vlastní doména | Premium feature |
| domain verification | ověření domény | Setup process |
| DNS record | DNS záznam | Configuration |
| CNAME record | CNAME záznam | DNS configuration |

### Error Messages

| English | Čeština (CS) | Context |
|---------|-------------|---------|
| error | chyba | Problem notification |
| warning | varování | Caution notification |
| oops | jejda | Friendly error introduction |

### Buttons and Actions

| English | Čeština (CS) | Context | Notes |
|---------|-------------|---------|-------|
| submit | odeslat | Form action | |
| cancel | zrušit | Negative action | |
| confirm | potvrdit | Positive action | |
| copy to clipboard | zkopírovat do schránky | Utility action | |
| continue | pokračovat | Navigation | |
| back | zpět | Navigation | |

### Marketing Terms

| English | Čeština (CS) | Context |
|---------|-------------|---------|
| secure links | bezpečné odkazy | Product feature |
| privacy-first design | design zaměřený na soukromí | Design philosophy |
| custom branding | vlastní branding | Premium feature |

---

## Translation Guidelines

### 1. Consistency

- Use the same translation for a term throughout the application
- Maintain standardized terminology from the glossary above
- Key distinctions to preserve:
  - `heslo` for account passwords
  - `přístupová fráze` for secret protection
  - `tajemství` as the core concept

### 2. Context Awareness

- Consider how the term is used in the application
- Account for surrounding UI elements and user flow
- Ensure translations make sense in their specific context

### 3. Cultural Adaptation

- Adapt terms to local conventions when necessary
- Use modern Czech suitable for digital interfaces
- Use standard technical terms familiar to Czech-speaking users

### 4. Technical Accuracy

- Security-related terms must be translated accurately
- Prioritize precision over localization for technical terminology
- Use established Czech technical vocabulary

### 5. Voice and Tone

- Use informal "ty" form for modern UX experience
- Maintain professional but approachable language
- Ensure consistency in formality level across all interfaces

### 6. Czech Language Specifics

#### Grammatical Cases
- Czech has 7 cases (nominativ, genitiv, dativ, akuzativ, vokativ, lokál, instrumentál)
- Apply correct case declension based on context
- Examples of important gender assignments:
  - tajemství (neuter)
  - heslo (neuter)
  - fráze (feminine)
  - odkaz (masculine)

#### Plural Forms
Czech requires three plural forms based on quantity:
- 1: singular (den, hodina, minuta, sekunda)
- 2-4: first plural form (dny, hodiny, minuty, sekundy)
- 5+: second plural form (dnů, hodin, minut, sekund)

#### Diacritics
- Essential and change meaning completely
- Must be used correctly: á, č, ď, é, ě, í, ň, ó, ř, š, ť, ú, ů, ý, ž
- Never omit or substitute

#### Contractions (Spřežky)
- Use for smoother reading: "ve věci", "ke dni", "ze souboru"
- Common in natural Czech text

### 7. Verb Aspects

- Use perfective aspect for completed actions
- Use imperfective aspect for ongoing or repeated actions
- Choose appropriate aspect based on context

### 8. Clarity and Natural Phrasing

- Prioritize natural Czech expressions over literal translations
- Use standard phrases familiar to Czech speakers
- Ensure terminology is accessible and professional

### 9. Completeness

- Ensure all user-facing strings are translated
- Avoid leaving English text in the interface
- Translate help text, descriptions, and metadata

---

## Common Translation Patterns

### User Instructions
Use imperative forms with appropriate verb aspects

### Status Descriptions
Use passive voice or past participles with correct gender agreement

### Help Text and Descriptions
Use declarative sentences with informal second person (ty)

### Error Messages
Use clear, direct language with friendly tone

---

## Special Considerations

### The Term "Secret"
- Fundamental to the application - translate consistently as `tajemství`
- Neuter gender
- Appropriate for professional contexts
- Emphasizes the confidential nature of the shared item

### Password vs. Passphrase
Critical distinction:
- **`heslo`** - for user account login credentials
- **`přístupová fráze`** - for protecting individual secrets

This distinction must be maintained throughout the application to avoid confusion.

### The Term "Burn"
- Translated as `trvale smazat` (permanently delete)
- More natural in digital Czech context than literal translation
- Clearly conveys permanent deletion concept

### Diacritics are Essential
- Never omit Czech diacritical marks
- They are not optional decorations but essential characters
- Incorrect diacritics completely change meaning
- Examples where diacritics matter:
  - být (to be) vs byt (apartment)
  - heslo (password) vs héslo (with wrong diacritic - invalid)

### Gender Agreement
- Ensure adjectives, past participles, and pronouns agree with noun gender
- Important genders to remember:
  - tajemství (neuter)
  - heslo (neuter)
  - přístupová fráze (feminine - "fráze" is feminine)
  - odkaz (masculine)

### UI Element Conventions
- Follow platform conventions for Czech interfaces
- Use standard Czech terminology for common UI elements
- Maintain consistency with other Czech applications

### Technical Security Terms
- Prioritize accuracy over casual localization
- Use established Czech technical vocabulary
- Examples:
  - `šifrovat` (to encrypt)
  - `šifrovaný` (encrypted)
  - `ověření` (verification)
  - `autentizace` (authentication)

---

## Summary of Translation Principles

The Czech translation maintains:

1. **Terminology Consistency** - Standardized key terms throughout the application
2. **Grammatical Accuracy** - Proper use of 7 cases, plural forms, and gender agreement
3. **Natural Phrasing** - Standard Czech expressions and idioms
4. **Essential Diacritics** - Complete and correct use of Czech diacritical marks
5. **Complete Coverage** - All user-facing strings translated
6. **Technical Accuracy** - Precise terminology for security concepts
7. **Clear Distinctions** - Especially between account passwords and secret passphrases
8. **Modern Tone** - Informal "ty" form for friendly, approachable communication

By following these guidelines, translators can ensure that the Czech version of Onetime Secret is accurate, consistent, and provides a natural user experience for Czech-speaking audiences.
