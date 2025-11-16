# Translation Quality Report: Turkish (tr.json)

**Date:** 2025-11-16
**Locale:** Turkish (tr)
**Compared to:** English (en.json)
**Analysis Type:** Comprehensive Quality Assessment

---

## Executive Summary

The Turkish translation demonstrates **good quality** with mostly natural Turkish phrasing and appropriate technical terminology. However, it contains inconsistencies in formality (sen/siz), some incomplete translations, and areas where more natural Turkish expressions could be used. With refinements, this translation could reach excellent quality.

**Overall Score: 7/10**

---

## 1. Completeness Analysis

### Coverage: ⚠️ Mostly Complete (95%)
- Most keys from English version are present
- Several empty or incomplete values detected
- All nested structures properly maintained

### Missing/Empty Translations:
```json
"broadcast": "",  // Empty in COMMON section
"button_create_incoming": "",  // Empty in COMMON section
"incoming_button_creating": "Creating",  // Not translated (English)
```

### Incomplete Sections:
```json
"colonel" section: // Many strings still in English
"customer-verified-verified-not-verified-0": "`+customer.verified ? `verified` : `not verified",
"customers-details-counts-recent_customer_count-o-0": "Customers ({0} of {1})",
// ... several more in this section
```

**Impact:** MODERATE - Colonel section appears to be admin interface, less critical but should be translated

---

## 2. Translation Quality Assessment

### 2.1 Strengths

#### Good Technical Terminology
Professional Turkish IT terminology used appropriately:

```json
"secret": "Gizli Mesaj"  // Good choice - "Secret Message"
"passphrase": "Parola"  // Appropriate
"encryption": "Şifrelenmiş"  // Correct technical term
"burn": "Yak"  // Direct but effective
```

#### Natural Turkish Sentence Structure
Generally follows Turkish word order (SOV):

```json
"click_to_continue": "Devam etmek için tıkla →"  // ✅ Natural order
"burn_this_secret": "Bu gizli mesajı yak"  // ✅ Correct SOV structure
```

#### Proper Use of Turkish Grammar
- Correct vowel harmony (mostly)
- Appropriate case suffixes
- Proper verb conjugations

### 2.2 Notable Quality Features

#### Agglutination Handled Well
Turkish is agglutinative language - words built with suffixes. Translation handles this well:

```json
"copied_to_clipboard": "Panoya kopyalandı"
// "pano-ya" (to clipboard) + "kopyala-n-dı" (was copied)
// ✅ Perfect suffix usage

"expires_in": "Kalan zaman"
// Simple, effective
```

#### Cultural Adaptation of Some Terms
```json
"oops": "Eyvah!"  // ⭐ Excellent - natural Turkish exclamation
"error": "Hata"  // Standard
"warning": "Uyarı"  // Correct
```

---

## 3. Issues and Recommendations

### 3.1 Major Issues

#### Issue 1: CRITICAL - Inconsistent Formality (Sen/Siz) ❌
**Location:** Throughout the file
**Impact:** HIGH - Undermines professionalism

**Examples of Informality (Sen):**
```json
"your_account": "Hesabın"  // Informal "your"
"your_secret_message": "Gizli mesajın:"  // Informal possessive
"description": "...sohbet geçmişinizde..."  // MIX: "sohbet" informal but "geçmişinizde" formal!
```

**Examples of Formality (Siz):**
```json
"header_settings": "Ayarlar"  // Neutral
"enter_your_credentials": "Giriş bilgilerini yaz"  // Imperative but neutral
```

**Problem:** The mixing is inconsistent and confusing. Some sentences even mix both!

**Recommendation:** **CRITICAL FIX NEEDED**
- Choose ONE form: Formal (Siz) OR Informal (Sen)
- For security application: **Recommend Formal (Siz)**
- Apply consistently throughout

**Examples of needed fixes:**
```
BEFORE: "Hesabın" (your account - informal)
AFTER:  "Hesabınız" (your account - formal)

BEFORE: "Gizli mesajın" (your secret - informal)
AFTER:  "Gizli mesajınız" (your secret - formal)
```

#### Issue 2: Untranslated/English Fragments
**Location:** Multiple
**Impact:** MODERATE

**Examples:**
```json
"incoming_button_creating": "Creating",  // Should be "Oluşturuluyor..."
"learn_more": "Learn more",  // Should be "Daha fazla bilgi"

// Colonel section (admin interface):
"customer-verified-verified-not-verified-0": "`+customer.verified ? `verified` : `not verified",
"customers-details-counts-recent_customer_count-o-0": "Customers ({0} of {1})",
```

**Recommendation:** Complete all translations

#### Issue 3: Some Awkward/Overly Literal Translations
**Location:** Various
**Examples:**
```json
"careful_only_see_once": "dikkat: sadece bir defa gösterilecek."
// Better: "dikkat: Bu mesaj sadece bir kez gösterilecek."

"button_generate_secret": "Veya rastgele parola oluştur"
// Current mixing "veya" (or) in button text - awkward
// Better: "Rastgele Parola Oluştur" (remove "Veya")
```

### 3.2 Moderate Issues

#### Issue 4: Terminology Inconsistency
**Location:** Various
**Examples:**
```json
"secret": "Gizli Mesaj"  // Used throughout (good)
BUT ALSO:
"header_dashboard": "Hesabım"  // "My Account" instead of "Pano" (Dashboard)
```

**Analysis:** Generally consistent but some English terms could have better Turkish equivalents

---

## 4. Specific Section Analysis

### 4.1 Help/FAQ Section
**Quality:** Good with minor issues
**Example:**
```json
"what_am_i_looking_at": {
  "title": "Neye bakıyorum?",  // ⚠️ Informal "bakıyorum"
  "description": "Onetime Secret aracılığıyla sizinle paylaşılan güvenli bir mesaja bakıyorsunuz..."  // ✅ Formal "bakıyorsunuz"
}
```

**Issue:** Title uses informal, description uses formal - inconsistent within same entry!

**Recommendation:**
```json
"title": "Neye bakıyorum?",  // Keep informal for conversational question
// OR make both formal:
"title": "Neye bakıyorsunuz?",
```

### 4.2 Error Messages
**Quality:** Good, mostly clear
**Example:**
```json
"error_secret": "Paylaşılacak birşey yazmadın",  // ⚠️ Informal "yazmadın"
"error_passphrase": "Yanlış parola",  // ✅ Clear, neutral
"incorrect_passphrase": "Hatalı parola"  // ✅ Good
```

**Issue:** Formality inconsistency again

**Strength:** Messages are clear and actionable

### 4.3 Email Templates
**Quality:** Professional
**Example:**
```json
"secretlink": {
  "subject": "%s sana bir gizli mesaj yolladı",  // ⚠️ "sana" informal
  "body1": "Senin için bir gizli mesaj gönderdi, ",  // ⚠️ "Senin" informal
  "body_tagline": "Eğer göndereni tanımıyorsanız..."  // ✅ "tanımıyorsanız" formal
}
```

**Critical Issue:** Email templates MIX informal and formal in same message!
- Subject: Informal ("sana")
- Body: Informal ("senin")
- Tagline: Formal ("tanımıyorsanız")

**Recommendation:** Emails should be completely formal (professional correspondence):
```json
"subject": "%s size bir gizli mesaj yolladı",  // Formal "size"
"body1": "Sizin için bir gizli mesaj gönderildi, ",  // Formal "sizin"
```

---

## 5. Accessibility Considerations

### Screen Reader Friendliness: ✅ Good
- ARIA labels translated
- Turkish screen readers will handle well
- Proper use of Turkish characters (ç, ğ, ı, İ, ö, ş, ü)

**Example:**
```json
"burn_this_secret_aria": "Bu gizli mesajı kalıcı olarak yak"
```

**Quality:** Clear action description

---

## 6. Consistency Analysis

### Terminology Consistency Score: 7/10

#### Consistent Terms:
- ✅ "Gizli Mesaj" (secret message) - mostly consistent
- ✅ "Link/Bağlantı" - varies but acceptable
- ✅ "Kopya/Kopyala" (copy) - consistent
- ✅ "Şifrelenmiş" (encrypted) - consistent

#### Inconsistent Areas:
- ❌ **MAJOR:** Sen/Siz formality throughout
- ⚠️ "Parola" vs "Frase" (passphrase) - needs clarification
- ⚠️ Some English terms kept, others translated

---

## 7. Technical Accuracy

### Format Strings: ✅ Good
Most placeholders preserved correctly:

```json
"expires_in": "Kalan zaman",  // Simple but works
"items_count": "{count} Öğe",
"days_remaining": "{count} Gün Kaldı"
```

**Note:** Some could be more natural:
```json
"expires_in": "Kalan zaman"  // Works but could be "Süre: {time}" for clarity
```

### Special Characters: ✅ Excellent
- Turkish characters properly used: ç, ğ, ı, İ, ö, ş, ü
- Dotted (İ) vs dotless (ı) I handled correctly
- Email format preserved: `{'@'}`

**Example:**
```json
"şifrelenmiş"  // ✅ Correct ş
"öğe"  // ✅ Correct ö
"gönder"  // ✅ Correct ö
```

### HTML/Markdown: ✅ Preserved
- Links intact
- Formatting maintained

---

## 8. Cultural Appropriateness

### Score: 7.5/10

#### Strengths:
- ✅ Generally appropriate for Turkish users
- ✅ Professional tone (when formal is used)
- ✅ Security concepts explained reasonably
- ✅ Natural Turkish expressions used

#### Issues:
- ❌ Formality inconsistency culturally problematic
  - Turkish business culture values formal address
  - Mixing sen/siz is considered unprofessional
- ⚠️ Some metaphors could be more culturally adapted

---

## 9. Grammar and Orthography

### Grammar: ✅ Generally Good
- Mostly correct vowel harmony
- Proper agglutination
- Correct case suffixes

**Examples:**
```json
"panoya"  // pano-ya (to clipboard) ✅
"kopyalandı"  // kopyala-n-dı (was copied) ✅
"şifrelenmiş"  // şifrele-n-miş (encrypted) ✅
```

### Orthography: ✅ Excellent
- Turkish characters correct (ç, ğ, ı, İ, ö, ş, ü)
- Proper capitalization
- Correct dotted/dotless I usage

---

## 10. Length and Layout Considerations

### UI Space Efficiency: ⚠️ Variable
Turkish text can be significantly longer due to agglutination:

**Examples:**
```json
// Short:
"Close": "Kapat" (5 chars vs 5) ✅

// Longer:
"Copy to clipboard": "Panoya kopyala" (14 chars vs 17) ⚠️
"Burn this secret": "Bu gizli mesajı yak" (19 chars vs 16) ⚠️

// Very long compound words possible:
"burn_this_secret_confirm_hint": "Gizli mesajı yakmak kalıcıdır ve geri alınamaz"
```

**Recommendation:** Test UI with actual Turkish text

---

## 11. Recommendations for Improvement

### Priority: CRITICAL ⚠️
1. **Standardize Formality Level (Sen vs Siz)**
   - **DECISION NEEDED:** Choose one
   - **Recommendation: Use Siz (formal)** for security application
   - **Impact:** Affects ~50% of strings
   - **Urgency:** Must fix before production

**Conversion Examples:**
```
Informal → Formal conversions needed:

"Hesabın" → "Hesabınız"
"mesajın" → "mesajınız"
"sana" → "size"
"senin" → "sizin"
"yazmadın" → "yazmadınız"
"bakıyorum" → "bakıyorum" (keep for question, or make "bakıyorsunuz")
```

### Priority: HIGH
2. **Complete Untranslated Strings**
   ```json
   "incoming_button_creating": "Creating"  // → "Oluşturuluyor..."
   "learn_more": "Learn more"  // → "Daha fazla bilgi"

   // Colonel section - translate all admin strings
   ```

3. **Fix Email Template Formality**
   - All emails must be fully formal
   - Critical for business credibility

### Priority: MEDIUM
4. **Review and Naturalize Some Phrases**
   ```json
   // Current:
   "button_generate_secret": "Veya rastgele parola oluştur"
   // Better:
   "button_generate_secret": "Rastgele Parola Oluştur"

   // Current:
   "careful_only_see_once": "dikkat: sadece bir defa gösterilecek."
   // Better:
   "careful_only_see_once": "Dikkat: Bu mesaj sadece bir kez gösterilecek."
   ```

5. **Standardize "Link" vs "Bağlantı"**
   - Decide whether to use English "link" or Turkish "bağlantı"
   - Current uses both - choose one for consistency

---

## 12. Testing Recommendations

1. **Native Speaker Review - CRITICAL**
   - Have Turkish IT professionals review
   - Finalize sen/siz decision with target audience input
   - Verify naturalness of technical terms

2. **Formality Consistency Audit**
   - Check every string for formality
   - Document which form is used
   - Apply chosen form consistently

3. **UI Testing**
   - Test longer Turkish compounds in UI
   - Verify Turkish character display (ç, ğ, ı, İ, ö, ş, ü)
   - Test on Turkish locale systems

4. **Email Testing**
   - Send test emails in Turkish
   - Verify formality is professional
   - Check rendering on Turkish email clients

---

## 13. Comparison with English

### Translation Approach: Mostly Direct
- Generally faithful to English
- Some cultural adaptations
- Technical terms appropriately localized

### Examples of Good Translation:
```json
// English: "Burn this secret"
// Turkish: "Bu gizli mesajı yak"
// Analysis: Direct but clear, "yak" (burn) works in Turkish context

// English: "Oops!"
// Turkish: "Eyvah!"
// Analysis: ⭐ Excellent cultural adaptation

// English: "One-time access"
// Turkish: "Tek Seferlik Erişim"
// Analysis: ✅ Natural Turkish
```

### Examples Needing Improvement:
```json
// English: "Dashboard"
// Turkish: "Hesabım" (My Account)
// Analysis: Inconsistent - could be "Pano" or "Kontrol Paneli"

// English: "Careful: We'll only show it once"
// Turkish: "dikkat: sadece bir defa gösterilecek."
// Analysis: Too terse, lacks subject
// Better: "Dikkat: Bu mesaj sadece bir kez gösterilecek."
```

---

## 14. Standout Examples

### Well-Translated:
```json
"one_time_warning": "Bu sayfadan ayrıldığınızda veya yenilediğinizde, bu gizli mesaj kalıcı olarak silinecek ve hiç kimse tarafından kurtarılamayacaktır."
```
**Why:** Clear, complete explanation, good formal structure, natural Turkish

```json
"copied_to_clipboard": "Panoya kopyalandı"
```
**Why:** Perfect Turkish agglutination, concise, clear

### Problematic:
```json
"your_secret_message": "Gizli mesajın:"  // Informal
```
**Should be:** "Gizli mesajınız:" (Formal)

```json
"tagline2": "Hassas bilgilerinizi sohbet geçmişinizde veya e-postalarınızda saklamayın."
```
**Issue:** "sohbet" sounds informal while rest is formal
**Better:** "Hassas bilgilerinizi sohbetlerinizde veya e-postalarınızda saklamayın."

---

## 15. Turkish Language-Specific Features

### Vowel Harmony: ✅ Mostly Correct
Turkish requires vowels in suffixes to harmonize with root word:

```json
"panoya" // pano (back vowel) + ya (back vowel harmony) ✅
"kopyalandı" // kopya + landı (harmony) ✅
```

### Dotted/Dotless I: ✅ Correct
Turkish distinguishes İ/i and I/ı:

```json
"şifrelenmiş" // lowercase ı (dotless) ✅
"İmza" // capital İ (dotted) would be correct if used
```

### Agglutination: ✅ Good
Turkish builds words with multiple suffixes:

```json
"kopyalandı" = kopya-la-n-dı
// copy + verb marker + passive + past tense ✅
```

---

## 16. Conclusion

The Turkish translation is of **good quality** with significant room for improvement. The most critical issue is formality consistency (sen/siz).

### Strengths Summary:
1. ✅ Mostly complete (95%)
2. ✅ Good technical terminology
3. ✅ Proper Turkish grammar (agglutination, vowel harmony)
4. ✅ Correct use of Turkish characters
5. ✅ Some excellent cultural adaptations

### Critical Issues:
1. ❌ **MAJOR: Inconsistent sen/siz formality** - MUST BE FIXED
2. ❌ Untranslated strings ("Creating", "Learn more", colonel section)
3. ❌ Email templates mix formal/informal

### Required Actions Before Production:
1. **CRITICAL:** Standardize to formal (siz) throughout
2. Complete all untranslated strings
3. Fix email template formality
4. Native speaker review

### Overall Assessment:
**NOT production-ready** without formality fixes. Current state: 7/10.
**After fixes:** Could reach 8.5-9/10.

The foundation is good, but consistency issues significantly impact professionalism. With dedicated formality standardization pass, this translation can be excellent.

---

## Appendix A: Sen/Siz Conversion Guide

### Informal (Sen) → Formal (Siz) Conversions:

| Informal | Formal |
|----------|--------|
| senin | sizin |
| sana | size |
| seni | sizi |
| -n (possessive) | -nız/-niz |
| -ın/-in | -ınız/-iniz |
| -dın/-din | -dınız/-diniz |

### Example Conversions:
```
"Hesabın" → "Hesabınız" (your account)
"mesajın" → "mesajınız" (your message)
"yazmadın" → "yazmadınız" (you didn't write)
"sana" → "size" (to you)
"senin" → "sizin" (your)
```

---

## Appendix B: Recommended Terminology

| English | Current Turkish | Recommended |
|---------|----------------|-------------|
| Secret | Gizli Mesaj | ✅ Good |
| Password | Parola | ✅ Standard |
| Passphrase | Parola | Consider "Parola İfadesi" |
| Link | Link/Bağlantı | Choose one consistently |
| Burn | Yak | ✅ Works |
| Dashboard | Hesabım | "Pano" or "Kontrol Paneli" |
| View | Görüntüle | ✅ Good |
| Copy | Kopyala | ✅ Standard |

---

**Report prepared by:** Translation Quality Analysis System
**Methodology:** Comparative analysis, linguistic review, Turkish grammar validation, formality analysis
**Next review:** REQUIRED after formality standardization; recommended after completing untranslated strings
**Critical Note:** ⚠️ Formality inconsistency is a blocking issue for production release
