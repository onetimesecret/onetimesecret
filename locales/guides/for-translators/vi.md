---
title: Hướng dẫn dịch thuật cho tiếng Việt
description: Hướng dẫn toàn diện để dịch Onetime Secret sang tiếng Việt, kết hợp bảng thuật ngữ và ghi chú ngôn ngữ
---

# Translation Guidance for Vietnamese (Tiếng Việt)

This document combines the glossary of standardized terms and language-specific translation notes for Vietnamese translations of Onetime Secret. It serves as a comprehensive reference for translators working on the Vietnamese locale to ensure consistency, accuracy, and natural phrasing.

## Overview

The Vietnamese translation aims to:
- Maintain consistency across all application interfaces
- Use clear, natural phrasing for Vietnamese-speaking audiences
- Follow technical accuracy for security-related terminology
- Apply appropriate voice and tone for different contexts
- Properly handle Vietnamese tonal system and diacritics

---

## Core Terminology

### Basic Terms

| English | Tiếng Việt (VI) | Context | Notes |
|---------|-----------------|---------|-------|
| secret (noun) | bí mật | Central application concept | Appropriate for professional contexts |
| secret (adj) | bí mật/an toàn | Descriptive use | |
| passphrase | cụm mật khẩu | Authentication method for secrets | Compound term distinguishing from account password |
| password | mật khẩu | Account login credential | Standard term for account passwords |
| burn | xóa vĩnh viễn | Action to delete a secret before viewing | Delete permanently |
| view/reveal | xem/hiển thị | Action to access a secret | |
| link | liên kết | URL providing access to a secret | |
| encrypt/encrypted | mã hóa/đã mã hóa | Security method | |
| secure | an toàn | Protection state | |

### User Interface Elements

| English | Tiếng Việt (VI) | Context | Notes |
|---------|-----------------|---------|-------|
| Share a secret | Chia sẻ bí mật | Primary action | |
| Create Account | Tạo tài khoản | Registration | |
| Sign In | Đăng nhập | Authentication | |
| Dashboard | Bảng điều khiển | User's main page | |
| Settings | Cài đặt | Configuration page | |
| Privacy Options | Tùy chọn quyền riêng tư | Secret configuration | |
| Feedback | Phản hồi | User feedback | |

### Status Terms

| English | Tiếng Việt (VI) | Context | Notes |
|---------|-----------------|---------|-------|
| received | đã nhận | Secret has been viewed | Uses past marker đã |
| burned | đã xóa vĩnh viễn | Secret was deleted before viewing | |
| expired | đã hết hạn | Secret no longer available due to time | |
| created | đã tạo | Secret has been generated | |
| active | hoạt động | Secret is available | |
| inactive | không hoạt động | Secret is not available | |

### Time-Related Terms

| English | Tiếng Việt (VI) | Context | Notes |
|---------|-----------------|---------|-------|
| expires in | hết hạn sau | Time until secret becomes unavailable | |
| day/days | ngày | Time unit | No plural form needed |
| hour/hours | giờ | Time unit | No plural form needed |
| minute/minutes | phút | Time unit | No plural form needed |
| second/seconds | giây | Time unit | No plural form needed |

### Security Features

| English | Tiếng Việt (VI) | Context |
|---------|-----------------|---------|
| one-time access | truy cập một lần | Core security feature |
| passphrase protection | bảo vệ bằng cụm mật khẩu | Additional security |
| encrypted in transit | mã hóa khi truyền | Data protection method |
| encrypted at rest | mã hóa khi lưu trữ | Storage protection |

### Account-Related Terms

| English | Tiếng Việt (VI) | Context |
|---------|-----------------|---------|
| email | email | User identifier |
| password | mật khẩu | Account authentication |
| account | tài khoản | User profile |
| subscription | đăng ký | Paid service |
| customer | khách hàng | Paying user |

### Domain-Related Terms

| English | Tiếng Việt (VI) | Context |
|---------|-----------------|---------|
| custom domain | tên miền tùy chỉnh | Premium feature |
| domain verification | xác minh tên miền | Setup process |
| DNS record | bản ghi DNS | Configuration |
| CNAME record | bản ghi CNAME | DNS configuration |

### Error Messages

| English | Tiếng Việt (VI) | Context |
|---------|-----------------|---------|
| error | lỗi | Problem notification |
| warning | cảnh báo | Caution notification |
| oops | rất tiếc | Friendly error introduction |

### Buttons and Actions

| English | Tiếng Việt (VI) | Context | Notes |
|---------|-----------------|---------|-------|
| submit | gửi | Form action | |
| cancel | hủy | Negative action | |
| confirm | xác nhận | Positive action | |
| copy to clipboard | sao chép vào clipboard | Utility action | |
| continue | tiếp tục | Navigation | |
| back | quay lại | Navigation | |

### Marketing Terms

| English | Tiếng Việt (VI) | Context |
|---------|-----------------|---------|
| secure links | liên kết an toàn | Product feature |
| privacy-first design | thiết kế ưu tiên quyền riêng tư | Design philosophy |
| custom branding | thương hiệu tùy chỉnh | Premium feature |

---

## Translation Guidelines

### 1. Consistency

- Use the same translation for a term throughout the application
- Maintain standardized terminology from the glossary above
- Key distinctions to preserve:
  - `mật khẩu` for account passwords
  - `cụm mật khẩu` for secret protection
  - `bí mật` as the core concept

### 2. Context Awareness

- Consider how the term is used in the application
- Account for surrounding UI elements and user flow
- Ensure translations make sense in their specific context

### 3. Cultural Adaptation

- Adapt terms to local conventions when necessary
- Use modern Vietnamese suitable for digital interfaces
- Use standard technical terms familiar to Vietnamese-speaking users

### 4. Technical Accuracy

- Security-related terms must be translated accurately
- Prioritize precision over localization for technical terminology
- Use established Vietnamese technical vocabulary

### 5. Voice and Tone

- Use "bạn" for neutral, respectful formality appropriate for professional contexts
- Maintain professional but approachable language
- Ensure consistency in formality level across all interfaces

### 6. Vietnamese Language Specifics

#### Analytic Language Structure
- Vietnamese is an analytic language with no inflection or conjugation
- Words do not change form based on tense, number, or gender
- Grammatical relationships expressed through word order and particles
- No verb conjugation: "tôi tạo" (I create), "chúng tôi tạo" (we create)

#### Tonal System
- Vietnamese has 6 tones that are essential for meaning
- Tones: level (no mark), sharp/rising (sắc), falling (huyền), tumbling (hỏi), broken rising (ngã), heavy (nặng)
- Incorrect tones completely change meaning
- Examples:
  - ma (ghost), má (mother), mà (but), mả (tomb), mã (code), mạ (rice seedling)
- All tone marks must be preserved accurately

#### Vietnamese Script and Diacritics
- Uses Latin alphabet with additional diacritics
- Vowel modifications: ă, â, ê, ô, ơ, ư
- Tone marks: ́ (sắc), ̀ (huyền), ̉ (hỏi), ̃ (ngã), ̣ (nặng)
- Both vowel and tone diacritics can appear on same letter: ế, ồ, ữ
- Never omit diacritics - they are essential to meaning

#### No Grammatical Gender or Plural
- Vietnamese has no grammatical gender
- No plural forms for most nouns (unless emphasis needed)
- Same word form for singular and plural: ngày (day/days), giờ (hour/hours)
- Quantity expressed through numbers or quantifiers: 3 ngày (3 days)

#### Tense Markers
- Tense indicated by markers, not verb changes
- đã - past tense marker
- sẽ - future tense marker
- đang - progressive aspect marker
- Examples:
  - đã tạo (created/have created)
  - sẽ tạo (will create)
  - đang tạo (is/are creating)

#### Word Order
- Subject-Verb-Object (SVO) like English
- Adjectives and modifiers typically follow nouns
- Examples:
  - bí mật (secret - noun)
  - thông tin bí mật (secret information - adjective follows)

#### Syllable Spacing
- Vietnamese words can be monosyllabic or multisyllabic
- Compound words written with spaces between syllables
- Examples:
  - mã hóa (encryption - two syllables, space between)
  - bảo mật (security - two syllables, space between)
  - tài khoản (account - two syllables, space between)
- Never write without spaces like German compounds

### 7. Clarity and Natural Phrasing

- Prioritize natural Vietnamese expressions over literal translations
- Use standard phrases familiar to Vietnamese speakers
- Ensure terminology is accessible and professional

### 8. Completeness

- Ensure all user-facing strings are translated
- Avoid leaving English text in the interface
- Translate help text, descriptions, and metadata

---

## Common Translation Patterns

### User Instructions
Use imperative verbs without subject (understood "bạn")

### Status Descriptions
Use past tense markers (đã) for completed states

### Help Text and Descriptions
Use declarative sentences with neutral tone

### Error Messages
Use clear, direct language with respectful tone

---

## Special Considerations

### The Term "Secret"
- Fundamental to the application - translate consistently as `bí mật`
- Appropriate for professional contexts
- Emphasizes the confidential nature of the shared item

### Password vs. Passphrase
Critical distinction:
- **`mật khẩu`** - for user account login credentials
- **`cụm mật khẩu`** - for protecting individual secrets (cụm = phrase/cluster)

This distinction must be maintained throughout the application to avoid confusion.

### The Term "Burn"
- Translated as `xóa vĩnh viễn` (delete permanently)
- More natural in digital Vietnamese context than literal translation
- Clearly conveys permanent deletion concept

### Tones Cannot Be Omitted
- Vietnamese tones are not optional
- Omitting tones makes text unreadable or changes meaning completely
- Always include all tone marks: á, à, ả, ã, ạ
- Example of importance:
  - ma (ghost), má (mother), mà (but), mả (tomb), mã (code), mạ (rice seedling)

### Diacritics Are Essential
- All Vietnamese diacritics must be preserved
- Both vowel modifications (ă, â, ê, ô, ơ, ư) and tone marks
- Never substitute with unaccented letters
- Example: hoa (flower) vs hoà (harmony) vs hòa (peace/blend)

### No Plural Forms Needed
- Unlike English, Vietnamese doesn't mark plurals on nouns
- Use same form for singular and plural
- Context and numbers indicate quantity
- Examples:
  - 1 ngày (1 day)
  - 5 ngày (5 days) - NOT "5 ngàys"

### Tense Markers Placement
- Place tense markers before main verb
- đã, sẽ, đang come before the verb they modify
- Examples:
  - Bí mật đã được tạo (The secret has been created)
  - Liên kết sẽ hết hạn (The link will expire)

### UI Element Conventions
- Follow platform conventions for Vietnamese interfaces
- Use standard Vietnamese terminology for common UI elements
- Maintain consistency with other Vietnamese applications
- Use "bạn" for respectful but friendly address

### Technical Security Terms
- Prioritize accuracy over casual localization
- Use established Vietnamese technical vocabulary
- Examples:
  - `mã hóa` (encryption)
  - `đã mã hóa` (encrypted)
  - `xác minh` (verification)
  - `xác thực` (authentication)

### Simplicity of Vietnamese Grammar
- No verb conjugation (simplifies translation)
- No grammatical gender (simplifies agreement)
- No plural marking (simplifies noun forms)
- Main complexity is in tonal system and diacritics

---

## Summary of Translation Principles

The Vietnamese translation maintains:

1. **Terminology Consistency** - Standardized key terms throughout the application
2. **Tonal Accuracy** - Complete and correct use of all 6 Vietnamese tones
3. **Natural Phrasing** - Standard Vietnamese expressions and idioms
4. **Diacritical Integrity** - All vowel modifications and tone marks preserved
5. **Complete Coverage** - All user-facing strings translated
6. **Technical Accuracy** - Precise terminology for security concepts
7. **Clear Distinctions** - Especially between account passwords and secret passphrases
8. **Respectful Tone** - Use of "bạn" for professional yet friendly communication
9. **Analytic Structure** - Proper use of particles and word order instead of inflection

By following these guidelines, translators can ensure that the Vietnamese version of Onetime Secret is accurate, consistent, and provides a natural user experience for Vietnamese-speaking audiences.
