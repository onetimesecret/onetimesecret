---
title: Guia de tradução para português brasileiro
description: Guia completo para traduzir o Onetime Secret para português brasileiro, combinando glossário e notas linguísticas
---

# Translation Guidance for Portuguese (Brazil)

This document provides comprehensive guidance for translating Onetime Secret content. It combines universal translation resources with locale-specific terminology and rules.

## Universal Translation Resources

Before translating, review these cross-language guidelines that apply to all locales:

- **[Translating "Secret"](/en/translations/universal/secret-concept)** - How to handle the word "secret" across different language contexts
- **[Password vs. Passphrase](/en/translations/universal/password-passphrase)** - Maintaining the critical distinction between account passwords and secret passphrases
- **[Voice and Tone](/en/translations/universal/voice-and-tone)** - Patterns for active vs. passive voice, formality levels, and cultural adaptations
- **[Brand Terms](/en/translations/universal/brand-terms)** - Terms that should not be translated (product names, tier names)
- **[Quality Checklist](/en/translations/universal/quality-checklist)** - Comprehensive checklist for pre-submission review

---

## Glossário

# Glossário de Tradução do Onetime Secret

Este glossário fornece traduções padronizadas para termos-chave para garantir consistência na aplicação Onetime Secret.

## Terminologia Principal

| Inglês | Português (BR) | Contexto |
|---------|----------------|----------|
| secret (substantivo) | mensagem confidencial / conteúdo confidencial | Conceito central da aplicação |
| secret (adjetivo) | confidencial / secreto | |
| passphrase | frase secreta | Método de autenticação para segredos. NÃO "senha" |
| hide | ocultar | Ação para ocultar conteúdo |
| password | senha | Credencial de login da conta |
| burn | queimar | Ação para excluir um segredo antes de visualizar |
| view/reveal | visualizar/exibir | Ação para acessar um segredo |
| link | link | O URL que fornece acesso a um segredo |
| encrypt/encrypted | criptografar/criptografado | Método de segurança |
| secure | seguro | Estado de proteção |

## Elementos da Interface do Usuário

| Inglês | Português (BR) | Contexto |
|---------|----------------|----------|
| Share a secret | Compartilhar mensagem confidencial | Ação principal |
| Create Account | Criar conta | Registro |
| Sign In | Entrar | Autenticação |
| Dashboard | Painel | Página principal do usuário |
| Settings | Configurações | Página de configuração |
| Privacy Options | Opções de privacidade | Configurações de segredo |
| Feedback | Feedback | Comentários do usuário |

## Termos de Status

| Inglês | Português (BR) | Contexto |
|---------|----------------|----------|
| received | recebido | Segredo foi visualizado |
| burned | queimado | Segredo foi excluído antes da visualização |
| expired | expirado | Segredo não está mais disponível devido ao tempo |
| created | criado | Segredo foi gerado |
| active | ativo | Segredo está disponível |
| inactive | inativo | Segredo não está disponível |

## Termos Relacionados ao Tempo

| Inglês | Português (BR) | Contexto |
|---------|----------------|----------|
| expires in | expira em | Tempo até o segredo não estar mais disponível |
| day/days | dia/dias | Unidade de tempo |
| hour/hours | hora/horas | Unidade de tempo |
| minute/minutes | minuto/minutos | Unidade de tempo |
| second/seconds | segundo/segundos | Unidade de tempo |

## Recursos de Segurança

| Inglês | Português (BR) | Contexto |
|---------|----------------|----------|
| one-time access | acesso único | Recurso de segurança principal |
| passphrase protection | proteção por frase secreta | Segurança adicional |
| encrypted in transit | criptografado em trânsito | Método de proteção de dados |
| encrypted at rest | criptografado em repouso | Proteção de armazenamento |

## Termos Relacionados à Conta

| Inglês | Português (BR) | Contexto |
|---------|----------------|----------|
| email | e-mail | Identificador do usuário |
| password | senha | Autenticação |
| account | conta | Perfil do usuário |
| subscription | assinatura | Serviço pago |
| customer | cliente | Usuário pagante |

## Termos Relacionados ao Domínio

| Inglês | Português (BR) | Contexto |
|---------|----------------|----------|
| custom domain | domínio personalizado | Recurso premium |
| domain verification | verificação de domínio | Processo de configuração |
| DNS record | registro DNS | Configuração |
| CNAME record | registro CNAME | Configuração de DNS |

## Mensagens de Erro

| Inglês | Português (BR) | Contexto |
|---------|----------------|----------|
| error | erro | Notificação de problema |
| warning | aviso | Notificação de cuidado |
| oops | ops | Introdução de erro amigável |

## Botões e Ações

| Inglês | Português (BR) | Contexto |
|---------|----------------|----------|
| submit | enviar | Ação de submissão |
| cancel | cancelar | Ação negativa |
| confirm | confirmar | Ação positiva |
| copy to clipboard | copiar para área de transferência | Ação utilitária |
| continue | continuar | Navegação |
| back | voltar | Navegação |

## Termos de Marketing

| Inglês | Português (BR) | Contexto |
|---------|----------------|----------|
| secure links | links seguros | Recurso do produto |
| privacy-first design | design com privacidade em primeiro lugar | Filosofia de design |
| custom branding | marca personalizada | Recurso premium |

## Diretrizes de Tradução

1. **Consistência**: Use a mesma tradução para um termo em toda a aplicação
2. **Contexto**: Considere como o termo é usado na aplicação
3. **Adaptação Cultural**: Adapte termos às convenções locais quando necessário
4. **Precisão Técnica**: Certifique-se de que os termos de segurança sejam traduzidos com precisão
5. **Tom**: Mantenha um tom profissional, mas direto

## Considerações Especiais

### Distinção Crucial: "Secret" vs "Segredo"

O termo "secret" é central para a aplicação e deve ser traduzido consistentemente como **"mensagem confidencial"** ou **"conteúdo confidencial"** em vez de simplesmente "segredo", para evitar conotações de informações pessoais.

✅ Correto:
- "Criar mensagem confidencial"
- "Visualizar conteúdo confidencial"
- "3 novas mensagens confidenciais"

❌ Incorreto:
- "Criar segredo" (implica segredo pessoal)
- "Visualizar segredo"
- "3 novos segredos"

### Distinção Password vs Passphrase

- **Senha**: Apenas para login de conta
- **Frase secreta**: Apenas para proteção de mensagens individuais

✅ Correto:
- "Digite sua senha para entrar na conta"
- "Proteja com uma frase secreta"

❌ Incorreto:
- Usar "senha" para ambos os conceitos

### Termos Técnicos a Manter em Inglês

Manter estes termos em inglês para precisão técnica:
- API
- URL
- DNS
- SSL/TLS
- HTTP/HTTPS
- JSON
- YAML
- hash

### Termos Técnicos a Traduzir

Termos técnicos relacionados à segurança devem priorizar precisão sobre localização:
- encryption → criptografia (não "encriptação")
- secrets → mensagens confidenciais
- passphrase → frase secreta
- custom domains → domínios personalizados
- settings → configurações
- dashboard → painel
- clipboard → área de transferência

### Elementos de Interface

Elementos de interface devem seguir convenções da plataforma para português do Brasil:
- Use "Entrar" em vez de "Login" ou "Logar"
- Use "Sair" em vez de "Logout"
- Use "Configurações" em vez de "Ajustes" ou "Opções"

---

## Portuguese (Brazil) Translation Notes

# Portuguese (Brazil, pt-BR) Translation Notes

## Translation Goals

The primary goal was to ensure the translation aligns precisely with the guidelines, focusing on:

1. **Consistency and Clarity of Core Concepts:** Ensuring terms like `secret` and `passphrase` are translated consistently and accurately according to their specific meanings within the Onetime Secret platform
2. **Brand Voice and Tone:** Refining the language to be professional, clear, and efficient, while remaining approachable
3. **Grammar and Style:** Applying rules regarding active/imperative voice for actions (buttons) and passive/declarative voice for informational text (status messages or descriptions)
4. **Natural Language:** Selecting translations that sound natural in Brazilian Portuguese, rather than overly literal translations from English

## Important Translation Examples

### 1. `secret` Translation

**Guideline:** Translate `secret` as the confidential information/message, not personal secrets.

**Changes:** Keys like `create-a-secret`, `recent-secrets-count`, `hide-secret-message`, `view-secret-message`, `secret-content`, `secrets-details-counts-secret_count` were updated.

**Reasoning:** The previous translations might have used "segredo," which could imply a personal secret. The updated translations consistently use variations like **"mensagem confidencial"** (confidential message) or **"conteúdo confidencial"** (confidential content) to more accurately reflect the nature of the shared item.

**Examples:**
- `create-a-secret`: "Criar um Segredo" → **"Criar Mensagem Confidencial"**
- `secret-content`: "Conteúdo secreto" → **"Conteúdo confidencial"**

### 2. `passphrase` Translation

**Guideline:** Distinguish clearly between account `password` and secret `passphrase`. Use a term implying a phrase-based security measure for the latter.

**Change:** Keys like `enter-a-passphrase` and the new `Double check that passphrase` use **"frase secreta"**.

**Reasoning:** To avoid ambiguity with the account `password` (typically "senha"), the distinct term **"frase secreta"** (secret phrase) was consistently applied for protecting individual secrets, directly following the guideline.

**Examples:**
- `enter-a-passphrase`: Potentially ambiguous term → **"Insira uma frase secreta"**

### 3. Clarity and Conciseness

**Guideline:** Prioritize clarity, avoid redundancy.

**Changes:**
- `e-g-example`: Changed from "p. ex. exemplo" to **"ex."**
  - Reasoning: "ex." is the standard and more concise abbreviation for "for example" in Portuguese, making the UI cleaner

- `docs`: Changed from "Documentos" to **"Documentação"**
  - Reasoning: "Documentação" is the more common and precise term for technical documentation in this context

### 4. Voice Consistency (Imperative for Actions)

**Guideline:** Use active, imperative voice for user actions (buttons, etc.).

**Changes:** `hide-secret-message` and `view-secret-message` verbs were refined.

**Reasoning:** Ensured the verbs used (**"Ocultar"**, **"Visualizar"**) are clear commands appropriate for button labels, alongside the updated term for `secret`.

## Summary of Changes to the Portuguese (Brazil) Translation

The Portuguese (Brazil) translation was updated to align more closely with the specific terminology and style guidelines. Key changes involved:

### Standardizing `secret`
Consistently translating `secret` as **"mensagem confidencial"** or **"conteúdo confidencial"** to emphasize the nature of the shared information rather than personal secrets.

### Clarifying `passphrase`
Using the distinct term **"frase secreta"** for secret protection to differentiate it clearly from the account `password` (**"senha"**).

### Improving Clarity and Conciseness
Refining phrasing for better natural language flow and using standard abbreviations (e.g., **"ex."** for "e.g.").

### Ensuring Voice Consistency
Applying imperative verbs for user actions (buttons) and declarative/passive voice for informational text where appropriate.

These adjustments aim to enhance the accuracy, consistency, and clarity of the user interface for Brazilian Portuguese speakers using Onetime Secret.

## Key Terminology

| English | Portuguese (Brazil) | Notes |
|---------|-------------------|-------|
| secret (noun) | mensagem confidencial / conteúdo confidencial | Emphasizes the information being shared |
| password | senha | Account login credential only |
| passphrase | frase secreta | Secret protection mechanism |
| burn | queimar | Permanent deletion metaphor |
| view | visualizar | Imperative form for buttons |
| hide | ocultar | Imperative form for buttons |
| documentation | documentação | Technical documentation |
| search | buscar | Brazilian preference (not "pesquisar") |
| clipboard | área de transferência | Brazilian term |
| custom domains | domínios personalizados | Standard translation |
| dashboard | painel | Translated (not loanword) |
| settings | configurações | Standard translation |

## Brazilian vs European Portuguese

**CRITICAL:** This translation uses Brazilian Portuguese conventions, not European Portuguese.

### Key Differences

| Aspect | Brazilian (pt-br) ✅ | European (pt-pt) ❌ |
|--------|---------------------|-------------------|
| Search verb | buscar | pesquisar |
| You (informal) | você | tu/vós |
| Application | aplicativo/aplicação | aplicação |
| Train | treinar | formar |

### Gerund Usage

Brazilian Portuguese uses the gerund (-ndo) more frequently than European Portuguese:

- ✅ **Brazilian:** "Mostrando resultados" (Showing results)
- ❌ **European:** "A mostrar resultados"

- ✅ **Brazilian:** "Buscando" (Searching)
- ❌ **European:** "A buscar"

Use the Brazilian gerund style throughout documentation.

## Formality and Tone

### Use "Você" (Informal You)

Modern Brazilian Portuguese tech documentation uses **"você"** (informal you), not overly formal "o senhor/a senhora":

**Examples:**
- "Seu recurso central" (Your central resource)
- "Confira nossa documentação" (Check our documentation)
- "Se você tiver dúvidas" (If you have questions)

This creates a professional but approachable tone, standard for tech documentation in Brazil.

## Link Localization

**CRITICAL:** All internal links must use the `/pt-br/` prefix.

### Correct Format

```markdown
✅ CORRECT: [documentação](/pt-br/docs-overview)
✅ CORRECT: [primeiros passos](/pt-br/introduction)
✅ CORRECT: [segurança](/pt-br/security/best-practices)

❌ WRONG: [documentação](/pt/docs-overview)  # Wrong locale code
❌ WRONG: [documentação](docs-overview)      # Missing locale prefix
```

**Note:** The locale code uses a hyphen: `pt-br` (not `pt_br` or `ptbr`)

### External Links

External links to onetimesecret.com should remain as-is:

```markdown
✅ CORRECT: [entrar em contato](https://onetimesecret.com/feedback)
```

## Technical Terms

### Keep in English

These terms should remain in English:
- API
- URL
- DNS
- SSL/TLS
- HTTP/HTTPS
- JSON
- YAML

### Translate to Portuguese

Technical concepts should be translated for clarity:
- secrets → mensagens confidenciais
- passphrase → frase secreta
- custom domains → domínios personalizados
- settings → configurações
- dashboard → painel
- clipboard → área de transferência

## Natural Language Flow

### Write for Brazilian Portuguese Speakers

Translations should sound natural in Brazilian Portuguese, not like literal English translations:

**Good example:**
```markdown
"Bem-vindo ao Onetime Secret Docs, seu recurso central para
maximizar o valor do nosso serviço de compartilhamento de
mensagens confidenciais efêmeras e focado em privacidade."
```

This uses:
- Natural Brazilian Portuguese sentence structure
- Professional tone with "você/seu"
- Appropriate vocabulary choices
- Natural gerund usage (-ndo verbs)

## Voice Consistency

### For Actions (Buttons, Commands)

Use active, imperative voice:
- **"Ocultar"** (Hide)
- **"Visualizar"** (View)
- **"Enviar"** (Submit)
- **"Cancelar"** (Cancel)

### For Informational Text (Status, Descriptions)

Use declarative/passive voice:
- "A mensagem foi visualizada" (The message was viewed)
- "Conteúdo criptografado em repouso" (Content encrypted at rest)
- "Proteção por frase secreta aplicada" (Passphrase protection applied)

## Standard Abbreviations

Use standard Brazilian Portuguese abbreviations:

| English | Portuguese (BR) | Notes |
|---------|----------------|-------|
| e.g. | ex. | NOT "p. ex. exemplo" |
| i.e. | isto é / ou seja | Spelled out for clarity |
| etc. | etc. | Same as English |

---

## Document Information

This guide was generated from the following source files:

- Universal resources: `/en/translations/universal/`
- Glossary: `/pt-br/translations/glossary.md`
- Language notes: `/pt-br/translations/language-notes.md`

Generated: 2026-01-20
