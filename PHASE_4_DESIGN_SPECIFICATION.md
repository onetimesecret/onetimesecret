# PHASE 4: DESIGN PRINCIPLES & SPECIFICATIONS
## OneTimeSecret Create-Secret Experience Redesign — Implementation-Ready Specification

**Date**: 2025-11-18
**Branch**: `claude/redesign-create-secret-01VCPSHrMm9voh36zpcZTmrD`
**Status**: Ready for Implementation

---

## DESIGN APPROACH

Based on Phase 3 analysis, we're implementing a **Hybrid Model** that combines:

- **Foundation**: Model A (Express Lane) — Input-first, progressive disclosure
- **Enhancement**: Model B elements — Visible mode switcher, clear discovery
- **Enhancement**: Model C elements — Smart suggestions, behavioral memory

This approach optimizes for **time-to-task-completion** while maintaining **utility and discoverability**.

---

## PART 1: DESIGN PRINCIPLES

These 5 principles guide every design decision in the create-secret experience:

### 1. **SPEED IS A FEATURE**

**Principle**: Every interaction should optimize for time-to-task-completion. Remove friction ruthlessly.

**Application**:
- Default to smart suggestions, not blank forms
- Keyboard shortcuts for power users (`Cmd+V` → paste triggers detection)
- Auto-focus on primary action (textarea on load)
- Sticky actions on mobile (button always visible)
- One-click actions where possible ("Apply" preset vs manual config)

**Anti-Patterns to Avoid**:
- ❌ Requiring clicks through multiple steps for common cases
- ❌ Hiding primary action below fold
- ❌ Forcing configuration before allowing submission
- ❌ Modal dialogs that interrupt flow

**Measurement**: Track time from page load to secret created (target: <10s for 80% of cases)

---

### 2. **PROGRESSIVE DISCLOSURE, NOT PROGRESSIVE COMPLEXITY**

**Principle**: Reveal options as users need them, but keep the interface simple by default.

**Application**:
- Start with minimal UI (textarea + create button)
- Show suggestions when content detected (non-blocking banner)
- Expand options only when user clicks "Customize"
- Advanced features (email, QR) appear contextually, not upfront
- Power user features (keyboard shortcuts) discoverable but not intrusive

**Anti-Patterns to Avoid**:
- ❌ Showing all 10 fields simultaneously
- ❌ Nested dropdowns or hidden menus
- ❌ "Advanced options" that require hunting
- ❌ Configuration that feels mandatory but isn't

**Measurement**: Track % of users who use default settings vs customize (target: 70%+ use defaults)

---

### 3. **CONTEXT-AWARE WITHOUT BEING CREEPY**

**Principle**: Use smart detection to help users, but always make suggestions transparent and overridable.

**Application**:
- Auto-detect content type (credentials, WiFi, markdown) with pattern matching
- Remember user's previous choices (in localStorage, not server-side)
- Explain why suggestions appear ("Detected: Database credentials")
- Always provide "Customize" option to override
- Never force adaptation—user has final say

**Anti-Patterns to Avoid**:
- ❌ Silent auto-configuration without user awareness
- ❌ Server-side behavioral tracking (violates privacy-first ethos)
- ❌ Interface changes that feel unpredictable
- ❌ Assumptions that can't be corrected

**Measurement**: Track suggestion acceptance rate (target: 60%+ accept suggestions)

---

### 4. **MOBILE FIRST, DESKTOP ENHANCED**

**Principle**: Design for the smallest screen first, then enhance for larger screens. Never treat mobile as "responsive desktop."

**Application**:
- Mobile: Sticky footer with primary action always visible
- Mobile: Bottom sheet for options (native pattern)
- Mobile: Large tap targets (minimum 44x44px)
- Desktop: Keyboard shortcuts, preview panes, split views
- Responsive breakpoints: Mobile (<768px), Tablet (768-1024px), Desktop (>1024px)

**Anti-Patterns to Avoid**:
- ❌ Submit button below fold on mobile
- ❌ Small dropdowns that require precision tapping
- ❌ Desktop-only features with no mobile alternative
- ❌ Assuming desktop interaction patterns on mobile

**Measurement**: Track completion rates by device type (target: parity between mobile/desktop)

---

### 5. **CLARITY OVER CLEVERNESS**

**Principle**: Users should always understand what's happening and why. No "magic" without explanation.

**Application**:
- Show security level impact: "Expires in 1 hour" not "TTL: 3600"
- Explain suggestions: "Detected credentials → High security recommended"
- Provide inline help: "Passphrase protects against link interception"
- Use plain language: "How sensitive is this?" not "Risk level?"
- Announce state changes to screen readers

**Anti-Patterns to Avoid**:
- ❌ Technical jargon without context (TTL, ephemeral, entropy)
- ❌ Icons without labels or tooltips
- ❌ Errors that blame the user ("Invalid input")
- ❌ Silent failures or changes

**Measurement**: User comprehension testing (target: 90%+ understand security options)

---

## PART 2: INTERACTION SPECIFICATIONS

### 2.1 INITIAL STATE

#### Desktop View (>1024px)

```
┌──────────────────────────────────────────────────────────────┐
│  OneTimeSecret              [Sign In] or [Maya ▼] [Settings] │
├──────────────────────────────────────────────────────────────┤
│                                                               │
│  Share Mode: [📝 Text] [🔑 Generate] [📄 Document]          │
│                           ↑ Text selected by default         │
│                                                               │
│  ┌────────────────────────────────────────────────────────┐ │
│  │                                                        │ │
│  │  Paste or type your secret...                         │ │
│  │                                                        │ │
│  │                                                        │ │
│  │  [Auto-focused, cursor blinking]                      │ │
│  │                                                        │ │
│  │                                                        │ │
│  └────────────────────────────────────────────────────────┘ │
│  0 / 10,000 characters                                      │
│                                                               │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ 💡 Quick Actions                                       │ │
│  │  ⚡ Express (7 days)  🔒 Secure (1hr + pass)           │ │
│  │  ⚙️ Custom settings                                    │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                               │
│                                    [Create Secret]            │
│                                         ↑ disabled (gray)     │
└──────────────────────────────────────────────────────────────┘
```

**Technical Specs**:
- Container: `max-w-3xl mx-auto px-6 py-8`
- Textarea: `min-h-[300px] max-h-[500px] font-mono text-base`
- Mode tabs: `inline-flex gap-2 mb-6`
- Button disabled state: `opacity-50 cursor-not-allowed`

**Interaction Behavior**:
- On page load → Textarea auto-focused
- Keyboard: `Cmd/Ctrl+K` → Focus textarea (if lost)
- Paste: `Cmd/Ctrl+V` → Triggers content detection
- Button: Remains disabled until `content.length > 0`

---

#### Mobile View (<768px)

```
┌─────────────────────┐
│ OneTimeSecret       │
│           [Sign In] │
├─────────────────────┤
│                     │
│ [📝] [🔑] [📄]     │
│  ↑ Tab bar          │
│                     │
│ ┌─────────────────┐ │
│ │ Paste secret... │ │
│ │                 │ │
│ │                 │ │
│ │                 │ │
│ │                 │ │
│ │                 │ │
│ │                 │ │
│ │                 │ │
│ └─────────────────┘ │
│ 0 / 10k             │
│                     │
│ [Space for content] │
│                     │
└─────────────────────┘
┌─────────────────────┐ ← Sticky footer
│ [Create Secret]     │
│      ↑ disabled     │
└─────────────────────┘
```

**Technical Specs**:
- Tab bar: `fixed top-0 z-10 bg-white/95 backdrop-blur`
- Textarea: `min-h-[60vh] w-full px-4 py-3`
- Sticky footer: `fixed bottom-0 left-0 right-0 z-20 p-4 bg-white border-t shadow-lg`
- Safe area insets: `pb-[env(safe-area-inset-bottom)]`

**Interaction Behavior**:
- Swipe down on tab bar → Dismisses keyboard (iOS)
- Footer button always visible (no scrolling to submit)
- Tap textarea → Keyboard appears, footer adjusts height

---

### 2.2 PRIMARY PATH: TEXT MODE (Step-by-Step)

#### Step 1: User Pastes Content

**User Action**: Pastes database credentials into textarea

```
DB_HOST=prod.example.com
DB_USER=admin
DB_PASS=SuperSecret123!
```

**System Response** (200ms after paste):

```
┌──────────────────────────────────────────────────────────────┐
│  [Content in textarea...]                                    │
│  98 / 10,000 characters                                      │
│                                                               │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ 🔍 Detected: Database credentials                      │ │
│  │ ⚡ Recommended: High security                          │ │
│  │    • Expires in 1 hour                                 │ │
│  │    • Passphrase required                               │ │
│  │    • [Apply Recommendation] or [Customize]            │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                               │
│  [Create Secret]  ← Now enabled (blue, pulsing)             │
└──────────────────────────────────────────────────────────────┘
```

**Technical Implementation**:

```typescript
// Content detection on paste event
const handlePaste = debounce((content: string) => {
  const detected = detectContentType(content);

  if (detected.type === 'credentials') {
    showSuggestion({
      icon: '🔍',
      title: 'Detected: Database credentials',
      preset: 'secure',
      settings: {
        ttl: 3600, // 1 hour
        passphrase: generatePassphrase(),
      },
      explanation: 'High security recommended for sensitive credentials',
    });
  }
}, 200);
```

**Auto-Detection Patterns**:

```typescript
const contentPatterns = {
  credentials: /(?:password|passwd|pwd|secret|token|api[_-]?key|db[_-]?pass|credential)/i,
  database: /(?:db_host|db_user|db_name|database|connection[_-]?string|jdbc)/i,
  wifi: /(?:ssid|wpa|wep|wifi|wireless|network[_-]?key)/i,
  totp: /(?:otpauth:\/\/|totp|otp|2fa|authenticator|secret[_-]?key=)/i,
  markdown: /^#+\s|```|\*\*|__|##|\n\n/,
  url: /https?:\/\/[^\s]+/,
};

function detectContentType(content: string): DetectionResult {
  const length = content.length;

  // Check patterns in priority order
  if (contentPatterns.credentials.test(content) ||
      contentPatterns.database.test(content)) {
    return {
      type: 'credentials',
      confidence: 0.9,
      suggestedPreset: 'secure'
    };
  }

  if (contentPatterns.wifi.test(content) && length < 100) {
    return {
      type: 'wifi',
      confidence: 0.85,
      suggestedPreset: 'express',
      suggestedFeature: 'qr-code'
    };
  }

  if (contentPatterns.markdown.test(content)) {
    return {
      type: 'markdown',
      confidence: 0.8,
      suggestedFeature: 'markdown-rendering'
    };
  }

  // Default
  return {
    type: 'generic',
    confidence: 0.5,
    suggestedPreset: 'express'
  };
}
```

**Accessibility**:
- Banner: `role="alert" aria-live="polite"` (announces detection)
- Buttons: `aria-label="Apply recommended high security settings"`
- Keyboard: Tab to [Apply], Enter to accept

---

#### Step 2A: User Accepts Recommendation

**User Action**: Clicks [Apply Recommendation]

**System Response**:

```
┌──────────────────────────────────────────────────────────────┐
│  [Content in textarea...]                                    │
│  98 / 10,000 characters                                      │
│                                                               │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ ✓ Applied: High security                               │ │
│  │    • Expires in 1 hour (2:45 PM today)                 │ │
│  │    • Passphrase: debug-nov18-45a2 [👁️ Show] [📋 Copy]│ │
│  │    [Change Settings]                                   │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                               │
│  [Create Secret]  ← Ready (green, emphasized)               │
└──────────────────────────────────────────────────────────────┘
```

**State Changes**:
- Banner background: Blue → Green
- Icon: 🔍 → ✓
- Passphrase: Generated and shown (hidden by default)
- Button: Blue → Green (visual confirmation ready)

**Technical Implementation**:

```typescript
const applyRecommendation = () => {
  const passphrase = generatePassphrase();

  formState.value = {
    ttl: 3600,
    passphrase: passphrase,
    passphraseVisible: false,
  };

  suggestionState.value = 'applied';

  // Announce to screen readers
  announceToScreenReader('High security settings applied. Passphrase generated.');

  // Auto-focus create button (optional for keyboard users)
  nextTick(() => {
    createButtonRef.value?.focus();
  });
};
```

**Passphrase Generation**:

```typescript
function generatePassphrase(): string {
  const adjectives = ['swift', 'bright', 'calm', 'bold', 'quick'];
  const nouns = ['tiger', 'eagle', 'river', 'storm', 'star'];
  const date = new Date().toISOString().slice(5, 10).replace('-', '');
  const random = Math.floor(Math.random() * 1000);

  const adj = adjectives[Math.floor(Math.random() * adjectives.length)];
  const noun = nouns[Math.floor(Math.random() * nouns.length)];

  return `${adj}-${noun}-${date}-${random}`;
  // Example: "swift-tiger-1118-742"
}
```

**User Journey**: Paste → Apply → Create = **3 interactions, ~5 seconds**

---

#### Step 2B: User Customizes Settings

**User Action**: Clicks [Customize] instead of Apply

**System Response** (Expands inline):

```
┌──────────────────────────────────────────────────────────────┐
│  [Content in textarea...]                                    │
│  98 / 10,000 characters                                      │
│                                                               │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ Security Level                                         │ │
│  │  ○ Express (7 days, no passphrase)                    │ │
│  │  ● Secure (1 hour, passphrase) ← Recommended          │ │
│  │  ○ Custom (configure below)                           │ │
│  │                                                         │ │
│  │ ┌──────────────────────────────────────────────────────┤ │
│  │ │ Expires in          │ Passphrase                    │ │
│  │ │ [1 hour ▼]          │ [••••••••••••] 👁️           │ │
│  │ │ At 2:45 PM today    │ Auto-generated [🔄 Regenerate]│ │
│  │ └──────────────────────────────────────────────────────┘ │
│  │                                                         │ │
│  │ ▼ Advanced Options                                      │ │
│  │   □ Send via email                                      │ │
│  │   □ Display as QR code                                  │ │
│  │   □ Enable markdown rendering                           │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                               │
│  [Create Secret]                                             │
└──────────────────────────────────────────────────────────────┘
```

**Technical Implementation**:

```vue
<template>
  <div class="security-options" :class="{ expanded: isCustomizing }">
    <!-- Security Level Presets -->
    <fieldset>
      <legend>Security Level</legend>
      <div class="preset-options">
        <label>
          <input type="radio" name="preset" value="express" v-model="selectedPreset" />
          <span>⚡ Express (7 days, no passphrase)</span>
        </label>
        <label>
          <input type="radio" name="preset" value="secure" v-model="selectedPreset" />
          <span>🔒 Secure (1 hour, passphrase)</span>
          <span class="badge">Recommended</span>
        </label>
        <label>
          <input type="radio" name="preset" value="custom" v-model="selectedPreset" />
          <span>⚙️ Custom (configure below)</span>
        </label>
      </div>
    </fieldset>

    <!-- Detailed Configuration (if Custom selected) -->
    <div v-show="selectedPreset === 'custom'" class="custom-config">
      <div class="grid grid-cols-2 gap-4">
        <!-- TTL Selector -->
        <div>
          <label for="ttl-select">Expires in</label>
          <select id="ttl-select" v-model="formState.ttl">
            <option value="300">5 minutes</option>
            <option value="3600">1 hour</option>
            <option value="86400">1 day</option>
            <option value="604800">7 days</option>
          </select>
          <p class="help-text">At {{ formatExpirationTime(formState.ttl) }}</p>
        </div>

        <!-- Passphrase -->
        <div>
          <label for="passphrase">Passphrase (optional)</label>
          <div class="passphrase-input">
            <input
              id="passphrase"
              :type="passphraseVisible ? 'text' : 'password'"
              v-model="formState.passphrase"
              placeholder="Leave empty or auto-generate"
            />
            <button @click="togglePassphraseVisibility" aria-label="Toggle passphrase visibility">
              👁️
            </button>
          </div>
          <button @click="generateNewPassphrase">🔄 Regenerate</button>
        </div>
      </div>
    </div>

    <!-- Advanced Options (Collapsible) -->
    <details class="advanced-options">
      <summary>▼ Advanced Options</summary>
      <div class="options-grid">
        <label>
          <input type="checkbox" v-model="advancedOptions.sendEmail" />
          Send via email
        </label>
        <label>
          <input type="checkbox" v-model="advancedOptions.displayQR" />
          Display as QR code
        </label>
        <label>
          <input type="checkbox" v-model="advancedOptions.enableMarkdown" />
          Enable markdown rendering
        </label>
      </div>
    </details>
  </div>
</template>
```

**TTL Formatting**:

```typescript
function formatExpirationTime(ttl: number): string {
  const now = new Date();
  const expiresAt = new Date(now.getTime() + ttl * 1000);

  const isToday = expiresAt.toDateString() === now.toDateString();
  const isTomorrow = expiresAt.toDateString() ===
    new Date(now.getTime() + 86400000).toDateString();

  const timeStr = expiresAt.toLocaleTimeString('en-US', {
    hour: 'numeric',
    minute: '2-digit'
  });

  if (isToday) return `${timeStr} today`;
  if (isTomorrow) return `${timeStr} tomorrow`;

  return expiresAt.toLocaleString('en-US', {
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit'
  });
}
```

**Accessibility**:
- Radio buttons: `role="radiogroup"` with `aria-describedby`
- Checkboxes: Clear labels, no "click here"
- Collapsible sections: `<details>` element (native, accessible)
- Screen reader: "Security level. 3 options. Secure recommended."

---

#### Step 3: User Submits

**User Action**: Clicks [Create Secret]

**Loading State** (Immediate):

```
┌──────────────────────────────────────────────────────────────┐
│  [Content in textarea, now read-only with overlay...]        │
│                                                               │
│  ┌────────────────────────────────────────────────────────┐ │
│  │        🔐 Encrypting your secret...                    │ │
│  │        [Spinner animation]                             │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                               │
│  [Create Secret]  ← Disabled, loading state                 │
└──────────────────────────────────────────────────────────────┘
```

**Technical Implementation**:

```typescript
const createSecret = async () => {
  isSubmitting.value = true;

  try {
    // Show loading state
    loadingMessage.value = 'Encrypting your secret...';

    // Call API
    const response = await secretStore.conceal({
      secret: {
        kind: 'conceal',
        secret: formState.content,
        ttl: formState.ttl,
        passphrase: formState.passphrase,
        share_domain: formState.shareDomain,
      },
    });

    // Success: Navigate to receipt
    await router.push(`/receipt/${response.record.metadata.key}`);

  } catch (error) {
    // Error handling
    showError(error.message);
  } finally {
    isSubmitting.value = false;
  }
};
```

**Error Handling**:

```
┌──────────────────────────────────────────────────────────────┐
│  ┌────────────────────────────────────────────────────────┐ │
│  │ ⚠️ Error creating secret                               │ │
│  │ Rate limit exceeded. Please try again in 5 minutes.    │ │
│  │ [Dismiss]                                              │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                               │
│  [Content restored, editable again...]                      │
│                                                               │
│  [Create Secret]  ← Re-enabled                              │
└──────────────────────────────────────────────────────────────┘
```

**Error Types**:
- Rate limit: "Too many secrets. Please try again in X minutes."
- Network error: "Connection failed. Check your internet connection."
- Validation error: "Passphrase must be at least 8 characters."
- Server error: "Something went wrong. Please try again."

---

#### Step 4: Receipt Page

**After Successful Creation**:

```
┌──────────────────────────────────────────────────────────────┐
│  ✓ Secret Created Successfully                               │
├──────────────────────────────────────────────────────────────┤
│                                                               │
│  🔗 Share this link                                          │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ https://onetimesecret.com/private/abc123xyz456          │ │
│  │ [📋 Copy Link]                                         │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                               │
│  🔐 Passphrase (share separately via different channel)      │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ swift-tiger-1118-742                                   │ │
│  │ [📋 Copy Passphrase]  [👁️ Hide]                       │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                               │
│  ⏱️ Details                                                  │
│  • Expires in 59 minutes (at 2:45 PM today)                 │
│  • One-time view (link self-destructs after viewing)        │
│  • Not yet viewed                                            │
│                                                               │
│  ┌──────────────────┐  ┌──────────────────┐                 │
│  │ 📱 Show QR Code  │  │ 📧 Email Link    │                 │
│  └──────────────────┘  └──────────────────┘                 │
│                                                               │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ 🔥 Burn Secret (immediate destruction)                 │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                               │
│  [← Create Another Secret]                                   │
└──────────────────────────────────────────────────────────────┘
```

**Copy Workflow**:

```typescript
const copyToClipboard = async (text: string, type: 'link' | 'passphrase') => {
  try {
    await navigator.clipboard.writeText(text);

    // Visual feedback
    if (type === 'link') {
      linkCopyState.value = 'copied';
      setTimeout(() => linkCopyState.value = 'idle', 2000);
    } else {
      passphraseCopyState.value = 'copied';
      setTimeout(() => passphraseCopyState.value = 'idle', 2000);
    }

    // Screen reader announcement
    announceToScreenReader(`${type} copied to clipboard`);

  } catch (error) {
    // Fallback for older browsers
    showLegacyCopyModal(text);
  }
};
```

**Button States**:

```vue
<button
  @click="copyLink"
  :class="{
    'btn-primary': linkCopyState === 'idle',
    'btn-success': linkCopyState === 'copied',
  }"
  :aria-label="linkCopyState === 'copied' ? 'Link copied' : 'Copy link to clipboard'"
>
  <template v-if="linkCopyState === 'idle'">
    📋 Copy Link
  </template>
  <template v-else>
    ✓ Copied!
  </template>
</button>
```

**QR Code Modal** (When user clicks "Show QR Code"):

```
┌──────────────────────────────────────────────────────────────┐
│                          [× Close]                           │
│                                                               │
│                    Scan to view secret                       │
│                                                               │
│                  ┌─────────────────┐                         │
│                  │  [QR Code SVG]  │                         │
│                  │                 │                         │
│                  │   ████ ██ ████  │                         │
│                  │   ██ ████ ██ ██ │                         │
│                  │   ████ ██ ████  │                         │
│                  └─────────────────┘                         │
│                                                               │
│               Passphrase: swift-tiger-1118-742               │
│                                                               │
│  💡 Share passphrase separately (e.g., via text message)    │
│                                                               │
│  [Download QR Code]                                          │
└──────────────────────────────────────────────────────────────┘
```

**QR Code Generation**:

```typescript
import QRCode from 'qrcode';

const generateQRCode = async (url: string): Promise<string> => {
  try {
    const qrDataURL = await QRCode.toDataURL(url, {
      width: 400,
      margin: 2,
      color: {
        dark: '#000000',
        light: '#FFFFFF',
      },
      errorCorrectionLevel: 'H', // High redundancy
    });

    return qrDataURL;
  } catch (error) {
    console.error('QR generation failed:', error);
    throw new Error('Could not generate QR code');
  }
};
```

---

### 2.3 GENERATE PASSWORD MODE

#### Initial State

**User Action**: Clicks [🔑 Generate] tab

**System Response**:

```
┌──────────────────────────────────────────────────────────────┐
│  Share Mode: [📝 Text] [🔑 Generate] [📄 Document]          │
│                           ↑ Generate selected                │
│                                                               │
│  ┌────────────────────────────────────────────────────────┐ │
│  │                  🔑 Password Generator                  │ │
│  │                                                         │ │
│  │  Length: [12 ▼] characters                             │ │
│  │                                                         │ │
│  │  Include:                                               │ │
│  │   ☑ Uppercase (A-Z)                                    │ │
│  │   ☑ Lowercase (a-z)                                    │ │
│  │   ☑ Numbers (0-9)                                      │ │
│  │   ☑ Symbols (!@#$%)                                    │ │
│  │   ☐ Exclude ambiguous (0, O, l, I)                     │ │
│  │                                                         │ │
│  │  [Generate Password]                                   │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                               │
│  Preview: [No password generated yet]                       │
└──────────────────────────────────────────────────────────────┘
```

#### After Generation

**User Action**: Clicks [Generate Password]

**System Response**:

```
┌──────────────────────────────────────────────────────────────┐
│  [Password options above...]                                 │
│                                                               │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ Generated Password:                                    │ │
│  │  aB3$xZ9!kL2m                                          │ │
│  │  [📋 Copy]  [🔄 Regenerate]  [👁️ Hide]               │ │
│  │                                                         │ │
│  │  Strength: ██████████ Strong (94 bits entropy)        │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                               │
│  Expires in: [1 hour ▼]                                      │
│                                                               │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ 💡 How to share:                                      │   │
│  │  • Show QR code for in-person sharing                │   │
│  │  • Send link via secure channel (Slack, Signal)       │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                               │
│  [Create Secret with This Password]                          │
└──────────────────────────────────────────────────────────────┘
```

**Password Generation Algorithm**:

```typescript
interface PasswordOptions {
  length: number;
  uppercase: boolean;
  lowercase: boolean;
  numbers: boolean;
  symbols: boolean;
  excludeAmbiguous: boolean;
}

function generatePassword(options: PasswordOptions): string {
  const chars = {
    uppercase: 'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
    lowercase: 'abcdefghijklmnopqrstuvwxyz',
    numbers: '0123456789',
    symbols: '!@#$%^&*()_+-=[]{}|;:,.<>?',
  };

  const ambiguous = /[0O1lI]/g;

  // Build character set
  let charset = '';
  if (options.uppercase) charset += chars.uppercase;
  if (options.lowercase) charset += chars.lowercase;
  if (options.numbers) charset += chars.numbers;
  if (options.symbols) charset += chars.symbols;

  if (options.excludeAmbiguous) {
    charset = charset.replace(ambiguous, '');
  }

  // Generate password with crypto.getRandomValues (secure)
  const array = new Uint32Array(options.length);
  crypto.getRandomValues(array);

  let password = '';
  for (let i = 0; i < options.length; i++) {
    password += charset[array[i] % charset.length];
  }

  // Ensure at least one character from each selected category
  password = ensureComplexity(password, options, charset);

  return password;
}

function calculateEntropy(password: string, charset: string): number {
  // Entropy = log2(charset^length)
  return Math.log2(Math.pow(charset.length, password.length));
}
```

**Strength Indicator**:

```typescript
function getPasswordStrength(entropy: number): { label: string; color: string; percentage: number } {
  if (entropy < 40) return { label: 'Weak', color: 'red', percentage: 30 };
  if (entropy < 60) return { label: 'Fair', color: 'orange', percentage: 50 };
  if (entropy < 80) return { label: 'Good', color: 'yellow', percentage: 70 };
  if (entropy < 100) return { label: 'Strong', color: 'green', percentage: 90 };
  return { label: 'Very Strong', color: 'green', percentage: 100 };
}
```

---

### 2.4 DOCUMENT (MARKDOWN) MODE

#### Initial State

**User Action**: Clicks [📄 Document] tab

**System Response**:

```
┌──────────────────────────────────────────────────────────────┐
│  Share Mode: [📝 Text] [🔑 Generate] [📄 Document]          │
│                                        ↑ Document selected   │
│                                                               │
│  ┌─────────────────────┬────────────────────────────────────┐│
│  │ ✏️ Edit             │ 👁️ Preview                        ││
│  ├─────────────────────┼────────────────────────────────────┤│
│  │                     │                                    ││
│  │ # Welcome!          │ Welcome!                           ││
│  │                     │ ═══════                            ││
│  │ Your credentials:   │                                    ││
│  │                     │ Your credentials:                  ││
│  │ - **Email**: user   │ • Email: user@example.com          ││
│  │ - **Pass**: temp    │ • Pass: temp123                    ││
│  │                     │                                    ││
│  └─────────────────────┴────────────────────────────────────┘│
│                                                               │
│  💡 Use markdown for formatting (**, #, `, lists)           │
│                                                               │
│  Expires in: [3 days ▼]     Send via email                  │
│  To: [recipient@example.com_____________________________]    │
│                                                               │
│  [Create & Send Document]                                    │
└──────────────────────────────────────────────────────────────┘
```

**Markdown Editor Implementation**:

```vue
<template>
  <div class="markdown-editor">
    <div class="editor-toolbar">
      <button @click="insertMarkdown('bold')" title="Bold">
        <strong>B</strong>
      </button>
      <button @click="insertMarkdown('italic')" title="Italic">
        <em>I</em>
      </button>
      <button @click="insertMarkdown('code')" title="Code">
        &lt;/&gt;
      </button>
      <button @click="insertMarkdown('link')" title="Link">
        🔗
      </button>
      <button @click="insertMarkdown('list')" title="List">
        ≡
      </button>
    </div>

    <div class="split-view">
      <!-- Editor Pane -->
      <div class="editor-pane">
        <textarea
          ref="editorRef"
          v-model="content"
          @input="updatePreview"
          placeholder="# Start writing..."
          class="markdown-input"
        ></textarea>
      </div>

      <!-- Preview Pane -->
      <div class="preview-pane" v-html="renderedMarkdown"></div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { marked } from 'marked';
import DOMPurify from 'dompurify';

const content = ref('');
const renderedMarkdown = computed(() => {
  const raw = marked(content.value);
  return DOMPurify.sanitize(raw);
});

const insertMarkdown = (type: string) => {
  const textarea = editorRef.value;
  const start = textarea.selectionStart;
  const end = textarea.selectionEnd;
  const selectedText = content.value.substring(start, end);

  let insertion = '';
  switch (type) {
    case 'bold':
      insertion = `**${selectedText || 'bold text'}**`;
      break;
    case 'italic':
      insertion = `*${selectedText || 'italic text'}*`;
      break;
    case 'code':
      insertion = `\`${selectedText || 'code'}\``;
      break;
    case 'link':
      insertion = `[${selectedText || 'link text'}](url)`;
      break;
    case 'list':
      insertion = `\n- ${selectedText || 'list item'}`;
      break;
  }

  content.value = content.value.substring(0, start) + insertion + content.value.substring(end);
};
</script>
```

**Markdown Preview Styling**:

```css
.preview-pane {
  @apply prose prose-slate max-w-none;
  @apply p-6 bg-gray-50 rounded-lg;
  @apply dark:prose-invert dark:bg-slate-800;
}

.preview-pane h1 {
  @apply text-3xl font-bold mb-4 border-b-2 pb-2;
}

.preview-pane h2 {
  @apply text-2xl font-semibold mb-3 mt-6;
}

.preview-pane code {
  @apply bg-gray-200 dark:bg-slate-700 px-2 py-1 rounded text-sm font-mono;
}

.preview-pane pre {
  @apply bg-gray-900 text-gray-100 p-4 rounded-lg overflow-x-auto;
}

.preview-pane ul {
  @apply list-disc pl-6 space-y-2;
}
```

---

### 2.5 MOBILE EXPERIENCE SPECIFICATIONS

#### Bottom Sheet Component

**Collapsed State** (Suggestions visible):

```
┌─────────────────────┐
│ [Content in        │
│  textarea...]      │
│                     │
│                     │
├─────────────────────┤ ← Drag handle
│ ▲ Swipe up         │
│                     │
│ 🔍 Detected: Creds │
│ ⚡ High security   │
│  [Apply]  [Custom] │
└─────────────────────┘
┌─────────────────────┐ ← Sticky footer
│ [Create Secret]     │
└─────────────────────┘
```

**Expanded State** (Full options):

```
┌─────────────────────┐ ← Bottom sheet covers screen
│ ──── Swipe down    │
│                     │
│ Security Level      │
│  ○ Express          │
│  ● Secure ✓         │
│  ○ Custom           │
│                     │
│ Expires in          │
│ [1 hour ▼]          │
│                     │
│ Passphrase          │
│ [•••••] 👁️ [🔄]    │
│                     │
│ [Apply Settings]    │
│                     │
│ ▼ Advanced          │
│  □ Email            │
│  □ QR Code          │
└─────────────────────┘
┌─────────────────────┐ ← Sticky footer still visible
│ [Create Secret]     │
└─────────────────────┘
```

**Technical Implementation**:

```vue
<template>
  <Teleport to="body">
    <div
      class="bottom-sheet"
      :class="{
        collapsed: !isExpanded,
        expanded: isExpanded
      }"
      :style="{ transform: `translateY(${dragOffset}px)` }"
    >
      <!-- Drag Handle -->
      <div
        class="handle"
        @touchstart="handleDragStart"
        @touchmove="handleDragMove"
        @touchend="handleDragEnd"
      >
        <div class="handle-bar"></div>
      </div>

      <!-- Content -->
      <div class="sheet-content">
        <slot></slot>
      </div>
    </div>
  </Teleport>
</template>

<script setup lang="ts">
const isExpanded = ref(false);
const dragOffset = ref(0);
const startY = ref(0);

const handleDragStart = (e: TouchEvent) => {
  startY.value = e.touches[0].clientY;
};

const handleDragMove = (e: TouchEvent) => {
  const deltaY = e.touches[0].clientY - startY.value;

  // Only allow dragging down when expanded, or up when collapsed
  if ((isExpanded.value && deltaY > 0) || (!isExpanded.value && deltaY < 0)) {
    dragOffset.value = deltaY;
  }
};

const handleDragEnd = () => {
  // Snap to expanded or collapsed based on drag distance
  if (Math.abs(dragOffset.value) > 100) {
    isExpanded.value = !isExpanded.value;
  }

  // Reset with spring animation
  dragOffset.value = 0;
};
</script>

<style scoped>
.bottom-sheet {
  @apply fixed left-0 right-0 z-50;
  @apply bg-white dark:bg-slate-900;
  @apply rounded-t-3xl shadow-2xl;
  @apply transition-transform duration-300 ease-out;
  bottom: calc(env(safe-area-inset-bottom) + 4rem);
}

.bottom-sheet.collapsed {
  @apply h-32;
}

.bottom-sheet.expanded {
  @apply h-[70vh];
}

.handle {
  @apply flex justify-center items-center;
  @apply h-8 cursor-grab active:cursor-grabbing;
}

.handle-bar {
  @apply w-12 h-1.5 bg-gray-300 rounded-full;
}

.sheet-content {
  @apply overflow-y-auto p-6;
  @apply pb-safe; /* Respects safe area insets */
}
</style>
```

#### Mobile Gesture Navigation

**Swipe Left/Right** (Between modes):

```typescript
const modeSwipeHandler = {
  threshold: 50, // px
  currentMode: 'text',
  modes: ['text', 'generate', 'document'],

  handleSwipe(direction: 'left' | 'right') {
    const currentIndex = this.modes.indexOf(this.currentMode);

    if (direction === 'left' && currentIndex < this.modes.length - 1) {
      // Swipe left → Next mode
      this.currentMode = this.modes[currentIndex + 1];
      switchToMode(this.currentMode);
    } else if (direction === 'right' && currentIndex > 0) {
      // Swipe right → Previous mode
      this.currentMode = this.modes[currentIndex - 1];
      switchToMode(this.currentMode);
    }
  }
};
```

**Long Press** (Quick actions):

```typescript
const longPressHandler = {
  timeout: 500, // ms

  onLongPress(element: HTMLElement, callback: () => void) {
    let timer: NodeJS.Timeout;

    element.addEventListener('touchstart', (e) => {
      timer = setTimeout(() => {
        // Vibrate (if supported)
        if ('vibrate' in navigator) {
          navigator.vibrate(50);
        }

        callback();
      }, this.timeout);
    });

    element.addEventListener('touchend', () => {
      clearTimeout(timer);
    });
  }
};

// Usage: Long press "Create Secret" → Show share options
longPressHandler.onLongPress(createButtonRef.value, () => {
  showQuickShareMenu(); // Opens: Copy, QR, Email options
});
```

---

## PART 3: ACCESSIBILITY REQUIREMENTS (WCAG 2.1 AA)

### 3.1 KEYBOARD NAVIGATION

#### Navigation Order (Desktop)

```
Tab Order:
1. Mode tabs (Text, Generate, Document) → Arrow keys to switch
2. Textarea / Input area → Enter to start new line
3. Suggestion banner (if visible) → [Apply] or [Customize]
4. Security options (if customizing) → Radio buttons, selects
5. Advanced options (if expanded) → Checkboxes
6. [Create Secret] button → Enter to submit
7. Skip to footer links
```

**Keyboard Shortcuts**:

| Shortcut | Action | Context |
|----------|--------|---------|
| `Cmd/Ctrl+K` | Focus textarea | Global |
| `Cmd/Ctrl+Enter` | Submit form | When textarea focused |
| `Cmd/Ctrl+G` | Switch to Generate mode | Global |
| `Cmd/Ctrl+M` | Switch to Markdown mode | Global |
| `Esc` | Close modal/collapse options | When expanded |
| `?` | Show keyboard shortcuts help | Global |

**Implementation**:

```vue
<script setup lang="ts">
onMounted(() => {
  document.addEventListener('keydown', (e) => {
    // Global shortcuts
    if ((e.metaKey || e.ctrlKey) && e.key === 'k') {
      e.preventDefault();
      focusTextarea();
    }

    if ((e.metaKey || e.ctrlKey) && e.key === 'Enter') {
      e.preventDefault();
      if (canSubmit.value) {
        submitForm();
      }
    }

    if ((e.metaKey || e.ctrlKey) && e.key === 'g') {
      e.preventDefault();
      switchMode('generate');
    }

    if (e.key === 'Escape') {
      closeModal();
      collapseOptions();
    }

    if (e.key === '?' && !isTyping.value) {
      e.preventDefault();
      showKeyboardHelp();
    }
  });
});
</script>
```

---

### 3.2 SCREEN READER EXPERIENCE

#### ARIA Landmarks

```html
<body>
  <!-- Skip Links (first focusable elements) -->
  <a href="#main-content" class="sr-only-focusable">Skip to main content</a>
  <a href="#create-form" class="sr-only-focusable">Skip to create secret form</a>

  <!-- Header -->
  <header role="banner">
    <nav role="navigation" aria-label="Main navigation">
      <!-- Navigation items -->
    </nav>
  </header>

  <!-- Main Content -->
  <main id="main-content" role="main" aria-label="Create secret">
    <!-- Mode selector -->
    <div role="tablist" aria-label="Sharing mode">
      <button role="tab" aria-selected="true" aria-controls="text-panel">
        Text
      </button>
      <button role="tab" aria-selected="false" aria-controls="generate-panel">
        Generate
      </button>
      <button role="tab" aria-selected="false" aria-controls="document-panel">
        Document
      </button>
    </div>

    <!-- Form -->
    <form id="create-form" role="form" aria-label="Create secret form">
      <div role="tabpanel" id="text-panel" aria-labelledby="text-tab">
        <!-- Form fields -->
      </div>
    </form>
  </main>

  <!-- Footer -->
  <footer role="contentinfo">
    <!-- Footer content -->
  </footer>
</body>
```

#### Form Labels and Descriptions

```html
<!-- Textarea with full context -->
<label for="secret-content" id="secret-label">
  Secret content
  <span class="sr-only">
    Enter the sensitive information you want to share securely
  </span>
</label>
<textarea
  id="secret-content"
  aria-labelledby="secret-label"
  aria-describedby="secret-help secret-count"
  aria-required="true"
  aria-invalid="false"
></textarea>
<p id="secret-help" class="help-text">
  Your secret will be encrypted and viewable only once
</p>
<p id="secret-count" aria-live="polite" aria-atomic="true">
  <span class="sr-only">Character count:</span>
  0 of 10,000 characters
</p>

<!-- Security level with proper grouping -->
<fieldset>
  <legend id="security-legend">
    Security level
    <span class="help-text">Choose how long the secret should remain accessible</span>
  </legend>

  <div role="radiogroup" aria-labelledby="security-legend">
    <label>
      <input
        type="radio"
        name="security"
        value="express"
        aria-describedby="express-desc"
      />
      <span>Express</span>
    </label>
    <p id="express-desc" class="preset-description">
      7 days, no passphrase
    </p>

    <label>
      <input
        type="radio"
        name="security"
        value="secure"
        aria-describedby="secure-desc"
        aria-checked="true"
      />
      <span>Secure</span>
      <span class="badge" role="status">Recommended</span>
    </label>
    <p id="secure-desc" class="preset-description">
      1 hour, passphrase required
    </p>
  </div>
</fieldset>
```

#### Live Regions for Dynamic Content

```html
<!-- Auto-detection announcement -->
<div
  role="status"
  aria-live="polite"
  aria-atomic="true"
  class="suggestion-banner"
>
  <p>
    <span class="sr-only">Content detected:</span>
    Database credentials
  </p>
  <p>
    <span class="sr-only">Recommendation:</span>
    High security settings suggested. Expires in 1 hour with passphrase required.
  </p>
  <button aria-label="Apply recommended high security settings">
    Apply
  </button>
</div>

<!-- Error messages -->
<div
  role="alert"
  aria-live="assertive"
  aria-atomic="true"
  id="form-errors"
>
  <!-- Dynamically injected error messages -->
</div>

<!-- Loading state -->
<div
  role="status"
  aria-live="polite"
  aria-busy="true"
>
  Encrypting your secret. Please wait.
</div>
```

#### Screen Reader Only Text

```css
/* Visually hidden but accessible to screen readers */
.sr-only {
  position: absolute;
  width: 1px;
  height: 1px;
  padding: 0;
  margin: -1px;
  overflow: hidden;
  clip: rect(0, 0, 0, 0);
  white-space: nowrap;
  border-width: 0;
}

/* Visible on focus (for skip links) */
.sr-only-focusable:focus {
  position: static;
  width: auto;
  height: auto;
  margin: 0;
  overflow: visible;
  clip: auto;
  white-space: normal;
}
```

---

### 3.3 COLOR CONTRAST

**WCAG 2.1 AA Requirements**: Minimum 4.5:1 contrast ratio for normal text, 3:1 for large text (18pt+)

#### Color Palette (Accessible)

```typescript
const colors = {
  // Primary action (meets 4.5:1 on white)
  primary: {
    DEFAULT: '#2563eb', // Blue 600
    hover: '#1d4ed8',   // Blue 700
    active: '#1e40af',  // Blue 800
  },

  // Success (meets 4.5:1 on white)
  success: {
    DEFAULT: '#16a34a', // Green 600
    hover: '#15803d',   // Green 700
  },

  // Danger (meets 4.5:1 on white)
  danger: {
    DEFAULT: '#dc2626', // Red 600
    hover: '#b91c1c',   // Red 700
  },

  // Text (meets 7:1 on white - AAA level)
  text: {
    primary: '#0f172a',   // Slate 900
    secondary: '#475569', // Slate 600
    tertiary: '#64748b',  // Slate 500
  },

  // Borders (meets 3:1 for UI components)
  border: {
    DEFAULT: '#cbd5e1', // Slate 300
    focus: '#2563eb',   // Blue 600 (visible focus indicator)
  },
};
```

**Contrast Verification**:

```typescript
// Utility to check contrast ratio
function getContrastRatio(foreground: string, background: string): number {
  const lum1 = getRelativeLuminance(foreground);
  const lum2 = getRelativeLuminance(background);

  const lighter = Math.max(lum1, lum2);
  const darker = Math.min(lum1, lum2);

  return (lighter + 0.05) / (darker + 0.05);
}

// Ensure all interactive elements meet WCAG AA
const buttonContrast = getContrastRatio(colors.primary.DEFAULT, '#ffffff');
console.assert(buttonContrast >= 4.5, 'Button contrast too low');
```

---

### 3.4 FOCUS INDICATORS

**Visible Focus States**:

```css
/* Default focus outline (browser-native) */
*:focus {
  outline: 2px solid #2563eb; /* Blue 600 */
  outline-offset: 2px;
}

/* Enhanced focus for interactive elements */
button:focus-visible,
a:focus-visible,
input:focus-visible,
textarea:focus-visible,
select:focus-visible {
  outline: 3px solid #2563eb;
  outline-offset: 2px;
  box-shadow: 0 0 0 3px rgba(37, 99, 235, 0.1);
}

/* Focus within (for composite widgets) */
.mode-tabs:focus-within {
  outline: 2px solid #2563eb;
  outline-offset: 2px;
}

/* Remove focus outline for mouse users (but keep for keyboard) */
.js-focus-visible :focus:not(.focus-visible) {
  outline: none;
}
```

**Focus Management**:

```typescript
// Focus trap for modal dialogs
const useFocusTrap = (containerRef: Ref<HTMLElement | null>) => {
  const focusableElements = computed(() => {
    if (!containerRef.value) return [];

    return Array.from(
      containerRef.value.querySelectorAll(
        'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])'
      )
    ) as HTMLElement[];
  });

  const firstElement = computed(() => focusableElements.value[0]);
  const lastElement = computed(() =>
    focusableElements.value[focusableElements.value.length - 1]
  );

  const handleKeyDown = (e: KeyboardEvent) => {
    if (e.key !== 'Tab') return;

    // Shift+Tab on first element → Focus last
    if (e.shiftKey && document.activeElement === firstElement.value) {
      e.preventDefault();
      lastElement.value?.focus();
    }
    // Tab on last element → Focus first
    else if (!e.shiftKey && document.activeElement === lastElement.value) {
      e.preventDefault();
      firstElement.value?.focus();
    }
  };

  onMounted(() => {
    document.addEventListener('keydown', handleKeyDown);
    firstElement.value?.focus();
  });

  onUnmounted(() => {
    document.removeEventListener('keydown', handleKeyDown);
  });
};
```

---

### 3.5 RESPONSIVE TEXT & ZOOM

**Support for 200% zoom** (WCAG 2.1 AA requirement):

```css
/* Use relative units (rem, em) instead of px */
:root {
  font-size: 16px; /* Base font size */
}

body {
  font-size: 1rem; /* 16px at 100%, 32px at 200% zoom */
}

h1 {
  font-size: 2rem; /* 32px at 100%, 64px at 200% zoom */
}

.button {
  font-size: 0.875rem; /* 14px at 100%, 28px at 200% zoom */
  padding: 0.625rem 1.25rem; /* Scales proportionally */
}

/* Ensure tap targets scale correctly */
.mobile-button {
  min-height: 44px; /* Apple HIG minimum */
  min-width: 44px;
  /* At 200% zoom, this becomes 88px (still accessible) */
}

/* Prevent horizontal scrolling at 200% zoom */
.container {
  max-width: 100%;
  overflow-x: hidden;
}

/* Text doesn't break layout when zoomed */
.secret-link {
  word-break: break-all;
  overflow-wrap: break-word;
}
```

**Respecting User Preferences**:

```css
/* Reduced motion for users with vestibular disorders */
@media (prefers-reduced-motion: reduce) {
  *,
  *::before,
  *::after {
    animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
    transition-duration: 0.01ms !important;
    scroll-behavior: auto !important;
  }

  .bottom-sheet {
    transition: none;
  }
}

/* High contrast mode */
@media (prefers-contrast: high) {
  .button {
    border: 2px solid currentColor;
  }

  .suggestion-banner {
    border: 3px solid currentColor;
  }
}

/* Dark mode (respects OS preference) */
@media (prefers-color-scheme: dark) {
  :root {
    color-scheme: dark;
  }

  body {
    background-color: #0f172a;
    color: #f1f5f9;
  }
}
```

---

## PART 4: TECHNICAL APPROACH

### 4.1 COMPONENT ARCHITECTURE

#### Component Tree

```
App.vue
├── Header.vue
│   ├── Logo.vue
│   ├── Navigation.vue
│   └── UserMenu.vue
│
├── CreateSecretPage.vue (main page)
│   ├── ModeSelector.vue
│   │   ├── ModeTab.vue (Text)
│   │   ├── ModeTab.vue (Generate)
│   │   └── ModeTab.vue (Document)
│   │
│   ├── TextMode.vue
│   │   ├── SecretTextarea.vue
│   │   ├── SuggestionBanner.vue
│   │   ├── SecurityOptions.vue (progressive)
│   │   └── AdvancedOptions.vue (collapsible)
│   │
│   ├── GenerateMode.vue
│   │   ├── PasswordOptions.vue
│   │   ├── PasswordPreview.vue
│   │   └── StrengthMeter.vue
│   │
│   ├── DocumentMode.vue
│   │   ├── MarkdownEditor.vue
│   │   ├── EditorToolbar.vue
│   │   ├── MarkdownPreview.vue
│   │   └── EmailOptions.vue
│   │
│   ├── BottomSheet.vue (mobile only)
│   │   └── [mode content]
│   │
│   └── CreateButton.vue (sticky footer mobile)
│
├── ReceiptPage.vue
│   ├── SecretLink.vue
│   ├── PassphraseDisplay.vue
│   ├── ExpirationInfo.vue
│   ├── ShareOptions.vue
│   │   ├── CopyButton.vue
│   │   ├── QRCodeButton.vue
│   │   └── EmailButton.vue
│   └── BurnButton.vue
│
└── QRCodeModal.vue
    ├── QRCode.vue (canvas-based)
    └── DownloadButton.vue
```

#### Core Composables

```typescript
// composables/useSecretCreation.ts
export function useSecretCreation() {
  const formState = reactive({
    mode: 'text',
    content: '',
    ttl: 604800,
    passphrase: '',
    security: 'express',
    advancedOptions: {
      sendEmail: false,
      displayQR: false,
      enableMarkdown: false,
    },
  });

  const detectionResult = ref<DetectionResult | null>(null);
  const isSubmitting = ref(false);

  const detectContent = (content: string) => {
    detectionResult.value = detectContentType(content);
  };

  const applyRecommendation = () => {
    if (!detectionResult.value) return;

    const preset = securityPresets[detectionResult.value.suggestedPreset];
    formState.ttl = preset.ttl;
    formState.passphrase = preset.passphrase === 'auto-generate'
      ? generatePassphrase()
      : '';
  };

  const submitSecret = async () => {
    isSubmitting.value = true;

    try {
      const response = await secretStore.conceal({
        secret: {
          kind: formState.mode === 'generate' ? 'generate' : 'conceal',
          secret: formState.content,
          ttl: formState.ttl,
          passphrase: formState.passphrase,
        },
      });

      await router.push(`/receipt/${response.record.metadata.key}`);
    } catch (error) {
      handleError(error);
    } finally {
      isSubmitting.value = false;
    }
  };

  return {
    formState,
    detectionResult,
    isSubmitting,
    detectContent,
    applyRecommendation,
    submitSecret,
  };
}

// composables/useUserPreferences.ts
export function useUserPreferences() {
  const preferences = useLocalStorage('ots_preferences', {
    lastUsedPreset: 'express',
    presetUsageCount: {
      express: 0,
      secure: 0,
      custom: 0,
    },
    totalSecretsCreated: 0,
  });

  const getMostUsedPreset = computed(() => {
    const counts = preferences.value.presetUsageCount;
    return Object.entries(counts).sort(([,a], [,b]) => b - a)[0][0];
  });

  const recordPresetUsage = (preset: string) => {
    preferences.value.lastUsedPreset = preset;
    preferences.value.presetUsageCount[preset]++;
    preferences.value.totalSecretsCreated++;
  };

  return {
    preferences,
    getMostUsedPreset,
    recordPresetUsage,
  };
}

// composables/useKeyboardShortcuts.ts
export function useKeyboardShortcuts(handlers: Record<string, () => void>) {
  const handleKeyDown = (e: KeyboardEvent) => {
    const key = [
      e.ctrlKey && 'Ctrl',
      e.metaKey && 'Cmd',
      e.shiftKey && 'Shift',
      e.altKey && 'Alt',
      e.key,
    ].filter(Boolean).join('+');

    if (handlers[key]) {
      e.preventDefault();
      handlers[key]();
    }
  };

  onMounted(() => {
    document.addEventListener('keydown', handleKeyDown);
  });

  onUnmounted(() => {
    document.removeEventListener('keydown', handleKeyDown);
  });
}
```

---

### 4.2 TAILWIND 4.1 PATTERNS

#### Configuration

```typescript
// tailwind.config.ts
import type { Config } from 'tailwindcss';
import forms from '@tailwindcss/forms';
import typography from '@tailwindcss/typography';
import containerQueries from '@tailwindcss/container-queries';

export default {
  content: ['./src/**/*.{vue,ts}'],
  darkMode: 'class',
  theme: {
    extend: {
      colors: {
        brand: {
          50: '#eff6ff',
          600: '#2563eb',
          700: '#1d4ed8',
        },
      },
      animation: {
        'pulse-slow': 'pulse 3s cubic-bezier(0.4, 0, 0.6, 1) infinite',
        'slide-up': 'slideUp 0.3s ease-out',
        'fade-in': 'fadeIn 0.2s ease-in',
      },
      keyframes: {
        slideUp: {
          '0%': { transform: 'translateY(100%)' },
          '100%': { transform: 'translateY(0)' },
        },
        fadeIn: {
          '0%': { opacity: '0' },
          '100%': { opacity: '1' },
        },
      },
    },
  },
  plugins: [
    forms,
    typography,
    containerQueries,
  ],
} satisfies Config;
```

#### Utility Patterns

```vue
<template>
  <!-- Responsive container with safe areas -->
  <div class="container mx-auto px-4 sm:px-6 lg:px-8 pb-safe">

    <!-- Card pattern with dark mode -->
    <div class="rounded-xl border border-gray-200 bg-white p-6 shadow-sm
                dark:border-gray-700 dark:bg-slate-900">

      <!-- Typography scale -->
      <h1 class="text-3xl font-bold text-gray-900 dark:text-white">
        Create Secret
      </h1>

      <!-- Interactive element states -->
      <button class="rounded-lg bg-brand-600 px-4 py-2.5 text-white
                     hover:bg-brand-700 active:bg-brand-800
                     focus-visible:outline focus-visible:outline-2
                     focus-visible:outline-offset-2 focus-visible:outline-brand-600
                     disabled:opacity-50 disabled:cursor-not-allowed
                     transition-colors duration-150">
        Create Secret
      </button>

      <!-- Form input with focus -->
      <input
        type="text"
        class="block w-full rounded-lg border-gray-300
               focus:border-brand-500 focus:ring-brand-500
               dark:border-gray-600 dark:bg-slate-800 dark:text-white"
      />

      <!-- Container queries for responsive components -->
      <div class="@container">
        <div class="@sm:grid @sm:grid-cols-2 gap-4">
          <!-- Responsive grid that changes based on container, not viewport -->
        </div>
      </div>

    </div>
  </div>
</template>
```

#### Custom Utilities

```css
/* globals.css */
@tailwind base;
@tailwind components;
@tailwind utilities;

@layer base {
  /* Safe area insets for mobile notches/home indicators */
  .pb-safe {
    padding-bottom: env(safe-area-inset-bottom);
  }

  .pt-safe {
    padding-top: env(safe-area-inset-top);
  }
}

@layer components {
  /* Button variants */
  .btn-primary {
    @apply rounded-lg bg-brand-600 px-4 py-2.5 text-sm font-semibold text-white shadow-sm;
    @apply hover:bg-brand-700 active:bg-brand-800;
    @apply focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2;
    @apply focus-visible:outline-brand-600;
    @apply disabled:opacity-50 disabled:cursor-not-allowed;
    @apply transition-colors duration-150;
  }

  .btn-secondary {
    @apply rounded-lg bg-white px-4 py-2.5 text-sm font-semibold text-gray-900;
    @apply ring-1 ring-inset ring-gray-300;
    @apply hover:bg-gray-50 active:bg-gray-100;
    @apply dark:bg-slate-800 dark:text-white dark:ring-gray-600;
    @apply dark:hover:bg-slate-700;
  }

  /* Form elements */
  .form-input {
    @apply block w-full rounded-lg border-gray-300 shadow-sm;
    @apply focus:border-brand-500 focus:ring-brand-500;
    @apply dark:border-gray-600 dark:bg-slate-800 dark:text-white;
    @apply disabled:opacity-50 disabled:bg-gray-100 dark:disabled:bg-slate-900;
  }

  /* Card patterns */
  .card {
    @apply rounded-xl border border-gray-200 bg-white p-6 shadow-sm;
    @apply dark:border-gray-700 dark:bg-slate-900;
  }

  /* Sticky footer (mobile) */
  .sticky-footer {
    @apply fixed bottom-0 left-0 right-0 z-20;
    @apply border-t border-gray-200 bg-white/95 p-4 shadow-lg backdrop-blur;
    @apply dark:border-gray-700 dark:bg-slate-900/95;
    @apply pb-[calc(1rem+env(safe-area-inset-bottom))];
  }
}

@layer utilities {
  /* Visually hidden (screen reader only) */
  .sr-only {
    @apply absolute -m-px h-px w-px overflow-hidden p-0;
    clip: rect(0, 0, 0, 0);
    white-space: nowrap;
    border-width: 0;
  }

  .sr-only-focusable:focus {
    @apply static m-0 h-auto w-auto overflow-visible p-0;
    clip: auto;
    white-space: normal;
  }

  /* Animations respect reduced motion */
  @media (prefers-reduced-motion: reduce) {
    .animate-pulse,
    .animate-slide-up,
    .animate-fade-in {
      animation: none;
    }
  }
}
```

---

### 4.3 STATE MANAGEMENT (PINIA)

#### Secret Creation Store

```typescript
// stores/secretCreationStore.ts
import { defineStore } from 'pinia';
import type { SecretFormData, DetectionResult } from '@/types';

export const useSecretCreationStore = defineStore('secretCreation', {
  state: () => ({
    mode: 'text' as 'text' | 'generate' | 'document',
    formData: {
      content: '',
      ttl: 604800,
      passphrase: '',
      securityPreset: 'express',
      recipient: '',
      shareDomain: '',
    } as SecretFormData,
    detection: null as DetectionResult | null,
    isSubmitting: false,
    errors: [] as string[],
  }),

  getters: {
    canSubmit: (state) => {
      if (state.mode === 'text' && !state.formData.content) return false;
      if (state.isSubmitting) return false;
      return true;
    },

    suggestedPreset: (state) => {
      return state.detection?.suggestedPreset || 'express';
    },
  },

  actions: {
    setMode(mode: 'text' | 'generate' | 'document') {
      this.mode = mode;
      this.errors = [];
    },

    updateContent(content: string) {
      this.formData.content = content;

      // Trigger detection after debounce
      if (content.length > 10) {
        this.detectContentType();
      }
    },

    detectContentType() {
      this.detection = detectContentType(this.formData.content);
    },

    applyRecommendation() {
      if (!this.detection) return;

      const preset = securityPresets[this.detection.suggestedPreset];
      this.formData.ttl = preset.ttl;

      if (preset.passphrase === 'auto-generate') {
        this.formData.passphrase = generatePassphrase();
      }

      this.formData.securityPreset = this.detection.suggestedPreset;
    },

    async submit() {
      this.isSubmitting = true;
      this.errors = [];

      try {
        const payload = this.buildPayload();
        const response = await this.submitToAPI(payload);

        // Store in local preferences
        const prefs = useUserPreferences();
        prefs.recordPresetUsage(this.formData.securityPreset);

        // Navigate to receipt
        await router.push(`/receipt/${response.record.metadata.key}`);

        // Reset form
        this.reset();

      } catch (error) {
        this.handleError(error);
      } finally {
        this.isSubmitting = false;
      }
    },

    buildPayload() {
      const base = {
        kind: this.mode === 'generate' ? 'generate' : 'conceal',
        ttl: this.formData.ttl,
        passphrase: this.formData.passphrase || undefined,
        recipient: this.formData.recipient || undefined,
        share_domain: this.formData.shareDomain || undefined,
      };

      if (this.mode === 'text' || this.mode === 'document') {
        return {
          secret: {
            ...base,
            secret: this.formData.content,
          },
        };
      } else {
        return {
          secret: {
            ...base,
            length: 12,
            character_sets: {
              uppercase: true,
              lowercase: true,
              numbers: true,
              symbols: true,
            },
          },
        };
      }
    },

    async submitToAPI(payload: any) {
      const secretStore = useSecretStore();

      if (this.mode === 'generate') {
        return await secretStore.generate(payload);
      } else {
        return await secretStore.conceal(payload);
      }
    },

    handleError(error: any) {
      if (error.response?.status === 429) {
        this.errors.push('Rate limit exceeded. Please try again in a few minutes.');
      } else if (error.response?.data?.form_fields) {
        this.errors = Object.values(error.response.data.form_fields);
      } else {
        this.errors.push('Something went wrong. Please try again.');
      }
    },

    reset() {
      this.formData = {
        content: '',
        ttl: 604800,
        passphrase: '',
        securityPreset: 'express',
        recipient: '',
        shareDomain: '',
      };
      this.detection = null;
      this.errors = [];
    },
  },
});
```

---

### 4.4 PERFORMANCE CONSIDERATIONS

#### Code Splitting

```typescript
// router/index.ts
import { createRouter, createWebHistory } from 'vue-router';

const routes = [
  {
    path: '/',
    name: 'create',
    component: () => import('@/views/CreateSecretPage.vue'), // Lazy load
  },
  {
    path: '/receipt/:metadataKey',
    name: 'receipt',
    component: () => import('@/views/ReceiptPage.vue'), // Lazy load
  },
  {
    path: '/private/:metadataKey',
    name: 'view-secret',
    component: () => import('@/views/ViewSecretPage.vue'), // Lazy load
  },
];

export const router = createRouter({
  history: createWebHistory(),
  routes,
});
```

#### Debouncing & Throttling

```typescript
// utils/debounce.ts
export function debounce<T extends (...args: any[]) => any>(
  fn: T,
  delay: number
): (...args: Parameters<T>) => void {
  let timeoutId: ReturnType<typeof setTimeout>;

  return function(...args: Parameters<T>) {
    clearTimeout(timeoutId);
    timeoutId = setTimeout(() => fn(...args), delay);
  };
}

// Usage in component
const debouncedDetect = debounce((content: string) => {
  detectContentType(content);
}, 200);

watch(() => formData.content, (newContent) => {
  debouncedDetect(newContent);
});
```

#### Virtual Scrolling (for long content)

```typescript
// For very long secrets (edge case)
import { useVirtualList } from '@vueuse/core';

const { list, containerProps, wrapperProps } = useVirtualList(
  secretLines, // Split content by \n
  { itemHeight: 24 } // Line height
);
```

#### Optimistic Updates

```typescript
// Show success immediately, rollback on error
const createSecret = async () => {
  const tempId = generateTempId();

  // Optimistic: Navigate immediately
  await router.push(`/receipt/${tempId}`);
  showLoadingReceipt();

  try {
    const response = await submitToAPI();
    // Replace temp with real data
    updateReceiptWithReal(response);
  } catch (error) {
    // Rollback: Go back to form
    await router.push('/');
    showError(error);
  }
};
```

---

### 4.5 TESTING STRATEGY

#### Unit Tests (Vitest)

```typescript
// __tests__/detectContentType.test.ts
import { describe, it, expect } from 'vitest';
import { detectContentType } from '@/utils/contentDetection';

describe('Content Type Detection', () => {
  it('detects database credentials', () => {
    const content = 'DB_HOST=prod.example.com\nDB_PASS=secret123';
    const result = detectContentType(content);

    expect(result.type).toBe('credentials');
    expect(result.suggestedPreset).toBe('secure');
    expect(result.confidence).toBeGreaterThan(0.8);
  });

  it('detects WiFi passwords', () => {
    const content = 'SSID: MyWiFi\nPassword: abc123xyz';
    const result = detectContentType(content);

    expect(result.type).toBe('wifi');
    expect(result.suggestedFeature).toBe('qr-code');
  });

  it('detects markdown content', () => {
    const content = '# Welcome\n\n**Bold text**\n\n```code```';
    const result = detectContentType(content);

    expect(result.type).toBe('markdown');
    expect(result.suggestedFeature).toBe('markdown-rendering');
  });

  it('defaults to generic for plain text', () => {
    const content = 'Just some regular text';
    const result = detectContentType(content);

    expect(result.type).toBe('generic');
    expect(result.suggestedPreset).toBe('express');
  });
});
```

#### Component Tests (Vue Test Utils)

```typescript
// __tests__/SecretTextarea.test.ts
import { mount } from '@vue/test-utils';
import { describe, it, expect } from 'vitest';
import SecretTextarea from '@/components/SecretTextarea.vue';

describe('SecretTextarea', () => {
  it('auto-focuses on mount', () => {
    const wrapper = mount(SecretTextarea);
    const textarea = wrapper.find('textarea').element;

    expect(document.activeElement).toBe(textarea);
  });

  it('emits update event on input', async () => {
    const wrapper = mount(SecretTextarea);
    const textarea = wrapper.find('textarea');

    await textarea.setValue('test content');

    expect(wrapper.emitted('update:modelValue')).toBeTruthy();
    expect(wrapper.emitted('update:modelValue')[0]).toEqual(['test content']);
  });

  it('shows character count', async () => {
    const wrapper = mount(SecretTextarea);
    const textarea = wrapper.find('textarea');

    await textarea.setValue('test');

    expect(wrapper.text()).toContain('4 / 10,000');
  });

  it('disables submit when empty', () => {
    const wrapper = mount(SecretTextarea, {
      props: { modelValue: '' }
    });

    expect(wrapper.vm.canSubmit).toBe(false);
  });
});
```

#### Accessibility Tests (Axe)

```typescript
// __tests__/a11y/CreateSecretPage.a11y.test.ts
import { mount } from '@vue/test-utils';
import { axe, toHaveNoViolations } from 'jest-axe';
import CreateSecretPage from '@/views/CreateSecretPage.vue';

expect.extend(toHaveNoViolations);

describe('CreateSecretPage Accessibility', () => {
  it('has no axe violations', async () => {
    const wrapper = mount(CreateSecretPage);
    const results = await axe(wrapper.html());

    expect(results).toHaveNoViolations();
  });

  it('has proper ARIA landmarks', () => {
    const wrapper = mount(CreateSecretPage);

    expect(wrapper.find('[role="main"]').exists()).toBe(true);
    expect(wrapper.find('[role="form"]').exists()).toBe(true);
    expect(wrapper.find('textarea[aria-required="true"]').exists()).toBe(true);
  });

  it('announces detection to screen readers', async () => {
    const wrapper = mount(CreateSecretPage);

    await wrapper.find('textarea').setValue('DB_PASS=secret');

    const liveRegion = wrapper.find('[aria-live="polite"]');
    expect(liveRegion.exists()).toBe(true);
    expect(liveRegion.text()).toContain('Detected');
  });
});
```

#### E2E Tests (Playwright)

```typescript
// e2e/createSecret.spec.ts
import { test, expect } from '@playwright/test';

test.describe('Create Secret Flow', () => {
  test('completes happy path', async ({ page }) => {
    await page.goto('/');

    // Fill textarea
    await page.fill('textarea', 'My secret content');

    // Click create button
    await page.click('button:has-text("Create Secret")');

    // Should navigate to receipt
    await expect(page).toHaveURL(/\/receipt\/.+/);

    // Should show link
    await expect(page.locator('text=https://onetimesecret.com')).toBeVisible();

    // Can copy link
    await page.click('button:has-text("Copy Link")');
    await expect(page.locator('text=Copied')).toBeVisible();
  });

  test('applies recommendation', async ({ page }) => {
    await page.goto('/');

    // Paste credentials
    await page.fill('textarea', 'DB_HOST=prod\nDB_PASS=secret');

    // Wait for detection
    await expect(page.locator('text=Detected: Database credentials')).toBeVisible();

    // Apply recommendation
    await page.click('button:has-text("Apply")');

    // Should show applied state
    await expect(page.locator('text=Applied: High security')).toBeVisible();

    // Create secret
    await page.click('button:has-text("Create Secret")');

    // Should succeed
    await expect(page).toHaveURL(/\/receipt\/.+/);
  });

  test('keyboard navigation works', async ({ page }) => {
    await page.goto('/');

    // Tab to textarea (should auto-focus, so press Tab to test focus trap)
    await page.keyboard.press('Tab');

    // Type content
    await page.keyboard.type('Secret');

    // Cmd+Enter to submit
    await page.keyboard.press('Meta+Enter');

    // Should submit
    await expect(page).toHaveURL(/\/receipt\/.+/);
  });
});
```

---

## IMPLEMENTATION ROADMAP

### Phase 1: Foundation (Week 1-2)
- [ ] Set up new component structure
- [ ] Implement mode selector (tabs)
- [ ] Create SecretTextarea with auto-focus
- [ ] Build security preset system
- [ ] Implement content detection logic

### Phase 2: Core UX (Week 3-4)
- [ ] Suggestion banner with apply/customize
- [ ] Progressive disclosure for options
- [ ] Generate password mode
- [ ] Markdown editor + preview
- [ ] Receipt page enhancements

### Phase 3: Mobile Optimization (Week 5-6)
- [ ] Bottom sheet component
- [ ] Sticky footer for mobile
- [ ] Touch gestures (swipe, long-press)
- [ ] Safe area insets
- [ ] Performance optimization

### Phase 4: Accessibility (Week 7)
- [ ] ARIA landmarks and labels
- [ ] Keyboard shortcuts
- [ ] Screen reader testing
- [ ] Focus management
- [ ] Contrast verification

### Phase 5: Advanced Features (Week 8-9)
- [ ] QR code generation
- [ ] Email integration
- [ ] Behavioral learning (localStorage)
- [ ] Markdown rendering for recipients
- [ ] Error handling improvements

### Phase 6: Testing & Polish (Week 10)
- [ ] Unit tests (90%+ coverage)
- [ ] E2E tests (critical paths)
- [ ] Accessibility audit (axe)
- [ ] Performance profiling
- [ ] Cross-browser testing

---

## SUCCESS METRICS

### Quantitative Goals
- **Time-to-task**: <10s for 80% of secret creations
- **Mobile completion rate**: >95% (parity with desktop)
- **Suggestion acceptance**: >60% of users accept recommendations
- **Error rate**: <5% of submissions result in errors
- **Accessibility**: 0 critical axe violations

### Qualitative Goals
- Users understand security options without confusion
- Mobile experience feels native, not compromised
- Power users discover keyboard shortcuts naturally
- First-time users complete flow without help documentation

---

## CONCLUSION

This specification provides a complete, implementation-ready design for the OneTimeSecret create-secret experience redesign. The approach balances:

✅ **Speed** — Time-to-task-completion optimized (50-85% improvements)
✅ **Utility** — Smart detection, presets, behavioral learning
✅ **Accessibility** — WCAG 2.1 AA compliance throughout
✅ **Mobile-first** — Touch-optimized, gesture-aware, native patterns
✅ **Maintainability** — Component architecture, type safety, test coverage

The design enables future features (Linear Secrets, Inbound Secrets, QR codes, markdown) while improving the core experience today.

**Ready for development handoff.**
