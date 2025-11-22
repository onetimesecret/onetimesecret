# OneTimeSecret - Create Secret UX Redesign Mockups

**Design Approach:** Adaptive Progressive UX
**Last Updated:** 2025-11-19

---

## 📁 Mockup Files

### Desktop States

1. **`01-landing-state.html`** - Initial page load
   - Clean, focused landing state
   - Single input field (100px height)
   - ~70% whitespace, minimal chrome
   - Trust signals below fold
   - No visible configuration options

2. **`02-typing-state.html`** - After user starts typing
   - Input expanded to 140px
   - Character counter appears (bottom-right)
   - **Smart suggestion panel** (API key detected)
   - Options disclosure button appears (collapsed)
   - Primary CTA appears ("Create Secret Link")
   - Keyboard hint shown (⌘ + Enter)

3. **`03-options-expanded.html`** - User clicks "Options"
   - Disclosure panel expands smoothly
   - Passphrase field with visibility toggle
   - **TTL button group** (1 hour / 1 day / 7 days) - NOT dropdown
   - Custom duration dropdown (fallback)
   - Email recipient field (for authenticated users)
   - Visual separators between sections

4. **`04-success-state.html`** - Secret created successfully
   - Celebration icon (green checkmark)
   - Link auto-selected and auto-copied
   - Security details displayed (encryption, views, expiration)
   - Sharing options (Email, Message, Share)
   - Metadata link shown separately (with explanation)
   - "Share Another Secret" CTA

### Mobile States

5. **`05-mobile-states.html`** - Mobile responsive design
   - Three phone mockups side-by-side:
     - **Landing:** Compact, single-column, minimal
     - **Typing:** Smart suggestion condensed, sticky button
     - **Options:** Stacked vertically, large touch targets (44px min)
   - Design principles annotated:
     - Touch target sizing
     - Sticky actions (fixed bottom button)
     - Progressive disclosure
     - Input optimization

### Interactive Demo

6. **`06-interactive-demo.html`** - Fully interactive prototype
   - **Live typing simulation** - Watch progressive disclosure
   - **Keyboard shortcuts:**
     - Type in textarea to trigger state changes
     - `Cmd/Ctrl + Enter` to "submit"
     - `Escape` to reset
   - **Control buttons:**
     - Reset demo
     - Simulate typing (auto-fills API key)
     - Toggle options panel
     - Apply suggestion
   - **Smart detection:** Detects `sk_` or `pk_` prefixes for API keys
   - **Smooth animations:** All transitions match production specs (300ms ease-out)

---

## 🚀 How to Use

### Viewing Mockups

1. **Open in browser** - All files are standalone HTML with Tailwind CSS via CDN
   ```bash
   # From project root
   open mockups/01-landing-state.html

   # Or navigate to directory
   cd mockups/
   open 06-interactive-demo.html
   ```

2. **Use a local server** (optional, for better experience)
   ```bash
   # Python 3
   cd mockups/
   python3 -m http.server 8080

   # Open http://localhost:8080 in browser
   ```

### Best Viewing Order

For stakeholder presentations:

1. **Start with `06-interactive-demo.html`** - Show the full experience
   - Click "Simulate Typing" to demonstrate progressive disclosure
   - Toggle options to show expansion
   - Explain keyboard shortcuts

2. **Then show desktop states** (01-04) - Explain each stage
   - Landing: Simplicity and focus
   - Typing: Smart suggestions and progressive reveal
   - Options: Full configurability without overwhelming
   - Success: Clear next steps and security transparency

3. **Finally show `05-mobile-states.html`** - Mobile considerations
   - Point out sticky actions
   - Discuss touch target sizing
   - Show condensed smart suggestions

---

## 🎨 Design System Reference

### Colors

**Brand Colors (from `tailwind.config.ts`):**
```
brand-500: #dc4a22  (Primary orange)
brand-600: #c43d1b  (Hover state)
brand-700: #a32d12  (Pressed state)
```

**Semantic Colors:**
- Success: `green-600` (#059669)
- Info: `blue-600` (#2563eb)
- Warning: `amber-500` (#f59e0b)
- Error: `red-600` (#dc2626)
- Neutral: `gray-*` scale

### Typography

- **Headings:** Default sans-serif (system font stack)
- **Body:** Default sans-serif
- **Brand font:** Zilla Slab (serif) - used for logo/headings in production
- **Code/Monospace:** Default monospace (for secret content)

### Spacing

- **Container max-width:** `max-w-2xl` (672px)
- **Card padding:** `p-8` (32px)
- **Vertical rhythm:** `space-y-6` (24px between sections)
- **Button padding:** `px-6 py-4` (24px x 16px)

### Border Radius

- **Inputs:** `rounded-lg` (8px)
- **Buttons:** `rounded-lg` (8px)
- **Cards:** `rounded-2xl` (16px)
- **Pills:** `rounded-full`

### Shadows

- **Card elevation:** `shadow-lg` (0 10px 15px -3px rgba(0,0,0,0.1))
- **Button active:** `shadow-md` (0 4px 6px -1px rgba(0,0,0,0.1))

---

## 🔍 Key Design Decisions

### 1. Progressive Disclosure

**Problem:** Current form shows all options upfront (passphrase + TTL), causing decision fatigue
**Solution:** Hide options until user starts typing
**Evidence:** Phase 2 research shows 29% abandon due to form intimidation

**Implementation in mockups:**
- Landing: Just textarea + secondary link
- After typing: Options button appears (collapsed)
- Expanded: Full options panel with clear organization

### 2. Smart Suggestions

**Problem:** Users don't know appropriate TTL for different secret types
**Solution:** Detect content type (API key, SSH key, etc.) and suggest settings
**Evidence:** Daria needs 1 hour 90% of time, but default is 7 days

**Implementation in mockups:**
- Blue info panel appears when `sk_` or `pk_` detected
- Suggests: "Shorter expiration + passphrase"
- One-click "Apply settings" button
- Dismissible (not blocking)

### 3. Button Group vs Dropdown (TTL)

**Problem:** Dropdown requires 2 clicks (open + select), hard to tap on mobile
**Solution:** Button group for common options (1h / 1d / 7d), dropdown for custom
**Evidence:** Phase 3 research - dropdowns are mobile anti-pattern

**Implementation in mockups:**
- 3 large buttons (44px height on mobile) for quick selection
- Visually selected (brand-500 background)
- Custom dropdown as fallback (below buttons)

### 4. Sticky Actions (Mobile)

**Problem:** Keyboard covers submit button on mobile (50% of screen)
**Solution:** Fixed-bottom button with white border-top
**Evidence:** Phase 2 shows mobile users abandon when button is hidden

**Implementation in mockups:**
- Mobile states show `fixed bottom-0` button
- Always visible, even when keyboard is up
- 56px height (thumb-friendly)

### 5. Auto-Copy on Success

**Problem:** Users forget to copy link, or don't know which link to copy
**Solution:** Auto-select and auto-copy secret link on page load
**Evidence:** Reduces post-creation confusion (Phase 2: 11% don't successfully share)

**Implementation in mockups:**
- Success state shows link pre-selected
- Green confirmation: "✓ Link automatically copied to clipboard"
- Copy button still visible for manual re-copy

---

## 📊 Metrics to Measure

When implementing these designs, track:

### Primary Metrics

| Metric | Current | Target | Where to Track |
|--------|---------|--------|----------------|
| **Conversion Rate** | 45% | 65-70% | GA4 funnel: page load → secret created |
| **Time to First Create** | 25-35s | 12-18s | Custom event timing |
| **Mobile Completion** | ~30% | 50%+ | Device segmentation in analytics |

### Secondary Metrics

- **Options Discovery:** % of users who click "Options" (target: 40%+)
- **Passphrase Usage:** % of secrets with passphrase (target: 25%+)
- **Smart Suggestion Acceptance:** % who click "Apply settings" (target: 50%+)
- **TTL Distribution:** Shift from 100% default to varied distribution

### Qualitative

- User testing: "I knew exactly what to do" (>80% agreement)
- Support tickets about form confusion (<5/month, down from ~20)
- Positive sentiment in feedback (>70%)

---

## 🛠️ Implementation Notes

### Technologies Used in Mockups

- **Tailwind CSS 3.4** (CDN) - Matches project version
- **Vanilla JavaScript** - For interactive demo
- **SVG icons** - Inline for simplicity (production uses icon library)
- **No build step** - Pure HTML for easy sharing

### Differences from Production

These are **high-fidelity mockups**, not pixel-perfect:

1. **Fonts:** Uses system fonts (production uses Zilla Slab for brand)
2. **Icons:** Generic SVG paths (production may use custom icon set)
3. **Animations:** Simplified CSS (production uses Vue transitions)
4. **Dark mode:** Not shown (but spec'd in Phase 3 research)
5. **i18n:** English only (production supports multiple languages)

### Ready for Development?

Yes! These mockups provide:

✅ Exact spacing, colors, and sizing
✅ Transition durations and easing
✅ Interactive behavior logic
✅ Mobile responsive breakpoints
✅ Accessibility patterns (ARIA, keyboard)

**Next steps:**
1. Convert HTML mockups to Vue 3 components
2. Implement composables (useContentDetection, useProgressiveDisclosure)
3. Connect to existing API (no backend changes needed)
4. Add unit tests for state transitions
5. Conduct accessibility audit (axe-core, screen readers)
6. A/B test against current form

---

## 📝 Design Annotations

### Annotation Boxes

Each mockup includes a **fixed annotation box** (bottom-right) with design notes:
- Key decisions
- Measurements
- State changes
- Accessibility considerations

**To hide annotations** (for cleaner screenshots):
- Open browser DevTools
- Run: `document.querySelector('.fixed.bottom-4').style.display = 'none'`

### State Indicators

Each mockup has a **blue pill badge** showing which state it represents:
- "Mockup: Landing State"
- "Mockup: After Typing State"
- etc.

**To hide state badges**:
- Run: `document.querySelector('.inline-block.px-3').style.display = 'none'`

---

## 🎯 Decision Points for Stakeholders

Before implementation, align on:

### 1. Smart Suggestion Scope
**Question:** Which secret types should we detect?
**Options:**
- **Minimal:** Just API keys (`sk_`, `pk_`)
- **Medium:** + SSH keys (`-----BEGIN`)
- **Full:** + URLs, email/password pairs, JSON/XML

**Recommendation:** Start with Minimal, expand based on usage data

### 2. Anonymous vs Authenticated UI
**Question:** Should we promote sign-up more aggressively?
**Current mockups:** Email field only shown to authenticated users
**Alternative:** Show email field to anonymous, prompt to sign in when they type

**Recommendation:** Keep current approach (don't interrupt anonymous flow)

### 3. Mobile-First vs Desktop-First Development
**Question:** Which platform to optimize first?
**Stats:** 83% desktop, 17% mobile - BUT mobile has highest abandonment
**Options:**
- **Desktop-first:** Serve majority, optimize mobile later
- **Mobile-first:** Fix highest pain point, desktop is easier

**Recommendation:** Mobile-first (bigger impact on conversion)

### 4. A/B Test Strategy
**Question:** How to roll out?
**Options:**
- **Big bang:** Replace old form entirely
- **A/B test:** 50/50 split for 2 weeks
- **Gradual:** Paid users first, then free

**Recommendation:** A/B test with 50/50 split, measure for 2 weeks

---

## 📞 Questions?

**For design questions:** Review Phase 1-5 research documents
**For technical questions:** See `src/components/secrets/form/` in codebase
**For accessibility:** See Phase 3 > Pattern 11-13 (WCAG 2.1 compliance)

---

**Ready to implement?** Start with the interactive demo to understand the full user journey, then break down into component development sprints.
