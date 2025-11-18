# PHASE 1: CRITICAL ANALYSIS OF CREATE-SECRET EXPERIENCE

## Executive Summary

OneTimeSecret's create-secret experience is a **form-heavy, configuration-first interface** that presents users with multiple options upfront before they've even entered their secret. The current design assumes users understand concepts like TTL, passphrases, and custom domains immediately upon arrival.

This analysis examines what works, what doesn't, and what assumptions we're making about user needs—preparing the foundation for a redesign that prioritizes clarity, speed, and confidence.

---

## 1. CURRENT IMPLEMENTATION OVERVIEW

### The User Journey (Public Homepage)

**Landing State:**
- User arrives at homepage (`Homepage.vue`)
- Sees taglines (if unauthenticated): marketing copy about what OneTimeSecret does
- Immediately presented with `SecretForm.vue` containing:
  - Large textarea (empty, 200-400px height)
  - Passphrase field (with visibility toggle)
  - Expiration dropdown (pre-selected to 7 days)
  - Split button: "Create Link" / "Generate Password"
  - Pro tip: "A secret can be anything—passwords, API keys, etc."

**Create Flow:**
1. User types/pastes secret into textarea
2. (Optionally) configures passphrase
3. (Optionally) changes expiration time
4. Clicks "Create Link"
5. Frontend validates (Zod schema)
6. API POST to `/api/v2/secret/conceal`
7. Backend validates extensively
8. Secret + Metadata pair created
9. Secret encrypted and stored
10. User redirected to `/receipt/{metadata_key}`

**Generate Password Flow:**
1. User clicks "Generate Password" button
2. Textarea is hidden, replaced with icon + description
3. User configures passphrase/expiration (same fields)
4. Clicks "Generate Password"
5. API POST to `/api/v2/secret/generate`
6. Backend generates random password (12 chars by default)
7. Same storage/encryption process
8. User redirected to `/receipt/{metadata_key}`

### Technical Architecture

**Frontend Stack:**
- Vue 3 Composition API
- TypeScript with Zod validation
- Pinia for state management
- Tailwind 4.1 for styling
- Axios for API communication

**Key Components:**
- `SecretForm.vue` (L444): Main form orchestrator
- `SecretContentInputArea.vue`: Textarea with character counter
- `useSecretForm.ts` (L152): Form state + validation
- `useSecretConcealer.ts` (L112): Submission workflow
- `usePrivacyOptions.ts`: TTL/passphrase UI logic
- `useDomainDropdown.ts`: Custom domain selection

**Backend Stack:**
- Ruby/Sinatra API
- Redis for data storage
- AES-256 encryption
- Rate limiting via Rack middleware

**Key Backend Files:**
- `apps/api/v2/controllers/secrets.rb`: Request handlers
- `apps/api/v2/logic/secrets/base_secret_action.rb` (L322): Business logic
- `apps/api/v2/models/secret.rb`: Secret model + encryption
- `apps/api/v2/models/metadata.rb`: Metadata model

---

## 2. DATA MODEL & VALIDATION RULES

### Secret Model

**Core Fields:**
```ruby
custid            # Customer ID or 'anon'
state             # 'new', 'viewed', 'received', 'burned'
value             # Encrypted secret content (AES-256)
metadata_key      # Link to metadata record
value_checksum    # SHA256 hash of plaintext
value_encryption  # 0=none, 1=v1, 2=v2 (current)
lifespan          # TTL in seconds
share_domain      # Custom domain (optional)
passphrase        # Hashed passphrase (if protected)
truncated         # Boolean flag if exceeded size limit
```

**Encryption:**
- Algorithm: AES-256 with SHA256-based key derivation
- Key components: `global_secret + secret_key + passphrase_temp`
- Fallback support for rotated secrets
- Size limits enforced per plan with 0-20% random fuzz

**Size Constraints by Plan:**
- Anonymous: 100KB max
- Basic: 1MB max
- Identity: 10MB max

### Metadata Model

**Core Fields:**
```ruby
key              # Unique identifier (for URLs)
custid           # Creator's customer ID
state            # Mirrors secret state
secret_key       # Link to secret
secret_ttl       # Secret's TTL
lifespan         # Metadata TTL (2x secret TTL)
share_domain     # Custom domain (optional)
passphrase       # Hash of passphrase (if protected)
recipients       # Email addresses (optional)
```

**Lifespan Strategy:**
- Metadata lives 2x longer than secret
- Allows showing "secret expired" page after burnout
- Default: secret 7 days, metadata 14 days

### Validation Rules

**Frontend Validation (Zod Schema):**
```typescript
secret: z.string().min(1)                    // Required, non-empty
ttl: z.number().min(1)                       // Required, positive
passphrase: z.string()                       // Optional (unless config requires)
recipient: optionalEmail                     // Optional, validated format
share_domain: z.string()                     // Optional
```

**Additional Frontend Validation:**
- Passphrase minimum length (if configured)
- Passphrase maximum length (default: 128)
- Passphrase complexity (if enabled):
  - At least one uppercase letter
  - At least one lowercase letter
  - At least one number
  - At least one symbol from `!@#$%^&*()_+-=[]{};':"\\|,.<>/?~\``

**Backend Validation (Ruby):**
- Rate limiting: `create_secret` event tracked per session/customer
- Rate limiting: `email_recipient` event tracked if recipient provided
- Secret kind validation (conceal vs generate)
- TTL bounds enforcement:
  - Min: 60 seconds (from config)
  - Max: Plan-dependent (7d/14d/30d for anon/basic/identity)
- Email validation via Truemail gem
- Domain validation (must be legitimate CustomDomain)
- Passphrase validation (same rules as frontend)
- Anonymous users cannot send emails

---

## 3. AUTHENTICATION DEPENDENCIES & SECURITY

### Authentication Model

**Anonymous Access:**
- Fully supported for secret creation
- Default customer: `cust.anonymous?` returns true
- Limited plan features (7d TTL max, 100KB size max)
- Cannot send email notifications
- No custom domains

**Authenticated Access:**
- Session-based (cookies)
- Basic auth (username:apitoken)
- Unlocks higher plan limits
- Enables email notifications
- Enables custom domains (Identity plan)

**Authentication is NOT required for:**
- Creating secrets
- Viewing secrets
- Generating passwords

**Authentication IS required for:**
- Sending email notifications
- Using custom domains (ownership validation)
- API access
- Viewing secret history

### Security Measures

**CSRF Protection:**
- `check_shrimp!()` validates CSRF token on POST requests
- Token obtained from `/api/v2/validate-shrimp` endpoint

**Rate Limiting:**
- Per session/customer tracking
- Two events monitored: `create_secret`, `email_recipient`
- Disabled for paid plans
- Enforcement via `limit_action` method

**Encryption at Rest:**
- AES-256 encryption for secret values
- SHA256 key derivation: `global_secret + secret_key + passphrase`
- Passphrase hashed with salt (not stored plaintext)
- Support for key rotation (fallback to old keys)

**Input Validation:**
- Frontend: Zod schema validation
- Backend: Comprehensive `raise_concerns` method
- Email validation: Truemail gem (DNS MX record checks)
- Domain whitelist: Only validated CustomDomain objects

**Size Limits with Anti-Inference:**
- Hard limits per plan (100KB/1MB/10MB)
- Truncation with 0-20% random fuzz
- Prevents attackers from inferring secret length
- `truncated` flag set on secret

---

## 4. MANDATORY vs CONFIGURABLE vs DEFAULTED

### Mandatory Fields (Cannot Be Empty)

**For "Create Link" Flow:**
1. **Secret content** (`secret`)
   - Frontend validation: `min(1)`
   - Backend validation: Must not be empty
   - User-facing: Textarea required to have content
   - Button disabled if textarea empty

**For "Generate Password" Flow:**
1. Nothing! Password generation has zero mandatory user inputs
   - Secret is auto-generated
   - All other fields have defaults

### Configurable Fields (User Can Change)

1. **Passphrase** (`passphrase`)
   - Default: Empty (no passphrase)
   - Can be configured: Optional → Required (via `site.secret_options.passphrase.required`)
   - Visibility toggle: Eye icon shows/hides text
   - Constraints: Min/max length, complexity requirements

2. **Expiration Time** (`ttl`)
   - Default: 7 days (604,800 seconds)
   - Options: 60s, 5m, 30m, 1h, 4h, 12h, 1d, 3d, 7d, 14d, 30d
   - Plan-filtered: Anonymous sees up to 7d, Basic up to 14d, Identity up to 30d
   - Dropdown pre-selected to default

3. **Recipient Email** (`recipient`) - **HIDDEN ON PUBLIC HOMEPAGE**
   - Default: Empty (no email)
   - Shown only when `withRecipient={true}` (e.g., on authenticated dashboard)
   - Requires authentication to send
   - Rate-limited separately

4. **Share Domain** (`share_domain`) - **HIDDEN ON PUBLIC HOMEPAGE**
   - Default: Canonical domain (e.g., `onetimesecret.com`)
   - Shown only on canonical domain when custom domains exist
   - Requires ownership validation
   - Identity plan feature

### Defaulted Fields (Auto-Populated)

1. **TTL**: 7 days (from `site.secret_options.default_ttl`)
2. **Passphrase**: Empty string
3. **Recipient**: Empty string
4. **Share Domain**: Current domain or canonical
5. **Customer ID**: `anon` for anonymous users

### Configuration Hierarchy

**System Defaults (lib/onetime/config.rb):**
```yaml
secret_options:
  default_ttl: 7.days
  ttl_options: [60s, 5m, 30m, 1h, 4h, 12h, 1d, 3d, 7d, 14d, 30d]
  passphrase:
    required: false
    minimum_length: nil
    maximum_length: 128
    enforce_complexity: false
  password_generation:
    default_length: 12
    character_sets:
      uppercase: true
      lowercase: true
      numbers: true
      symbols: false
      exclude_ambiguous: true
```

**Plan Overrides (lib/onetime/plan.rb):**
- Anonymous: TTL max 7d, size max 100KB
- Basic: TTL max 14d, size max 1MB
- Identity: TTL max 30d, size max 10MB

---

## 5. WHAT WORKS WELL

### ✅ Strengths of Current Implementation

**1. Clear Primary Action**
- The "Create Link" button is visually prominent
- Form is centered and focused
- No navigation clutter on the page

**2. Smart Defaults**
- 7-day expiration is reasonable for most use cases
- Optional passphrase doesn't force users to think about it
- Empty recipient field doesn't create noise

**3. Progressive Disclosure (Partial)**
- Recipient email hidden on public homepage (shown only when needed)
- Custom domain selection hidden unless multiple domains exist
- Pro tip displayed for unauthenticated users

**4. Accessibility Foundations**
- Screen reader labels (`sr-only` for textarea label)
- ARIA attributes: `aria-invalid`, `aria-errormessage`, `aria-busy`
- Keyboard navigation: Tab order logical
- Focus management: Passphrase visibility toggle has focus ring
- Unique IDs: Generated for proper label associations

**5. Real-Time Feedback**
- Character counter on textarea (shows 0/10,000)
- Passphrase visibility toggle (immediate response)
- Button disabling (prevents accidental submission)

**6. Dual-Purpose Interface**
- Split button elegantly handles two distinct flows: Create Link vs Generate Password
- Textarea hides when generating passwords (avoids confusion)

**7. Robust Backend Validation**
- Comprehensive security checks
- Rate limiting to prevent abuse
- Plan-aware constraints
- Email validation via DNS MX records

**8. Excellent Encryption Design**
- AES-256 with proper key derivation
- Passphrase integration into encryption key
- Support for key rotation
- Size limits with anti-inference protection

---

## 6. WHERE USERS LIKELY EXPERIENCE FRICTION

### 🚨 Critical Friction Points

**1. Cognitive Overload on First Impression**
- **Problem**: Users see 4+ form fields immediately, even for a 2-step task (paste secret → get link)
- **Evidence**:
  - Passphrase field visible but empty (is it required?)
  - Expiration dropdown pre-selected but visible (do I need to change it?)
  - "Pro tip" adds reading burden
  - Character counter visible before typing
- **Impact**: Decision paralysis—users must evaluate multiple options before acting
- **Mental Model Mismatch**: Users think "paste text → get link" but see a complex form

**2. Passphrase Ambiguity**
- **Problem**: Passphrase field is visible but not clearly required/optional
- **Evidence**:
  - No asterisk unless `required: true` in config
  - Label says "Secret Passphrase" (what does that mean?)
  - Hints show min-length/complexity BEFORE user interacts (premature)
- **Impact**: Users wonder: "Do I need this? What is it for? Is my secret less secure without it?"
- **Confusion**: Passphrase vs password (are they different?)

**3. Expiration Dropdown Friction**
- **Problem**: Users must understand TTL concept and evaluate 11 options
- **Evidence**:
  - Dropdown has 11 choices (60s to 30d)
  - Pre-selected to 7d, but visible (draws attention)
  - Label "Secret Expiration" requires understanding of ephemeral secrets
- **Impact**: Users must decide "how long should this exist?" before they've even created it
- **Anxiety**: "What if I choose wrong? Will my recipient miss it?"

**4. Empty Textarea Ambiguity**
- **Problem**: Large empty textarea (200-400px) with placeholder text is intimidating
- **Evidence**:
  - Textarea dominates the visual hierarchy
  - Placeholder: Generic textarea appearance
  - Character counter shows "0 / 10,000" before typing (feels like homework)
- **Impact**: Users may not know what to put in (despite pro tip)
- **Blank Slate Anxiety**: Large empty space feels like a commitment

**5. Split Button Confusion**
- **Problem**: "Create Link" and "Generate Password" are visually equal but functionally different
- **Evidence**:
  - Button has two actions (dropdown-style split button)
  - No clear indication which is primary vs secondary
  - Switching modes hides textarea (surprising behavior)
- **Impact**: Users may accidentally click "Generate Password" and get confused when textarea disappears
- **Discoverability**: Users may not realize password generation exists

**6. No Context for Options**
- **Problem**: Configuration options lack contextual help
- **Evidence**:
  - No tooltip for passphrase explaining protection benefit
  - No tooltip for expiration explaining why shorter is safer
  - No inline help for "What happens after expiration?"
- **Impact**: Users make uninformed decisions or ignore options entirely

**7. Error Handling is Backend-Heavy**
- **Problem**: Most validation errors only appear after backend response
- **Evidence**:
  - Frontend validates schema, but passphrase complexity validated on submit
  - Rate limiting errors only shown after API call
  - Email validation only on backend (via Truemail)
- **Impact**: Slow feedback loop—users wait for API round-trip to see errors
- **Frustration**: "Why didn't you tell me this before I clicked?"

**8. Mobile Experience Assumptions**
- **Problem**: Form is optimized for desktop interaction patterns
- **Evidence**:
  - Large textarea assumes mouse-based selection/pasting
  - Expiration dropdown requires precise tapping
  - Passphrase visibility toggle is small (24x24px icon)
  - Split button complexity on small screens
- **Impact**: Mobile users (who may be in a hurry) face extra friction

**9. No Progressive Success Feedback**
- **Problem**: Users have no idea if submission is working until redirect
- **Evidence**:
  - `isSubmitting` shows loading state on button
  - No progress indicator for encryption, storage, etc.
  - No confirmation message before redirect
- **Impact**: Anxiety during 0.5-2s wait time—"Did it work? Should I click again?"

**10. Generate Password Flow is Hidden**
- **Problem**: Password generation feature is buried in split button
- **Evidence**:
  - Secondary action in button (dropdown)
  - No visual cue on homepage that this exists
  - Modal-like behavior (hides textarea) is unexpected
- **Impact**: Users who want password generation may never discover it
- **Learnability**: Feature requires exploration to find

---

## 7. ASSUMPTIONS ABOUT USER NEEDS

### Explicit Assumptions (Revealed by Current Design)

**1. Users understand ephemeral secrets immediately**
- Design assumes: Users know what "secret expiration" means
- Reality: Many users may think "why does it expire? Can I extend it?"
- Challenge: OneTimeSecret's core value prop (security via ephemerality) is assumed knowledge

**2. Users can evaluate security options upfront**
- Design assumes: Users know if they need a passphrase
- Reality: Users don't know threat model—"Is email secure? Is Slack secure?"
- Challenge: Passphrase decision requires understanding attack vectors

**3. Users have their secret ready to paste**
- Design assumes: Users arrive with secret in clipboard
- Reality: Users may be composing the secret, switching between apps, or typing from memory
- Challenge: Large empty textarea may feel premature

**4. Users prefer configuration to defaults**
- Design assumes: Showing all options upfront empowers users
- Reality: Most users want "just give me a link" with zero config
- Challenge: 80/20 rule—most users want defaults, 20% want control

**5. Users will read the pro tip**
- Design assumes: Taglines and pro tip educate users
- Reality: Users in a hurry (most users) skip explanatory text
- Challenge: Critical onboarding info may be ignored

**6. Users understand the difference between "Create Link" and "Generate Password"**
- Design assumes: Split button labels are self-explanatory
- Reality: Users may not realize these are fundamentally different workflows
- Challenge: "Create Link" sounds like it creates a password, but it doesn't

**7. Users are willing to trust the system with sensitive data**
- Design assumes: Users will paste secrets immediately
- Reality: Trust must be built—"Is this site legit? Where does my secret go?"
- Challenge: No trust indicators visible on form (HTTPS badge, encryption explanation, etc.)

### Implicit Assumptions (Revealed by Implementation Choices)

**8. Desktop-first mental model**
- Evidence: Form layout optimized for mouse interaction, large textarea
- Reality: Mobile usage is growing—users may be on phones in emergencies

**9. Single-recipient model**
- Evidence: Recipient field is singular (though backend supports array)
- Reality: Users may want to share with multiple people

**10. English-language proficiency**
- Evidence: Labels like "Secret Expiration" use formal language
- Reality: International users may need simpler language or visual cues

**11. Technical literacy**
- Evidence: Terms like "passphrase," "expiration," "TTL" assume technical background
- Reality: Non-technical users (e.g., HR sending temp passwords) may struggle

**12. Users share secrets immediately after creation**
- Evidence: Redirect to receipt page assumes user wants link now
- Reality: Users may want to review, test, or delay sharing

---

## 8. TECHNICAL CONSTRAINTS SHAPING REDESIGN

### Hard Constraints (Cannot Change)

**1. Stateless API**
- No server-side sessions for anonymous users
- Each request must be self-contained
- Implication: Cannot save partial form state server-side

**2. Encryption Architecture**
- Secret value encrypted with: `global_secret + secret_key + passphrase`
- Passphrase is part of encryption key (not just access control)
- Implication: Cannot change passphrase after creation

**3. One-Time Model**
- Secrets are write-once, read-once
- No editing after creation
- Implication: Must get creation flow right the first time

**4. Plan Constraints**
- TTL/size limits enforced per plan
- Anonymous users heavily restricted
- Implication: Cannot offer features that require authentication to anonymous users

**5. Backend Validation is Authoritative**
- Frontend validation is UX enhancement only
- Backend re-validates everything
- Implication: Must handle backend validation errors gracefully

### Soft Constraints (Can Be Changed, But Difficult)

**6. Current Form Schema**
- Changing field names requires frontend + backend coordination
- Existing secrets expect current schema
- Implication: API contract changes require versioning

**7. Vue 3 + TypeScript + Tailwind Stack**
- Rewrite in different framework is impractical
- Must work within Vue ecosystem
- Implication: Interaction patterns must fit Vue reactivity model

**8. Character Counter on Textarea**
- Integrated into `SecretContentInputArea.vue`
- Shows remaining characters live
- Implication: Large refactors to textarea affect multiple composables

**9. Split Button Component**
- Custom component handling dual actions
- Used across multiple views
- Implication: Changing button behavior affects other pages

**10. Internationalization (i18n)**
- All text uses `$t()` translation keys
- Changing copy requires updating locale files
- Implication: Conversation-style UI needs new translation keys

### Opportunities (Constraints That Enable Better UX)

**11. Plan System Enables Progressive Disclosure**
- Can show advanced features only to authenticated users
- Can simplify anonymous experience
- Implication: Redesign can leverage plan system for staged complexity

**12. Backend Handles Password Generation**
- Frontend just needs to trigger API call
- No client-side password generation logic
- Implication: Can simplify generate flow to single button

**13. Custom Domain System is Modular**
- Domain selection is composable (`useDomainDropdown`)
- Can be shown/hidden independently
- Implication: Can defer domain selection to advanced options

**14. Passphrase is Optional by Default**
- Config: `passphrase.required: false`
- Most deployments don't require passphrases
- Implication: Can hide passphrase by default, show on demand

**15. Validation is Composable**
- `useSecretForm.ts` handles validation
- Can be extended for new validation rules
- Implication: Can add conversational validation patterns

---

## 9. CRITICAL INSIGHTS FOR REDESIGN

### User Psychology

**1. Peak-End Rule**
- Users remember the most intense moment and the final moment
- Current design: Intense = form complexity, End = redirect (abrupt)
- Redesign opportunity: Make intensity peak at secret creation success, end with clear call-to-action

**2. Zeigarnik Effect**
- People remember uncompleted tasks better than completed ones
- Current design: Form looks incomplete (empty fields) even after submission
- Redesign opportunity: Show progressive completion states

**3. Hick's Law**
- Time to decide increases with number of options
- Current design: 4+ simultaneous decisions (passphrase? expiration? generate?)
- Redesign opportunity: Reduce choices to 1-2 at any given moment

**4. Progressive Disclosure**
- Show only what's needed, when it's needed
- Current design: All options visible upfront
- Redesign opportunity: Start minimal, reveal options on demand

### Technical Opportunities

**5. Validation Can Be Conversational**
- Current: Silent validation on submit
- Redesign opportunity: Inline validation with helpful messages

**6. State Management is Ready**
- `useSecretForm` already handles reactive state
- Redesign opportunity: Add wizard/step state without major refactor

**7. Backend is Flexible**
- API accepts optional fields
- Redesign opportunity: Send only what user configured

**8. Mobile-First is Achievable**
- Tailwind 4.1 has excellent mobile utilities
- Redesign opportunity: Design for thumb-friendly interaction

### Strategic Insights

**9. Two Distinct Personas**
- **Quick Sharer**: "Just give me a link" (80% of users)
- **Security-Conscious**: "I need passphrase + short TTL" (20% of users)
- Current design: Tries to serve both equally
- Redesign opportunity: Optimize for Quick Sharer, accommodate Security-Conscious

**10. Trust is Implicit**
- No visible security indicators
- Users must infer safety from URL (HTTPS), brand, design
- Redesign opportunity: Make security visible without being preachy

---

## 10. SUMMARY: PROBLEM DEFINITION

### The Core Problem

**The current create-secret experience optimizes for configuration flexibility at the expense of speed and clarity.**

Users arrive with a simple mental model:
1. Paste sensitive text
2. Get a link
3. Share it

But are presented with a complex form requiring:
1. Decide if passphrase is needed
2. Evaluate 11 expiration options
3. Understand "Create Link" vs "Generate Password"
4. Navigate validation errors on submit
5. Wait for redirect

### The Redesign Opportunity

**Create a conversational, progressive experience that:**
- Gets users to their first link in 2 clicks
- Reveals options contextually when needed
- Builds trust through transparency
- Scales from simple to advanced use cases
- Works beautifully on mobile

### Hypothesis

**By prioritizing input-first, defaults-first, and progressive disclosure, we can reduce time-to-first-link by 50% while increasing user confidence in the security of their secret.**

---

## Next Steps → PHASE 2

With this foundation, we can now:
1. Define user scenarios (developer, support agent, personal use)
2. Map mental models vs. actual flow
3. Identify points of confusion and abandonment
4. Propose 2-3 fundamentally different interaction models

**Key Questions for Phase 2:**
- What does "conversational" mean in practice?
- How do we progressively disclose options without hiding important features?
- How do we build trust in the first 3 seconds?
- What changes for mobile vs. desktop?

---

**Document Status:** ✅ Complete
**Next Phase:** PHASE 2 - Define Problem Space
**Date:** 2025-11-18
