---
title: Översättningsguide för svenska
description: Omfattande guide för översättning av Onetime Secret till svenska som kombinerar ordlista och språkliga noteringar
---

# Translation Guidance for Swedish (Svenska)

This document combines the glossary of standardized terms and language-specific translation notes for Swedish translations of Onetime Secret. It serves as a comprehensive reference for translators working on the Swedish locale to ensure consistency, accuracy, and natural phrasing.

## Overview

The Swedish translation aims to:
- Maintain consistency across all application interfaces
- Use clear, natural phrasing for Swedish-speaking audiences
- Follow technical accuracy for security-related terminology
- Apply appropriate voice and tone for different contexts
- Use proper Swedish compound word formation and grammar

---

## Core Terminology

### Basic Terms

| English | Svenska (SV) | Context | Notes |
|---------|-------------|---------|-------|
| secret (noun) | hemlighet | Central application concept | Common gender (en hemlighet); appropriate for professional contexts |
| secret (adj) | hemlig/säker | Descriptive use | |
| passphrase | lösenfras | Authentication method for secrets | Compound term distinguishing from account password |
| password | lösenord | Account login credential | Standard term for account passwords; compound word |
| burn | radera permanent | Action to delete a secret before viewing | Delete permanently |
| view/reveal | visa/avslöja | Action to access a secret | |
| link | länk | URL providing access to a secret | Common gender |
| encrypt/encrypted | kryptering/krypterad | Security method | |
| secure | säker | Protection state | |

### User Interface Elements

| English | Svenska (SV) | Context | Notes |
|---------|-------------|---------|-------|
| Share a secret | Dela en hemlighet | Primary action | |
| Create Account | Skapa konto | Registration | |
| Sign In | Logga in | Authentication | |
| Dashboard | Instrumentpanel | User's main page | |
| Settings | Inställningar | Configuration page | |
| Privacy Options | Integritetsalternativ | Secret configuration | |
| Feedback | Återkoppling | User feedback | |

### Status Terms

| English | Svenska (SV) | Context | Notes |
|---------|-------------|---------|-------|
| received | mottagen | Secret has been viewed | |
| burned | raderad permanent | Secret was deleted before viewing | |
| expired | utgången | Secret no longer available due to time | |
| created | skapad | Secret has been generated | |
| active | aktiv | Secret is available | |
| inactive | inaktiv | Secret is not available | |

### Time-Related Terms

| English | Svenska (SV) | Context |
|---------|-------------|---------|
| expires in | går ut om | Time until secret becomes unavailable |
| day/days | dag/dagar | Time unit |
| hour/hours | timme/timmar | Time unit |
| minute/minutes | minut/minuter | Time unit |
| second/seconds | sekund/sekunder | Time unit |

### Security Features

| English | Svenska (SV) | Context |
|---------|-------------|---------|
| one-time access | engångsåtkomst | Core security feature |
| passphrase protection | lösenfrasskydd | Additional security |
| encrypted in transit | krypterad under överföring | Data protection method |
| encrypted at rest | krypterad vid lagring | Storage protection |

### Account-Related Terms

| English | Svenska (SV) | Context |
|---------|-------------|---------|
| email | e-post | User identifier |
| password | lösenord | Account authentication |
| account | konto | User profile |
| subscription | prenumeration | Paid service |
| customer | kund | Paying user |

### Domain-Related Terms

| English | Svenska (SV) | Context |
|---------|-------------|---------|
| custom domain | anpassad domän | Premium feature |
| domain verification | domänverifiering | Setup process |
| DNS record | DNS-post | Configuration |
| CNAME record | CNAME-post | DNS configuration |

### Error Messages

| English | Svenska (SV) | Context |
|---------|-------------|---------|
| error | fel | Problem notification |
| warning | varning | Caution notification |
| oops | hoppsan | Friendly error introduction |

### Buttons and Actions

| English | Svenska (SV) | Context | Notes |
|---------|-------------|---------|-------|
| submit | skicka | Form action | |
| cancel | avbryt | Negative action | |
| confirm | bekräfta | Positive action | |
| copy to clipboard | kopiera till urklipp | Utility action | |
| continue | fortsätt | Navigation | |
| back | tillbaka | Navigation | |

### Marketing Terms

| English | Svenska (SV) | Context |
|---------|-------------|---------|
| secure links | säkra länkar | Product feature |
| privacy-first design | integritetsfokuserad design | Design philosophy |
| custom branding | anpassad varumärkesprofilering | Premium feature |

---

## Translation Guidelines

### 1. Consistency

- Use the same translation for a term throughout the application
- Maintain standardized terminology from the glossary above
- Key distinctions to preserve:
  - `lösenord` for account passwords
  - `lösenfras` for secret protection
  - `hemlighet` as the core concept

### 2. Context Awareness

- Consider how the term is used in the application
- Account for surrounding UI elements and user flow
- Ensure translations make sense in their specific context

### 3. Cultural Adaptation

- Adapt terms to local conventions when necessary
- Use modern Swedish suitable for digital interfaces
- Use standard technical terms familiar to Swedish-speaking users

### 4. Technical Accuracy

- Security-related terms must be translated accurately
- Prioritize precision over localization for technical terminology
- Use established Swedish technical vocabulary

### 5. Voice and Tone

- Use informal "du" form universally (standard since du-reformen in 1960s)
- Maintain professional but approachable language
- Ensure consistency in formality level across all interfaces

### 6. Swedish Language Specifics

#### Compound Words
- Swedish compound words are written as one word without spaces or hyphens
- Examples:
  - lösenord (password) - NOT "lösen ord"
  - lösenfras (passphrase) - NOT "lösen fras"
  - användargränssnitt (user interface) - NOT "användare gränssnitt"
- This is essential for proper Swedish orthography

#### Two Genders
- Common gender (utrum): en - masculine and feminine merged
- Neuter gender (neutrum): ett
- Important gender assignments:
  - en hemlighet (common - the secret)
  - ett lösenord (neuter - the password)
  - en länk (common - the link)
  - ett konto (neuter - the account)

#### Swedish Letters å, ä, ö
- These are distinct letters, not variants of a and o
- Alphabetically come after z
- Never substitute with a, a, o or ae, oe
- Essential for proper Swedish spelling
- Examples:
  - för (for) vs for (groove - different meaning)
  - får (sheep/get) vs far (father)

#### Informal "Du" Universal
- Since du-reformen (1960s), informal "du" is universally used
- Professional contexts also use "du"
- No need for formal "Ni" in modern Swedish interfaces
- Simpler than many other languages

#### No Verb Conjugation for Person/Number
- Swedish verbs don't conjugate for person or number
- Same form for all subjects
- Examples:
  - jag skapar (I create)
  - du skapar (you create)
  - vi skapar (we create)
- Simplifies translation

#### V2 Rule (Verb Second)
- In declarative sentences, the verb comes second
- When sentence doesn't start with subject, word order changes
- Examples:
  - Subject first: "Hemligheten skapas här" (The secret is created here)
  - Other element first: "Här skapas hemligheten" (Here is created the secret)

### 7. Clarity and Natural Phrasing

- Prioritize natural Swedish expressions over literal translations
- Use standard phrases familiar to Swedish speakers
- Ensure terminology is accessible and professional

### 8. Completeness

- Ensure all user-facing strings are translated
- Avoid leaving English text in the interface
- Translate help text, descriptions, and metadata

---

## Common Translation Patterns

### User Instructions
Use imperative forms with informal du understood

### Status Descriptions
Use past participles with correct gender agreement

### Help Text and Descriptions
Use declarative sentences with informal du

### Error Messages
Use clear, direct language with friendly tone

---

## Special Considerations

### The Term "Secret"
- Fundamental to the application - translate consistently as `hemlighet`
- Common gender (en hemlighet)
- Appropriate for professional contexts
- Emphasizes the confidential nature of the shared item

### Password vs. Passphrase
Critical distinction:
- **`lösenord`** - for user account login credentials (compound word)
- **`lösenfras`** - for protecting individual secrets (compound word)

This distinction must be maintained throughout the application to avoid confusion.

### The Term "Burn"
- Translated as `radera permanent` (delete permanently)
- More natural in digital Swedish context than literal translation
- Clearly conveys permanent deletion concept

### Compound Words Must Be Written Together
- Never separate Swedish compound words with spaces
- This is a fundamental rule of Swedish orthography
- Incorrect spacing looks unprofessional and is grammatically wrong
- Examples of correct compounds:
  - lösenord (not "lösen ord")
  - lösenfras (not "lösen fras")
  - säkerhetskopia (not "säkerhets kopia")
  - användarnamn (not "användar namn")

### Swedish Letters Cannot Be Substituted
- å, ä, ö are distinct letters
- Never use a, a, o as substitutes
- Never use ae or oe as substitutes
- Essential for proper Swedish
- Examples of importance:
  - får (sheep/get) vs far (father) vs fär (obsolete word)

### Gender Agreement for Adjectives
- Adjectives must agree with noun gender
- Common gender: -en ending (den skapade hemligheten)
- Neuter gender: -et ending (det skapade lösenordet)
- Indefinite common: -ad ending (en skapad hemlighet)
- Indefinite neuter: -at ending (ett skapat lösenord)

### UI Element Conventions
- Follow platform conventions for Swedish interfaces
- Use standard Swedish terminology for common UI elements
- Maintain consistency with other Swedish applications
- Use informal du universally

### Technical Security Terms
- Prioritize accuracy over casual localization
- Use established Swedish technical vocabulary
- Examples:
  - `kryptering` (encryption)
  - `krypterad` (encrypted)
  - `verifiering` (verification)
  - `autentisering` (authentication)

### Simplicity of Swedish Grammar
- No formal/informal distinction (always du)
- No verb conjugation for person/number
- Only two genders (not three like German)
- Makes translation somewhat simpler than many languages

---

## Summary of Translation Principles

The Swedish translation maintains:

1. **Terminology Consistency** - Standardized key terms throughout the application
2. **Grammatical Accuracy** - Proper use of 2 genders and compound word formation
3. **Natural Phrasing** - Standard Swedish expressions and idioms
4. **Compound Words** - Correct formation without spaces or hyphens
5. **Complete Coverage** - All user-facing strings translated
6. **Technical Accuracy** - Precise terminology for security concepts
7. **Clear Distinctions** - Especially between account passwords and secret passphrases
8. **Informal Tone** - Universal use of informal "du" for approachable communication
9. **Swedish Letters** - Correct use of å, ä, ö as distinct letters

By following these guidelines, translators can ensure that the Swedish version of Onetime Secret is accurate, consistent, and provides a natural user experience for Swedish-speaking audiences.
