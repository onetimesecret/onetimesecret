# OneTimeSecret Create Secret UX Prototype

## Overview

This is a static, interactive prototype demonstrating the **"Progressive Minimalism"** approach for the redesigned OneTimeSecret create secret experience.

**File:** `prototype-create-secret.html`

## How to View

### Option 1: Direct Browser Open
```bash
# Open in your default browser
open prototype-create-secret.html

# Or on Linux
xdg-open prototype-create-secret.html

# Or simply double-click the file
```

### Option 2: Local Server (Recommended for testing)
```bash
# Python 3
python3 -m http.server 8080

# Then visit: http://localhost:8080/prototype-create-secret.html
```

## Key Features Demonstrated

### 1. **Minimal Landing State**
- Single textarea dominates the viewport
- Submit button appears (disabled until content entered)
- "More options" collapsed by default
- Clear metadata line showing smart defaults

### 2. **Progressive Disclosure**
- Click "More options" to reveal:
  - Passphrase input with generator
  - TTL selector (expiration time)
  - Recipient email field
- Smooth animation on expand/collapse
- Proper ARIA attributes for accessibility

### 3. **Character Counter**
- Hidden until >50% of limit (5,000 chars)
- Color-coded feedback:
  - Gray: 0-8,000 chars
  - Amber: 8,000-9,500 chars
  - Red: 9,500-10,000 chars
- Updates in real-time

### 4. **Keyboard Shortcuts**
All features accessible via keyboard:

| Shortcut | Action |
|----------|--------|
| `⌘/Ctrl + Enter` | Submit form |
| `⌘/Ctrl + O` | Toggle options panel |
| `⌘/Ctrl + P` | Focus passphrase (auto-expands options) |
| `⌘/Ctrl + T` | Focus TTL selector (auto-expands options) |
| `?` | Show keyboard shortcuts help |
| `Escape` | Close modals |

### 5. **Success State**
- Smooth transition from form to success card
- Auto-copy link to clipboard
- Share actions (Email, Share, QR Code)
- Secret details summary
- "Create Another" action

### 6. **Accessibility Features**
- **Semantic HTML:** Proper `<form>`, `<label>`, `<input>` structure
- **ARIA Attributes:**
  - `aria-expanded` on disclosure buttons
  - `aria-controls` linking buttons to panels
  - `aria-live` for dynamic announcements
  - `aria-invalid` for validation states
- **Keyboard Navigation:** Full keyboard support, logical tab order
- **Focus Management:** Clear focus indicators, focus moves to revealed content
- **Screen Reader Support:** Hidden helper text, status announcements

### 7. **Dark Mode**
- Toggle via button in header
- Respects `prefers-color-scheme` (can be extended)
- All colors maintain WCAG AA contrast ratios

### 8. **Mobile Optimization**
- Responsive layout (mobile-first)
- 16px base font size (prevents iOS zoom)
- Touch-friendly targets (minimum 44px)
- Auto-resize textarea
- Mobile view simulation (via prototype controls)

## Prototype Testing Controls

Yellow banner at top provides testing utilities:

1. **Reset Form** - Clear all inputs and return to initial state
2. **Fill Sample Content** - Populate with example API keys
3. **Show Success State** - Jump to success screen
4. **Toggle Mobile View** - Simulate mobile viewport (375px)

## What This Prototype Shows

### User Flow 1: Basic User (Zero Config)
```
1. Land on page
2. Paste secret in textarea
3. Press ⌘⏎ or click "Create Secret"
4. See success screen with link
5. Link auto-copied to clipboard
```

**Time to complete:** ~5 seconds

### User Flow 2: Security-Conscious User
```
1. Land on page
2. Paste secret in textarea
3. Click "More options" or press ⌘O
4. Add passphrase (or click "Generate")
5. Press ⌘⏎ to submit
6. Success screen confirms passphrase required
```

**Time to complete:** ~10 seconds

### User Flow 3: Email Sender
```
1. Land on page
2. Type secret
3. Click "More options"
4. Enter recipient email
5. Adjust TTL if needed
6. Submit
7. Success confirms email sent
```

**Time to complete:** ~15 seconds

## Technical Implementation Notes

### Auto-Resize Textarea
```javascript
textarea.addEventListener('input', function() {
  this.style.height = 'auto';
  this.style.height = this.scrollHeight + 'px';
});
```

### Progressive Disclosure Animation
- CSS transitions for smooth expand/collapse
- `max-height` animated from 0 to 500px
- Opacity fades in/out
- Icon rotates 180deg on expand

### Character Counter Logic
```javascript
const progress = length / maxLength;

// Show when >50% or focused
if (progress > 0.5 || isFocused) {
  charCounter.style.opacity = '1';
}

// Color code based on thresholds
if (progress > 0.95) return 'red'
if (progress > 0.80) return 'amber'
return 'gray'
```

## Comparison with Current Implementation

| Aspect | Current | Prototype |
|--------|---------|-----------|
| **Fields visible on landing** | 4 (content, passphrase, TTL, recipient*) | 1 (content only) |
| **Textarea height** | Fixed 200px | Auto-resize (200-400px) |
| **Character counter** | Always visible | Contextual (>50% or focused) |
| **Keyboard shortcuts** | None | 5+ shortcuts |
| **Submit button state** | Always enabled | Disabled until content |
| **Success state** | Navigate to new page | In-page transition |
| **Mobile optimization** | Desktop-first | Mobile-first |
| **Accessibility** | Basic | WCAG 2.1 AA |

## Design Specifications Used

### Colors
- **Primary:** `#2563eb` (Blue 600)
- **Success:** `#16a34a` (Green 600)
- **Warning:** `#f59e0b` (Amber 500)
- **Danger:** `#dc2626` (Red 600)

### Spacing
- **Base unit:** 16px (1rem)
- **Container padding:** 24px (sm) → 32px (lg)
- **Element gaps:** 12px (3) standard

### Typography
- **Base font size:** 16px (mobile-safe)
- **Headings:** 24px (2xl) for h2
- **Small text:** 14px (sm) for metadata

### Breakpoints
- **Mobile:** < 640px
- **Tablet:** 640px - 1024px
- **Desktop:** > 1024px

## Testing Checklist

### Functional Testing
- [ ] Form submission works
- [ ] Options panel expands/collapses
- [ ] Character counter shows/hides correctly
- [ ] Color coding updates at thresholds
- [ ] Passphrase visibility toggle works
- [ ] Passphrase generator creates passwords
- [ ] Success state displays correctly
- [ ] Copy to clipboard works
- [ ] Reset returns to initial state

### Keyboard Testing
- [ ] All keyboard shortcuts work
- [ ] Tab navigation follows logical order
- [ ] Focus indicators visible
- [ ] Enter key submits when content present
- [ ] Escape closes modals

### Accessibility Testing
- [ ] Screen reader announces form fields
- [ ] ARIA attributes correctly set
- [ ] Color contrast meets WCAG AA (4.5:1 text, 3:1 UI)
- [ ] Focus management works (revealed content receives focus)
- [ ] Status messages announced (success, errors)

### Responsive Testing
- [ ] Layout adapts to mobile (< 640px)
- [ ] Touch targets meet 44px minimum
- [ ] Text remains readable at all sizes
- [ ] No horizontal scrolling on mobile
- [ ] Buttons stack on small screens

### Browser Testing
- [ ] Chrome/Edge (Chromium)
- [ ] Firefox
- [ ] Safari (iOS/macOS)
- [ ] Mobile browsers (Safari iOS, Chrome Android)

## Known Limitations (Prototype Only)

1. **No real API calls** - Form submission is simulated
2. **Static share link** - Always shows same dummy URL
3. **No validation** - Doesn't validate email format, etc.
4. **No error states** - Success path only
5. **Single page** - Receipt page not included
6. **No authentication** - Doesn't show logged-in state

## Next Steps

After prototype review and feedback:

1. **User Testing** - Show to 5-10 real users
2. **Accessibility Audit** - Test with screen readers (NVDA, JAWS, VoiceOver)
3. **Mobile Device Testing** - Test on actual devices (iOS, Android)
4. **Stakeholder Review** - Gather feedback on approach
5. **Iterate Design** - Refine based on feedback
6. **Implementation Planning** - Break down into Vue components

## Files Created

```
onetimesecret/
├── prototype-create-secret.html   (Static prototype)
└── PROTOTYPE-README.md            (This file)
```

## Questions & Feedback

When reviewing this prototype, consider:

1. **Does this feel simpler than the current form?**
2. **Is the progressive disclosure pattern intuitive?**
3. **Do the keyboard shortcuts add value or complexity?**
4. **Is the success state clear and actionable?**
5. **Does this work well on your mobile device?**
6. **Are there any accessibility concerns?**
7. **What's missing or confusing?**

---

**Created:** 2025-11-18
**Design Approach:** Progressive Minimalism
**Status:** Ready for Review
