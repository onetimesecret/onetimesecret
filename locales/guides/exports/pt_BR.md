---
title: Guia de tradução para português brasileiro
description: Guia completo para traduzir o Onetime Secret para português brasileiro, combinando glossário e notas linguísticas
---

# Translation Guidance for Portuguese (Português Brasileiro)

This document combines the complete glossary and language-specific translation notes for Portuguese (Brazilian) translations of Onetime Secret. It serves as the authoritative reference for maintaining consistency, accuracy, and natural language flow across all Portuguese (Brazilian) content.

## Overview

This guide provides comprehensive translation standards for the Onetime Secret platform, combining:
- **Standardized terminology glossary** for consistent term usage
- **Language-specific guidelines** for Brazilian Portuguese conventions
- **Translation examples** demonstrating proper application
- **Cultural and technical considerations** specific to the pt-BR locale

## Core Translation Principles

1. **Consistency**: Use the same translation for each term throughout the application
2. **Clarity**: Prioritize clear, unambiguous language over literal translations
3. **Context**: Consider how terms are used within the application
4. **Cultural Adaptation**: Apply Brazilian Portuguese conventions and preferences
5. **Technical Precision**: Ensure security and technical terms are accurately translated
6. **Professional Tone**: Maintain a professional yet approachable voice using "você"
7. **Natural Flow**: Write translations that sound natural to Brazilian Portuguese speakers

---

# Standardized Terminology Glossary

## Main Application Concepts

| English | Portuguese (BR) | Context | Notes |
|---------|----------------|----------|-------|
| secret (noun) | mensagem confidencial / conteúdo confidencial | Core application concept | NOT "segredo" - emphasizes shared information |
| secret (adjective) | confidencial / secreto | Descriptor | |
| passphrase | frase secreta | Secret protection mechanism | Distinct from account password |
| password | senha | Account login credential | Only for account authentication |
| burn | queimar | Delete secret before viewing | Permanent deletion metaphor |
| view/reveal | visualizar/exibir | Access a secret | Imperative form for buttons |
| hide | ocultar | Conceal content | Imperative form for buttons |
| link | link | URL providing access | |
| encrypt/encrypted | criptografar/criptografado | Security method | NOT "encriptar" |
| secure | seguro | Protection state | |

## User Interface Elements

| English | Portuguese (BR) | Context | Notes |
|---------|----------------|----------|-------|
| Share a secret | Compartilhar mensagem confidencial | Primary action | |
| Create Account | Criar conta | Registration | |
| Sign In | Entrar | Authentication | NOT "Login" or "Logar" |
| Sign Out | Sair | Logout action | NOT "Logout" |
| Dashboard | Painel | User main page | Translated, not loanword |
| Settings | Configurações | Configuration page | NOT "Ajustes" or "Opções" |
| Privacy Options | Opções de privacidade | Secret settings | |
| Feedback | Feedback | User comments | Keep English term |
| Search | Buscar | Search action | Brazilian preference, NOT "pesquisar" |
| Documentation | Documentação | Technical docs | NOT "Documentos" |

## Status Terms

| English | Portuguese (BR) | Context |
|---------|----------------|----------|
| received | recebido | Secret was viewed |
| burned | queimado | Secret deleted before viewing |
| expired | expirado | Secret no longer available due to time |
| created | criado | Secret was generated |
| active | ativo | Secret is available |
| inactive | inativo | Secret not available |

## Time-Related Terms

| English | Portuguese (BR) | Context |
|---------|----------------|----------|
| expires in | expira em | Time until secret unavailable |
| day/days | dia/dias | Time unit |
| hour/hours | hora/horas | Time unit |
| minute/minutes | minuto/minutos | Time unit |
| second/seconds | segundo/segundos | Time unit |

## Security Features

| English | Portuguese (BR) | Context |
|---------|----------------|----------|
| one-time access | acesso único | Core security feature |
| passphrase protection | proteção por frase secreta | Additional security |
| encrypted in transit | criptografado em trânsito | Data protection method |
| encrypted at rest | criptografado em repouso | Storage protection |

## Account-Related Terms

| English | Portuguese (BR) | Context |
|---------|----------------|----------|
| email | e-mail | User identifier |
| password | senha | Authentication |
| account | conta | User profile |
| subscription | assinatura | Paid service |
| customer | cliente | Paying user |

## Domain-Related Terms

| English | Portuguese (BR) | Context |
|---------|----------------|----------|
| custom domain | domínio personalizado | Premium feature |
| domain verification | verificação de domínio | Setup process |
| DNS record | registro DNS | Configuration |
| CNAME record | registro CNAME | DNS configuration |

## Error Messages

| English | Portuguese (BR) | Context |
|---------|----------------|----------|
| error | erro | Problem notification |
| warning | aviso | Caution notification |
| oops | ops | Friendly error introduction |

## Buttons and Actions

| English | Portuguese (BR) | Context | Notes |
|---------|----------------|----------|-------|
| submit | enviar | Submit action | Imperative voice |
| cancel | cancelar | Negative action | Imperative voice |
| confirm | confirmar | Positive action | Imperative voice |
| copy to clipboard | copiar para área de transferência | Utility action | Brazilian term for clipboard |
| continue | continuar | Navigation | Imperative voice |
| back | voltar | Navigation | Imperative voice |

## Marketing Terms

| English | Portuguese (BR) | Context |
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

---

# Language-Specific Guidelines

## Critical Terminology Distinctions

### 1. Secret vs Segredo

**CRITICAL:** The term "secret" is central to the application and must be translated consistently.

Use **"mensagem confidencial"** (confidential message) or **"conteúdo confidencial"** (confidential content) instead of "segredo" to avoid implications of personal secrets.

✅ **CORRECT:**
- "Criar mensagem confidencial"
- "Visualizar conteúdo confidencial"
- "3 novas mensagens confidenciais"

❌ **INCORRECT:**
- "Criar segredo" (implies personal secret)
- "Visualizar segredo"
- "3 novos segredos"

**Examples from actual translations:**
- `create-a-secret`: "Criar um Segredo" → **"Criar Mensagem Confidencial"**
- `secret-content`: "Conteúdo secreto" → **"Conteúdo confidencial"**
- `recent-secrets-count`: Use **"mensagens confidenciais"**

### 2. Password vs Passphrase

**CRITICAL:** Distinguish clearly between these two concepts.

- **Senha**: ONLY for account login
- **Frase secreta**: ONLY for protecting individual secrets

✅ **CORRECT:**
- "Digite sua senha para entrar na conta" (Enter your password to log in)
- "Proteja com uma frase secreta" (Protect with a passphrase)
- `enter-a-passphrase`: **"Insira uma frase secreta"**

❌ **INCORRECT:**
- Using "senha" for both concepts
- Using ambiguous terms

## Brazilian vs European Portuguese

**CRITICAL:** This translation uses Brazilian Portuguese (pt-BR) conventions, NOT European Portuguese (pt-PT).

### Key Differences

| Aspect | Brazilian (pt-BR) ✅ | European (pt-PT) ❌ |
|--------|---------------------|-------------------|
| Search verb | buscar | pesquisar |
| Informal you | você | tu/vós |
| Application | aplicativo/aplicação | aplicação |
| Training | treinar | formar |
| Clipboard | área de transferência | prancheta |

### Gerund Usage

Brazilian Portuguese uses the gerund (-ndo) more frequently than European Portuguese.

✅ **Brazilian (CORRECT):**
- "Mostrando resultados" (Showing results)
- "Buscando" (Searching)
- "Carregando" (Loading)

❌ **European (INCORRECT for pt-BR):**
- "A mostrar resultados"
- "A buscar"
- "A carregar"

**Use the Brazilian gerund style throughout all documentation and UI text.**

## Formality and Tone

### Use "Você" (Informal You)

Modern Brazilian Portuguese tech documentation uses **"você"** (informal you), not overly formal "o senhor/a senhora".

**Examples:**
- "Seu recurso central" (Your central resource)
- "Confira nossa documentação" (Check our documentation)
- "Se você tiver dúvidas" (If you have questions)
- "Bem-vindo ao painel" (Welcome to your dashboard)

This creates a professional but approachable tone, which is standard for tech documentation in Brazil.

### Voice Consistency

**For Actions (Buttons, Commands):**
Use active, imperative voice:
- **"Ocultar"** (Hide)
- **"Visualizar"** (View)
- **"Enviar"** (Submit)
- **"Cancelar"** (Cancel)

**For Informational Text (Status, Descriptions):**
Use declarative/passive voice:
- "A mensagem foi visualizada" (The message was viewed)
- "Conteúdo criptografado em repouso" (Content encrypted at rest)
- "Proteção por frase secreta aplicada" (Passphrase protection applied)

## Clarity and Conciseness

### Standard Abbreviations

Use standard Brazilian Portuguese abbreviations:

| English | Portuguese (BR) | Notes |
|---------|----------------|-------|
| e.g. | ex. | NOT "p. ex. exemplo" |
| i.e. | isto é / ou seja | Spelled out for clarity |
| etc. | etc. | Same as English |

**Example:**
- `e-g-example`: Changed from "p. ex. exemplo" to **"ex."**

### Natural Language Flow

Write for Brazilian Portuguese speakers, not literal English translations.

✅ **GOOD (Natural Brazilian Portuguese):**
```
"Bem-vindo ao Onetime Secret Docs, seu recurso central para
maximizar o valor do nosso serviço de compartilhamento de
mensagens confidenciais efêmeras e focado em privacidade."
```

This uses:
- Natural sentence structure
- Professional tone with "você/seu"
- Appropriate vocabulary
- Natural gerund usage

❌ **BAD (Literal translation):**
```
"Bem-vindo para Documentos de Onetime Secret, o recurso central
de você para maximizando valor de nosso serviço..."
```

## Link Localization

**CRITICAL:** All internal documentation links must use the `/pt-br/` prefix.

### Correct Link Format

```markdown
✅ CORRECT: [documentação](/pt-br/docs-overview)
✅ CORRECT: [primeiros passos](/pt-br/introduction)
✅ CORRECT: [segurança](/pt-br/security/best-practices)

❌ WRONG: [documentação](/pt/docs-overview)     # Wrong locale code
❌ WRONG: [documentação](/pt-pt/docs-overview)  # Wrong variant
❌ WRONG: [documentação](docs-overview)         # Missing locale prefix
```

**Note:** The locale code uses a hyphen: `pt-br` (NOT `pt_br` or `ptbr`)

### External Links

External links to onetimesecret.com should remain as-is:

```markdown
✅ CORRECT: [entrar em contato](https://onetimesecret.com/feedback)
✅ CORRECT: [criar conta](https://onetimesecret.com/signup)
```

---

# Translation Examples and Best Practices

## Example Transformations

### Creating Secrets

**Before:** "Criar um Segredo"
**After:** **"Criar Mensagem Confidencial"**
**Reasoning:** Emphasizes the nature of shared information, not personal secrets

### Viewing Content

**Before:** "Ver conteúdo secreto"
**After:** **"Visualizar conteúdo confidencial"**
**Reasoning:** Uses imperative verb appropriate for buttons + correct terminology

### Passphrase Protection

**Before:** "Digite uma senha" (ambiguous)
**After:** **"Insira uma frase secreta"**
**Reasoning:** Clearly distinguishes from account password

### Documentation Reference

**Before:** "Documentos"
**After:** **"Documentação"**
**Reasoning:** More precise term for technical documentation

### Example Abbreviation

**Before:** "p. ex. exemplo"
**After:** **"ex."**
**Reasoning:** Standard Brazilian abbreviation, more concise

## Complete UI Example

**Welcome Screen (Good Translation):**
```
Bem-vindo ao Onetime Secret

Compartilhe mensagens confidenciais de forma segura com links de acesso único.

[Criar Mensagem Confidencial]
[Entrar na Conta]
[Ver Documentação]

Seus dados são criptografados em trânsito e em repouso.
```

This demonstrates:
- Correct use of "mensagem confidencial"
- Imperative verbs on buttons
- "você" tone ("Seus dados")
- Proper technical terms
- Natural Brazilian Portuguese flow

---

# Summary of Translation Goals

The Portuguese (Brazilian) translation aims to:

1. **Ensure Consistency:** Use standardized terminology for core concepts like `secret` → `mensagem confidencial` and `passphrase` → `frase secreta`

2. **Maintain Clarity:** Distinguish clearly between similar concepts (password vs passphrase, secret vs personal secret)

3. **Follow Brazilian Conventions:** Use Brazilian Portuguese vocabulary, gerund forms, and "você" tone

4. **Apply Correct Voice:** Imperative for actions, declarative for information

5. **Achieve Natural Flow:** Write translations that sound natural to Brazilian Portuguese speakers

6. **Ensure Technical Accuracy:** Translate security and technical terms precisely

7. **Maintain Professional Approachability:** Professional tone while remaining accessible and user-friendly

---

# Quick Reference Checklist

When translating Onetime Secret content to Brazilian Portuguese:

- [ ] Use "mensagem confidencial" or "conteúdo confidencial" for "secret" (noun)
- [ ] Use "frase secreta" for "passphrase"
- [ ] Use "senha" ONLY for account passwords
- [ ] Use "você" tone (informal you), not overly formal language
- [ ] Use Brazilian Portuguese vocabulary (buscar, não pesquisar)
- [ ] Use gerund forms (-ndo) for progressive actions
- [ ] Use imperative voice for buttons and commands
- [ ] Use declarative voice for status and informational text
- [ ] Keep technical terms (API, DNS, SSL) in English
- [ ] Use `/pt-br/` prefix for all internal documentation links
- [ ] Use "ex." for "e.g."
- [ ] Use "Entrar" for "Sign In" (not "Login")
- [ ] Use "Sair" for "Sign Out" (not "Logout")
- [ ] Use "Configurações" for "Settings"
- [ ] Use "Documentação" for technical documentation
- [ ] Write for natural Brazilian Portuguese flow, not literal translations

---

**Document Version:** 1.0
**Created:** 2025
**For Use With:** Onetime Secret translation projects
**Locale:** pt-BR (Portuguese - Brazil)
