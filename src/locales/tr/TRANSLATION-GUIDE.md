# Translation Guidance for Turkish (Türkçe)

This document combines the glossary of standardized terms and language-specific translation notes for Turkish translations of Onetime Secret. It serves as a comprehensive reference for translators working on the Turkish locale to ensure consistency, accuracy, and natural phrasing.

## Overview

The Turkish translation aims to:
- Maintain consistency across all application interfaces
- Use clear, natural phrasing for Turkish-speaking audiences
- Follow technical accuracy for security-related terminology
- Apply appropriate voice and tone for different contexts
- Use formal "siz" form to maintain professional tone

---

## Core Terminology

### Basic Terms

| English | Türkçe (TR) | Context | Notes |
|---------|-------------|---------|-------|
| secret (noun) | gizli mesaj | Central application concept | Use "gizli mesaj" instead of "sır" to avoid personal/intimate connotations |
| secret (adj) | gizli | Descriptive use | |
| passphrase | güvenlik ifadesi | Authentication method for secrets | Distinct term for secret protection |
| password | parola / şifre | Account login credential | Standard term for account passwords only |
| burn | yakmak | Action to delete a secret before viewing | Strong metaphor for permanent deletion |
| view/reveal | görüntüle/göster | Action to access a secret | Display/show content |
| link | bağlantı | URL providing access to a secret | |
| encrypt/encrypted | şifrele/şifrelenmiş | Security method | |
| secure | güvenli | Protection state | |

### User Interface Elements

| English | Türkçe (TR) | Context | Notes |
|---------|-------------|---------|-------|
| Share a secret | Gizli mesaj paylaş | Primary action | |
| Create Account | Hesap oluştur | Registration | |
| Sign In | Giriş yap | Authentication | |
| Dashboard | Kontrol paneli | User's main page | |
| Settings | Ayarlar | Configuration page | |
| Privacy Options | Gizlilik seçenekleri | Secret configuration | |
| Feedback | Geri bildirim | User feedback | |

### Status Terms

| English | Türkçe (TR) | Context | Notes |
|---------|-------------|---------|-------|
| received | alındı | Secret has been viewed | Past tense passive |
| burned | yakıldı | Secret was deleted before viewing | Past tense passive |
| expired | süresi doldu | Secret no longer available due to time | Past tense passive |
| created | oluşturuldu | Secret has been generated | Past tense passive |
| active | aktif | Secret is available | |
| inactive | pasif | Secret is not available | |
| expiring soon | yakında sona erecek | Approaching expiration | |
| orphaned | sahipsiz | Without an owner | |
| securing | güvenli hale getiriliyor | Being made secure | Present continuous passive |

### Time-Related Terms

| English | Türkçe (TR) | Context |
|---------|-------------|---------|
| expires in | ... içinde sona erer | Time until secret becomes unavailable |
| day/days | gün | Time unit |
| hour/hours | saat | Time unit |
| minute/minutes | dakika | Time unit |
| second/seconds | saniye | Time unit |

### Security Features

| English | Türkçe (TR) | Context |
|---------|-------------|---------|
| one-time access | tek kullanımlık erişim | Core security feature |
| passphrase protection | güvenlik ifadesi koruması | Additional security |
| encrypted in transit | aktarım sırasında şifrelenmiş | Data protection method |
| encrypted at rest | beklemede şifrelenmiş | Storage protection |

### Account-Related Terms

| English | Türkçe (TR) | Context |
|---------|-------------|---------|
| email | e-posta | User identifier |
| password | parola / şifre | Account authentication |
| account | hesap | User profile |
| subscription | abonelik | Paid service |
| customer | müşteri | Paying user |
| plan | plan | Service tier |
| colonel | yönetici | Administrator role (highest privileges) |

### Domain-Related Terms

| English | Türkçe (TR) | Context |
|---------|-------------|---------|
| custom domain | özel alan adı | Premium feature |
| domain verification | alan adı doğrulaması | Setup process |
| DNS record | DNS kaydı | Configuration |
| CNAME record | CNAME kaydı | DNS configuration |

### Error Messages

| English | Türkçe (TR) | Context |
|---------|-------------|---------|
| error | hata | Problem notification |
| warning | uyarı | Caution notification |
| oops | Hata! | Friendly error introduction |

### Buttons and Actions

| English | Türkçe (TR) | Context | Notes |
|---------|-------------|---------|-------|
| submit | gönder | Form action | Imperative form |
| cancel | iptal et | Negative action | Imperative form |
| confirm | onayla | Positive action | Imperative form |
| copy to clipboard | panoya kopyala | Utility action | Imperative form |
| continue | devam et | Navigation | Imperative form |
| back | geri | Navigation | |
| create | oluştur | Imperative form for buttons | |
| save | kaydet | Imperative form for buttons | |
| delete | sil | Remove item | Imperative form |
| share | paylaş | Share/distribute | Imperative form |

### Marketing Terms

| English | Türkçe (TR) | Context |
|---------|-------------|---------|
| secure links | güvenli bağlantılar | Product feature |
| privacy-first design | gizlilik odaklı tasarım | Design philosophy |
| custom branding | özel markalama | Premium feature |

---

## Translation Guidelines

### 1. Consistency

- Use the same translation for a term throughout the application
- Maintain standardized terminology from the glossary above
- Key distinctions to preserve:
  - `parola/şifre` for account passwords
  - `güvenlik ifadesi` for secret protection
  - `gizli mesaj` as the core concept (not "sır")

### 2. Context Awareness

- Consider how the term is used in the application
- Account for surrounding UI elements and user flow
- Ensure translations make sense in their specific context

### 3. Cultural Adaptation

- Adapt terms to local conventions when necessary
- Use standard Turkish that works across regions
- Use standard technical terms familiar to Turkish-speaking users

### 4. Technical Accuracy

- Security-related terms must be translated accurately
- Prioritize precision over localization for technical terminology
- Use established Turkish technical vocabulary

### 5. Voice and Tone

#### Active, Imperative Voice (for Actions)
Use imperative voice for buttons, links, and user actions:
- `Gizli mesaj oluştur` (Create secret)
- `Panoya kopyala` (Copy to clipboard)
- `Hesap oluştur` (Create account)
- `Kaydet` (Save)
- `Paylaş` (Share)

#### Passive or Declarative Voice (for Information)
Use passive voice or past tense for informational text, status messages, and descriptions:
- `Gizli mesaj oluşturuldu` (Secret created - status)
- `Güvenli mesajınız aşağıda gösterilmektedir.` (Your secure message is shown below.)
- `Gizli mesaj manuel olarak yakıldı...` (The secret was manually burned...)
- `Kaydedildi` (Saved - status message)

### 6. Formal Address

- **Use formal "siz" form** consistently when addressing users (not informal "sen")
- Examples:
  - `Parolanızı girin` (Enter your password)
  - `Güvenli mesajınız` (Your secure message)
- Turkish professional context requires respectful "siz" form

### 7. Clarity and Natural Phrasing

- Prioritize natural Turkish expressions over literal translations
- Use standard phrases familiar to Turkish speakers
- **Avoid verbose sentences** - Turkish can become wordy; resist this tendency
- Use clear, direct language that respects users' time

### 8. Completeness

- Ensure all user-facing strings are translated
- Avoid leaving English text in the interface
- Translate help text, descriptions, and metadata

---

## Common Translation Patterns

### User Instructions
Use imperative forms:
- `Parolanızı girin` (Enter your password)
- `Panoya kopyala` (Copy to clipboard)
- `Güvenlik ifadesini buraya girin` (Enter the passphrase here)

### Status Descriptions
Use passive voice or past tense:
- `Panoya kopyalandı` (Copied to clipboard)
- `Gizli mesaj oluşturuldu` (Secret created)
- `Kaydedildi` (Saved)
- `Oluşturuldu` (Created)

### Help Text and Descriptions
Use declarative sentences in formal address:
- `Gizli içeriği görüntülüyorsunuz` (You are viewing the secret content)
- `Bu içerik yalnızca bir kez gösterilir` (This content is shown only once)

### Error Messages
Use clear, direct language:
- `Yanlış güvenlik ifadesi` (Incorrect passphrase)
- `Bir hata oluştu` (An error occurred)

---

## Special Considerations

### The Term "Secret" - Critical Choice

**ALWAYS use "gizli mesaj" (secret/confidential message), NOT "sır" (personal secret)**

The Turkish word "sır" carries inappropriate connotations:
- Personal, intimate secrets
- Private or hidden information
- Connotations too personal for business/security context

This parallels the Danish translation decision documented in the English style guide, where "hemmeligheder" was rejected in favor of "beskeder" (messages) for the same reasons.

**Precedent from Translation Guide:**
The English translation guide provides this Danish example that directly applies to Turkish:

> **Danish Translation:**
> - CORRECT: "Beskeder" (messages)
> - INCORRECT: "Hemmeligheder" (secrets)
>
> Reasoning: While "Hemmeligheder" is a literal translation, it carries connotations of personal or hidden information in everyday Danish usage that don't match the intended meaning.

**Turkish follows the same pattern:**
- ✓ CORRECT: `gizli mesaj` (secret/confidential message) - neutral, technical
- ✗ INCORRECT: `sır` (personal secret) - too personal/intimate

Examples:
- ✓ `3 yeni gizli mesajınız var` (You have 3 new secret messages)
- ✗ `3 yeni sırrınız var` (You have 3 new secrets)
- ✓ `Gizli mesaj oluştur` (Create a secret)
- ✗ `Sır oluştur` (Create a secret)

### Password vs. Passphrase - CRITICAL DISTINCTION

**This distinction is critical for security clarity and must be maintained throughout:**

- **`parola` or `şifre`** - for user account login credentials ONLY
- **`güvenlik ifadesi`** - for protecting individual secrets (NOT account login)

Users must understand that:
1. **Password (parola/şifre)** = credentials to access their Onetime Secret account
2. **Passphrase (güvenlik ifadesi)** = optional extra layer of protection for individual secrets

**Precedent from Other Languages:**
- Bulgarian: "парола" (password) vs "ключова фраза" (key phrase)
- Danish: "adgangskode" vs "adgangssætning"
- Spanish: "contraseña" vs "frase de seguridad"

Examples:
- ✓ `Giriş yapmak için parolanızı girin` (Enter your password - account login)
- ✗ `Giriş yapmak için güvenlik ifadenizi girin` (Enter your passphrase - account login)
- ✓ `Bu gizli mesaj bir güvenlik ifadesi ile korunmaktadır` (This secret is protected with a passphrase)
- ✗ `Bu gizli mesaj bir parola ile korunmaktadır` (This secret is protected with a password)

### The Term "Burn"
Consistently translated as **`yakmak`** (to burn):
- Creates strong mental image of permanent deletion
- More impactful than generic `sil` (delete)
- Examples:
  - `Bu gizli mesajı yak` (Burn this secret - button)
  - `Gizli mesaj yakıldı` (The secret was burned - status)

### The Term "Colonel"
Translated as **`yönetici`** (administrator):
- Project-specific term that rhymes with "kernel" in English
- No direct Turkish equivalent for this playful technical term
- Use common term for "administrator" - the account with highest privileges
- Example: `Yalnızca yöneticiler bu özelliğe erişebilir` (Only admins can access this feature)

### UI Element Conventions
- Follow platform conventions for the target language
- Use standard Turkish terminology for common UI elements
- Maintain consistency with other Turkish applications

### Technical Security Terms
- Prioritize accuracy over casual localization
- Use established Turkish technical vocabulary
- Examples:
  - `şifrelenmiş` (encrypted)
  - `şifrele` (to encrypt)
  - `doğrulama` (verification)
  - `kimlik doğrulama` (authentication)

---

## Brand Voice in Turkish

### Core Values
- **Özgün ve şeffaf** (Authentic and transparent) - Use clear, honest language
- **Sabırlı ve odaklı** (Patient and focused) - Provide helpful explanations
- **Kaliteden ödün vermeden verimli** (Efficient without sacrificing quality) - Be concise but complete
- **Profesyonel ama ulaşılabilir** (Professional yet approachable) - Balance formality with warmth

### Communication Principles
- Adapt technical detail based on user context
- Balance friendliness with reliability
- Prioritize clarity over casual language
- Use patient, helpful tone even when explaining complex concepts

### Turkish-Specific Considerations
- Avoid overly bureaucratic language while maintaining professionalism
- Use clear, direct sentences (Turkish can become verbose - resist this)
- Technical terms should remain consistent and clear
- Maintain warmth through respectful language, not informality

---

## UI Text: Active vs Passive Voice in Turkish

### Active, Imperative Voice ("Bir şey yap" - Do something)

**Buttons:**
- ✓ Değişiklikleri kaydet (Save changes)
- ✓ Dosyayı sil (Delete file)
- ✓ Mesajı gönder (Send message)
- ✓ Gizli mesaj oluştur (Create secret)

**Menu items:**
- ✓ Ayarları görüntüle (View settings)
- ✓ Yeni klasör oluştur (Create new folder)

### Passive or Declarative Voice ("Bir şey oldu" - Something happened)

**Status messages:**
- ✓ Değişiklikler kaydedildi (Changes saved)
- ✓ Dosya silindi (File deleted)
- ✓ Ödeme reddedildi (Payment declined)
- ✓ Gizli mesaj yakıldı (Secret burned)

**Notifications:**
- ✓ 3 yeni mesaj (3 new messages)
- ✓ İndirme tamamlandı (Download complete)
- ✓ Sunucu kullanılamıyor (Server unavailable)

**System states:**
- ✓ Yükleme devam ediyor (Upload in progress)
- ✓ Bağlantı kesildi (Connection lost)
- ✓ E-posta adresi bulunamadı (Email address not found)

### Examples in Context

**Form submission:**
- Button (active): `Değişiklikleri kaydet`
- Status (passive): `Değişiklikler başarıyla kaydedildi`

**File upload:**
- Button: `Dosya yükle`
- Status: `Yükleme tamamlandı`

**Secret creation:**
- Button: `Gizli mesaj oluştur`
- Status: `Gizli mesaj oluşturuldu`

---

## Encoding Considerations

### Turkish Character Encoding

Ensure proper UTF-8 encoding for Turkish-specific characters:
- `ı` (dotless i)
- `ğ` (g with breve)
- `ü` (u with diaeresis)
- `ş` (s with cedilla)
- `ç` (c with cedilla)
- `ö` (o with diaeresis)
- `İ` (capital I with dot)

Avoid Unicode escape sequences (`\u0131`, etc.) - use proper UTF-8 encoding for better readability and maintenance.

---

## Summary of Translation Principles

The Turkish translation maintains:

1. **Terminology Consistency** - Standardized key terms throughout the application
2. **Appropriate Voice** - Imperative for actions, passive/past tense for information
3. **Natural Phrasing** - Standard Turkish expressions avoiding verbosity
4. **Formal Address** - Respectful "siz" form throughout
5. **Complete Coverage** - All user-facing strings translated
6. **Technical Accuracy** - Precise terminology for security concepts
7. **Clear Distinctions** - Especially:
   - Account passwords (`parola/şifre`) and secret passphrases (`güvenlik ifadesi`)
   - Using `gizli mesaj` (secret message) instead of `sır` (personal secret)
   - Action verbs (imperative) and status messages (passive/past tense)
8. **Professional Tone** - Balancing formality with approachability

By following these guidelines, translators can ensure that the Turkish version of Onetime Secret is accurate, consistent, professional, and provides a natural user experience for Turkish-speaking audiences.
