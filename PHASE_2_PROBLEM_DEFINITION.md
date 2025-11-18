# PHASE 2: PROBLEM DEFINITION & USER SCENARIOS
## OneTimeSecret Create-Secret Experience Redesign

**Date**: 2025-11-18
**Branch**: `claude/redesign-create-secret-01VCPSHrMm9voh36zpcZTmrD`
**Context**: Privacy-first (no analytics), focus on utility and time-to-task-completion

---

## DESIGN CONSTRAINTS FROM STAKEHOLDER INPUT

### Strategic Priority
**"Focus on utility, time to task completion"**

This means:
- **Speed is a feature** — Reduce steps, eliminate friction, optimize for power users
- **Utility over aesthetics** — Functional improvements trump visual polish
- **Time-to-task-completion = primary metric** — How fast can a user go from "I need to share this" to "Link copied"?

### Privacy-First Ethos
**"No analytics, as a privacy rule"**

This means:
- **No telemetry to validate assumptions** — Must design based on first principles and user research
- **No A/B testing infrastructure** — Decisions must be defensible without data
- **Design for multiple personas** — Can't optimize for "average user" (no data to define it)

### Novel UX Flows (Encouraged)
**"We think there are opportunities for novel UX flows"**

Specific opportunities mentioned:
1. **Linear Secrets** — Sequential viewing (multi-page secrets? step-by-step reveal?)
2. **Inbound Secrets** — Receiver initiates secret request (pull vs push model)
3. **Inbound Requests** — Request-a-secret flow (recipient asks, sender provides)
4. **Markdown rendering** — Recipient receives rich-formatted content (e.g., employee onboarding docs)
5. **QR code delivery** — Recipient scans QR code (e.g., TOTP setup, WiFi credentials)

**Implication**: Redesign should **enable these future flows** without being constrained by current "paste → share link" paradigm.

---

## CORE PROBLEM STATEMENT

### The User's Primary Goal
**"Get a shareable method to deliver sensitive information to a specific person, right now, with appropriate security."**

Breaking this down:
- **Shareable method** — Not just "link" (could be QR code, email, request token)
- **Sensitive information** — Requires encryption, view-once, expiration
- **Specific person** — Delivery mechanism matters (email vs Slack vs in-person scan)
- **Right now** — Time-sensitive, user is blocked until this task is done
- **Appropriate security** — User can assess risk and choose matching protection (passphrase, short TTL)

### The User's Context
Users arrive at OneTimeSecret in specific emotional/situational states:

1. **Rushed** — "I need this done in 30 seconds or I'm late for a meeting"
2. **Distracted** — Multitasking, may context-switch mid-flow (Slack notification, phone call)
3. **Security-conscious** — Aware of risks (phishing, link interception), wants reassurance
4. **Uncertain** — First-time user, doesn't know what options mean or which to choose
5. **Mobile** — On phone, potentially one-handed, small screen, unreliable connection

### Why the Current Experience Could Be Better

**Hypothesis 1: Decision fatigue upfront**
- Current flow: Secret → Passphrase | Expiry → Recipient → Domain → Submit
- User must make 4-5 decisions before seeing value
- For rushed users, this feels like bureaucracy ("Just give me the link!")

**Hypothesis 2: Mobile friction creates abandonment**
- Submit button below fold on mobile (requires scrolling)
- No sticky action button = visual disconnection between input and confirmation
- Distracted mobile users paste content, scroll to submit, get interrupted, navigate away

**Hypothesis 3: Hidden features = lost utility**
- Generate password hidden in dropdown (users go to 1Password instead)
- Email recipient hidden/blocked by auth (users copy link to Gmail manually)
- QR code not offered (users screenshot link and text it)

**Hypothesis 4: One-size-fits-all form doesn't match mental models**
- Developer sharing DB credentials thinks: "This is HIGH risk, short-lived, needs passphrase"
- Friend sharing WiFi password thinks: "This is LOW risk, scan QR code, keep it simple"
- Same form serves both = suboptimal for each

**Hypothesis 5: No guidance = security gaps**
- Users don't know when passphrase adds value (skip it even for credentials)
- Users don't know which TTL matches their use case (accept default blindly)
- Users don't realize link can be intercepted (share via unencrypted email)

---

## USER SCENARIOS

### Scenario 1: **Developer Shares Database Credentials with Contractor**

**Persona**: Maya, Senior Backend Engineer at SaaS startup

**Context**:
- **Device**: MacBook Pro (desktop browser)
- **Situation**: Contractor needs production DB access to debug performance issue
- **Time pressure**: HIGH — Production issue affecting customers, contractor waiting on Slack
- **Security awareness**: VERY HIGH — DB credentials are crown jewels
- **Technical comfort**: Expert

**Mental Model**:
- "This credential is extremely sensitive"
- "Contractor needs it immediately, but only for this debugging session"
- "I want this to expire in 1 hour and require a passphrase"
- "I'll send the link via Slack, passphrase via Signal"

**Current Workflow**:
1. Opens OneTimeSecret in new tab
2. Copies DB connection string from `.env` file
3. Pastes into textarea
4. Sets passphrase: `debug-nov18-maya`
5. Changes TTL to 1 hour (dropdown navigation)
6. Clicks "Create Link"
7. Copies link from receipt page
8. Pastes link in Slack DM to contractor
9. Opens Signal, sends passphrase separately
10. Returns to receipt page, clicks "Burn" to delete after contractor confirms receipt

**Pain Points**:
- ❌ **Passphrase + TTL in separate fields** — Feels like two disconnected decisions
- ❌ **No "copy passphrase" button** — Has to manually copy from form before submit (or regenerate)
- ❌ **No "expires at [time]" preview** — Has to mentally calculate "1 hour from now = 3:45 PM"
- ❌ **Burn requires navigation back** — If she's already in Slack, has to switch back to browser

**Ideal Workflow**:
1. Opens OneTimeSecret (already in browser)
2. **Keyboard shortcut to focus form** (`Cmd+K` to focus textarea)
3. Pastes DB credentials
4. **Quick action**: Clicks "High Security" preset → Auto-sets 1hr TTL + required passphrase
5. **Passphrase auto-generated** and shown → Clicks "Copy passphrase" → Sent to clipboard
6. Clicks "Create Link" → Link auto-copied to clipboard
7. **Dual-clipboard support** (link in clipboard, passphrase in "clipboard history")
8. Pastes link in Slack (primary clipboard)
9. Opens Signal, pastes passphrase (secondary clipboard or retrieves from history)
10. **Burn via API/webhook** or auto-burn after first view (no manual step)

**Time-to-Task**:
- Current: ~45-60 seconds (10 steps)
- Ideal: ~20-30 seconds (6 steps with presets and auto-copy)

**Required Features**:
- Security level presets (High/Medium/Low)
- Auto-generated passphrases with copy button
- Dual-clipboard or passphrase retrieval
- Quick burn (API endpoint or auto-burn option)
- Keyboard shortcuts for power users

**Nice-to-Have**:
- Integration with Slack (post link directly)
- "Expires at [timestamp]" preview
- Browser extension (create secret from selected text)

---

### Scenario 2: **Support Agent Shares Temporary Password with Customer**

**Persona**: James, Customer Support Specialist at B2B SaaS company

**Context**:
- **Device**: iPad (mobile browser) + customer on phone call
- **Situation**: Customer locked out of account, needs temp password to reset
- **Time pressure**: MEDIUM — Customer is frustrated, on hold
- **Security awareness**: MEDIUM — Knows passwords shouldn't be emailed, uses OneTimeSecret
- **Technical comfort**: Intermediate

**Mental Model**:
- "Customer needs a password RIGHT NOW while I have them on the phone"
- "I'll generate a temp password and read it to them over the phone"
- "It should expire quickly (30 minutes) in case they don't use it"
- "No passphrase needed — customer has the link, that's enough security"

**Current Workflow**:
1. Opens OneTimeSecret on iPad (still on phone call with customer)
2. **Switches to Generate Password mode** (clicks SplitButton dropdown — requires precision tap)
3. Clicks "Generate Password"
4. Receipt page shows link: `https://onetimesecret.com/private/abc123xyz`
5. **Can't see generated password** (only customer will see it on first view)
6. Reads link aloud to customer: "H-T-T-P-S colon slash slash..." (awkward, error-prone)
7. Customer types link into browser (slow, typos likely)
8. Customer views secret, sees password
9. Customer uses password to log in

**Pain Points**:
- ❌ **Generate mode hidden in dropdown** — Doesn't discover feature, manually creates weak password
- ❌ **Link is not voice-friendly** — Reading 30+ character URL aloud is painful
- ❌ **No SMS/email option** — Can't send link directly from form (would need to copy → open email → paste)
- ❌ **Mobile tap targets small** — Dropdown menu hard to use on phone while talking
- ❌ **No QR code option** — Could show QR code on screen, customer scans with phone camera

**Ideal Workflow**:
1. Opens OneTimeSecret on iPad (on call with customer)
2. **Generate mode is prominent** (toggle switch or separate button, not hidden dropdown)
3. Clicks "Generate Password" → Password instantly generated
4. **Shows password AND link preview** (James can see what was generated)
5. **Option appears: "Share via QR code, SMS, or Email"**
6. Selects **"QR Code"** → Fullscreen QR code appears on iPad
7. Holds iPad to customer's phone camera → Customer scans QR code
8. Customer's browser opens secret link → Password revealed
9. Customer uses password to log in (James can see generated password to verify if needed)

**Alternative Flow (Email)**:
5. Selects **"Email"** → Modal prompts for customer email
6. Enters customer's email: `customer@example.com`
7. Email sent instantly (customer receives while on call)
8. "Email sent to cus...@example.com" confirmation shown
9. Customer opens email on phone, clicks link, sees password

**Time-to-Task**:
- Current: ~90-120 seconds (awkward voice reading, typos, re-reading)
- Ideal (QR): ~10-15 seconds (generate → show QR → scan → done)
- Ideal (Email): ~20-30 seconds (generate → enter email → send → confirm)

**Required Features**:
- Prominent Generate mode (not buried in dropdown)
- QR code display (fullscreen, high contrast)
- Email delivery from form (no copy/paste)
- Show generated password to creator (for verification)
- Mobile-optimized UI (large tap targets)

**Nice-to-Have**:
- SMS delivery (requires Twilio integration)
- Short URLs for voice reading (`onetimesecret.com/abc123` vs full path)
- "Copy password to clipboard" (for creator to paste into support ticket)

---

### Scenario 3: **Friend Shares WiFi Password via QR Code**

**Persona**: Alex, homeowner hosting dinner party

**Context**:
- **Device**: iPhone (mobile browser)
- **Situation**: Guest asks for WiFi password
- **Time pressure**: LOW — Social situation, not urgent
- **Security awareness**: LOW — WiFi password is low-stakes
- **Technical comfort**: Casual user

**Mental Model**:
- "I don't want to read this 16-character WPA2 password aloud"
- "Guest should just scan a QR code with their phone"
- "Password can last a few hours (duration of party)"
- "No passphrase needed — it's just WiFi"

**Current Workflow**:
1. Opens OneTimeSecret on iPhone
2. Finds WiFi password (goes to Settings → WiFi → Shares password via iOS share sheet)
3. **OneTimeSecret doesn't support iOS share sheet** → Must manually copy password
4. Returns to OneTimeSecret, pastes password
5. Clicks "Create Link"
6. Copies link from receipt page
7. **No QR code option** → Uses separate QR code generator app (QRTiger, etc.)
8. Pastes link into QR code app
9. Shows generated QR code to guest
10. Guest scans, opens browser, sees password, connects to WiFi

**Pain Points**:
- ❌ **No native QR code support** — Requires third-party app (extra steps)
- ❌ **No iOS share extension** — Can't share directly from iOS WiFi settings
- ❌ **Link is intermediary** — Guest wants password, gets link first (extra tap)
- ❌ **Mobile workflow clunky** — Too many app switches (Settings → OneTimeSecret → QR app → back)

**Ideal Workflow**:
1. Opens OneTimeSecret on iPhone
2. **Pastes WiFi password** (or uses iOS share extension from Settings)
3. **Toggle: "Share as QR code"** → Selected by default for short text
4. **TTL preset: "A few hours"** (auto-selected based on content type)
5. Taps "Create QR Code" → **Instant fullscreen QR code** (no link, direct to secret)
6. Guest scans QR code → **Password revealed immediately** (no intermediate link page)
7. Guest copies password, connects to WiFi

**Alternative Flow (If OneTimeSecret had iOS share extension)**:
1. Goes to Settings → WiFi → Taps share icon
2. Selects "OneTimeSecret" from share sheet
3. **QR code appears instantly** (no form, uses sensible defaults)
4. Shows to guest → Guest scans → Password revealed

**Time-to-Task**:
- Current: ~60-90 seconds (copy → paste → create → open QR app → generate QR)
- Ideal (native QR): ~10-20 seconds (paste → create QR → show)
- Ideal (share extension): ~5 seconds (share → show QR)

**Required Features**:
- Native QR code generation (no external app)
- "Share as QR code" toggle (skip link step)
- Context-aware defaults (short text = QR code suggested)
- Mobile-optimized fullscreen QR display

**Nice-to-Have**:
- iOS/Android share extension
- QR code customization (color, logo)
- "Direct reveal" mode (QR → password, no intermediate page)

---

### Scenario 4: **HR Manager Sends Onboarding Credentials via Markdown**

**Persona**: Priya, HR Manager at 50-person startup

**Context**:
- **Device**: Desktop (Chrome browser)
- **Situation**: New employee starts Monday, needs credentials for 5 systems
- **Time pressure**: LOW — Preparing in advance (Friday afternoon)
- **Security awareness**: HIGH — Credentials for Slack, GitHub, AWS, email, password manager
- **Technical comfort**: Intermediate

**Mental Model**:
- "New employee needs multiple credentials, formatted clearly"
- "I want to send one link with everything, not 5 separate secrets"
- "It should look professional (formatted, not plain text dump)"
- "It should expire Monday EOD (after they've set up accounts)"
- "They shouldn't need to remember a passphrase on Day 1"

**Current Workflow**:
1. Opens OneTimeSecret
2. Copies credentials from HR system (Google Sheet)
3. Pastes into textarea:
   ```
   Slack: priya@company.com / TempPass123
   GitHub: priya-company / TempPass456
   AWS: priya.kumar@company.com / TempPass789
   Email: priya.kumar@company.com / TempPass012
   1Password: priya@company.com / TempPass345
   ```
4. Sets TTL to 3 days (to cover Monday)
5. Decides against passphrase (don't want to overwhelm new employee)
6. Creates link
7. Copies link
8. Opens email client, composes welcome email:
   ```
   Hi Sarah,

   Welcome to the team! Here are your login credentials:
   [paste link]

   Please change all passwords after your first login.

   Best,
   Priya
   ```
9. Sends email
10. Sarah opens email Monday morning, clicks link, sees **plain text blob** (hard to parse)

**Pain Points**:
- ❌ **No formatting support** — Plain text is hard to scan (which password goes with which system?)
- ❌ **No structure** — Can't group related info (e.g., "Primary Accounts" vs "Secondary Tools")
- ❌ **No instructions** — Can't embed "Change this password after first login" next to each credential
- ❌ **Single long string** — Recipient must copy/paste carefully (easy to grab wrong line)
- ❌ **No rich preview** — Email just shows link, no context about what's inside

**Ideal Workflow**:
1. Opens OneTimeSecret
2. **Toggles "Markdown mode"** (or auto-detected from content)
3. Pastes formatted credentials:
   ```markdown
   # Welcome to Acme Corp! 🎉

   Here are your login credentials. **Please change all passwords after first login.**

   ## Primary Accounts
   - **Slack**: `priya@company.com` / `TempPass123`
   - **Email**: `priya.kumar@company.com` / `TempPass012`

   ## Developer Tools
   - **GitHub**: `priya-company` / `TempPass456`
   - **AWS Console**: `priya.kumar@company.com` / `TempPass789`

   ## Password Manager
   - **1Password**: `priya@company.com` / `TempPass345`

   ---
   Questions? Slack me @priya or email priya@company.com
   ```
4. **Preview pane shows rendered markdown** (WYSIWYG)
5. Sets TTL to "3 days" (dropdown or text input)
6. **Recipient field auto-filled** from HR system (integration) or manually entered
7. **Email template auto-populated**:
   ```
   Subject: Welcome to Acme! Your credentials inside

   Hi Sarah,

   Your secure onboarding credentials: [link]

   This link expires in 3 days and can only be viewed once.

   Welcome to the team!
   Priya
   ```
8. Clicks "Create & Email" → Secret created, email sent
9. Sarah receives email Monday, clicks link
10. **Sees beautifully formatted onboarding doc** (rendered markdown with syntax highlighting for credentials)
11. Copies each credential individually (code blocks have copy buttons)

**Time-to-Task**:
- Current: ~3-5 minutes (create secret → copy link → compose email → send)
- Ideal: ~1-2 minutes (paste markdown → preview → email → done)

**Required Features**:
- Markdown rendering for recipients
- Live preview while composing
- Code block copy buttons (for credentials)
- Email template integration
- Recipient field with auto-send

**Nice-to-Have**:
- HR system integration (auto-fetch credentials)
- Onboarding template library (pre-formatted)
- Custom branding (company logo in rendered secret)
- Expiration reminder (email to Priya if Sarah hasn't viewed by Sunday)

---

## SYNTHESIS: PATTERNS ACROSS SCENARIOS

### Common Jobs-to-Be-Done
1. **"Get sensitive data from my system to someone else's system"** (all scenarios)
2. **"Choose appropriate security for sensitivity level"** (Scenarios 1, 4)
3. **"Minimize steps between 'I need to share this' and 'Done'"** (Scenarios 1, 2, 3)
4. **"Avoid voice-reading or manual typing of complex strings"** (Scenarios 2, 3)
5. **"Provide context to recipient about what they're receiving"** (Scenario 4)

### Context-Specific Needs

| Scenario | Primary Need | Secondary Need | Delivery Method |
|----------|--------------|----------------|-----------------|
| **Developer** | High security | Speed | Link (Slack + Signal) |
| **Support** | Speed | Ease of delivery | QR code or Email |
| **Friend** | Simplicity | No typing | QR code |
| **HR** | Professionalism | Clarity | Email with rich format |

### Mental Model Divergence

**Current OneTimeSecret mental model**:
> "Create a secret → Get a link → Share the link"

**User mental models**:
- Developer: "Securely transmit credential → Verify receipt → Destroy"
- Support: "Generate password → Get it to customer's device → Done"
- Friend: "Make password scannable → Guest connects → Forget about it"
- HR: "Package credentials professionally → Email to new hire → Track delivery"

**The gap**: OneTimeSecret thinks in terms of "secrets and links." Users think in terms of "transmission methods and outcomes."

### Friction Point Patterns

#### 1. **Delivery Method Mismatch**
- User needs QR code → OneTimeSecret gives link → User uses third-party QR generator
- User needs email → OneTimeSecret gives link → User manually copies to email client
- User needs voice-friendly format → OneTimeSecret gives 30-char URL → User reads awkwardly

**Insight**: Link is *a* delivery method, not *the* delivery method.

#### 2. **Security Calibration Gap**
- Developer knows "high security" → Must manually configure TTL + passphrase + burn
- Friend knows "low security" → Must skip fields (passphrase, recipient) that feel intimidating
- No presets or guidance → Users either over-secure (friction) or under-secure (risk)

**Insight**: Users think in risk levels, not configuration options.

#### 3. **Mobile-First vs Desktop-Designed**
- Support agent on iPad → UI optimized for desktop (small dropdowns, scrolling)
- Friend on iPhone → Workflow requires app-switching (Settings → OneTimeSecret → QR app)
- No mobile-native patterns (sticky buttons, gesture nav, share extensions)

**Insight**: Mobile is not "responsive desktop" — it's a different interaction paradigm.

#### 4. **Creator vs Recipient Mismatch**
- Developer sees form → Recipient sees plain link (no context)
- HR sends formatted text → Recipient sees unformatted blob
- Support generates password → Can't see what was generated (verification impossible)

**Insight**: Creator and recipient experiences are disconnected.

---

## HYPOTHESIS VALIDATION (NO ANALYTICS)

Since we can't use telemetry, how do we validate hypotheses?

### Heuristic Evaluation
- **Nielsen's Usability Heuristics**: Visibility of system status, match between system and real world, user control, consistency
- **Time-to-Task Benchmarking**: Measure steps in current vs proposed flows
- **Cognitive Load Assessment**: Count decisions required before value delivered

### Comparative Analysis
- **Competitor Flows**: How do similar tools (PrivateBin, Bitwarden Send, Firefox Send) handle these scenarios?
- **Adjacent Domains**: How do messaging apps (Signal, WhatsApp) handle ephemeral content?
- **Platform Patterns**: What are iOS/Android standards for sharing sensitive data?

### User Research (Privacy-Compatible)
- **Interviews**: Talk to 5-10 users across personas (developers, support, casual users)
- **Contextual Inquiry**: Watch users complete tasks in their actual environments
- **Diary Studies**: Ask users to log when/why they share sensitive data over 1 week
- **Prototype Testing**: Build lo-fi prototypes, observe task completion (no tracking)

### First Principles Reasoning
- **Cognitive Psychology**: Humans can hold 7±2 items in working memory (minimize form fields)
- **Fitts's Law**: Larger, closer targets = faster interaction (mobile button positioning)
- **Hick's Law**: More choices = longer decision time (reduce upfront configuration)
- **Peak-End Rule**: Users remember the peak (moment of success) and end (receipt page) most vividly

---

## PROBLEM DEFINITION SUMMARY

### Core Problem
**The current create-secret flow optimizes for feature completeness, not task completion speed.**

It presents a single interface for all use cases:
- ✅ **Strength**: Flexible, powerful, handles edge cases
- ❌ **Weakness**: Slow for common cases, hidden features, one-size-fits-all

### Opportunity
**Enable multiple creation paradigms that match user mental models:**

1. **Express Mode** → "Paste and go" (defaults, 5 seconds)
2. **Secure Mode** → "High-security preset" (passphrase + short TTL, 15 seconds)
3. **Generate Mode** → "Create password" (prominent, show result, 10 seconds)
4. **QR Mode** → "Scannable delivery" (fullscreen QR, 10 seconds)
5. **Markdown Mode** → "Formatted onboarding" (rich preview, email integration, 60 seconds)

Each mode optimized for specific context, not generic form.

### Success Criteria (Time-to-Task-Completion)

| Scenario | Current Time | Target Time | Improvement |
|----------|--------------|-------------|-------------|
| Developer (high security) | 45-60s | 20-30s | 50% faster |
| Support (generate + QR) | 90-120s | 10-15s | 85% faster |
| Friend (WiFi QR code) | 60-90s | 10-20s | 75% faster |
| HR (markdown email) | 180-300s | 60-120s | 60% faster |

### Key Insights for Phase 3
1. **Delivery method > Link format** — QR codes, emails, SMS as first-class options
2. **Presets > Configuration** — High/Medium/Low security instead of TTL + passphrase fields
3. **Mobile ≠ Responsive Desktop** — Needs gesture nav, sticky buttons, share extensions
4. **Context-aware defaults** — Detect content type (WiFi password, credentials, formatted text)
5. **Creator/Recipient parity** — What creator sees should match what recipient gets

---

## NEXT: PHASE 3 — INTERACTION MODELS

With this problem definition, we can now explore **2-3 fundamentally different approaches** to the create-secret flow:

**Potential dimensions to vary**:
- Single-page progressive vs multi-step wizard
- Input-first (paste → configure) vs intent-first (choose mode → input)
- Minimal defaults vs explicit choices
- Traditional form vs conversational/chat-like
- Unified interface vs separate flows per use case

**Questions for Phase 3**:
1. Should all modes live in one interface, or separate entry points?
2. Should mobile and desktop have different flows, or unified responsive?
3. Should presets be prominent, or keep current granular control?
4. How do we introduce new modes (QR, markdown) without overwhelming existing users?

Ready to explore interaction models in Phase 3?
