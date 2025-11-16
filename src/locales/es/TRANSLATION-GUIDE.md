# Translation Guidance for Spanish (Español)

This document combines the glossary of standardized terms and language-specific translation notes for Spanish translations of Onetime Secret. It serves as a comprehensive reference for translators working on the Spanish locale to ensure consistency, accuracy, and natural phrasing.

## Overview

The Spanish translation aims to:
- Maintain consistency across all application interfaces
- Use clear, natural phrasing for Spanish-speaking audiences
- Follow technical accuracy for security-related terminology
- Apply appropriate voice and tone for different contexts
- Distinguish between neutral Spanish where possible while remaining accessible

---

## Core Terminology

### Basic Terms

| English | Español (ES) | Context | Notes |
|---------|-------------|---------|-------|
| secret (noun) | secreto | Central application concept | Emphasizes the confidential item being shared |
| secret (adj) | secreto/seguro | Descriptive use | |
| passphrase | frase de contraseña | Authentication method for secrets | Compound term distinguishing from account password |
| password | contraseña | Account login credential | Standard term for account passwords |
| burn | destruir | Action to delete a secret before viewing | Consistently use verb/past participle forms |
| view/reveal | ver/mostrar | Action to access a secret | |
| link | enlace | URL providing access to a secret | |
| encrypt/encrypted | cifrar/cifrado | Security method | |
| secure | seguro | Protection state | |

### User Interface Elements

| English | Español (ES) | Context | Notes |
|---------|-------------|---------|-------|
| Share a secret | Compartir un secreto | Primary action | |
| Create Account | Crear una cuenta | Registration | |
| Sign In | Iniciar sesión | Authentication | Very common term for logging in |
| Dashboard | Panel | User's main page | More accurate than "Cuenta" for this context |
| Settings | Configuración | Configuration page | |
| Privacy Options | Opciones de privacidad | Secret configuration | |
| Feedback | Comentarios | User feedback | |

### Status Terms

| English | Español (ES) | Context | Notes |
|---------|-------------|---------|-------|
| received | recibido | Secret has been viewed | |
| burned | destruido | Secret was deleted before viewing | Standardized form |
| expired | expirado | Secret no longer available due to time | |
| created | creado | Secret has been generated | |
| active | activo | Secret is available | |
| inactive | inactivo | Secret is not available | |

### Time-Related Terms

| English | Español (ES) | Context |
|---------|-------------|---------|
| expires in | expira en | Time until secret becomes unavailable |
| day/days | día/días | Time unit |
| hour/hours | hora/horas | Time unit |
| minute/minutes | minuto/minutos | Time unit |
| second/seconds | segundo/segundos | Time unit |

### Security Features

| English | Español (ES) | Context |
|---------|-------------|---------|
| one-time access | acceso único | Core security feature |
| passphrase protection | protección mediante frase de contraseña | Additional security |
| encrypted in transit | cifrado en tránsito | Data protection method |
| encrypted at rest | cifrado en reposo | Storage protection |

### Account-Related Terms

| English | Español (ES) | Context |
|---------|-------------|---------|
| email | correo electrónico | User identifier |
| password | contraseña | Account authentication |
| account | cuenta | User profile |
| subscription | suscripción | Paid service |
| customer | cliente | Paying user |

### Domain-Related Terms

| English | Español (ES) | Context |
|---------|-------------|---------|
| custom domain | dominio personalizado | Premium feature |
| domain verification | verificación del dominio | Setup process |
| DNS record | registro DNS | Configuration |
| CNAME record | registro CNAME | DNS configuration |

### Error Messages

| English | Español (ES) | Context |
|---------|-------------|---------|
| error | error | Problem notification |
| warning | advertencia | Caution notification |
| oops | ups | Friendly error introduction |

### Buttons and Actions

| English | Español (ES) | Context | Notes |
|---------|-------------|---------|-------|
| submit | enviar | Form action | |
| cancel | cancelar | Negative action | |
| confirm | confirmar | Positive action | |
| copy to clipboard | copiar al portapapeles | Utility action | Standard Spanish phrase |
| continue | continuar | Navigation | |
| back | atrás | Navigation | |

### Marketing Terms

| English | Español (ES) | Context |
|---------|-------------|---------|
| secure links | enlaces seguros | Product feature |
| privacy-first design | diseño que prioriza la privacidad | Design philosophy |
| custom branding | marca personalizada | Premium feature |

---

## Translation Guidelines

### 1. Consistency

- Use the same translation for a term throughout the application
- Maintain standardized terminology from the glossary above
- Key distinctions to preserve:
  - `contraseña` for account passwords
  - `frase de contraseña` for secret protection
  - `secreto` as the core concept

### 2. Context Awareness

- Consider how the term is used in the application
- Account for surrounding UI elements and user flow
- Ensure translations make sense in their specific context

### 3. Cultural Adaptation

- Adapt terms to local conventions when necessary
- Aim for neutral Spanish that works across regions
- Use standard technical terms familiar to Spanish-speaking users

### 4. Technical Accuracy

- Security-related terms must be translated accurately
- Prioritize precision over localization for technical terminology
- Use established Spanish technical vocabulary

### 5. Voice and Tone

#### Imperative Voice (for Actions)
Use imperative voice for buttons, links, and user actions:
- `Generar Contraseña` (Generate Password)
- `Copiar al portapapeles` (Copy to clipboard)
- `Crear una cuenta` (Create Account)

#### Passive/Declarative Voice (for Information)
Use passive or declarative voice for informational text, status messages, and descriptions:
- `Tu mensaje seguro se muestra a continuación.` (Your secure message is shown below.)
- `El enlace secreto ha sido creado...` (The secret link has been created...)
- `El secreto fue destruido manualmente...` (The secret was manually destroyed...)
- `Estás viendo...` (You are viewing...)

### 6. Direct Address

- Use informal "tú" form consistently when addressing users
- Examples:
  - `Introduce tu contraseña` (Enter your password)
  - `Tu mensaje seguro` (Your secure message)
  - `Estás viendo...` (You are viewing...)
- When direct address can be avoided, use 3rd person passive:
  - `Se notificará...` (Will be notified...)

### 7. Clarity and Natural Phrasing

- Prioritize natural Spanish expressions over literal translations
- Use standard phrases familiar to Spanish speakers:
  - `Preguntas Frecuentes` instead of `F.A.Q.`
  - `Cargando...` for loading states
  - `Recuérdame` for "Remember me" checkboxes

### 8. Completeness

- Ensure all user-facing strings are translated
- Avoid leaving English text in the interface
- Translate help text, descriptions, and metadata

---

## Common Translation Patterns

### User Instructions
Use imperative or infinitive forms:
- `Introduce tu contraseña` (Enter your password)
- `Copiar al portapapeles` (Copy to clipboard)

### Status Descriptions
Use passive voice or past participles:
- `Copiado al portapapeles` (Copied to clipboard)
- `El secreto ha sido creado` (The secret has been created)

### Help Text and Descriptions
Use declarative sentences in 2nd person informal:
- `Estás viendo el contenido secreto` (You are viewing the secret content)
- `Este contenido se muestra solo una vez` (This content is shown only once)

### Error Messages
Use clear, direct language:
- `Frase de contraseña incorrecta` (Incorrect passphrase)
- `Ha ocurrido un error` (An error has occurred)

---

## Special Considerations

### The Term "Secret"
- Fundamental to the application - translate consistently as `secreto`
- Emphasizes the confidential nature of the shared item
- Distinguishes from personal secrets or confidential information in general

### Password vs. Passphrase
Critical distinction:
- **`contraseña`** - for user account login credentials
- **`frase de contraseña`** - for protecting individual secrets

This distinction must be maintained throughout the application to avoid confusion.

### UI Element Conventions
- Follow platform conventions for the target language
- Use standard Spanish terminology for common UI elements
- Maintain consistency with other Spanish applications

### Technical Security Terms
- Prioritize accuracy over casual localization
- Use established Spanish technical vocabulary
- Examples:
  - `cifrado` (encrypted)
  - `cifrar` (to encrypt)
  - `verificación` (verification)
  - `autenticación` (authentication)

---

## Summary of Translation Principles

The Spanish translation maintains:

1. **Terminology Consistency** - Standardized key terms throughout the application
2. **Appropriate Voice** - Imperative for actions, passive/declarative for information
3. **Natural Phrasing** - Standard Spanish expressions and idioms
4. **Consistent Address** - Informal "tú" form when addressing users
5. **Complete Coverage** - All user-facing strings translated
6. **Technical Accuracy** - Precise terminology for security concepts
7. **Clear Distinctions** - Especially between account passwords and secret passphrases

By following these guidelines, translators can ensure that the Spanish version of Onetime Secret is accurate, consistent, and provides a natural user experience for Spanish-speaking audiences.
