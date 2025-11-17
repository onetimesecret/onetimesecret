# Translation Guidance for Swedish (Svenska)

This document combines the glossary of standardized terms and language-specific translation notes for Swedish translations of Onetime Secret. It serves as a comprehensive reference for translators working on the Swedish locale to ensure consistency, accuracy, and natural phrasing.

## Overview

The Swedish translation aims to:
- Maintain consistency across all application interfaces
- Use clear, natural phrasing for Swedish-speaking audiences
- Follow technical accuracy for security-related terminology
- Apply appropriate voice and tone for different contexts
- Provide clarity while maintaining professional tone

---

## Core Terminology

### Basic Terms

| English | Svenska (SV) | Context | Notes |
|---------|-------------|---------|-------|
| secret (noun) | hemlighet / meddelande | Central application concept | Context-dependent; "meddelande" for clarity about the message |
| secret (adj) | hemlig/konfidentiell | Descriptive use | |
| passphrase | lösenfras | Authentication method for secrets | Distinct compound term for secret protection |
| password | lösenord | Account login credential | Standard term for account passwords only |
| burn | bränn | Action to delete a secret before viewing | Permanent deletion metaphor |
| view/reveal | visa | Action to access a secret | Display/show content |
| link | länk | URL providing access to a secret | |
| encrypt/encrypted | kryptera/krypterad | Security method | |
| secure | säker | Protection state | |

### User Interface Elements

| English | Svenska (SV) | Context | Notes |
|---------|-------------|---------|-------|
| Share a secret | Dela en hemlighet | Primary action | |
| Create Account | Skapa konto | Registration | |
| Sign In | Logga in | Authentication | |
| Dashboard | Instrumentpanel | User's main page | |
| Settings | Inställningar | Configuration page | |
| Privacy Options | Sekretessalternativ | Secret configuration | |
| Feedback | Återkoppling | User feedback | |

### Status Terms

| English | Svenska (SV) | Context | Notes |
|---------|-------------|---------|-------|
| received | mottagen | Secret has been viewed | |
| burned | bränd | Secret was deleted before viewing | |
| expired | utgången | Secret no longer available due to time | |
| created | skapad | Secret has been generated | Past participle for status |
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
| encrypted at rest | krypterad i vila | Storage protection |

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
| create | skapa | Imperative form for buttons | |
| save | spara | Imperative form for buttons | |
| saved | sparad | Past participle for status | |
| share | dela | Share/distribute | |

### Marketing Terms

| English | Svenska (SV) | Context |
|---------|-------------|---------|
| secure links | säkra länkar | Product feature |
| privacy-first design | integritetsfokuserad design | Design philosophy |
| custom branding | anpassad varumärkning | Premium feature |

---

## Translation Guidelines

### 1. Consistency

- Use the same translation for a term throughout the application
- Maintain standardized terminology from the glossary above
- Key distinctions to preserve:
  - `lösenord` for account passwords
  - `lösenfras` for secret protection
  - `hemlighet` as the core concept (with `meddelande` where context requires clarity)

### 2. Context Awareness

- Consider how the term is used in the application
- Account for surrounding UI elements and user flow
- Ensure translations make sense in their specific context
- Use `hemlighet` for the abstract concept, `meddelande` when referring to the actual message content

### 3. Cultural Adaptation

- Adapt terms to local conventions when necessary
- Use standard Swedish that works across regions
- Use standard technical terms familiar to Swedish-speaking users

### 4. Technical Accuracy

- Security-related terms must be translated accurately
- Prioritize precision over localization for technical terminology
- Use established Swedish technical vocabulary

### 5. Voice and Tone

#### Imperative Voice (for Actions)
Use imperative voice for buttons, links, and user actions:
- `Skapa hemlig länk` (Create secret link)
- `Kopiera till urklipp` (Copy to clipboard)
- `Skapa konto` (Create account)
- `Spara` (Save)
- `Bränn denna hemlighet` (Burn this secret)

#### Passive/Declarative Voice (for Information)
Use passive or declarative voice for informational text, status messages, and descriptions:
- `Hemlighet skapad!` (Secret created!)
- `Din hemliga länk visas nedan.` (Your secret link is shown below.)
- `Hemligheten förstördes manuellt...` (The secret was manually destroyed...)
- `Du visar...` (You are viewing...)
- `Sparad` (Saved - status message)

### 6. Direct Address

- Use informal "du" form consistently when addressing users
- Examples:
  - `Ange ditt lösenord` (Enter your password)
  - `Ditt hemliga meddelande` (Your secret message)
  - `Du visar...` (You are viewing...)
- Swedish naturally flows with direct "du" address in most contexts

### 7. Clarity and Natural Phrasing

- Prioritize natural Swedish expressions over literal translations
- Use standard phrases familiar to Swedish speakers
- Minor phrasing adjustments for improved natural flow
- Simplify complex sentences for better readability:
  - `* En länk som bara kan användas en gång och sedan försvinner för alltid.` (A link that can only be used once and then disappears forever.)

### 8. Completeness

- Ensure all user-facing strings are translated
- Avoid leaving English text in the interface
- Translate help text, descriptions, and metadata

---

## Common Translation Patterns

### User Instructions
Use imperative forms:
- `Ange ditt lösenord` (Enter your password)
- `Kopiera till urklipp` (Copy to clipboard)
- `Ange lösenfrasen här` (Enter the passphrase here)

### Status Descriptions
Use passive voice or past participles:
- `Kopierad till urklipp` (Copied to clipboard)
- `Hemlighet skapad` (Secret created)
- `Sparad` (Saved)
- `Skapad` (Created)

### Help Text and Descriptions
Use declarative sentences in 2nd person informal:
- `Du visar det hemliga innehållet` (You are viewing the secret content)
- `Detta innehåll visas endast en gång` (This content is shown only once)

### Error Messages
Use clear, direct language:
- `Felaktig lösenfras` (Incorrect passphrase)
- `Ett fel har uppstått` (An error has occurred)

---

## Special Considerations

### The Term "Secret"
- Fundamental to the application - translate as `hemlighet` or `meddelande` depending on context
- `hemlighet` emphasizes the confidential item/concept
- `meddelande` clarifies it's a message when context requires
- Examples:
  - `Hemlighet skapad!` (Secret created! - the item)
  - `Ditt hemliga meddelande:` (Your secret message: - the content)

### Password vs. Passphrase
**Critical distinction that must be maintained:**
- **`lösenord`** - for user account login credentials ONLY
- **`lösenfras`** - for protecting individual secrets

This distinction must be maintained throughout the application to avoid confusion.

Examples:
- `Lösenord` - Account login field
- `Felaktig lösenfras` - Incorrect passphrase for secret
- `Ange lösenfrasen här` - Enter the passphrase here (for secret protection)

### The Term "Burn"
Consistently translated as **`bränn`** (verb) / **`bränd`** (past participle):
- Conveys the permanent, irreversible nature of deletion
- Metaphor works well in Swedish
- Examples:
  - `Bränn denna hemlighet` (Burn this secret - button)
  - `Hemligheten är bränd` (The secret is burned - status)

### UI Element Conventions
- Follow platform conventions for the target language
- Use standard Swedish terminology for common UI elements
- Maintain consistency with other Swedish applications

### Technical Security Terms
- Prioritize accuracy over casual localization
- Use established Swedish technical vocabulary
- Examples:
  - `krypterad` (encrypted)
  - `kryptera` (to encrypt)
  - `verifiering` (verification)
  - `autentisering` (authentication)

---

## Rationale for Swedish-Specific Adjustments

The Swedish translation was refined to:

1. **Distinguish `lösenord` and `lösenfras`**: Ensuring "lösenord" is used strictly for account login and "lösenfras" for secret protection
2. **Clarify `secret` context**: Using "hemlighet" for the concept/item and "meddelande" where it improves clarity about the shared information
3. **Improve Natural Flow**: Refining phrasing to sound more natural in Swedish, especially for potentially less technical users (recipients)
4. **Apply Voice Guidelines**: Adjusting verbs in UI elements to imperative mood (`Skapa`, `Spara`) and using declarative/passive voice for informational text (`Hemlighet skapad`, `Sparad`)
5. **Maintain Consistency**: Ensuring terms like `bränn` (burn), `visa` (view), `dela` (share) are used consistently throughout

---

## Summary of Translation Principles

The Swedish translation maintains:

1. **Terminology Consistency** - Standardized key terms throughout the application
2. **Appropriate Voice** - Imperative for actions, passive/declarative for information
3. **Natural Phrasing** - Standard Swedish expressions and sentence structures
4. **Consistent Address** - Informal "du" form when addressing users
5. **Complete Coverage** - All user-facing strings translated
6. **Technical Accuracy** - Precise terminology for security concepts
7. **Clear Distinctions** - Especially between:
   - Account passwords (`lösenord`) and secret passphrases (`lösenfras`)
   - The secret concept (`hemlighet`) and the message content (`meddelande`)
   - Action verbs (imperative) and status messages (declarative/passive)

By following these guidelines, translators can ensure that the Swedish version of Onetime Secret is accurate, consistent, and provides a natural user experience for Swedish-speaking audiences.
