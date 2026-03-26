---
title: Esperanta Traduka Gvidilo
description: Ampleksa gvidilo por traduki Onetime Secret en Esperanton, kombinante vortaron kaj lingvajn notojn
---

# Translation Guidance for Esperanto

This document provides comprehensive guidance for translating Onetime Secret content into Esperanto. It combines universal translation resources with locale-specific terminology and rules.

## Universal Translation Resources

Before translating, review these cross-language guidelines that apply to all locales:

- **[Translating "Secret"](/en/translations/universal/secret-concept)** - How to handle the word "secret" across different language contexts
- **[Password vs. Passphrase](/en/translations/universal/password-passphrase)** - Maintaining the critical distinction between account passwords and secret passphrases
- **[Voice and Tone](/en/translations/universal/voice-and-tone)** - Patterns for active vs. passive voice, formality levels, and cultural adaptations
- **[Brand Terms](/en/translations/universal/brand-terms)** - Terms that should not be translated (product names, tier names)
- **Literal keys (`_literal` suffix)** - Keys ending in `_literal` (e.g., `onetime_secret_literal`) contain brand names that must remain in English exactly as-is. Do not translate these values.
- **[Quality Checklist](/en/translations/universal/quality-checklist)** - Comprehensive checklist for pre-submission review

---

## Core Terminology

| English | Esperanto | Context | Notes |
|---------|-----------|---------|-------|
| secret (noun) | sekreto | Core application concept | Use "sekreto" (noun) or "sekreta mesaĝo" (secret message) |
| secret (adj) | sekreta | Descriptor | |
| passphrase | sekreta frazo | Secret protection mechanism | Distinct from "pasvorto" (account password) |
| password | pasvorto | Account login credential | Only for account authentication |
| burn | forbruligi | Delete secret before viewing | Esperanto verb with -ig- causative suffix |
| burned | forbruligita | Status: deleted before viewing | Past participle |
| view/reveal | vidi / malkaŝi | Access a secret | |
| hide | kaŝi | Conceal content | |
| link | ligilo | URL providing access | |
| encrypt/encrypted | ĉifri / ĉifrita | Security method | |
| secure | sekura | Protection state | |
| clipboard | tondujo | System clipboard | Esperanto coinage, not "clipboard" |
| passkey | pasŝlosilo | WebAuthn/FIDO credential | Compound: pas- + ŝlosilo (key) |

## User Interface Elements

| English | Esperanto | Context | Notes |
|---------|-----------|---------|-------|
| Share a secret | Kunhavigi sekreton | Primary action | |
| Create Account | Krei Konton | Registration | |
| Sign In | Ensaluti | Authentication | |
| Sign Out | Elsaluti | Logout action | |
| Dashboard | Panelo | User main page | |
| Settings | Agordoj | Configuration page | |
| Privacy Options | Privatecaj Opcioj | Secret settings | |
| Feedback | Komentoj / Reagoj | User comments | |
| Getting Started | Komenci | Introductory content | |

## Status Terms

| English | Esperanto | Context |
|---------|-----------|---------|
| received | ricevita | Secret was viewed |
| burned | forbruligita | Secret deleted before viewing |
| expired | eksvalidiĝinta | Secret no longer available due to time |
| created | kreita | Secret was generated |
| active | aktiva | Secret is available |
| inactive | neaktiva | Secret not available |
| copied | kopiita | Copied to clipboard |

## Time-Related Terms

| English | Esperanto | Context |
|---------|-----------|---------|
| expires in | eksvalidiĝas post | Time until secret becomes unavailable |
| day/days | tago / tagoj | Time unit |
| hour/hours | horo / horoj | Time unit |
| minute/minutes | minuto / minutoj | Time unit |
| second/seconds | sekundo / sekundoj | Time unit |

## Security Features

| English | Esperanto | Context | Notes |
|---------|-----------|---------|-------|
| one-time access | unufoja aliro | Core security feature | |
| passphrase protection | protekto per sekreta frazo | Additional security | Distinguish from "pasvorto" |
| encrypted in transit | ĉifrita dum transsendo | Data protection method | |
| encrypted at rest | ĉifrita dum konservado | Storage protection | |
| two-factor authentication | dufaktora aŭtentikigo | 2FA | Compound: du- + faktora |
| recovery code | restaŭra kodo | Backup authentication | |

## Account-Related Terms

| English | Esperanto | Context |
|---------|-----------|---------|
| email | retpoŝtadreso / retpoŝto | User identifier |
| password | pasvorto | Authentication |
| account | konto | User profile |
| subscription | abono | Paid service |
| customer | kliento | Paying user |

## Domain-Related Terms

| English | Esperanto | Context |
|---------|-----------|---------|
| custom domain | propra domajno | Premium feature |
| domain verification | domajnkonfirmo | Setup process |
| DNS record | DNS-registro | Configuration |
| CNAME record | CNAME-registro | DNS configuration |

## Error Messages

| English | Esperanto | Context |
|---------|-----------|---------|
| error | eraro | Problem notification |
| warning | averto | Caution notification |
| oops | ho ve | Friendly error introduction |

## Buttons and Actions

| English | Esperanto | Context |
|---------|-----------|---------|
| submit | sendi | Form action |
| cancel | nuligi | Negative action |
| confirm | konfirmi | Affirmative action |
| copy to clipboard | kopii al tondujo | Utility action |
| continue | daŭrigi | Navigation |
| back | reen / reveni | Navigation |
| save | konservi | Save action |
| delete | forigi | Delete action |

## Terms to Keep in English

### Brand Names (Do Not Translate)

- **Onetime Secret** - Keep in English
- **OTS** - Keep in English
- **Identity Plus** - Keep in English
- **Global Elite** - Keep in English
- **Custom Install** - Keep in English
- **Secret Support** - Keep in English (email signature, brand name)

### Technical Terms

Keep these in English:
- API, REST
- DNS, CNAME
- SSL/TLS
- HTTP/HTTPS
- URL
- SSO
- TOTP, WebAuthn

---

## Esperanto-Specific Guidelines

### Critical Terminology Distinctions

#### Password vs Passphrase

**pasvorto** (password): ONLY for account login/authentication.
**sekreta frazo** (passphrase): ONLY for protecting individual secrets.

This distinction must be maintained throughout to avoid user confusion between account security and content protection.

#### Secret Terminology

Esperanto uses "sekreto" directly, which works well as a neutral term. Use:
- "sekreto" for the noun (the shared content)
- "sekreta" as an adjective
- "sekreta mesaĝo" when more context is needed
- "sekreta frazo" specifically for passphrase (not "pasfrazo")

### Esperanto Grammar Notes

#### Accusative Case (-n)

Always apply the accusative ending -n for direct objects:
- "Krei sekreton" (Create a secret)
- "Enigu vian pasvorton" (Enter your password)
- "Kopii al tondujo" (Copy to clipboard - no -n after preposition)

#### Word Building

Esperanto's agglutinative nature allows compound terms:
- forbruligi = for- (away) + bruligi (to burn) = to burn away/destroy
- pasŝlosilo = pas- (pass) + ŝlosilo (key) = passkey
- dufaktora = du- (two) + faktora (factor) = two-factor
- eksvalidiĝi = eks- (former) + valida (valid) + -iĝi (become) = to expire
- kunhavigi = kun- (with/together) + havigi (to provide) = to share

#### Verb Forms for UI

**Imperative (-u)** for buttons and actions:
- "Ensalutu" (Sign in)
- "Konservu" (Save)
- "Konfirmu" (Confirm)

**Infinitive (-i)** for labels and descriptions:
- "Kopii al tondujo" (Copy to clipboard)
- "Forbruligi ĉi tiun sekreton" (Burn this secret)

#### Diacritics

Esperanto uses circumflex diacritics that are essential and must never be omitted:
- ĉ, ĝ, ĥ, ĵ, ŝ, ŭ
- Never substitute with cx, gx, hx, jx, sx, ux (x-system) in production translations

### Voice and Tone

Use the formal "vi" (you) pronoun throughout, which in Esperanto is the standard form for both formal and informal address. Esperanto does not have a separate formal/informal distinction like many European languages, so "vi" is always appropriate.

Maintain a professional yet warm tone, consistent with Esperanto's international and inclusive ethos.

### Pluralization

Esperanto has a simple plural system: add -j to nouns and adjectives.
- sekreto / sekretoj (secret / secrets)
- nova pasvorto / novaj pasvortoj (new password / new passwords)

For i18n plural forms, use the pipe separator:
- "sekreto | sekretoj" (singular | plural)

---

## Summary of Key Terminology Choices

| Concept | Chosen Term | Rationale |
|---------|-------------|-----------|
| secret (noun) | sekreto | Direct, clear Esperanto equivalent |
| passphrase | sekreta frazo | Two-word term distinguishes from pasvorto |
| password | pasvorto | Standard Esperanto computing term |
| burn | forbruligi | Esperanto compound conveying permanent destruction |
| clipboard | tondujo | Established Esperanto computing term |
| passkey | pasŝlosilo | Compound following Esperanto word-building rules |
| two-factor auth | dufaktora aŭtentikigo | Standard compound construction |
| encrypt | ĉifri | Standard Esperanto term for encryption |

---

**Document Version:** 1.0
**Created:** 2026
**For Use With:** Onetime Secret translation projects
**Locale:** eo (Esperanto)
