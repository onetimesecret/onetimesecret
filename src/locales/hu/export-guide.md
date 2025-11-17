---
title: Fordítási útmutató a magyar nyelvhez
description: Átfogó útmutató az Onetime Secret magyar fordításához, amely egyesíti a szójegyzéket és a nyelvi megjegyzéseket
---

# Translation Guidance for Hungarian (Magyar)

This document combines the glossary of standardized terms and language-specific translation notes for Hungarian translations of Onetime Secret. It serves as a comprehensive reference for translators working on the Hungarian locale to ensure consistency, accuracy, and natural phrasing.

## Overview

The Hungarian translation aims to:
- Maintain consistency across all application interfaces
- Use clear, natural phrasing for Hungarian-speaking audiences
- Follow technical accuracy for security-related terminology
- Apply appropriate voice and tone for different contexts
- Properly handle Hungarian agglutinative grammar and vowel harmony

---

## Core Terminology

### Basic Terms

| English | Magyar (HU) | Context | Notes |
|---------|-------------|---------|-------|
| secret (noun) | titok | Central application concept | Appropriate for professional contexts |
| secret (adj) | titkos/biztonságos | Descriptive use | |
| passphrase | hozzáférési mondat | Authentication method for secrets | Compound term distinguishing from account password |
| password | jelszó | Account login credential | Standard term for account passwords |
| burn | végleges törlés | Action to delete a secret before viewing | Permanent deletion |
| view/reveal | megtekintés/felfedés | Action to access a secret | |
| link | hivatkozás | URL providing access to a secret | |
| encrypt/encrypted | titkosítás/titkosított | Security method | |
| secure | biztonságos | Protection state | |

### User Interface Elements

| English | Magyar (HU) | Context | Notes |
|---------|-------------|---------|-------|
| Share a secret | Titok megosztása | Primary action | |
| Create Account | Fiók létrehozása | Registration | |
| Sign In | Bejelentkezés | Authentication | |
| Dashboard | Vezérlőpult | User's main page | |
| Settings | Beállítások | Configuration page | |
| Privacy Options | Adatvédelmi beállítások | Secret configuration | |
| Feedback | Visszajelzés | User feedback | |

### Status Terms

| English | Magyar (HU) | Context | Notes |
|---------|-------------|---------|-------|
| received | megkapva | Secret has been viewed | |
| burned | véglegesen törölve | Secret was deleted before viewing | |
| expired | lejárt | Secret no longer available due to time | |
| created | létrehozva | Secret has been generated | |
| active | aktív | Secret is available | |
| inactive | inaktív | Secret is not available | |

### Time-Related Terms

| English | Magyar (HU) | Context | Notes |
|---------|-------------|---------|-------|
| expires in | lejár | Time until secret becomes unavailable | |
| day/days | nap/nap | Time unit | Same form for singular and plural |
| hour/hours | óra/óra | Time unit | Same form for singular and plural |
| minute/minutes | perc/perc | Time unit | Same form for singular and plural |
| second/seconds | másodperc/másodperc | Time unit | Same form for singular and plural |

### Security Features

| English | Magyar (HU) | Context |
|---------|-------------|---------|
| one-time access | egyszeri hozzáférés | Core security feature |
| passphrase protection | hozzáférési mondattal való védelem | Additional security |
| encrypted in transit | átvitel közben titkosítva | Data protection method |
| encrypted at rest | tároláskor titkosítva | Storage protection |

### Account-Related Terms

| English | Magyar (HU) | Context |
|---------|-------------|---------|
| email | e-mail | User identifier |
| password | jelszó | Account authentication |
| account | fiók | User profile |
| subscription | előfizetés | Paid service |
| customer | ügyfél | Paying user |

### Domain-Related Terms

| English | Magyar (HU) | Context |
|---------|-------------|---------|
| custom domain | egyéni domén | Premium feature |
| domain verification | domén ellenőrzés | Setup process |
| DNS record | DNS rekord | Configuration |
| CNAME record | CNAME rekord | DNS configuration |

### Error Messages

| English | Magyar (HU) | Context |
|---------|-------------|---------|
| error | hiba | Problem notification |
| warning | figyelmeztetés | Caution notification |
| oops | hoppá | Friendly error introduction |

### Buttons and Actions

| English | Magyar (HU) | Context | Notes |
|---------|-------------|---------|-------|
| submit | küldés | Form action | |
| cancel | mégse | Negative action | |
| confirm | megerősítés | Positive action | |
| copy to clipboard | másolás vágólapra | Utility action | |
| continue | folytatás | Navigation | |
| back | vissza | Navigation | |

### Marketing Terms

| English | Magyar (HU) | Context |
|---------|-------------|---------|
| secure links | biztonságos hivatkozások | Product feature |
| privacy-first design | adatvédelem-központú tervezés | Design philosophy |
| custom branding | egyéni márkajelzés | Premium feature |

---

## Translation Guidelines

### 1. Consistency

- Use the same translation for a term throughout the application
- Maintain standardized terminology from the glossary above
- Key distinctions to preserve:
  - `jelszó` for account passwords
  - `hozzáférési mondat` for secret protection
  - `titok` as the core concept

### 2. Context Awareness

- Consider how the term is used in the application
- Account for surrounding UI elements and user flow
- Ensure translations make sense in their specific context

### 3. Cultural Adaptation

- Adapt terms to local conventions when necessary
- Use modern Hungarian suitable for digital interfaces
- Use standard technical terms familiar to Hungarian-speaking users

### 4. Technical Accuracy

- Security-related terms must be translated accurately
- Prioritize precision over localization for technical terminology
- Use established Hungarian technical vocabulary

### 5. Voice and Tone

- Use formal address (maga/ön forms) for professional tone
- Maintain professional but approachable language
- Ensure consistency in formality level across all interfaces

### 6. Hungarian Language Specifics

#### Agglutinative Grammar
- Hungarian uses 18+ grammatical cases expressed through suffixes
- Cases are formed by adding suffixes to word stems
- Each suffix must follow vowel harmony rules

#### Vowel Harmony
- Essential for correct suffix attachment
- Front vowels (e, é, i, í, ö, ő, ü, ű) take front-vowel suffixes
- Back vowels (a, á, o, ó, u, ú) take back-vowel suffixes
- Examples:
  - házban (in the house - back vowel)
  - kertben (in the garden - front vowel)
  - NOT "házben" (incorrect)

#### Diacritics (Ékezetek)
- Essential and change meaning completely
- Must be used correctly: á, é, í, ó, ö, ő, ú, ü, ű
- Never omit or substitute
- Examples where diacritics change meaning:
  - kor (age) vs kór (disease)
  - tuz (imperative: endure) vs tűz (fire)

#### No Grammatical Gender
- Unlike many European languages, Hungarian has no grammatical gender
- This simplifies some aspects of translation
- No need to worry about masculine/feminine agreement

#### Definite vs Indefinite Conjugation
- Verbs have two different conjugation patterns
- Definite conjugation used when object is definite
- Indefinite conjugation used when object is indefinite
- Examples:
  - látom a titkot (I see the secret - definite)
  - látok egy titkot (I see a secret - indefinite)

#### Articles
- Definite articles: a (before consonants), az (before vowels)
- Indefinite article: egy
- Examples:
  - a titok (the secret)
  - az e-mail (the email)
  - egy hivatkozás (a link)

### 7. Clarity and Natural Phrasing

- Prioritize natural Hungarian expressions over literal translations
- Use standard phrases familiar to Hungarian speakers
- Ensure terminology is accessible and professional

### 8. Completeness

- Ensure all user-facing strings are translated
- Avoid leaving English text in the interface
- Translate help text, descriptions, and metadata

---

## Common Translation Patterns

### User Instructions
Use imperative forms or infinitives for instructions

### Status Descriptions
Use passive voice or past participles appropriately

### Help Text and Descriptions
Use declarative sentences with formal address (maga/ön)

### Error Messages
Use clear, direct language with professional tone

---

## Special Considerations

### The Term "Secret"
- Fundamental to the application - translate consistently as `titok`
- Appropriate for professional contexts
- Emphasizes the confidential nature of the shared item

### Password vs. Passphrase
Critical distinction:
- **`jelszó`** - for user account login credentials
- **`hozzáférési mondat`** - for protecting individual secrets

This distinction must be maintained throughout the application to avoid confusion.

### The Term "Burn"
- Translated as `végleges törlés` (permanent deletion)
- More natural in digital Hungarian context than literal translation
- Clearly conveys permanent deletion concept

### Vowel Harmony is Mandatory
- Never violate vowel harmony rules
- Incorrect vowel harmony sounds very unnatural to native speakers
- Always check that suffixes match the stem's vowel type
- Examples:
  - titokban (in the secret - back vowels: o, a)
  - linkben (in the link - front vowels: e)

### Diacritics Cannot Be Omitted
- Hungarian diacritics are not optional decorations
- They represent entirely different sounds
- Omitting them creates spelling errors and can change meaning
- All diacritical marks must be preserved: á, é, í, ó, ö, ő, ú, ü, ű

### No Gender Agreement Needed
- Simplifies translation compared to gendered languages
- Same adjective/verb form regardless of noun
- Focus on case suffixes and vowel harmony instead

### Definite Conjugation Awareness
- Pay attention to whether objects are definite or indefinite
- Use correct verb conjugation pattern
- This affects how natural the translation sounds

### UI Element Conventions
- Follow platform conventions for Hungarian interfaces
- Use standard Hungarian terminology for common UI elements
- Maintain consistency with other Hungarian applications

### Technical Security Terms
- Prioritize accuracy over casual localization
- Use established Hungarian technical vocabulary
- Examples:
  - `titkosítás` (encryption)
  - `titkosított` (encrypted)
  - `ellenőrzés` (verification)
  - `hitelesítés` (authentication)

---

## Summary of Translation Principles

The Hungarian translation maintains:

1. **Terminology Consistency** - Standardized key terms throughout the application
2. **Grammatical Accuracy** - Proper use of cases, vowel harmony, and conjugation patterns
3. **Natural Phrasing** - Standard Hungarian expressions and idioms
4. **Essential Diacritics** - Complete and correct use of Hungarian diacritical marks
5. **Complete Coverage** - All user-facing strings translated
6. **Technical Accuracy** - Precise terminology for security concepts
7. **Clear Distinctions** - Especially between account passwords and secret passphrases
8. **Professional Tone** - Formal address (maga/ön) for respectful communication
9. **Vowel Harmony** - Mandatory compliance with vowel harmony rules

By following these guidelines, translators can ensure that the Hungarian version of Onetime Secret is accurate, consistent, and provides a natural user experience for Hungarian-speaking audiences.
