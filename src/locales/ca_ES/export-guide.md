---
title: Guia de traducció per al català
description: Guia completa per traduir Onetime Secret al català que combina el glossari de termes i les notes lingüístiques
---

# Translation Guidance for Catalan (Català)

This document combines the glossary of standardized terms and language-specific translation notes for Catalan translations of Onetime Secret. It serves as a comprehensive reference for translators working on the Catalan locale to ensure consistency, accuracy, and natural phrasing.

## Overview

The Catalan translation aims to:
- Maintain consistency across all application interfaces
- Use clear, natural phrasing for Catalan-speaking audiences
- Follow technical accuracy for security-related terminology
- Apply appropriate voice and tone for different contexts
- Use Standard Catalan following Institut d'Estudis Catalans (IEC) norms

---

## Core Terminology

### Basic Terms

| English | Català (CA) | Context | Notes |
|---------|-------------|---------|-------|
| secret (noun) | secret | Central application concept | Works perfectly in professional contexts |
| secret (adj) | secret/segur | Descriptive use | |
| passphrase | frase de contrasenya | Authentication method for secrets | Compound term distinguishing from account password |
| password | contrasenya | Account login credential | Standard term for account passwords |
| burn | destruir | Action to delete a secret before viewing | Destroy/delete permanently |
| view/reveal | veure/mostrar | Action to access a secret | |
| link | enllaç | URL providing access to a secret | |
| encrypt/encrypted | xifrar/xifrat | Security method | Use "xifrar" with x, not "cifrar" |
| secure | segur | Protection state | |

### User Interface Elements

| English | Català (CA) | Context | Notes |
|---------|-------------|---------|-------|
| Share a secret | Compartir un secret | Primary action | |
| Create Account | Crear compte | Registration | |
| Sign In | Iniciar sessió | Authentication | |
| Dashboard | Tauler de control | User's main page | |
| Settings | Configuració | Configuration page | |
| Privacy Options | Opcions de privadesa | Secret configuration | |
| Feedback | Comentaris | User feedback | |

### Status Terms

| English | Català (CA) | Context | Notes |
|---------|-------------|---------|-------|
| received | rebut | Secret has been viewed | |
| burned | destruït | Secret was deleted before viewing | |
| expired | caducat | Secret no longer available due to time | |
| created | creat | Secret has been generated | |
| active | actiu | Secret is available | |
| inactive | inactiu | Secret is not available | |

### Time-Related Terms

| English | Català (CA) | Context |
|---------|-------------|---------|
| expires in | caduca en | Time until secret becomes unavailable |
| day/days | dia/dies | Time unit |
| hour/hours | hora/hores | Time unit |
| minute/minutes | minut/minuts | Time unit |
| second/seconds | segon/segons | Time unit |

### Security Features

| English | Català (CA) | Context |
|---------|-------------|---------|
| one-time access | accés d'un sol ús | Core security feature |
| passphrase protection | protecció amb frase de contrasenya | Additional security |
| encrypted in transit | xifrat en trànsit | Data protection method |
| encrypted at rest | xifrat en repòs | Storage protection |

### Account-Related Terms

| English | Català (CA) | Context |
|---------|-------------|---------|
| email | correu electrònic | User identifier |
| password | contrasenya | Account authentication |
| account | compte | User profile |
| subscription | subscripció | Paid service |
| customer | client | Paying user |

### Domain-Related Terms

| English | Català (CA) | Context |
|---------|-------------|---------|
| custom domain | domini personalitzat | Premium feature |
| domain verification | verificació del domini | Setup process |
| DNS record | registre DNS | Configuration |
| CNAME record | registre CNAME | DNS configuration |

### Error Messages

| English | Català (CA) | Context |
|---------|-------------|---------|
| error | error | Problem notification |
| warning | advertència | Caution notification |
| oops | ups | Friendly error introduction |

### Buttons and Actions

| English | Català (CA) | Context | Notes |
|---------|-------------|---------|-------|
| submit | enviar | Form action | |
| cancel | cancel·lar | Negative action | Note the punt volat (·) |
| confirm | confirmar | Positive action | |
| copy to clipboard | copiar al porta-retalls | Utility action | |
| continue | continuar | Navigation | |
| back | enrere | Navigation | |

### Marketing Terms

| English | Català (CA) | Context |
|---------|-------------|---------|
| secure links | enllaços segurs | Product feature |
| privacy-first design | disseny que prioritza la privadesa | Design philosophy |
| custom branding | marca personalitzada | Premium feature |

---

## Translation Guidelines

### 1. Consistency

- Use the same translation for a term throughout the application
- Maintain standardized terminology from the glossary above
- Key distinctions to preserve:
  - `contrasenya` for account passwords
  - `frase de contrasenya` for secret protection
  - `secret` as the core concept

### 2. Context Awareness

- Consider how the term is used in the application
- Account for surrounding UI elements and user flow
- Ensure translations make sense in their specific context

### 3. Cultural Adaptation

- Adapt terms to local conventions when necessary
- Use Standard Catalan following Institut d'Estudis Catalans (IEC) norms
- Use standard technical terms familiar to Catalan-speaking users

### 4. Technical Accuracy

- Security-related terms must be translated accurately
- Prioritize precision over localization for technical terminology
- Use established Catalan technical vocabulary
- **Important**: Use "xifrar" (with x), not "cifrar" for encryption terms

### 5. Voice and Tone

- Use informal second person (tu) for friendly tone
- Maintain professional but approachable language
- Ensure consistency in formality level across all interfaces

### 6. Catalan Language Specifics

#### Punt Volat (·)
- Essential in geminated l combinations: excel·lent, intel·ligent, cancel·lar
- Must be included for proper Catalan orthography

#### Apostrophes
- Common in Catalan: d'un, l'usuari, s'ha
- Use appropriately with articles and pronouns

#### Gender Agreement
- Ensure proper gender agreement (masculine, feminine, neuter)
- Use correct definite and indefinite articles: el secret, la frase, un enllaç, una opció

### 7. Clarity and Natural Phrasing

- Prioritize natural Catalan expressions over literal translations
- Use standard phrases familiar to Catalan speakers
- Ensure terminology is accessible and professional

### 8. Completeness

- Ensure all user-facing strings are translated
- Avoid leaving English text in the interface
- Translate help text, descriptions, and metadata

---

## Common Translation Patterns

### User Instructions
Use imperative or infinitive forms for instructions and actions

### Status Descriptions
Use passive voice or past participles appropriately

### Help Text and Descriptions
Use declarative sentences with informal second person (tu)

### Error Messages
Use clear, direct language with friendly tone

---

## Special Considerations

### The Term "Secret"
- Fundamental to the application - translate consistently as `secret`
- Works perfectly in professional contexts in Catalan
- Emphasizes the confidential nature of the shared item

### Password vs. Passphrase
Critical distinction:
- **`contrasenya`** - for user account login credentials
- **`frase de contrasenya`** - for protecting individual secrets

This distinction must be maintained throughout the application to avoid confusion.

### The Term "Burn"
- Translated as `destruir` (destroy/delete permanently)
- More natural in digital Catalan context
- Clearly conveys permanent deletion concept

### Encryption Terminology
- **Always use "xifrar" (with x)**, not "cifrar"
- This is the standard form in Catalan orthography
- Examples: xifrar, xifrat, xifratge

### Punt Volat (·) Usage
- Critical for proper Catalan spelling
- Required in geminated l: cancel·lar, col·laborar, intel·ligent, excel·lent
- Do not omit or replace with simple l

### UI Element Conventions
- Follow platform conventions for Catalan interfaces
- Use standard Catalan terminology for common UI elements
- Maintain consistency with other Catalan applications

### Technical Security Terms
- Prioritize accuracy over casual localization
- Use established Catalan technical vocabulary
- Examples:
  - `xifrar` (to encrypt)
  - `xifrat` (encrypted)
  - `verificació` (verification)
  - `autenticació` (authentication)

---

## Summary of Translation Principles

The Catalan translation maintains:

1. **Terminology Consistency** - Standardized key terms throughout the application
2. **IEC Standards** - Following Institut d'Estudis Catalans orthographic norms
3. **Natural Phrasing** - Standard Catalan expressions and idioms
4. **Proper Orthography** - Correct use of punt volat (·), apostrophes, and gender agreement
5. **Complete Coverage** - All user-facing strings translated
6. **Technical Accuracy** - Precise terminology for security concepts (xifrar, not cifrar)
7. **Clear Distinctions** - Especially between account passwords and secret passphrases
8. **Friendly Tone** - Informal second person (tu) for approachable communication

By following these guidelines, translators can ensure that the Catalan version of Onetime Secret is accurate, consistent, and provides a natural user experience for Catalan-speaking audiences.
