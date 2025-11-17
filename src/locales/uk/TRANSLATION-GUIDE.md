# Translation Guidance for Ukrainian (Українська)

This document combines the glossary of standardized terms and language-specific translation notes for Ukrainian translations of Onetime Secret. It serves as a comprehensive reference for translators working on the Ukrainian locale to ensure consistency, accuracy, and natural phrasing.

## Overview

The Ukrainian translation aims to:
- Maintain consistency across all application interfaces
- Use clear, natural phrasing for Ukrainian-speaking audiences
- Follow technical accuracy for security-related terminology
- Apply appropriate voice and tone for different contexts
- Ensure proper gender and case agreement throughout

---

## Core Terminology

### Basic Terms

| English | Українська | Context | Notes |
|---------|-----------|---------|-------|
| secret (noun) | таємниця | Central application concept | Avoid "секрет" - overly personal connotation |
| secret (adj) | таємний/таємна/таємне | Descriptive use | Adapt to gender; avoid "секретний" |
| secret message | таємне повідомлення | Product feature | Always "таємне", never "секретне" |
| secret content | таємний вміст | Security feature | Masculine gender agreement |
| secret link(s) | таємне посилання/таємні посилання | URL feature | ALWAYS "таємні", never "секретні" |
| passphrase | парольна фраза, ключова фраза | Authentication method for secrets | Distinguishes from account password |
| password | пароль | Account login credential | For account access only |
| burn | знищити, спалити | Action to delete a secret before viewing | Emphasizes permanence |
| view/reveal | переглянути/показати | Action to access a secret | |
| link | посилання | URL providing access to a secret | |
| encrypt/encrypted | зашифрувати/зашифрований | Security method | |
| secure | безпечний | Protection state | |
| colonel | адміністратор | Administrator role | Translate to common term; do not use "полковник" |
| one-time | одноразовий/одноразова/одноразове | Single-use descriptor | Adjective, adapt to gender |
| Onetime | Onetime | Part of brand name | DO NOT translate |

### User Interface Elements

| English | Українська | Context | Notes |
|---------|-----------|---------|-------|
| Share a secret | Поділитися таємницею | Primary action | |
| Create Account | Створити обліковий запис | Registration | |
| Sign In | Увійти | Authentication | Common term for login |
| Dashboard | Панель керування | User's main page | |
| Settings | Налаштування | Configuration page | |
| Privacy Options | Параметри конфіденційності | Secret configuration | |
| Feedback | Зворотний зв'язок | User feedback | |

### Status Terms

| English | Українська | Context | Notes |
|---------|-----------|---------|-------|
| received | отримано | Secret has been viewed | Passive voice |
| burned | знищено | Secret was deleted before viewing | Passive voice |
| expired | закінчився термін дії | Secret no longer available due to time | Full phrase preferred |
| created | створено | Secret has been generated | Passive voice |
| active | активна | Secret is available | Feminine gender (таємниця) |
| inactive | неактивна | Secret is not available | Feminine gender (таємниця) |

### Time-Related Terms

| English | Українська | Context |
|---------|-----------|---------|
| expires in | закінчується через | Time until secret becomes unavailable |
| day/days | день/дні/днів | Time unit (singular/2-4/5+) |
| hour/hours | година/години/годин | Time unit (singular/2-4/5+) |
| minute/minutes | хвилина/хвилини/хвилин | Time unit (singular/2-4/5+) |
| second/seconds | секунда/секунди/секунд | Time unit (singular/2-4/5+) |

### Security Features

| English | Українська | Context |
|---------|-----------|---------|
| one-time access | одноразовий доступ | Core security feature |
| passphrase protection | захист парольною фразою | Additional security |
| encrypted in transit | зашифровано під час передачі | Data protection method |
| encrypted at rest | зашифровано в стані спокою | Storage protection |

### Account-Related Terms

| English | Українська | Context |
|---------|-----------|---------|
| email | електронна пошта, e-mail | User identifier |
| password | пароль | Account authentication |
| account | обліковий запис | User profile |
| subscription | підписка | Paid service |
| customer | клієнт | Paying user |

### Domain-Related Terms

| English | Українська | Context |
|---------|-----------|---------|
| custom domain | користувацький домен | Premium feature |
| domain verification | перевірка домену | Setup process |
| DNS record | DNS-запис | Configuration |
| CNAME record | CNAME-запис | DNS configuration |

### Error Messages

| English | Українська | Context |
|---------|-----------|---------|
| error | помилка | Problem notification |
| warning | попередження | Caution notification |
| oops | ой | Friendly error introduction |

### Buttons and Actions

| English | Українська | Context | Notes |
|---------|-----------|---------|-------|
| submit | надіслати | Form action | |
| cancel | скасувати | Negative action | |
| confirm | підтвердити | Positive action | |
| copy to clipboard | скопіювати в буфер обміну | Utility action | Standard Ukrainian phrase |
| continue | продовжити | Navigation | |
| back | назад | Navigation | |

### Marketing Terms

| English | Українська | Context |
|---------|-----------|---------|
| secure links | безпечні посилання | Product feature |
| privacy-first design | дизайн з пріоритетом конфіденційності | Design philosophy |
| custom branding | користувацький брендинг | Premium feature |

---

## Translation Guidelines

### 1. Consistency

- Use the same translation for a term throughout the application
- Maintain standardized terminology from the glossary above
- Key distinctions to preserve:
  - `пароль` for account passwords
  - `парольна фраза` or `ключова фраза` for secret protection
  - `таємниця` (noun) vs `таємний/таємна/таємне` (adjective)

### 2. Context Awareness

- Consider how the term is used in the application
- Account for surrounding UI elements and user flow
- Ensure translations make sense in their specific context
- Pay attention to grammatical context requiring specific cases

### 3. Cultural Adaptation

- Adapt terms to Ukrainian conventions when necessary
- Use standard technical terms familiar to Ukrainian-speaking users
- Avoid Russian loanwords when Ukrainian equivalents exist

### 4. Technical Accuracy

- Security-related terms must be translated accurately
- Prioritize precision over casual localization
- Use established Ukrainian technical vocabulary

### 5. Voice and Tone

#### Imperative Voice (for Actions)
Use infinitive or imperative forms for buttons, links, and user actions:
- `Зберегти зміни` (Save changes)
- `Видалити файл` (Delete file)
- `Створити таємницю` (Create secret)
- `Скопіювати в буфер обміну` (Copy to clipboard)

#### Passive/Declarative Voice (for Information)
Use passive voice or past participles for informational text and status messages:
- `Зміни збережено` (Changes saved)
- `Файл видалено` (File deleted)
- `Таємницю створено` (Secret created)
- `Посилання скопійовано` (Link copied)

### 6. Direct Address

- Use polite second person "ви" (not informal "ти") when addressing users
- Examples:
  - `Введіть ваш пароль` (Enter your password)
  - `Ваше таємне повідомлення` (Your secret message)
  - `Ви створюєте таємницю` (You are creating a secret)

### 7. Clarity and Natural Phrasing

- Prioritize natural Ukrainian expressions over literal translations
- Avoid calques from English
- Use standard phrases familiar to Ukrainian speakers
- Read translations aloud to ensure natural flow

### 8. Completeness

- Ensure all user-facing strings are translated
- Avoid leaving English text in the interface
- Translate help text, descriptions, and metadata

---

## Ukrainian Grammar Specifics

### Gender Agreement

Ukrainian has three genders (masculine, feminine, neuter). Ensure adjectives agree with nouns:

| Noun | Gender | Example with "таємний" |
|------|--------|----------------------|
| повідомлення | neuter | таємне повідомлення |
| посилання | neuter | таємне посилання |
| таємниця | feminine | нова таємниця |
| вміст | masculine | таємний вміст |
| доступ | masculine | одноразовий доступ |

### Case System

Use correct case forms depending on grammatical context:

| Case | Name | Example with "таємне посилання" |
|------|------|-------------------------------|
| Nominative | Називний | таємне посилання існує |
| Genitive | Родовий | створення таємного посилання |
| Dative | Давальний | доступ до таємного посилання |
| Accusative | Знахідний | створити таємне посилання |
| Instrumental | Орудний | поділитися таємним посиланням |
| Locative | Місцевий | у таємному посиланні |

### Number Agreement

Ukrainian has special rules for number agreement:

| Quantity | Form | Example |
|----------|------|---------|
| 1 | Singular | 1 день, 1 година, 1 хвилина |
| 2-4 | Plural genitive singular | 2/3/4 дні, години, хвилини |
| 5+ | Plural genitive plural | 5+ днів, годин, хвилин |

---

## Common Translation Patterns

### User Instructions
Use infinitive or imperative forms:
- `Введіть ваш пароль` (Enter your password)
- `Скопіювати в буфер обміну` (Copy to clipboard)

### Status Descriptions
Use passive voice or past participles:
- `Скопійовано в буфер обміну` (Copied to clipboard)
- `Таємницю створено` (The secret has been created)

### Help Text and Descriptions
Use declarative sentences in 2nd person formal:
- `Ви переглядаєте таємний вміст` (You are viewing the secret content)
- `Цей вміст показується лише один раз` (This content is shown only once)

### Error Messages
Use clear, direct language:
- `Неправильна парольна фраза` (Incorrect passphrase)
- `Сталася помилка` (An error has occurred)

---

## Special Considerations

### The Term "Таємниця"
- Fundamental to the application - translate consistently as `таємниця`
- Use `таємний/таємна/таємне` as adjective with proper gender agreement
- Avoid `секрет/секретний` - these carry overly personal connotations
- Examples of correct usage:
  - ✓ "Створити таємне повідомлення"
  - ✓ "Поділитися таємницею"
  - ✓ "Таємні посилання"
  - ✗ "Створити секрет"
  - ✗ "Секретні посилання"

### Password vs. Passphrase
Critical distinction:
- **`пароль`** - for user account login credentials
- **`парольна фраза`** or **`ключова фраза`** - for protecting individual secrets

This distinction must be maintained throughout the application to avoid confusion.

Examples:
- ✓ "Введіть ваш пароль для входу" (Enter your password to log in)
- ✓ "Захистити парольною фразою" (Protect with passphrase)
- ✗ "Захистити паролем" (Protect with password)

### Brand Names
Never translate brand or product names:
- **Onetime Secret** - DO NOT translate to "Одноразова Таємниця"
- **Identity Plus** - DO NOT translate to "Ідентичність Плюс"
- **Global Elite** - DO NOT translate to "Глобальна Еліта"
- **Custom Install** - DO NOT translate

### UI Element Conventions
- Follow platform conventions for Ukrainian language
- Use standard Ukrainian terminology for common UI elements
- Maintain consistency with other Ukrainian applications

### Technical Security Terms
- Prioritize accuracy over casual localization
- Use established Ukrainian technical vocabulary
- Examples:
  - `зашифрований` (encrypted)
  - `зашифрувати` (to encrypt)
  - `перевірка` (verification)
  - `автентифікація` (authentication)

---

## Critical Quality Checklist

Before approving a translation, verify:

1. ✓ **Brand names are not translated** (Onetime Secret, Identity Plus, etc.)
2. ✓ **"Secret" translates to "таємний/таємниця"**, not "секретний/секрет"
3. ✓ **Gender and case agreement is correct** for all adjectives and nouns
4. ✓ **"Password" and "passphrase" are distinguished** (`пароль` vs `парольна фраза`)
5. ✓ **Consistency with glossary** is maintained throughout
6. ✓ **Natural-sounding Ukrainian** when read aloud
7. ✓ **Proper number agreement** for time units (день/дні/днів)
8. ✓ **Formal "ви" is used** for user address (not informal "ти")

---

## Summary of Translation Principles

The Ukrainian translation maintains:

1. **Terminology Consistency** - Standardized key terms throughout the application
2. **Appropriate Voice** - Imperative for actions, passive/declarative for information
3. **Natural Phrasing** - Standard Ukrainian expressions avoiding English calques
4. **Formal Address** - Polite "ви" form when addressing users
5. **Complete Coverage** - All user-facing strings translated
6. **Technical Accuracy** - Precise terminology for security concepts
7. **Clear Distinctions** - Especially between account passwords and secret passphrases
8. **Grammatical Correctness** - Proper gender, case, and number agreement
9. **Brand Preservation** - Product and brand names remain in English

By following these guidelines, translators can ensure that the Ukrainian version of Onetime Secret is accurate, consistent, and provides a natural user experience for Ukrainian-speaking audiences.
