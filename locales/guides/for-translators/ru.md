---
title: Руководство по переводу на русский язык
description: Комплексное руководство по переводу Onetime Secret на русский язык, объединяющее глоссарий терминов и языковые заметки
---

# Translation Guidance for Russian (Русский)

This document combines the glossary of standardized terms and language-specific translation notes for Russian translations of Onetime Secret. It serves as a comprehensive reference for translators working on the Russian locale to ensure consistency, accuracy, and natural phrasing.

## Overview

The Russian translation aims to:
- Maintain consistency across all application interfaces
- Use clear, natural phrasing for Russian-speaking audiences
- Follow technical accuracy for security-related terminology
- Apply appropriate voice and tone for different contexts
- Properly handle Russian grammatical cases, genders, and plural forms

---

## Core Terminology

### Basic Terms

| English | Русский (RU) | Context | Notes |
|---------|-------------|---------|-------|
| secret (noun) | секрет | Central application concept | Masculine gender; appropriate for professional contexts |
| secret (adj) | секретный/безопасный | Descriptive use | |
| passphrase | кодовая фраза | Authentication method for secrets | Compound term distinguishing from account password |
| password | пароль | Account login credential | Standard term for account passwords |
| burn | окончательное удаление | Action to delete a secret before viewing | Permanent deletion |
| view/reveal | просмотр/раскрытие | Action to access a secret | |
| link | ссылка | URL providing access to a secret | Feminine gender |
| encrypt/encrypted | шифрование/зашифрованный | Security method | |
| secure | безопасный | Protection state | |

### User Interface Elements

| English | Русский (RU) | Context | Notes |
|---------|-------------|---------|-------|
| Share a secret | Поделиться секретом | Primary action | |
| Create Account | Создать учётную запись | Registration | |
| Sign In | Войти | Authentication | |
| Dashboard | Панель управления | User's main page | |
| Settings | Настройки | Configuration page | |
| Privacy Options | Параметры конфиденциальности | Secret configuration | |
| Feedback | Обратная связь | User feedback | |

### Status Terms

| English | Русский (RU) | Context | Notes |
|---------|-------------|---------|-------|
| received | получено | Secret has been viewed | |
| burned | окончательно удалено | Secret was deleted before viewing | |
| expired | истёк | Secret no longer available due to time | |
| created | создано | Secret has been generated | |
| active | активный | Secret is available | |
| inactive | неактивный | Secret is not available | |

### Time-Related Terms

| English | Русский (RU) | Context | Notes |
|---------|-------------|---------|-------|
| expires in | истекает через | Time until secret becomes unavailable | |
| day/days | день/дня/дней | Time unit | 1 день, 2-4 дня, 5+ дней |
| hour/hours | час/часа/часов | Time unit | 1 час, 2-4 часа, 5+ часов |
| minute/minutes | минута/минуты/минут | Time unit | 1 минута, 2-4 минуты, 5+ минут |
| second/seconds | секунда/секунды/секунд | Time unit | 1 секунда, 2-4 секунды, 5+ секунд |

### Security Features

| English | Русский (RU) | Context |
|---------|-------------|---------|
| one-time access | одноразовый доступ | Core security feature |
| passphrase protection | защита кодовой фразой | Additional security |
| encrypted in transit | зашифровано при передаче | Data protection method |
| encrypted at rest | зашифровано при хранении | Storage protection |

### Account-Related Terms

| English | Русский (RU) | Context |
|---------|-------------|---------|
| email | электронная почта | User identifier |
| password | пароль | Account authentication |
| account | учётная запись | User profile |
| subscription | подписка | Paid service |
| customer | клиент | Paying user |

### Domain-Related Terms

| English | Русский (RU) | Context |
|---------|-------------|---------|
| custom domain | пользовательский домен | Premium feature |
| domain verification | проверка домена | Setup process |
| DNS record | DNS-запись | Configuration |
| CNAME record | CNAME-запись | DNS configuration |

### Error Messages

| English | Русский (RU) | Context |
|---------|-------------|---------|
| error | ошибка | Problem notification |
| warning | предупреждение | Caution notification |
| oops | упс | Friendly error introduction |

### Buttons and Actions

| English | Русский (RU) | Context | Notes |
|---------|-------------|---------|-------|
| submit | отправить | Form action | |
| cancel | отменить | Negative action | |
| confirm | подтвердить | Positive action | |
| copy to clipboard | копировать в буфер обмена | Utility action | |
| continue | продолжить | Navigation | |
| back | назад | Navigation | |

### Marketing Terms

| English | Русский (RU) | Context |
|---------|-------------|---------|
| secure links | безопасные ссылки | Product feature |
| privacy-first design | дизайн, ориентированный на конфиденциальность | Design philosophy |
| custom branding | персонализированный брендинг | Premium feature |

---

## Translation Guidelines

### 1. Consistency

- Use the same translation for a term throughout the application
- Maintain standardized terminology from the glossary above
- Key distinctions to preserve:
  - `пароль` for account passwords
  - `кодовая фраза` for secret protection
  - `секрет` as the core concept

### 2. Context Awareness

- Consider how the term is used in the application
- Account for surrounding UI elements and user flow
- Ensure translations make sense in their specific context

### 3. Cultural Adaptation

- Adapt terms to local conventions when necessary
- Use modern Russian suitable for digital interfaces
- Use standard technical terms familiar to Russian-speaking users

### 4. Technical Accuracy

- Security-related terms must be translated accurately
- Prioritize precision over localization for technical terminology
- Use established Russian technical vocabulary

### 5. Voice and Tone

- Use polite вы forms for professional tone
- Maintain professional but approachable language
- Ensure consistency in formality level across all interfaces

### 6. Russian Language Specifics

#### Cyrillic Alphabet
- Russian uses Cyrillic alphabet with 33 letters
- Essential: use Ё where needed for clarity (not just Е)
- Never substitute Cyrillic with Latin look-alikes

#### Grammatical Cases
- Russian has 6 cases (именительный, родительный, дательный, винительный, творительный, предложный)
- Apply correct case declension based on context
- Examples of important gender assignments:
  - секрет (masculine)
  - ссылка (feminine)
  - шифрование (neuter)

#### Three Genders
- Masculine, feminine, and neuter
- Ensure proper gender agreement with adjectives and past participles
- Important genders to remember:
  - секрет (masculine) - создан
  - ссылка (feminine) - создана
  - шифрование (neuter) - создано

#### Plural Forms
Russian requires three plural forms based on quantity:
- 1: singular (день, час, минута, секунда)
- 2-4: first plural form (дня, часа, минуты, секунды)
- 5+: second plural form (дней, часов, минут, секунд)

This applies to all countable nouns and must be implemented correctly.

#### Verb Aspects
- Russian verbs have perfective and imperfective aspects
- Perfective: completed action (создать - to create, once)
- Imperfective: ongoing/repeated action (создавать - to be creating)
- Choose appropriate aspect based on context

### 7. Clarity and Natural Phrasing

- Prioritize natural Russian expressions over literal translations
- Use standard phrases familiar to Russian speakers
- Ensure terminology is accessible and professional

### 8. Completeness

- Ensure all user-facing strings are translated
- Avoid leaving English text in the interface
- Translate help text, descriptions, and metadata

---

## Common Translation Patterns

### User Instructions
Use infinitive or imperative forms with polite вы

### Status Descriptions
Use past participles with correct gender agreement

### Help Text and Descriptions
Use declarative sentences with polite second person (вы)

### Error Messages
Use clear, direct language with professional tone

---

## Special Considerations

### The Term "Secret"
- Fundamental to the application - translate consistently as `секрет`
- Masculine gender
- Appropriate for professional contexts
- Emphasizes the confidential nature of the shared item

### Password vs. Passphrase
Critical distinction:
- **`пароль`** - for user account login credentials
- **`кодовая фраза`** - for protecting individual secrets

This distinction must be maintained throughout the application to avoid confusion.

### The Term "Burn"
- Translated as `окончательное удаление` (permanent deletion)
- More natural in digital Russian context than literal translation
- Clearly conveys permanent deletion concept

### Letter Ё Must Be Used
- Always use Ё where needed, not just Е
- Omitting Ё can cause confusion or misreading
- Example: всё (everything) vs все (all/everyone)
- Essential for clarity and proper pronunciation

### Gender Agreement is Critical
- Adjectives and past participles must agree with noun gender
- Incorrect gender agreement sounds unnatural
- Examples:
  - секрет создан (masculine - the secret was created)
  - ссылка создана (feminine - the link was created)
  - сообщение создано (neuter - the message was created)

### Plural Forms Must Be Correct
- Three-form plural system is mandatory
- Native speakers immediately notice errors
- Must implement correct form based on number:
  - 1 день, 21 день, 101 день (singular)
  - 2 дня, 3 дня, 4 дня, 22 дня (2-4 form)
  - 5 дней, 10 дней, 25 дней (5+ form)

### UI Element Conventions
- Follow platform conventions for Russian interfaces
- Use standard Russian terminology for common UI elements
- Maintain consistency with other Russian applications

### Technical Security Terms
- Prioritize accuracy over casual localization
- Use established Russian technical vocabulary
- Examples:
  - `шифрование` (encryption)
  - `зашифрованный` (encrypted)
  - `проверка` (verification)
  - `аутентификация` (authentication)

### Verb Aspect Selection
- Use perfective aspect for completed actions (results)
- Use imperfective aspect for processes or repeated actions
- Examples:
  - создать секрет (create a secret - one action, perfective)
  - создавать секреты (create secrets - repeated, imperfective)

---

## Summary of Translation Principles

The Russian translation maintains:

1. **Terminology Consistency** - Standardized key terms throughout the application
2. **Grammatical Accuracy** - Proper use of 6 cases, 3 genders, and plural forms
3. **Natural Phrasing** - Standard Russian expressions and idioms
4. **Cyrillic Integrity** - Correct use of all Cyrillic letters including Ё
5. **Complete Coverage** - All user-facing strings translated
6. **Technical Accuracy** - Precise terminology for security concepts
7. **Clear Distinctions** - Especially between account passwords and secret passphrases
8. **Professional Tone** - Polite вы form for respectful communication
9. **Aspect Awareness** - Proper use of perfective/imperfective verb aspects

By following these guidelines, translators can ensure that the Russian version of Onetime Secret is accurate, consistent, and provides a natural user experience for Russian-speaking audiences.
