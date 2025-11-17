---
title: Przewodnik tłumaczenia na polski
description: Kompleksowy przewodnik tłumaczenia Onetime Secret na język polski, łączący słowniczek i notatki językowe
---

# Translation Guidance for Polish (Polski)

This document combines the glossary of standardized terms and language-specific translation notes for Polish translations of Onetime Secret. It serves as a comprehensive reference for translators working on the Polish locale to ensure consistency, accuracy, and natural phrasing.

## Overview

The Polish translation aims to:
- Maintain consistency across all application interfaces
- Use clear, natural phrasing for Polish-speaking audiences
- Follow technical accuracy for security-related terminology
- Apply appropriate voice and tone for different contexts
- Respect Polish grammatical rules, especially noun declensions and pluralization

---

## Core Terminology

### Basic Terms

| English | Polski (PL) | Context | Notes |
|---------|------------|---------|-------|
| secret (noun) | sekret | Central application concept | "Sekret" is appropriate across all contexts from "sekret państwowy" (state secret) to business usage without childish connotations |
| secret (adj) | sekretny/poufny | Descriptive use | |
| passphrase | fraza dostępowa | Authentication method for secrets | Compound term distinguishing from account password; implies a longer phrase used for access |
| password | hasło | Account login credential | Standard term for account passwords only |
| burn | zniszczyć/spalić | Action to delete a secret before viewing | Use verb forms: zniszczyć (destroy), spalić (burn) |
| view/reveal | wyświetlić/pokazać | Action to access a secret | |
| link | link/łącze | URL providing access to a secret | "Link" is commonly used and acceptable |
| encrypt/encrypted | szyfrować/zaszyfrowany | Security method | |
| secure | bezpieczny | Protection state | |

### User Interface Elements

| English | Polski (PL) | Context | Notes |
|---------|------------|---------|-------|
| Share a secret | Udostępnij sekret | Primary action | Imperative form |
| Create Account | Utwórz konto | Registration | Imperative form |
| Sign In | Zaloguj się | Authentication | Standard term for logging in |
| Dashboard | Panel/Konto | User's main page | "Panel" for dashboard, "Konto" for account context |
| Settings | Ustawienia | Configuration page | |
| Privacy Options | Opcje prywatności | Secret configuration | |
| Feedback | Opinia | User feedback | |

### Status Terms

| English | Polski (PL) | Context | Notes |
|---------|------------|---------|-------|
| received | otrzymany | Secret has been viewed | |
| burned | zniszczony | Secret was deleted before viewing | Standardized past participle form |
| expired | wygasły | Secret no longer available due to time | |
| created | utworzony | Secret has been generated | |
| active | aktywny | Secret is available | |
| inactive | nieaktywny | Secret is not available | |

### Time-Related Terms

Polish has complex pluralization rules. Numbers are critical for choosing the correct form.

| English | 1 | 2-4 | 5+ | Context |
|---------|---|-----|----|---------|
| second/seconds | sekunda | sekundy | sekund | Time unit |
| minute/minutes | minuta | minuty | minut | Time unit |
| hour/hours | godzina | godziny | godzin | Time unit |
| day/days | dzień | dni | dni | Time unit |
| week/weeks | tydzień | tygodnie | tygodni | Time unit |
| month/months | miesiąc | miesiące | miesięcy | Time unit |
| year/years | rok | lata | lat | Time unit |

**Important**: Numbers ending in 2, 3, 4 (but not 12, 13, 14) use the 2-4 form.
- Examples: 22 sekundy, 33 minuty, 44 godziny

| English | Polski (PL) | Context |
|---------|------------|---------|
| expires in | wygasa za | Time until secret becomes unavailable |

### Security Features

| English | Polski (PL) | Context |
|---------|------------|---------|
| one-time access | jednorazowy dostęp | Core security feature |
| passphrase protection | ochrona frazą dostępową | Additional security |
| encrypted in transit | zaszyfrowany w trakcie przesyłania | Data protection method |
| encrypted at rest | zaszyfrowany w spoczynku | Storage protection |

### Account-Related Terms

| English | Polski (PL) | Context |
|---------|------------|---------|
| email | e-mail | User identifier |
| password | hasło | Account authentication only |
| account | konto | User profile |
| subscription | subskrypcja | Paid service |
| customer | klient | Paying user |

### Domain-Related Terms

| English | Polski (PL) | Context |
|---------|------------|---------|
| custom domain | domena niestandardowa | Premium feature |
| domain verification | weryfikacja domeny | Setup process |
| DNS record | rekord DNS | Configuration |
| CNAME record | rekord CNAME | DNS configuration |

### Error Messages

| English | Polski (PL) | Context |
|---------|------------|---------|
| error | błąd | Problem notification |
| warning | ostrzeżenie | Caution notification |
| oops | ups | Friendly error introduction |

### Buttons and Actions

Polish uses imperative mood (tryb rozkazujący) for buttons and actions. Use the 2nd person singular informal form.

| Infinitive | Imperative (2nd person singular) | English | Context |
|------------|----------------------------------|---------|---------|
| utworzyć | utwórz | create | Form action |
| zapisać | zapisz | save | Form action |
| usunąć | usuń | delete | Destructive action |
| wysłać | wyślij | submit/send | Form action |
| anulować | anuluj | cancel | Negative action |
| potwierdzić | potwierdź | confirm | Positive action |
| kopiować | kopiuj | copy | Utility action |
| kontynuować | kontynuuj | continue | Navigation |

| English | Polski (PL) | Context | Notes |
|---------|------------|---------|-------|
| submit | wyślij | Form action | Imperative form |
| cancel | anuluj | Negative action | Imperative form |
| confirm | potwierdź | Positive action | Imperative form |
| copy to clipboard | kopiuj do schowka | Utility action | Imperative form |
| continue | kontynuuj | Navigation | Imperative form |
| back | wstecz | Navigation | Adverb form |

### Marketing Terms

| English | Polski (PL) | Context |
|---------|------------|---------|
| secure links | bezpieczne linki | Product feature |
| privacy-first design | projekt z priorytetem prywatności | Design philosophy |
| custom branding | niestandardowy branding | Premium feature |

### Application Features

| English | Polski (PL) | Context |
|---------|------------|---------|
| Create a secret | Utwórz sekret | Primary user action |
| View secret | Wyświetl sekret | Access to secret |
| Secret link | Link do sekretu / Tajny link | Secret URL |
| Share | Udostępnij | Sharing action |
| Download | Pobierz | File download |
| Upload | Prześlij | File upload |

### System Messages

Use passive voice or past participles for system messages and status updates.

| English | Polski (PL) | Context |
|---------|------------|---------|
| Changes saved | Zmiany zapisane | Save confirmation |
| File deleted | Plik usunięty | Delete confirmation |
| Upload complete | Przesyłanie zakończone | Upload status |
| Connection lost | Połączenie utracone | Connection error |
| Loading... | Ładowanie... | Loading state |

---

## Translation Guidelines

### 1. Consistency

- Use the same translation for a term throughout the application
- Maintain standardized terminology from the glossary above
- Key distinctions to preserve:
  - `hasło` for account passwords only
  - `fraza dostępowa` for secret protection
  - `sekret` as the core concept (never "wiadomość" unless contextually necessary)

### 2. Context Awareness

- Consider how the term is used in the application
- Account for surrounding UI elements and user flow
- Ensure translations make sense in their specific context
- Respect grammatical cases (nominative, genitive, etc.) based on sentence structure

### 3. Cultural Adaptation

- Adapt terms to Polish conventions when necessary
- Use standard technical terms familiar to Polish-speaking users
- Prefer naturalized terms over direct translations when they exist in Polish IT vocabulary

### 4. Technical Accuracy

- Security-related terms must be translated accurately
- Prioritize precision over casual localization for technical terminology
- Use established Polish technical vocabulary
- Many English technical terms are commonly used in Polish IT contexts (e.g., "link", "e-mail")

### 5. Voice and Tone

#### Imperative Voice (for Actions)
Use imperative mood (2nd person singular informal) for buttons, links, and user actions:
- `Utwórz sekret` (Create secret)
- `Zapisz zmiany` (Save changes)
- `Kopiuj do schowka` (Copy to clipboard)
- `Wyślij` (Submit)

#### Passive/Declarative Voice (for Information)
Use passive voice or past participles for informational text, status messages, and descriptions:
- `Twoja wiadomość jest wyświetlona poniżej.` (Your message is shown below.)
- `Link do sekretu został utworzony...` (The secret link has been created...)
- `Sekret został zniszczony ręcznie...` (The secret was manually destroyed...)
- `Wyświetlasz...` (You are viewing...)

### 6. Direct Address

- Use informal "ty" form consistently when addressing users (2nd person singular)
- Examples:
  - `Wprowadź swoje hasło` (Enter your password)
  - `Twoja bezpieczna wiadomość` (Your secure message)
  - `Wyświetlasz...` (You are viewing...)
- When direct address can be avoided, use 3rd person or passive constructions

### 7. Clarity and Natural Phrasing

- Prioritize natural Polish expressions over literal translations
- Use standard phrases familiar to Polish speakers
- Avoid overly formal or bureaucratic language
- Keep sentences clear and concise

### 8. Completeness

- Ensure all user-facing strings are translated
- Avoid leaving English text in the interface
- Translate help text, descriptions, and metadata
- Pay attention to pluralization forms

---

## Polish Grammar Considerations

### Noun Declensions and Cases

Polish uses seven grammatical cases. Pay attention to context:

**Example with "sekret" (secret):**
- Nominative (mianownik): `sekret` - "Secret was created"
- Genitive (dopełniacz): `sekretu` - "Link of the secret"
- Dative (celownik): `sekretowi` - "Give to the secret"
- Accusative (biernik): `sekret` - "View the secret"
- Instrumental (narzędnik): `sekretem` - "Protected by secret"
- Locative (miejscownik): `(o) sekrecie` - "About the secret"
- Vocative (wołacz): `sekrecie!` - Rarely used

Common UI patterns:
- "Link do sekretu" (genitive) - Link of/to the secret
- "Utwórz sekret" (accusative) - Create a secret
- "Status sekretu" (genitive) - Secret's status

### Pluralization Rules

Polish pluralization is complex and depends on the number:

#### For Objects (like secrets, links, files):

| 1 | 2-4 | 5+ | Notes |
|---|-----|----|-------|
| 1 sekret | 2 sekrety | 5 sekretów | |
| 1 link | 2 linki | 5 linków | |
| 1 plik | 2 pliki | 5 plików | |
| 1 użytkownik | 2 użytkowników | 5 użytkowników | Exception: masculine personal nouns |
| 1 konto | 2 konta | 5 kont | |

Numbers ending in 2, 3, 4 (except 12, 13, 14) use the 2-4 form:
- 22 sekrety, 33 linki, 44 pliki

Numbers ending in 12, 13, 14 use the 5+ form:
- 12 sekretów, 13 linków, 114 plików

### Verb Forms

#### Imperative (Commands - for buttons):
Use 2nd person singular:
- `Utwórz` (Create)
- `Zapisz` (Save)
- `Usuń` (Delete)
- `Wyślij` (Submit)

#### Infinitive (for menu items or descriptions):
- `Utworzyć nowy sekret` (To create a new secret)
- `Wyświetlić ustawienia` (To view settings)

#### Past Participles (for status messages):
Match gender and number:
- `Utworzony` (masculine) - Created
- `Zapisane` (neuter) - Saved
- `Usunięte` (neuter) - Deleted

---

## Common Translation Patterns

### User Instructions
Use imperative forms:
- `Wprowadź hasło` (Enter password)
- `Kopiuj do schowka` (Copy to clipboard)
- `Wybierz opcję` (Select option)

### Status Descriptions
Use passive voice or past participles:
- `Skopiowano do schowka` (Copied to clipboard)
- `Sekret został utworzony` (The secret has been created)
- `Link wygasł` (The link expired)

### Help Text and Descriptions
Use declarative sentences in 2nd person informal:
- `Wyświetlasz zawartość sekretu` (You are viewing the secret content)
- `Ta zawartość jest pokazywana tylko raz` (This content is shown only once)
- `Twój sekret zostanie zniszczony po wyświetleniu` (Your secret will be destroyed after viewing)

### Error Messages
Use clear, direct language:
- `Nieprawidłowa fraza dostępowa` (Incorrect passphrase)
- `Wystąpił błąd` (An error occurred)
- `Sekret nie został znaleziony` (Secret not found)

### Time Expressions
Pay attention to pluralization:
- `Wygasa za 1 minutę` (Expires in 1 minute)
- `Wygasa za 2 minuty` (Expires in 2 minutes)
- `Wygasa za 5 minut` (Expires in 5 minutes)
- `Wygasa za 22 minuty` (Expires in 22 minutes)

---

## Special Considerations

### The Term "Sekret" (Secret)

Polish "sekret" is fundamental to the application and should be translated consistently:
- Unlike some languages (Danish, Dutch), Polish "sekret" is appropriate across all contexts
- It works naturally from "sekret państwowy" (state secret) to everyday business usage
- No childish or trivial connotations
- Maintains security context naturally
- DO NOT use "wiadomość" (message) as a general replacement unless the context specifically refers to a message format

**Correct usage:**
- ✓ `Utwórz sekret` (Create a secret)
- ✓ `Wyświetl sekret` (View secret)
- ✓ `Link do sekretu` (Secret link)
- ✓ `Status sekretu` (Secret status)

**Incorrect usage:**
- ✗ `Utwórz wiadomość` (Create a message) - Only use if context is specifically about messages
- ✗ `Wyświetl informację` (View information) - Too generic

### Password vs. Passphrase - Critical Distinction

This is the most critical terminology distinction in the Polish translation:

**`hasło` (Password)** - ONLY for user account login credentials
- `Wprowadź hasło do konta` (Enter account password)
- `Zmień hasło` (Change password)
- `Zapomniane hasło` (Forgot password)

**`fraza dostępowa` (Passphrase)** - ONLY for protecting individual secrets
- `Chroń frazą dostępową` (Protect with passphrase)
- `Wprowadź frazę dostępową` (Enter passphrase)
- `Chronione frazą dostępową` (Protected with passphrase)
- `Nieprawidłowa fraza dostępowa` (Incorrect passphrase)

This distinction must be maintained rigorously throughout the application to avoid user confusion.

**Why "Fraza dostępowa"?**
- "Fraza" = phrase (suggests something longer, more complex)
- "Dostępowa" = access (emphasizes its purpose for accessing the secret)
- Together: "Access phrase" - clearly different from a standard password
- Communicates the concept of a longer, phrase-based protection mechanism

### UI Element Conventions

- Follow Polish software conventions for common UI elements
- Use standard Polish terminology for buttons and actions
- Maintain consistency with other Polish applications
- Many technical terms can remain in English form if commonly used (e.g., "link", "e-mail")

### Technical Security Terms

Prioritize accuracy over casual localization:
- `zaszyfrowany` (encrypted)
- `szyfrować` (to encrypt)
- `weryfikacja` (verification)
- `uwierzytelnianie` (authentication)
- `bezpieczeństwo` (security)
- `prywatność` (privacy)

---

## Summary of Translation Principles

The Polish translation maintains:

1. **Terminology Consistency** - Standardized key terms throughout the application, especially the critical distinction between `hasło` (account password) and `fraza dostępowa` (secret passphrase)

2. **Appropriate Use of "Sekret"** - Polish "sekret" is used consistently as it naturally maintains security context across all uses without problematic connotations

3. **Appropriate Voice** - Imperative for actions (buttons, commands), passive/declarative for information and status messages

4. **Natural Phrasing** - Standard Polish expressions and natural word order

5. **Consistent Address** - Informal "ty" form (2nd person singular) when addressing users

6. **Correct Grammar** - Proper noun declensions, cases, and pluralization rules following Polish grammar

7. **Complete Coverage** - All user-facing strings translated with attention to Polish linguistic requirements

8. **Technical Accuracy** - Precise terminology for security concepts while using naturalized technical terms where appropriate

By following these guidelines, translators can ensure that the Polish version of Onetime Secret is accurate, consistent, and provides a natural user experience for Polish-speaking audiences while maintaining the critical security-focused terminology that defines the application.
