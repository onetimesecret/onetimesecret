# GENERATED from translation-rules@18c2c91cce6e9ed5ca8520982bdd291740b56b84 — do not edit, do not cite as source

Locale: `fr_CA` · schema v1

## Register

- Form: **formal**
- Pronoun: `vous`
- Possessive: `votre`, `vos`
- Forbidden tokens:
  - `tu` (standalone_word, error) — informal subject pronoun
  - `ton` (standalone_word, error) — informal possessive (masc.)
  - `ta` (standalone_word, error) — informal possessive (fem.)
  - `tes` (standalone_word, error) — informal possessive (plural)
  - `toi` (standalone_word, error) — informal stressed pronoun
  - `te` (standalone_word, error) — informal object pronoun (non-contracted)
  - `toi-même` (standalone_word, error) — informal reflexive
  - `t'` (word_prefix, error) — elided informal object/reflexive pronoun (t'envoie, t'inscrire)
  - `t’` (word_prefix, error) — elided informal pronoun, curly apostrophe (U+2019)

## Glossary

### burn (en: burn)
- _verb_: **brûler**
  - ✓ Burn this secret before it is read. → Brûler ce secret avant qu'il ne soit lu.
  - ✗ Burn this secret before it is read. → Détruire ce secret avant qu'il ne soit lu.
### email (en: email)
- _noun_: **courriel**
  - ✓ Enter your email address. → Saisissez votre adresse courriel.
  - ✗ Enter your email address. → Saisissez votre adresse e-mail.
### encrypt (en: encrypt)
- _state_: **chiffré**
- _verb_: **chiffrer**
  - ✓ This message is encrypted with your passphrase. → Ce message est chiffré avec votre phrase secrète.
  - ✗ This message is encrypted with your passphrase. → Ce message est crypté avec ta phrase secrète.
### link (en: link)
- _noun_: **lien**
  - ✓ Copy the secret link to share it. → Copiez le lien secret pour le partager.
  - ✗ Copy the secret link to share it. → Copie ton lien secret pour le partager.
### passphrase (en: passphrase)
- _noun_: **phrase secrète**
  - ✓ Enter the passphrase to view this secret. → Saisissez la phrase secrète pour consulter ce secret.
  - ✗ Enter the passphrase to view this secret. → Saisissez le mot de passe pour consulter ce secret.
### password (en: password)
- _noun_: **mot de passe**
  - ✓ Enter your password to sign in. → Saisissez votre mot de passe pour vous connecter.
  - ✗ Enter your password to sign in. → Saisis ton mot de passe pour te connecter.
### secret_object (en: secret)
- _noun_: **secret**
  - ✓ Your secret has been created. → Votre secret a été créé.
  - ✗ Your secret has been created. → Ton secret a été créé.

## Rules (binding)

- **MUST** (error): Use the locale's locked register form (formality, pronoun, possessives) in all UI and email content. `[rule.register-lock]`
- **MUST** (error): Keep web.auth.security.* messages generic — never reveal which credential failed, precise timing, attempt counts, or account existence. `[rule.security-generic-messages]`
- **MUST** (error): Preserve interpolation placeholders ({var}, {0}, %{var}) exactly — identical names, count, and syntax as the source string. `[rule.preserve-interpolation]`
- **MUST** (error): Express countable strings with vue-i18n pipe syntax so the target language's plural forms are expressible. `[rule.pluralization-syntax]`
- **MUST_NOT** (error): Do not translate or transliterate brand names (Onetime Secret, One-Time Secret, Identity Plus, Starlight); adapt only the surrounding grammar. `[rule.brand-names-untranslated]`
- **MUST_NOT** (error): Do not translate underscore-prefixed metadata keys (_README, _meta, _translation_guidelines); they are documentation and never user-facing. `[rule.meta-keys-untranslated]`
- **MUST** (error): Use the glossary's chosen term for each concept consistently; do not vary terminology across strings for the same sense. `[rule.terminology-consistency]`
- **MUST** (warning): Destructive or irreversible action labels name their object (Delete Account, not Delete). `[rule.destructive-action-object]`
- **MUST** (error): French content uses the formal vous register (vous / votre / vos) throughout product UI and email content; informal tutoiement (tu / ton / ta / tes) is forbidden. `[register.fr.formality]`
- **MUST** (error): Place a non-breaking space before the double punctuation marks `:` `;` `!` `?`, per French typographic convention. `[rule.fr-punctuation-nbsp]`
- **MUST** (warning): Use the infinitive for button and link labels (Mettre à niveau), and the noun form for titles and headings (Mise à niveau). `[rule.fr-infinitive-buttons]`
- **MUST** (error): Keep mot de passe (system authentication / login) distinct from phrase secrète (protection of a secret); never use one where the other is meant. `[rule.fr-passphrase-password]`
- **MUST** (error): Canadian French uses "courriel" for email throughout UI and email content; the European "e-mail" form is not used in fr_CA. `[rule.fr_CA-courriel]`

## Context (non-binding)

- Brand names stay in English across all locales; only surrounding grammar adapts.
- [SHOULD] Prefer concise phrasing where meaning is preserved, and respect component character limits.
- [SHOULD] Use active imperative voice for action labels and declarative voice for status and error messages.

## Anti-patterns

- Do not treat change-log or descriptive prose as prescriptive translation guidance. `[anti.changelog-as-guidance]`
- Harmonize keys only — never rewrite translated text. A harmonize task that requires text changes is mislabeled; stop and escalate. `[anti.harmonize-text-rewrite]`
