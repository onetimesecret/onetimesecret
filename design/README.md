# Secret Form V2 Design Documentation

This directory contains comprehensive design exploration and implementation documentation for the OneTimeSecret homepage create secret experience redesign.

## 📁 Contents

### 1. **Visual Mockups** (`mockups/secret-form-v2-mockup.html`)

Interactive HTML mockup demonstrating all UI states using actual Tailwind CSS and brand colors.

**How to use:**
```bash
# Open in browser
open design/mockups/secret-form-v2-mockup.html

# Or serve locally
cd design/mockups
python -m http.server 8000
# Then visit: http://localhost:8000/secret-form-v2-mockup.html
```

**Features:**
- 7 interactive states (dropdown to switch between them)
- Dark mode toggle
- Actual brand colors from `tailwind.config.ts`
- Responsive breakpoints
- Mobile view
- Copy-paste ready HTML/CSS

**States Demonstrated:**
1. **State 1:** Initial landing (empty form)
2. **State 2:** With content (enabled submit button)
3. **State 3:** Options expanded (expiration dropdown open)
4. **State 4:** Passphrase added (with strength indicator)
5. **State 5:** Advanced panel open (modal overlay)
6. **State 6:** Success state (link created)
7. **Mobile:** Mobile view (stacked layout)

---

### 2. **User Stories** (`user-stories.md`)

Detailed implementation stories organized by 5-week development phases.

**Structure:**
- **30 user stories** across 5 phases
- Story points estimation (145 total)
- Acceptance criteria for each story
- Technical implementation notes
- Dependencies mapped
- Non-functional requirements

**How to use:**
1. Import into your project management tool (Jira, Linear, etc.)
2. Assign to sprints according to phases
3. Reference during implementation
4. Update acceptance criteria as completed
5. Track progress against Definition of Done

**Phases:**
- **Phase 1 (Week 1):** Foundation - Basic form structure
- **Phase 2 (Week 2):** Inline Controls - Smart defaults bar
- **Phase 3 (Week 3):** Advanced Options - Modal panel
- **Phase 4 (Week 4):** Success & Polish - Completion flow
- **Phase 5 (Week 5):** Migration - Feature flag, A/B test, cleanup

---

## 🎯 Quick Start for Developers

### 1. Review the Design

```bash
# View interactive mockup
open design/mockups/secret-form-v2-mockup.html

# Read recommendation
cat docs/phase-5-recommendation.md  # (if you created this separately)
```

### 2. Understand the Architecture

Key files to implement:

```
src/components/secrets/form/
├── SecretFormV2.vue              # Main orchestrator
├── SecretContentInput.vue         # Textarea with enhancements
├── InlineControls.vue            # Expiration/Passphrase bar
│   ├── ExpirationQuickSelect.vue
│   ├── PassphraseToggle.vue
│   └── MoreOptionsButton.vue
├── AdvancedOptionsPanel.vue      # Modal for advanced options
├── SubmitButton.vue              # Primary action
└── SuccessState.vue              # Post-creation UI

src/composables/
├── useSecretFormV2.ts            # Form state management
├── useInlineControls.ts          # Inline controls logic
├── useKeyboardShortcuts.ts       # Keyboard navigation
└── useFormAccessibility.ts       # ARIA management
```

### 3. Start Implementation

```bash
# Create feature branch
git checkout -b feature/secret-form-v2

# Create component directory structure
mkdir -p src/components/secrets/form/v2

# Start with Phase 1, Story 1.1
# Reference: design/user-stories.md -> Story 1.1
```

### 4. Reference During Development

**For each story:**
1. Read acceptance criteria
2. Review design mockup for that state
3. Check technical notes for implementation hints
4. Verify dependencies are complete
5. Implement with tests
6. Mark as done when all criteria met

---

## 🎨 Design Principles

The redesign follows these core principles:

1. **Paste-First Optimization** - 75% of users arrive with content ready
2. **Progressive Disclosure** - Show defaults, reveal complexity on demand
3. **Mobile Equals Desktop** - Excellent experience on all devices
4. **Transparent Defaults** - Users know what's happening before submission
5. **Keyboard Fluency** - Power users work at keyboard speed
6. **Accessible by Default** - WCAG 2.1 AA compliance non-negotiable
7. **Respectful Animation** - Subtle, purposeful, respects preferences
8. **Content Over Chrome** - Secret content is the star

---

## 📊 Success Metrics

### Primary Metrics (90-day post-launch)

| Metric | Baseline | Target | Measurement |
|--------|----------|--------|-------------|
| Time to First Secret | ~12 sec | <5 sec | Analytics timing |
| Mobile Completion | ~50% | >80% | Device segmentation |
| Options Discovery | ~30% | >60% | Interaction events |
| User Satisfaction | TBD | >4.5/5 | Post-creation survey |

### Technical Metrics

| Metric | Target | Validation |
|--------|--------|------------|
| WCAG 2.1 AA | 100% | Automated + manual audits |
| Bundle Size | <50KB added | Bundle analyzer |
| Test Coverage | >80% | Jest/Vitest coverage |
| Performance | LCP <2.5s | Lighthouse CI |

---

## 🧪 Testing Strategy

### Unit Tests
- All composables (>80% coverage)
- Component logic
- Validation functions
- State management

### Component Tests
- User interactions
- Keyboard navigation
- Form submission
- Error states

### Integration Tests
- Full form flow
- API integration
- State synchronization

### E2E Tests
- Critical user paths
- Mobile flows
- Keyboard-only flows
- Screen reader flows

### Accessibility Tests
- Automated (axe, Lighthouse)
- Manual keyboard testing
- Screen reader testing (NVDA, JAWS, VoiceOver)
- Color contrast validation

### Visual Regression
- Snapshot tests for all states
- Dark mode variants
- Mobile vs desktop

---

## 🚀 Deployment Strategy

### Phase 1-4: Build Features
- Develop behind feature flag
- Deploy to staging continuously
- QA validation each phase
- No production exposure yet

### Phase 5: Gradual Rollout

**Week 1: Internal Testing**
- Enable for team members only
- Gather feedback
- Fix critical issues

**Week 2: Beta Users (10%)**
- Feature flag → 10% of traffic
- Monitor metrics closely
- A/B test comparison

**Week 3: Expand (50%)**
- If metrics positive, expand to 50%
- Continue monitoring
- Iterate on feedback

**Week 4: Full Rollout (100%)**
- If successful, 100% rollout
- Monitor for 1 week
- Remove feature flag
- Delete old component

**Rollback Plan:**
- Feature flag can instantly revert to old form
- Monitoring alerts on error rates
- Automated rollback if error rate >5%

---

## 🛠️ Development Tools

### Recommended VS Code Extensions
- **Volar** - Vue 3 language support
- **Tailwind CSS IntelliSense** - Class autocomplete
- **ESLint** - Code quality
- **Prettier** - Code formatting
- **axe Accessibility Linter** - Accessibility checks

### Browser DevTools
- **Vue DevTools** - Component inspection
- **Lighthouse** - Performance & accessibility audits
- **axe DevTools** - Accessibility testing
- **Responsive Design Mode** - Mobile testing

### Testing Tools
- **Vitest** - Unit/component tests
- **Playwright** - E2E tests
- **@testing-library/vue** - Component testing
- **axe-core** - Automated accessibility

---

## 📚 Additional Resources

### Design Research
- Phase 1: Discovery & Vision
- Phase 2: User Engagement Study (5 personas)
- Phase 3: Conversational UX Patterns Research
- Phase 4: Design Exploration (3 approaches)
- Phase 5: Final Recommendation

### Technical Documentation
- Component API reference (to be created)
- Composable documentation (to be created)
- Accessibility guidelines (WCAG 2.1 AA)
- Analytics events specification

### External References
- [WCAG 2.1 Quick Reference](https://www.w3.org/WAI/WCAG21/quickref/)
- [Tailwind CSS Documentation](https://tailwindcss.com/docs)
- [Vue 3 Composition API](https://vuejs.org/guide/extras/composition-api-faq.html)
- [ARIA Authoring Practices](https://www.w3.org/WAI/ARIA/apg/)

---

## 🤝 Team Collaboration

### Roles & Responsibilities

**Frontend Developers:**
- Implement components per user stories
- Write unit and component tests
- Ensure accessibility compliance
- Code reviews

**QA Engineers:**
- Test each story's acceptance criteria
- Accessibility testing
- Cross-browser/device testing
- Regression testing

**Product Manager:**
- Prioritize stories
- Review implementation
- Validate against requirements
- Monitor analytics

**Designer:**
- Design approval for each phase
- Visual QA
- Accessibility consultation
- User testing facilitation

### Communication Channels
- Daily standups: Progress updates
- Weekly design reviews: Visual approval
- Bi-weekly demos: Stakeholder alignment
- Slack: Async questions/blockers

---

## 📝 Change Log

### Version 1.0 (2025-01-XX)
- Initial design exploration complete
- Interactive mockups created
- 30 user stories documented
- 5-week implementation plan
- Success metrics defined

---

## ❓ FAQ

### Q: Why not implement all three approaches?
**A:** Approach 2 "Smart Defaults" serves 85%+ of users effectively. It balances simplicity with discoverability. We can iterate to Approach 3 (Dual Mode) later if data shows strong demand for email-first workflow.

### Q: What about the current SecretForm.vue?
**A:** It stays untouched during Phases 1-4. Feature flag controls which renders. Old component deleted in Phase 5 after successful validation.

### Q: Can we skip Phase 5 (A/B testing)?
**A:** Not recommended. A/B testing validates our assumptions and provides data for stakeholder buy-in. However, if time-constrained, can do phased rollout (10% → 50% → 100%) with manual metric comparison.

### Q: What if metrics don't improve?
**A:** Feature flag allows instant rollback. We'd analyze why (likely: design issues, bugs, or wrong metrics). Iterate and re-test. That's why phased rollout is critical.

### Q: How do we handle existing secrets?
**A:** No impact. This is purely UI. Backend API (`/api/v2/secret/conceal`) remains unchanged. All existing secrets, links, and metadata unaffected.

### Q: What about i18n (internationalization)?
**A:** Use existing `$t()` translation system. All user-facing strings should be translation keys. Example: `$t('web.homepage.headline')`. No hardcoded English strings.

### Q: Mobile testing requirements?
**A:** Minimum test matrix:
- iOS Safari (latest)
- iOS Safari (latest - 1)
- Android Chrome (latest)
- Android Chrome (latest - 1)
- Screen sizes: 320px, 375px, 414px, 768px

### Q: Performance budget?
**A:**
- Bundle size: <50KB additional (gzipped)
- LCP: <2.5s
- FCP: <1.5s
- TTI: <3s
Monitor in Lighthouse CI. Fail build if exceeded.

---

## 🐛 Known Issues & Considerations

### Browser Limitations
- **Safari < 14:** Clipboard API limited (fallback needed)
- **iOS Safari:** Backdrop blur performance (use carefully)
- **Firefox:** Focus-visible polyfill may be needed

### Accessibility Considerations
- Screen reader testing required for final approval
- Focus trap in modal critical for keyboard users
- Color-blind users: Don't rely on color alone (use icons + text)

### Mobile Considerations
- Virtual keyboard behavior (test on real devices)
- Touch target sizes (44x44px minimum)
- Paste behavior differs iOS vs Android

---

## 💡 Tips for Implementation

### DO:
✅ Start with Phase 1 completely before moving to Phase 2
✅ Write tests alongside code (not after)
✅ Test on real mobile devices (not just DevTools)
✅ Use existing composables when possible
✅ Keep components small and focused
✅ Reference mockup HTML for exact styling
✅ Test dark mode for every component

### DON'T:
❌ Skip accessibility testing
❌ Hardcode strings (use i18n)
❌ Ignore performance budgets
❌ Test only on desktop
❌ Commit commented-out code
❌ Skip keyboard navigation testing
❌ Forget to update documentation

---

## 📞 Support

**Questions about design:** @design-team
**Questions about implementation:** @engineering-team
**Questions about testing:** @qa-team
**Questions about scope/priority:** @product-team

**Documentation issues:** Create issue in project repo
**Design bugs:** Reference mockup state and screenshot
**Implementation blockers:** Tag in daily standup

---

**Happy Building! 🚀**

This redesign will make OneTimeSecret simpler, faster, and more delightful for all users.
