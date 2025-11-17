---
title: Aratohu Whakamāori ki te Reo Māori
description: Aratohu whānui mō te whakamāori i a Onetime Secret ki te reo Māori, e whakakotahi ana i te papakupu me ngā tuhipoka reo
---

# Translation Guidance for Māori (Te Reo Māori)

This document combines the comprehensive glossary and language-specific translation notes for Māori (mi-NZ) translations of Onetime Secret. It provides standardized terminology, cultural guidance, and detailed translation decisions to ensure consistency and quality across all Māori translations.

## Introduction

This guide serves as the authoritative reference for translating Onetime Secret into Māori (te reo Māori). It combines:

1. **Comprehensive Glossary**: Standardized translations for all core terms, UI elements, and technical concepts
2. **Language-Specific Notes**: Detailed rationale for translation decisions and cultural adaptations
3. **Translation Guidelines**: Best practices for maintaining consistency, clarity, and cultural appropriateness

Use this guide to ensure all Māori translations maintain consistency, technical accuracy, and cultural resonance with Māori-speaking users.

---

## Core Terminology

### Primary Concepts

| English | Māori (mi-NZ) | Context / Notes |
|---------|--------------|-------|
| secret (noun) | karere huna | The core concept of the application. "karere huna" (hidden message) better captures the concept than "mea huna" (secret thing) |
| secret (adj) | huna/matatapu | "huna" means hidden/concealed, "matatapu" means private/confidential |
| passphrase | kupu karapa | Refers to a specific phrase for authentication. Different from password |
| burn | whakawareware | Action of permanently deleting a secret before viewing |
| view/reveal | tiro/whakaatu | Action of accessing a secret |
| link | hononga | The URL that provides access to a secret |
| encrypt/encrypted | whakamuhumuhu/muhumuhu | Security method. "whakamuhumuhu" is the action, "muhumuhu" is the state |
| secure | haumaru | State of protection |
| private | tūmataiti | Characteristic of being confidential, private |
| one-time | kotahi-wā | Describes the single-use nature of the service |
| expiration / expiry | paunga / pau | Time when secret becomes unavailable |
| time-to-live | wā-ki-te-ora | Time remaining before expiration |

### User Interface Elements

| English | Māori (mi-NZ) | Context / Notes |
|---------|--------------|-------|
| Share a secret | Tohatoha karere huna | Primary action of the application |
| Create a secret | Waihanga karere huna | Creating a new secret |
| Create Account | Waihanga Pūkete | Registration |
| Sign In | Takiuru | Authentication |
| Sign Out | Takiputa | Logout from account |
| Dashboard | Papatohu | User's main page |
| Settings | Tautuhinga | Configuration page |
| Privacy Options | Kōwhiringa Matatapu | Secret settings |
| Feedback | Urupare | User feedback |
| Account | Pūkete | User account |

### Status Terms

| English | Māori (mi-NZ) | Context / Notes |
|---------|--------------|-------|
| received | kua tirohia | Secret has been viewed |
| burned | kua whakawarekia | Secret deleted before viewing |
| expired | kua pau | Secret no longer available due to time |
| created | kua hangaia | Secret has been created |
| active | hohe | Secret is available |
| inactive | kāore e hohe | Secret is not available |
| shared | kua tohatohahia | Secret has been shared |
| viewed | kua tirohia | Secret has been viewed |

### Time-Related Terms

| English | Māori (mi-NZ) | Context / Notes |
|---------|--------------|-------|
| expires in | ka pau i roto i | Time until secret becomes unavailable |
| expired in | i pau i roto i | Expired after elapsed time |
| day/days | rā/ngā rā | Time unit |
| hour/hours | hāora/ngā hāora | Time unit |
| minute/minutes | meneti/ngā meneti | Time unit |
| second/seconds | hēkona/ngā hēkona | Time unit |
| time remaining | wā e toe ana | Time remaining before expiration |
| lifetime | wā ora | Duration that secret is available |

### Security Features

| English | Māori (mi-NZ) | Context / Notes |
|---------|--------------|-------|
| one-time access | urunga kotahi-wā | Primary security feature |
| passphrase protection | tiaki kupu karapa | Additional security |
| encrypted in transit | muhumuhu i te wā kawe | Data protection method during transmission |
| encrypted at rest | muhumuhu i te wā noho | Storage protection |
| end-to-end encryption | whakamuhumuhu pito-ki-pito | Encryption from sender to receiver |
| rate limiting | whakawhāiti tukanga | System to prevent abuse |
| security | haumaru | Protection characteristic |

### Account-Related Terms

| English | Māori (mi-NZ) | Context / Notes |
|---------|--------------|-------|
| email | īmēra | User identifier |
| password | kupuhipa | Account authentication. Different from passphrase |
| account | pūkete | User account |
| subscription | ohaurunga | Paid service |
| plan | mahere | Subscription tier |
| customer | kiritaki | Paying user |
| colonel | kaiwhakahaere | Administrator with highest permissions |
| username | ingoa kaiwhakamahi | Login name |
| profile | kōtaha | User details |

### Domain-Related Terms

| English | Māori (mi-NZ) | Context / Notes |
|---------|--------------|-------|
| custom domain | rohe ritenga | High-tier feature |
| domain | rohe | Website location |
| domain verification | manatoko rohe | Setup process |
| DNS record | tuhinga DNS | Configuration |
| CNAME record | tuhinga CNAME | DNS setup |
| subdomain | rohe-iti | Sub-location within a larger domain |

### Error Messages

| English | Māori (mi-NZ) | Context / Notes |
|---------|--------------|-------|
| error | hapa | Error notification |
| warning | whakatūpato | Warning notification |
| oops | auē | Friendly error introduction |
| not found | kāore i kitea | Data not found |
| access denied | kua whakakāhoretia te urunga | Access not permitted |
| invalid | muhu | Invalid data, incorrect |
| required | e hiahiatia ana | Required field |

### Buttons and Actions

| English | Māori (mi-NZ) | Context / Notes |
|---------|--------------|-------|
| submit | tuku | Submit action |
| cancel | whakakore | Cancel action |
| confirm | whakaū | Confirm action |
| copy to clipboard | tārua ki te papatopenga | Usage action |
| continue | haere tonu | Navigation |
| back | hoki | Navigation |
| save | tiaki | Save changes |
| delete | muku | Delete data |
| edit | whakatika | Edit content |
| download | tikiake | Download file |
| upload | tukuake | Upload file |

### Marketing Terms

| English | Māori (mi-NZ) | Context / Notes |
|---------|--------------|-------|
| secure links | hononga haumaru | Product feature |
| privacy-first design | hoahoa matatapu-tuatahi | Design principle |
| custom branding | waitohu ritenga | High-tier feature |
| one-time secrets | ngā karere huna kotahi-wā | Primary product concept |
| zero-knowledge encryption | whakamuhumuhu kore-mōhiotanga | Security system where company doesn't know contents |

---

## Translation Guidelines

### 1. Consistency
Maintain the same translation for a term throughout the application. Use this glossary as the authoritative reference.

### 2. Context Awareness
Consider how the term is being used within the application. The same English word may require different Māori translations based on context.

### 3. Cultural Adaptation
Adapt terms to Māori cultural conventions when appropriate, while maintaining clarity and technical accuracy.

### 4. Technical Accuracy
Ensure security and technical terms are translated accurately to maintain the integrity of the application's security messaging.

### 5. Tone
Maintain a professional, friendly, yet clear tone throughout all translations.

---

## Key Translation Decisions

### Central Term: "Secret" → "Karere Huna"

The word "secret" is fundamental to the application. In Māori:
- Use **"karere huna"** (hidden message) rather than **"mea huna"** (secret thing)
- "karere huna" better captures the concept of sharing information/messages
- Don't worry about Māori speakers - it sounds professional and high-quality

**Reasoning:**
- Better captures the nature of what's being shared through the platform (messages, information)
- Avoids connotations of personal secrets/private affairs that "mea huna" might suggest
- Creates consistency with how other platforms translate similar concepts in Māori

**Examples:**
- "Create a secret" → "Waihanga karere huna" (not "Waihanga mea huna")
- "Your secret was viewed" → "I tirohia tō karere huna"
- "Secret content" → "Ihirangi karere huna"

### Distinction: "Password" vs "Passphrase"

- **Kupuhipa** = for account login
- **Kupu karapa** = for protecting individual secrets
- Maintain this distinction consistently across all translations

**Examples:**
- "Enter your password" → "Urunga tō kupuhipa" (account login)
- "Set a passphrase" → "Whakatū kupu karapa" (secret protection)

### Verb Forms for UI Elements

Use clear distinction between active/imperative voice for actions and passive/declarative voice for status messages.

**Examples:**
- Action button: "Create Secret" → "Waihanga Karere Huna" (imperative)
- Status message: "Secret created" → "Kua hangaia te karere huna" (passive)
- Button: "Copy to clipboard" → "Tārua ki te papatopenga" (imperative)
- Status: "Copied to clipboard" → "Kua tāruatia ki te papatopenga" (passive)

### Grammar Structure

- Use active, imperative voice for buttons and actions (e.g., "Waihanga", "Tiaki")
- Use passive, declarative voice for status messages (e.g., "Kua hangaia", "Kua tiakina")
- Do not use language abbreviations - use full words
- Maintain clear, direct tone at all times

### Technical Terms

Balance authenticity with accessibility when translating technical concepts.

**Examples:**
- "encryption/encrypted" → "whakamuhumuhu/muhumuhu" (relates to making something secret/whispered)
- "passphrase" → "kupu karapa" (a phrase that grants access)
- "domain" → "rohe" (territory/region)
- "dashboard" → "papatohu" (guidance board)

### Cultural Adaptations

Incorporate Māori conventions for greetings, time expressions, and sentence structures where appropriate.

**Examples:**
- "Welcome Back" → "Nau Mai Anō" (traditional Māori welcome expression)
- "You've got (secret) mail" → "He īmēra (huna) tāu" (using Māori possession structure)
- Time expressions follow Māori conventions

### Brand and Product Names

Following the style guide, brand names remain untranslated but descriptions are translated.

**Examples:**
- "Identity Plus" remains "Identity Plus" (untranslated)
- "Onetime Secret" remains "Onetime Secret" (untranslated)
- "Custom Install" description → "Tāutatanga Ritenga" (customized installation)

### Technical Conventions

- Security-related technical terms must be verified for accuracy before translation
- Preserve product brand names (Onetime Secret, Identity Plus, etc.) without translation
- UI elements must follow standard conventions for Māori language

---

## Translation Approach Summary

### 1. Terminology Standardization
- Established consistent translations for all core terms
- Created comprehensive glossary for future translators
- Ensured security and technical terms maintain precision while being natural in Māori

### 2. UI Flow Improvements
- Aligned button text with Māori action verb conventions
- Used proper passive forms for status messages
- Created natural-sounding instructions and error messages

### 3. Cultural Context
- Incorporated traditional Māori greeting patterns
- Adapted metaphors and idioms to resonate with Māori speakers
- Used Māori-specific linguistic structures

### 4. Technical Precision
- Created accurate translations for security concepts
- Preserved all placeholders and formatting variables
- Maintained distinctions between similar terms (password vs passphrase)

### 5. Accessibility Enhancements
- Focused on clear, direct language accessible to all Māori speakers
- Used consistent terminology for better user experience
- Avoided overly academic or formal language

---

## Voice and Tone

### Brand Voice in Māori
- Maintains a clear, professional yet approachable tone
- Uses authentic Māori expressions while keeping technical concepts clear
- Prioritizes clarity over literal translations
- Addresses users in second person ("koe")
- Maintains consistent punctuation and avoids contractions

### Key Principles
1. **Professional yet Friendly**: Balance technical accuracy with approachable language
2. **Clear Communication**: Prioritize user understanding over literal translation
3. **Cultural Authenticity**: Use natural Māori expressions that resonate with speakers
4. **Consistency**: Maintain uniform terminology and style throughout
5. **Accessibility**: Ensure translations are understandable to all Māori speakers

---

## Conclusion

This translation approach makes Onetime Secret accessible and culturally appropriate for Māori-speaking users while maintaining the technical precision and security focus essential to the application. By following these guidelines and using the standardized terminology in this glossary, translators can ensure high-quality, consistent Māori translations that serve the user community effectively.
