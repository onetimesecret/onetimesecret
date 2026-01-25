---
title: 한국어 번역 가이드
description: Onetime Secret의 한국어 번역을 위한 포괄적인 가이드. 용어집과 언어별 주석을 결합합니다
---

# Translation Guidance for Korean (한국어)

This document combines the glossary and language-specific translation notes for Korean (ko) localization of Onetime Secret. It provides standardized terminology, translation principles, and practical examples to ensure consistency and quality across all Korean translations.

## About This Document

This comprehensive guide merges:
- **Glossary**: Standardized translations for key terms across the application
- **Language Notes**: Korean-specific translation guidelines, style conventions, and important distinctions

Use this document as your primary reference when translating or reviewing Korean content for Onetime Secret.

---

## Core Terminology

### Primary Concepts

| English | Korean (KO) | Notes |
|---------|------------|-------|
| secret (noun) | 비밀 메시지 | The application's central concept; emphasizes confidential information being shared |
| secret (adjective) | 비밀의 | Used in descriptive contexts |
| passphrase | 접근 문구 | Authentication method for secret protection; distinct from account passwords |
| password | 비밀번호 | Account login credentials only |
| burn | 소각 | Action of deleting a secret before viewing; emphasizes permanent deletion |
| view/reveal | 보기/공개 | Action of accessing a secret |
| link | 링크 | URL providing access to a secret |
| encrypt/encrypted | 암호화/암호화됨 | Security method |
| secure | 안전한 | Protected state |

### Critical Distinction: Password vs. Passphrase

**This is the most important distinction in Korean translation:**

- **Password (비밀번호)**: Used ONLY for account login credentials
  - Examples: "계정 비밀번호" (account password), "로그인 비밀번호" (login password)

- **Passphrase (접근 문구)**: Used ONLY for protecting individual secrets
  - Examples: "접근 문구 보호" (passphrase protection), "접근 문구를 입력하세요" (enter passphrase)

**Common Mistakes to Avoid:**
```
❌ "비밀번호 보호" (when protecting secrets)
✅ "접근 문구 보호"

❌ "암호" (generic/ambiguous)
✅ "비밀번호" (for accounts) or "접근 문구" (for secrets)
```

---

## User Interface Elements

| English | Korean (KO) | Notes |
|---------|------------|-------|
| Share a Secret | 비밀 메시지 공유 | Primary action |
| Create Account | 계정 만들기 | Registration |
| Log In | 로그인 | Authentication |
| Dashboard | 대시보드 | User's main page |
| Settings | 설정 | Configuration page |
| Privacy Options | 비밀 메시지 설정 | Secret configuration |
| Feedback | 피드백 | User comments |

---

## Status Terms

| English | Korean (KO) | Notes |
|---------|------------|-------|
| Received | 수신됨 | Secret has been viewed |
| Burned | 소각됨 | Secret deleted before viewing |
| Expired | 만료됨 | Secret no longer available due to timeout |
| Created | 생성됨 | Secret has been created |
| Active | 활성 상태 | Secret is available |
| Inactive | 비활성 상태 | Secret is not available |

---

## Time-Related Terms

| English | Korean (KO) | Notes |
|---------|------------|-------|
| Expiration Time | 만료 시간 | Time when secret becomes unavailable |
| day/days | 일/일 | Time unit |
| hour/hours | 시간/시간 | Time unit |
| minute/minutes | 분/분 | Time unit |
| second/seconds | 초/초 | Time unit |

---

## Security Features

| English | Korean (KO) | Notes |
|---------|------------|-------|
| one-time access | 일회성 접근 | Core security feature |
| passphrase protection | 접근 문구 보호 | Additional security |
| encrypted in transit | 전송 중 암호화 | Data protection method |
| encrypted at rest | 저장 시 암호화 | Storage protection |

---

## Account-Related Terms

| English | Korean (KO) | Notes |
|---------|------------|-------|
| email | 이메일 | User identifier |
| password | 비밀번호 | Account login credential |
| account | 계정 | User profile |
| subscription | 구독 | Paid service |
| customer | 고객 | Paying user |

---

## Domain-Related Terms

| English | Korean (KO) | Notes |
|---------|------------|-------|
| custom domain | 사용자 정의 도메인 | Premium feature |
| domain verification | 도메인 확인 | Setup process |
| DNS record | DNS 레코드 | Configuration |
| CNAME record | CNAME 레코드 | DNS setting |

---

## Error Messages

| English | Korean (KO) | Notes |
|---------|------------|-------|
| Error | 오류 | Problem notification |
| Warning | 경고 | Alert |
| Oops | 이런 | Friendly error introduction |

---

## Buttons and Actions

| English | Korean (KO) | Notes |
|---------|------------|-------|
| Submit | 제출하기 | Form action |
| Cancel | 취소 | Negative action |
| Confirm | 확인 | Positive action |
| Copy to Clipboard | 클립보드에 복사 | Utility action |
| Continue | 계속 | Navigation |
| Back | 뒤로 | Navigation |

---

## Marketing Terms

| English | Korean (KO) | Notes |
|---------|------------|-------|
| secure links | 안전한 링크 | Product feature |
| privacy-first design | 개인정보 보호 최우선 설계 | Design philosophy |
| custom branding | 맞춤형 브랜딩 | Premium feature |

---

## Translation Style Guide

### Voice and Tone

1. **Active, Imperative Voice for Actions**
   - Use for buttons, commands, and calls to action
   - Examples:
     - "비밀 링크 생성" (Create secret link)
     - "복사" (Copy)
     - "비밀 메시지 공유" (Share secret)
     - "비밀 메시지 소각" (Burn secret)

2. **Passive or Declarative Voice for Status**
   - Use for notifications, confirmations, and status messages
   - Examples:
     - "복사됨" (Copied)
     - "생성되었습니다" (Has been created)
     - "소각되었습니다" (Has been burned)
     - "비밀 메시지가 열람되었습니다" (Secret has been viewed)

3. **Professional Yet Approachable Tone**
   - Maintain throughout the interface
   - Use clear, direct language
   - Keep accessible to users with varying technical backgrounds
   - Maintain consistent politeness levels appropriate for a professional application

### Grammar and Style Conventions

1. **Natural Korean Sentence Structure**
   - Adapt English sentence structure to natural Korean grammar patterns
   - Avoid literal word-for-word translations
   - Prioritize clarity and natural flow

2. **Standard Punctuation**
   - Use appropriate Korean punctuation conventions
   - Maintain consistency across the application

3. **Direct User Address**
   - Use second person where appropriate
   - Maintain respectful but not overly formal language

4. **Brand Terms**
   - Leave untranslated: "Onetime Secret", "OTS", "Identity Plus"

---

## Practical Translation Examples

### Security Terminology in Context

```
"burn_this_secret": "이 비밀 메시지 소각"
"view_secret": "비밀 메시지 보기"
"share_a_secret": "비밀 메시지 공유"
"secret_link": "비밀 링크"
"secure_link": "안전한 링크"
"one_time_access": "일회성 접근"
```

### Password vs. Passphrase Examples

**Account Authentication (비밀번호):**
```
"account_password": "계정 비밀번호"
"login_password": "로그인 비밀번호"
"reset_password": "비밀번호 재설정"
"enter_your_password": "비밀번호를 입력하세요"
"password_required": "비밀번호 필요"
"change_password": "비밀번호 변경"
```

**Secret Protection (접근 문구):**
```
"passphrase_protection": "접근 문구 보호"
"enter_passphrase": "접근 문구를 입력하세요"
"passphrase_required": "접근 문구 필요"
"protect_with_passphrase": "접근 문구로 보호"
"set_passphrase": "접근 문구 설정"
"optional_passphrase": "선택적 접근 문구"
```

### UI Actions (Active Voice)

```
"create_secret": "비밀 링크 생성"
"copy_to_clipboard": "클립보드에 복사"
"share_secret": "비밀 메시지 공유"
"burn_secret": "비밀 메시지 소각"
"delete_account": "계정 삭제"
"view_dashboard": "대시보드 보기"
"update_settings": "설정 업데이트"
```

### Status Messages (Passive Voice)

```
"copied": "복사됨"
"created": "생성되었습니다"
"burned": "소각되었습니다"
"secret_viewed": "비밀 메시지가 열람되었습니다"
"account_deleted": "계정이 삭제되었습니다"
"settings_updated": "설정이 업데이트되었습니다"
```

### Instructions and Warnings

```
"enter_passphrase": "접근 문구를 입력하세요"
"careful_only_see_once": "주의: 한 번만 볼 수 있습니다"
"secret_will_be_deleted": "비밀 메시지는 열람 후 삭제됩니다"
"use_passphrase_for_security": "보안을 위해 접근 문구를 사용하세요"
"enter_account_password": "계정 비밀번호를 입력하세요"
```

### Common Translation Mistakes

```
❌ "비밀" (bare, without context)
✅ "비밀 메시지" (for the secret being shared)

❌ "보안 메시지"
✅ "비밀 메시지" (consistent terminology)

❌ "비밀번호 보호" (when protecting secrets)
✅ "접근 문구 보호"

❌ "암호" (generic/ambiguous)
✅ "비밀번호" (for accounts) OR "접근 문구" (for secret protection)

❌ "임시 비밀번호"
✅ "임시 비밀 메시지" (temporary secrets, not passwords)

❌ Following English sentence structure literally
✅ Adapt to natural Korean grammar patterns
```

---

## Translation Principles

### 1. Consistency
- Use the same translation for terms throughout the application
- Refer to this glossary for standardized terminology
- Maintain consistent voice and tone across all content

### 2. Context Awareness
- Consider how terms are used in the application
- Adapt translations based on UI context (button, label, message, etc.)
- Ensure translations fit within UI space constraints

### 3. Cultural Adaptation
- Adjust terms to local Korean practices when appropriate
- Ensure translations resonate with Korean users' expectations
- Make the interface feel native rather than obviously translated

### 4. Technical Accuracy
- Ensure security terms are translated accurately
- Prioritize accuracy over localization for critical technical concepts
- Maintain clarity for both technical and non-technical users

### 5. Natural Language
- Prioritize natural-sounding translations over literal ones
- Use Korean sentence structure and grammar conventions
- Avoid awkward phrasing that suggests machine translation

### 6. Tone Consistency
- Maintain professional yet approachable tone
- Use appropriate politeness levels for a business application
- Keep language clear and direct

---

## Key Changes from Previous Translation

### Terminology Improvements

1. **Consistent Translation of "secret"**: Standardized use of "비밀 메시지" throughout the application to clarify what's being shared

2. **Clear Password/Passphrase Distinction**: Implemented "비밀번호" for account credentials and "접근 문구" for secret protection consistently

3. **Technical Term Clarity**: Standardized terms like "burn" (소각), "encryption" (암호화), and "one-time access" (일회성 접근)

### User Interface Improvements

1. **Button Labels**: Optimized for Korean UI conventions while maintaining clarity
2. **Error Messages**: Made more natural and helpful in Korean
3. **Instructional Text**: Adjusted to sound natural while providing clear instructions

### Structural Enhancements

1. **Korean Sentence Structure**: Reworked sentences to use natural Korean grammar patterns
2. **Honorifics and Politeness Levels**: Maintained consistent appropriate levels
3. **Length Considerations**: Adjusted translations for proper UI element display

---

## Special Considerations

### The "Secret" Term
- "비밀 메시지" (secret message) is the application's core concept
- Must be translated consistently throughout
- Emphasizes confidential information being shared rather than personal secrets
- Use "비밀" alone only in short UI elements where context is absolutely clear

### Regional Variations
- Follow South Korean (대한민국) language conventions
- Use standard Seoul dialect as the baseline
- Avoid region-specific terms that might confuse users

### Security Terminology Priority
- Security-related technical terms prioritize accuracy over localization
- When in doubt, favor clarity and technical precision
- Ensure users understand the security implications

### UI Platform Conventions
- Follow Korean UI/UX conventions
- Match expectations from other professional Korean applications
- Ensure button and action labels are concise yet clear

---

## Using This Guide

When translating or reviewing Korean content:

1. **Check the Glossary First**: Ensure you're using standardized terminology
2. **Follow Style Guidelines**: Apply appropriate voice and tone
3. **Review Examples**: Reference practical examples for similar contexts
4. **Maintain Consistency**: Cross-reference with existing translations
5. **Prioritize Clarity**: When in doubt, choose the clearer option
6. **Test in Context**: Verify translations work in actual UI elements

This guide should be your primary reference for all Korean translation work on Onetime Secret, ensuring a consistent, professional, and user-friendly experience for Korean-speaking users.
