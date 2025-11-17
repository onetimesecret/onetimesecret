---
title: Vodnik za prevajanje v slovenščino
description: Celovit vodnik za prevajanje Onetime Secret v slovenščino, ki združuje slovar izrazov in jezikovne opombe
---

# Translation Guidance for Slovenian (Slovenščina)

This document combines the glossary of standardized terms and language-specific translation notes for Slovenian translations of Onetime Secret. It serves as a comprehensive reference for translators working on the Slovenian locale to ensure consistency, accuracy, and natural phrasing.

## Overview

The Slovenian translation aims to:
- Maintain consistency across all application interfaces
- Use clear, natural phrasing for Slovenian-speaking audiences
- Follow technical accuracy for security-related terminology
- Apply appropriate voice and tone for different contexts
- Properly handle Slovenian's unique dual number system and grammatical cases

---

## Core Terminology

### Basic Terms

| English | Slovenščina (SL) | Context | Notes |
|---------|-----------------|---------|-------|
| secret (noun) | skrivnost | Central application concept | Feminine gender; appropriate for professional contexts |
| secret (adj) | skrivno/varno | Descriptive use | |
| passphrase | pristopna fraza | Authentication method for secrets | Compound term distinguishing from account password |
| password | geslo | Account login credential | Standard term for account passwords; neuter gender |
| burn | trajno izbrisati | Action to delete a secret before viewing | Permanently delete |
| view/reveal | ogled/razkritje | Action to access a secret | |
| link | povezava | URL providing access to a secret | Feminine gender |
| encrypt/encrypted | šifriranje/šifrirano | Security method | |
| secure | varno | Protection state | |

### User Interface Elements

| English | Slovenščina (SL) | Context | Notes |
|---------|-----------------|---------|-------|
| Share a secret | Deli skrivnost | Primary action | |
| Create Account | Ustvari račun | Registration | |
| Sign In | Prijava | Authentication | |
| Dashboard | Nadzorna plošča | User's main page | |
| Settings | Nastavitve | Configuration page | |
| Privacy Options | Možnosti zasebnosti | Secret configuration | |
| Feedback | Povratne informacije | User feedback | |

### Status Terms

| English | Slovenščina (SL) | Context | Notes |
|---------|-----------------|---------|-------|
| received | prejeto | Secret has been viewed | |
| burned | trajno izbrisano | Secret was deleted before viewing | |
| expired | poteklo | Secret no longer available due to time | |
| created | ustvarjeno | Secret has been generated | |
| active | aktivno | Secret is available | |
| inactive | neaktivno | Secret is not available | |

### Time-Related Terms

| English | Slovenščina (SL) | Context | Notes |
|---------|-----------------|---------|-------|
| expires in | poteče čez | Time until secret becomes unavailable | |
| day/days | dan/dni/dni | Time unit | 1 dan (singular), 2 dni (dual), 3+ dni (plural) |
| hour/hours | ura/uri/ur | Time unit | 1 ura, 2 uri, 3+ ur |
| minute/minutes | minuta/minuti/minut | Time unit | 1 minuta, 2 minuti, 3+ minut |
| second/seconds | sekunda/sekundi/sekund | Time unit | 1 sekunda, 2 sekundi, 3+ sekund |

### Security Features

| English | Slovenščina (SL) | Context |
|---------|-----------------|---------|
| one-time access | enkraten dostop | Core security feature |
| passphrase protection | zaščita s pristopno frazo | Additional security |
| encrypted in transit | šifrirano med prenosom | Data protection method |
| encrypted at rest | šifrirano pri shranjevanju | Storage protection |

### Account-Related Terms

| English | Slovenščina (SL) | Context |
|---------|-----------------|---------|
| email | e-pošta | User identifier |
| password | geslo | Account authentication |
| account | račun | User profile |
| subscription | naročnina | Paid service |
| customer | stranka | Paying user |

### Domain-Related Terms

| English | Slovenščina (SL) | Context |
|---------|-----------------|---------|
| custom domain | domena po meri | Premium feature |
| domain verification | preverjanje domene | Setup process |
| DNS record | DNS zapis | Configuration |
| CNAME record | CNAME zapis | DNS configuration |

### Error Messages

| English | Slovenščina (SL) | Context |
|---------|-----------------|---------|
| error | napaka | Problem notification |
| warning | opozorilo | Caution notification |
| oops | ups | Friendly error introduction |

### Buttons and Actions

| English | Slovenščina (SL) | Context | Notes |
|---------|-----------------|---------|-------|
| submit | pošlji | Form action | |
| cancel | prekliči | Negative action | |
| confirm | potrdi | Positive action | |
| copy to clipboard | kopiraj v odložišče | Utility action | |
| continue | nadaljuj | Navigation | |
| back | nazaj | Navigation | |

### Marketing Terms

| English | Slovenščina (SL) | Context |
|---------|-----------------|---------|
| secure links | varne povezave | Product feature |
| privacy-first design | zasnova s poudarkom na zasebnosti | Design philosophy |
| custom branding | blagovna znamka po meri | Premium feature |

---

## Translation Guidelines

### 1. Consistency

- Use the same translation for a term throughout the application
- Maintain standardized terminology from the glossary above
- Key distinctions to preserve:
  - `geslo` for account passwords
  - `pristopna fraza` for secret protection
  - `skrivnost` as the core concept

### 2. Context Awareness

- Consider how the term is used in the application
- Account for surrounding UI elements and user flow
- Ensure translations make sense in their specific context

### 3. Cultural Adaptation

- Adapt terms to local conventions when necessary
- Use modern Slovenian suitable for digital interfaces
- Use standard technical terms familiar to Slovenian-speaking users

### 4. Technical Accuracy

- Security-related terms must be translated accurately
- Prioritize precision over localization for technical terminology
- Use established Slovenian technical vocabulary

### 5. Voice and Tone

- Use polite vi forms for professional tone (not informal ti)
- Maintain professional but approachable language
- Ensure consistency in formality level across all interfaces

### 6. Slovenian Language Specifics

#### Unique Dual Number System
- Slovenian is one of few languages with a dual number (dvojina)
- Three number forms: singular (1), dual (2), plural (3+)
- Examples:
  - 1 dan (singular)
  - 2 dni (dual)
  - 3+ dni (plural)
- Same pattern for all countable nouns

#### Grammatical Cases
- Slovenian has 6 cases (imenovalnik, rodilnik, dajalnik, tožilnik, mestnik, orodnik)
- Apply correct case declension based on context
- Examples of important gender assignments:
  - skrivnost (feminine)
  - geslo (neuter)
  - dostop (masculine)

#### Three Genders
- Masculine, feminine, and neuter
- Ensure proper gender agreement with adjectives and past participles
- Important genders to remember:
  - skrivnost (feminine) - ustvarjena
  - geslo (neuter) - ustvarjeno
  - dostop (masculine) - ustvarjen

#### Diacritics
- Essential characters that change meaning: č, š, ž
- Never substitute with c, s, z
- Examples where diacritics matter:
  - cas (time - incorrect) vs čas (time - correct)
  - siriti (spread - incorrect) vs širiti (spread - correct)

#### Verb Aspects
- Slovenian verbs have perfective and imperfective aspects
- Perfective: completed action (ustvariti - to create, once)
- Imperfective: ongoing/repeated action (ustvarjati - to be creating)
- Choose appropriate aspect based on context

### 7. Clarity and Natural Phrasing

- Prioritize natural Slovenian expressions over literal translations
- Use standard phrases familiar to Slovenian speakers
- Ensure terminology is accessible and professional

### 8. Completeness

- Ensure all user-facing strings are translated
- Avoid leaving English text in the interface
- Translate help text, descriptions, and metadata

---

## Common Translation Patterns

### User Instructions
Use imperative forms with polite vi

### Status Descriptions
Use past participles with correct gender agreement

### Help Text and Descriptions
Use declarative sentences with polite second person (vi)

### Error Messages
Use clear, direct language with professional tone

---

## Special Considerations

### The Term "Secret"
- Fundamental to the application - translate consistently as `skrivnost`
- Feminine gender
- Appropriate for professional contexts
- Emphasizes the confidential nature of the shared item

### Password vs. Passphrase
Critical distinction:
- **`geslo`** - for user account login credentials (neuter)
- **`pristopna fraza`** - for protecting individual secrets

This distinction must be maintained throughout the application to avoid confusion.

### The Term "Burn"
- Translated as `trajno izbrisati` (permanently delete)
- More natural in digital Slovenian context than literal translation
- Clearly conveys permanent deletion concept

### Dual Number is Unique and Mandatory
- Slovenian is one of only a few languages preserving dual number
- Always use dual forms for quantity 2
- Never use plural for 2 items
- Examples:
  - 2 skrivnosti (dual - two secrets)
  - 2 uri (dual - two hours)
  - NOT "2 skrivnosti" using plural form

### Gender Agreement is Critical
- Adjectives and past participles must agree with noun gender
- Incorrect gender agreement sounds unnatural
- Examples:
  - skrivnost je bila ustvarjena (feminine - the secret was created)
  - geslo je bilo ustvarjeno (neuter - the password was created)
  - dostop je bil ustvarjen (masculine - the access was created)

### Diacritics Cannot Be Omitted
- č, š, ž are distinct letters, not variants of c, s, z
- Omitting diacritics creates spelling errors
- May change meaning entirely or make text unreadable
- Always preserve: č, š, ž

### UI Element Conventions
- Follow platform conventions for Slovenian interfaces
- Use standard Slovenian terminology for common UI elements
- Maintain consistency with other Slovenian applications
- Use polite vi form throughout

### Technical Security Terms
- Prioritize accuracy over casual localization
- Use established Slovenian technical vocabulary
- Examples:
  - `šifriranje` (encryption)
  - `šifrirano` (encrypted)
  - `preverjanje` (verification)
  - `avtentikacija` (authentication)

### Polite Address Forms
- Always use polite vi, never informal ti
- Professional interfaces require formal address
- Maintain consistency throughout application

---

## Summary of Translation Principles

The Slovenian translation maintains:

1. **Terminology Consistency** - Standardized key terms throughout the application
2. **Grammatical Accuracy** - Proper use of 6 cases, 3 genders, and dual number system
3. **Natural Phrasing** - Standard Slovenian expressions and idioms
4. **Dual Number System** - Unique feature requiring singular/dual/plural forms
5. **Complete Coverage** - All user-facing strings translated
6. **Technical Accuracy** - Precise terminology for security concepts
7. **Clear Distinctions** - Especially between account passwords and secret passphrases
8. **Professional Tone** - Polite vi form for respectful communication
9. **Essential Diacritics** - Correct use of č, š, ž

By following these guidelines, translators can ensure that the Slovenian version of Onetime Secret is accurate, consistent, and provides a natural user experience for Slovenian-speaking audiences.
