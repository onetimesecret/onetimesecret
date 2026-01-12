---
title: 简体中文翻译指南
description: Onetime Secret 简体中文翻译综合指南，结合术语表和语言注释
---

# Translation Guidance for Simplified Chinese (简体中文)

This document combines translation glossary and language-specific notes to provide comprehensive guidance for translating Onetime Secret into Simplified Chinese. It serves as the authoritative reference for maintaining consistency, quality, and cultural appropriateness in Chinese translations.

## Introduction

This guide merges two key resources:
1. **Translation Glossary**: Standardized Chinese translations for key terms, UI elements, and technical vocabulary
2. **Language Notes**: Translation principles, rationale, and Chinese-specific considerations

Together, they ensure all Chinese translations maintain consistency, respect Chinese language conventions, and effectively communicate to both technical and general users.

## Core Translation Principles

### 1. Avoid "秘密" (Secret) - Use Functional Terminology

**Critical Principle:** The word "秘密" in Chinese carries strong connotations of personal, hidden, or confidential information with emotional weight. It suggests something deliberately concealed rather than a functional security feature.

**Alternative Approaches:**
- **Functional contexts**: Use "内容" (content) for create/retrieve operations
- **Product features**: Use "一次性链接" (one-time links) to emphasize the core single-use feature
- **Descriptive contexts**: Use "加密的" (encrypted) or "安全的" (secure) as adjectives

**Examples:**
- "Create Secrets" → "创建内容" (create content)
- "Retrieve Secrets" → "获取内容" (retrieve content)
- "Secret Links" → "一次性链接" (one-time links)
- "Why Use Secret Links" → "为什么使用一次性链接" (why use one-time links)

### 2. Distinguish Password Types

**Must differentiate** between these two concepts:
- **密码 (password)**: For account login/authentication
- **口令 (passphrase)**: For protecting specific content

This distinction prevents confusion between account security and content protection mechanisms.

### 3. Optimize for Chinese Language Patterns

Chinese allows more concise expressions than English. Follow these patterns:

**Action-oriented text** (buttons, menu items):
- Use direct, imperative forms
- Examples: "保存更改" (save changes), "删除文件" (delete file), "发送消息" (send message)

**Status messages**:
- Use passive or declarative forms
- Examples: "已保存更改" (changes saved), "文件已删除" (file deleted), "下载完成" (download complete)

**UI simplification**:
- "Getting Started" → "开始使用" (start using - more action-oriented, not "入门")
- "Edit page" → "编辑" (edit - concise for buttons, not "编辑页面")
- "Copy to clipboard" → "复制" (copy - simplified, not "复制到剪贴板")
- "Copied!" → "已复制" (copied - no exclamation mark)

### 4. Punctuation Guidelines

Follow the style guide punctuation principles:
- Use periods, commas, and question marks as appropriate
- **Avoid exclamation marks** (except in quoted source material)
- No semicolons or abbreviations
- Maintain professional, calm tone

### 5. Cultural and Linguistic Adaptation

Adapt phrasing to feel natural in Chinese while maintaining professional tone:
- Use Chinese sentence structure patterns (not direct English translation)
- Choose appropriate formality level for both technical and general users
- Maintain warmth while being concise and efficient

## Standard Terminology Reference

### Core Product Terms

| English | Chinese (Simplified) | Context | Notes |
|---------|---------------------|---------|-------|
| secret (noun) | 内容 / 信息 | Core application concept | Use "内容" in create/retrieve operations; avoid "秘密" emotional connotations |
| secret (adj) | 加密的 / 安全的 | Descriptive adjective | Use based on context |
| secret link | 一次性链接 | Core product feature | **Do not** translate as "秘密链接"; emphasizes one-time use characteristic |
| passphrase | 口令 | Authentication method for protecting content | Distinguish from "密码" (account authentication) |
| password | 密码 | Authentication for account access | Used for account login |
| burn | 销毁 | Action to delete content before viewing | Emphasizes permanence |
| view/reveal | 查看 / 显示 | Action to access content | |
| link | 链接 | URL providing content access | |
| encrypt/encrypted | 加密 / 已加密 | Security method | |
| secure | 安全的 | Protection status | |

### User Interface Elements

| English | Chinese (Simplified) | Context | Notes |
|---------|---------------------|---------|-------|
| Share a secret | 分享内容 | Primary action | Use "内容" not "秘密" |
| Secret Links | 一次性链接 | Navigation/feature name | Emphasizes one-time use characteristic |
| Create Account | 创建账户 | Registration | |
| Sign In | 登录 | Authentication | |
| Dashboard | 仪表板 / 控制台 | User main page | |
| Settings | 设置 | Configuration page | |
| Privacy Options | 隐私选项 | Content settings | |
| Feedback | 反馈 | User comments | |
| Getting Started | 开始使用 | Introductory content | Action-oriented; **not** "入门" |
| Edit page | 编辑 | Button text | Concise; **not** "编辑页面" |

### Status Terms

| English | Chinese (Simplified) | Context | Notes |
|---------|---------------------|---------|-------|
| received | 已接收 | Content has been viewed | |
| burned | 已销毁 | Content deleted before viewing | |
| expired | 已过期 | Content no longer available due to time | |
| created | 已创建 | Content has been generated | |
| active | 活跃的 | Content available | |
| inactive | 未激活 | Content unavailable | |

### Time-Related Terms

| English | Chinese (Simplified) | Context | Notes |
|---------|---------------------|---------|-------|
| expires in | 将在...后过期 | Time before content becomes unavailable | |
| day/days | 天 | Time unit | |
| hour/hours | 小时 | Time unit | |
| minute/minutes | 分钟 | Time unit | |
| second/seconds | 秒 | Time unit | |

### Security Features

| English | Chinese (Simplified) | Context | Notes |
|---------|---------------------|---------|-------|
| one-time access | 一次性访问 | Core security feature | |
| passphrase protection | 口令保护 | Additional security | Distinguish from account "密码" |
| encrypted in transit | 传输中加密 | Data protection method | |
| encrypted at rest | 静态加密 | Storage protection | |

### Account-Related Terms

| English | Chinese (Simplified) | Context | Notes |
|---------|---------------------|---------|-------|
| email | 邮箱 / 电子邮件 | User identifier | |
| password | 密码 | Authentication | For account access |
| account | 账户 | User profile | |
| subscription | 订阅 | Paid service | |
| customer | 客户 | Paying user | |

### Domain-Related Terms

| English | Chinese (Simplified) | Context | Notes |
|---------|---------------------|---------|-------|
| custom domain | 自定义域名 | Premium feature | |
| domain verification | 域名验证 | Setup process | |
| DNS record | DNS 记录 | Configuration | |
| CNAME record | CNAME 记录 | DNS setup | |

### Error Messages

| English | Chinese (Simplified) | Context | Notes |
|---------|---------------------|---------|-------|
| error | 错误 | Problem notification | |
| warning | 警告 | Caution notification | |
| oops | 哎呀 | Friendly error introduction | |

### Buttons and Actions

| English | Chinese (Simplified) | Context | Notes |
|---------|---------------------|---------|-------|
| submit | 提交 | Form action | |
| cancel | 取消 | Negative action | |
| confirm | 确认 | Affirmative action | |
| copy to clipboard | 复制 | Utility action | Concise; **not** "复制到剪贴板" |
| continue | 继续 | Navigation | |
| back | 返回 | Navigation | |
| Copied! | 已复制 | Status message | No exclamation mark |

### Marketing Terms

| English | Chinese (Simplified) | Context | Notes |
|---------|---------------------|---------|-------|
| secure links | 安全链接 | Product feature | |
| privacy-first design | 隐私优先设计 | Design philosophy | |
| custom branding | 自定义品牌 | Premium feature | |

### API-Related Terms

| English | Chinese (Simplified) | Context | Notes |
|---------|---------------------|---------|-------|
| create secrets | 创建内容 | API operation | Use "内容" not "秘密" |
| retrieve secrets | 获取内容 | API operation | Use "内容" not "秘密" |
| client libraries | 客户端库 | Development tools | |
| REST API | REST API | Technical term | Keep in English |

## Terms to Keep in English

### Brand Names (Do Not Translate)

- **Onetime Secret** - Keep in English
- **OTS** - Keep in English (when used as product abbreviation)
- **Identity Plus** - Keep in English (product name)
- **Global Elite** - Keep in English (product name)
- **Custom Install** - Keep in English (product name)
- **Starlight** - Keep in English (documentation framework)

### Technical Terms

Keep these technical terms in English:
- API
- REST
- v1, v2 (version numbers)
- DNS, CNAME
- SSL/TLS

## Translation Best Practices

### 1. Consistency
Use the same translation for the same term throughout the application. Refer to this glossary consistently.

### 2. Context Awareness
Consider how the term is used in the application. The same English word may require different Chinese translations based on context.

### 3. Cultural Adaptation
Adjust terminology to local conventions when necessary, but maintain professional accuracy.

### 4. Technical Accuracy
Ensure security and technical terms are translated accurately to avoid confusion or security misunderstandings.

### 5. Tone Maintenance
Maintain a professional yet concise tone. Chinese users value efficiency and directness.

## Detailed Translation Rationale

### Why Move Away from "秘密" (Secret)

The deliberate avoidance of "秘密" (secret) in Chinese translations is based on:

**Emotional connotations**: "秘密" in Chinese carries strong personal, hidden, or confidential overtones - similar to Italian "segreto" or Danish "hemmelighed." It suggests something emotionally charged or deliberately concealed.

**Functional clarity**: Better alternatives emphasize the functional security feature:
- **"内容" (content)**: Neutral, functional term for what is being shared
- **"一次性链接" (one-time links)**: Emphasizes the core product feature of single-use access
- **"加密的" / "安全的"**: When describing security attributes

**User trust**: Using functional terminology builds trust by focusing on the security mechanism rather than creating mystery or secrecy around the content.

### Voice Patterns in Chinese

**Actions** (buttons, menu items) - Use imperative, direct forms:
- "保存更改" (save changes)
- "删除文件" (delete file)
- "发送消息" (send message)
- "开始使用" (start using)

**Status messages** - Use passive or declarative forms:
- "已保存更改" (changes saved)
- "文件已删除" (file deleted)
- "下载完成" (download complete)
- "已复制" (copied)

**Navigation** - Use clear, descriptive terms:
- "概览" (overview)
- "主导航" (main navigation)
- "设置" (settings)

### Accessibility Considerations

Chinese accessibility labels should be more descriptive than direct translations:
- "Main" → "主导航" (main navigation) - more helpful for screen readers
- Provide context in labels where English might be minimal

### Natural Chinese Phrasing

Adapt sentence structure to Chinese patterns rather than translating word-for-word:
- **English structure**: Subject-Verb-Object
- **Chinese adaptation**: May use topic-comment structure or different emphasis patterns
- **Result**: More natural reading experience for Chinese users

## Summary of Key Terminology Choices

### Core Terminology Evolution
- **"秘密" → Functional alternatives**: Replaced with "内容" (content) for create/retrieve actions and "一次性链接" (one-time links) for the core feature
- **Technical precision maintained**: API, REST, version numbers preserved
- **Brand names untranslated**: Starlight, Onetime Secret kept in original form

### UI/UX Refinements
- **Removed exclamation marks**: Following style guide punctuation principles
- **Shortened action text**: "编辑页面" → "编辑" for button efficiency
- **Simplified tooltips**: "复制到剪贴板" → "复制" for clarity
- **Natural Chinese flow**: Restructured phrases to follow Chinese language patterns

### Voice and Tone
- **Action-oriented for user tasks**: "开始使用" instead of "开始入门"
- **Declarative for status**: "已复制" (completed state) vs "复制" (action)
- **Professional yet accessible**: Maintained warmth while being concise

### Chinese-Specific Improvements
- **Better accessibility**: "主导航" (main navigation) more descriptive than direct translation
- **Natural sentence structure**: Adapted error messages and descriptions to Chinese writing patterns
- **Appropriate formality**: Professional tone suitable for both technical and general Chinese users

## Implementation Guidelines

When translating new content:

1. **Check this glossary first** for established terminology
2. **Consider the context** - is this an action, status, or description?
3. **Apply Chinese language patterns** - don't translate word-for-word
4. **Avoid "秘密"** - use functional alternatives from this guide
5. **Maintain consistency** - use the same translation for the same concept
6. **Keep it concise** - Chinese allows shorter expressions; use them
7. **No exclamation marks** - maintain professional, calm tone
8. **Test readability** - ensure natural flow for native Chinese speakers

## Version History

- **2025-11-14**: Initial comprehensive translation guide created by combining glossary and language notes

---

**For questions or updates to this guide, please consult the translation team.**
