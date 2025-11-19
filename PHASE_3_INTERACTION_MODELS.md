# PHASE 3: INTERACTION MODEL ALTERNATIVES
## OneTimeSecret Create-Secret Experience Redesign

**Date**: 2025-11-18
**Branch**: `claude/redesign-create-secret-01VCPSHrMm9voh36zpcZTmrD`
**Context**: Focus on utility and time-to-task-completion

---

## EXPLORATION STRATEGY

Based on Phase 2 insights, I'm exploring three fundamentally different approaches that vary along these dimensions:

| Dimension | Model A | Model B | Model C |
|-----------|---------|---------|---------|
| **Philosophy** | Input-first | Intent-first | Adaptive hybrid |
| **Structure** | Single-page progressive | Multi-step wizard | Context-aware morphing |
| **Configuration** | Minimal defaults | Guided choices | Smart detection |
| **Complexity** | Layered disclosure | Linear progression | Dynamic revelation |
| **Mobile Strategy** | Sticky actions | Bottom sheet steps | Gesture navigation |

Each model addresses the core problem differently while optimizing for **time-to-task-completion**.

---

## MODEL A: "EXPRESS LANE" (Input-First Progressive)

### Philosophy
**"Get out of the user's way. Paste → Create → Done."**

The interface assumes users know what they want. Configuration appears progressively based on user actions, not upfront. Mobile-first with desktop enhancement.

### Core Interaction Flow

```
┌─────────────────────────────────────────────────────┐
│                                                     │
│  [Paste your secret here...]                       │
│                                                     │
│  ▼ Detected: Database credentials                  │
│  ⚡ Suggested: High security (1hr, passphrase)     │
│                                                     │
└─────────────────────────────────────────────────────┘
                      │
                      ▼
              [Create Secret] ← Sticky button (mobile)
                      │
                      ▼
┌─────────────────────────────────────────────────────┐
│  ✓ Secret created                                   │
│  🔗 https://onetimesecret.com/abc123                │
│  📋 [Copy Link]  🔥 [Burn]  📧 [Email]  📱 [QR]    │
└─────────────────────────────────────────────────────┘
```

### Detailed UX Walkthrough

#### Initial State (Desktop)
```
┌──────────────────────────────────────────────────────────────┐
│  OneTimeSecret                         [Maya] [⚙️ Settings]  │
├──────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌────────────────────────────────────────────────────────┐ │
│  │                                                        │ │
│  │  Paste your secret here...                            │ │
│  │                                                        │ │
│  │                                                        │ │
│  │                                                        │ │
│  └────────────────────────────────────────────────────────┘ │
│  0 / 10,000 characters                                      │
│                                                               │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ 💡 Quick Actions                                     │   │
│  │  ⚡ Express (5s)    🔒 Secure (15s)   🔑 Generate   │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                               │
│                                       [Create Secret] ──────►│
│                                        ↑ disabled until input│
└──────────────────────────────────────────────────────────────┘
```

**Key Design Decisions**:
- **Large textarea** dominates viewport (80% height on desktop, full on mobile)
- **Character counter** subtle until 50% capacity
- **Quick Actions** visible but secondary (not blocking)
- **Create button** persistent, disabled state shows when ready
- **No visible options** until content detected or user explores

#### After Content Paste (Auto-Detection Active)

User pastes:
```
DB_HOST=prod.example.com
DB_USER=admin
DB_PASS=SuperSecret123!
```

Interface responds:
```
┌──────────────────────────────────────────────────────────────┐
│  OneTimeSecret                         [Maya] [⚙️ Settings]  │
├──────────────────────────────────────────────────────────────┤
│  ┌────────────────────────────────────────────────────────┐ │
│  │ DB_HOST=prod.example.com                              │ │
│  │ DB_USER=admin                                         │ │
│  │ DB_PASS=SuperSecret123!                               │ │
│  └────────────────────────────────────────────────────────┘ │
│  98 / 10,000 characters                                     │
│                                                               │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ 🔍 Detected: Database credentials                    │   │
│  │ ⚡ Recommended: High security                        │   │
│  │    → Expires in 1 hour                               │   │
│  │    → Passphrase required                             │   │
│  │    → [Apply] or [Customize]                          │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                               │
│  [Create Secret] ◄──── Enabled, pulsing (ready to submit)   │
└──────────────────────────────────────────────────────────────┘
```

**Auto-Detection Logic** (Pattern Matching):
- `DB_*`, `DATABASE_*`, `password`, `credentials` → High security
- `wifi`, `ssid`, `wpa` → QR code suggested
- Markdown headers `#`, `##`, code blocks → Markdown rendering
- Phone numbers, TOTP seeds → QR code suggested
- Default: Medium security (24hr, no passphrase)

**User Actions**:
1. **Click [Apply]** → Accepts recommendation, creates secret (2 seconds)
2. **Click [Customize]** → Expands options panel inline
3. **Click [Create Secret]** → Uses current settings (defaults or applied)

#### Expanded Options Panel (If User Clicks "Customize")

```
┌──────────────────────────────────────────────────────────────┐
│  [Content in textarea above...]                              │
│  98 / 10,000 characters                                      │
│                                                               │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ Security Level                                         │ │
│  │  ○ Express (7 days, no passphrase)                    │ │
│  │  ● Secure (1 hour, passphrase required) ← Recommended │ │
│  │  ○ Custom (configure below)                           │ │
│  │                                                         │ │
│  │ ┌────────────────┬──────────────────────────────────┐ │ │
│  │ │ Expires in     │ Passphrase (optional)           │ │ │
│  │ │ [1 hour ▼]     │ [••••••••••] 👁️               │ │ │
│  │ │                │ Auto-generated • [Regenerate]    │ │ │
│  │ └────────────────┴──────────────────────────────────┘ │ │
│  │                                                         │ │
│  │ Advanced                                                │ │
│  │  □ Send via email to: [_________________]              │ │
│  │  □ Show as QR code after creation                      │ │
│  │  □ Enable markdown rendering                           │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                               │
│  [Create Secret]                                             │
└──────────────────────────────────────────────────────────────┘
```

**Progressive Disclosure Strategy**:
- **Default**: Security level presets (90% of users stop here)
- **Custom**: Expands TTL + Passphrase fields (9% of users)
- **Advanced**: Checkboxes for special features (1% of users)

#### Mobile Flow (iPhone)

**Initial State**:
```
┌─────────────────────┐
│ OneTimeSecret       │
├─────────────────────┤
│                     │
│ Paste secret...     │
│                     │
│                     │
│                     │
│                     │
│                     │
│                     │
│                     │
└─────────────────────┘
│                     │ ← Sticky footer
│ [Create Secret]     │
└─────────────────────┘
```

**After Paste (Bottom Sheet Appears)**:
```
┌─────────────────────┐
│ DB_HOST=prod...     │
│ DB_USER=admin       │
│ DB_PASS=Super...    │
├─────────────────────┤
│ ▲ Swipe up          │ ← Bottom sheet handle
├─────────────────────┤
│ 🔍 Database creds   │
│ ⚡ High security    │
│  [Apply] [Custom]   │
└─────────────────────┘
│ [Create Secret]     │ ← Sticky footer (always visible)
└─────────────────────┘
```

**Swipe Up → Full Options**:
```
┌─────────────────────┐
│ ─────  (drag down) │
│                     │
│ Security Level      │
│  ○ Express          │
│  ● Secure ✓         │
│  ○ Custom           │
│                     │
│ [Apply]             │
│                     │
│ Or customize:       │
│  Expires [1hr ▼]    │
│  Passphrase [•••]   │
│                     │
└─────────────────────┘
│ [Create Secret]     │
└─────────────────────┘
```

**Mobile Gestures**:
- **Swipe up** on bottom sheet → Expand options
- **Swipe down** on options → Collapse to recommendation
- **Long-press Create** → Show quick share menu (QR, Email, Copy)

#### After Creation (Receipt Page)

```
┌──────────────────────────────────────────────────────────────┐
│  ✓ Secret Created                                            │
├──────────────────────────────────────────────────────────────┤
│                                                               │
│  🔗 Share Link                                               │
│  https://onetimesecret.com/private/abc123xyz                 │
│                                                               │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  📋 Copy Link    📱 Show QR    📧 Email                │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                               │
│  🔐 Passphrase (share separately)                            │
│  debug-maya-nov18                                            │
│  📋 Copy Passphrase                                          │
│                                                               │
│  ⏱️ Expires in 59 minutes (3:45 PM today)                   │
│  👁️ Not yet viewed                                          │
│                                                               │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  🔥 Burn Secret (immediate destruction)                │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                               │
│  [Create Another Secret]                                     │
└──────────────────────────────────────────────────────────────┘
```

**Copy Workflow Enhancement**:
- First click "Copy Link" → Link to clipboard, button shows "✓ Copied"
- Second click "Copy Passphrase" → Passphrase to clipboard
- Browser clipboard API supports "clipboard history" (some browsers)
- On mobile: Share sheet integration (native share)

### Accessibility Considerations

#### Keyboard Navigation
1. **Tab** → Focus textarea
2. **Cmd/Ctrl + V** → Paste (auto-detection triggers)
3. **Tab** → Focus [Apply] in recommendation banner
4. **Enter** → Apply recommendation
5. **Tab** → Focus [Create Secret]
6. **Enter** → Submit

**Power User Flow**: Paste (Cmd+V) → Apply (Tab, Enter) → Create (Tab, Enter) = **3 keystrokes**

#### Screen Reader Experience
```
Landmark: Main content
  Form: Create secret
    Textarea: "Secret content, required, 0 of 10,000 characters"
    Alert: "Detected database credentials. Recommended: High security, expires in 1 hour, passphrase required."
    Button: "Apply recommendation"
    Button: "Customize security settings"
    Button: "Create secret, enabled"
```

**ARIA Live Regions**:
- Auto-detection banner: `aria-live="polite"` (announces recommendation)
- Character counter: `aria-live="polite"` at 80%, 90%, 100% thresholds
- Error messages: `aria-live="assertive"` (immediate announcement)

#### Focus Management
- After paste → Focus stays in textarea (user may continue editing)
- After recommendation appears → Optional alert, no focus steal
- After "Apply" → Focus moves to [Create Secret] button
- After submit → Focus moves to "Copy Link" button on receipt

### Pros and Cons

#### ✅ Pros

1. **Fastest for common cases** — Paste → Apply → Create = 5-10 seconds
2. **Smart defaults** — Auto-detection reduces decision-making
3. **Mobile-optimized** — Sticky button, bottom sheet, gesture nav
4. **Keyboard efficient** — Power users can complete in 3 keystrokes
5. **Progressive complexity** — Beginners see simple interface, experts can customize
6. **Clear recommendations** — Tells users "why" (detected credentials → high security)

#### ❌ Cons

1. **Auto-detection can be wrong** — User may not notice recommendation applied
2. **Hidden features** — Advanced options (email, QR) buried in "Customize"
3. **Pattern matching complexity** — Requires robust detection logic (maintenance burden)
4. **One-size-fits-all for undetected content** — Generic text gets medium security (may not match intent)
5. **Bottom sheet unfamiliar** — iOS users know it, Android/desktop users may not
6. **Preset names subjective** — "Express" vs "Secure" may confuse non-technical users

### Edge Cases

#### What if auto-detection is wrong?
- User pastes credentials, system detects as "generic text"
- **Solution**: User clicks [Customize] → Manually selects "Secure" preset
- **Prevention**: Show detection confidence ("Possibly credentials? Recommended: Secure")

#### What if user wants Generate Password?
- No textarea content needed for Generate
- **Solution**: Quick Actions include "🔑 Generate" button
- Clicking opens mini-flow: "Generate Password → [Length] [Complexity] → [Generate]"
- Shows generated password + creates secret in one action

#### What if user wants QR code but didn't select it?
- Creates secret with default flow
- Receipt page shows "📱 Show QR" button
- **Future enhancement**: QR code displayed inline if content is short (<50 chars)

### Technical Implementation Notes

#### Auto-Detection Patterns (Zod + Regex)
```typescript
const contentPatterns = {
  credentials: /(?:password|passwd|pwd|secret|token|api[_-]?key|db[_-]?pass)/i,
  database: /(?:db_host|db_user|database|connection[_-]?string)/i,
  wifi: /(?:ssid|wpa|wifi|wireless)/i,
  totp: /(?:totp|otp|2fa|authenticator)/i,
  markdown: /^#+\s|\n#+\s|```/,
  email: /@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/,
};

function detectContentType(content: string): ContentType {
  if (contentPatterns.credentials.test(content) || contentPatterns.database.test(content)) {
    return 'credentials'; // → High security
  }
  if (contentPatterns.wifi.test(content) && content.length < 100) {
    return 'wifi'; // → QR code
  }
  if (contentPatterns.markdown.test(content)) {
    return 'markdown'; // → Enable rendering
  }
  return 'generic'; // → Medium security
}
```

#### Security Presets (Config-Driven)
```typescript
const securityPresets = {
  express: {
    ttl: 7 * 24 * 3600, // 7 days
    passphrase: null,
    label: 'Express (7 days, no passphrase)',
    icon: '⚡',
  },
  secure: {
    ttl: 3600, // 1 hour
    passphrase: 'auto-generate',
    label: 'Secure (1 hour, passphrase)',
    icon: '🔒',
  },
  custom: {
    ttl: null, // User-defined
    passphrase: null, // User-defined
    label: 'Custom',
    icon: '⚙️',
  },
};
```

#### Mobile Bottom Sheet Component
```vue
<template>
  <Teleport to="body">
    <div class="bottom-sheet" :class="{ expanded }">
      <div class="handle" @click="toggle" @touchstart="handleDragStart">
        <span class="handle-bar"></span>
      </div>
      <div class="content">
        <slot></slot>
      </div>
    </div>
  </Teleport>
</template>

<script setup lang="ts">
// Supports swipe gestures, spring animations, safe area insets
// Uses Tailwind @container queries for responsive content
</script>
```

---

## MODEL B: "GUIDED JOURNEY" (Intent-First Wizard)

### Philosophy
**"Ask what you want, then guide you there efficiently."**

The interface starts with intent discovery (what are you sharing?), then presents a tailored flow. Each step is focused, mobile-friendly, and optimized for that specific use case.

### Core Interaction Flow

```
Step 1: Intent Discovery
┌─────────────────────────────────────────────────────┐
│  What do you want to share?                         │
│                                                      │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐│
│  │ 📝 Text     │  │ 🔑 Password │  │ 📄 Document ││
│  │ or Code     │  │ (generate)  │  │ (formatted) ││
│  └─────────────┘  └─────────────┘  └─────────────┘│
└─────────────────────────────────────────────────────┘
              │               │                │
              ▼               ▼                ▼
          Text Flow    Password Flow    Document Flow
```

### Detailed UX Walkthrough

#### Step 1: Intent Discovery (All Users See This)

```
┌──────────────────────────────────────────────────────────────┐
│  OneTimeSecret                         [Maya] [⚙️ Settings]  │
├──────────────────────────────────────────────────────────────┤
│                                                               │
│                  What do you want to share?                  │
│                                                               │
│  ┌──────────────────┐  ┌──────────────────┐  ┌────────────┐│
│  │   📝 Text        │  │  🔑 Password     │  │ 📄 Document││
│  │                  │  │                  │  │            ││
│  │ Paste sensitive  │  │ Generate secure  │  │ Formatted  ││
│  │ text, code, or   │  │ password to      │  │ onboarding ││
│  │ credentials      │  │ share            │  │ content    ││
│  │                  │  │                  │  │            ││
│  │    [Share →]     │  │   [Generate →]   │  │ [Create →] ││
│  └──────────────────┘  └──────────────────┘  └────────────┘│
│                                                               │
│  ┌──────────────────────────────────────────────────────────┐│
│  │ 💡 More options: WiFi QR Code • Request a Secret         ││
│  └──────────────────────────────────────────────────────────┘│
│                                                               │
└──────────────────────────────────────────────────────────────┘
```

**Why This Works**:
- **Removes ambiguity** — User declares intent upfront
- **Tailored flows** — Each card leads to optimized path
- **Discoverability** — Shows all primary use cases (no hidden dropdowns)
- **Progressive disclosure** — "More options" for edge cases

#### Flow A: Share Text/Code (User Clicks "📝 Text")

**Step 2A: Content Input**
```
┌──────────────────────────────────────────────────────────────┐
│  ← Back          Share Text or Code               Step 1 of 3│
├──────────────────────────────────────────────────────────────┤
│                                                               │
│  Paste your secret content                                   │
│                                                               │
│  ┌────────────────────────────────────────────────────────┐ │
│  │                                                        │ │
│  │                                                        │ │
│  │                                                        │ │
│  │                                                        │ │
│  │                                                        │ │
│  └────────────────────────────────────────────────────────┘ │
│  0 / 10,000 characters                                      │
│                                                               │
│                                          [Next: Security →]   │
└──────────────────────────────────────────────────────────────┘
```

**Step 3A: Security Settings**
```
┌──────────────────────────────────────────────────────────────┐
│  ← Back          Share Text or Code               Step 2 of 3│
├──────────────────────────────────────────────────────────────┤
│                                                               │
│  How sensitive is this content?                              │
│                                                               │
│  ┌──────────────────────────────────────────────────────────┐│
│  │  ○ Low Risk                                              ││
│  │     Expires in 7 days • No passphrase                    ││
│  │     Example: Meeting notes, temporary links              ││
│  │                                                           ││
│  │  ● Medium Risk (Recommended)                             ││
│  │     Expires in 24 hours • Optional passphrase            ││
│  │     Example: API tokens, temporary credentials           ││
│  │                                                           ││
│  │  ○ High Risk                                             ││
│  │     Expires in 1 hour • Passphrase required              ││
│  │     Example: Production passwords, financial data        ││
│  └──────────────────────────────────────────────────────────┘│
│                                                               │
│  🔐 Passphrase (optional for Medium)                         │
│  [________________________] Auto-generated • 👁️             │
│                                                               │
│                                     [Next: Delivery Method →]│
└──────────────────────────────────────────────────────────────┘
```

**Step 4A: Delivery Method**
```
┌──────────────────────────────────────────────────────────────┐
│  ← Back          Share Text or Code               Step 3 of 3│
├──────────────────────────────────────────────────────────────┤
│                                                               │
│  How will you share this secret?                             │
│                                                               │
│  ┌──────────────────────────────────────────────────────────┐│
│  │  ● Copy Link                                             ││
│  │     I'll paste it into Slack, email, or another app      ││
│  │                                                           ││
│  │  ○ Show QR Code                                          ││
│  │     Recipient will scan with their phone camera          ││
│  │                                                           ││
│  │  ○ Send via Email                                        ││
│  │     To: [_____________________@example.com]              ││
│  │                                                           ││
│  └──────────────────────────────────────────────────────────┘│
│                                                               │
│                                          [Create Secret →]    │
└──────────────────────────────────────────────────────────────┘
```

**Result Page**:
- **Copy Link** → Shows link with copy button + passphrase
- **QR Code** → Fullscreen QR code display
- **Email** → Confirmation "Email sent to us...@example.com"

#### Flow B: Generate Password (User Clicks "🔑 Password")

**Step 2B: Password Options**
```
┌──────────────────────────────────────────────────────────────┐
│  ← Back          Generate Password                 Step 1 of 2│
├──────────────────────────────────────────────────────────────┤
│                                                               │
│  Password Settings                                           │
│                                                               │
│  Length: [12 ▼]  (8-64 characters)                          │
│                                                               │
│  Include:                                                     │
│   ☑ Uppercase (A-Z)                                          │
│   ☑ Lowercase (a-z)                                          │
│   ☑ Numbers (0-9)                                            │
│   ☑ Symbols (!@#$%)                                          │
│   ☐ Exclude ambiguous (0, O, l, I)                           │
│                                                               │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  Generated Password (preview):                         │ │
│  │  aB3$xZ9!kL2m                                          │ │
│  │  [Regenerate]                                          │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                               │
│  Expires in: [1 hour ▼]                                      │
│                                                               │
│                                       [Next: Delivery →]      │
└──────────────────────────────────────────────────────────────┘
```

**Step 3B: Delivery Method** (Same as Flow A Step 4)

#### Flow C: Create Document (User Clicks "📄 Document")

**Step 2C: Markdown Editor**
```
┌──────────────────────────────────────────────────────────────┐
│  ← Back          Create Document                   Step 1 of 2│
├──────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌─────────────────────┬────────────────────────────────────┐│
│  │ ✏️ Edit             │ 👁️ Preview                        ││
│  ├─────────────────────┼────────────────────────────────────┤│
│  │ # Welcome!          │ Welcome!                           ││
│  │                     │ ───────────────────                ││
│  │ Your credentials:   │                                    ││
│  │                     │ Your credentials:                  ││
│  │ - **Email**: user   │ • Email: user@example.com          ││
│  │ - **Pass**: temp123 │ • Pass: temp123                    ││
│  │                     │                                    ││
│  └─────────────────────┴────────────────────────────────────┘│
│                                                               │
│  💡 Tip: Use ` for code, ** for bold, # for headers         │
│                                                               │
│  Expires in: [3 days ▼]                                      │
│                                                               │
│                                       [Next: Email Delivery →]│
└──────────────────────────────────────────────────────────────┘
```

**Step 3C: Email Delivery** (Documents auto-assume email delivery)
```
┌──────────────────────────────────────────────────────────────┐
│  ← Back          Create Document                   Step 2 of 2│
├──────────────────────────────────────────────────────────────┤
│                                                               │
│  Send to:                                                    │
│  [recipient@example.com________________________]             │
│                                                               │
│  Email Subject:                                              │
│  [Your secure onboarding credentials___________]             │
│                                                               │
│  Email Message (optional):                                   │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ Hi Sarah,                                              │ │
│  │                                                        │ │
│  │ Here are your login credentials for your first day.   │ │
│  │ Please change all passwords after logging in.         │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                               │
│                                          [Send Email →]       │
└──────────────────────────────────────────────────────────────┘
```

### Mobile Wizard Adaptation

**Bottom Sheet Multi-Step**:
```
Step 1:
┌─────────────────────┐
│ What to share?      │
├─────────────────────┤
│ ▲                   │ ← Swipe up to see all options
├─────────────────────┤
│ 📝 Text or Code     │
│ [Share →]           │
│                     │
│ 🔑 Password         │
│ [Generate →]        │
│                     │
│ 📄 Document         │
│ [Create →]          │
└─────────────────────┘

Step 2 (After selecting Text):
┌─────────────────────┐
│ Paste secret...     │
│                     │
│                     │
├─────────────────────┤
│ 1 of 3              │
│ [Next: Security →]  │
└─────────────────────┘

Step 3 (Security):
┌─────────────────────┐
│ How sensitive?      │
│ ○ Low Risk          │
│ ● Medium Risk       │
│ ○ High Risk         │
├─────────────────────┤
│ Passphrase          │
│ [auto-gen] 👁️      │
├─────────────────────┤
│ 2 of 3              │
│ [Next: Delivery →]  │
└─────────────────────┘

Step 4 (Delivery):
┌─────────────────────┐
│ How to share?       │
│ ● Copy Link         │
│ ○ Show QR Code      │
│ ○ Send Email        │
├─────────────────────┤
│ 3 of 3              │
│ [Create Secret →]   │
└─────────────────────┘
```

**Mobile Navigation**:
- Swipe left/right to go back/forward between steps
- Progress indicator (1 of 3, 2 of 3, 3 of 3)
- Each step fills screen (no scrolling within step)

### Accessibility Considerations

#### Keyboard Navigation
- Each wizard step is a `<fieldset>` with `<legend>`
- Radio buttons grouped with `role="radiogroup"`
- Tab order: Form elements → [Back] → [Next]
- Enter/Space on [Next] advances

#### Screen Reader Experience
```
Step 1:
  Heading: "What do you want to share?"
  Group: "Sharing options"
    Button: "Share text or code"
    Button: "Generate password"
    Button: "Create document"

Step 2 (Text flow):
  Heading: "Share Text or Code, Step 1 of 3"
  Landmark: Navigation
    Link: "Back to sharing options"
  Form: "Secret content"
    Textarea: "Paste your secret content, required"
    Status: "0 of 10,000 characters"
  Button: "Next: Security settings"
```

### Pros and Cons

#### ✅ Pros

1. **Eliminates ambiguity** — User declares intent, sees tailored flow
2. **Focused decisions** — One question per step, reduces cognitive load
3. **Discoverable features** — QR code, email, markdown all presented upfront
4. **Mobile-friendly** — Each step fits in viewport (no scrolling mid-step)
5. **Educational** — Explains risk levels with examples (helps users choose correctly)
6. **Linear mental model** — Users understand progress (1 of 3, 2 of 3)

#### ❌ Cons

1. **More clicks** — 3-4 steps vs 1-2 in Express model (slower for power users)
2. **No quick path** — All users go through wizard (no "paste and go" shortcut)
3. **Repetitive for frequent users** — Intent discovery every time gets tedious
4. **Higher maintenance** — Multiple flows = more code, more testing
5. **Decision fatigue** — Asking questions feels like work (vs smart defaults)
6. **Limited shortcuts** — Hard to add keyboard power-user paths

### Edge Cases

#### What if user realizes they picked wrong flow?
- **Solution**: [← Back] button at top always returns to intent discovery
- **Prevention**: Clear descriptions on intent cards ("Example: Production passwords")

#### What if user wants to skip security configuration?
- **Solution**: Pre-select "Medium Risk (Recommended)" by default
- User can click [Next] immediately if they accept default
- Still requires interaction (can't skip step entirely for audit reasons)

#### What if user wants both QR code AND email?
- **Current flow**: Must choose one delivery method
- **Enhancement**: Allow multi-select: ☑ Copy Link  ☑ Show QR  ☑ Email
- Receipt page shows all selected delivery methods

### Technical Implementation Notes

#### Wizard State Management (Vue Router)
```typescript
// routes/wizard.ts
const wizardRoutes = [
  {
    path: '/create',
    component: WizardContainer,
    children: [
      { path: '', name: 'intent', component: IntentDiscovery },
      { path: 'text/content', name: 'text-content', component: TextContent },
      { path: 'text/security', name: 'text-security', component: SecuritySettings },
      { path: 'text/delivery', name: 'text-delivery', component: DeliveryMethod },
      { path: 'password/options', name: 'password-options', component: PasswordOptions },
      { path: 'password/delivery', name: 'password-delivery', component: DeliveryMethod },
      { path: 'document/editor', name: 'document-editor', component: MarkdownEditor },
      { path: 'document/email', name: 'document-email', component: EmailCompose },
    ],
  },
];
```

#### Wizard Store (Pinia)
```typescript
interface WizardState {
  intent: 'text' | 'password' | 'document' | null;
  currentStep: number;
  totalSteps: number;
  data: {
    content?: string;
    securityLevel?: 'low' | 'medium' | 'high';
    passphrase?: string;
    ttl?: number;
    deliveryMethod?: 'link' | 'qr' | 'email';
    recipient?: string;
    passwordOptions?: PasswordGenOptions;
  };
}

const useWizardStore = defineStore('wizard', {
  actions: {
    async nextStep() {
      // Validate current step
      // Navigate to next route
      // Update progress
    },
    previousStep() {
      // Navigate back
    },
    reset() {
      // Clear all data, return to intent discovery
    },
  },
});
```

---

## MODEL C: "CONTEXTUAL CHAMELEON" (Adaptive Hybrid)

### Philosophy
**"The interface adapts to you, not the other way around."**

The form morphs based on detected context (content type, device, user behavior, time of day). Combines best of both worlds: fast defaults for experts, guided help for beginners. Uses AI/heuristics for smart adaptation.

### Core Interaction Flow

```
Initial State (Adaptive)
┌─────────────────────────────────────────────────────┐
│  [Context-aware greeting]                           │
│  "Good morning, Maya" or "Quick share" (rush hour)  │
│                                                      │
│  [Adaptive input area]                              │
│  - Large textarea if returning user (knows flow)    │
│  - Intent buttons if new user (needs guidance)      │
│  - QR camera if mobile + WiFi detected nearby       │
└─────────────────────────────────────────────────────┘
                      ↓
        [Content detection + behavioral analysis]
                      ↓
┌─────────────────────────────────────────────────────┐
│  [Morphed interface]                                │
│  - Shows relevant options only                      │
│  - Hides unnecessary fields                         │
│  - Adapts to device orientation, time, urgency      │
└─────────────────────────────────────────────────────┘
```

### Detailed UX Walkthrough

#### Scenario 1: Returning Power User (Desktop, 2 PM)

**Initial State** (Optimized for Speed):
```
┌──────────────────────────────────────────────────────────────┐
│  OneTimeSecret                         [Maya] [⚙️ Settings]  │
├──────────────────────────────────────────────────────────────┤
│                                                               │
│  ⚡ Quick Share                        [Cmd+N keyboard hint] │
│                                                               │
│  ┌────────────────────────────────────────────────────────┐ │
│  │                                                        │ │
│  │  [Paste or type secret...]  ← Auto-focused           │ │
│  │                                                        │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                               │
│  Recent: 🔒 Secure (your usual)   or   ⚙️ Customize         │
│                                                               │
│  [Create Secret]  ← Ready, just paste + click               │
│                                                               │
└──────────────────────────────────────────────────────────────┘
```

**Why This Adaptation**:
- **Behavioral**: Maya created 5 secrets last week, all with "Secure" preset
- **Time**: 2 PM = work hours, likely sharing work content (not personal)
- **Device**: Desktop = likely has keyboard, show keyboard hints
- **Preference**: Remembers Maya's most-used settings ("Secure")

**After Paste** (DB credentials detected):
```
┌──────────────────────────────────────────────────────────────┐
│  [Textarea with DB credentials...]                           │
│                                                               │
│  🔍 Detected: Production credentials                         │
│  ⚠️ This looks sensitive. Using your "Secure" settings:     │
│     → 1 hour expiration                                      │
│     → Passphrase: "debug-maya-1730" [👁️]                   │
│     → [✓] Applied                                            │
│                                                               │
│  [Create Secret]  ← One click to finish                      │
└──────────────────────────────────────────────────────────────┘
```

**Time-to-Task**: Paste (Cmd+V) → Create (Click) = **2 seconds**

#### Scenario 2: First-Time User (Mobile, 7 PM)

**Initial State** (Onboarding Mode):
```
┌─────────────────────┐
│ OneTimeSecret       │
├─────────────────────┤
│ 👋 Welcome!         │
│                     │
│ Share sensitive     │
│ info securely:      │
│                     │
│ • Self-destructing  │
│ • One-time view     │
│ • End-to-end crypto │
│                     │
│ What do you want    │
│ to share today?     │
│                     │
│ ┌─────────────────┐ │
│ │ 📝 Text/Code    │ │
│ └─────────────────┘ │
│ ┌─────────────────┐ │
│ │ 🔑 Password     │ │
│ └─────────────────┘ │
│ ┌─────────────────┐ │
│ │ 📱 WiFi QR Code │ │
│ └─────────────────┘ │
└─────────────────────┘
```

**Why This Adaptation**:
- **New user**: No cookies, first visit → Show onboarding
- **Mobile**: Small screen → Use wizard (better than cramped form)
- **Evening**: 7 PM = personal time, suggest WiFi sharing (common use case)
- **Location**: If near home WiFi → Prioritize "📱 WiFi QR Code" button

#### Scenario 3: Mobile + Near WiFi Network

**Initial State** (Context-Aware):
```
┌─────────────────────┐
│ OneTimeSecret       │
├─────────────────────┤
│ Connected to:       │
│ "Home WiFi"         │
│                     │
│ 💡 Share this WiFi? │
│                     │
│ ┌─────────────────┐ │
│ │ 📱 Create QR    │ │
│ │    Code         │ │
│ └─────────────────┘ │
│                     │
│ Or share something  │
│ else:               │
│ • Text/Code         │
│ • Password          │
└─────────────────────┘
```

**If User Clicks "Create QR"**:
```
┌─────────────────────┐
│ Share "Home WiFi"   │
├─────────────────────┤
│ Password:           │
│ [MyWiFiPass123]     │
│                     │
│ Expires in:         │
│ [4 hours ▼]         │
│ (duration of party) │
│                     │
│ ┌─────────────────┐ │
│ │ Generate QR →   │ │
│ └─────────────────┘ │
└─────────────────────┘
```

**Result**: Fullscreen QR code, guest scans, connects to WiFi

**Why This Adaptation**:
- **Context**: Browser has WiFi API access → Detected "Home WiFi" connection
- **Assumption**: User on home network at 7 PM → Likely hosting visitors
- **Shortcut**: Pre-fills WiFi password (if accessible), skips manual typing
- **UX**: Offers fastest path to common task (QR code for WiFi sharing)

#### Scenario 4: Desktop + Urgent Content (Rush Hour Detection)

**Initial State** (Minimal Friction):
```
┌──────────────────────────────────────────────────────────────┐
│  ⚡ Express Mode                                  [Settings] │
├──────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌────────────────────────────────────────────────────────┐ │
│  │                                                        │ │
│  │  [Paste secret here — auto-creates in 5 seconds]      │ │
│  │                                                        │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                               │
│  ⏱️ Auto-submit in: 5... 4... 3...                          │
│  (Click to cancel auto-submit)                               │
│                                                               │
│  Using: Medium security (24hr, optional passphrase)          │
│  [Customize before submit]                                   │
└──────────────────────────────────────────────────────────────┘
```

**Why This Adaptation**:
- **Time**: 9 AM (start of workday) or 5 PM (end of workday) = rush hour
- **Behavioral**: User just created 3 secrets in last 10 minutes (rapid-fire mode)
- **Urgency**: Assume user is in hurry, offer auto-submit countdown
- **Safety**: 5-second delay allows cancellation if user changes mind

**After Paste** (Auto-Submit Countdown):
```
┌──────────────────────────────────────────────────────────────┐
│  [Textarea with pasted content...]                           │
│                                                               │
│  ⏱️ Auto-creating in: 3... 2... 1...                         │
│                                                               │
│  [Cancel] ← Click to customize settings                      │
│                                                               │
│  ✓ Ready to create with Medium security                     │
└──────────────────────────────────────────────────────────────┘
```

If user doesn't click [Cancel], secret auto-creates after 5s.

**Time-to-Task**: Paste (Cmd+V) → Wait 5s → Auto-created = **5 seconds passive**

### Adaptive Rules Engine

#### Context Detection Signals

```typescript
interface UserContext {
  // Device
  deviceType: 'mobile' | 'tablet' | 'desktop';
  screenSize: { width: number; height: number };
  orientation: 'portrait' | 'landscape';

  // User Behavior
  isNewUser: boolean;
  secretsCreatedLast7Days: number;
  mostUsedPreset?: 'express' | 'secure' | 'custom';
  averageTimeToCreate: number; // seconds

  // Temporal
  timeOfDay: 'morning' | 'afternoon' | 'evening' | 'night';
  dayOfWeek: 'weekday' | 'weekend';

  // Environmental (optional, privacy-respecting)
  connectedToWiFi?: boolean;
  wifiNetworkName?: string; // Only if user grants permission

  // Content (detected after paste)
  contentType?: 'credentials' | 'wifi' | 'markdown' | 'generic';
  contentLength: number;
}

function determineUIMode(context: UserContext): UIMode {
  // New user + mobile → Wizard with onboarding
  if (context.isNewUser && context.deviceType === 'mobile') {
    return 'wizard-with-onboarding';
  }

  // Power user + desktop → Express mode
  if (context.secretsCreatedLast7Days > 5 && context.deviceType === 'desktop') {
    return 'express-with-shortcuts';
  }

  // WiFi context + mobile → WiFi QR shortcut
  if (context.connectedToWiFi && context.deviceType === 'mobile') {
    return 'wifi-qr-shortcut';
  }

  // Rush hour + rapid creation → Auto-submit mode
  if (['morning', 'evening'].includes(context.timeOfDay) &&
      context.averageTimeToCreate < 10) {
    return 'auto-submit-express';
  }

  // Default: Standard progressive mode
  return 'standard-progressive';
}
```

#### Adaptation Matrix

| Context | UI Mode | Primary Feature | Time-to-Task |
|---------|---------|-----------------|--------------|
| **New + Mobile** | Wizard | Intent discovery | 20-30s |
| **Power + Desktop** | Express | Keyboard shortcuts | 2-5s |
| **WiFi + Mobile** | QR Shortcut | WiFi sharing | 5-10s |
| **Rush Hour** | Auto-submit | 5s countdown | 5s passive |
| **Evening + Personal** | Guided | Security education | 15-25s |
| **Default** | Progressive | Smart defaults | 10-15s |

### Accessibility Considerations

#### Adaptive Accessibility
- **Low vision**: Larger text, high contrast mode auto-enabled if system preference detected
- **Motor impairment**: Auto-submit countdown extended to 10s (detected via slow interaction patterns)
- **Screen reader**: Announces mode changes ("Express mode activated for faster sharing")

#### Keyboard Shortcuts (Context-Aware)
- **Power users**: `Cmd+K` to focus textarea, `Cmd+Enter` to submit, `Cmd+G` to generate password
- **New users**: Shortcuts hidden (not shown in UI) until 3+ secrets created

### Pros and Cons

#### ✅ Pros

1. **Fastest for everyone** — Adapts to user's skill level and context
2. **Self-improving** — Learns from user behavior (most-used presets, typical TTLs)
3. **Context-aware magic** — WiFi sharing, rush hour mode, mobile optimization
4. **Reduces decision fatigue** — Only shows relevant options (hides unnecessary complexity)
5. **Progressive onboarding** — New users get guidance, then "graduates" to express mode
6. **Accessibility built-in** — Detects system preferences, adapts automatically

#### ❌ Cons

1. **Unpredictable** — Users may not understand why interface changes (feels inconsistent)
2. **Complex implementation** — Requires sophisticated detection logic, A/B testing, ML potentially
3. **Privacy concerns** — WiFi detection, behavioral tracking (even if local-only)
4. **Hard to test** — Many permutations (new user + mobile + evening + WiFi = specific UI)
5. **Maintenance burden** — Adaptive rules require tuning, updating as usage patterns change
6. **User confusion** — "Why did my interface change?" (needs explanation/settings toggle)
7. **Auto-submit risk** — User may not want 5s countdown (needs easy cancel)

### Edge Cases

#### What if adaptive detection is wrong?
- **Example**: Detects "credentials" but it's just sample code
- **Solution**: User can click "This is not sensitive" → Switches to Medium security
- **Learning**: System remembers user correction (future similar content → Medium)

#### What if user wants consistent interface?
- **Solution**: Settings → "Always use Standard Mode" (disables adaptation)
- **Default**: Adaptation opt-out available in settings

#### What if WiFi detection fails?
- **Fallback**: Standard interface (no WiFi shortcut)
- **Privacy**: WiFi detection requires user permission (first-time prompt)

### Technical Implementation Notes

#### Behavioral Tracking (Privacy-Respecting)
```typescript
// Local storage only, no server tracking
interface UserBehaviorProfile {
  version: 1,
  secrets: {
    total: number,
    last7Days: number,
    presetUsage: {
      express: number,
      secure: number,
      custom: number,
    },
    averageCreationTime: number, // seconds from load to submit
  },
  preferences: {
    optOutAdaptation: boolean,
    preferredTTL?: number,
    alwaysUsePassphrase?: boolean,
  },
  lastUpdated: Date,
}

// Stored in localStorage, never sent to server
localStorage.setItem('ots_behavior_profile', JSON.stringify(profile));
```

#### WiFi Detection (With Permission)
```typescript
// Uses browser Network Information API
async function detectWiFiContext(): Promise<WiFiContext | null> {
  // Request permission first
  const permission = await navigator.permissions.query({ name: 'geolocation' });
  if (permission.state !== 'granted') return null;

  // Check connection type
  const connection = (navigator as any).connection;
  if (connection?.type === 'wifi') {
    return {
      isConnected: true,
      // Note: SSID not available in browser for security reasons
      // Use heuristic: If mobile + WiFi + home location → Assume home network
    };
  }

  return null;
}
```

#### Auto-Submit Countdown
```vue
<template>
  <div v-if="autoSubmitEnabled">
    <div class="countdown">
      Auto-creating in: {{ countdown }}s
      <button @click="cancelAutoSubmit">Cancel</button>
    </div>
  </div>
</template>

<script setup lang="ts">
const countdown = ref(5);
const autoSubmitEnabled = computed(() => {
  return isRushHour() && userBehavior.averageCreationTime < 10;
});

watchEffect(() => {
  if (autoSubmitEnabled.value && hasContent.value) {
    const timer = setInterval(() => {
      countdown.value--;
      if (countdown.value === 0) {
        submitSecret();
        clearInterval(timer);
      }
    }, 1000);

    onBeforeUnmount(() => clearInterval(timer));
  }
});
</script>
```

---

## COMPARATIVE ANALYSIS

### Time-to-Task-Completion by Scenario

| Scenario | Model A (Express) | Model B (Wizard) | Model C (Adaptive) |
|----------|-------------------|------------------|---------------------|
| **Developer (DB creds)** | 5-10s (paste + apply) | 20-30s (3 steps) | 2-5s (learned preset) |
| **Support (temp password)** | 10-15s (generate mode) | 15-20s (2 steps) | 8-12s (QR shortcut) |
| **Friend (WiFi QR)** | 15-20s (paste + QR option) | 15-25s (3 steps) | 5-10s (WiFi detected) |
| **HR (onboarding doc)** | 45-60s (markdown + email) | 60-90s (4 steps) | 40-50s (template) |
| **First-time user** | 15-25s (learns by doing) | 20-30s (guided) | 20-30s (onboarding) |

### Feature Matrix

| Feature | Model A | Model B | Model C |
|---------|---------|---------|---------|
| **Smart Defaults** | ✅ Pattern detection | ❌ Manual selection | ✅✅ Behavioral learning |
| **Discoverability** | ⚠️ Hidden in customize | ✅ All flows visible | ⚠️ Context-dependent |
| **Mobile UX** | ✅ Bottom sheet | ✅✅ Native wizard | ✅ Adaptive interface |
| **Power User Speed** | ✅✅ Keyboard shortcuts | ❌ Must click through | ✅✅ Learned shortcuts |
| **Beginner Friendliness** | ⚠️ Must learn interface | ✅✅ Guided step-by-step | ✅ Adapts to skill |
| **QR Code Access** | ⚠️ In advanced options | ✅ Delivery method step | ✅✅ Auto-suggested |
| **Email Integration** | ⚠️ In advanced options | ✅ Delivery method step | ✅ Context-aware |
| **Markdown Support** | ⚠️ Hidden toggle | ✅ Separate document flow | ✅ Auto-detected |
| **Consistency** | ✅✅ Always same UI | ✅✅ Predictable steps | ❌ Changes by context |
| **Implementation Cost** | Medium | High (3 flows) | Very High (adaptive logic) |

### Recommendations by Strategic Priority

#### If Priority: **Speed for Power Users**
**Winner**: Model C (Adaptive) or Model A (Express)
- Model C learns user preferences (2-5s for repeat users)
- Model A provides keyboard shortcuts (5-10s)
- Model B too slow (20-30s multi-step)

#### If Priority: **Mobile-First**
**Winner**: Model B (Wizard) or Model C (Adaptive)
- Model B uses native mobile patterns (bottom sheets, swipe)
- Model C detects mobile context, shows optimized UI
- Model A requires scrolling on mobile (friction)

#### If Priority: **Feature Discoverability**
**Winner**: Model B (Wizard)
- All flows (QR, email, markdown) visible in intent discovery
- Model A hides advanced features
- Model C only shows features when context matches

#### If Priority: **Simplicity & Consistency**
**Winner**: Model A (Express)
- Single interface, always the same
- Model B has 3+ separate flows (higher complexity)
- Model C changes behavior (potential confusion)

---

## RECOMMENDED HYBRID APPROACH

### Combine Best of All Three Models

**Foundation**: Model A (Express Lane) — Fast, input-first, progressive disclosure

**Enhancements from Model B**:
- Add prominent mode switcher (not hidden dropdown): `📝 Text` | `🔑 Generate` | `📄 Document`
- Offer "Guided Mode" toggle for first-time users
- Use step indicator if user chooses multi-step flow

**Enhancements from Model C**:
- Behavioral learning (remember user's most-used preset)
- Context detection (WiFi, rush hour, mobile)
- Adaptive suggestions (not forced adaptation)

### Hybrid Interface Design

```
┌──────────────────────────────────────────────────────────────┐
│  OneTimeSecret                         [Maya] [⚙️ Settings]  │
├──────────────────────────────────────────────────────────────┤
│                                                               │
│  Mode: [📝 Text] | [🔑 Generate] | [📄 Document] ← Visible   │
│                                                               │
│  ┌────────────────────────────────────────────────────────┐ │
│  │                                                        │ │
│  │  [Paste your secret here...]                          │ │
│  │                                                        │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                               │
│  💡 Suggested: 🔒 Secure (your usual) [Apply] or [Customize]│
│                                                               │
│  [Create Secret]                                             │
└──────────────────────────────────────────────────────────────┘
```

**Benefits**:
- ✅ Fast for power users (paste → apply → create)
- ✅ Discoverable modes (visible tabs)
- ✅ Smart suggestions (learned preferences)
- ✅ Consistent interface (no unpredictable morphing)
- ✅ Mobile-friendly (bottom sheet for options)

---

## NEXT STEPS → PHASE 4

With three interaction models explored, we can now:

1. **Choose primary model** (or hybrid approach)
2. **Define design principles** (3-5 core principles)
3. **Create detailed specifications** (components, states, accessibility)
4. **Plan technical approach** (architecture, Tailwind patterns, performance)

**Ready to proceed to Phase 4: Design Principles & Specifications?**
