# Express Lane Mockups

Static HTML mockups demonstrating the redesigned create-secret experience for OneTimeSecret.

## Quick Start

Open `index.html` in your browser to view all mockups.

## Mockup Files

### Desktop Views

1. **[01-initial-state.html](01-initial-state.html)** - Empty textarea, auto-focused, button disabled
2. **[02-with-content.html](02-with-content.html)** - Secret entered, button enabled, options link visible
3. **[03-options-expanded.html](03-options-expanded.html)** - Passphrase field + expiration chips (progressive disclosure)
4. **[04-confirmation.html](04-confirmation.html)** - Success screen with link display, copy button
5. **[05-generate-password.html](05-generate-password.html)** - Alternate flow for password generation

### Mobile Views (375px)

6. **[06-mobile-initial.html](06-mobile-initial.html)** - Touch-optimized, sticky button
7. **[07-mobile-options.html](07-mobile-options.html)** - 2-column expiration chips, 48px tap targets
8. **[08-mobile-confirmation.html](08-mobile-confirmation.html)** - Stacked buttons, one-tap copy

### Interactive Demo

9. **[interactive-demo.html](interactive-demo.html)** ⭐ **Start here!**
   - Full flow with JavaScript state management
   - All states: empty → filled → options → confirmation
   - Real-time interactions (no API calls)
   - Copy to clipboard, button animations
   - Best way to experience the redesign

## Key Features Demonstrated

✅ **Progressive Disclosure** - Options hidden by default, shown on demand
✅ **Button Chips** - Touch-friendly expiration selection (no dropdowns)
✅ **Inline Confirmation** - No page redirect, stays in context
✅ **Mobile-First** - 48px tap targets, sticky button, 2-column layout
✅ **Conversational Copy** - "Your secret link is ready!" vs "Secret created"
✅ **Auto-Focus** - Textarea focused on load (keyboard-first)
✅ **Copy to Clipboard** - One-click copy with "Copied!" feedback
✅ **Trust Indicators** - HTTPS badge, encryption note, self-destruct reminder

## Design Decisions

### Why Progressive Disclosure?
- **80/20 rule:** Most users want defaults, 20% want configuration
- Reduces cognitive load from 4+ decisions to 1 primary action
- Options still accessible—just not forced upfront

### Why Button Chips Instead of Dropdowns?
- **Mobile-first:** Dropdowns are hard to tap (small arrows, 11 options)
- Button chips: Large 48px tap targets, grid layout
- Visual feedback: Selected chip has blue background + checkmark

### Why Inline Confirmation?
- **Faster perceived performance:** No page load, instant transition
- Stays in context: User doesn't lose their place
- Clear success state: Large checkmark, obvious link display

### Why Auto-Focus Textarea?
- **Keyboard-first:** Users can paste immediately (saves 1 click)
- Desktop users often have secret in clipboard already
- Mobile: Soft keyboard opens automatically (ready to paste)

## Tech Stack

- **Tailwind CSS** (via CDN for mockups, real implementation uses Tailwind 4.1)
- **Vanilla JavaScript** (state management, no framework needed for mockups)
- **Semantic HTML5** (proper labels, ARIA attributes, accessibility)
- **Responsive Design** (mobile 375px, desktop max-width 640px)

## Design Notes in Each Mockup

Every mockup file includes:
- 📋 **State label** at top (e.g., "State: Initial (Empty)")
- 🎯 **Design notes** (yellow box) explaining decisions
- ♿ **Accessibility notes** (green box) for keyboard nav, screen readers
- 📊 **Performance notes** (blue box) comparing to current implementation

## Expected Improvements

| Metric | Current | Target | Improvement |
|--------|---------|--------|-------------|
| Time-to-first-link | ~30s | <10s | **70% ↓** |
| Required clicks | 6+ | 2-3 | **50% ↓** |
| First-time success | ~70% | >90% | **20% ↑** |
| Mobile completion | Lower | = Desktop | **Parity** |

## Viewing Tips

### Desktop
- Open in Chrome/Firefox/Safari at full window width
- Use keyboard navigation (Tab, Enter) to test accessibility
- Try copy-to-clipboard functionality

### Mobile
- View mobile mockups (06-08) on actual mobile device, or
- Use browser DevTools responsive mode (375px width)
- Test touch interactions (tap targets, sticky button)

### Interactive Demo
- Click **"Fill Sample Secret"** to populate textarea
- Click **"Toggle Options"** to expand/collapse options panel
- Click **"Reset Demo"** to start over
- Complete full flow: fill → options → create → copy → reset

## Related Documentation

- [PHASE1_CRITICAL_ANALYSIS.md](../PHASE1_CRITICAL_ANALYSIS.md) - Current implementation analysis
- [PHASE2_PROBLEM_DEFINITION.md](../PHASE2_PROBLEM_DEFINITION.md) - User scenarios (Alex, Jamie, Morgan, Priya)
- [PHASE3_INTERACTION_MODELS.md](../PHASE3_INTERACTION_MODELS.md) - 3 approaches evaluated
- [PHASE4_DESIGN_SPECIFICATION.md](../PHASE4_DESIGN_SPECIFICATION.md) - Complete design specs
- [PHASE5_IMPLEMENTATION_ROADMAP.md](../PHASE5_IMPLEMENTATION_ROADMAP.md) - 11-week implementation plan
- [REDESIGN_SUMMARY.md](../REDESIGN_SUMMARY.md) - Executive summary

## Feedback & Iteration

These mockups are **static prototypes** for design validation. Next steps:

1. ✅ **Stakeholder review** - Share with team, gather feedback
2. ✅ **User testing** - Test with 5-10 people (all personas)
3. ✅ **Design mockups** - Create high-fidelity Figma designs
4. ✅ **Implementation** - Follow Phase 5 roadmap (11 weeks)

## Questions?

See [REDESIGN_SUMMARY.md](../REDESIGN_SUMMARY.md) for full project overview.

---

**Branch:** `claude/redesign-create-secret-01NMwwtwStNJzgN7t7vReXY7`
**Status:** Ready for stakeholder review
**Date:** 2025-11-18
