# RTL (Right-to-Left) Locale Readiness Report
**Date**: 2025-11-17
**Codebase**: OneTimeSecret Vue Application (src/)
**RTL Languages Supported**: Arabic (ar), Hebrew (he)

---

## Executive Summary

The OneTimeSecret Vue codebase has **strong internationalization (i18n) infrastructure** with 24+ language translations, including Arabic and Hebrew (both RTL languages). However, the application currently **lacks fundamental RTL layout and styling support**.

**Overall RTL Readiness Score**: 🔴 **25/100** (Critical Issues Present)

### Quick Assessment
- ✅ **Translation Files**: Arabic and Hebrew locale files exist
- ✅ **i18n Framework**: Vue i18n properly configured
- ✅ **Language Switching**: Functional locale switching mechanism
- ❌ **HTML Direction Attribute**: Not implemented
- ❌ **RTL-Aware Styling**: No RTL CSS support
- ❌ **Tailwind RTL Plugin**: Not configured
- ❌ **Component RTL Logic**: No directional awareness
- ❌ **Icon Mirroring**: Directional icons won't flip

---

## Standard RTL Readiness Criteria Evaluation

### 1. HTML Document Direction (dir attribute)
**Status**: ❌ **CRITICAL FAILURE**

**Current State**:
- `templates/web/index.html:2` has hardcoded `<html lang="en" class="light">`
- No dynamic `dir` attribute binding
- App.vue passes `lang="locale"` to layouts but not `dir`
- BaseLayout.vue has no RTL awareness

**Impact**: RTL languages will render LTR, causing severe usability issues

**Required Changes**:
```html
<!-- Current -->
<html lang="en" class="light">

<!-- Required -->
<html :lang="locale" :dir="isRTL ? 'rtl' : 'ltr'" class="light">
```

**Files to Modify**:
- `templates/web/index.html`
- `src/App.vue`
- `src/layouts/BaseLayout.vue`
- `src/stores/languageStore.ts` (add RTL detection)

---

### 2. CSS Directional Properties
**Status**: ❌ **CRITICAL FAILURE**

**Issues Found**:
- **229 occurrences** of hardcoded directional utilities across 89 Vue files:
  - `ml-*`, `mr-*` (margin-left/right)
  - `pl-*`, `pr-*` (padding-left/right)
  - `rounded-l-*`, `rounded-r-*` (border-radius)
  - `border-l-*`, `border-r-*` (borders)

- **38 occurrences** of `text-left`/`text-right` across 20 files
- **54 occurrences** of positioning utilities (`left-*`, `right-*`) across 35 files
- **3 occurrences** of float utilities in 2 files

**Example from `src/components/secrets/SecretMetadataTable.vue:80-94`**:
```vue
<th class="px-6 py-2.5 text-left text-xs...">
  {{ $t('web.COMMON.secret') }}
</th>
<th class="px-6 py-2.5 text-right text-xs...">
  {{ $t('web.LABELS.actions') }}
</th>
```

**Impact**: In RTL mode, all margins, paddings, and alignments will be inverted incorrectly

**Solution**: Use logical properties or Tailwind RTL plugin
- Replace `ml-4` → `ms-4` (margin-inline-start)
- Replace `mr-4` → `me-4` (margin-inline-end)
- Replace `text-left` → `text-start`
- Replace `text-right` → `text-end`

---

### 3. Tailwind CSS RTL Support
**Status**: ❌ **NOT CONFIGURED**

**Current State**:
- `tailwind.config.ts` has no RTL plugin
- No logical property utilities enabled
- Safelist includes only LTR border-radius variants

**Required Plugin**: `tailwindcss-rtl` or logical properties plugin

**Installation**:
```bash
npm install tailwindcss-rtl tailwindcss-logical
```

**Configuration**:
```javascript
// tailwind.config.ts
import rtl from 'tailwindcss-rtl';
import logical from 'tailwindcss-logical';

export default {
  plugins: [
    forms(),
    typography(),
    rtl,
    logical,
  ],
};
```

---

### 4. Flexbox and Grid Layouts
**Status**: ⚠️ **PARTIAL ISSUES**

**Issues Found**:
- **19 occurrences** of `justify-start`/`justify-end` across 16 files
- **22 occurrences** of `items-start`/`items-end` across 18 files
- **5 occurrences** of `flex-row-reverse` (already used, but not RTL-aware)

**Example from `src/components/layout/DefaultFooter.vue`**:
```vue
<div class="flex flex-row-reverse gap-3">
  <!-- Buttons in reversed order -->
</div>
```

**Impact**: Medium - Flexbox start/end alignment will need adjustment

**Recommendation**: Use flex logical properties with RTL plugin

---

### 5. Internationalization (i18n)
**Status**: ✅ **EXCELLENT** (but missing RTL detection)

**Strengths**:
- ✅ Vue i18n 11.1.10 properly configured
- ✅ 24+ language JSON files including Arabic (`ar.json`) and Hebrew (`he.json`)
- ✅ Dynamic locale loading and switching
- ✅ Fallback locale support
- ✅ Language store with session persistence

**Missing**:
- ❌ No RTL language detection in `src/stores/languageStore.ts`
- ❌ No `isRTL` computed property
- ❌ No automatic `dir` attribute management

**Required Addition**:
```typescript
// src/stores/languageStore.ts
const RTL_LOCALES = ['ar', 'he', 'fa', 'ur']; // Arabic, Hebrew, Farsi, Urdu

const isRTL = computed(() => {
  const primaryLocale = currentLocale.value?.split('-')[0] ?? 'en';
  return RTL_LOCALES.includes(primaryLocale);
});

const textDirection = computed(() => isRTL.value ? 'rtl' : 'ltr');
```

---

### 6. Icons and Visual Elements
**Status**: ❌ **REQUIRES MIRRORING LOGIC**

**Issues Found**:
- **9 files** contain directional icons:
  - ChevronLeft/ChevronRight
  - ArrowLeft/ArrowRight

**Files Affected**:
- `src/views/secrets/ShowMetadata.vue`
- `src/views/colonel/ColonelIndex.vue`
- `src/components/modals/SettingsModal.vue`
- `src/components/layout/MastHead.vue`
- `src/components/dashboard/DashboardTabNav.vue`
- `src/components/MoreInfoText.vue`
- Icon sprite components (HeroiconsSprites, MdiSprites, CriticalSprites)

**Impact**: Navigation arrows and chevrons will point the wrong direction in RTL

**Solution**: Conditional icon selection based on text direction
```vue
<OIcon
  :name="isRTL ? 'chevron-right' : 'chevron-left'"
  class="transform"
  :class="{ 'scale-x-[-1]': isRTL }"
/>
```

---

### 7. Typography and Text Alignment
**Status**: ❌ **REQUIRES REFACTORING**

**Issues Found**:
- **38 instances** of `text-left` and `text-right` in 20 files
- Table headers with directional alignment
- Form labels with hardcoded alignment

**High-Priority Files**:
1. `src/components/secrets/SecretMetadataTable.vue` (8 instances)
2. `src/components/modals/settings/JurisdictionInfo.vue` (4 instances)
3. `src/components/secrets/SecretLinksTable.vue` (3 instances)
4. `src/components/DomainsTable.vue` (3 instances)

**Solution**: Replace with logical alignment
- `text-left` → `text-start`
- `text-right` → `text-end`

---

### 8. Forms and Input Elements
**Status**: ⚠️ **MODERATE ISSUES**

**Issues Found**:
- Input padding/margins use directional utilities
- Button groups may have incorrect visual flow
- Icon positions in inputs are hardcoded

**Example Issues**:
- `src/components/CopyButton.vue` - Icon positioning
- `src/components/DomainInput.vue` - Input icon alignment
- `src/components/ButtonGroup.vue` - Button order

**Impact**: Form elements will have misaligned icons and spacing

---

### 9. Modal and Overlay Positioning
**Status**: ⚠️ **MODERATE ISSUES**

**Issues Found**:
- Modal content alignment uses `text-left`/`text-right`
- Button positioning in modal footers
- Close button positioning (typically top-right)

**Affected Components**:
- `src/components/SimpleModal.vue`
- `src/components/modals/UpgradeIdentityModal.vue`
- `src/components/modals/UpgradeIdentityModalAlt.vue`
- `src/components/modals/SettingsModal.vue`

---

### 10. Navigation and Menus
**Status**: ❌ **REQUIRES REFACTORING**

**Issues Found**:
- Dropdown menu positioning
- Navigation chevrons/arrows
- Submenu alignment

**Affected Components**:
- `src/components/MinimalDropdownMenu.vue`
- `src/components/layout/MastHead.vue`
- `src/components/layout/HeaderUserNav.vue`
- `src/components/dashboard/DashboardTabNav.vue`

---

## Critical Potholes (Must Fix Before RTL Launch)

### 🔴 Priority 1: Infrastructure (Blocking)

1. **No HTML `dir` Attribute Management**
   - **Impact**: Complete RTL rendering failure
   - **Effort**: Medium
   - **Files**: `templates/web/index.html`, `src/App.vue`, `src/layouts/BaseLayout.vue`

2. **No Tailwind RTL Plugin**
   - **Impact**: All directional utilities break
   - **Effort**: Low
   - **Files**: `tailwind.config.ts`, `package.json`

3. **No RTL Language Detection**
   - **Impact**: Cannot determine when to apply RTL
   - **Effort**: Low
   - **Files**: `src/stores/languageStore.ts`

### 🟠 Priority 2: Layout and Styling (High Impact)

4. **229 Hardcoded Directional Utilities**
   - **Impact**: Reversed layouts, broken spacing
   - **Effort**: High (bulk refactor required)
   - **Files**: 89 Vue components across src/

5. **38 Text Alignment Instances**
   - **Impact**: Text aligned incorrectly
   - **Effort**: Medium
   - **Files**: 20 Vue components (especially tables)

6. **54 Absolute Positioning Utilities**
   - **Impact**: Elements positioned on wrong side
   - **Effort**: Medium
   - **Files**: 35 Vue components

### 🟡 Priority 3: Visual Elements (Medium Impact)

7. **Directional Icons Without Mirroring**
   - **Impact**: Confusing navigation (arrows point wrong way)
   - **Effort**: Medium
   - **Files**: 9 components with chevrons/arrows

8. **Form Input Icon Positioning**
   - **Impact**: Icons on wrong side of inputs
   - **Effort**: Medium
   - **Files**: Input components, form components

### 🟢 Priority 4: Polish (Low Impact)

9. **Border Radius Directional Variants**
   - **Impact**: Rounded corners on wrong side
   - **Effort**: Low
   - **Files**: Components using `rounded-l-*` / `rounded-r-*`

10. **Animation Directions**
    - **Impact**: Animations move in wrong direction
    - **Effort**: Low
    - **Files**: `tailwind.config.ts` (kitt-rider, gradient-x animations)

---

## Detailed File Impact Analysis

### Components with Highest RTL Impact (Top 20)

| File | Directional Utils | Text Align | Positioning | Priority |
|------|-------------------|------------|-------------|----------|
| `src/components/secrets/SecretMetadataTable.vue` | 6 | 8 | 2 | 🔴 Critical |
| `src/components/secrets/SecretLinksTableRow.vue` | 7 | 1 | 2 | 🔴 Critical |
| `src/views/account/AccountIndex.vue` | 6 | 0 | 0 | 🟠 High |
| `src/views/colonel/SystemSettings.vue` | 7 | 0 | 1 | 🟠 High |
| `src/components/account/AccountChangePasswordForm.vue` | 7 | 0 | 3 | 🟠 High |
| `src/components/secrets/form/SecretForm.vue` | 5 | 0 | 3 | 🟠 High |
| `src/components/dashboard/BrowserPreviewFrame.vue` | 6 | 0 | 0 | 🟠 High |
| `src/components/icons/sprites/HeroiconsSprites.vue` | 17 | 0 | 4 | 🟡 Medium |
| `src/components/modals/UpgradeIdentityModalAlt.vue` | 4 | 2 | 0 | 🟡 Medium |
| `src/components/ActivityFeed.vue` | 4 | 0 | 3 | 🟡 Medium |
| `src/views/colonel/ColonelInfo.vue` | 4 | 2 | 0 | 🟡 Medium |
| `src/components/logos/OnetimeSecretLogo.vue` | 4 | 0 | 2 | 🟡 Medium |
| `src/components/secrets/SecretLinkLine.vue` | 3 | 0 | 1 | 🟡 Medium |
| `src/components/DomainsTable.vue` | 3 | 3 | 0 | 🟡 Medium |
| `src/components/secrets/canonical/SecretDisplayCase.vue` | 5 | 0 | 0 | 🟡 Medium |
| `src/components/BasicFormAlerts.vue` | 4 | 0 | 0 | 🟡 Medium |
| `src/components/FeedbackForm.vue` | 3 | 0 | 1 | 🟢 Low |
| `src/components/ButtonGroup.vue` | 3 | 0 | 0 | 🟢 Low |
| `src/components/CustomDomainPreview.vue` | 3 | 1 | 0 | 🟢 Low |
| `src/components/account/DomainBrandView.vue` | 3 | 0 | 1 | 🟢 Low |

---

## Recommended Implementation Roadmap

### Phase 1: Foundation (Week 1)
**Goal**: Enable basic RTL infrastructure

1. ✅ Install Tailwind RTL plugins
   ```bash
   npm install -D tailwindcss-rtl tailwindcss-logical
   ```

2. ✅ Update Tailwind config
   - Add RTL and logical plugins
   - Configure RTL variants
   - Update safelist for RTL utilities

3. ✅ Add RTL detection to language store
   - Create `RTL_LOCALES` constant
   - Add `isRTL` computed property
   - Add `textDirection` computed property

4. ✅ Update HTML template and layouts
   - Dynamic `dir` attribute in `index.html`
   - Propagate `dir` through App.vue and BaseLayout.vue
   - Update `lang` attribute to be dynamic

### Phase 2: Core Components (Week 2-3)
**Goal**: Fix critical layout and table components

5. ✅ Refactor table components (highest impact)
   - SecretMetadataTable.vue
   - SecretLinksTable.vue
   - DomainsTable.vue
   - Replace `text-left/right` with `text-start/end`
   - Fix header alignment

6. ✅ Update form components
   - Input icon positioning
   - Button group ordering
   - Form validation message alignment

7. ✅ Fix navigation components
   - MastHead navigation
   - Dropdown menus
   - Tab navigation

### Phase 3: Bulk Refactoring (Week 4-5)
**Goal**: Migrate all directional utilities

8. ✅ Automated bulk replacement (use find/replace with verification)
   - `ml-` → `ms-` (margin-inline-start)
   - `mr-` → `me-` (margin-inline-end)
   - `pl-` → `ps-` (padding-inline-start)
   - `pr-` → `pe-` (padding-inline-end)
   - `rounded-l-` → `rounded-s-`
   - `rounded-r-` → `rounded-e-`
   - `border-l-` → `border-s-`
   - `border-r-` → `border-e-`

9. ✅ Manual review of positioning utilities
   - `left-*` / `right-*` absolute positioning
   - Float utilities
   - Transform/translate values

### Phase 4: Visual Polish (Week 6)
**Goal**: Icon mirroring and animations

10. ✅ Implement icon mirroring logic
    - Create RTL-aware icon component wrapper
    - Update directional icons (chevrons, arrows)
    - Test icon flipping in RTL mode

11. ✅ Fix animations
    - Update kitt-rider animation for RTL
    - Update gradient-x animation for RTL
    - Add RTL variants to custom animations

### Phase 5: Testing and Validation (Week 7)
**Goal**: Comprehensive RTL testing

12. ✅ Visual regression testing
    - Test all pages in Arabic locale
    - Test all pages in Hebrew locale
    - Screenshot comparison LTR vs RTL

13. ✅ Functional testing
    - Form submissions
    - Navigation flows
    - Modal interactions
    - Dropdown behaviors

14. ✅ Accessibility testing
    - Screen reader compatibility (NVDA, JAWS)
    - Keyboard navigation
    - Focus indicators

---

## Testing Checklist

### Manual Testing (Required for Each RTL Locale)

- [ ] Switch to Arabic (ar) locale
- [ ] Verify `<html dir="rtl">` is set
- [ ] Check homepage layout flows RTL
- [ ] Test secret creation form
- [ ] Test secret viewing page
- [ ] Test account settings
- [ ] Test dashboard tables
- [ ] Test navigation menus
- [ ] Test modals and overlays
- [ ] Test dropdown menus
- [ ] Verify icons are mirrored correctly
- [ ] Check form validation messages
- [ ] Test copy button functionality
- [ ] Verify tooltips position correctly
- [ ] Test responsive layouts (mobile)

### Automated Testing

- [ ] Add Cypress/Playwright tests for RTL
- [ ] Add visual regression tests (Percy, Chromatic)
- [ ] Add unit tests for `isRTL` logic
- [ ] Add integration tests for language switching

---

## Browser Compatibility

### RTL CSS Support
- ✅ Chrome/Edge: Excellent (full logical properties support)
- ✅ Firefox: Excellent (full logical properties support)
- ✅ Safari: Excellent (full logical properties support as of Safari 14.1+)
- ⚠️ IE11: Not supported (but app likely doesn't support IE11 anyway)

### Tailwind RTL Plugin Support
- ✅ All modern browsers (uses standard CSS `dir` selectors)
- ✅ No JavaScript required (pure CSS solution)

---

## Cost Estimate

### Development Effort

| Phase | Estimated Hours | Complexity |
|-------|----------------|------------|
| Phase 1: Foundation | 8-12 hours | Low |
| Phase 2: Core Components | 16-24 hours | Medium |
| Phase 3: Bulk Refactoring | 24-32 hours | Medium-High |
| Phase 4: Visual Polish | 8-16 hours | Medium |
| Phase 5: Testing | 16-24 hours | Medium |
| **Total** | **72-108 hours** | **9-14 days** |

### Risk Factors
- 🟡 Regression risk during bulk refactoring (mitigated by testing)
- 🟡 Edge cases in complex components (modals, tables)
- 🟢 Low breaking change risk (additive changes mostly)

---

## Long-Term Maintenance

### Best Practices for RTL-Ready Code

1. **Always use logical properties**
   ```vue
   <!-- ❌ Don't -->
   <div class="ml-4 mr-2">

   <!-- ✅ Do -->
   <div class="ms-4 me-2">
   ```

2. **Use start/end for alignment**
   ```vue
   <!-- ❌ Don't -->
   <p class="text-left">

   <!-- ✅ Do -->
   <p class="text-start">
   ```

3. **Make icons RTL-aware**
   ```vue
   <!-- ❌ Don't -->
   <OIcon name="chevron-right" />

   <!-- ✅ Do -->
   <OIcon :name="isRTL ? 'chevron-left' : 'chevron-right'" />
   ```

4. **Test in both directions**
   - Add RTL to CI/CD pipeline
   - Include RTL in PR review checklist
   - Maintain RTL screenshot tests

### Code Review Guidelines

Add to PR template:
```markdown
## RTL Considerations
- [ ] No hardcoded `ml-`, `mr-`, `pl-`, `pr-` utilities
- [ ] No `text-left` or `text-right` (use `text-start`/`text-end`)
- [ ] Directional icons are RTL-aware
- [ ] Tested in both LTR and RTL locales
```

---

## References

### Tailwind RTL Resources
- [tailwindcss-rtl Plugin](https://github.com/20lives/tailwindcss-rtl)
- [tailwindcss-logical Plugin](https://github.com/stevecochrane/tailwindcss-logical)
- [Tailwind CSS Logical Properties](https://tailwindcss.com/docs/padding#logical-properties)

### RTL Best Practices
- [MDN: CSS Logical Properties](https://developer.mozilla.org/en-US/docs/Web/CSS/CSS_Logical_Properties)
- [W3C: Structural Markup and RTL](https://www.w3.org/International/questions/qa-html-dir)
- [Material Design: Bidirectionality](https://m2.material.io/design/usability/bidirectionality.html)

### Vue.js RTL Integration
- [Vue i18n: Right-to-Left](https://vue-i18n.intlify.dev/guide/essentials/syntax.html#rtl-support)
- [Vuetify RTL Support](https://vuetifyjs.com/en/features/internationalization/#rtl-support)

---

## Conclusion

The OneTimeSecret Vue application has a **solid i18n foundation** but requires **significant CSS and layout refactoring** to properly support RTL languages. The primary challenges are:

1. Lack of `dir` attribute infrastructure
2. Extensive use of physical directional utilities (229 instances)
3. No automated RTL tooling (Tailwind plugin)

**Recommended Action**: Proceed with the 7-week implementation roadmap to achieve full RTL support. The effort is substantial but manageable with a systematic approach.

**Quick Win**: Implement Phase 1 (Foundation) immediately to enable basic RTL rendering, then incrementally refactor components in order of priority.

---

**Report Prepared By**: Claude Code (AI Assistant)
**Review Status**: Awaiting Human Review
**Next Steps**: Approve roadmap and begin Phase 1 implementation
