# OneTimeSecret - Design Mockups

**Progressive Simplicity Approach** - Redesigned Create Secret Experience

## 📋 Overview

This directory contains static HTML mockups demonstrating the recommended redesign for the OneTimeSecret create secret flow. These mockups are based on comprehensive research and design work completed across 5 phases:

- **Phase 1**: Discovery & Vision
- **Phase 2**: User Engagement Study (5 personas)
- **Phase 3**: Modern Best Practices Research
- **Phase 4**: Design Exploration (3 approaches)
- **Phase 5**: Final Recommendation

## 🎯 Design Approach

**Progressive Simplicity** - The recommended approach that balances simplicity for beginners with power for experts.

### Core Principles

1. **Simple First, Powerful Always** - Primary path feels like magic, advanced options always discoverable
2. **Mobile-Native, Desktop-Enhanced** - Thumb-reachable targets, single-column flow, desktop adds breathing room
3. **Security Through Education** - Guide users to secure choices without enforcement
4. **Accessible by Default** - WCAG 2.2 AA compliance in every interaction

## 📱 Mockup Gallery

### How to View

**Option 1: Open the Gallery**
```bash
# Open index.html in your browser
open design-mockups/index.html
```

**Option 2: View Individual Mockups**
Navigate to any of the HTML files below directly in your browser.

### Mobile Mockups (375px viewport)

1. **[01-mobile-initial.html](01-mobile-initial.html)**
   - Empty state with collapsed security options
   - Disabled submit button
   - Trust badges and minimal UI
   - **Key Feature**: Clean, uncluttered initial view

2. **[02-mobile-expanded.html](02-mobile-expanded.html)**
   - Security options accordion expanded
   - Passphrase, TTL, and notification fields visible
   - Active submit button with content
   - **Key Feature**: Progressive disclosure in action

3. **[03-mobile-suggestion.html](03-mobile-suggestion.html)**
   - Content-aware AI suggestion banner
   - Detects password-like content
   - Recommends security options
   - **Key Feature**: Smart contextual guidance

4. **[06-error-state.html](06-error-state.html)**
   - Validation errors displayed
   - Sticky error banner at top
   - Inline errors adjacent to fields
   - **Key Feature**: WCAG-compliant error handling

5. **[07-success-receipt.html](07-success-receipt.html)**
   - Secret created successfully
   - Copy link functionality
   - Sharing instructions
   - Secret metadata and quick actions
   - **Key Feature**: Complete success flow

### Desktop Mockups (1024px+ viewport)

6. **[04-desktop-initial.html](04-desktop-initial.html)**
   - Gradient hero section
   - Expanded layout with breathing room
   - Keyboard shortcuts hint
   - "How it Works" expandable footer
   - **Key Feature**: Desktop-enhanced experience

7. **[05-desktop-expanded.html](05-desktop-expanded.html)**
   - Two-column grid for security options
   - Passphrase strength meter
   - Info tooltips on hover
   - Side-by-side fields for efficiency
   - **Key Feature**: Power user optimization

## ✨ Key Features Demonstrated

### Progressive Disclosure
- Security options hidden by default in accordion
- Expands with clear affordance
- State persists per user preference

### Content-Aware Intelligence
- Detects password vs. text content
- Suggests appropriate security settings
- Non-intrusive banner with clear actions

### Mobile-First Design
- 48×48px minimum tap targets
- Single-column vertical flow
- Sticky submit button (always reachable)
- Optimized for one-handed use

### Inline Validation
- Errors appear adjacent to invalid fields
- Clear error messages with icons
- ARIA announcements for screen readers
- Color + icon (not color alone)

### Accessibility (WCAG 2.2 AA)
- Proper semantic HTML
- ARIA attributes for dynamic content
- Keyboard navigation support
- High contrast (4.5:1+ for text)
- Focus indicators (3px outline)

### Trust & Security Messaging
- Visual badges (encrypted, one-view, auto-delete)
- "How it Works" explainer
- Clear passphrase guidance
- Transparent security features

### Desktop Enhancements
- Two-column layouts where appropriate
- Hover tooltips with explanations
- Keyboard shortcuts (Cmd+Enter to submit)
- Expanded "How it Works" with timeline

## 🛠️ Technical Stack

- **Framework**: Static HTML (production uses Vue 3 + TypeScript)
- **CSS**: Tailwind CSS 4.1 (via CDN for mockups)
- **Responsive**: Mobile-first breakpoints (375px, 768px, 1024px)
- **Accessibility**: WCAG 2.2 AA compliant patterns
- **Icons**: Heroicons (inline SVG)

## 📊 Success Metrics

### Quantitative Goals
| Metric | Current Baseline | Target (3 months) |
|--------|------------------|-------------------|
| Form completion rate | ~65% | 80%+ |
| Mobile completion | ~50% | 75%+ (parity) |
| Time to first secret | ~30s | <20s |
| Passphrase adoption | ~20% | 35%+ |
| Accessibility score | ~85 | 100 |
| Page load (LCP) | ~1.8s | <1.2s |

### Qualitative Goals
- User feedback score 4.5+/5
- Zero critical accessibility issues
- Reduced support tickets for "How do I...?"

## 🚀 Implementation Plan

### Phase 1: Foundation (Week 1-2)
- Set up new component structure
- Implement progressive disclosure accordion
- Mobile-first responsive layout
- Update Tailwind config

### Phase 2: Intelligence & Accessibility (Week 3-4)
- Content detection logic
- WCAG 2.2 AA compliance audit
- Enhanced validation with ARIA
- Character counter improvements

### Phase 3: Polish & Performance (Week 5)
- Lazy-load accordion content
- Smooth animations
- Analytics instrumentation
- Cross-browser testing

### Phase 4: Enterprise Enhancements (Week 6+)
- Template system
- Audit trail metadata
- Advanced power user features

**Total Timeline**: 5-6 weeks to production-ready MVP

## 📁 File Structure

```
design-mockups/
├── index.html              # Gallery navigation
├── 01-mobile-initial.html  # Mobile: Empty state
├── 02-mobile-expanded.html # Mobile: Expanded options
├── 03-mobile-suggestion.html # Mobile: AI suggestion
├── 04-desktop-initial.html # Desktop: Initial view
├── 05-desktop-expanded.html # Desktop: Expanded view
├── 06-error-state.html     # Mobile: Validation errors
├── 07-success-receipt.html # Mobile: Success page
└── README.md               # This file
```

## 🎨 Design Tokens

### Colors
- **Primary**: Indigo-600 (#4f46e5)
- **Success**: Green-600 (#16a34a)
- **Error**: Red-600 (#dc2626)
- **Warning**: Amber-600 (#d97706)

### Typography
- **Headings**: Font weight 600-700
- **Body**: Font size 16px base (mobile), 14-16px (desktop)
- **Small**: Font size 12-14px

### Spacing
- **Base unit**: 4px (Tailwind default)
- **Tap targets**: 48×48px (mobile), 40×40px (desktop)
- **Form spacing**: 16-24px vertical rhythm

### Borders
- **Default**: 2px solid (focus states, important boundaries)
- **Subtle**: 1px solid (dividers)
- **Radius**: 8px (inputs), 12px (cards)

## 🔍 Next Steps

1. **Review** - Share mockups with stakeholders for feedback
2. **Refine** - Iterate based on feedback
3. **Design System** - Create high-fidelity designs in Figma (optional)
4. **Implement** - Begin Phase 1 development
5. **Test** - A/B test with 10% → 25% → 50% → 100% rollout

## 📞 Questions?

For questions or feedback about these mockups, refer to the comprehensive design documentation in the main conversation thread covering all 5 phases of research and design work.

---

**Created**: 2025-11-19
**Version**: 1.0
**Status**: Ready for review and feedback
