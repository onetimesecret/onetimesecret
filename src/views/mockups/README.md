# Create Secret Redesign - Static Mockups

This directory contains static mockups for the proposed redesign of the OneTimeSecret create secret experience, based on the **Progressive Simplicity** design approach.

## Overview

The redesign follows a comprehensive design study that analyzed:
- Current user pain points across 5 personas
- WCAG 2.1 AA accessibility standards
- Modern UX patterns (progressive disclosure, inline validation)
- Core Web Vitals optimization (INP <200ms, LCP <2.5s, CLS <0.1)
- Mobile-first responsive design

## Accessing the Mockups

**Development Server:**
```bash
npm run dev
```

Then navigate to: **http://localhost:5173/mockups/redesign**

## Mockup States

### 1. Default State
- **File:** `DefaultStateMockup.vue`
- **Shows:** Empty form on first load
- **Key Features:**
  - Textarea as hero element
  - Submit button disabled until content entered
  - Advanced options collapsed
  - Trust indicators always visible

### 2. Active State
- **File:** `ActiveStateMockup.vue`
- **Shows:** Form with content entered
- **Key Features:**
  - Character counter prominent with green status
  - Smart suggestion appears (contextual recommendation)
  - Submit button now enabled
  - Auto-save confirmation

### 3. Advanced Options Expanded
- **File:** `AdvancedExpandedMockup.vue`
- **Shows:** All advanced configuration options
- **Key Features:**
  - Passphrase field with strength meter
  - Real-time validation checklist
  - TTL visual presets (1h, 1d, 1w)
  - Custom dropdown for specific durations
  - Recipient email field (optional)

### 4. Pre-Flight Confirmation
- **File:** `PreFlightModalMockup.vue`
- **Shows:** Final review modal before submission
- **Key Features:**
  - Color-coded security summary
  - Encrypted, passphrase-protected, one-time badges
  - Important security reminders
  - "Go Back" option preserves data

### 5. Mobile View
- **File:** `MobileViewMockup.vue`
- **Shows:** Responsive mobile-optimized layout
- **Key Features:**
  - Single column layout
  - Large touch targets (48x48px)
  - Sticky header and footer
  - Compact trust indicators
  - One-handed operation friendly

## Design Principles

1. **"Textarea is the Hero"** - Everything else supports the primary action
2. **Progressive, Not Hidden** - Advanced options clearly discoverable
3. **Trust Through Transparency** - Security measures always visible
4. **Mobile is Primary** - Design for one-handed mobile use first
5. **Validate Proactively** - Show requirements upfront, validate in real-time
6. **Speed Without Sacrifice** - Fast for power users, simple for casual users

## Technical Stack

- **Framework:** Vue 3.5.13 with Composition API
- **Styling:** Tailwind CSS 3.4.17
- **Icons:** Heroicons (inline SVG)
- **Router:** Vue Router 4.5.1
- **Type Safety:** TypeScript 5.8.3

## Key Improvements Over Current Design

| Aspect | Current | Proposed |
|--------|---------|----------|
| **Cognitive Load** | All options visible | Progressive disclosure |
| **Character Counter** | Appears at 50% | Visible from first keystroke |
| **Validation** | On submit only | Real-time with debouncing |
| **Trust Indicators** | At bottom | Always visible, contextual |
| **Mobile UX** | Two-column stack | Single column, sticky buttons |
| **Passphrase** | Hidden complexity rules | Visual strength meter + checklist |
| **TTL Selection** | Dropdown only | Visual presets + dropdown |
| **Confirmation** | None | Pre-flight modal review |

## Accessibility Features

- ✅ WCAG 2.1 AA compliant
- ✅ Screen reader optimized with proper ARIA labels
- ✅ Keyboard navigation (<3 tab stops to submit)
- ✅ High contrast mode compatible
- ✅ Respects `prefers-reduced-motion`
- ✅ Focus indicators visible and clear
- ✅ Error messages associated with fields

## Performance Targets

- **LCP:** <2.5 seconds (Largest Contentful Paint)
- **INP:** <200 milliseconds (Interaction to Next Paint)
- **CLS:** <0.1 (Cumulative Layout Shift)
- **Bundle Size:** Optimized with code splitting and lazy loading

## Next Steps

1. **Stakeholder Review** - Gather feedback on design direction
2. **User Testing** - Test with 5 representative users per persona
3. **Technical Validation** - Architecture review with engineering team
4. **Accessibility Audit** - Review with accessibility specialist
5. **Implementation Planning** - Break down into phased development

## Related Documentation

- `/docs/design/create-secret-redesign-phase-1-5.md` - Full design study
- `/docs/design/progressive-simplicity-approach.md` - Design approach details
- `/docs/design/persona-research.md` - User persona analysis

## Questions or Feedback?

Contact the design team or open an issue in the repository.

---

**Status:** Static Mockups Complete ✅
**Last Updated:** 2025-11-18
**Design Phase:** Phase 5 (Recommendation) Complete
