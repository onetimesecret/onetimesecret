---
title: Guida alla traduzione per l'italiano
description: Guida completa per tradurre Onetime Secret in italiano, che combina glossario e note linguistiche
---

# Translation Guidance for Italian (Italiano)

This document combines the Onetime Secret glossary and Italian-specific language notes to provide comprehensive translation guidance for Italian localizations. It is designed to ensure consistency, accuracy, and cultural appropriateness across all Italian translations of the Onetime Secret platform.

## Introduction

This guide serves two primary purposes:

1. **Glossary**: Standardized translations of key terms to maintain consistency across the application
2. **Language-Specific Notes**: Italian-specific translation decisions, reasoning, and best practices

All translations should follow these guidelines to ensure a cohesive user experience that respects both the technical requirements and cultural expectations of Italian-speaking users.

---

## Core Translation Principles

### 1. Authenticity
- Use natural Italian phrasing while maintaining technical precision
- Avoid overly literal translations that sound awkward in Italian
- Respect Italian grammatical conventions and sentence structure

### 2. Efficiency
- Use clear, direct language that respects users' time
- Prefer concise button text and UI labels
- Remove unnecessary words without sacrificing clarity

### 3. Consistency
- Use the same translation for a term throughout the application
- Maintain the distinction between technical concepts (e.g., password vs. passphrase)
- Follow established terminology standards

### 4. Context Awareness
- Consider how terms are used in the application
- Use imperative voice for actions, declarative for status messages
- Adapt tone based on context (buttons vs. descriptions)

### 5. Cultural Adaptation
- Adapt terms to Italian conventions when appropriate
- Ensure accessibility labels are descriptive and clear
- Maintain professional yet approachable tone

---

## Core Terminology Standards

### Critical Distinction: Password vs. Passphrase

**IMPORTANT:** Onetime Secret makes a crucial distinction between two security concepts that MUST be maintained in all translations:

#### Password (Password)
- **Definition**: Standard credential for account authentication
- **Context**: Used exclusively for user account login on the Onetime Secret platform
- **Italian Translation**: "password"
- **Examples**:
  - "Password account"
  - "Password di login"
  - "Reimposta password"

#### Passphrase (Frase di Sicurezza)
- **Definition**: Specific security measure to protect individual secrets
- **Context**: Used when creating or accessing protected secrets (NOT for account login)
- **Italian Translation**: "frase di sicurezza"
- **Examples**:
  - "Proteggi con frase di sicurezza"
  - "Inserisci la frase di sicurezza per visualizzare"
  - "Segreto protetto da frase di sicurezza"

#### Maintaining the Distinction

✅ **Correct Approach:**
- Account section: "Inserisci la tua **password** per accedere"
- Secrets section: "Questo segreto è protetto con una **frase di sicurezza**"

❌ **Incorrect Approach:**
- Using the same term for both concepts
- Inconsistently alternating between terms

### Using "Segreto" (Secret) Correctly

**Core Principle:**
The term "secret" is central to the Onetime Secret brand and must be translated to maintain the context of confidentiality. Unlike some languages where equivalent terms carry problematic connotations, Italian "segreto" appropriately conveys confidential information.

**Correct Italian Usage:**
- `secret (noun)` → `segreto` (confidential information)
- `secret (adjective)` → `segreto/sécurisé` (describing protected content)
- `secret links` → `Link Segreti` (maintains confidentiality context)
- `create secrets` → `Crea Segreti` (NOT "Crea Messaggio")
- `retrieve secrets` → `Recupera Segreti` (NOT "Recupera Messaggio")

**Why "Segreto" Works for Italian:**
Italian "segreto" naturally encompasses:
- Confidential business information
- Professional secrets
- Protected data
- Secure communications

**Alternatives to Avoid:**
- "Messaggio" (message) - too generic, loses security context
- "Monouso" (single-use) - describes mechanism, not content
- "Temporaneo" (temporary) - describes duration, not confidentiality

---

## Standardized Terminology

### Basic Terminology

| Italian | English | German (AT) | French (FR) | French (CA) | Context |
|---------|---------|-------------|-------------|-------------|---------|
| segreto (sostantivo) | secret | Geheimnis | secret | secret | Core application concept |
| segreto (aggettivo) | secret | geheim | secret/sécurisé | secret/sécurisé | Describing confidential content |
| frase di sicurezza | passphrase | Sicherheitsphrase | phrase secrète | mot de passe | Secret protection (distinct from account password) |
| password | password | Passwort | mot de passe | mot de passe | User account authentication |
| distruggere/bruciare | burn | verbrennen | supprimer | supprimer | Delete secret before viewing |
| visualizzare/rivelare | view/reveal | ansehen/anzeigen | consulter/afficher | consulter/afficher | Access a secret |
| link/collegamento | link | Link/Verbindung | lien | lien | URL to access a secret |
| crittografare/crittografato | encrypt/encrypted | verschlüsseln/verschlüsselt | chiffrer/chiffré | chiffrer/chiffré | Security method |
| sicuro | secure | sicher | sécurisé | sécurisé | Protection state |

### User Interface Elements

| Italian | English | German (AT) | French (FR) | French (CA) | Context |
|---------|---------|-------------|-------------|-------------|---------|
| Condividi un segreto | Share a secret | Ein Geheimnis teilen | Partager un secret | Partager un secret | Primary action |
| Crea account | Create Account | Konto erstellen | Créer un compte | Créer un compte | Registration |
| Accedi | Sign In | Eintragen | Se connecter | Se connecter | Authentication |
| Dashboard/Pannello | Dashboard | Konto | Tableau de bord | Compte | User main page |
| Impostazioni | Settings | Einstellungen | Paramètres | Paramètres | Configuration page |
| Opzioni di privacy | Privacy Options | Datenschutz-Optionen | Options de confidentialité | Options de confidentialité | Privacy settings |
| Feedback | Feedback | Rückmeldung | Retour d'information | Retour d'information | User feedback |

### Status Conditions

| Italian | English | German (AT) | French (FR) | French (CA) | Context |
|---------|---------|-------------|-------------|-------------|---------|
| ricevuto | received | empfangen | reçu | reçu | Secret has been viewed |
| bruciato/distrutto | burned | verbrannt | supprimé | supprimé | Secret deleted before viewing |
| scaduto | expired | abgelaufen | expiré | expiré | Secret no longer available (time expired) |
| creato | created | erstellt | créé | créé | Secret was generated |
| attivo | active | aktiv | actif | actif | Secret is available |
| inattivo | inactive | inaktiv | inactif | inactif | Secret is unavailable |

### Time-Related Terms

| Italian | English | German (AT) | French (FR) | French (CA) | Context |
|---------|---------|-------------|-------------|-------------|---------|
| scade tra | expires in | läuft ab in | expire dans | expire dans | Time remaining before expiration |
| giorno/giorni | day/days | Tag/Tage | jour/jours | jour/jours | Time unit |
| ora/ore | hour/hours | Stunde/Stunden | heure/heures | heure/heures | Time unit |
| minuto/minuti | minute/minutes | Minute/Minuten | minute/minutes | minute/minutes | Time unit |
| secondo/secondi | second/seconds | Sekunde/Sekunden | seconde/secondes | seconde/secondes | Time unit |

### Security Features

| Italian | English | German (AT) | French (FR) | French (CA) | Context |
|---------|---------|-------------|-------------|-------------|---------|
| accesso una tantum | one-time access | einmaliger Zugang | accès unique | accès unique | Core security feature |
| protezione con frase di sicurezza | passphrase protection | Schutz durch Sicherheitsphrase | protection par phrase secrète | protection par phrase d'authentification | Additional secret security |
| crittografato in transito | encrypted in transit | verschlüsselt bei der Übertragung | chiffré en transit | chiffré en transit | Protection during transmission |
| crittografato a riposo | encrypted at rest | verschlüsselt im Ruhezustand | chiffré au repos | chiffré au repos | Protection during storage |

### Account-Related Terms

| Italian | English | German (AT) | French (FR) | French (CA) | Context |
|---------|---------|-------------|-------------|-------------|---------|
| email | email | E-Mail | courriel/e-mail | courriel | User identifier |
| password | password | Passwort | mot de passe | mot de passe | Account authentication (distinct from passphrase) |
| account | account | Konto | compte | compte | User profile |
| abbonamento | subscription | Abonnement | abonnement | abonnement | Paid service |
| cliente | customer | Kunde | client | client | Paying user |

### Domain-Related Terms

| Italian | English | German (AT) | French (FR) | French (CA) | Context |
|---------|---------|-------------|-------------|-------------|---------|
| dominio personalizzato | custom domain | benutzerdefinierter Bereich | domaine personnalisé | domaine personnalisé | Premium feature |
| verifica del dominio | domain verification | Domänenüberprüfung | vérification du domaine | vérification du domaine | Setup process |
| record DNS | DNS record | Namensserver-Eintrag | enregistrement DNS | enregistrement DNS | DNS configuration |
| record CNAME | CNAME record | CNAME-Eintrag | enregistrement CNAME | enregistrement CNAME | Specific DNS configuration |

### Error Messages

| Italian | English | German (AT) | French (FR) | French (CA) | Context |
|---------|---------|-------------|-------------|-------------|---------|
| errore | error | Fehler | erreur | bug | Problem notification |
| avviso | warning | Warnung | avertissement | attention | Caution notification |
| ops | oops | Huch | oups | oups | Friendly error introduction |

### Buttons and Actions

| Italian | English | German (AT) | French (FR) | French (CA) | Context |
|---------|---------|-------------|-------------|-------------|---------|
| invia | submit | einreichen | soumettre | soumettre | Form action |
| annulla | cancel | abbrechen | annuler | annuler | Negative action |
| conferma | confirm | bestätigen | confirmer | confirmer | Positive action |
| copia negli appunti | copy to clipboard | in die Zwischenablage kopieren | copier dans le presse-papiers | copier dans le presse-papiers | Utility action |
| continua | continue | weiter | continuer | continuer | Forward navigation |
| indietro | back | zurück | retour | retour | Backward navigation |

### Marketing Terms

| Italian | English | German (AT) | French (FR) | French (CA) | Context |
|---------|---------|-------------|-------------|-------------|---------|
| link sicuri | secure links | sichere Links | liens sécurisés | liens sécurisés | Product feature |
| design incentrato sulla privacy | privacy-first design | Datenschutz als oberstes Gebot | conception privilégiant la protection de la vie privée | conception privilégiant la protection de la vie privée | Design philosophy |
| branding personalizzato | custom branding | benutzerdefiniertes Branding | image de marque personnalisée | image de marque personnalisée | Premium feature |

---

## Voice and Tone Guidelines

### Voice Consistency Based on Context

Use the appropriate voice based on the element type:

**Active/Imperative Voice** (for user actions):
- "Inizia" (Start)
- "Modifica" (Edit)
- "Copia" (Copy)
- "Crea" (Create)
- "Elimina" (Delete)

**Passive/Declarative Voice** (for status messages):
- "Copiato" (Copied)
- "Ultimo aggiornamento" (Last updated)
- "Creato" (Created)
- "Eliminato" (Deleted)

### UI Text Simplification

Prioritize efficiency without sacrificing quality:

**Simplified Examples:**
- "Per Iniziare" → "Inizia" (use imperative for actions)
- "Modifica pagina" → "Modifica" (concise button text)
- "Carica altri risultati" → "Altri risultati" (shorter, clearer)
- "Copia negli appunti" → "Copia" (tooltips can be brief)

**Punctuation Guidelines:**
- Remove exclamation marks from UI text
- "Copiato!" → "Copiato" (no exclamation)
- Use periods sparingly in short UI text
- Full sentences in descriptions should have proper punctuation

---

## Italian-Specific Adaptations

### Cultural Considerations

1. **Professional Yet Approachable Tone**
   - Maintain warmth while being concise
   - Avoid overly formal language that creates distance
   - Use standard Italian, not regional dialects

2. **Technical Precision**
   - Preserve technical accuracy for security-related terms
   - Keep English terms when they're standard in Italian IT contexts (API, REST, DNS)
   - Translate user-facing features into natural Italian

3. **Accessibility**
   - Use descriptive labels for screen readers
   - "Main" → "Navigazione principale" (more descriptive)
   - Ensure ARIA labels are clear and functional

### Common UI Patterns

**Navigation:**
- Getting Started: "Inizia"
- Next: "Avanti"
- Back: "Indietro"
- Continue: "Continua"

**Forms:**
- Submit: "Invia"
- Cancel: "Annulla"
- Confirm: "Conferma"
- Reset: "Reimposta"

**Status Messages:**
- Success: "Operazione completata"
- Error: "Si è verificato un errore"
- Warning: "Attenzione"
- Info: "Informazione"

---

## Translation Best Practices

### 1. Maintain Brand Identity
- Keep "Onetime Secret" untranslated
- Preserve product names (Starlight, etc.)
- Use consistent branding terminology

### 2. Ensure Technical Accuracy
- Security terms must be precise
- Maintain distinction between similar concepts
- Verify technical terminology with Italian IT standards

### 3. Respect Regional Variations
- Use standard Italian (italiano standard)
- Avoid region-specific colloquialisms
- When in doubt, use neutral terminology

### 4. Follow Platform Conventions
- Respect Italian UI conventions
- Use standard Italian date/time formats
- Follow Italian capitalization rules for UI elements

### 5. Test for Natural Flow
- Read translations aloud to check naturalness
- Ensure sentence structure follows Italian grammar
- Verify that translations fit UI space constraints

---

## Examples of Applied Principles

### Example 1: Secret Creation Flow

**English:**
- "Create a Secret"
- "Add a passphrase for extra security"
- "Share this link securely"

**Italian (Correct):**
- "Crea un Segreto"
- "Aggiungi una frase di sicurezza per maggiore protezione"
- "Condividi questo link in modo sicuro"

### Example 2: Account vs. Secret Security

**English:**
- "Enter your password to sign in" (account)
- "This secret requires a passphrase" (secret)

**Italian (Correct):**
- "Inserisci la tua password per accedere" (account)
- "Questo segreto richiede una frase di sicurezza" (segreto)

### Example 3: Status Messages

**English:**
- "Secret created successfully!"
- "Copied to clipboard"
- "Secret has been viewed"

**Italian (Correct):**
- "Segreto creato con successo" (no exclamation)
- "Copiato" (concise status)
- "Il segreto è stato visualizzato" (declarative)

---

## Quality Assurance Checklist

Before finalizing any Italian translation, verify:

- [ ] Password/passphrase distinction is maintained
- [ ] "Segreto" used consistently for secrets
- [ ] Voice matches context (imperative for actions, declarative for status)
- [ ] Exclamation marks removed from UI text
- [ ] Technical terms are accurate
- [ ] Brand names remain untranslated
- [ ] Text fits within UI constraints
- [ ] Natural Italian phrasing maintained
- [ ] Accessibility labels are descriptive
- [ ] Consistency with established glossary

---

## Revision History

This guide should be updated when:
- New features require new terminology
- User feedback indicates confusion
- Platform conventions change
- Additional languages provide useful insights

**Last Updated:** 2025-11-16
**Version:** 1.0
**Maintained By:** Onetime Secret Translation Team
