# Translation Guidance for German (Deutsch)

This document combines the translation glossary and language-specific notes to provide comprehensive guidance for translating Onetime Secret content into German. It serves as a reference for maintaining consistency, accuracy, and appropriate tone across all German translations.

## Table of Contents

1. [Core Terminology](#core-terminology)
2. [Critical Translation Rules](#critical-translation-rules)
3. [Key Translation Decisions](#key-translation-decisions)
4. [Regional Formality Considerations](#regional-formality-considerations)
5. [UI Elements](#ui-elements)
6. [Status Terms](#status-terms)
7. [Time-Related Terms](#time-related-terms)
8. [Security Features](#security-features)
9. [Account-Related Terms](#account-related-terms)
10. [Domain-Related Terms](#domain-related-terms)
11. [Error Messages](#error-messages)
12. [Buttons and Actions](#buttons-and-actions)
13. [Marketing Terms](#marketing-terms)
14. [Translation Guidelines](#translation-guidelines)

---

## Core Terminology

| English | German (AT) | German (DE) | French (FR) | French (CA) | Notes |
|---------|-------------|-------------|-------------|-------------|-------|
| secret (noun) | Geheimnis | Geheimnis | secret | secret | Central concept of the application |
| secret (adj) | geheim | geheim | secret/sécurisé | secret/sécurisé | |
| passphrase | Sicherheitsphrase | Passphrase | phrase secrète | mot de passe | Authentication method for secrets |
| burn | verbrennen | löschen | supprimer | supprimer | Action to delete a secret before viewing |
| view/reveal | ansehen/anzeigen | ansehen/anzeigen | consulter/afficher | consulter/afficher | Action to access a secret |
| link | Link/Verbindung | Link | lien | lien | The URL that provides access to a secret |
| encrypt/encrypted | verschlüsseln/verschlüsselt | verschlüsseln/verschlüsselt | chiffrer/chiffré | chiffrer/chiffré | Security method |
| secure | sicher | sicher | sécurisé | sécurisé | State of protection |

---

## Critical Translation Rules

| Regel | Korrekt | Inkorrekt | Beispiel |
|-------|---------|-----------|---------|
| Secret Übersetzung | Nachricht (UI-Elemente), Geheimnis (technische Dokumentation) | Mixed usage | ✓ Sie haben 3 neue Nachrichten (UI); ✗ Sie haben 3 neue Geheimnisse (UI) |
| Aktiv vs. Passiv | Aktiv (Schaltflächen/Aktionen), Passiv (Status/Benachrichtigungen) | Mixed forms | ✓ Änderungen speichern (button); ✗ Änderungen speichern (status) |
| Förmliche Anrede | du (informal - DE), Sie (formal - AT) | Mixing forms | ✓ Du kannst dein Geheimnis erstellen (DE); ✓ Sie können Ihr Geheimnis erstellen (AT) |
| Zahlenformat | Komma (Dezimal), Punkt (Tausender) | Englisches Format | ✓ 1.234,56; ✗ 1,234.56 |
| Colonel Rolle | Administrator | Wörtliche Übersetzung | ✓ Nur Administratoren haben Zugriff; ✗ Nur Colonels haben Zugriff |

---

## Key Translation Decisions

### 1. `secret` → `Geheimnis`

**Choice:** The term `secret` was consistently translated as `Geheimnis`.

**Rationale:** `Geheimnis` is the direct German equivalent of `secret`. While the guidelines suggest emphasizing "confidential information or message" (like the Danish "besked"), `Geheimnis` is commonly understood in German technical contexts to refer to sensitive data or credentials. Using `Nachricht` (message) might lose the implication of confidentiality, and longer phrases like `vertrauliche Information` are unsuitable for UI elements.

**Distinction from `de_AT`:** Usage is expected to be identical in Austrian German. `Geheimnis` is standard German and used similarly in Austria.

### 2. `password` → `Passwort`

**Choice:** The term `password`, referring specifically to account login credentials, was translated as `Passwort`.

**Rationale:** `Passwort` is the standard, universally understood term for website/account login credentials in German-speaking regions. The alternative `Kennwort` is sometimes seen but `Passwort` is dominant for digital contexts.

**Distinction from `de_AT`:** Usage is identical in Austrian German. `Passwort` is the standard term.

### 3. `passphrase` → `Passphrase`

**Choice:** The term `passphrase`, referring to the protection for an individual secret, was translated directly as `Passphrase`.

**Rationale:** This follows the guideline to maintain a clear distinction from the account `Passwort`. While `Passphrase` is an adopted English term, it is widely recognized in German technical and security contexts precisely for this distinct meaning (a potentially longer, phrase-based secret protector, different from a standard password).

**Distinction from `de_AT`:** Usage is expected to be very similar in Austrian German. `Passphrase` is understood and used in technical contexts across German-speaking areas, including Austria.

---

## Regional Formality Considerations

### German Language Variants

The German language has two primary forms of address that significantly impact translation tone and style. Both Onetime Secret German translations (de and de_AT) maintain consistent approaches within their respective regions:

#### German (Germany) - de.json
**Address Form:** Informal "du" (second person singular informal)

**Characteristics:**
- Modern tech sector standard
- Approachable, friendly tone
- Common in startup and consumer-facing contexts
- Creates sense of partnership with users
- Used with lowercase "du", "dein", "dir", etc.

**Examples:**
- "Du siehst eine sichere Nachricht" (You see a secure message)
- "Gib dein Passwort ein" (Enter your password)
- "Teile diesen Link" (Share this link)

**When to use:**
- Consumer-facing applications
- Modern SaaS products
- Startup or tech-forward brands
- When emphasizing accessibility and approachability

#### German (Austria) - de_AT.json
**Address Form:** Formal "Sie" (second person formal)

**Characteristics:**
- Austrian business standard
- Professional, respectful tone
- Expected in B2B and enterprise contexts
- Maintains appropriate professional distance
- Used with capitalized "Sie", "Ihr", "Ihnen", etc.

**Examples:**
- "Sie betrachten eine sichere Nachricht" (You view a secure message)
- "Geben Sie Ihr Passwort ein" (Enter your password)
- "Teilen Sie diesen Link" (Share this link)

**When to use:**
- Austrian market (regardless of company size)
- B2B/enterprise products
- Government or institutional contexts
- When emphasizing professionalism and trust

### Implementation Guidelines

1. **Consistency Within Locale:**
   - Never mix "du" and "Sie" within a single locale file
   - Maintain chosen formality throughout all user-facing text
   - Apply consistently to buttons, messages, instructions, and help text

2. **Grammar Implications:**
   - "Du" uses second person singular verb forms
   - "Sie" uses third person plural verb forms (even for one person)
   - Possessive pronouns differ: "dein" (du) vs "Ihr" (Sie)
   - Imperative forms differ: "gib" (du) vs "geben Sie" (Sie)

3. **When Unsure:**
   - For Austrian translations: default to "Sie"
   - For German translations: consider target audience
   - Consumer product → "du" likely appropriate
   - B2B product → consider "Sie" for broader appeal

### Translation Pairs Examples

Common phrases showing both approaches:

| Context | German (DE) - du | German (AT) - Sie |
|---------|------------------|-------------------|
| Error message | "Du hast nichts zum Teilen angegeben" | "Sie haben keine Informationen zur Verfügung gestellt" |
| Instruction | "Klicke auf die Schaltfläche" | "Klicken Sie auf die Schaltfläche" |
| Confirmation | "Bist du sicher?" | "Sind Sie sicher?" |
| Success | "Dein Geheimnis wurde erstellt" | "Ihr Geheimnis wurde erstellt" |
| Help text | "Du findest diese in deiner E-Mail" | "Sie finden diese in Ihrer E-Mail" |

### Other German Regional Variations

Beyond formality, note these additional regional differences:

| Concept | German (DE) | German (AT) | Notes |
|---------|-------------|-------------|-------|
| Email example | tom@myspace.com | kontakt@musterfirma.gv.at | .gv.at = Austrian government |
| Passphrase | Passphrase | Sicherheitsphrase | Anglicism vs native compound |
| Submit | senden | einreichen | Informal vs formal term |
| Domain | Domain | Bereich | Technical vs general |

---

## UI Elements

| English | German (AT) | German (DE) | French (FR) | French (CA) | Notes |
|---------|-------------|-------------|-------------|-------------|-------|
| Share a secret | Ein Geheimnis teilen | Geheimnis teilen | Partager un secret | Partager un secret | Main action |
| Create Account | Konto erstellen | Konto erstellen | Créer un compte | Créer un compte | Registration |
| Sign In | Eintragen | Anmelden | Se connecter | Se connecter | Authentication |
| Dashboard | Konto | Dashboard | Tableau de bord | Compte | User's main page |
| Settings | Einstellungen | Einstellungen | Paramètres | Paramètres | Configuration page |
| Privacy Options | Datenschutz-Optionen | Datenschutzoptionen | Options de confidentialité | Options de confidentialité | Secret settings |
| Feedback | Rückmeldung | Feedback | Retour d'information | Retour d'information | User comments |

### Important Examples

**Consistency of Core Terms:**
- `web.COMMON.secret`: Changed from `Geheim` (adjective) to `Geheimnis` (noun)
- `web.COMMON.header_dashboard`: Changed from `Account` to `Konto`
- `web.COMMON.header_sign_in`: Changed from `Einloggen` to `Anmelden`
- `web.COMMON.burn`: Standardized to `Zerstören` (verb) / `Zerstört` (past participle/status)
- `web.COMMON.received`: Changed from `Erhalten` to `Empfangen`

**Clarity and Natural Phrasing:**
- `web.COMMON.copied_to_clipboard`: `In die Zwischenablage kopiert`
- `web.COMMON.faq_title`: Changed from `F.A.Q.` to `Häufig gestellte Fragen`
- `web.LABELS.loading`: Changed from `Loading...` to `Lädt...`
- `web.login.remember_me`: `Angemeldet bleiben` (Standard phrase)
- `web.shared.viewed_own_secret`: Changed `angeschaut` to `angesehen`

---

## Status Terms

| English | German (AT) | German (DE) | French (FR) | French (CA) | Notes |
|---------|-------------|-------------|-------------|-------------|-------|
| received | empfangen | empfangen | reçu | reçu | Secret has been viewed |
| burned | verbrannt | gelöscht | supprimé | supprimé | Secret was deleted before viewing |
| expired | abgelaufen | abgelaufen | expiré | expiré | Secret is no longer available due to time |
| created | erstellt | erstellt | créé | créé | Secret has been generated |
| active | aktiv | aktiv | actif | actif | Secret is available |
| inactive | inaktiv | inaktiv | inactif | inactif | Secret is not available |

### Voice Usage for Status

**Rationale:** Guidelines specify imperative for user actions (buttons, links) and passive/declarative for informational text.

**Examples:**
- `web.STATUS.*_description`: Declarative/passive voice (e.g., "Geheimer Link wurde erstellt...")
- `web.shared.post_reveal_default`: `Deine sichere Nachricht wird unten angezeigt.` (Passive voice)

---

## Time-Related Terms

| English | German (AT) | German (DE) | French (FR) | French (CA) | Notes |
|---------|-------------|-------------|-------------|-------------|-------|
| expires in | läuft ab in | läuft ab in | expire dans | expire dans | Time until secret is no longer available |
| day/days | Tag/Tage | Tag/Tage | jour/jours | jour/jours | Time unit |
| hour/hours | Stunde/Stunden | Stunde/Stunden | heure/heures | heure/heures | Time unit |
| minute/minutes | Minute/Minuten | Minute/Minuten | minute/minutes | minute/minutes | Time unit |
| second/seconds | Sekunde/Sekunden | Sekunde/Sekunden | seconde/secondes | seconde/secondes | Time unit |

---

## Security Features

| English | German (AT) | German (DE) | French (FR) | French (CA) | Notes |
|---------|-------------|-------------|-------------|-------------|-------|
| one-time access | einmaliger Zugang | einmaliger Zugriff | accès unique | accès unique | Core security feature |
| passphrase protection | Schutz durch Sicherheitsphrase | Passphrasenschutz | protection par phrase secrète | protection par phrase d'authentification | Additional security |
| encrypted in transit | verschlüsselt bei der Übertragung | während der Übertragung verschlüsselt | chiffré en transit | chiffré en transit | Data protection method |
| encrypted at rest | verschlüsselt im Ruhezustand | im Ruhezustand verschlüsselt | chiffré au repos | chiffré au repos | Storage protection |

---

## Account-Related Terms

| English | German (AT) | German (DE) | French (FR) | French (CA) | Notes |
|---------|-------------|-------------|-------------|-------------|-------|
| email | E-Mail | E-Mail | courriel/e-mail | courriel | User identifier |
| password | Passwort | Passwort | mot de passe | mot de passe | Authentication |
| account | Konto | Konto | compte | compte | User profile |
| subscription | Abonnement | Abonnement | abonnement | abonnement | Paid service |
| customer | Kunde | Kunde | client | client | Paying user |

**Direct Address Examples (Du vs. Sie):**
- `web.COMMON.careful_only_see_once`: Changed "Wir werden es..." to `Du wirst es...`
- `web.LABELS.need_help`: `Brauchst du Hilfe?`
- `web.homepage.cta_title`: Changed from formal "Verwenden Sie..." to informal `Verwende...`
- `web.login.login_to_your_account`: `Melde dich bei deinem Konto an`

---

## Domain-Related Terms

| English | German (AT) | German (DE) | French (FR) | French (CA) | Notes |
|---------|-------------|-------------|-------------|-------------|-------|
| custom domain | benutzerdefinierter Bereich | benutzerdefinierte Domain | domaine personnalisé | domaine personnalisé | Premium feature |
| domain verification | Domänenüberprüfung | Domain-Verifizierung | vérification du domaine | vérification du domaine | Setup process |
| DNS record | Namensserver-Eintrag | DNS-Eintrag | enregistrement DNS | enregistrement DNS | Configuration |
| CNAME record | CNAME-Eintrag | CNAME-Eintrag | enregistrement CNAME | enregistrement CNAME | DNS setup |

---

## Error Messages

| English | German (AT) | German (DE) | French (FR) | French (CA) | Notes |
|---------|-------------|-------------|-------------|-------------|-------|
| error | Fehler | Fehler | erreur | bug | Problem notification |
| warning | Warnung | Warnung | avertissement | attention | Caution notification |
| oops | Huch | Hoppla | oups | oups | Friendly error intro |

---

## Buttons and Actions

| English | German (AT) | German (DE) | French (FR) | French (CA) | Notes |
|---------|-------------|-------------|-------------|-------------|-------|
| submit | einreichen | absenden | soumettre | soumettre | Form action |
| cancel | abbrechen | abbrechen | annuler | annuler | Negative action |
| confirm | bestätigen | bestätigen | confirmer | confirmer | Positive action |
| copy to clipboard | in die Zwischenablage kopieren | in die Zwischenablage kopieren | copier dans le presse-papiers | copier dans le presse-papiers | Utility action |
| continue | weiter | fortfahren | continuer | continuer | Navigation |
| back | zurück | zurück | retour | retour | Navigation |

### Voice Usage for Actions

**Rationale:** Imperative for user actions (buttons, links).

**Examples:**
- `web.help.learn_more`: `Mehr erfahren` (Imperative/infinitive for links)
- `web.COMMON.button_generate_secret_short`: `Passwort generieren` (Imperative action)
- `web.COMMON.share_link_securely`: `Teile diesen Link aus Sicherheitsgründen...` (Clear imperative)
- `web.help.secret_view_faq.*.description`: Declarative sentences (e.g., "Du siehst...", "Dieser Inhalt wird...")

---

## Marketing Terms

| English | German (AT) | German (DE) | French (FR) | French (CA) | Notes |
|---------|-------------|-------------|-------------|-------------|-------|
| secure links | sichere Links | sichere Links | liens sécurisés | liens sécurisés | Product feature |
| privacy-first design | Datenschutz als oberstes Gebot | Datenschutz-First-Design | conception privilégiant la protection de la vie privée | conception privilégiant la protection de la vie privée | Design philosophy |
| custom branding | benutzerdefiniertes Branding | individuelles Branding | image de marque personnalisée | image de marque personnalisée | Premium feature |

---

## Translation Guidelines

### Core Principles

1. **Consistency**: Use the same translation for a term throughout the application
2. **Context**: Consider how the term is used in the application
3. **Cultural Adaptation**: Adapt terms to local conventions when needed
4. **Technical Accuracy**: Ensure security terms are correctly translated
5. **Tone**: Maintain a professional but direct tone

### Specific Guidelines

#### Voice and Formality
- **Imperative for Actions**: Use imperative voice for buttons and user actions
- **Passive for Status**: Use passive/declarative voice for informational text and status messages
- **Consistent Address Form**: Never mix "du" and "Sie" within the same locale
- **Regional Consistency**: Maintain formality appropriate to the target region (DE vs AT)

#### Number Formatting
- Use comma for decimal separator: `1.234,56`
- Use period for thousands separator
- Never use English number formatting

#### Technical Terms
- Prioritize accuracy over localization for security terms
- Use established German technical terminology
- Maintain clear distinction between `Passwort` (account password) and `Passphrase` (secret protection)

#### UI and Platform Conventions
- Follow platform conventions for the target language
- Ensure UI elements are clear and actionable
- Keep button text concise and in imperative form

### Testing Formality Choices

Before finalizing translations:

1. **Native Speaker Review**: Have native speakers from target region review
2. **Context Check**: Ensure formality matches brand positioning
3. **Consistency Audit**: Verify no formality mixing within locale
4. **Competitor Benchmark**: Check how similar products address users in target market

---

## Special Considerations

- The term "secret" is central to the application and should be translated consistently as `Geheimnis`
- Regional variations between German (DE) and Austrian German (AT) should be respected, particularly regarding formality
- For security-related technical terms, accuracy should take precedence over localization
- UI elements should follow platform conventions for the target language
- Maintain clear distinction between `Passwort` (account password) and `Passphrase` (individual secret protection)
- Number formatting must always use German conventions (comma for decimals, period for thousands)
- Role names like "Colonel" should be translated to their functional equivalent (`Administrator`) rather than literally

---

## Document History

This document combines content from:
- `glossary.md` - Translation glossary reference
- `language-notes.md` - German-specific translation decisions and rules

Last updated: 2025-11-16
