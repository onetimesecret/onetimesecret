# PHASE 1: CURRENT STATE ANALYSIS
## OneTimeSecret Create-Secret Experience Redesign

**Date**: 2025-11-18
**Branch**: `claude/redesign-create-secret-01VCPSHrMm9voh36zpcZTmrD`

---

## EXECUTIVE SUMMARY

OneTimeSecret's create-secret feature is **technically excellent** but has **UX optimization opportunities**. The implementation demonstrates strong security architecture, accessibility foundations, and flexible configuration. However, the interface prioritizes feature completeness over focused simplicity, creating friction points for first-time and mobile users.

**Architecture Overview**:
- **Frontend**: Vue 3 + TypeScript with Zod validation, Pinia stores, composable logic
- **Backend**: Ruby/Sinatra with encryption, rate limiting, plan enforcement
- **Security**: AES-256 encryption, view-once guarantee, configurable constraints
- **Access**: Anonymous-friendly (no auth required), paid plans for advanced features

---

## 1. WHAT WORKS WELL

### 1.1 **Zero-Friction Entry** ✨
**Finding**: Users can create secrets without signup/login (configurable)

**Evidence**:
- `etc/config.example.yaml:141` - `authentication:required: false`
- Anonymous users get full create functionality
- Rate limiting prevents abuse without blocking legitimate use

**Why This Matters**:
Users in crisis situations ("I need to share this DB password RIGHT NOW") don't face authentication barriers. This reduces time-to-value to near-zero.

**Design Strength**: Respects the "jobs to be done" framework—users hire OneTimeSecret to solve an immediate problem, not to create another account.

---

### 1.2 **Dual-Mode Interface** (Create vs Generate)
**Finding**: Single interface supports both user-provided content and password generation

**Evidence**:
- `src/components/SplitButton.vue` - Toggles between "Create Link" and "Generate Password"
- No context switching required—users stay in same mental space
- Generate mode doesn't require secret content input

**Why This Matters**:
Addresses two distinct user needs without fragmenting the experience:
1. "I have sensitive text to share" → Conceal mode
2. "I need a secure password to share" → Generate mode

**Design Strength**: Progressive disclosure done right—advanced feature (Generate) doesn't clutter primary use case (Create).

---

### 1.3 **Real-Time Validation Feedback**
**Finding**: Frontend validation mirrors backend constraints with immediate feedback

**Evidence**:
- `src/composables/useSecretForm.ts:23-49` - Zod schema validation
- `apps/api/v2/logic/secrets/base_secret_action.rb:168-216` - Server-side validation
- Character counter in textarea shows approaching limits
- Passphrase complexity shown before submission

**Why This Matters**:
Users learn system constraints during input, not after submission failure. Reduces "submit → error → fix → resubmit" loops.

**Design Strength**: Proactive guidance vs reactive error messages.

---

### 1.4 **Accessibility Foundation**
**Finding**: Strong ARIA support, keyboard navigation, dark mode, screen reader compatibility

**Evidence**:
- `src/components/secrets/form/SecretContentInputArea.vue:48` - `aria-label` on textarea
- `src/components/CustomDomainPreview.vue:185-220` - ARIA listbox pattern for domain dropdown
- `src/components/SplitButton.vue:134` - Keyboard handling (Enter, Escape, arrows)
- Full dark mode support via Tailwind classes

**Why This Matters**:
Accessibility isn't a retrofit—it's baked into component design. Benefits all users (keyboard shortcuts speed up power users, not just accessibility tool users).

**Design Strength**: Follows modern a11y patterns (combobox, listbox, focus management).

---

### 1.5 **Progressive Disclosure of Complexity**
**Finding**: Advanced options hidden by default, revealed contextually

**Evidence**:
- Recipient field: `withRecipient` prop controls visibility
- Custom domains: Only shown if `productIdentity.isCanonical`
- Generate password options: Hidden unless user switches modes
- Pro tips: Conditional `withAsterisk` prop

**Why This Matters**:
Interface scales from simple ("paste secret, click create") to power user ("custom domain, recipient email, passphrase enforcement") without overwhelming beginners.

**Design Strength**: Layered complexity—users only see what's relevant to their current path.

---

### 1.6 **Configuration-Driven Flexibility**
**Finding**: Entire system behavior controlled via YAML config, allowing per-deployment customization

**Evidence**:
- `etc/config.example.yaml:119-142` - Auth settings
- `etc/config.example.yaml:secret_options` - TTL defaults, passphrase rules
- `apps/api/v2/logic/secrets/base_secret_action.rb:76-104` - Plan-based constraints

**Why This Matters**:
Same codebase supports:
- Public anonymous service (onetimesecret.com)
- Enterprise locked-down instance (auth required, passphrase mandatory)
- Custom branded deployments (custom domains, plans)

**Design Strength**: Separation of policy (config) from mechanism (code).

---

### 1.7 **Security-First Architecture**
**Finding**: Multiple layers of security with no shortcuts

**Evidence**:
- `apps/api/v2/models/secret.rb:114-191` - Encryption with randomized truncation
- `apps/api/v2/models/secret.rb:342` - Key derivation from global secret + secret key + passphrase
- View-once enforcement via state machine (`new` → `viewed` → `received` → destroyed)
- Metadata outlives secret (2x TTL) for audit without exposing content

**Why This Matters**:
Users trust OneTimeSecret with credentials, PII, financial data. Any security weakness would be catastrophic for reputation.

**Design Strength**: Defense in depth—encryption, TTL enforcement, rate limiting, state transitions.

---

## 2. WHERE USERS LIKELY EXPERIENCE FRICTION

### 2.1 **Cognitive Load of Vertical Form Layout**
**Problem**: Form presents all options simultaneously in single column

**Evidence**:
- `src/components/secrets/form/SecretForm.vue:100-200` - Textarea → Passphrase/Expiry grid → Recipient → Domain → Button
- On mobile: 5+ input fields stacked vertically = requires scrolling
- Visual hierarchy unclear—all fields appear equally important

**User Impact**:
- **First-time users**: "What do I need to fill out before clicking Create?"
- **Mobile users**: Scrolling to reach submit button breaks focus
- **Distracted users**: Forget what they've already configured mid-scroll

**Mental Model Mismatch**:
Users think: "I want to share this text" (1 action)
System presents: "Configure 5 settings" (feels like 5 actions)

**Friction Magnitude**: 🔴 HIGH for mobile, 🟡 MEDIUM for desktop

---

### 2.2 **Passphrase Field Positioning**
**Problem**: Passphrase appears before user understands what it protects

**Evidence**:
- `src/components/secrets/form/SecretForm.vue:135-175` - Passphrase in grid alongside expiration
- No contextual explanation of "Why would I set a passphrase?"
- Complexity rules shown but not "When should I use this?"

**User Impact**:
- **Confused users**: "Is this required? What happens if I skip it?"
- **Security-conscious users**: "Should I ALWAYS set a passphrase? Is it insecure not to?"
- **Friction point**: Pausing to decide slows down flow

**Mental Model Mismatch**:
Users don't think in terms of "encryption layers"—they think "How sensitive is this?"

**Design Anti-Pattern**: Form order doesn't match user's decision-making sequence.

**Friction Magnitude**: 🟡 MEDIUM—causes hesitation, not abandonment

---

### 2.3 **Expiration Selection UX**
**Problem**: Dropdown requires click → scan list → select (4 steps) for common action

**Evidence**:
- `src/composables/usePrivacyOptions.ts:68-94` - TTL options as dropdown
- Default: 7 days (may not match user intent)
- No "quick select" buttons for common durations

**User Impact**:
- **Time-sensitive users**: "I need this to expire in 5 minutes" requires dropdown navigation
- **Mobile users**: Dropdown UX on mobile is suboptimal (requires precision tapping)
- **Uncertainty**: "What should I choose?" → analysis paralysis

**Mental Model Mismatch**:
Users think in contexts, not durations:
- "This needs to last through the workday" → 8 hours
- "They'll read this immediately" → 5 minutes
- "Archive for compliance" → 30 days

Form presents: "60, 3600, 86400, 604800" (seconds)—requires mental math.

**Friction Magnitude**: 🟡 MEDIUM—usable but not optimal

---

### 2.4 **Mobile Submit Button Visibility**
**Problem**: Submit button at bottom requires scrolling, breaking visual connection to action

**Evidence**:
- Textarea + options + recipient = ~600-800px on mobile
- Button below fold → users must scroll to submit
- No sticky footer to keep button visible

**User Impact**:
- **Mobile workflow break**: Fill content → scroll down → find button → tap
- **Forget to submit**: Users paste content, get distracted, navigate away
- **Lost context**: By time they scroll to button, they've lost view of their content

**Mobile-Specific Pain**:
Desktop users see full form + button in viewport. Mobile users don't.

**Friction Magnitude**: 🔴 HIGH for mobile users (majority of traffic?)

---

### 2.5 **Character Counter Discoverability**
**Problem**: Counter only shows when >50% capacity or on hover (desktop)

**Evidence**:
- `src/components/secrets/form/SecretContentInputArea.vue:58-68` - Conditional visibility
- Mobile: Shows immediately (good)
- Desktop: Hidden until hover or 50% (inconsistent)

**User Impact**:
- **Uncertainty**: "How much can I paste here?"
- **Late discovery**: User pastes 15,000 chars, sees limit is 10,000
- **Data loss**: May not realize content was truncated

**Mental Model Mismatch**:
Users assume "if it fits in the box, it's accepted"—visual truncation in textarea doesn't communicate backend limits.

**Friction Magnitude**: 🟡 MEDIUM—only affects edge cases (large content)

---

### 2.6 **Recipient Email UX**
**Problem**: Feature hidden by default, requires authentication, provides no preview

**Evidence**:
- `src/components/secrets/form/SecretForm.vue:withRecipient` prop controls visibility
- `apps/api/v2/logic/secrets/base_secret_action.rb:150` - Requires authenticated user
- No email preview shown before submission

**User Impact**:
- **Discovery**: Users don't know email feature exists
- **Auth barrier**: Anonymous users can't use it (raises "Why can't I?" question)
- **No confirmation**: After submit, unclear if/when email was sent
- **Trust issue**: "What will the email say? Will it look suspicious?"

**Workflow Friction**:
If user wants to email secret but is anonymous:
1. Discover recipient field
2. Enter email
3. Submit
4. Get error: "Authentication required"
5. Create account
6. Return to form (lose state? Or preserved?)
7. Re-submit

**Friction Magnitude**: 🔴 HIGH—abandoned workflow likely

---

### 2.7 **Domain Selection Complexity**
**Problem**: Custom domain feature buried in footer, unclear value proposition

**Evidence**:
- `src/components/CustomDomainPreview.vue` - Shows domain dropdown in footer
- Only visible if canonical domain (most users won't see it)
- No explanation of "Why choose a different domain?"

**User Impact**:
- **Confusion**: "What does this do?"
- **Ignored**: Most users won't interact with it
- **Discovery**: Power users need this, but won't find it

**Mental Model Mismatch**:
UI presents as technical configuration. Users think in terms of "branding" or "trust signal" (e.g., share from company.com, not onetimesecret.com).

**Friction Magnitude**: 🟢 LOW—feature is niche, doesn't block primary flow

---

### 2.8 **Generate Password Mode Discovery**
**Problem**: Generate feature hidden in SplitButton dropdown

**Evidence**:
- `src/components/SplitButton.vue:185-220` - Dropdown menu contains mode switch
- Button label doesn't indicate dropdown exists (no visual chevron in some states)
- No onboarding hint: "You can also generate passwords"

**User Impact**:
- **Hidden value**: Users who need password generation don't discover it
- **Competitor loss**: User goes to separate password generator tool
- **Workflow inefficiency**: "I could've done this here?"

**Friction Magnitude**: 🔴 HIGH—feature abandonment due to discoverability

---

### 2.9 **Error State Handling**
**Problem**: Errors shown in sticky alert at top, lose context with field

**Evidence**:
- `src/components/secrets/form/SecretForm.vue:91-97` - BasicFormAlerts at top
- Field-level errors not inline (not visible in code)
- Error messages shown in alert = user must read → scroll to field → fix → scroll to submit

**User Impact**:
- **Context loss**: "Which field has the error?"
- **Multiple errors**: Alert may show 3 errors → fix first → scroll → fix second → repeat
- **Mobile pain**: Scrolling between alert and field is tedious

**Friction Magnitude**: 🟡 MEDIUM—depends on error frequency

---

### 2.10 **Receipt Page Transition**
**Problem**: After submit, navigation to `/receipt/:key` feels abrupt

**Evidence**:
- `src/composables/useSecretConcealer.ts:85` - `router.push('/receipt/...')`
- No transition feedback ("Encrypting your secret...")
- No confirmation moment ("Success! Here's your link")

**User Impact**:
- **Jarring**: Instant navigation feels like page error, not success
- **Confusion**: "Did it work? Where's my link?"
- **Learning curve**: New page layout requires re-orientation

**Mental Model Mismatch**:
Users expect: Submit → Confirmation → Link appears
System provides: Submit → New page with link (skips confirmation moment)

**Friction Magnitude**: 🟡 MEDIUM—doesn't block task but reduces satisfaction

---

## 3. ASSUMPTIONS ABOUT USER NEEDS

### 3.1 **Assumption: Users Understand Expiration**
**What We Assume**: Users know what TTL means and can choose appropriate duration

**Reality Check**:
- **Evidence for**: Most users familiar with "expires in X" (Snapchat, temp files)
- **Evidence against**:
  - Config offers 60s, 3600s, 86400s, 604800s (technical units, not human language)
  - No guidance: "Choose 5 min for immediate sharing, 7 days for async collaboration"
  - Default (7 days) may not match user intent for 90% of use cases

**Risk**: Users accept default without thinking, leading to:
- Secrets expire before recipient views (7 days too short)
- Secrets linger longer than necessary (7 days too long)

**What We Should Validate**:
- Survey actual TTL distribution (do users change default?)
- A/B test contextual defaults (email recipient = longer TTL?)
- Explore "expires after first view" vs time-based expiration

---

### 3.2 **Assumption: Users Can Assess Passphrase Necessity**
**What We Assume**: Users understand when passphrase adds security value

**Reality Check**:
- **Evidence for**: Security-conscious users know passphrases protect against link interception
- **Evidence against**:
  - No guidance on threat model (what attack does passphrase prevent?)
  - Complexity rules shown but not "why" passphrase matters
  - Optional field = "I'll skip this" default behavior

**Risk**:
- Users share highly sensitive content (SSNs, credentials) without passphrase
- False sense of security ("I used OneTimeSecret, it's encrypted!")
- Liability for service if breach occurs

**What We Should Validate**:
- Do users understand view-once ≠ encryption?
- Would "recommended for sensitive data" hint increase passphrase usage?
- Can we detect high-sensitivity content (pattern matching) and prompt passphrase?

---

### 3.3 **Assumption: Mobile Users Accept Scrolling**
**What We Assume**: Mobile form UX is acceptable despite vertical scrolling

**Reality Check**:
- **Evidence for**: Responsive design is implemented, fields stack properly
- **Evidence against**:
  - Submit button below fold = extra cognitive step
  - Distracted mobile users more likely to abandon mid-scroll
  - Competing services may have simpler mobile UX (competitive risk)

**Risk**:
- High mobile bounce rate (users paste content but never submit)
- Perception: "This is too complicated for mobile"
- Loss to competitors with mobile-optimized flows

**What We Should Validate**:
- Analytics: What % of mobile users scroll to submit button?
- Heatmaps: Where do mobile users tap/abandon?
- Competitor analysis: How do similar services handle mobile create flow?

---

### 3.4 **Assumption: Anonymous Users Don't Need Email Feature**
**What We Assume**: Email feature is power user / paid feature, not core to anonymous users

**Reality Check**:
- **Evidence for**: Sending emails requires sender identity (spam prevention)
- **Evidence against**:
  - Use case: "I want to send temp password to client"—natural to email it
  - Friction: User creates secret → copies link → opens email client → pastes link (manual)
  - Auto-email would save 2 steps, reduce copy/paste errors

**Risk**:
- Users expect "Share via email" button, don't find it, perceive as feature gap
- Workflow abandonment: "I'll just use Slack instead"

**What We Should Validate**:
- Survey users: "How do you share the link?" (email, Slack, SMS, in-person)
- A/B test: Show email field to all users, count conversions to signup
- Explore temporary email (disposable sender address) for anonymous users

---

### 3.5 **Assumption: Dual-Mode Interface Clarifies Options**
**What We Assume**: Users understand Create vs Generate modes and when to use each

**Reality Check**:
- **Evidence for**: SplitButton pattern is familiar (iOS share sheets, Google Docs)
- **Evidence against**:
  - Dropdown hidden unless clicked (discoverability issue)
  - No onboarding: "Not sure what to share? Generate a secure password"
  - Mode switch clears form state (potential data loss)

**Risk**:
- Users who need password generation never discover it
- Users accidentally switch modes and lose typed content (frustration)

**What We Should Validate**:
- Tooltip/hint on first visit: "Tip: You can generate passwords too"
- Analytics: What % of users switch modes? What % abandon after switching?
- Confirmation dialog: "Switching modes will clear your content. Continue?"

---

### 3.6 **Assumption: Users Trust Default Settings**
**What We Assume**: Defaults (7 days, no passphrase) reflect typical user needs

**Reality Check**:
- **Evidence for**: Config allows changing defaults (deployment-specific)
- **Evidence against**:
  - No data on "ideal" defaults for diverse use cases
  - Default = lazy choice for users (may not be optimal)

**Risk**:
- Defaults serve admins (max TTL = resource conservation) not users (ideal security posture)
- Users unknowingly create weaker secrets than needed

**What We Should Validate**:
- Contextual defaults based on content:
  - Contains "password" or "credential" → shorter TTL, prompt passphrase
  - Long content (>1000 chars) → longer TTL (assumes not immediate)
  - Email recipient specified → longer TTL (async sharing)

---

### 3.7 **Assumption: Receipt Page Is Sufficient Confirmation**
**What We Assume**: Navigating to `/receipt/:key` confirms success

**Reality Check**:
- **Evidence for**: Receipt shows link, metadata, burn option (comprehensive)
- **Evidence against**:
  - No "moment of success" (celebration, animation, clear confirmation)
  - Abrupt transition feels like error, not success
  - Users may not realize they've succeeded

**Risk**:
- User confusion: "Did it work?"
- Perception of instability: "The page just changed on me"
- No positive reinforcement (reduces trust)

**What We Should Validate**:
- Toast notification before navigation: "Secret created! Redirecting..."
- Success animation on receipt page: Checkmark, fade-in
- User sentiment analysis: "How did you feel when your secret was created?"

---

### 3.8 **Assumption: Real-Time Validation Is Helpful**
**What We Assume**: Showing errors before submission improves UX

**Reality Check**:
- **Evidence for**: Reduces submit → error → resubmit cycles
- **Evidence against**:
  - Aggressive validation can feel naggy ("Stop interrupting me!")
  - May discourage users from exploring options
  - No research on optimal validation timing (on-blur, on-submit, on-change)

**Risk**:
- Users abandon form mid-completion due to error fatigue
- Perception: "This form is too strict"

**What We Should Validate**:
- A/B test validation timing:
  - A: Real-time (current)
  - B: On-blur (after leaving field)
  - C: On-submit only
- Measure completion rates, error rates, time-to-submit

---

## 4. TECHNICAL CONSTRAINTS SHAPING REDESIGN

### 4.1 **Encryption Architecture Constraints**

**Constraint**: Secrets are encrypted server-side; passphrase is part of encryption key

**Technical Evidence**:
- `apps/api/v2/models/secret.rb:342` - Key derivation:
  ```ruby
  encryption_key = SHA256(global_secret : secret_key : passphrase_temp)
  ```
- Client never sees decrypted value without passphrase
- Passphrase cannot be changed after creation (key would change)

**Design Implications**:
1. **Cannot offer "add passphrase later"**—must be set at creation time
2. **Cannot preview encrypted content**—encryption happens server-side
3. **Passphrase recovery impossible**—no "forgot passphrase" flow
4. **Frontend validation critical**—passphrase errors can't be fixed after submit

**Redesign Constraints**:
- ✅ Can improve passphrase UX (strength meter, suggestions)
- ✅ Can make passphrase more discoverable (default to visible)
- ❌ Cannot decouple passphrase from encryption flow
- ❌ Cannot add "edit passphrase" after creation

---

### 4.2 **TTL and Redis Expiration**

**Constraint**: Secrets auto-delete from Redis after TTL expires (hard delete)

**Technical Evidence**:
- `apps/api/v2/models/secret.rb:ttl 7.days` - Redis expiration
- Metadata TTL = 2x secret TTL (outlives for audit)
- No "soft delete" or recovery mechanism

**Design Implications**:
1. **Cannot offer "extend expiration"**—secret may already be deleted
2. **Cannot undo burn**—deletion is immediate and permanent
3. **TTL must be accurate**—users cannot fix mistakes
4. **No "archive" feature**—secrets are ephemeral by design

**Redesign Constraints**:
- ✅ Can add "time remaining" visualizations (countdown, progress bar)
- ✅ Can prompt confirmation before burn ("This cannot be undone")
- ✅ Can suggest longer TTLs for async sharing (email recipient detected)
- ❌ Cannot add "grace period" after expiration
- ❌ Cannot implement "save for later" (conflicts with security model)

---

### 4.3 **Anonymous User Rate Limiting**

**Constraint**: Anonymous users are rate-limited; paid plans bypass limits

**Technical Evidence**:
- `apps/api/v2/logic/base.rb:104-111` - `limit_action` checks plan
- `apps/api/v2/models/mixins/rate_limited.rb` - Session-based counting
- Config: `:rate_limits:create_secret: 10` (per 24 hours)

**Design Implications**:
1. **Cannot promise unlimited creates** to anonymous users
2. **Must communicate limits** before user hits them
3. **Upgrade prompt** should appear before limit (not after)
4. **Session-based** = clearing cookies resets (can be gamed)

**Redesign Constraints**:
- ✅ Can show "X creates remaining today" counter
- ✅ Can prompt signup before hitting limit ("Upgrade for unlimited")
- ✅ Can implement "soft paywall" (3 creates = show upgrade CTA)
- ❌ Cannot remove rate limiting (security requirement)
- ❌ Cannot make session-based more robust (requires auth)

---

### 4.4 **Authentication Optional Architecture**

**Constraint**: System must work for both anonymous and authenticated users

**Technical Evidence**:
- `etc/config.example.yaml:141` - `authentication:required: false` (configurable)
- `apps/api/v2/models/customer.rb` - Anonymous customer object (`anon`)
- Features gated by auth: email recipient, custom domains, higher limits

**Design Implications**:
1. **Dual UX**: Form must degrade gracefully for anonymous users
2. **Progressive enhancement**: Auth features appear conditionally
3. **Persistent state**: Anonymous users lose history on logout/clear cookies
4. **Upgrade paths**: Must show value of authentication without blocking

**Redesign Constraints**:
- ✅ Can show "Sign in for more features" hints
- ✅ Can progressively disclose auth-only features
- ✅ Can implement "upgrade prompt" when anonymous hits limits
- ❌ Cannot require auth globally (deployment choice)
- ❌ Cannot persist history for anonymous users (no identity)

---

### 4.5 **View-Once State Machine**

**Constraint**: Secret state transitions are one-way (new → viewed → received → destroyed)

**Technical Evidence**:
- `apps/api/v2/models/secret.rb:272-314` - State transitions
- `apps/api/v2/models/secret.rb:received!` - Destroys on view
- Metadata outlives secret for audit (2x TTL)

**Design Implications**:
1. **Cannot "unburn" a secret**—destruction is final
2. **Cannot preview before sharing**—creator never sees encrypted value
3. **View tracking** is permanent (metadata counter persists)
4. **No "view count limit"**—secret destroyed on first view

**Redesign Constraints**:
- ✅ Can add "Preview link" (shows metadata, not content)
- ✅ Can show "This link will self-destruct on first view" warning
- ✅ Can implement "Burn now" (creator-initiated destruction)
- ❌ Cannot add "multi-view" mode (conflicts with security model)
- ❌ Cannot recover burned secrets (no backups by design)

---

### 4.6 **Custom Domain Validation**

**Constraint**: Custom domains require ownership verification and plan entitlement

**Technical Evidence**:
- `apps/api/v2/logic/secrets/base_secret_action.rb:129-166` - Domain validation
- `apps/api/v2/models/custom_domain.rb` - Verification logic
- Requires authenticated user with paid plan

**Design Implications**:
1. **Cannot offer custom domains to anonymous users**
2. **Must validate domain before use** (DNS/HTTP challenge)
3. **Paid feature**—cannot democratize without revenue loss
4. **Setup friction**—domain verification is multi-step process

**Redesign Constraints**:
- ✅ Can hide domain selector for anonymous users
- ✅ Can show "Upgrade to use custom domains" CTA
- ✅ Can streamline domain verification flow (onboarding wizard)
- ❌ Cannot bypass verification (security requirement)
- ❌ Cannot offer free custom domains (business model constraint)

---

### 4.7 **Content Size Limits**

**Constraint**: Secrets are truncated based on plan-specific size limits

**Technical Evidence**:
- `apps/api/v2/models/secret.rb:114-148` - Truncation logic with randomization
- `apps/api/v2/logic/secrets/base_secret_action.rb:231` - Plan-based size enforcement
- Randomized truncation (±20%) prevents information leakage via size

**Design Implications**:
1. **Cannot accept unlimited content**—must enforce hard limits
2. **Truncation is lossy**—users may not realize data was cut
3. **No warning after truncation**—`truncated` flag stored but not shown prominently
4. **Plan upgrade prompt** should appear before truncation

**Redesign Constraints**:
- ✅ Can show "Content too large, will be truncated" warning
- ✅ Can prompt upgrade before truncation occurs
- ✅ Can show byte size vs limit in real-time
- ❌ Cannot remove size limits (resource constraint)
- ❌ Cannot show exact truncation point (security: randomization)

---

### 4.8 **Frontend/Backend Validation Parity**

**Constraint**: Frontend (Zod) and backend (Ruby) validation must stay synchronized

**Technical Evidence**:
- `src/composables/useSecretForm.ts:23-49` - Zod schema
- `apps/api/v2/logic/secrets/base_secret_action.rb:168-216` - Ruby validation
- Passphrase complexity rules duplicated in both layers

**Design Implications**:
1. **Configuration drives validation**—changes must update both frontend and backend
2. **Cannot rely on frontend alone**—backend is source of truth
3. **Error messages must match**—inconsistent messages confuse users
4. **Breaking changes risky**—validation changes affect existing deployments

**Redesign Constraints**:
- ✅ Can improve error message clarity (update both layers)
- ✅ Can add progressive validation (frontend warnings, backend errors)
- ❌ Cannot remove backend validation (security requirement)
- ❌ Cannot skip frontend validation (poor UX)

---

### 4.9 **Tailwind 4.1 and Vue 3 Ecosystem**

**Constraint**: Must use Tailwind 4.1 patterns and Vue 3 composition API

**Technical Evidence**:
- `package.json` - Tailwind 4.x, Vue 3.x
- All components use `<script setup>` composition API
- Dark mode via Tailwind classes (`dark:bg-slate-900`)

**Design Implications**:
1. **Utility-first CSS**—custom CSS should be minimal
2. **Composition API**—no options API components
3. **Reactive state**—use `ref`, `computed`, `watch`
4. **Tailwind 4 features**—can leverage new syntax, variants

**Redesign Constraints**:
- ✅ Can use Tailwind 4.1 container queries, dynamic variants
- ✅ Can leverage Vue 3 `defineModel`, Suspense, Teleport
- ✅ Can use composables for shared logic (existing pattern)
- ❌ Cannot use class-based components (Vue 3 doesn't support)
- ❌ Cannot use styled-components or CSS-in-JS (conflicts with Tailwind)

---

### 4.10 **Internationalization (i18n)**

**Constraint**: All user-facing text must support localization

**Technical Evidence**:
- `src/i18n/` - Translation files
- `src/components/secrets/form/SecretForm.vue:$t('secret.form.passphrase')` - Usage
- Multiple languages supported (en, es, de, fr, etc.)

**Design Implications**:
1. **Cannot hardcode text**—all strings must use `$t()` helper
2. **RTL support**—must consider Arabic, Hebrew layouts
3. **Dynamic content length**—German text ~30% longer than English
4. **Pluralization rules**—must handle singular/plural correctly

**Redesign Constraints**:
- ✅ Can add new translations for new features
- ✅ Can improve existing translations (clarity, tone)
- ❌ Cannot assume text length (must design for variable width)
- ❌ Cannot use culturally-specific metaphors (must be universal)

---

## 5. CRITICAL PATH TO REDESIGN

Based on this analysis, the redesign must balance:

### Must Preserve
1. **Zero-friction anonymous access**—no auth barriers
2. **Security guarantees**—encryption, view-once, TTL enforcement
3. **Accessibility**—keyboard nav, screen readers, WCAG 2.1 AA
4. **Dual-mode interface**—Create and Generate in single flow
5. **Configuration flexibility**—deployments can customize behavior

### Must Improve
1. **Mobile UX**—reduce scrolling, improve button visibility
2. **Passphrase guidance**—help users understand when/why to use
3. **Expiration selection**—make TTL choice easier and contextual
4. **Error handling**—inline field errors, not just top alerts
5. **Feature discovery**—make Generate mode and email more discoverable

### Can Experiment With
1. **Multi-step flow**—wizard vs single-page form
2. **Input-first vs guide-first**—paste content or configure options first?
3. **Contextual defaults**—smart TTL/passphrase based on content
4. **Progressive disclosure**—reveal options as needed vs all upfront
5. **Mobile-specific patterns**—bottom sheets, swipe gestures, sticky buttons

### Cannot Change
1. **Encryption architecture**—passphrase is part of key derivation
2. **TTL hard deletes**—Redis expiration is permanent
3. **Rate limiting**—required for abuse prevention
4. **Anonymous vs authenticated**—must support both
5. **Backend validation**—source of truth for security

---

## NEXT STEPS → PHASE 2

With this foundation, we can now:

1. **Define the problem space**—articulate user goals, contexts, hypotheses
2. **Create user scenarios**—concrete use cases with mental models
3. **Identify intervention points**—where UX changes have highest impact
4. **Prioritize friction points**—quick wins vs strategic improvements

**Key Questions for Phase 2**:
- What is the user's primary goal? (Hypothesis: Get shareable link ASAP)
- What is the user's context? (Hypothesis: Rushed, distracted, security-conscious)
- Why could the current experience be better? (Hypothesis: Too many decisions upfront)

Ready to proceed to Phase 2?
