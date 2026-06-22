# GENERATED from translation-rules@18c2c91cce6e9ed5ca8520982bdd291740b56b84 — do not edit, do not cite as source

Locale: `de_AT` · schema v1

## Register

- Form: **formal**
- Pronoun: `Sie`
- Possessive: `Ihr`, `Ihre`, `Ihren`, `Ihrem`, `Ihrer`, `Ihres`
- Forbidden tokens:
  - `du` (standalone_word, error)
  - `dein` (standalone_word, error)
  - `deine` (standalone_word, error)
  - `deinen` (standalone_word, error)
  - `deinem` (standalone_word, error)
  - `deiner` (standalone_word, error)
  - `dich` (standalone_word, error)
  - `dir` (standalone_word, error)
  - `euch` (standalone_word, error)
  - `euer` (standalone_word, error)

## Glossary

### secret_object (en: secret)
- _noun_: **Geheimnis**
  - ✓ Your secret has been created. → Ihr Geheimnis wurde erstellt.
  - ✓ The secret's link has expired. → Der Link des Geheimnisses ist abgelaufen.
  - ✗ Your secret has been created. → Dein Geheimnis wurde erstellt.
### secret_payload (en: secret message)
- _noun_: **Nachricht**
  - ✓ Enter your secret message → Geben Sie Ihre Nachricht ein
  - ✗ Enter your secret message → Gib deine Nachricht ein

## Rules (binding)

- **MUST** (error): Use the locale's locked register form (formality, pronoun, possessives) in all UI and email content. `[rule.register-lock]`
- **MUST** (error): Keep web.auth.security.* messages generic — never reveal which credential failed, precise timing, attempt counts, or account existence. `[rule.security-generic-messages]`
- **MUST** (error): Preserve interpolation placeholders ({var}, {0}, %{var}) exactly — identical names, count, and syntax as the source string. `[rule.preserve-interpolation]`
- **MUST** (error): Express countable strings with vue-i18n pipe syntax so the target language's plural forms are expressible. `[rule.pluralization-syntax]`
- **MUST_NOT** (error): Do not translate or transliterate brand names (Onetime Secret, One-Time Secret, Identity Plus, Starlight); adapt only the surrounding grammar. `[rule.brand-names-untranslated]`
- **MUST_NOT** (error): Do not translate underscore-prefixed metadata keys (_README, _meta, _translation_guidelines); they are documentation and never user-facing. `[rule.meta-keys-untranslated]`
- **MUST** (error): Use the glossary's chosen term for each concept consistently; do not vary terminology across strings for the same sense. `[rule.terminology-consistency]`
- **MUST** (warning): Destructive or irreversible action labels name their object (Delete Account, not Delete). `[rule.destructive-action-object]`
- **MUST** (error): German content uses the formal Sie form (Sie / Ihr / Ihre), not the informal du. `[rule.de-sie]`
- **MUST** (error): de_AT uses the formal Sie-form throughout product UI and email content; informal du/dein forms are forbidden. `[register.de_AT.formality]`

## Context (non-binding)

- Brand names stay in English across all locales; only surrounding grammar adapts.
- [SHOULD] Prefer concise phrasing where meaning is preserved, and respect component character limits.
- [SHOULD] Use active imperative voice for action labels and declarative voice for status and error messages.

## Anti-patterns

- Do not treat change-log or descriptive prose as prescriptive translation guidance. `[anti.changelog-as-guidance]`
- Harmonize keys only — never rewrite translated text. A harmonize task that requires text changes is mislabeled; stop and escalate. `[anti.harmonize-text-rewrite]`
