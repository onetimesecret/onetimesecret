# PHASE 3: INTERACTION MODELS

## Executive Summary

This phase explores three fundamentally different approaches to the create-secret experience, each optimized for different user priorities. Through detailed flow descriptions and persona testing, we evaluate which approach best serves our diverse user base while maintaining simplicity and speed.

**Recommendation Preview:** Model 1 ("The Express Lane") emerges as the strongest candidate, with selective elements from Model 3 for enhanced guidance.

---

## EVALUATION FRAMEWORK

Each model will be tested against:

**Speed Metrics:**
- Time-to-first-link (target: < 10 seconds)
- Required clicks (target: ≤ 2)
- Cognitive load (decisions required)

**User Fit:**
- ✅ Alex (Rusher) - needs speed, zero config
- ✅ Jamie (Scripter) - needs simplicity, clear defaults
- ✅ Morgan (Worrier) - needs guidance, trust, review
- ✅ Priya (Expert) - needs control, advanced features

**Accessibility:**
- Keyboard navigation flow
- Screen reader experience
- Mobile optimization
- Focus management

---

## MODEL 1: "THE EXPRESS LANE"

### Philosophy

**Get out of the user's way.**

Start with the absolute minimum—just the textarea. Everything else is progressive disclosure triggered by user need, not designer assumptions. The interface adapts to the user's pace: rushers get instant results, worriers get guidance on demand.

### Core Principles

1. **Input-first:** Show textarea immediately, no preamble
2. **Defaults-first:** Smart defaults handle 80% of use cases
3. **Progressive disclosure:** Options appear contextually, not upfront
4. **One primary action:** Always clear what to do next
5. **Instant feedback:** Real-time validation and confirmation

---

### INTERACTION FLOW (Desktop)

#### Initial State

User lands on homepage and sees:

```
┌─────────────────────────────────────────────────────────┐
│  OneTimeSecret                         [Sign In]  [?]   │
└─────────────────────────────────────────────────────────┘

   Share a secret, the secure way

   ┌─────────────────────────────────────────────────────┐
   │                                                     │
   │  Paste your secret here...                         │
   │                                                     │
   │                                                     │
   │                                                     │
   │                                                     │
   └─────────────────────────────────────────────────────┘
                                          0 / 10,000 chars

   ┌────────────────────────────────────────────┐
   │         Create Secret Link                 │
   └────────────────────────────────────────────┘

   or generate a random password →
```

**What's visible:**
- Large, welcoming textarea (empty state)
- Character counter (subtle, bottom-right)
- One prominent button: "Create Secret Link"
- Small text link below: "or generate a random password →"
- Help icon (?) in header for first-time users

**What's NOT visible yet:**
- Passphrase field
- Expiration dropdown
- Recipient email
- Custom domain selector

**Accessibility:**
- Focus automatically on textarea on page load
- Textarea has `aria-label="Secret content"`
- Button is disabled until textarea has content
- Keyboard shortcut: Cmd/Ctrl+Enter to submit

---

#### User Types in Textarea

As user types (real-time updates):

```
   ┌─────────────────────────────────────────────────────┐
   │ postgres://admin:xK9$mP2#vL5@prod-db.example.com   │
   │                                                     │
   │                                                     │
   │                                                     │
   │                                                     │
   │                                                     │
   └─────────────────────────────────────────────────────┘
                                            53 / 10,000

   ┌────────────────────────────────────────────┐
   │         Create Secret Link                 │  ← Now enabled
   └────────────────────────────────────────────┘

   ⚙️ Add passphrase or change expiration (7 days)  ← NEW

   or generate a random password →
```

**What changed:**
- Button enabled (blue, prominent)
- Small gear icon ⚙️ + text link appears below button
- Text shows current default: "7 days"

**Progressive disclosure trigger:**
- "Add passphrase or change expiration (7 days)" expands options when clicked

---

#### User Clicks "Add Passphrase or Change Expiration"

Smooth expand animation reveals options inline:

```
   ┌─────────────────────────────────────────────────────┐
   │ postgres://admin:xK9$mP2#vL5@prod-db.example.com   │
   │                                                     │
   │                                                     │
   └─────────────────────────────────────────────────────┘
                                            53 / 10,000

   ┌─────────────────────────────────────────────────────┐
   │  🔒 Passphrase (optional)                           │
   │  ┌───────────────────────────────────────────┐  👁  │
   │  │                                           │      │
   │  └───────────────────────────────────────────┘      │
   │  💡 Share passphrase separately (SMS, phone call)  │
   │                                                     │
   │  ⏱️  Expires in                                      │
   │  [ 1 hour ] [ 4 hours ] [ 1 day ] [✓ 7 days] ...  │
   │                                                     │
   └─────────────────────────────────────────────────────┘

   ┌────────────────────────────────────────────┐
   │         Create Secret Link                 │
   └────────────────────────────────────────────┘

   ⚙️ Hide options  ← Changed to "Hide"
```

**What changed:**
- Passphrase field revealed with:
  - Label: "🔒 Passphrase (optional)"
  - Visibility toggle (eye icon)
  - Inline tip: "Share passphrase separately"
- Expiration revealed as:
  - **Button group** (not dropdown!) for mobile-friendly tapping
  - Pre-selected: 7 days (checkmark ✓)
  - Options: 1h, 4h, 1d, 7d, 14d, 30d (filtered by plan)
  - "More options..." expands full list
- Link text changes to "Hide options"

**Accessibility:**
- Focus moves to passphrase field when expanded
- Button group is keyboard navigable (arrow keys)
- Screen reader announces "Options expanded"

---

#### User Clicks "Create Secret Link"

Instant feedback, no page reload:

```
   [Fade out form, fade in confirmation]

   ┌─────────────────────────────────────────────────────┐
   │                                                     │
   │            ✅  Your secret link is ready!           │
   │                                                     │
   │  This link will expire in 7 days or after 1 view   │
   │                                                     │
   │  ┌─────────────────────────────────────────────┐   │
   │  │ https://onetimesecret.com/s/a3k9x2m...     │   │
   │  └─────────────────────────────────────────────┘   │
   │                                                     │
   │  ┌────────────────────────┐  ┌──────────────┐     │
   │  │   Copy Link            │  │  Start Over  │     │
   │  └────────────────────────┘  └──────────────┘     │
   │                                                     │
   │  🔒 Passphrase protected: Yes                      │
   │  💡 Remember: Share the passphrase separately!     │
   │                                                     │
   └─────────────────────────────────────────────────────┘

   [View secret management] → (for authenticated users)
```

**What's visible:**
- Success message with checkmark
- Clear expiration info
- **Link in a copyable field** (not just text)
- Two buttons:
  - "Copy Link" (primary, auto-focuses)
  - "Start Over" (secondary)
- Confirmation of settings:
  - Passphrase status (Yes/No)
  - Reminder if passphrase set
- Link to view secret management (if authenticated)

**Auto-behavior:**
- Link field auto-selected (ready to Cmd+C)
- "Copy Link" button copies to clipboard + shows "Copied!" for 2s
- No redirect—user stays on confirmation screen

**Accessibility:**
- Focus on "Copy Link" button
- Keyboard shortcut: Cmd/Ctrl+C copies link
- Screen reader announces: "Secret link created. Link copied to clipboard."

---

#### Alternative Flow: "Generate a Random Password"

User clicks "or generate a random password →" link:

```
   ┌─────────────────────────────────────────────────────┐
   │                                                     │
   │         🔑  Generate a Random Password             │
   │                                                     │
   │   We'll create a secure password and give you      │
   │   a one-time link to share it.                     │
   │                                                     │
   └─────────────────────────────────────────────────────┘

   ┌────────────────────────────────────────────┐
   │      Generate Password                     │
   └────────────────────────────────────────────┘

   ⚙️ Password options (12 chars, letters + numbers)

   ← Back to create link
```

**What changed:**
- Textarea hidden
- Icon + heading explain what this does
- Button says "Generate Password"
- Options collapsed by default (shows current settings)
- "Back to create link" returns to main flow

**User clicks "Generate Password":**

```
   ✅  Your password link is ready!

   The password is:  xK9$mP2#vL5@

   ┌─────────────────────────────────────────────┐
   │ https://onetimesecret.com/s/a3k9x2m...     │
   └─────────────────────────────────────────────┘

   ┌────────────────────────┐  ┌──────────────┐
   │   Copy Link            │  │  Copy Both   │
   │   (without password)   │  │              │
   └────────────────────────┘  └──────────────┘

   💡 The link shows the password—don't share the
      password separately unless you set a passphrase.
```

**Key difference:**
- Shows the generated password (user needs to see it)
- Two copy options:
  1. "Copy Link" - just the URL
  2. "Copy Both" - link + password (for convenience)
- Inline tip about passphrase difference

---

### INTERACTION FLOW (Mobile)

Key differences for mobile:

**Initial State:**
```
┌─────────────────────────────┐
│  OneTimeSecret          [?] │
├─────────────────────────────┤
│                             │
│  Share a secret,            │
│  the secure way             │
│                             │
│  ┌───────────────────────┐  │
│  │ Paste your secret...│  │
│  │                     │  │
│  │                     │  │
│  └───────────────────────┘  │
│                 0 / 10,000  │
│                             │
│  ┌─────────────────────────┐│
│  │  Create Secret Link    ││
│  └─────────────────────────┘│
│                             │
│  or generate password →     │
│                             │
└─────────────────────────────┘
```

**Expiration Options (Mobile):**
```
┌─────────────────────────────┐
│  ⏱️  Expires in              │
│                             │
│  ┌─────┐ ┌─────┐ ┌──────┐  │
│  │ 1h  │ │ 4h  │ │ 1 day│  │
│  └─────┘ └─────┘ └──────┘  │
│                             │
│  ┌──────┐ ┌──────┐ ┌──────┐│
│  │✓ 7d  │ │ 14d  │ │ 30d ││
│  └──────┘ └──────┘ └──────┘│
│                             │
│  Custom... ▼                │
└─────────────────────────────┘
```

**Mobile-specific optimizations:**
- Larger tap targets (48px minimum)
- Button chips instead of dropdown
- Stacked layout (no side-by-side)
- Sticky "Create Secret Link" button at bottom
- Auto-scroll to confirmation (no redirect)

---

### UX PHILOSOPHY

**"Assume the user knows what they're doing, but make help available."**

1. **Trust the user:** Don't force configuration
2. **Smart defaults:** 7-day expiration, no passphrase (secure enough for most)
3. **Just-in-time help:** Options appear when needed, not before
4. **No wizards:** Single page, progressive disclosure
5. **Instant gratification:** No redirects, immediate confirmation

---

### ACCESSIBILITY CONSIDERATIONS

**Keyboard Navigation:**
```
Tab 1:  Textarea (auto-focus on load)
Tab 2:  "Create Secret Link" button
Tab 3:  "Add passphrase or change expiration" link
Tab 4:  "Generate password" link
[Enter: Submit form]

If options expanded:
Tab 3a: Passphrase field
Tab 3b: Passphrase visibility toggle
Tab 3c: Expiration button group (arrow keys to navigate)
Tab 4:  "Hide options" link
```

**Screen Reader Experience:**
```
[Page load]
"Share a secret, the secure way. Secret content, edit text.
 Create secret link, button, disabled."

[User types]
"Create secret link, button, enabled."

[Options expanded]
"Options expanded. Passphrase, optional, edit text.
 Expires in, button group, 7 days selected."

[Submit]
"Creating secret link... Your secret link is ready.
 Link copied to clipboard. Expires in 7 days."
```

**Focus Management:**
- Load: Auto-focus textarea
- Options expand: Focus passphrase field
- Submit: Focus "Copy Link" button
- Link copied: Announce "Copied!" via aria-live region

**Mobile Accessibility:**
- Touch targets: 48px minimum (iOS/Android guidelines)
- Pinch-to-zoom enabled
- No hover states (tap-only)
- Bottom sheet for options (native mobile pattern)

---

### PERSONA TESTING

#### ✅ Alex (Backend Developer - Emergency DB Credentials)

**Flow:**
1. Lands on page, textarea auto-focused
2. Cmd+V pastes DB credentials
3. Clicks "Create Secret Link" (or presses Enter)
4. Link appears, auto-selected
5. Cmd+C copies link
6. Pastes in Slack

**Time:** ~5 seconds (vs. current ~30s)
**Clicks:** 1 (paste) + 1 (create) + 1 (copy) = **3 clicks**
**Friction:** ❌ None—no configuration decisions
**Verdict:** ✅ **PERFECT** - Gets out of Alex's way completely

---

#### ✅ Jamie (Support Agent - Customer Password Reset)

**Flow:**
1. Lands on page
2. Pastes temp password
3. Sees "or generate a random password →" link 💡 **DISCOVERS FEATURE**
4. Next time: Clicks "Generate Password" instead
5. Password generated instantly
6. Copies link + password, sends to customer

**Time:** ~8 seconds (first time), ~3 seconds (subsequent)
**Clicks:** 2-3 clicks
**Friction:** ❌ None—discovers better workflow organically
**Verdict:** ✅ **EXCELLENT** - Learns advanced feature naturally

---

#### ⚠️ Morgan (Freelancer - Personal Tax Documents)

**Flow:**
1. Lands on page, sees textarea
2. Tries to drag/drop W-9 PDF ❌ **FAILS**
3. *Could abandon here...*
4. Sees help icon (?) in header, clicks
5. Modal explains: "Text only—try WeTransfer for files"
6. *Recovers:* Copy-pastes SSN + tax info as text
7. Clicks "Add passphrase or change expiration"
8. Sets passphrase, sees tip: "Share separately"
9. Changes expiration to 3 days (buttons, not dropdown)
10. Clicks "Create Secret Link"
11. Sees confirmation: "Passphrase protected: Yes"
12. **Feels confident** ✅

**Time:** ~45 seconds (with recovery)
**Clicks:** 6-7 clicks
**Friction:** ⚠️ Initial file upload confusion, but recoverable
**Verdict:** ⚠️ **GOOD** - Needs trust indicators + file upload clarity

**Improvements needed:**
- Clearer "text only" messaging upfront
- Trust badges (HTTPS, encryption explanation)
- Review step before finalizing (not just confirmation after)

---

#### ✅ Priya (DevOps Engineer - API Key Handoff)

**Flow:**
1. Lands on page, pastes API key
2. Clicks "Add passphrase or change expiration"
3. Sets strong passphrase, changes to 1 hour
4. Clicks "Create Secret Link"
5. Sees confirmation
6. *Wants:* View status tracking ❌ **NOT VISIBLE**

**Time:** ~12 seconds
**Clicks:** 4 clicks
**Friction:** ⚠️ Missing power user features (tracking, dashboard)
**Verdict:** ⚠️ **GOOD** - Fast, but lacks advanced features

**Improvements needed:**
- Link to "View all secrets" (for authenticated users)
- Inline status indicator ("Not viewed yet")
- Email notification option

---

### PROS vs CURRENT IMPLEMENTATION

✅ **Speed:** 3 clicks vs. 6+ clicks (50% reduction)
✅ **Clarity:** No upfront configuration burden
✅ **Discoverability:** Features revealed contextually (Generate Password link)
✅ **Mobile:** Button chips instead of dropdowns
✅ **Feedback:** Immediate confirmation, no redirect
✅ **Accessibility:** Clear keyboard navigation, auto-focus
✅ **Trust:** Confirmation screen shows exactly what was created

---

### CONS vs CURRENT IMPLEMENTATION

⚠️ **Hidden options:** Power users must know to expand options
⚠️ **No file upload:** Still text-only (Morgan's use case fails initially)
⚠️ **No review step:** Options expanded → create → done (no "preview")
⚠️ **Limited tracking:** No way to see if secret was viewed (Priya's need)
⚠️ **Authentication features hidden:** Email recipient not visible to anon users

---

### TECHNICAL IMPLEMENTATION NOTES

**Component Architecture:**
```
<SecretFormExpress>
  └─ <SecretTextarea /> (always visible)
  └─ <ProgressiveOptions> (collapsible)
      ├─ <PassphraseField />
      ├─ <ExpirationButtonGroup />
  └─ <PrimaryAction /> (Create Link or Generate Password)
  └─ <ConfirmationScreen /> (inline, replaces form)
```

**State Management:**
```typescript
const state = {
  secret: '',
  optionsExpanded: false,
  passphrase: '',
  ttl: 604800, // 7 days default
  mode: 'conceal' | 'generate',
  confirmation: null, // response data
}
```

**Tailwind Patterns:**
- Smooth expand/collapse: `transition-all duration-300 ease-in-out`
- Button group: `flex gap-2 flex-wrap` (mobile-friendly)
- Auto-focus: `focus:ring-2 focus:ring-blue-500`
- Confirmation: `animate-fade-in` (custom animation)

---

## MODEL 2: "THE GUIDED JOURNEY"

### Philosophy

**Hand-hold the user through each decision.**

Break the process into discrete steps, each focused on a single choice. Users see progress (Step 1 of 3), can go back and edit, and get a review screen before finalizing. This reduces anxiety and ensures users understand what they're creating.

### Core Principles

1. **Step-by-step:** One decision per screen
2. **Progress indicators:** Always show where you are
3. **Review before send:** Confirmation step with editable summary
4. **Explainers:** Each step has contextual help
5. **No surprises:** Show exactly what will happen

---

### INTERACTION FLOW

#### Step 1: What Are You Sharing?

```
┌─────────────────────────────────────────────────────────┐
│  OneTimeSecret                                          │
└─────────────────────────────────────────────────────────┘

   Step 1 of 3: What are you sharing?
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

   ┌─────────────────────────────────────────────────────┐
   │                                                     │
   │  [ ] I have a secret to share                      │
   │      (password, API key, sensitive text)           │
   │                                                     │
   │  [ ] Generate a random password for me             │
   │      (we'll create a secure password)              │
   │                                                     │
   └─────────────────────────────────────────────────────┘

   ┌────────────────────────────────────────────┐
   │              Next →                        │
   └────────────────────────────────────────────┘
```

**Philosophy:** Explicit choice upfront—are you creating or generating?

---

#### Step 2a: Enter Your Secret (If "I have a secret")

```
   Step 2 of 3: Enter your secret
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

   ┌─────────────────────────────────────────────────────┐
   │                                                     │
   │  Paste your secret here...                         │
   │                                                     │
   │                                                     │
   │                                                     │
   └─────────────────────────────────────────────────────┘
                                          0 / 10,000

   💡 Your secret is encrypted and can only be viewed once.

   ┌──────────────────┐  ┌────────────────────────────┐
   │   ← Back         │  │       Next →               │
   └──────────────────┘  └────────────────────────────┘
```

---

#### Step 3: Set Security Options

```
   Step 3 of 3: Set security options
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

   🔒 Add a passphrase? (Recommended for sensitive data)

   ( ) No passphrase needed
   (•) Yes, set a passphrase

       ┌───────────────────────────────────────────┐
       │  [passphrase field]                       │
       └───────────────────────────────────────────┘

       💡 Share the passphrase separately (via phone or SMS)

   ⏱️  When should this expire?

   ( ) 1 hour     ( ) 4 hours    (•) 1 day
   ( ) 7 days     ( ) 14 days    ( ) 30 days

   ┌──────────────────┐  ┌────────────────────────────┐
   │   ← Back         │  │    Review & Create →       │
   └──────────────────┘  └────────────────────────────┘
```

**Key difference:** Radio buttons for passphrase (explicit yes/no), not optional field.

---

#### Step 4: Review & Create

```
   Review your secret link
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

   📄 Secret:  postgres://admin:xK9$... (53 characters)
                                            [Edit]

   🔒 Passphrase:  Set (strong)            [Edit]

   ⏱️  Expires:  In 1 day (Nov 19, 3:42 PM) [Edit]

   ───────────────────────────────────────────────────

   What happens next:

   ✓ Your secret will be encrypted
   ✓ You'll get a one-time link to share
   ✓ The recipient can view it once
   ✓ After viewing (or 1 day), it's deleted forever

   ┌──────────────────┐  ┌────────────────────────────┐
   │   ← Back         │  │    Create Secret Link      │
   └──────────────────┘  └────────────────────────────┘
```

**Key feature:** Full review with inline editing (each [Edit] jumps back to that step).

---

### PERSONA TESTING

#### ❌ Alex (Backend Developer - Emergency)

**Flow:** 4 screens to click through
**Time:** ~25 seconds (too slow for emergency)
**Verdict:** ❌ **FAIL** - Too many steps for urgent use case

---

#### ✅ Jamie (Support Agent)

**Flow:** Guided through each choice
**Time:** ~18 seconds
**Verdict:** ⚠️ **ACCEPTABLE** - Clear, but slower than needed

---

#### ✅ Morgan (Freelancer - Worrier)

**Flow:** Loves the review step, feels confident
**Time:** ~40 seconds (fine for low-pressure scenario)
**Verdict:** ✅ **EXCELLENT** - Builds trust, clear explanations

---

#### ❌ Priya (DevOps Engineer)

**Flow:** Finds wizard patronizing
**Time:** ~22 seconds
**Verdict:** ❌ **POOR** - Too many clicks for experienced user

---

### PROS vs CURRENT

✅ **Clarity:** Each step is focused
✅ **Review:** No surprises before creation
✅ **Trust:** Explains what happens
✅ **First-time UX:** Best for new users

### CONS vs CURRENT

❌ **Speed:** 4 screens vs. 1 screen (slower)
❌ **Clicks:** 6+ clicks required
❌ **Friction:** Can't skip steps (even if experienced)
❌ **Mobile:** Multiple screens = more scrolling

---

## MODEL 3: "THE CONVERSATIONAL INTERFACE"

### Philosophy

**Talk to the user like a human.**

Use natural language to guide the user through choices. The interface adapts based on responses, like a conversation with a helpful assistant. This feels less like a form and more like a guided dialogue.

### Core Principles

1. **Question-driven:** Ask simple questions, one at a time
2. **Adaptive:** Next question depends on previous answer
3. **Conversational tone:** Friendly, not robotic
4. **Visual cues:** Icons, animations, personality
5. **Progressive complexity:** Start simple, get advanced only if needed

---

### INTERACTION FLOW

#### Initial State

```
┌─────────────────────────────────────────────────────────┐
│  OneTimeSecret                                          │
└─────────────────────────────────────────────────────────┘

   👋 Hi! What would you like to do?

   ┌─────────────────────────────────────────────────────┐
   │                                                     │
   │  ┌──────────────────────────────────────────────┐  │
   │  │  📝  Share a secret                          │  │
   │  │      I have sensitive text to share         │  │
   │  └──────────────────────────────────────────────┘  │
   │                                                     │
   │  ┌──────────────────────────────────────────────┐  │
   │  │  🔑  Generate a password                     │  │
   │  │      Create a random, secure password       │  │
   │  └──────────────────────────────────────────────┘  │
   │                                                     │
   └─────────────────────────────────────────────────────┘
```

**User clicks "Share a secret":**

---

#### Conversation Flow

```
   👋 Great! Paste your secret below.

   ┌─────────────────────────────────────────────────────┐
   │  postgres://admin:xK9$mP2#vL5@prod-db.example.com  │
   │                                                     │
   └─────────────────────────────────────────────────────┘
                                            53 / 10,000

   ┌────────────────────────────────────────────┐
   │              Continue →                    │
   └────────────────────────────────────────────┘
```

**User clicks "Continue":**

```
   👋 Great! Paste your secret below.
      ✓ Got it! 53 characters

   🔒 Do you want to add a passphrase?

      This adds extra protection—the recipient will need
      both the link AND the passphrase to view your secret.

   ┌──────────────────────┐  ┌──────────────────────┐
   │  No, skip this       │  │  Yes, add passphrase │
   └──────────────────────┘  └──────────────────────┘
```

**User clicks "Yes, add passphrase":**

```
   👋 Great! Paste your secret below.
      ✓ Got it! 53 characters

   🔒 Do you want to add a passphrase?
      ✓ Yes

   🔐 Enter your passphrase:

   ┌─────────────────────────────────────────────────────┐
   │  [passphrase field]                                 │
   └─────────────────────────────────────────────────────┘

   💡 Remember: Share the passphrase separately!

   ┌────────────────────────────────────────────┐
   │              Continue →                    │
   └────────────────────────────────────────────┘
```

**User clicks "Continue":**

```
   👋 Great! Paste your secret below.
      ✓ Got it! 53 characters

   🔒 Do you want to add a passphrase?
      ✓ Yes (set)

   ⏱️  When should this expire?

   ┌────────────┐ ┌────────────┐ ┌────────────┐
   │  In 1 hour │ │  In 1 day  │ │  In 7 days │
   └────────────┘ └────────────┘ └────────────┘

   or choose a custom time →
```

**User clicks "In 1 hour":**

```
   👋 Great! Paste your secret below.
      ✓ Got it! 53 characters

   🔒 Do you want to add a passphrase?
      ✓ Yes (set)

   ⏱️  When should this expire?
      ✓ In 1 hour

   ✨ Perfect! Here's what will happen:

      • Your secret will be encrypted
      • You'll get a one-time link
      • It expires in 1 hour or after 1 view
      • The recipient needs the passphrase

   ┌────────────────────────────────────────────┐
   │         Create My Secret Link              │
   └────────────────────────────────────────────┘
```

---

### PERSONA TESTING

#### ❌ Alex (Backend Developer - Emergency)

**Flow:** Too chatty, too many "Continue" buttons
**Time:** ~20 seconds
**Verdict:** ❌ **FAIL** - Slows down urgent workflow

---

#### ✅ Jamie (Support Agent)

**Flow:** Clear questions, easy to follow
**Time:** ~15 seconds
**Verdict:** ✅ **GOOD** - Conversational tone reduces confusion

---

#### ✅ Morgan (Freelancer - Worrier)

**Flow:** Friendly, reassuring, builds trust
**Time:** ~35 seconds
**Verdict:** ✅ **EXCELLENT** - Feels guided, not intimidated

---

#### ⚠️ Priya (DevOps Engineer)

**Flow:** Finds conversation patronizing
**Time:** ~18 seconds
**Verdict:** ⚠️ **ACCEPTABLE** - Works, but prefers express flow

---

### PROS vs CURRENT

✅ **Friendly:** Reduces anxiety for first-timers
✅ **Guided:** Questions are clearer than form labels
✅ **Adaptive:** Can skip irrelevant questions
✅ **Personality:** Brand voice comes through

### CONS vs CURRENT

❌ **Chatty:** More words than necessary (slower)
❌ **Clicks:** Many "Continue" buttons
❌ **Screen space:** Conversation history takes vertical space
❌ **Power users:** Experienced users find it slow

---

## COMPARATIVE ANALYSIS

### Speed Comparison (Time to First Link)

| User Type | Model 1 (Express) | Model 2 (Wizard) | Model 3 (Chat) | Current |
|-----------|-------------------|------------------|----------------|---------|
| Alex      | **5s** ✅         | 25s ❌           | 20s ❌         | 30s     |
| Jamie     | **8s** ✅         | 18s ⚠️           | 15s ✅         | 25s     |
| Morgan    | 45s ⚠️            | **40s** ✅       | **35s** ✅     | 60s     |
| Priya     | **12s** ✅        | 22s ❌           | 18s ⚠️         | 20s     |

**Winner:** Model 1 (Express) - Fastest for 3 of 4 personas

---

### Clicks Comparison

| User Type | Model 1 (Express) | Model 2 (Wizard) | Model 3 (Chat) | Current |
|-----------|-------------------|------------------|----------------|---------|
| Alex      | **3 clicks** ✅   | 7 clicks ❌      | 6 clicks ❌    | 6 clicks|
| Jamie     | **2 clicks** ✅   | 7 clicks ❌      | 5 clicks ⚠️    | 5 clicks|
| Morgan    | 6 clicks ⚠️       | **7 clicks** ⚠️  | **6 clicks** ⚠️| 8 clicks|
| Priya     | **4 clicks** ✅   | 8 clicks ❌      | 6 clicks ⚠️    | 7 clicks|

**Winner:** Model 1 (Express) - Fewest clicks across all personas

---

### Satisfaction by User Type

| User Type | Model 1 (Express) | Model 2 (Wizard) | Model 3 (Chat) |
|-----------|-------------------|------------------|----------------|
| Alex      | ✅ Perfect        | ❌ Too slow      | ❌ Too chatty  |
| Jamie     | ✅ Excellent      | ⚠️ Acceptable    | ✅ Good        |
| Morgan    | ⚠️ Good           | ✅ Excellent     | ✅ Excellent   |
| Priya     | ✅ Excellent      | ❌ Poor          | ⚠️ Acceptable  |

**Winner:** Model 1 (Express) - Satisfies 3 of 4 strongly

---

### Feature Comparison

| Feature | Model 1 | Model 2 | Model 3 |
|---------|---------|---------|---------|
| Progressive disclosure | ✅ Yes | ❌ No (wizard) | ⚠️ Partial |
| Mobile-optimized | ✅ Yes | ⚠️ Partial | ⚠️ Partial |
| Review before send | ❌ No | ✅ Yes | ✅ Yes |
| Passphrase clarity | ✅ Yes | ✅ Yes | ✅ Yes |
| Feature discovery | ✅ Yes | ⚠️ Partial | ✅ Yes |
| Trust indicators | ⚠️ Needs help (?) | ✅ Built-in | ✅ Built-in |
| Power user mode | ✅ Yes (expand) | ❌ No | ❌ No |
| Accessibility | ✅ Excellent | ✅ Good | ⚠️ Complex |

---

## RECOMMENDATION

### Primary Recommendation: MODEL 1 (EXPRESS LANE)

**With selective enhancements from Model 2 and Model 3:**

**Why Model 1 Wins:**
1. ✅ **Fastest** for 3 of 4 personas
2. ✅ **Fewest clicks** across all personas
3. ✅ **Satisfies power users** (Priya) while remaining simple
4. ✅ **Progressive disclosure** scales from simple to advanced
5. ✅ **Mobile-optimized** (button chips, no wizards)

**Enhancements from Model 2:**
- ✅ Add **review step** option (for Morgan)
  - Link: "Review settings before creating →"
  - Modal shows summary + editable fields
  - Optional, not required

**Enhancements from Model 3:**
- ✅ Add **conversational copy** (friendlier tone)
  - "Your secret link is ready!" vs. "Secret created"
  - "Share this link (just once)" vs. "Link"
  - Inline tips with emoji icons

**Enhancements for Morgan (Trust):**
- ✅ Add **"How it works"** modal (help icon in header)
- ✅ Add **HTTPS badge** + "End-to-end encrypted"
- ✅ Add **"Text only"** clarification in placeholder
  - "Paste your secret here (text only, no files)..."

**Enhancements for Priya (Power User):**
- ✅ Add **"View secret status"** link (authenticated users)
- ✅ Show **"Not viewed yet"** indicator on confirmation
- ✅ Add **email notification** option (if recipient email set)

---

### Hybrid Approach: "Express Lane with Safety Rails"

**Default Flow (80% of users):**
```
1. Land → Textarea auto-focused
2. Paste secret
3. Click "Create Secret Link"
4. Link ready (2 clicks, 5 seconds)
```

**With Options (15% of users):**
```
1. Land → Textarea auto-focused
2. Paste secret
3. Click "Add passphrase or change expiration"
4. Configure options
5. Click "Create Secret Link"
6. Link ready (3-4 clicks, 10-15 seconds)
```

**With Review (5% of users - Morgan types):**
```
1. Land → Textarea auto-focused
2. Paste secret
3. Configure options
4. Click "Review settings before creating"
5. See summary modal
6. Confirm
7. Link ready (5-6 clicks, 20-30 seconds)
```

**Power User Flow (Priya):**
```
[Same as default, but confirmation screen shows:]
- "Not viewed yet" status
- Link to "View all secrets" dashboard
- Option to enable email notification
```

---

## NEXT STEPS → PHASE 4

With Model 1 (Express Lane + enhancements) selected, Phase 4 will:

1. **Define Design Principles** (3-5 core principles)
2. **Specify Interaction Details** (initial state, primary path, configuration flow)
3. **Accessibility Requirements** (keyboard nav, screen reader, WCAG 2.1 AA)
4. **Technical Approach** (component architecture, state management, Tailwind patterns)
5. **Mobile Strategy** (responsive patterns, touch targets, performance)

**Key Questions for Phase 4:**
- Exact animation timings for progressive disclosure?
- Copy-to-clipboard behavior (auto-copy vs. button)?
- Error handling patterns (inline vs. toast)?
- Success confirmation auto-dismiss timing?

---

**Document Status:** ✅ Complete
**Recommendation:** Model 1 (Express Lane) with enhancements
**Next Phase:** PHASE 4 - Design Principles & Specifications
**Date:** 2025-11-18
