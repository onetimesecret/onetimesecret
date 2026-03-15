# Translation Guidance for Portuguese (Portugues Europeu)

This document combines the complete glossary and language-specific translation notes for European Portuguese translations of Onetime Secret. It serves as the authoritative reference for maintaining consistency, accuracy, and natural language flow across all European Portuguese (pt-PT) content.

## Overview

This guide provides comprehensive translation standards for the Onetime Secret platform, combining:
- **Standardized terminology glossary** for consistent term usage
- **Language-specific guidelines** for European Portuguese conventions
- **Translation examples** demonstrating proper application
- **Cultural and technical considerations** specific to the pt-PT locale

## Core Translation Principles

1. **Consistency**: Use the same translation for each term throughout the application
2. **Clarity**: Prioritize clear, unambiguous language over literal translations
3. **Context**: Consider how terms are used within the application
4. **Cultural Adaptation**: Apply European Portuguese conventions and preferences
5. **Technical Precision**: Ensure security and technical terms are accurately translated
6. **Professional Tone**: Maintain a professional yet approachable voice using "tu"
7. **Natural Flow**: Write translations that sound natural to European Portuguese speakers

---

# Standardized Terminology Glossary

## Main Application Concepts

| English | Portuguese (PT) | Context | Notes |
|---------|----------------|----------|-------|
| secret (noun) | mensagem confidencial / conteudo confidencial | Core application concept | NOT "segredo" - emphasizes shared information |
| secret (adjective) | confidencial | Descriptor | NOT "secreto" |
| passphrase | frase secreta | Secret protection mechanism | Distinct from account password |
| password | palavra-passe | Account login credential | Only for account authentication; NOT "senha" |
| burn | queimar | Delete secret before viewing | Permanent deletion metaphor |
| view/reveal | ver/revelar | Access a secret | Imperative form for buttons |
| hide | ocultar | Conceal content | Imperative form for buttons |
| link | link | URL providing access | |
| encrypt/encrypted | encriptar/encriptado | Security method | NOT "criptografar" (Brazilian) |
| secure | seguro | Protection state | |

## User Interface Elements

| English | Portuguese (PT) | Context | Notes |
|---------|----------------|----------|-------|
| Share a secret | Partilhar mensagem confidencial | Primary action | NOT "Compartilhar" (Brazilian) |
| Create Account | Criar conta | Registration | |
| Sign In | Iniciar sessao | Authentication | NOT "Entrar" or "Login" |
| Sign Out | Terminar sessao | Logout action | NOT "Sair" alone |
| Dashboard | Painel | User main page | |
| Settings | Definicoes | Configuration page | NOT "Configuracoes" (Brazilian) |
| Privacy Options | Opcoes de privacidade | Secret settings | |
| Feedback | Feedback | User comments | Keep English term |
| Search | Pesquisar | Search action | European preference; NOT "buscar" (Brazilian) |
| Documentation | Documentacao | Technical docs | |

## Status Terms

| English | Portuguese (PT) | Context |
|---------|----------------|----------|
| received | recebido | Secret was viewed |
| burned | queimado | Secret deleted before viewing |
| expired | expirado | Secret no longer available due to time |
| created | criado | Secret was generated |
| active | ativo | Secret is available |
| inactive | inativo | Secret not available |

## Time-Related Terms

| English | Portuguese (PT) | Context |
|---------|----------------|----------|
| expires in | expira em | Time until secret unavailable |
| day/days | dia/dias | Time unit |
| hour/hours | hora/horas | Time unit |
| minute/minutes | minuto/minutos | Time unit |
| second/seconds | segundo/segundos | Time unit |

## Security Features

| English | Portuguese (PT) | Context |
|---------|----------------|----------|
| one-time access | acesso unico | Core security feature |
| passphrase protection | protecao por frase secreta | Additional security |
| encrypted in transit | encriptado em transito | Data protection method |
| encrypted at rest | encriptado em repouso | Storage protection |

## Account-Related Terms

| English | Portuguese (PT) | Context |
|---------|----------------|----------|
| email | e-mail | User identifier |
| password | palavra-passe | Authentication |
| account | conta | User profile |
| subscription | subscrição | Paid service |
| customer | cliente | Paying user |

## Domain-Related Terms

| English | Portuguese (PT) | Context |
|---------|----------------|----------|
| custom domain | dominio personalizado | Premium feature |
| domain verification | verificacao de dominio | Setup process |
| DNS record | registo DNS | Configuration |
| CNAME record | registo CNAME | DNS configuration |

## Error Messages

| English | Portuguese (PT) | Context |
|---------|----------------|----------|
| error | erro | Problem notification |
| warning | aviso | Caution notification |
| oops | ops | Friendly error introduction |

## Buttons and Actions

| English | Portuguese (PT) | Context | Notes |
|---------|----------------|----------|-------|
| submit | enviar | Submit action | Imperative voice |
| cancel | cancelar | Negative action | Imperative voice |
| confirm | confirmar | Positive action | Imperative voice |
| copy to clipboard | copiar para a area de transferencia | Utility action | |
| continue | continuar | Navigation | Imperative voice |
| back | voltar | Navigation | Imperative voice |

## Marketing Terms

| English | Portuguese (PT) | Context |
|---------|----------------|----------|
| secure links | links seguros | Product feature |
| privacy-first design | design com privacidade em primeiro lugar | Design philosophy |
| custom branding | marca personalizada | Premium feature |

## Technical Terms to Keep in English

Maintain these terms in English for technical precision:
- API
- URL
- DNS
- SSL/TLS
- HTTP/HTTPS
- JSON
- YAML
- hash
- Keys ending in `_literal` (e.g., `onetime_secret_literal`) contain brand names that must remain in English exactly as-is

---

# Language-Specific Guidelines

## Critical Terminology Distinctions

### 1. Secret vs Segredo

**CRITICAL:** The term "secret" is central to the application and must be translated consistently.

Use **"mensagem confidencial"** (confidential message) or **"conteudo confidencial"** (confidential content) instead of "segredo" to avoid implications of personal secrets.

- **"confidencial"** as adjective, NOT "secreto"

CORRECT:
- "Criar mensagem confidencial"
- "Ver conteudo confidencial"
- "3 novas mensagens confidenciais"

INCORRECT:
- "Criar segredo" (implies personal secret)
- "Ver segredo"
- "3 novos segredos"

### 2. Password vs Passphrase

**CRITICAL:** Distinguish clearly between these two concepts.

- **Palavra-passe**: ONLY for account login (NOT "senha", which is Brazilian)
- **Frase secreta**: ONLY for protecting individual secrets

CORRECT:
- "Introduz a tua palavra-passe para iniciar sessao" (Enter your password to log in)
- "Protege com uma frase secreta" (Protect with a passphrase)
- `enter-a-passphrase`: **"Introduz uma frase secreta"**

INCORRECT:
- Using "palavra-passe" for both concepts
- Using "senha" (Brazilian term)

## European vs Brazilian Portuguese

**CRITICAL:** This translation uses European Portuguese (pt-PT) conventions, NOT Brazilian Portuguese (pt-BR).

### Key Differences

| Aspect | European (pt-PT) | Brazilian (pt-BR) |
|--------|-------------------|-------------------|
| Password | palavra-passe | senha |
| Search verb | pesquisar | buscar |
| Informal you | tu | voce |
| Share | partilhar | compartilhar |
| Settings | definicoes | configuracoes |
| Encrypt | encriptar | criptografar |
| Sign in | iniciar sessao | entrar |
| DNS record | registo | registro |
| Progressive | a + infinitive | gerund (-ndo) |

### Progressive/Continuous Forms

European Portuguese uses **"a + infinitive"** construction, NOT the gerund.

CORRECT (European):
- "A mostrar resultados" (Showing results)
- "A pesquisar" (Searching)
- "A carregar" (Loading)

INCORRECT (Brazilian):
- "Mostrando resultados"
- "Buscando"
- "Carregando"

**Use the European "a + infinitive" style throughout all UI text.**

## Formality and Tone

### Use "Tu" (Informal You)

European Portuguese tech products use **"tu"** for an approachable tone. Use tu-form verb conjugations and possessives consistently.

**Tu-form conjugation patterns:**
- Imperative: "Introduz", "Partilha", "Cria", "Protege", "Faz"
- Possessives: "tua", "teu", "tuas", "teus"
- Pronouns: "tu", "te", "-te"
- Present indicative: "podes", "tens", "queres", "deves"

**Examples:**
- "O teu recurso central" (Your central resource)
- "Consulta a nossa documentacao" (Check our documentation)
- "Se tiveres duvidas" (If you have questions)
- "Bem-vindo ao painel" (Welcome to your dashboard)

**DO NOT MIX REGISTERS.** Every string must use tu-form consistently. Never use "voce", "sua/seu" (voce-form), "Introduza", "Proteja", "Faca" (voce-form imperatives) in the same locale.

| Register | Tu-form (CORRECT) | Voce-form (INCORRECT) |
|----------|-------------------|----------------------|
| Imperative | Introduz, Partilha, Cria | Introduza, Partilhe, Crie |
| Possessive | tua, teu | sua, seu |
| Present | podes, tens | pode, tem |
| Pronoun | tu, te | voce |

### Voice Consistency

**For Actions (Buttons, Commands):**
Use active, imperative voice (tu-form):
- **"Ocultar"** (Hide)
- **"Ver"** (View)
- **"Enviar"** (Submit)
- **"Cancelar"** (Cancel)

**For Informational Text (Status, Descriptions):**
Use declarative/passive voice:
- "A mensagem foi visualizada" (The message was viewed)
- "Conteudo encriptado em repouso" (Content encrypted at rest)
- "Protecao por frase secreta aplicada" (Passphrase protection applied)

## Clarity and Conciseness

### Standard Abbreviations

Use standard European Portuguese abbreviations:

| English | Portuguese (PT) | Notes |
|---------|----------------|-------|
| e.g. | p. ex. | Standard European abbreviation |
| i.e. | isto e / ou seja | Spelled out for clarity |
| etc. | etc. | Same as English |

### Natural Language Flow

Write for European Portuguese speakers, not literal English translations.

GOOD (Natural European Portuguese):
```
"Bem-vindo ao Onetime Secret Docs, o teu recurso central para
tirares o maximo partido do nosso servico de partilha de
mensagens confidenciais efemeras e focado em privacidade."
```

This uses:
- Natural sentence structure
- Professional tone with "tu/teu"
- European vocabulary ("partilha", not "compartilhamento")
- No gerund constructions

BAD (Brazilian Portuguese or mixed):
```
"Bem-vindo ao Onetime Secret Docs, seu recurso central para
maximizar o valor do nosso servico de compartilhamento de
mensagens confidenciais..."
```

## Link Localization

**CRITICAL:** All internal documentation links must use the `/pt-pt/` prefix.

### Correct Link Format

```markdown
CORRECT: [documentacao](/pt-pt/docs-overview)
CORRECT: [primeiros passos](/pt-pt/introduction)
CORRECT: [seguranca](/pt-pt/security/best-practices)

WRONG: [documentacao](/pt/docs-overview)     # Wrong locale code
WRONG: [documentacao](/pt-br/docs-overview)  # Wrong variant
WRONG: [documentacao](docs-overview)         # Missing locale prefix
```

**Note:** The locale code uses a hyphen: `pt-pt` (NOT `pt_pt` or `ptpt`)

### External Links

External links to onetimesecret.com should remain as-is:

```markdown
CORRECT: [contactar](https://onetimesecret.com/feedback)
CORRECT: [criar conta](https://onetimesecret.com/signup)
```

---

# Translation Examples and Best Practices

## Example Transformations

### Creating Secrets

**Before:** "Criar um Segredo"
**After:** **"Criar Mensagem Confidencial"**
**Reasoning:** Emphasizes the nature of shared information, not personal secrets

### Viewing Content

**Before:** "Ver conteudo secreto"
**After:** **"Ver conteudo confidencial"**
**Reasoning:** Uses correct terminology; "confidencial" not "secreto"

### Passphrase Protection

**Before:** "Introduz uma senha" (Brazilian term)
**After:** **"Introduz uma frase secreta"**
**Reasoning:** Uses European "palavra-passe" for passwords, "frase secreta" for passphrases

### Settings Reference

**Before:** "Configuracoes" (Brazilian)
**After:** **"Definicoes"**
**Reasoning:** European Portuguese standard term

## Complete UI Example

**Welcome Screen (Good Translation):**
```
Bem-vindo ao Onetime Secret

Partilha mensagens confidenciais de forma segura com links de acesso unico.

[Criar Mensagem Confidencial]
[Iniciar Sessao]
[Ver Documentacao]

Os teus dados sao encriptados em transito e em repouso.
```

This demonstrates:
- Correct use of "mensagem confidencial"
- Imperative verbs on buttons
- "tu" tone ("Os teus dados")
- European terminology ("partilha", "encriptados", "Iniciar Sessao")
- No gerund constructions

---

# Summary of Translation Goals

The European Portuguese translation aims to:

1. **Ensure Consistency:** Use standardized terminology for core concepts like `secret` -> `mensagem confidencial` and `passphrase` -> `frase secreta`

2. **Maintain Clarity:** Distinguish clearly between similar concepts (palavra-passe vs frase secreta, mensagem confidencial vs segredo)

3. **Follow European Conventions:** Use European Portuguese vocabulary, "a + infinitive" progressive forms, and "tu" register

4. **Apply Correct Voice:** Imperative (tu-form) for actions, declarative for information

5. **Achieve Natural Flow:** Write translations that sound natural to European Portuguese speakers

6. **Ensure Technical Accuracy:** Translate security and technical terms precisely using European conventions (encriptar, not criptografar)

7. **Maintain Professional Approachability:** Professional tone while remaining accessible and user-friendly

---

# Quick Reference Checklist

When translating Onetime Secret content to European Portuguese:

- [ ] Use "mensagem confidencial" or "conteudo confidencial" for "secret" (noun)
- [ ] Use "confidencial" for "secret" (adjective), NOT "secreto"
- [ ] Use "frase secreta" for "passphrase"
- [ ] Use "palavra-passe" for account passwords, NOT "senha"
- [ ] Use "tu" register consistently (tua/teu, Introduz/Partilha/Cria)
- [ ] NEVER mix tu-form and voce-form in the same locale
- [ ] Use "a + infinitive" for progressive actions, NOT gerund (-ndo)
- [ ] Use European vocabulary (partilhar, definicoes, pesquisar, encriptar)
- [ ] Use imperative voice (tu-form) for buttons and commands
- [ ] Use declarative voice for status and informational text
- [ ] Keep technical terms (API, DNS, SSL) in English
- [ ] Use `/pt-pt/` prefix for all internal documentation links
- [ ] Use "Iniciar sessao" for "Sign In"
- [ ] Use "Terminar sessao" for "Sign Out"
- [ ] Use "Definicoes" for "Settings"
- [ ] Use "Documentacao" for technical documentation
- [ ] Write for natural European Portuguese flow, not literal translations

---

**Document Version:** 1.0
**Created:** 2025
**For Use With:** Onetime Secret translation projects
**Locale:** pt-PT (Portuguese - Portugal)
