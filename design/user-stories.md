# User Stories: Secret Form V2 Redesign

**Project:** OneTimeSecret Homepage Create Secret Experience Redesign
**Approach:** Smart Defaults with Progressive Disclosure
**Epic:** Conversational Secret Creation Interface
**Target Release:** 5 weeks (Phased implementation)

---

## Table of Contents

1. [Epic Overview](#epic-overview)
2. [Phase 1: Foundation Stories](#phase-1-foundation-stories-week-1)
3. [Phase 2: Inline Controls Stories](#phase-2-inline-controls-stories-week-2)
4. [Phase 3: Advanced Options Stories](#phase-3-advanced-options-stories-week-3)
5. [Phase 4: Success & Polish Stories](#phase-4-success--polish-stories-week-4)
6. [Phase 5: Migration Stories](#phase-5-migration-stories-week-5)
7. [Non-Functional Requirements](#non-functional-requirements)

---

## Epic Overview

**As a** OneTimeSecret user
**I want** a simple, focused interface for sharing secrets
**So that** I can quickly and confidently create secure links without complexity or confusion

**Business Value:**
- 60% reduction in time to first secret
- 35% increase in mobile completion rate
- 40% increase in options discovery
- Improved user confidence and satisfaction

**Success Metrics:**
- Time to first secret < 5 seconds
- Mobile completion rate > 80%
- WCAG 2.1 AA compliance 100%
- Options usage +40%

---

## Phase 1: Foundation Stories (Week 1)

### Story 1.1: Basic Form Structure

**As a** user
**I want** to see a clean, focused textarea when I land on the homepage
**So that** I immediately understand this is where I paste/type my secret

**Acceptance Criteria:**
- [ ] SecretFormV2.vue component created as new implementation
- [ ] Large textarea (min 200px height) with monospace font
- [ ] Placeholder text: "Paste or type your secret here..."
- [ ] Textarea auto-focused on desktop (not mobile)
- [ ] Responsive layout (320px to 1440px+)
- [ ] Submit button disabled when textarea empty
- [ ] Submit button enabled when content exists
- [ ] Headline "Share a secret securely" centered above form

**Technical Notes:**
```vue
// src/components/secrets/form/SecretFormV2.vue
- Use existing Tailwind config
- Leverage @tailwindcss/forms plugin
- Component should be self-contained
- Use composition API (script setup)
```

**Dependencies:** None

**Story Points:** 5

**Design Reference:** `design/mockups/secret-form-v2-mockup.html` - State 1

---

### Story 1.2: Character Counter

**As a** user typing/pasting content
**I want** to see how many characters I've used
**So that** I know if I'm approaching the limit

**Acceptance Criteria:**
- [ ] Counter appears when content reaches 50% of max (5,000 chars)
- [ ] Shows format: "5,000 / 10,000" with commas
- [ ] Color-coded indicator (dot):
  - Green: < 80% (0-8,000 chars)
  - Amber: 80-95% (8,000-9,500 chars)
  - Red: > 95% (9,500+ chars)
- [ ] Positioned bottom-right of textarea
- [ ] Semi-transparent background (white/90 with backdrop-blur)
- [ ] Updates in real-time as user types
- [ ] Accessible via aria-live="polite"

**Technical Notes:**
```typescript
// Reuse existing useCharCounter composable
// Update colors to match design system
const statusColor = computed(() => {
  const percentage = charCount.value / maxLength;
  if (percentage < 0.8) return 'bg-emerald-400';
  if (percentage < 0.95) return 'bg-amber-400';
  return 'bg-red-400';
});
```

**Dependencies:** Story 1.1

**Story Points:** 3

**Design Reference:** State 2

---

### Story 1.3: Auto-Resize Textarea

**As a** user pasting multi-line content
**I want** the textarea to expand to show my content
**So that** I don't have to scroll within a small box

**Acceptance Criteria:**
- [ ] Textarea grows as content is added
- [ ] Min height: 200px
- [ ] Max height: 400px
- [ ] Scrollbar appears only when max height reached
- [ ] Smooth resize transition (no jarring jumps)
- [ ] Works on paste, type, and content deletion
- [ ] Preserves resize on browser resize

**Technical Notes:**
```typescript
function handleInput() {
  nextTick(() => {
    if (!textareaRef.value) return;
    textareaRef.value.style.height = 'auto';
    const scrollHeight = textareaRef.value.scrollHeight;
    const newHeight = Math.min(
      Math.max(scrollHeight, MIN_HEIGHT),
      MAX_HEIGHT
    );
    textareaHeight.value = `${newHeight}px`;
  });
}
```

**Dependencies:** Story 1.1

**Story Points:** 3

---

### Story 1.4: Form Submission

**As a** user with content in the textarea
**I want** to click "Share Securely" to create my secret
**So that** I receive a shareable link

**Acceptance Criteria:**
- [ ] Submit button labeled "Share Securely"
- [ ] Button disabled when no content
- [ ] Button enabled when content exists
- [ ] On click, show loading state: "Creating..." with spinner
- [ ] Integrate with existing POST /api/v2/secret/conceal endpoint
- [ ] Validate content using existing Zod schema
- [ ] Show error message if submission fails
- [ ] On success, navigate to /receipt/{key} (Phase 1 behavior)
- [ ] Loading state prevents double-submission

**Technical Notes:**
```typescript
// Use existing useSecretConcealer composable as reference
// Create new useSecretFormV2 composable
// Reuse existing API integration
// Maintain CSRF/Altcha protection
```

**Dependencies:** Stories 1.1, 1.2, 1.3

**Story Points:** 8

**Design Reference:** States 1-2 (button states)

---

### Story 1.5: Keyboard Shortcuts

**As a** power user
**I want** to submit the form with Cmd/Ctrl+Enter
**So that** I can work at keyboard speed

**Acceptance Criteria:**
- [ ] Cmd+Enter (Mac) or Ctrl+Enter (Windows/Linux) submits form
- [ ] Works when focus is anywhere in the form
- [ ] Only works when form is valid (content exists)
- [ ] Visual hint below button: "or press ⌘ + Enter"
- [ ] Hint shows correct modifier key based on OS
- [ ] Hint hidden on mobile (<768px)
- [ ] Keyboard shortcut registered on mount
- [ ] Keyboard shortcut cleaned up on unmount

**Technical Notes:**
```typescript
// Create useKeyboardShortcuts composable
// Detect platform: navigator.platform
// Register global keydown listener
// Clean up in onUnmounted
```

**Dependencies:** Story 1.4

**Story Points:** 3

---

### Story 1.6: Mobile Responsive Layout

**As a** mobile user
**I want** the form to work perfectly on my phone
**So that** I can share secrets from any device

**Acceptance Criteria:**
- [ ] Single-column layout on mobile (<768px)
- [ ] Full-width submit button on mobile
- [ ] Larger tap targets (min 44x44px) on mobile
- [ ] No horizontal scrolling
- [ ] Font size min 16px (prevents iOS zoom)
- [ ] Textarea not auto-focused on mobile
- [ ] Keyboard shortcuts hint hidden on mobile
- [ ] Appropriate spacing for thumb-zone interaction
- [ ] Tested on iOS Safari and Android Chrome
- [ ] Works from 320px width

**Technical Notes:**
```vue
<!-- Mobile-first classes -->
<button class="
  w-full py-4 px-6           <!-- Mobile: full-width, large -->
  md:w-auto md:py-3 md:px-8  <!-- Desktop: auto-width -->
">
```

**Dependencies:** Stories 1.1-1.5

**Story Points:** 5

**Design Reference:** State: Mobile View

---

## Phase 2: Inline Controls Stories (Week 2)

### Story 2.1: Inline Controls Bar

**As a** user
**I want** to see the default expiration time and security settings
**So that** I know what will happen to my secret without clicking anything

**Acceptance Criteria:**
- [ ] InlineControls.vue component created
- [ ] Bar displays below textarea, above submit button
- [ ] Light gray background (bg-gray-50/50)
- [ ] Contains three sections:
  1. Expiration control (left)
  2. Passphrase control (middle)
  3. More options button (right)
- [ ] Desktop: horizontal layout with dividers
- [ ] Mobile: stacked vertical layout
- [ ] Responsive breakpoint at 768px
- [ ] Matches design system colors and spacing

**Technical Notes:**
```vue
<div class="
  flex flex-col gap-2               <!-- Mobile: stack -->
  md:flex-row md:items-center md:gap-4  <!-- Desktop: horizontal -->
  rounded-lg border border-gray-200
  bg-gray-50/50 p-3
">
```

**Dependencies:** Story 1.1

**Story Points:** 5

**Design Reference:** State 2 (inline controls)

---

### Story 2.2: Expiration Quick-Select Dropdown

**As a** user
**I want** to quickly change the expiration time
**So that** I can control how long my secret is available

**Acceptance Criteria:**
- [ ] ExpirationQuickSelect.vue component created
- [ ] Default shows: "Expires in: **1 hour**" (bold value)
- [ ] Clock icon visible
- [ ] Chevron indicates clickable
- [ ] On click, dropdown opens with options:
  - 1 hour (default, selected)
  - 3 hours
  - 1 day
  - 3 days
  - 7 days
- [ ] Selected option highlighted (brand-50 background)
- [ ] Clicking option updates display and closes dropdown
- [ ] Click outside closes dropdown
- [ ] Escape key closes dropdown
- [ ] Arrow keys navigate options when open
- [ ] Enter/Space selects focused option
- [ ] Accessible with ARIA attributes

**Technical Notes:**
```typescript
// Use @vueuse/core onClickOutside
// Options match backend TTL values
const expirationOptions = [
  { value: 3600, label: '1 hour' },
  { value: 10800, label: '3 hours' },
  { value: 86400, label: '1 day' },
  // ...
];
```

**ARIA Requirements:**
```html
<button
  aria-expanded="false"
  aria-controls="expiration-menu"
  aria-haspopup="menu">
<div
  id="expiration-menu"
  role="menu">
```

**Dependencies:** Story 2.1

**Story Points:** 8

**Design Reference:** State 3 (dropdown open)

---

### Story 2.3: Add Passphrase Toggle

**As a** security-conscious user
**I want** to add a passphrase to my secret
**So that** only people with the passphrase can access it

**Acceptance Criteria:**
- [ ] Default shows: "Add passphrase" with lock icon
- [ ] On click, toggles to passphrase input mode
- [ ] Input field appears for passphrase entry
- [ ] "Remove" link appears to disable passphrase
- [ ] Input type="password" with show/hide toggle (eye icon)
- [ ] Auto-focus on passphrase input when enabled
- [ ] Input accepts any characters
- [ ] Max length matches backend validation
- [ ] Shows "Passphrase:" label when enabled
- [ ] Mobile: input takes full width
- [ ] Desktop: input fits within inline controls area

**Technical Notes:**
```typescript
const passphraseEnabled = ref(false);
const passphrase = ref('');

function enablePassphrase() {
  passphraseEnabled.value = true;
  nextTick(() => {
    passphraseInputRef.value?.focus();
  });
}
```

**Dependencies:** Story 2.1

**Story Points:** 5

**Design Reference:** State 4 (passphrase added)

---

### Story 2.4: Passphrase Strength Indicator

**As a** user entering a passphrase
**I want** to see if my passphrase is strong enough
**So that** I can make my secret more secure

**Acceptance Criteria:**
- [ ] Strength meter appears below passphrase input
- [ ] Shows 4 bars (segments)
- [ ] Bars fill based on strength calculation:
  - 1 bar (Weak): < 8 chars - Red
  - 2 bars (Fair): 8+ chars - Amber
  - 3 bars (Good): 12+ chars + mixed case - Emerald
  - 4 bars (Strong): 12+ chars + mixed case + numbers + special - Emerald
- [ ] Label shows: "Weak", "Fair", "Good", "Strong"
- [ ] Updates in real-time as user types
- [ ] Only visible when passphrase has content
- [ ] Does NOT enforce strength (informational only)
- [ ] Smooth animation when bars fill

**Technical Notes:**
```typescript
const passphraseStrength = computed(() => {
  const p = passphrase.value;
  if (!p) return 0;
  let strength = 0;
  if (p.length >= 8) strength++;
  if (p.length >= 12) strength++;
  if (/[A-Z]/.test(p) && /[a-z]/.test(p)) strength++;
  if (/[0-9]/.test(p) && /[^A-Za-z0-9]/.test(p)) strength++;
  return Math.min(strength, 4);
});
```

**Dependencies:** Story 2.3

**Story Points:** 5

**Design Reference:** State 4 (strength bars)

---

### Story 2.5: More Options Button

**As a** user who needs advanced features
**I want** a clear way to access more options
**So that** I can configure email sending or other advanced features

**Acceptance Criteria:**
- [ ] "More" button with right arrow/chevron
- [ ] Positioned at right end of inline controls (desktop)
- [ ] Brand color text (brand-600)
- [ ] On click, opens Advanced Options Panel (Phase 3)
- [ ] Hover state shows light brand background
- [ ] Mobile: Full-width row at bottom of stacked controls
- [ ] Keyboard accessible (Tab to focus, Enter to activate)
- [ ] Focus indicator visible

**Technical Notes:**
```vue
<button
  @click="$emit('show-advanced')"
  class="
    text-brand-600 hover:bg-brand-50
    dark:text-brand-400 dark:hover:bg-brand-900/30
    md:ml-auto
  ">
  <span>More</span>
  <svg><!-- Chevron --></svg>
</button>
```

**Dependencies:** Story 2.1

**Story Points:** 2

---

### Story 2.6: Inline Controls State Synchronization

**As a** developer
**I want** inline controls to sync with form state
**So that** all settings are properly submitted

**Acceptance Criteria:**
- [ ] TTL value synced to form.ttl
- [ ] Passphrase enabled state synced to form
- [ ] Passphrase value synced to form.passphrase
- [ ] Changes in inline controls update parent form
- [ ] Form submission includes all inline control values
- [ ] Values validated before submission
- [ ] Settings persist if user navigates away and back (optional)
- [ ] Unit tests cover state synchronization

**Technical Notes:**
```typescript
// Parent component (SecretFormV2)
<InlineControls
  v-model:ttl="form.ttl"
  v-model:passphrase-enabled="passphraseEnabled"
  v-model:passphrase="form.passphrase"
/>

// InlineControls emits
defineEmits<{
  'update:ttl': [value: number];
  'update:passphraseEnabled': [value: boolean];
  'update:passphrase': [value: string];
}>();
```

**Dependencies:** Stories 2.1-2.5

**Story Points:** 3

---

## Phase 3: Advanced Options Stories (Week 3)

### Story 3.1: Advanced Options Modal

**As a** user
**I want** to access advanced options without cluttering the main interface
**So that** I can configure email sending, burn after reading, and custom domains

**Acceptance Criteria:**
- [ ] AdvancedOptionsPanel.vue component created
- [ ] Opens as modal dialog on desktop (centered overlay)
- [ ] Opens as bottom sheet on mobile (slides up)
- [ ] Semi-transparent backdrop (bg-black/50)
- [ ] Click backdrop to close
- [ ] Escape key to close
- [ ] Focus trapped within modal when open
- [ ] Header with "Advanced Options" title and X button
- [ ] Footer with "Cancel" and "Apply" buttons
- [ ] Body scrollable if content overflows
- [ ] Smooth enter/exit animations
- [ ] ARIA dialog attributes

**Technical Notes:**
```vue
<!-- Use Teleport to body -->
<Teleport to="body">
  <Transition>
    <div
      v-if="visible"
      role="dialog"
      aria-modal="true"
      aria-labelledby="advanced-options-title">
    </div>
  </Transition>
</Teleport>
```

**ARIA Requirements:**
```html
- role="dialog"
- aria-modal="true"
- aria-labelledby pointing to title
- Focus trap (focus first input on open)
- Return focus to trigger on close
```

**Dependencies:** Story 2.5

**Story Points:** 8

**Design Reference:** State 5 (modal open)

---

### Story 3.2: Burn After Reading Option

**As a** user sharing highly sensitive information
**I want** to ensure my secret is deleted after one view
**So that** it can only be accessed once

**Acceptance Criteria:**
- [ ] Checkbox labeled "Burn after reading"
- [ ] Descriptive text: "Secret will be deleted after first view"
- [ ] Unchecked by default
- [ ] When checked, sets burn_after_reading flag
- [ ] Clear visual distinction (checkbox + label + description)
- [ ] Keyboard accessible (Space to toggle)
- [ ] State persists while modal is open
- [ ] Integrates with existing backend burn functionality
- [ ] Success message confirms burn setting

**Technical Notes:**
```vue
<label class="flex items-start gap-3 cursor-pointer">
  <input
    type="checkbox"
    v-model="burnAfterReading"
    class="mt-0.5 rounded"
  />
  <div>
    <div class="font-medium">Burn after reading</div>
    <div class="text-sm text-gray-600">
      Secret will be deleted after first view
    </div>
  </div>
</label>
```

**Dependencies:** Story 3.1

**Story Points:** 3

---

### Story 3.3: Email Recipient Input

**As a** user
**I want** to send the secret link directly via email
**So that** I don't have to manually copy and send it

**Acceptance Criteria:**
- [ ] Email input field with label "Send via email"
- [ ] Placeholder: "recipient@example.com"
- [ ] Input type="email" for mobile keyboard
- [ ] Email format validation (client-side)
- [ ] Help text: "Requires authentication"
- [ ] If not authenticated, show auth prompt (existing flow)
- [ ] Supports single recipient (current backend limitation)
- [ ] Email sent on form submission if recipient provided
- [ ] Error handling if email send fails
- [ ] Success message confirms email sent

**Technical Notes:**
```typescript
// Reuse existing email validation
// Check if user authenticated
// Use existing recipient field in API
const recipient = ref('');

// Email validation
const emailValid = computed(() => {
  if (!recipient.value) return true; // Optional field
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(recipient.value);
});
```

**Dependencies:** Story 3.1

**Story Points:** 5

---

### Story 3.4: Share Domain Selector

**As a** user with custom domains
**I want** to choose which domain to use for the secret link
**So that** I can use branded or custom domains

**Acceptance Criteria:**
- [ ] Dropdown labeled "Share domain"
- [ ] Shows available domains from config
- [ ] Default domain selected by default
- [ ] Only visible if multiple domains configured
- [ ] Updates form.shareDomain on selection
- [ ] Domain applies to generated link
- [ ] Uses existing useDomainDropdown composable
- [ ] Works with existing backend domain logic

**Technical Notes:**
```typescript
// Reuse existing composable
import { useDomainDropdown } from '@/composables/useDomainDropdown';

const { availableDomains, selectedDomain } = useDomainDropdown();

// Only show if multiple domains
const showDomainSelector = computed(() =>
  availableDomains.value.length > 1
);
```

**Dependencies:** Story 3.1

**Story Points:** 3

---

### Story 3.5: Advanced Panel Apply/Cancel

**As a** user
**I want** to apply or cancel my advanced settings
**So that** I have control over whether changes take effect

**Acceptance Criteria:**
- [ ] "Cancel" button discards changes and closes modal
- [ ] "Apply" button saves changes and closes modal
- [ ] Changes applied immediately to form state
- [ ] Changes reflected in main form view
- [ ] ESC key acts as Cancel
- [ ] Click backdrop acts as Cancel (with confirmation if changed)
- [ ] Enter key in inputs does NOT submit form
- [ ] Tab order: fields → Cancel → Apply → X button → wrap

**Technical Notes:**
```typescript
function apply() {
  // Values already bound via v-model
  // Just close the modal
  emit('update:visible', false);
}

function cancel() {
  // Reset to original values if needed
  // Or just close (values stay as-is)
  emit('update:visible', false);
}
```

**Dependencies:** Stories 3.1-3.4

**Story Points:** 3

---

### Story 3.6: Focus Management for Modal

**As a** keyboard user
**I want** proper focus management when the modal opens/closes
**So that** I can navigate efficiently

**Acceptance Criteria:**
- [ ] When modal opens, focus moves to first input (email field)
- [ ] Tab cycles through: inputs → Cancel → Apply → X → back to first
- [ ] Shift+Tab cycles backward
- [ ] Focus cannot escape modal while open (focus trap)
- [ ] When modal closes, focus returns to "More" button
- [ ] ESC key closes modal and returns focus
- [ ] Screen reader announces modal open/close

**Technical Notes:**
```typescript
// Use @vueuse/core useFocusTrap
import { useFocusTrap } from '@vueuse/core';

const modalRef = ref(null);
const { activate, deactivate } = useFocusTrap(modalRef);

watch(visible, (isVisible) => {
  if (isVisible) {
    activate();
    // Focus first input
    nextTick(() => {
      firstInputRef.value?.focus();
    });
  } else {
    deactivate();
    // Return focus to trigger
    triggerRef.value?.focus();
  }
});
```

**Dependencies:** Story 3.1

**Story Points:** 5

---

## Phase 4: Success & Polish Stories (Week 4)

### Story 4.1: Success State Component

**As a** user who just created a secret
**I want** to see a clear success message with the link
**So that** I know it worked and can copy the link

**Acceptance Criteria:**
- [ ] SuccessState.vue component created
- [ ] Shows success icon (green checkmark in circle)
- [ ] Headline: "Secret link created"
- [ ] Link displayed in code box with copy button
- [ ] "Copy Link" primary button
- [ ] Settings summary shows what was applied
- [ ] "Create another secret" link at bottom
- [ ] Success state replaces form (transition)
- [ ] Accessible announcements for screen readers

**Technical Notes:**
```vue
<div class="space-y-6 text-center">
  <!-- Icon -->
  <div class="rounded-full bg-emerald-100 p-3">
    <CheckIcon class="h-8 w-8 text-emerald-600" />
  </div>

  <!-- Link display -->
  <code>{{ secretLink }}</code>

  <!-- Settings summary -->
  <ul>
    <li>Expires in {{ expirationLabel }}</li>
    <li v-if="hasPassphrase">Passphrase required</li>
  </ul>
</div>
```

**Dependencies:** Story 1.4

**Story Points:** 5

**Design Reference:** State 6 (success)

---

### Story 4.2: Copy to Clipboard

**As a** user
**I want** to easily copy the secret link
**So that** I can share it via any channel

**Acceptance Criteria:**
- [ ] Copy button next to link (icon)
- [ ] "Copy Link" primary button below
- [ ] Uses navigator.clipboard API
- [ ] Shows confirmation on copy: "✓ Copied!"
- [ ] Confirmation fades after 2 seconds
- [ ] Fallback for browsers without clipboard API
- [ ] Error handling if copy fails
- [ ] Keyboard accessible (Enter/Space to copy)
- [ ] Works on both desktop and mobile

**Technical Notes:**
```typescript
async function copyLink() {
  try {
    await navigator.clipboard.writeText(secretLink.value);
    copied.value = true;
    setTimeout(() => {
      copied.value = false;
    }, 2000);
  } catch (err) {
    // Fallback: select text for manual copy
    selectText(linkRef.value);
  }
}
```

**Dependencies:** Story 4.1

**Story Points:** 3

---

### Story 4.3: Create Another Secret

**As a** user who just shared a secret
**I want** to quickly create another one
**So that** I can share multiple secrets efficiently

**Acceptance Criteria:**
- [ ] "Create another secret →" link in success state
- [ ] On click, resets form to initial state
- [ ] Clears textarea
- [ ] Resets all options to defaults
- [ ] Smooth transition back to form view
- [ ] Focus returns to textarea
- [ ] Previous secret's link no longer accessible in UI
- [ ] Keyboard accessible

**Technical Notes:**
```typescript
function resetForm() {
  // Clear all form fields
  form.secret = '';
  form.passphrase = '';
  form.ttl = 3600;
  form.recipient = '';
  form.burnAfterReading = false;

  // Reset UI state
  submitted.value = false;
  createdSecret.value = null;

  // Focus textarea
  nextTick(() => {
    textareaRef.value?.focus();
  });
}
```

**Dependencies:** Story 4.1

**Story Points:** 3

---

### Story 4.4: Loading States

**As a** user waiting for my secret to be created
**I want** clear feedback that something is happening
**So that** I know the system is working

**Acceptance Criteria:**
- [ ] Submit button shows loading state
- [ ] Button text changes to "Creating..."
- [ ] Spinner icon appears in button
- [ ] Button disabled during submission
- [ ] Form fields disabled during submission
- [ ] Textarea grayed out/dimmed
- [ ] No other interactions possible during loading
- [ ] Loading state ends on success or error
- [ ] Accessible loading announcement

**Technical Notes:**
```vue
<button
  :disabled="isSubmitting"
  class="relative">
  <span v-if="isSubmitting" class="flex items-center gap-2">
    <SpinnerIcon class="animate-spin" />
    Creating...
  </span>
  <span v-else>Share Securely</span>
</button>
```

**ARIA:**
```html
<form :aria-busy="isSubmitting">
<div role="status" aria-live="polite" v-if="isSubmitting">
  Creating secret...
</div>
```

**Dependencies:** Story 1.4

**Story Points:** 3

---

### Story 4.5: Error Handling

**As a** user experiencing an error
**I want** clear information about what went wrong
**So that** I can fix the problem

**Acceptance Criteria:**
- [ ] Validation errors shown inline (red text, icon)
- [ ] Server errors shown in alert banner at top
- [ ] Network errors handled gracefully
- [ ] Error messages are specific and actionable
- [ ] Errors don't lose user's content
- [ ] Error state is clearable
- [ ] Submit can be retried after error
- [ ] Errors announced to screen readers

**Error Types:**
1. Validation errors (client-side)
   - Empty content: "Please enter a secret to share"
   - Invalid email: "Please enter a valid email address"
   - Passphrase too short (if enforced): "Passphrase must be at least 8 characters"

2. Server errors
   - 400: "Invalid request. Please check your input."
   - 403: "Authentication required for this action."
   - 429: "Too many requests. Please try again in a moment."
   - 500: "Server error. Please try again."

3. Network errors
   - "Network error. Please check your connection and try again."

**Technical Notes:**
```vue
<!-- Error banner -->
<div
  v-if="errors.length"
  role="alert"
  class="rounded-lg bg-red-50 p-4 text-red-800">
  <ul>
    <li v-for="error in errors">{{ error }}</li>
  </ul>
</div>

<!-- Inline error -->
<input
  :aria-invalid="hasError"
  :aria-errormessage="errorId"
/>
<div :id="errorId" role="alert">
  {{ errorMessage }}
</div>
```

**Dependencies:** Story 1.4

**Story Points:** 5

---

### Story 4.6: Animations & Transitions

**As a** user
**I want** smooth, subtle animations
**So that** the interface feels polished and responsive

**Acceptance Criteria:**
- [ ] Form → Success transition (fade + scale)
- [ ] Success → Form transition (fade + scale)
- [ ] Dropdown expand/collapse (slide down/up)
- [ ] Modal enter/exit (fade + slide)
- [ ] Passphrase input appear (slide down)
- [ ] Character counter appear (fade)
- [ ] Button hover states (color transition)
- [ ] All transitions 200-300ms duration
- [ ] Respects prefers-reduced-motion
- [ ] No animations if user prefers reduced motion

**Technical Notes:**
```vue
<!-- Transition component -->
<Transition
  enter-active-class="
    motion-safe:transition-all
    motion-safe:duration-200
    motion-reduce:transition-none
  "
  enter-from-class="opacity-0 scale-95"
  leave-to-class="opacity-0 scale-95">
  <component :is="currentView" />
</Transition>
```

```css
/* Respect motion preferences */
@media (prefers-reduced-motion: reduce) {
  *,
  *::before,
  *::after {
    animation-duration: 0.01ms !important;
    transition-duration: 0.01ms !important;
  }
}
```

**Dependencies:** All previous stories

**Story Points:** 5

---

### Story 4.7: Dark Mode Support

**As a** user who prefers dark mode
**I want** the new form to work in dark mode
**So that** it matches my system preferences

**Acceptance Criteria:**
- [ ] All components support dark mode
- [ ] Uses existing dark: Tailwind classes
- [ ] Color contrast maintained in dark mode (WCAG 2.1 AA)
- [ ] All states visible in dark mode (hover, focus, disabled)
- [ ] Icons visible in dark mode
- [ ] Tested with dark mode toggle
- [ ] Smooth transition between modes
- [ ] Respects system preference

**Technical Notes:**
```vue
<!-- Example dark mode classes -->
<div class="
  bg-white dark:bg-slate-900
  text-gray-900 dark:text-white
  border-gray-200 dark:border-gray-700
">
```

**Testing:**
- Test all states in dark mode
- Verify contrast ratios
- Check focus indicators
- Test animations

**Dependencies:** All Phase 1-4 stories

**Story Points:** 5

---

## Phase 5: Migration Stories (Week 5)

### Story 5.1: Feature Flag Implementation

**As a** product manager
**I want** to control the rollout of the new form
**So that** I can gradually release it to users

**Acceptance Criteria:**
- [ ] Feature flag created: `secret_form_v2`
- [ ] Flag controls which component renders
- [ ] A/B test capability (50/50 split)
- [ ] Admin panel to toggle flag
- [ ] Flag respects user segments (e.g., beta users)
- [ ] Fallback to old form if flag disabled
- [ ] Analytics tracking which version shown
- [ ] No errors if flag changes mid-session

**Technical Notes:**
```vue
<component
  :is="useFormV2 ? SecretFormV2 : SecretForm"
  v-bind="props"
/>
```

```typescript
import { useFeatureFlag } from '@/composables/useFeatureFlag';

const useFormV2 = useFeatureFlag('secret_form_v2');
```

**Dependencies:** All Phase 1-4 stories complete

**Story Points:** 5

---

### Story 5.2: Analytics Integration

**As a** product manager
**I want** to track user behavior with the new form
**So that** I can measure success metrics

**Events to Track:**
1. `form_v2_viewed` - User sees new form
2. `form_v2_content_added` - User adds content
3. `form_v2_option_changed` - User changes TTL
4. `form_v2_passphrase_added` - User adds passphrase
5. `form_v2_advanced_opened` - User opens advanced panel
6. `form_v2_submitted` - User submits form
7. `form_v2_success` - Secret created successfully
8. `form_v2_error` - Error occurred
9. `form_v2_copied` - User copied link
10. `form_v2_create_another` - User creates another

**Metrics to Calculate:**
- Time to first secret (from page load to submit)
- Completion rate
- Option usage rate
- Error rate
- Mobile vs desktop usage
- Passphrase usage rate
- Advanced panel usage rate

**Acceptance Criteria:**
- [ ] All events tracked with timestamps
- [ ] User ID included (if authenticated)
- [ ] Session ID for grouping
- [ ] Device type tracked (mobile/desktop)
- [ ] Browser/OS tracked
- [ ] Events sent to analytics platform
- [ ] Dashboard created for metrics
- [ ] Baseline metrics established

**Dependencies:** Story 5.1

**Story Points:** 8

---

### Story 5.3: A/B Test Setup

**As a** product manager
**I want** to run an A/B test comparing old vs new form
**So that** I can validate the redesign improves metrics

**Acceptance Criteria:**
- [ ] 50/50 split between old and new form
- [ ] Split is stable (same user sees same version)
- [ ] Split tracked in analytics
- [ ] Comparison dashboard created
- [ ] Metrics compared:
  - Time to first secret
  - Completion rate
  - Mobile completion rate
  - Option usage
  - Error rate
  - User satisfaction (survey)
- [ ] Statistical significance calculated
- [ ] Test runs for 2 weeks minimum
- [ ] Results documented

**Dependencies:** Stories 5.1, 5.2

**Story Points:** 8

---

### Story 5.4: Migration & Cleanup

**As a** developer
**I want** to remove the old form component
**So that** we reduce technical debt

**Acceptance Criteria:**
- [ ] New form proven successful in A/B test
- [ ] Feature flag set to 100% new form
- [ ] Monitor for 1 week with no issues
- [ ] Remove feature flag code
- [ ] Delete old SecretForm.vue component
- [ ] Update all references to use SecretFormV2
- [ ] Rename SecretFormV2 to SecretForm
- [ ] Update documentation
- [ ] Remove unused composables
- [ ] Update tests to reflect new component

**Checklist:**
- [ ] Backup old component
- [ ] Create migration branch
- [ ] Remove old component
- [ ] Run full test suite
- [ ] Manual QA pass
- [ ] Deploy to staging
- [ ] Staging validation
- [ ] Deploy to production
- [ ] Monitor for 48 hours
- [ ] Close migration ticket

**Dependencies:** Story 5.3 (successful A/B test)

**Story Points:** 5

---

### Story 5.5: Documentation Updates

**As a** developer
**I want** comprehensive documentation for the new form
**So that** future changes are easier

**Deliverables:**
- [ ] Component API documentation
- [ ] Composable documentation
- [ ] User guide updates
- [ ] Accessibility documentation
- [ ] Testing documentation
- [ ] Analytics documentation
- [ ] Deployment guide
- [ ] Troubleshooting guide

**Documentation Locations:**
```
/docs/
  ├── components/
  │   ├── SecretForm.md
  │   ├── InlineControls.md
  │   ├── AdvancedOptionsPanel.md
  │   └── SuccessState.md
  ├── composables/
  │   ├── useSecretFormV2.md
  │   └── useKeyboardShortcuts.md
  ├── accessibility.md
  └── analytics.md
```

**Dependencies:** Story 5.4

**Story Points:** 5

---

## Non-Functional Requirements

### NFR-1: Performance

**Requirements:**
- [ ] First Contentful Paint < 1.5s
- [ ] Largest Contentful Paint < 2.5s
- [ ] Time to Interactive < 3s
- [ ] Form submission < 500ms (excluding network)
- [ ] Bundle size increase < 50KB (gzipped)
- [ ] No layout shifts (CLS = 0)
- [ ] Smooth 60fps animations

**Testing:**
- Lighthouse CI in pipeline
- Bundle size monitoring
- Real User Monitoring (RUM)

**Story Points:** N/A (ongoing validation)

---

### NFR-2: Accessibility

**Requirements:**
- [ ] WCAG 2.1 Level AA compliance (100%)
- [ ] Keyboard navigation complete
- [ ] Screen reader tested (NVDA, JAWS, VoiceOver)
- [ ] Focus indicators visible (3:1 contrast)
- [ ] Color contrast 4.5:1 (text), 3:1 (UI)
- [ ] Touch targets 44x44px minimum
- [ ] No keyboard traps
- [ ] Semantic HTML
- [ ] ARIA attributes correct
- [ ] Error messages clear and actionable

**Testing:**
- Automated: axe, Lighthouse
- Manual: Keyboard navigation
- Manual: Screen reader testing
- Manual: Contrast checker

**Story Points:** N/A (built into each story)

---

### NFR-3: Browser Support

**Supported Browsers:**
- [ ] Chrome 90+ (desktop & mobile)
- [ ] Firefox 88+ (desktop & mobile)
- [ ] Safari 14+ (desktop & iOS)
- [ ] Edge 90+
- [ ] Samsung Internet 14+

**Not Supported:**
- IE11 (deprecated)
- Opera Mini

**Progressive Enhancement:**
- Clipboard API with fallback
- Backdrop blur with fallback
- CSS Grid with flexbox fallback

**Story Points:** N/A (testing requirement)

---

### NFR-4: Security

**Requirements:**
- [ ] CSRF protection maintained (Altcha)
- [ ] XSS prevention (sanitize inputs)
- [ ] Content Security Policy compliant
- [ ] No sensitive data in console logs
- [ ] No sensitive data in error messages
- [ ] Rate limiting respected
- [ ] HTTPS enforced
- [ ] Secure clipboard access only

**Testing:**
- Security audit before launch
- Penetration testing
- OWASP Top 10 check

**Story Points:** N/A (security validation)

---

### NFR-5: Testing Coverage

**Requirements:**
- [ ] Unit test coverage > 80%
- [ ] Component tests for all components
- [ ] Integration tests for form flow
- [ ] E2E tests for critical paths
- [ ] Visual regression tests
- [ ] Accessibility tests (automated)
- [ ] Mobile device testing
- [ ] Cross-browser testing

**Test Scenarios:**
1. Happy path (create secret, copy link)
2. With passphrase
3. With advanced options
4. Error scenarios
5. Mobile flow
6. Keyboard-only flow
7. Screen reader flow
8. Dark mode

**Story Points:** N/A (part of each story)

---

## Definition of Done

A story is "Done" when:

- [ ] Code complete and peer-reviewed
- [ ] Unit tests written and passing
- [ ] Integration tests passing (if applicable)
- [ ] Accessibility tested (keyboard + screen reader)
- [ ] Mobile tested (iOS Safari + Android Chrome)
- [ ] Dark mode tested
- [ ] Design reviewed and approved
- [ ] Documentation updated
- [ ] Merged to main branch
- [ ] Deployed to staging
- [ ] QA verified on staging
- [ ] Product owner accepted

---

## Story Dependencies Chart

```
Phase 1: Foundation
1.1 → 1.2, 1.3, 1.4
1.4 → 1.5
All 1.x → 1.6

Phase 2: Inline Controls
1.1 → 2.1
2.1 → 2.2, 2.3, 2.5
2.3 → 2.4
All 2.x → 2.6

Phase 3: Advanced Options
2.5 → 3.1
3.1 → 3.2, 3.3, 3.4, 3.6
All 3.x → 3.5

Phase 4: Success & Polish
1.4 → 4.1
4.1 → 4.2, 4.3
1.4 → 4.4, 4.5
All 1-4 → 4.6, 4.7

Phase 5: Migration
All 1-4 → 5.1
5.1 → 5.2
5.1, 5.2 → 5.3
5.3 → 5.4
5.4 → 5.5
```

---

## Priority & Risk Assessment

### High Priority (Must Have)
- All Phase 1 stories (foundation)
- Story 2.1, 2.2 (inline controls core)
- Story 4.1, 4.2 (success state)
- Story 4.5 (error handling)
- NFR-2 (accessibility)

### Medium Priority (Should Have)
- Story 2.3, 2.4 (passphrase)
- All Phase 3 stories (advanced options)
- Story 4.4, 4.6 (polish)
- Story 5.1, 5.2 (feature flag, analytics)

### Low Priority (Nice to Have)
- Story 4.7 (dark mode - already exists)
- Story 5.3 (A/B test - can do manually)

### High Risk Areas
- **Story 3.6** (Focus management) - Complex accessibility concern
- **Story 4.5** (Error handling) - Many edge cases
- **Story 5.3** (A/B test) - Needs analytics setup
- **NFR-1** (Performance) - Bundle size concerns

### Mitigation Strategies
- Early prototyping of focus management
- Comprehensive error scenario testing
- Performance budgets in CI/CD
- Regular accessibility audits

---

## Estimation Summary

| Phase | Stories | Total Points | Duration |
|-------|---------|--------------|----------|
| Phase 1 | 6 | 27 | 1 week |
| Phase 2 | 6 | 31 | 1 week |
| Phase 3 | 6 | 27 | 1 week |
| Phase 4 | 7 | 29 | 1 week |
| Phase 5 | 5 | 31 | 1 week |
| **Total** | **30** | **145** | **5 weeks** |

**Team Velocity Assumption:** 25-30 points per week (2 developers)

---

## Success Criteria

### User Success Metrics
- [ ] Time to first secret reduced by 60% (from ~12s to <5s)
- [ ] Mobile completion rate increased by 35% (from ~50% to >80%)
- [ ] Options discovery increased by 40% (from ~30% to >60%)
- [ ] User satisfaction score > 4.5/5.0

### Technical Success Metrics
- [ ] WCAG 2.1 AA compliance 100%
- [ ] Bundle size increase < 50KB gzipped
- [ ] Test coverage > 80%
- [ ] Zero critical bugs in production
- [ ] Performance budgets met

### Business Success Metrics
- [ ] Reduced support tickets by 40%
- [ ] Increased repeat usage by 30%
- [ ] Improved conversion rate (free to paid) by 15%
- [ ] Positive user feedback (NPS increase)

---

## Appendix

### Glossary

- **TTL**: Time To Live - How long before the secret expires
- **Burn after reading**: Delete secret after first view
- **Passphrase**: Additional password to access secret
- **Inline controls**: Settings bar below textarea
- **Advanced options**: Modal panel with additional features
- **Feature flag**: Toggle to enable/disable feature

### References

- [Design Mockups](./mockups/secret-form-v2-mockup.html)
- [Phase 5 Recommendation](./phase-5-recommendation.md)
- [WCAG 2.1 Guidelines](https://www.w3.org/WAI/WCAG21/quickref/)
- [Tailwind CSS Docs](https://tailwindcss.com/docs)
- [Vue 3 Composition API](https://vuejs.org/guide/extras/composition-api-faq.html)

---

**Document Version:** 1.0
**Last Updated:** 2025-01-XX
**Author:** Design & Engineering Team
**Reviewers:** Product, Design, Engineering, QA
