---
title: دليل الترجمة للعربية
description: دليل شامل لترجمة Onetime Secret إلى العربية يجمع بين قائمة المصطلحات والملاحظات اللغوية
---

# Translation Guidance for Arabic (العربية)

This document combines the glossary of standardized terms and language-specific translation notes for Arabic translations of Onetime Secret. It serves as a comprehensive reference for translators working on the Arabic locale to ensure consistency, accuracy, and natural phrasing.

## Overview

The Arabic translation aims to:
- Maintain consistency across all application interfaces
- Use clear, natural phrasing for Arabic-speaking audiences
- Follow technical accuracy for security-related terminology
- Apply appropriate voice and tone for different contexts
- Use Modern Standard Arabic (MSA) for professional and technical content
- Properly implement Right-to-Left (RTL) layout requirements

---

## Core Terminology

### Basic Terms

| English | العربية (AR) | Context | Notes |
|---------|-------------|---------|-------|
| secret (noun) | سر | Central application concept | Appropriate for professional security contexts, used from "سر الدولة" (state secret) to business usage |
| secret (adj) | سري/آمن | Descriptive use | |
| passphrase | عبارة المرور | Authentication method for secrets | Compound term distinguishing from account password |
| password | كلمة المرور | Account login credential | Standard term for account passwords |
| burn | حذف نهائياً | Action to delete a secret before viewing | "Final deletion" is more natural than literal "burn" in digital context |
| view/reveal | عرض/إظهار | Action to access a secret | |
| link | رابط | URL providing access to a secret | |
| encrypt/encrypted | تشفير/مشفر | Security method | |
| secure | آمن | Protection state | |

### User Interface Elements

| English | العربية (AR) | Context | Notes |
|---------|-------------|---------|-------|
| Share a secret | مشاركة سر | Primary action | |
| Create Account | إنشاء حساب | Registration | |
| Sign In | تسجيل الدخول | Authentication | |
| Dashboard | لوحة التحكم | User's main page | |
| Settings | الإعدادات | Configuration page | |
| Privacy Options | خيارات الخصوصية | Secret configuration | |
| Feedback | الملاحظات | User feedback | |

### Status Terms

| English | العربية (AR) | Context | Notes |
|---------|-------------|---------|-------|
| received | تم الاستلام | Secret has been viewed | |
| burned | تم الحذف نهائياً | Secret was deleted before viewing | |
| expired | منتهي الصلاحية | Secret no longer available due to time | |
| created | تم الإنشاء | Secret has been generated | |
| active | نشط | Secret is available | |
| inactive | غير نشط | Secret is not available | |

### Time-Related Terms

| English | العربية (AR) | Context |
|---------|-------------|---------|
| expires in | تنتهي صلاحيته في | Time until secret becomes unavailable |
| day/days | يوم/أيام | Time unit |
| hour/hours | ساعة/ساعات | Time unit |
| minute/minutes | دقيقة/دقائق | Time unit |
| second/seconds | ثانية/ثوانٍ | Time unit |

### Security Features

| English | العربية (AR) | Context |
|---------|-------------|---------|
| one-time access | وصول لمرة واحدة | Core security feature |
| passphrase protection | الحماية بعبارة مرور | Additional security |
| encrypted in transit | مشفر أثناء النقل | Data protection method |
| encrypted at rest | مشفر أثناء التخزين | Storage protection |

### Account-Related Terms

| English | العربية (AR) | Context |
|---------|-------------|---------|
| email | البريد الإلكتروني | User identifier |
| password | كلمة المرور | Account authentication |
| account | حساب | User profile |
| subscription | اشتراك | Paid service |
| customer | عميل | Paying user |

### Domain-Related Terms

| English | العربية (AR) | Context |
|---------|-------------|---------|
| custom domain | نطاق مخصص | Premium feature |
| domain verification | التحقق من النطاق | Setup process |
| DNS record | سجل DNS | Configuration |
| CNAME record | سجل CNAME | DNS configuration |

### Error Messages

| English | العربية (AR) | Context |
|---------|-------------|---------|
| error | خطأ | Problem notification |
| warning | تحذير | Caution notification |
| oops | عذراً | Friendly error introduction |

### Buttons and Actions

| English | العربية (AR) | Context | Notes |
|---------|-------------|---------|-------|
| submit | إرسال | Form action | |
| cancel | إلغاء | Negative action | |
| confirm | تأكيد | Positive action | |
| copy to clipboard | نسخ إلى الحافظة | Utility action | |
| continue | متابعة | Navigation | |
| back | رجوع | Navigation | |

### Marketing Terms

| English | العربية (AR) | Context |
|---------|-------------|---------|
| secure links | روابط آمنة | Product feature |
| privacy-first design | تصميم يعطي الأولوية للخصوصية | Design philosophy |
| custom branding | علامة تجارية مخصصة | Premium feature |

---

## Translation Guidelines

### 1. Consistency

- Use the same translation for a term throughout the application
- Maintain standardized terminology from the glossary above
- Key distinctions to preserve:
  - `كلمة المرور` for account passwords
  - `عبارة المرور` for secret protection
  - `سر` as the core concept

### 2. Context Awareness

- Consider how the term is used in the application
- Account for surrounding UI elements and user flow
- Ensure translations make sense in their specific context

### 3. Cultural Adaptation

- Adapt terms to local conventions when necessary
- Use Modern Standard Arabic (MSA) for professional and technical content
- Use established Arabic technical vocabulary

### 4. Technical Accuracy

- Security-related terms must be translated accurately
- Prioritize precision over localization for technical terminology
- Use established Arabic technical terms where available
- Keep DNS, URL, and similar acronyms in Latin script as universally used

### 5. Voice and Tone

- Use formal second person with appropriate verb forms
- Maintain respectful, professional tone throughout
- Ensure consistency in formality level across all interfaces

### 6. Right-to-Left (RTL) Layout

- Arabic is written from right to left
- UI elements should be mirrored appropriately
- Numbers and Latin script remain LTR within RTL text
- Pay special attention to interface layout requirements

### 7. Clarity and Natural Phrasing

- Prioritize natural Arabic expressions over literal translations
- Use standard phrases familiar to Arabic speakers
- Ensure terminology is accessible and professional

### 8. Completeness

- Ensure all user-facing strings are translated
- Avoid leaving English text in the interface
- Translate help text, descriptions, and metadata

---

## Common Translation Patterns

### User Instructions
Use appropriate verb forms for instructions and actions

### Status Descriptions
Use passive voice or completed action forms

### Help Text and Descriptions
Use declarative sentences with formal tone

### Error Messages
Use clear, direct language with appropriate formality

---

## Special Considerations

### The Term "Secret"
- Fundamental to the application - translate consistently as `سر`
- Appropriate for professional security contexts
- Used in both governmental and business contexts
- Emphasizes the confidential nature of the shared item

### Password vs. Passphrase
Critical distinction:
- **`كلمة المرور`** - for user account login credentials
- **`عبارة المرور`** - for protecting individual secrets

This distinction must be maintained throughout the application to avoid confusion.

### The Term "Burn"
- Translated as `حذف نهائياً` (final deletion)
- More natural in digital Arabic context than literal translation
- Clearly conveys permanent deletion concept

### UI Element Conventions
- Follow platform conventions for Arabic interfaces
- Implement proper RTL layout and mirroring
- Use standard Arabic terminology for common UI elements
- Maintain consistency with other Arabic applications

### Technical Security Terms
- Prioritize accuracy over casual localization
- Use established Arabic technical vocabulary
- Examples:
  - `تشفير` (encryption)
  - `مشفر` (encrypted)
  - `التحقق` (verification)
  - `المصادقة` (authentication)

---

## Summary of Translation Principles

The Arabic translation maintains:

1. **Terminology Consistency** - Standardized key terms throughout the application
2. **Appropriate Formality** - Formal, respectful tone for professional context
3. **Natural Phrasing** - Standard Arabic expressions and idioms
4. **RTL Awareness** - Proper implementation of right-to-left layout
5. **Complete Coverage** - All user-facing strings translated
6. **Technical Accuracy** - Precise terminology for security concepts
7. **Clear Distinctions** - Especially between account passwords and secret passphrases
8. **Modern Standard Arabic** - Professional language suitable for all Arabic-speaking regions

By following these guidelines, translators can ensure that the Arabic version of Onetime Secret is accurate, consistent, and provides a natural user experience for Arabic-speaking audiences.
