# Translation Guidance for Dutch (Nederlands)

This document combines the glossary and language-specific translation notes for Dutch localization of Onetime Secret. It provides comprehensive guidance for maintaining consistency, cultural appropriateness, and technical accuracy in Dutch translations.

## Overview

This guide serves translators working on Dutch (Nederlands) localization for Onetime Secret. It includes:
- Standardized terminology glossary
- Critical translation decisions and rationale
- Grammar and style guidelines
- Regional and formatting conventions
- Quality assurance recommendations

---

## Critical Native Speaker Insight

**Native Dutch speakers report that word choice critically affects trust and professionalism:**

- **"Beveiligd"** (secured) - Sounds businesslike and professional. Makes users more likely to trust the service.
- **"Vertrouwelijk"** (confidential) - Sounds like you're trying to convince users you're trustworthy rather than actually being secure. AVOID in general UI.
- **"Geheim"** (secret) - Evokes associations with criminal underworld ("the German underworld"). AVOID entirely.

**Recommended approach:** Use "bericht" (message) or "beveiligd bericht" (secured message) for nouns, and "beveiligd" for adjectives describing protection. This follows the same principle as Danish translations, which use "beskeder" (messages) instead of "hemmeligheder" (secrets) to maintain professional context.

---

## Core Translation Principles

### 1. Consistency
Use the same translation for a term throughout the entire application to avoid confusion.

### 2. Context Awareness
Consider how terms are used in the application and adjust translations accordingly.

### 3. Cultural Adaptation
Adapt terms to local conventions and cultural norms where appropriate.

### 4. Technical Accuracy
Ensure security and technical terms are translated accurately, prioritizing clarity over localization when necessary.

### 5. Tone
Maintain a professional but approachable tone using informal "je" address form.

---

## Key Terminology Decisions

### 1. `secret` → `bericht` / `beveiligd bericht`

**Translation:** The term `secret` is translated as `bericht` (message) or `beveiligd bericht` (secured message).

**Rationale:** Following the Danish model and native speaker feedback, `bericht` or `beveiligd bericht` should be used instead of `geheim`. While `geheim` is a literal translation, native speakers report it evokes associations with the criminal underworld rather than business security. For general communication about protecting information, `beveiligd` sounds more businesslike and professional, inspiring trust.

**Native speaker feedback:** "For general communication about protecting information, 'beveiligd' reads more polished and businesslike. 'Beveiligd' makes me more likely to trust you. 'Vertrouwelijk' makes me think you have to convince me that you're trustworthy. 'Geheim' makes me think of the German underworld."

**Context-specific usage:**
- **UI elements (noun):** `bericht` or `beveiligd bericht` (e.g., "Je hebt 3 nieuwe berichten", "Maak een nieuw beveiligd bericht")
- **Descriptive context (adjective):** `beveiligd` (e.g., "beveiligde links", "beveiligd delen")
- **AVOID:** `geheim` (criminal underworld associations), `vertrouwelijk` (sounds unconvincing)

**Examples:**
- ✓ "Je hebt 3 nieuwe berichten" (You have 3 new messages)
- ✓ "Maak een nieuw beveiligd bericht" (Create a new secret)
- ✓ "Beveiligd bericht delen" (Share a secure message)
- ✓ "Beveiligde links" (Secure links - adjective)
- ✗ "Je hebt 3 nieuwe geheimen" (inappropriate connotations)
- ✗ "Geheime links" (evokes wrong associations)

### 2. `password` → `wachtwoord`

**Translation:** The term `password`, which specifically refers to login credentials for an account, is translated as `wachtwoord`.

**Rationale:** `Wachtwoord` is the standard, universally understood term for website/account login credentials in Dutch. This is the term users expect when logging into an account.

**Examples:**
- ✓ "Voer je wachtwoord in" (Enter your password)
- ✓ "Wachtwoord vergeten?" (Forgot password?)

### 3. `passphrase` → `wachtwoordzin`

**Translation:** The term `passphrase`, which refers to the protection for an individual secret, is translated as `wachtwoordzin`.

**Rationale:** This follows the guideline to maintain clear distinction from the account `wachtwoord`. `Wachtwoordzin` is a compound Dutch word that communicates the concept of a longer, phrase-based security measure, different from a standard password. This distinction is crucial for user understanding.

**Maintain distinction:**
- `wachtwoord` = for account access
- `wachtwoordzin` = for secret protection

**Examples:**
- ✓ "Beveilig met een wachtwoordzin" (Protect with a passphrase)
- ✓ "Voer de wachtwoordzin in om te bekijken" (Enter the passphrase to view)
- ✗ "Beveilig met een wachtwoord" (confusing - this is for accounts)

### 4. `burn` → `verbranden`

**Translation:** The term `burn` is translated as `verbranden`.

**Rationale:** `Verbranden` communicates the permanence and irreversibility of the action. Alternatives like `vernietigen` or `verwijderen` are also correct, but `verbranden` preserves the metaphor of the original and is understood in technical contexts.

**Examples:**
- ✓ "Het geheim werd verbrand" (The secret was burned)
- ✓ Status: "Verbrand" (Status: Burned)
- Also acceptable: "vernietigen", "verwijderen" (delete/destroy)

### 5. `link` → `link` or `koppeling`

**Translation:** Both `link` and `koppeling` are acceptable in Dutch.

**Rationale:** `Link` is a borrowed English word that is fully naturalized in Dutch. `Koppeling` is the pure Dutch equivalent. For consistency, we recommend choosing one term and using it consistently.

**Recommendation:** Use `link` in UI elements for conciseness, and `koppeling` in more extensive documentation where it sounds more natural.

**Examples:**
- ✓ "Kopieer de link" (Copy the link - UI)
- ✓ "Geheime koppelingen" (Secret links - documentation)

---

## Comprehensive Terminology Glossary

### Core Application Terms

| English | Dutch (NL) | Context |
|---------|------------|---------|
| secret (noun) | bericht / beveiligd bericht | Central application concept - the thing being shared |
| secret (adjective) | beveiligd | Descriptive adjective for protection |
| message | bericht | General term for messages |
| secure/secured | beveiligd | Protection status - sounds businesslike |
| confidential | vertrouwelijk | AVOID in general UI - use only in formal legal contexts |
| geheim | VERMIJD / AVOID | Evokes criminal underworld associations |
| passphrase | wachtwoordzin | Authentication method for secrets |
| password | wachtwoord | Authentication for account access |
| burn | verbranden | Action to delete a secret before viewing |
| view/reveal | bekijken/weergeven | Action to access a secret |
| link | link/koppeling | The URL that provides access to a secret |
| encrypt/encrypted | versleutelen/versleuteld | Security method |
| encryption | versleuteling/encryptie | The process of encrypting |
| secure | beveiligd/veilig | Protection status |
| private | privé | Privacy status |

### User Interface Elements

| English | Dutch (NL) | Context |
|---------|------------|---------|
| Share a secret | Een geheim delen | Main action |
| Create Account | Account aanmaken | Registration |
| Sign In | Inloggen/Aanmelden | Authentication |
| Dashboard | Dashboard | User main page |
| Settings | Instellingen | Configuration page |
| Privacy Options | Privacyopties | Secret settings |
| Feedback | Feedback | User comments |

### Status Terms

| English | Dutch (NL) | Context |
|---------|------------|---------|
| received | ontvangen | Secret has been viewed |
| burned | verbrand | Secret was deleted before viewing |
| expired | verlopen | Secret is no longer available due to time |
| created | aangemaakt | Secret was generated |
| active | actief | Secret is available |
| inactive | inactief | Secret is not available |

### Time-Related Terms

| English | Dutch (NL) | Context |
|---------|------------|---------|
| expires in | verloopt over | Time until secret is no longer available |
| day/days | dag/dagen | Time unit |
| hour/hours | uur/uren | Time unit |
| minute/minutes | minuut/minuten | Time unit |
| second/seconds | seconde/seconden | Time unit |

### Security Features

| English | Dutch (NL) | Context |
|---------|------------|---------|
| one-time access | eenmalige toegang | Core security feature |
| passphrase protection | bescherming door wachtwoordzin | Additional security |
| encrypted in transit | versleuteld tijdens transport | Data protection method |
| encrypted at rest | versleuteld in rust | Storage protection |
| self-destructing | zelfvernietigend | Automatic deletion after use |

### Account-Related Terms

| English | Dutch (NL) | Context |
|---------|------------|---------|
| email | e-mail | User identification |
| password | wachtwoord | Account authentication |
| account | account | User profile |
| subscription | abonnement | Paid service |
| customer | klant | Paying user |
| plan | plan/abonnement | Service level |

### Domain-Related Terms

| English | Dutch (NL) | Context |
|---------|------------|---------|
| custom domain | aangepast domein | Premium feature |
| domain verification | domeinverificatie | Setup process |
| DNS record | DNS-record | Configuration |
| CNAME record | CNAME-record | DNS setup |

### Error Messages

| English | Dutch (NL) | Context |
|---------|------------|---------|
| error | fout | Problem notification |
| warning | waarschuwing | Warning notification |
| oops | oeps | Friendly error introduction |

### Buttons and Actions

| English | Dutch (NL) | Context |
|---------|------------|---------|
| submit | verzenden/versturen | Form action |
| cancel | annuleren | Negative action |
| confirm | bevestigen | Positive action |
| copy to clipboard | kopiëren naar klembord | Utility action |
| continue | doorgaan | Navigation |
| back | terug | Navigation |
| delete | verwijderen | Delete action |
| save | opslaan | Save action |
| create | aanmaken | Create action |

### Marketing Terms

| English | Dutch (NL) | Context |
|---------|------------|---------|
| secure links | beveiligde links | Product feature |
| privacy-first design | privacy-eerst ontwerp | Design philosophy |
| custom branding | aangepaste branding | Premium feature |
| ephemeral | efemeer/tijdelijk | Temporary nature of secrets |

---

## Grammar and Style Guidelines

### Voice and Tone

#### Active vs. Passive Voice

**Rationale:** Guidelines specify active imperative voice for user actions (buttons, links) and passive/declarative voice for informative text.

**Examples:**

**Buttons (active):**
- ✓ "Opslaan" (Save)
- ✓ "Verwijderen" (Delete)
- ✓ "Aanmaken" (Create)

**Status messages (passive):**
- ✓ "Opgeslagen" (Saved)
- ✓ "Verwijderd" (Deleted)
- ✓ "Link aangemaakt" (Link created)

### Clarity and Natural Sentence Structure

**Rationale:** Translations should sound natural to native speakers and not be literal.

**Examples:**
- ✓ "Gekopieerd naar klembord" (Copied to clipboard)
- ✓ "Veelgestelde vragen" (FAQ)
- ✓ "Laden..." (Loading...)
- ✗ "Kopiëren naar het klembord" (too formal/long for UI)

### Direct Address (je vs. u)

**Rationale:** Dutch translations use the informal address form "je" for a more accessible, friendly tone. This is standard in modern tech products and SaaS applications.

**Examples:**
- ✓ "Je zult het maar één keer kunnen zien" (You will only be able to see it once)
- ✓ "Heb je hulp nodig?" (Do you need help?)
- ✓ "Maak je eerste geheim aan" (Create your first secret)
- ✗ "U zult het maar één keer kunnen zien" (too formal for target audience)

**When to use "u":**
- In very formal B2B/enterprise contexts
- For government or institutional applications
- Only if explicitly requested by client

### Borrowed English Words

Dutch accepts many borrowed English words, especially in technical contexts. Use them where they are natural and commonly understood.

**Acceptable borrowed words:**
- link
- e-mail (with hyphen)
- dashboard
- account
- feedback
- settings (though "instellingen" is preferred)
- API
- token

**Dutch preference:**
- ✓ instellingen (not settings)
- ✓ gebruiker (not user)
- ✓ klant (not customer)
- ✓ delen (not sharen)

---

## Critical Translation Rules

| Rule | Correct | Incorrect | Example |
|------|---------|-----------|---------|
| Secret translation (noun) | bericht / beveiligd bericht | geheim | ✓ Je hebt 3 nieuwe berichten; ✓ Beveiligd bericht delen; ✗ Je hebt 3 nieuwe geheimen |
| Secret translation (adjective) | beveiligd | geheim/vertrouwelijk | ✓ Beveiligde links; ✗ Geheime links; ✗ Vertrouwelijke links |
| Geheim | VERMIJD / AVOID | In any UI context | ✗ Geheime berichten; ✗ Maak een geheim (evokes criminal associations) |
| Password vs. passphrase | wachtwoord (account), wachtwoordzin (secret) | Both as "wachtwoord" | ✓ Voer je wachtwoord in (login); ✓ Voeg een wachtwoordzin toe (secret) |
| Active vs. passive | Active (buttons/actions), passive (status/notifications) | Mixed forms | ✓ Opslaan (button); ✓ Opgeslagen (status) |
| Informal address | je (informal) | u (formal) unless required | ✓ Je kunt je geheim aanmaken; ✗ U kunt uw geheim aanmaken |
| Number format | Comma (decimal), period (thousands) | English format | ✓ 1.234,56; ✗ 1,234.56 |
| Currency | € 19,99 or €19,99 | $19.99 | ✓ € 19,99; ✗ $19.99 |
| Date | dd-mm-yyyy or yyyy-mm-dd | mm/dd/yyyy | ✓ 14-11-2025; ✓ 2025-11-14; ✗ 11/14/2025 |
| Time | 24-hour notation | 12-hour notation with AM/PM | ✓ 14:30; ✗ 2:30 PM |
| Colonel role | beheerder/administrator | literal translation | ✓ Alleen beheerders hebben toegang; ✗ Alleen colonels hebben toegang |

---

## Numbers and Symbols

### Decimals and Thousands
- Decimal separator: comma (,)
- Thousands separator: period (.) or space ( )
- Examples: 1,23 or 1.234,56 or 1 234,56

### Currency
- Symbol: €
- Position: Before or after the amount with space
- Examples: € 19,99 or €19,99 (both acceptable)

### Percentages
- Symbol: %
- Position: Directly after the number
- Example: 99,95%

---

## Date and Time Formats

### Date
- Short format: dd-mm-yyyy (14-11-2025)
- ISO format: yyyy-mm-dd (2025-11-14) - preferred for technical contexts
- Long format: 14 november 2025

### Time
- Always 24-hour notation: 14:30 (not 2:30 PM)
- Seconds if needed: 14:30:45

---

## Address Format

Dutch address format follows this structure:

```
[Recipient name]
[Street name] [House number][Addition]
[Postal code] [City]
[COUNTRY]
```

Example:
```
Jan de Vries
Keizersgracht 123A
1015 CJ Amsterdam
NEDERLAND
```

---

## Regional Considerations

### Nederlands (Nederland) - nl

**Characteristics:**
- Informal "je" address form as standard
- Modern, accessible tone
- Common in tech and SaaS products
- Direct and efficient in communication

**Alternative variants:**
- Nederlands (België) may have small differences in word choice
- Flemish Dutch may have other preferred terms
- Standard Dutch (Netherlands) is recommended for international products

---

## Quality Assurance

### Testing Translation Choices

Before finalizing translations:

1. **Native speaker review:** Have native speakers from the Netherlands review the texts
2. **Context check:** Ensure tone and formality match brand positioning
3. **Consistency audit:** Verify terminology is used consistently
4. **User testing:** Test with real Dutch users for naturalness

### Completeness

All texts must be completely translated into natural Dutch, preserving the meaning and tone of the original.

---

## Important Examples Summary

### Consistency of Core Terms
- `secret` (noun): Always `bericht` or `beveiligd bericht` (AVOID `geheim` - criminal underworld associations)
- `dashboard`: `Dashboard` (naturalized English word)
- `settings`: `Instellingen`
- `account`: `Account` (naturalized English word)

### Context-Appropriate Translation
When the same English word requires different translations based on context:
- `password` (account) → `wachtwoord`
- `passphrase` (secret protection) → `wachtwoordzin`
- `secure` (status) → `beveiligd/veilig`
- `private` (privacy) → `privé`

### UI-Specific Patterns
- Keep button text concise using active verbs
- Use passive voice for status confirmations
- Maintain informal "je" throughout
- Prefer naturalized English terms where common (`link`, `dashboard`, `account`)

---

## Related Documentation

For additional guidance on brand voice, grammar guidelines, and specific use cases, refer to:
- Brand Voice guidelines
- Grammar and Style guidelines
- Security terminology documentation
- User interface copywriting standards

---

**Version:** 1.0
**Last Updated:** 2025-01-16
**Language Code:** nl
**Target Region:** Netherlands (primary), Belgium (secondary)
