# PHASE 4: DESIGN PRINCIPLES & SPECIFICATIONS

## Executive Summary

This phase translates the recommended interaction model (Express Lane with enhancements) into concrete design specifications ready for implementation. We establish core principles, detailed interaction flows, accessibility requirements, and technical architecture for the redesigned create-secret experience.

**Target Metrics:**
- Time-to-first-link: < 10 seconds (currently ~30s)
- Required clicks: 2-3 (currently 6+)
- First-time user success rate: > 90%
- Mobile completion rate: Match desktop

---

## 1. DESIGN PRINCIPLES

### Principle 1: **Clarity Over Cleverness**

**What it means:**
Every interaction should have one obvious next step. No hidden features, no surprises, no need to explore to understand what will happen.

**How it guides decisions:**
- Primary action always visible and clearly labeled
- Options revealed progressively, not hidden behind icons
- Confirmation shows exactly what was created (expiration, passphrase status)
- No jargon—use plain language ("Expires in 7 days" not "TTL: 604800")

**Examples:**
- ✅ "Create Secret Link" (clear action)
- ❌ "Submit" (vague)
- ✅ "Your link expires in 7 days or after 1 view"
- ❌ "Lifespan: 7d, Views: 1"

---

### Principle 2: **Speed by Default, Control on Demand**

**What it means:**
The default path should be the fastest path. Advanced options exist but don't slow down users who don't need them.

**How it guides decisions:**
- Start with textarea auto-focused—no intro screens
- Smart defaults handle 80% of use cases
- Options collapse by default, expand when clicked
- Power users can still access everything (no features removed)

**Examples:**
- ✅ Passphrase field hidden by default
- ✅ Expiration pre-set to 7 days (changeable)
- ✅ "Add passphrase or change expiration" link reveals options
- ❌ All fields visible upfront

---

### Principle 3: **Trust Through Transparency**

**What it means:**
Users share sensitive data. We build trust by showing exactly what happens, when it happens, and why it's secure.

**How it guides decisions:**
- Confirmation screen shows all settings before user leaves
- Inline explanations at point of decision ("Share passphrase separately")
- Security indicators visible (HTTPS badge, encryption mention)
- No black boxes—help modal explains entire process

**Examples:**
- ✅ "Your secret link is ready! Expires in 7 days or after 1 view"
- ✅ "🔒 Passphrase protected: Yes"
- ✅ "💡 Remember: Share the passphrase separately!"
- ❌ Silent redirect with no confirmation

---

### Principle 4: **Mobile-First Interaction Patterns**

**What it means:**
Touch-friendly interactions work on desktop, but mouse-only interactions fail on mobile. Design for thumbs, adapt for mouse.

**How it guides decisions:**
- Button chips instead of dropdowns
- 48px minimum touch targets
- Sticky primary action at bottom (mobile)
- No hover-only states
- One-column layouts stack naturally

**Examples:**
- ✅ Expiration as button group with large tap areas
- ✅ "Copy Link" button (not just "click to copy")
- ❌ Dropdown with 11 small options
- ❌ Hover-to-reveal controls

---

### Principle 5: **Accessibility is Not Optional**

**What it means:**
Every user, regardless of ability or tool, should complete the task successfully. Keyboard navigation, screen readers, and assistive tech are first-class experiences.

**How it guides decisions:**
- Auto-focus on load (keyboard users start typing immediately)
- Clear focus indicators (rings, outlines)
- ARIA labels and live regions
- Semantic HTML (buttons are `<button>`, not `<div onclick>`)
- Logical tab order

**Examples:**
- ✅ Textarea auto-focused on page load
- ✅ `aria-live="polite"` announces "Copied!" on copy
- ✅ Keyboard shortcut: Enter to submit
- ✅ Screen reader: "Secret link created. Link copied to clipboard."

---

## 2. INTERACTION SPECIFICATIONS

### 2.1 INITIAL STATE

**What the user sees on page load:**

```
┌─────────────────────────────────────────────────────────────┐
│  OneTimeSecret                    [How it works] [Sign In]  │
└─────────────────────────────────────────────────────────────┘

   Share a secret, the secure way
   🔒 End-to-end encrypted • One-time links

   ┌───────────────────────────────────────────────────────────┐
   │                                                           │
   │  Paste your secret here (text only, no files)...         │
   │                                                           │
   │                                                           │
   │                                                           │
   │                                                           │
   │                                                           │
   └───────────────────────────────────────────────────────────┘
                                              0 / 10,000 chars

   ┌──────────────────────────────────────────────┐
   │         Create Secret Link                   │  ← DISABLED
   └──────────────────────────────────────────────┘

   or generate a random password →
```

**Visual Hierarchy:**
1. **Hero message:** "Share a secret, the secure way"
2. **Trust indicators:** "🔒 End-to-end encrypted • One-time links"
3. **Textarea:** Large, welcoming, auto-focused
4. **Primary action:** "Create Secret Link" button (disabled until content)
5. **Secondary action:** "generate a random password →" link (subtle)

**State:**
- Textarea: Empty, auto-focused, cursor blinking
- Button: Disabled (gray, no pointer)
- Character counter: "0 / 10,000 chars" (subtle, bottom-right)
- Options: Hidden (no passphrase field, no expiration dropdown)

**Accessibility:**
- Focus: Textarea (`autofocus` attribute)
- ARIA: `aria-label="Secret content"` on textarea
- ARIA: `aria-disabled="true"` on button
- Screen reader announcement: "Share a secret, the secure way. Secret content, edit text."

**Mobile Differences:**
- Sticky header (collapses on scroll to maximize textarea space)
- Button full-width
- Character counter moves above button

---

### 2.2 PRIMARY PATH (Happy Path)

#### Step 1: User Types/Pastes Content

**User action:** Types or pastes secret into textarea

**System response (real-time):**
```
   ┌───────────────────────────────────────────────────────────┐
   │  postgres://admin:xK9$mP2#vL5@prod-db.example.com        │
   │                                                           │
   │                                                           │
   └───────────────────────────────────────────────────────────┘
                                                 53 / 10,000

   ┌──────────────────────────────────────────────┐
   │         Create Secret Link                   │  ← ENABLED
   └──────────────────────────────────────────────┘

   ⚙️ Add passphrase or change expiration (7 days)  ← NEW LINK

   or generate a random password →
```

**What changed:**
- Button enabled (blue background, white text, pointer cursor)
- Character counter updates in real-time (53 / 10,000)
- New link appears: "⚙️ Add passphrase or change expiration (7 days)"
  - Shows current default: 7 days
  - Gear icon indicates configuration

**Animations:**
- Button: Fade from gray to blue (200ms ease-out)
- Link: Slide down + fade in (300ms ease-out)

**Accessibility:**
- Button: `aria-disabled="false"`
- Button: Focus ring visible when tabbed to
- Screen reader: "Create secret link, button, enabled"

---

#### Step 2: User Clicks "Create Secret Link"

**User action:** Clicks button or presses Enter

**System response (immediate):**
1. Button shows loading state: "Creating..." with spinner
2. Form fades out (500ms)
3. API call to `/api/v2/secret/conceal`
4. Confirmation fades in (500ms) (no page redirect)

**Confirmation Screen:**
```
   ┌───────────────────────────────────────────────────────────┐
   │                                                           │
   │            ✅  Your secret link is ready!                 │
   │                                                           │
   │      This link expires in 7 days or after 1 view         │
   │                                                           │
   │  ┌─────────────────────────────────────────────────────┐ │
   │  │ https://onetimesecret.com/secret/a3k9x2m...         │ │
   │  └─────────────────────────────────────────────────────┘ │
   │                                                           │
   │  ┌────────────────────────┐  ┌──────────────────────┐   │
   │  │  📋 Copy Link          │  │  🔄 Create Another   │   │
   │  └────────────────────────┘  └──────────────────────┘   │
   │                                                           │
   │  🔓 Passphrase: None                                     │
   │                                                           │
   │  ℹ️  Share this link once—it self-destructs after viewing│
   │                                                           │
   └───────────────────────────────────────────────────────────┘
```

**Visual Elements:**
- Success icon: Large green checkmark
- Heading: "Your secret link is ready!"
- Expiration summary: Clear, human-readable
- Link field: Auto-selected text (ready to Cmd+C)
- Two buttons:
  - Primary: "📋 Copy Link" (blue, prominent)
  - Secondary: "🔄 Create Another" (gray outline)
- Settings summary:
  - "🔓 Passphrase: None" (clear status)
- Reminder: Bottom tip about one-time nature

**Animations:**
- Entire card: Fade in + slight scale (0.95 → 1.0, 500ms ease-out)
- Checkmark: Bounce animation (200ms delay)

**Accessibility:**
- Focus: "Copy Link" button auto-focused
- Link field: Auto-selected (Cmd+C copies immediately)
- ARIA live region: `aria-live="polite"` announces "Your secret link is ready. Link copied to clipboard."
- Keyboard: Enter or Space on "Copy Link" button copies

---

#### Step 3: User Copies Link

**User action:** Clicks "Copy Link" button (or presses Enter/Space)

**System response:**
- Button text changes: "📋 Copy Link" → "✅ Copied!"
- Button background: Blue → Green (200ms transition)
- Text copied to clipboard
- After 2 seconds: Button reverts to "📋 Copy Link"

**Accessibility:**
- ARIA live region: `aria-live="assertive"` announces "Link copied to clipboard"
- Visual feedback for non-screen-reader users
- Focus remains on button (user can copy again if needed)

---

### 2.3 CONFIGURATION FLOW (With Options)

#### User Clicks "⚙️ Add passphrase or change expiration"

**System response:** Options panel expands below textarea (smooth 400ms animation)

```
   ┌───────────────────────────────────────────────────────────┐
   │  postgres://admin:xK9$mP2#vL5@prod-db.example.com        │
   │                                                           │
   └───────────────────────────────────────────────────────────┘
                                                 53 / 10,000

   ┌───────────────────────────────────────────────────────────┐
   │  🔒 Passphrase (optional)                                 │
   │  ┌─────────────────────────────────────────────────┐  👁  │
   │  │                                                 │      │
   │  └─────────────────────────────────────────────────┘      │
   │  💡 Share the passphrase separately (SMS, phone call)    │
   │                                                           │
   │  ⏱️  Expires in                                           │
   │  ┌─────┐ ┌─────┐ ┌──────┐ ┌─────────┐ ┌──────┐ ┌──────┐│
   │  │ 1h  │ │ 4h  │ │ 1 day│ │✓ 7 days │ │ 14d  │ │ 30d  ││
   │  └─────┘ └─────┘ └──────┘ └─────────┘ └──────┘ └──────┘│
   │                                                           │
   │  Custom time... ▼                                         │
   └───────────────────────────────────────────────────────────┘

   ┌──────────────────────────────────────────────┐
   │         Create Secret Link                   │
   └──────────────────────────────────────────────┘

   ⚙️ Hide options  ← Changed from "Add passphrase"
```

**Panel Contents:**

1. **Passphrase Field:**
   - Label: "🔒 Passphrase (optional)"
   - Input: Text field with show/hide toggle (eye icon)
   - Hint: "💡 Share the passphrase separately (SMS, phone call)"
   - Validation: Real-time (if configured: min length, complexity)

2. **Expiration Buttons:**
   - Label: "⏱️ Expires in"
   - Button group: 6 chips (1h, 4h, 1d, 7d, 14d, 30d)
   - Pre-selected: 7 days (checkmark ✓, blue background)
   - Filtered by plan (anonymous users see up to 7d)
   - "Custom time..." expands additional input

**Animations:**
- Panel: Slide down + fade in (400ms ease-out)
- Height: Auto-animate from 0 to content height
- Focus: Auto-focus on passphrase field when panel opens

**Accessibility:**
- Focus management: Passphrase field focused when panel opens
- ARIA: `aria-expanded="true"` on trigger link
- Keyboard: Tab through passphrase → visibility toggle → expiration buttons
- Button group: Arrow keys navigate between chips
- Screen reader: "Options expanded. Passphrase, optional, edit text."

---

#### User Sets Passphrase

**User action:** Types passphrase into field

**Real-time validation (if configured):**

```
   🔒 Passphrase (optional)
   ┌─────────────────────────────────────────────────┐  👁
   │  myP@ssw0rd                                     │
   └─────────────────────────────────────────────────┘
   ✅ Strong passphrase  ← Validation feedback
```

**Validation states:**
- Empty: No feedback (field is optional by default)
- Too short: "⚠️ Minimum 8 characters" (if min length configured)
- Weak: "⚠️ Add uppercase, number, and symbol" (if complexity required)
- Good: "✅ Strong passphrase"

**Visibility Toggle:**
- Icon: 👁 (eye outline) when password hidden
- Icon: 👁‍🗨 (eye slash) when password visible
- Click: Toggles between `type="password"` and `type="text"`
- ARIA: `aria-label="Show passphrase"` / "Hide passphrase"
- ARIA: `aria-pressed="false"` / "true"

---

#### User Changes Expiration

**User action:** Clicks different expiration button (e.g., "1 day")

**System response:**
- Previous selection: Remove checkmark, gray background
- New selection: Add checkmark ✓, blue background
- Transition: 200ms background color animation

**Keyboard navigation:**
- Tab: Focus on button group
- Arrow keys: Navigate between chips (Left/Right or Up/Down)
- Enter/Space: Select focused chip
- Screen reader: "1 day, button, 1 of 6, not pressed" → "pressed"

---

#### User Clicks "Create Secret Link" (with options)

**Confirmation shows updated settings:**

```
   ✅  Your secret link is ready!

   This link expires in 1 day or after 1 view

   ┌─────────────────────────────────────────────────┐
   │ https://onetimesecret.com/secret/a3k9x2m...     │
   └─────────────────────────────────────────────────┘

   ┌────────────────────────┐  ┌──────────────────┐
   │  📋 Copy Link          │  │  🔄 Create Another│
   └────────────────────────┘  └──────────────────┘

   🔒 Passphrase: Set  ← Changed from "None"
   💡 Remember: Share the passphrase separately!

   ℹ️  Share this link once—it self-destructs after viewing
```

**Key differences:**
- Expiration: "1 day" instead of "7 days"
- Passphrase status: "🔒 Passphrase: Set"
- Additional reminder: "Share the passphrase separately!"

---

### 2.4 GENERATE PASSWORD FLOW

#### User Clicks "or generate a random password →"

**System response:** Form transforms to password generation mode

```
   ┌───────────────────────────────────────────────────────────┐
   │                                                           │
   │         🔑  Generate a Random Password                    │
   │                                                           │
   │     We'll create a secure password and give you          │
   │     a one-time link to share it.                         │
   │                                                           │
   └───────────────────────────────────────────────────────────┘

   ┌──────────────────────────────────────────────┐
   │      🎲 Generate Password                     │
   └──────────────────────────────────────────────┘

   ⚙️ Password options (12 chars, letters + numbers)

   ← Back to create link
```

**Visual changes:**
- Textarea: Hidden
- Icon + heading: "🔑 Generate a Random Password"
- Explanation: Clear description of what happens
- Button: Changed to "🎲 Generate Password"
- Options: Collapsed by default, shows current settings
- Back link: Returns to main flow

**Animations:**
- Textarea: Fade out (300ms)
- New content: Fade in (300ms, 100ms delay)

---

#### User Clicks "Generate Password"

**System response:**

```
   ✅  Your password link is ready!

   The generated password is:

   ┌─────────────────────────────────────────────────┐
   │  xK9$mP2#vL5@                                   │  👁
   └─────────────────────────────────────────────────┘

   The link to share:

   ┌─────────────────────────────────────────────────┐
   │ https://onetimesecret.com/secret/a3k9x2m...     │
   └─────────────────────────────────────────────────┘

   ┌────────────────────────┐  ┌──────────────────────┐
   │  📋 Copy Link Only     │  │  📋 Copy Both        │
   └────────────────────────┘  └──────────────────────┘

   ┌──────────────────────────────────────────────────┐
   │  🔄 Generate Another Password                    │
   └──────────────────────────────────────────────────┘

   💡 The link shows the password when opened—you don't
      need to share it separately unless you add a passphrase.
```

**Key elements:**
- Password shown: User needs to see what was generated
- Password has visibility toggle (can hide if needed)
- Link shown separately
- Two copy options:
  1. "Copy Link Only" → Just the URL
  2. "Copy Both" → Password + Link (for convenience)
- Generate another: Quick re-generation
- Inline tip: Explains passphrase difference

---

### 2.5 FEEDBACK & VALIDATION

#### Real-Time Validation (Frontend)

**Passphrase validation:**
```
State: Empty → No feedback (optional)
State: "abc" → ⚠️ Minimum 8 characters
State: "abcd1234" → ⚠️ Add uppercase and symbol
State: "Abcd1234!" → ✅ Strong passphrase
```

**Secret content validation:**
```
State: Empty → Button disabled
State: 1 char → Button enabled
State: 9,999 chars → "9,999 / 10,000" (green)
State: 10,000 chars → "10,000 / 10,000" (yellow warning)
State: > 10,000 chars → ⚠️ "Exceeded maximum length" (red, prevent submission)
```

**Expiration validation:**
```
Anonymous user clicks "30d" → Nothing happens (button disabled + tooltip)
Tooltip: "Upgrade to extend expiration to 30 days"
```

---

#### Error Handling

**Backend validation errors (after API call):**

```
   ┌───────────────────────────────────────────────────────────┐
   │  ⚠️  Couldn't create your secret                          │
   │                                                           │
   │  • Passphrase must be at least 12 characters              │
   │  • Please try again or contact support                    │
   │                                                           │
   │  ┌──────────────────┐                                     │
   │  │  Try Again       │                                     │
   │  └──────────────────┘                                     │
   └───────────────────────────────────────────────────────────┘
```

**Error display strategy:**
- Alert banner at top of form (sticky, doesn't scroll away)
- Red background, white text, warning icon
- Specific error messages (not generic "An error occurred")
- "Try Again" button returns to form (preserves content)
- Screen reader: `aria-live="assertive"` announces error

**Common errors:**
- Rate limit: "Too many secrets created. Please wait 5 minutes."
- Network: "Connection lost. Check your internet and try again."
- Server: "Service temporarily unavailable. Please try again in a moment."
- Validation: Specific field errors (passphrase, TTL, etc.)

---

#### Success Feedback

**Confirmation screen elements:**
- ✅ Visual checkmark (success color, animated)
- Clear heading: "Your secret link is ready!"
- Summary of settings (expiration, passphrase status)
- Link auto-selected (Cmd+C works immediately)
- Copy button with state change (Copied!)
- No auto-dismiss—user controls when to leave

**ARIA live regions:**
```html
<div role="status" aria-live="polite" aria-atomic="true">
  Your secret link is ready. Link copied to clipboard.
</div>
```

---

### 2.6 MOBILE STRATEGY

#### Responsive Breakpoints

**Mobile (< 640px):**
- Single column layout
- Textarea min-height: 150px (smaller than desktop)
- Button full-width
- Expiration chips: 2 per row (stacked grid)
- Sticky "Create Secret Link" button at bottom
- Character counter above button (not bottom-right)

**Tablet (640px - 1024px):**
- Same as mobile, but textarea min-height: 200px
- Expiration chips: 3 per row

**Desktop (> 1024px):**
- Max-width: 640px (centered)
- Textarea min-height: 250px
- Expiration chips: 6 in one row

---

#### Touch Target Sizes

**All interactive elements:**
- Minimum: 48px × 48px (iOS/Android guideline)
- Buttons: 56px height
- Expiration chips: 80px × 48px
- Visibility toggle: 48px × 48px
- Links: 44px height minimum

---

#### Mobile-Specific Optimizations

**Sticky button (mobile only):**
```
┌─────────────────────────────┐
│  [Textarea content]         │
│                             │
│                             │
│  [Character counter]        │
│                             │
│  ════════════════════       │  ← Divider
│  [Create Secret Link]       │  ← Sticky at bottom
└─────────────────────────────┘
```

**Keyboard behavior:**
- Textarea focuses → Keyboard opens → Button stays visible above keyboard
- Submit button always accessible (sticky positioning)

**Copy behavior:**
- One-tap copy (no need for manual selection)
- Toast notification: "Copied!" (appears above button)

**Scroll behavior:**
- Textarea: Scrollable content inside fixed-height container
- Page: Minimal scrolling (form fits in one screen when possible)

---

## 3. ACCESSIBILITY REQUIREMENTS

### 3.1 Keyboard Navigation Flow

**Tab order:**
```
1. Skip to main content (optional, for screen reader users)
2. "How it works" link (header)
3. "Sign In" link (header)
4. Textarea (auto-focused on load)
5. "Create Secret Link" button
6. "Add passphrase or change expiration" link
7. "Generate a random password" link

If options expanded:
7a. Passphrase field
7b. Passphrase visibility toggle
7c. Expiration button group (arrow keys navigate within)
7d. "Custom time..." link (if applicable)
7e. "Hide options" link

After success:
1. "Copy Link" button (auto-focused)
2. Link text field (selectable)
3. "Create Another" button
```

**Keyboard shortcuts:**
- Enter: Submit form (if textarea focused and button enabled)
- Cmd/Ctrl + Enter: Submit form (from anywhere in form)
- Escape: Collapse options panel (if expanded)
- Cmd/Ctrl + C: Copy link (if link field focused or "Copy Link" button focused)

---

### 3.2 Screen Reader Experience

**Page load announcement:**
```
"OneTimeSecret. Share a secret, the secure way.
End-to-end encrypted. One-time links.
Secret content, edit text."
```

**User types in textarea:**
```
[Character echo, word echo, or line echo per user settings]
"Create secret link, button, enabled."
```

**Options expanded:**
```
"Options expanded.
Passphrase, optional, edit text.
Expires in, button group, 7 days selected, 1 of 6."
```

**Expiration button navigation:**
```
"1 hour, button, 1 of 6, not pressed."
[Arrow right]
"4 hours, button, 2 of 6, not pressed."
[Enter]
"4 hours, pressed."
```

**Submit success:**
```
"Creating secret link."
[Pause for API call]
"Your secret link is ready.
Link copied to clipboard.
Copy link, button."
```

**Copy button clicked:**
```
"Link copied to clipboard."
[Button changes to "Copied!"]
"Copied, button."
```

---

### 3.3 ARIA Attributes

**Form elements:**
```html
<form role="form" aria-label="Create secret link">
  <textarea
    id="secret-content"
    aria-label="Secret content"
    aria-describedby="char-counter"
    aria-required="true"
    autofocus
  ></textarea>

  <div id="char-counter" role="status" aria-live="polite">
    0 of 10,000 characters
  </div>

  <button
    type="submit"
    aria-disabled="true"
    aria-describedby="create-link-desc"
  >
    Create Secret Link
  </button>

  <div id="create-link-desc" class="sr-only">
    Creates a secure, one-time link to share your secret
  </div>
</form>
```

**Options panel:**
```html
<button
  aria-expanded="false"
  aria-controls="options-panel"
>
  Add passphrase or change expiration (7 days)
</button>

<div id="options-panel" hidden>
  <label for="passphrase">
    Passphrase (optional)
  </label>
  <input
    type="password"
    id="passphrase"
    aria-describedby="passphrase-hint"
  />
  <div id="passphrase-hint">
    Share the passphrase separately (SMS, phone call)
  </div>

  <div role="group" aria-label="Expires in">
    <button
      role="radio"
      aria-checked="false"
    >1 hour</button>
    <button
      role="radio"
      aria-checked="true"
    >7 days</button>
    <!-- etc -->
  </div>
</div>
```

**Confirmation screen:**
```html
<div role="status" aria-live="polite" aria-atomic="true">
  Your secret link is ready. Link copied to clipboard.
</div>

<div class="confirmation">
  <h2 id="success-heading">Your secret link is ready!</h2>

  <input
    type="text"
    readonly
    value="https://onetimesecret.com/secret/a3k9x2m..."
    aria-label="Secret link"
    aria-describedby="expiry-info"
  />

  <div id="expiry-info">
    This link expires in 7 days or after 1 view
  </div>

  <button aria-describedby="copy-desc">
    Copy Link
  </button>
  <div id="copy-desc" class="sr-only">
    Copies the secret link to your clipboard
  </div>
</div>
```

---

### 3.4 Focus Management

**On page load:**
- Focus: Textarea
- Cursor: Blinking at position 0

**Options panel expanded:**
- Focus: Passphrase field
- Previous focus: Remembered (return to trigger link when collapsed)

**Form submitted:**
- Focus: "Copy Link" button on confirmation screen
- Previous focus: Form is no longer visible

**Link copied:**
- Focus: Remains on "Copy Link" button
- Visual feedback: Button text changes to "Copied!"

**Error occurred:**
- Focus: First error field (e.g., passphrase if validation failed)
- Visual feedback: Error banner at top + field highlight

---

### 3.5 WCAG 2.1 AA Compliance

**Color Contrast:**
- Text: 4.5:1 minimum (normal text)
- Large text: 3:1 minimum (18pt or 14pt bold)
- Interactive elements: 3:1 minimum against background

**Examples:**
- ✅ Button: #2563EB (blue) on white = 6.2:1
- ✅ Error: #DC2626 (red) on white = 5.9:1
- ✅ Success: #16A34A (green) on white = 4.6:1
- ✅ Disabled: #9CA3AF (gray) on white = 3.2:1

**Text Resizing:**
- All text: Resizable up to 200% without loss of functionality
- No fixed pixel heights on containers with text
- Line height: 1.5 minimum
- Paragraph spacing: 1.5× font size minimum

**Target Size:**
- All interactive elements: 44px × 44px minimum (WCAG 2.5.5, Level AAA)
- Exception: Inline links in paragraphs (not applicable here)

**Focus Visible:**
- All interactive elements: 2px solid outline, 2px offset
- Color: #2563EB (blue) or high-contrast OS default
- Never `outline: none` without custom focus indicator

**Semantic HTML:**
- Buttons: `<button>`, not `<div role="button">`
- Links: `<a href>`, not `<span onclick>`
- Headings: Proper hierarchy (h1 → h2 → h3)
- Landmarks: `<main>`, `<header>`, `<footer>`, `<form>`

---

## 4. TECHNICAL APPROACH

### 4.1 Component Architecture

**Component Hierarchy:**
```
<HomePage>
  └─ <SecretFormExpress>
      ├─ <FormHeader>
      │   ├─ <TrustBadge /> (HTTPS, encryption)
      │   └─ <HelpModal /> (How it works)
      │
      ├─ <SecretTextarea>
      │   └─ <CharacterCounter />
      │
      ├─ <OptionsPanel> (collapsible)
      │   ├─ <PassphraseField>
      │   │   └─ <VisibilityToggle />
      │   ├─ <ExpirationButtonGroup>
      │   │   └─ <ExpirationChip /> (×6)
      │   └─ <CustomTTLInput /> (optional)
      │
      ├─ <PrimaryActionButton />
      │   └─ <LoadingSpinner /> (conditional)
      │
      ├─ <SecondaryAction> (Generate Password)
      │
      └─ <ConfirmationScreen> (conditional)
          ├─ <LinkDisplay>
          │   └─ <CopyButton />
          ├─ <SettingsSummary />
          └─ <CreateAnotherButton />
```

**File Structure:**
```
src/components/secrets/form/
├─ SecretFormExpress.vue           (main orchestrator)
├─ SecretTextarea.vue               (reusable textarea)
├─ CharacterCounter.vue             (0 / 10,000 display)
├─ OptionsPanel.vue                 (collapsible options)
├─ PassphraseField.vue              (input + toggle)
├─ ExpirationButtonGroup.vue        (chip selector)
├─ ConfirmationScreen.vue           (success state)
└─ GeneratePasswordFlow.vue         (alternate mode)

src/composables/
├─ useSecretFormExpress.ts          (form state)
├─ useSecretSubmission.ts           (API handling)
├─ useOptionsPanel.ts               (expand/collapse)
├─ useCopyToClipboard.ts            (copy behavior)
└─ useValidation.ts                 (real-time validation)
```

---

### 4.2 State Management

**Local component state (Composition API):**

```typescript
// useSecretFormExpress.ts
export function useSecretFormExpress() {
  const form = reactive({
    secret: '',
    passphrase: '',
    ttl: 604800, // 7 days default
    mode: 'conceal' as 'conceal' | 'generate',
  })

  const ui = reactive({
    optionsExpanded: false,
    passphraseVisible: false,
    isSubmitting: false,
    confirmation: null as ConcealDataResponse | null,
  })

  const validation = reactive({
    secretValid: computed(() => form.secret.length > 0),
    passphraseValid: computed(() => validatePassphrase(form.passphrase)),
    canSubmit: computed(() => validation.secretValid),
  })

  return { form, ui, validation }
}
```

**Pinia store (global state, if needed):**
```typescript
// stores/secretStore.ts
export const useSecretStore = defineStore('secret', {
  state: () => ({
    recentSecrets: [] as Array<{ key: string, createdAt: Date }>,
  }),

  actions: {
    async conceal(payload: ConcealPayload) {
      const response = await api.post('/api/v2/secret/conceal', payload)
      this.recentSecrets.unshift({
        key: response.record.metadata.key,
        createdAt: new Date(),
      })
      return response
    },
  },
})
```

---

### 4.3 Tailwind 4.1 Patterns

**Theme Configuration:**
```js
// tailwind.config.js
export default {
  theme: {
    extend: {
      colors: {
        brand: {
          50: '#eff6ff',
          500: '#2563eb',
          600: '#1d4ed8',
        },
      },
      animation: {
        'fade-in': 'fadeIn 0.5s ease-out',
        'slide-down': 'slideDown 0.4s ease-out',
        'bounce-in': 'bounceIn 0.6s ease-out',
      },
      keyframes: {
        fadeIn: {
          '0%': { opacity: '0' },
          '100%': { opacity: '1' },
        },
        slideDown: {
          '0%': { transform: 'translateY(-10px)', opacity: '0' },
          '100%': { transform: 'translateY(0)', opacity: '1' },
        },
        bounceIn: {
          '0%': { transform: 'scale(0)', opacity: '0' },
          '50%': { transform: 'scale(1.1)' },
          '100%': { transform: 'scale(1)', opacity: '1' },
        },
      },
    },
  },
}
```

**Component Classes:**
```vue
<!-- Textarea -->
<textarea
  class="
    w-full min-h-[200px] md:min-h-[250px] p-4
    border-2 border-gray-200 rounded-lg
    focus:border-blue-500 focus:ring-2 focus:ring-blue-500 focus:outline-none
    transition-all duration-200
    dark:bg-slate-800 dark:border-gray-700 dark:text-white
    placeholder:text-gray-400 dark:placeholder:text-gray-500
  "
/>

<!-- Primary Button -->
<button
  class="
    w-full py-4 px-6 rounded-lg font-medium
    bg-blue-600 text-white
    hover:bg-blue-700 active:bg-blue-800
    focus:ring-2 focus:ring-blue-500 focus:ring-offset-2
    disabled:bg-gray-300 disabled:cursor-not-allowed
    transition-all duration-200
  "
  :class="{ 'opacity-50': isSubmitting }"
/>

<!-- Expiration Chip -->
<button
  class="
    px-4 py-2 min-w-[80px] rounded-md
    border-2 border-gray-200
    hover:border-blue-300 hover:bg-blue-50
    focus:border-blue-500 focus:ring-2 focus:ring-blue-500
    transition-all duration-200
  "
  :class="{
    'bg-blue-600 text-white border-blue-600': isSelected,
    'bg-white text-gray-700': !isSelected,
  }"
/>

<!-- Options Panel (collapsible) -->
<div
  class="
    overflow-hidden transition-all duration-400 ease-out
  "
  :class="{
    'max-h-0 opacity-0': !expanded,
    'max-h-[500px] opacity-100': expanded,
  }"
/>
```

**Responsive Utilities:**
```vue
<!-- Character Counter -->
<div
  class="
    text-sm text-gray-500
    absolute bottom-3 right-3
    md:static md:text-right md:mt-1
  "
/>

<!-- Button Layout -->
<div
  class="
    flex flex-col gap-3
    md:flex-row md:gap-4
  "
>
  <button class="flex-1">Copy Link</button>
  <button class="flex-1">Create Another</button>
</div>
```

---

### 4.4 Animation Strategy

**Principles:**
- Animations enhance understanding, not decoration
- Duration: 200-500ms (fast enough to feel instant, slow enough to see)
- Easing: `ease-out` for entrances, `ease-in` for exits
- Reduce motion: Respect `prefers-reduced-motion`

**Key Animations:**

1. **Button Enable (form filled):**
   ```css
   transition: background-color 200ms ease-out;
   ```

2. **Options Panel Expand:**
   ```css
   transition: max-height 400ms ease-out, opacity 400ms ease-out;
   ```

3. **Confirmation Screen:**
   ```css
   animation: fadeIn 500ms ease-out, scale 500ms ease-out;
   ```

4. **Success Checkmark:**
   ```css
   animation: bounceIn 600ms ease-out 200ms;
   ```

5. **Copy Button State:**
   ```css
   transition: background-color 200ms ease-out, transform 100ms ease-out;
   ```

**Reduced Motion:**
```css
@media (prefers-reduced-motion: reduce) {
  * {
    animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0.01ms !important;
  }
}
```

---

### 4.5 Performance Considerations

**Lazy Loading:**
- Help modal: Load on demand (not on initial page load)
- Advanced options: Render when expanded, not before

**Code Splitting:**
```typescript
// Route-based splitting
const SecretFormExpress = defineAsyncComponent(() =>
  import('./components/secrets/form/SecretFormExpress.vue')
)

// Modal splitting
const HelpModal = defineAsyncComponent(() =>
  import('./components/modals/HelpModal.vue')
)
```

**Debouncing:**
```typescript
// Character counter updates (debounce 100ms)
const debouncedUpdate = useDebounceFn((value: string) => {
  characterCount.value = value.length
}, 100)

// Validation (debounce 300ms)
const debouncedValidate = useDebounceFn((value: string) => {
  validatePassphrase(value)
}, 300)
```

**API Optimization:**
- Request deduplication (if user double-clicks submit)
- Optimistic UI updates (show confirmation before API confirms)
- Error retry with exponential backoff

**Bundle Size:**
- Tree-shake unused Tailwind classes
- Remove dev-only code in production
- Minify and compress

**Metrics to Track:**
- Time to Interactive (TTI): < 3s
- First Contentful Paint (FCP): < 1.5s
- Largest Contentful Paint (LCP): < 2.5s
- Cumulative Layout Shift (CLS): < 0.1

---

## 5. IMPLEMENTATION CHECKLIST

### Phase 1: Core Functionality (MVP)
- [ ] SecretTextarea component with character counter
- [ ] Primary action button (enabled/disabled states)
- [ ] Basic API integration (conceal endpoint)
- [ ] Confirmation screen with link display
- [ ] Copy to clipboard functionality
- [ ] Basic error handling

### Phase 2: Progressive Disclosure
- [ ] Options panel (expand/collapse)
- [ ] Passphrase field with visibility toggle
- [ ] Expiration button group (6 chips)
- [ ] Real-time validation (passphrase, length)
- [ ] Mobile-responsive layout

### Phase 3: Generate Password
- [ ] Generate password mode toggle
- [ ] API integration (generate endpoint)
- [ ] Password display with visibility toggle
- [ ] Copy link vs. copy both buttons

### Phase 4: Accessibility
- [ ] Keyboard navigation (tab order)
- [ ] ARIA labels and live regions
- [ ] Focus management (auto-focus, trap focus)
- [ ] Screen reader testing
- [ ] WCAG 2.1 AA compliance audit

### Phase 5: Polish
- [ ] Animations (smooth transitions)
- [ ] Loading states (spinners, skeleton)
- [ ] Error messages (specific, helpful)
- [ ] Help modal ("How it works")
- [ ] Trust indicators (HTTPS badge)
- [ ] Dark mode support

### Phase 6: Testing
- [ ] Unit tests (validation, state)
- [ ] Integration tests (API calls)
- [ ] E2E tests (user flows)
- [ ] Accessibility testing (axe, NVDA, VoiceOver)
- [ ] Cross-browser testing (Chrome, Firefox, Safari, Edge)
- [ ] Mobile testing (iOS Safari, Android Chrome)

---

## 6. SUCCESS METRICS

### Quantitative Metrics

**Speed:**
- Time-to-first-link: **< 10 seconds** (target)
  - Current: ~30 seconds
  - Model 1 (Express): 5-8 seconds
  - Improvement: 70-80% reduction

**Efficiency:**
- Required clicks: **2-3 clicks** (target)
  - Current: 6+ clicks
  - Model 1 (Express): 2-4 clicks
  - Improvement: 50-67% reduction

**Success Rate:**
- First-time user success: **> 90%** (target)
  - Current: Estimated 70%
  - Track: % of users who complete flow without errors

**Mobile Parity:**
- Mobile completion rate: **Match desktop** (target)
  - Current: Likely 50-70% of desktop
  - Track: Conversion rate mobile vs. desktop

---

### Qualitative Metrics

**User Confidence:**
- "I understand what will happen" (5-point scale)
- Target: > 4.5 average

**Clarity:**
- "I knew what to do at each step" (5-point scale)
- Target: > 4.5 average

**Trust:**
- "I feel my secret is secure" (5-point scale)
- Target: > 4.0 average

**Satisfaction:**
- "This was easy to use" (5-point scale)
- Target: > 4.5 average

---

### Behavioral Metrics

**Feature Discovery:**
- % of users who discover "Generate Password": **> 40%**
  - Current: Estimated < 10%

**Advanced Features:**
- % of users who set passphrase: Track baseline → improvement
- % of users who change default TTL: Track baseline → improvement

**Return Visits:**
- % of users who return within 30 days: **> 60%**
  - Indicates trust and satisfaction

---

## 7. NEXT STEPS

### Immediate Actions

1. **Stakeholder Review:**
   - Share Phase 4 spec with team
   - Gather feedback on design principles
   - Align on success metrics

2. **Design Mockups:**
   - Create high-fidelity mockups in Figma
   - Include all states (empty, filled, options expanded, confirmation, error)
   - Mobile and desktop versions

3. **Prototype:**
   - Build interactive prototype (Figma or code)
   - User test with 5-10 people (all 4 personas)
   - Iterate based on feedback

4. **Technical Spike:**
   - Validate component architecture
   - Test animation performance
   - Confirm API contract

### Implementation Plan

**Week 1-2: Core MVP**
- Textarea + button + confirmation
- Basic API integration
- No options panel yet

**Week 3-4: Progressive Disclosure**
- Options panel (passphrase + expiration)
- Validation logic
- Mobile responsive

**Week 5: Generate Password**
- Alternate flow
- Password display
- Copy options

**Week 6: Accessibility**
- Keyboard nav
- ARIA implementation
- Screen reader testing

**Week 7-8: Polish & Test**
- Animations
- Error states
- Cross-browser testing
- Performance optimization

**Week 9: Launch Prep**
- Beta testing
- Analytics setup
- Documentation
- Rollout plan (phased or full)

---

## 8. APPENDIX

### A. Design Tokens

```typescript
// colors.ts
export const colors = {
  primary: {
    50: '#eff6ff',
    500: '#2563eb',
    600: '#1d4ed8',
    700: '#1e40af',
  },
  success: {
    50: '#f0fdf4',
    500: '#16a34a',
    600: '#15803d',
  },
  error: {
    50: '#fef2f2',
    500: '#dc2626',
    600: '#b91c1c',
  },
  gray: {
    100: '#f3f4f6',
    200: '#e5e7eb',
    400: '#9ca3af',
    700: '#374151',
  },
}

// spacing.ts
export const spacing = {
  xs: '0.5rem',   // 8px
  sm: '0.75rem',  // 12px
  md: '1rem',     // 16px
  lg: '1.5rem',   // 24px
  xl: '2rem',     // 32px
}

// typography.ts
export const typography = {
  fontFamily: {
    sans: 'Inter, system-ui, sans-serif',
    mono: 'Fira Code, monospace',
  },
  fontSize: {
    xs: '0.75rem',   // 12px
    sm: '0.875rem',  // 14px
    base: '1rem',    // 16px
    lg: '1.125rem',  // 18px
    xl: '1.25rem',   // 20px
  },
  lineHeight: {
    tight: 1.25,
    normal: 1.5,
    relaxed: 1.75,
  },
}
```

---

### B. Copy Guidelines

**Voice & Tone:**
- Friendly but professional
- Clear and concise
- No jargon or technical terms
- Reassuring, not patronizing

**Examples:**

✅ **Good:**
- "Your secret link is ready!"
- "Share this link once—it self-destructs after viewing"
- "Add a passphrase for extra protection"

❌ **Bad:**
- "Secret successfully created" (robotic)
- "TTL: 604800" (jargon)
- "Link has been generated and is now available for distribution" (verbose)

**Microcopy:**
- Button: "Create Secret Link" (not "Submit" or "Create")
- Link: "or generate a random password" (lowercase, casual)
- Hint: "Share the passphrase separately" (helpful reminder)
- Confirmation: "Your secret link is ready!" (exclamation shows success)

---

### C. Error Messages

**Principles:**
- Specific, not generic
- Actionable (tell user what to do)
- Blame-free (no "you did X wrong")

**Examples:**

| Error | Generic ❌ | Specific ✅ |
|-------|-----------|------------|
| Rate limit | "Error occurred" | "Too many secrets created. Please wait 5 minutes." |
| Network | "Request failed" | "Connection lost. Check your internet and try again." |
| Validation | "Invalid input" | "Passphrase must be at least 12 characters" |
| Server | "500 error" | "Service temporarily unavailable. Please try again in a moment." |

---

**Document Status:** ✅ Complete
**Recommendation:** Model 1 (Express Lane) with enhancements
**Ready for:** Design mockups → Prototype → Implementation
**Date:** 2025-11-18
