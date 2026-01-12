---
title: Ръководство за превод на български
description: Цялостно ръководство за превод на Onetime Secret на български език, съчетаващо речник на термините и езикови бележки
---

# Translation Guidance for Bulgarian (Български)

This document combines the glossary and language-specific translation notes to provide comprehensive guidance for translating Onetime Secret into Bulgarian. It serves as a reference for maintaining consistency, clarity, and cultural appropriateness across the application.

---

## Core Terminology

The following table provides standardized Bulgarian translations for key terms, based on analysis of existing translations in German (Austria), French (France), and French (Canada).

| Bulgarian | German (AT) | French (FR) | French (CA) | Notes |
|---------|-------------|-------------|-------------|-------|
| secret (noun) | Geheimnis | secret | secret | Central concept of the application |
| secret (adj) | geheim | secret/sécurisé | secret/sécurisé | |
| passphrase | Sicherheitsphrase | phrase secrète | mot de passe | Authentication method for secrets |
| burn | verbrennen | supprimer | supprimer | Action to delete a secret before viewing |
| view/reveal | ansehen/anzeigen | consulter/afficher | consulter/afficher | Action to access a secret |
| link | Link/Verbindung | lien | lien | The URL that provides access to a secret |
| encrypt/encrypted | verschlüsseln/verschlüsselt | chiffrer/chiffré | chiffrer/chiffré | Security method |
| secure | sicher | sécurisé | sécurisé | State of protection |

---

## Critical Terminology Distinctions

### Password vs. Passphrase

**Important:** Bulgarian translations must distinguish clearly between two different security contexts:

1. **"парола" (password)** - Used for user authentication contexts:
   - Account login credentials
   - Password fields in registration forms
   - Account-related password operations
   - User account security

2. **"ключова фраза" (key phrase)** - Used for secret protection contexts:
   - Secret creation and viewing
   - Protection mechanism for shared secrets
   - Error messages related to incorrect secret access credentials
   - Optional security layer for individual secrets

**Examples:**
- `web.COMMON.incorrect_passphrase`: "Грешна ключова фраза"
- `web.COMMON.error_passphrase`: "...ключовата фраза..."
- `web.private.requires_passphrase`: "Изисква ключова фраза."
- `web.LABELS.passphrase_protected`: "Защитено с ключова фраза"

### Secret Translation

**Guideline:** Translate "secret" as confidential information being shared, not personal secrets.

- **Primary translation:** "тайна" (secret) - More natural and appropriate for confidential information being shared ephemerally
- **Avoid overusing:** "секрет" (direct loanword often implying personal/state secrets)
- **Alternative when appropriate:** "съобщение" (message) - Can be used in specific contexts

**Examples:**
- "Secret created successfully!" → "Тайната е създадена успешно!"
- "This secret..." → "Тази тайна..."
- "...the entire secret." → "...цялата тайна."

---

## User Interface Elements

| Bulgarian | German (AT) | French (FR) | French (CA) | Notes |
|---------|-------------|-------------|-------------|-------|
| Share a Secret | Ein Geheimnis teilen | Partager un secret | Partager un secret | Primary action |
| Create an Account | Konto erstellen | Créer un compte | Créer un compte | Registration |
| Log In | Eintragen | Se connecter | Se connecter | Authentication |
| Dashboard | Konto | Tableau de bord | Compte | Main user page |
| Settings | Einstellungen | Paramètres | Paramètres | Configuration page |
| Privacy Options | Datenschutz-Optionen | Options de confidentialité | Options de confidentialité | Secret settings |
| Feedback | Rückmeldung | Retour d'information | Retour d'information | User comments |

---

## State Conditions

| Bulgarian | German (AT) | French (FR) | French (CA) | Notes |
|---------|-------------|-------------|-------------|-------|
| received | empfangen | reçu | reçu | Secret has been viewed |
| burned | verbrannt | supprimé | supprimé | Secret was deleted before viewing |
| expired | abgelaufen | expiré | expiré | Secret is no longer available due to time expiration |
| created | erstellt | créé | créé | Secret has been generated |
| active | aktiv | actif | actif | Secret is available |
| inactive | inaktiv | inactif | inactif | Secret is not available |

---

## Time-Related Terms

| Bulgarian | German (AT) | French (FR) | French (CA) | Notes |
|---------|-------------|-------------|-------------|-------|
| expires in | läuft ab in | expire dans | expire dans | Time until secret is no longer available |
| day/days | Tag/Tage | jour/jours | jour/jours | Time unit |
| hour/hours | Stunde/Stunden | heure/heures | heure/heures | Time unit |
| minute/minutes | Minute/Minuten | minute/minutes | minute/minutes | Time unit |
| second/seconds | Sekunde/Sekunden | seconde/secondes | seconde/secondes | Time unit |

---

## Security Features

| Bulgarian | German (AT) | French (FR) | French (CA) | Notes |
|---------|-------------|-------------|-------------|-------|
| one-time access | einmaliger Zugang | accès unique | accès unique | Core security feature |
| passphrase protection | Schutz durch Sicherheitsphrase | protection par phrase secrète | protection par phrase d'authentification | Additional security |
| encrypted in transit | verschlüsselt bei der Übertragung | chiffré en transit | chiffré en transit | Data protection method |
| encrypted at rest | verschlüsselt im Ruhezustand | chiffré au repos | chiffré au repos | Storage protection |

---

## Account-Related Terms

| Bulgarian | German (AT) | French (FR) | French (CA) | Notes |
|---------|-------------|-------------|-------------|-------|
| email | E-Mail | courriel/e-mail | courriel | User identifier |
| password | Passwort | mot de passe | mot de passe | Authentication |
| account | Konto | compte | compte | User profile |
| subscription | Abonnement | abonnement | abonnement | Paid service |
| customer | Kunde | client | client | Paying user |

---

## Domain-Related Terms

| Bulgarian | German (AT) | French (FR) | French (CA) | Notes |
|---------|-------------|-------------|-------------|-------|
| custom domain | benutzerdefinierter Bereich | domaine personnalisé | domaine personnalisé | Premium feature |
| domain verification | Domänenüberprüfung | vérification du domaine | vérification du domaine | Setup process |
| DNS record | Namensserver-Eintrag | enregistrement DNS | enregistrement DNS | Configuration |
| CNAME record | CNAME-Eintrag | enregistrement CNAME | enregistrement CNAME | DNS setup |

---

## Error Messages

| Bulgarian | German (AT) | French (FR) | French (CA) | Notes |
|---------|-------------|-------------|-------------|-------|
| error | Fehler | erreur | bug | Problem notification |
| warning | Warnung | avertissement | attention | Caution notification |
| oops | Huch | oups | oups | Friendly error intro |

---

## Buttons and Actions

| Bulgarian | German (AT) | French (FR) | French (CA) | Notes |
|---------|-------------|-------------|-------------|-------|
| submit | einreichen | soumettre | soumettre | Form action |
| cancel | abbrechen | annuler | annuler | Negative action |
| confirm | bestätigen | confirmer | confirmer | Positive action |
| copy to clipboard | in die Zwischenablage kopieren | copier dans le presse-papiers | copier dans le presse-papiers | Utility action |
| continue | weiter | continuer | continuer | Navigation |
| back | zurück | retour | retour | Navigation |

---

## Marketing Terms

| Bulgarian | German (AT) | French (FR) | French (CA) | Notes |
|---------|-------------|-------------|-------------|-------|
| secure links | sichere Links | liens sécurisés | liens sécurisés | Product feature |
| privacy-first design | Datenschutz als oberstes Gebot | conception privilégiant la protection de la vie privée | conception privilégiant la protection de la vie privée | Design philosophy |
| custom branding | benutzerdefiniertes Branding | image de marque personnalisée | image de marque personnalisée | Premium feature |

---

## Translation Guidelines

### 1. Consistency
- Use the same translation for a given term throughout the application
- Maintain the password/passphrase distinction rigorously
- Follow the glossary for all standardized terms

### 2. Context
- Pay attention to how the term is used in the application
- Consider whether the action is user-initiated or system-generated
- Differentiate between authentication (account) and secret protection contexts

### 3. Cultural Adaptation
- Adapt terms to local conventions when necessary
- Use natural-sounding Bulgarian rather than literal translations
- Prefer clarity over casual language

### 4. Technical Accuracy
- Ensure security-related terms are translated precisely
- Maintain technical meaning even when localizing
- Use "перманентно изтрито" (permanently deleted) for emphasis when appropriate

### 5. Tone and Voice
- Maintain professional yet direct tone
- Use active, imperative voice for user actions (buttons)
- Use passive/declarative voice for informational content (status messages)

### 6. Clarity and Natural Phrasing
- Prioritize clarity over literal translation
- Replace vague terms with clearer ones like "изтрито" (deleted)
- Ensure placeholder text is natural: "...се въвежда тук..." (is entered here)

---

## Voice Consistency Examples

### Active/Imperative (User Actions)
- `web.COMMON.button_create_secret`: "Създай тайна връзка" (Create secret link)
- Buttons should use imperative mood
- Direct commands to the user

### Passive/Declarative (Status Messages)
- `web.private.created_success`: "Тайната е създадена успешно!" (The secret has been created successfully!)
- Status messages describe completed states
- Informational content about system state

---

## Special Considerations

### The Term "Secret"
- The term "secret" is central to the application and must be translated consistently
- "Тайна" is preferred over "секрет" for natural Bulgarian
- Context determines whether to use "съобщение" (message) as an alternative

### Deletion and Destruction
- Use "изтрито" (deleted) for clarity
- Add "перманентно" (permanently) for emphasis when the action is irreversible
- "Burned" secrets are "изгорени" but explanation text should clarify permanent deletion

### Natural Placeholders
- Input placeholder text should feel natural: "...се въвежда тук..." not "...отива тук..."
- Guide the user with clear, helpful text
- Avoid overly literal translations of English placeholders

### Password Strength Levels
- Use standard Bulgarian equivalents for strength indicators
- "Отлична" (Excellent) not "Great"
- "Задоволителна" (Satisfactory) not "Meh"
- Maintain professional tone even for informal English terms

---

## Summary of Key Changes from Initial Translation

### Terminology Standardization
1. **Passphrase distinction introduced:**
   - Changed from mixed usage of "парола" and "фраза"
   - Now consistently uses "ключова фраза" for secret protection
   - Reserves "парола" for account authentication

2. **Secret translation refined:**
   - Shifted from "секрет" to "тайна" as primary translation
   - More natural and appropriate for the application context
   - Better conveys the ephemeral, confidential nature

3. **Clarity improvements:**
   - Replaced awkward literal translations with natural Bulgarian
   - Added "перманентно" for irreversible actions
   - Improved placeholder text naturalness

### Section-Specific Updates

**Common UI Elements:**
- `secret_passphrase`: "Парола за тайната" → "Ключова фраза за тайната"
- `incorrect_passphrase`: "Грешна парола" → "Грешна ключова фраза"
- `enter_passphrase_here`: "Въведете паролата тук" → "Въведете ключовата фраза тук"

**Labels:**
- `no_passphrase`: "Не се изисква парола" → "Не се изисква ключова фраза"
- `passphrase_protected`: "Защитено с парола" → "Защитено с ключова фраза"

**Private and Shared Sections:**
- `requires_passphrase`: "Изисква парола" → "Изисква ключова фраза"
- All encryption-related messaging updated to reference "ключова фраза"

**FAQ Section:**
- `passphrase_title`: "Как работи опцията за парола?" → "Как работи опцията за ключова фраза?"
- All related trust and security points updated

---

## Translation Workflow Recommendations

1. **Initial Translation:**
   - Start with the glossary
   - Use standardized terms from the tables above
   - Apply the password/passphrase distinction immediately

2. **Review Phase:**
   - Check for consistency across all strings
   - Verify natural phrasing in Bulgarian
   - Ensure technical accuracy is maintained

3. **Context Verification:**
   - Test translations in the actual UI
   - Verify button text feels actionable
   - Ensure status messages are clear

4. **Final Polish:**
   - Remove any overly literal translations
   - Verify tone consistency
   - Check that all special considerations are addressed

---

## Conclusion

This guide ensures Bulgarian translations maintain high quality, consistency, and cultural appropriateness. The distinction between "парола" (password) and "ключова фраза" (key phrase) is fundamental to helping users understand different security contexts. Natural phrasing, technical accuracy, and consistent terminology create a professional, trustworthy experience for Bulgarian users of Onetime Secret.
