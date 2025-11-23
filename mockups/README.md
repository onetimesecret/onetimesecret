# OneTimeSecret Redesign - Static Mockups

This directory contains static HTML mockups for the proposed redesign of the OneTimeSecret create-secret experience. These mockups demonstrate **Model 1: Input-First Progressive** interaction design.

## 📁 Mockup Files

### Desktop Views

1. **`01-desktop-initial.html`** - Initial state (empty form)
   - Shows the landing state with tagline and empty textarea
   - Primary CTA is disabled until content is entered
   - "Customize options" link visible but not expanded
   - Demonstrates clean, focused first impression

2. **`02-desktop-customize.html`** - With customize panel expanded
   - Shows content entered in the textarea
   - Customize panel expanded revealing:
     - Expiration time selector (1 hour, 1 day, 7 days, Custom)
     - Optional passphrase field with generator button
     - Optional recipient email field
   - Primary CTA is now enabled
   - Demonstrates progressive disclosure pattern

3. **`03-desktop-success.html`** - Success state after creation
   - Shows success confirmation with checkmark
   - Secret link displayed prominently with copy button
   - Success message confirming link was copied
   - Important notes section highlighting:
     - One-time view constraint
     - Expiration time (7 days)
     - Cannot be recovered warning
   - Metadata collapsed by default (click to expand)
   - Actions: "Create Another Secret" and "View My Secrets"

### Mobile View

4. **`04-mobile.html`** - Mobile responsive layout (375px)
   - Compressed header with hamburger menu
   - Shorter textarea (4 rows vs 6 on desktop)
   - Full-width CTA button
   - Stacked info cards
   - "More options" link instead of "Customize options"
   - Optimized for one-handed mobile use

### Theme Variations

5. **`05-dark-mode.html`** - Dark theme variant
   - Shows dark mode color palette
   - Demonstrates contrast and accessibility in dark theme
   - Same layout as `02-desktop-customize.html` but with dark styling

## 🚀 How to View

### Option 1: Open Directly in Browser

Simply open any `.html` file in your web browser:

```bash
# From the mockups directory
open 01-desktop-initial.html

# Or on Linux
xdg-open 01-desktop-initial.html

# Or on Windows
start 01-desktop-initial.html
```

### Option 2: Local Web Server

For best results (especially for mobile testing), use a local web server:

```bash
# Using Python 3
python3 -m http.server 8000

# Using Node.js (if you have http-server installed)
npx http-server -p 8000

# Then open in browser:
# http://localhost:8000/01-desktop-initial.html
```

### Option 3: View All at Once

Create an index page to view all mockups:

```bash
# Open browser and navigate through files:
open http://localhost:8000/
```

## 📱 Responsive Testing

To test mobile mockups on desktop browsers:

1. **Chrome DevTools**
   - Open `04-mobile.html`
   - Press `Cmd+Option+I` (Mac) or `F12` (Windows/Linux)
   - Click the device toggle icon (or press `Cmd+Shift+M`)
   - Select "iPhone SE" or similar device

2. **Firefox Responsive Design Mode**
   - Open `04-mobile.html`
   - Press `Cmd+Option+M` (Mac) or `Ctrl+Shift+M` (Windows/Linux)
   - Select 375px width

## 🎨 Design Features Demonstrated

### Progressive Disclosure
- **01-desktop-initial.html**: Clean, minimal starting state
- **02-desktop-customize.html**: Options revealed on-demand

### Accessibility
- Proper semantic HTML (`<label>`, `<button>`, etc.)
- Keyboard-navigable focus states
- Clear visual hierarchy
- High contrast colors
- Screen reader friendly structure

### Mobile-First Responsiveness
- **04-mobile.html**: Touch-friendly targets (min 44px)
- Readable font sizes (min 14px)
- Appropriate spacing for thumbs
- Sticky/accessible primary actions

### Visual Design
- Tailwind CSS utility classes
- Modern rounded corners and shadows
- Consistent spacing scale
- Clear state changes (disabled, hover, focus)
- Professional color palette

## 🔄 User Flow Demonstrated

```
01-desktop-initial.html
  ↓ (user pastes content)

02-desktop-customize.html
  ↓ (user clicks "Create Secret Link")

03-desktop-success.html
  ↓ (link auto-copied to clipboard)

[User shares link via messenger/email]
```

## 📊 Design Specifications

### Color Palette

**Light Mode:**
- Primary: `blue-600` (#2563EB)
- Background: `gray-50` (#F9FAFB)
- Card: `white` (#FFFFFF)
- Text: `gray-900` (#111827)
- Border: `gray-200` (#E5E7EB)

**Dark Mode:**
- Primary: `blue-400` (#60A5FA)
- Background: `gray-900` (#111827)
- Card: `gray-800` (#1F2937)
- Text: `gray-100` (#F3F4F6)
- Border: `gray-700` (#374151)

### Typography
- Font: System fonts (`-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, ...`)
- Headings: `font-bold` or `font-semibold`
- Body: `text-base` (16px)
- Monospace (for secrets): `font-mono`

### Spacing
- Container: `max-w-2xl mx-auto`
- Section padding: `p-8` (2rem)
- Element gaps: `gap-4` (1rem) or `gap-2` (0.5rem)

### Interactive Elements
- Buttons: `rounded-lg` (8px border radius)
- Cards: `rounded-2xl` (16px border radius)
- Focus rings: `ring-2 ring-blue-500/20`
- Shadows: `shadow-lg`, `shadow-xl`

## 🎯 What to Look For

When reviewing these mockups, pay attention to:

1. **First Impression** (01-desktop-initial.html)
   - Is the purpose immediately clear?
   - Is the primary action obvious?
   - Does it feel trustworthy?

2. **Progressive Complexity** (02-desktop-customize.html)
   - Are advanced options easy to find?
   - Do they feel optional, not required?
   - Is the layout still clean when expanded?

3. **Success Clarity** (03-desktop-success.html)
   - Is it obvious that the operation succeeded?
   - Is the secret link immediately actionable?
   - Are the warnings clear but not alarming?

4. **Mobile Usability** (04-mobile.html)
   - Can you easily tap all interactive elements?
   - Is text readable without zooming?
   - Does the layout make sense on small screens?

5. **Accessibility** (all files)
   - Is focus visible on all interactive elements?
   - Is color contrast sufficient?
   - Are interactive elements clearly labeled?

## 📝 Implementation Notes

These are **static mockups** - they don't include:
- Form validation
- API integration
- State management
- Actual copy-to-clipboard functionality
- Route transitions

For implementation specifications, see the full design document in the project repository.

## 🔗 Related Documentation

- **Phase 1-5 Design Document**: Complete analysis and specifications
- **Component Architecture**: Proposed Vue 3 component structure
- **Migration Strategy**: Implementation plan and rollout approach

## ✅ Mockup Checklist

When presenting these mockups to stakeholders:

- [ ] All 5 mockup files open without errors
- [ ] Mobile mockup tested in responsive mode
- [ ] Dark mode mockup displays correctly
- [ ] Interactive states are visible (hover, focus, disabled)
- [ ] Text is legible at all sizes
- [ ] Layout matches design specifications
- [ ] Stakeholders understand these are static demos

---

**Created**: 2025-11-23
**Version**: 1.0
**Design Model**: Model 1 (Input-First Progressive)
**Framework**: HTML + Tailwind CSS CDN
