# RTL Critical Potholes - Must Fix

**Date**: 2025-11-17
**Status**: 🔴 **BLOCKING RTL SUPPORT**

---

## 🔴 Priority 1: Infrastructure (Blocking Issues)

### 1. No HTML `dir` Attribute Management
**Impact**: ⚠️ **CRITICAL** - RTL languages will render completely wrong

**Current State**:
```html
<!-- templates/web/index.html:2 -->
<html lang="en" class="light">  <!-- Hardcoded! -->
```

**Required Fix**:
```html
<html :lang="locale" :dir="textDirection" class="light">
```

**Files to Modify**:
- `templates/web/index.html` - Add dynamic `dir` attribute
- `src/App.vue` - Pass `dir` prop to layout
- `src/layouts/BaseLayout.vue` - Apply `dir` to wrapper

**Effort**: 2-4 hours

---

### 2. No Tailwind RTL Plugin Configured
**Impact**: ⚠️ **CRITICAL** - All directional utilities will break in RTL

**Current State**: No RTL support in `tailwind.config.ts`

**Required Fix**:
```bash
npm install -D tailwindcss-rtl tailwindcss-logical
```

```typescript
// tailwind.config.ts
import rtl from 'tailwindcss-rtl';
import logical from 'tailwindcss-logical';

export default {
  plugins: [
    forms(),
    typography(),
    rtl,      // ← Add
    logical,  // ← Add
  ],
};
```

**Effort**: 1-2 hours

---

### 3. No RTL Language Detection
**Impact**: ⚠️ **CRITICAL** - Cannot determine when to apply RTL mode

**Current State**: `src/stores/languageStore.ts` has no RTL logic

**Required Fix**:
```typescript
// src/stores/languageStore.ts
const RTL_LOCALES = ['ar', 'he', 'fa', 'ur'];

const isRTL = computed(() => {
  const primaryLocale = currentLocale.value?.split('-')[0] ?? 'en';
  return RTL_LOCALES.includes(primaryLocale);
});

const textDirection = computed(() => isRTL.value ? 'rtl' : 'ltr');

// Export for use in components
return {
  // ... existing exports
  isRTL,
  textDirection,
};
```

**Effort**: 2-3 hours

---

## 🟠 Priority 2: Layout and Styling (High Impact)

### 4. 229 Hardcoded Directional Utilities
**Impact**: 🔥 **HIGH** - Broken spacing, reversed layouts

**Location**: 89 Vue components across `src/`

**Examples**:
- `ml-4` → Should be `ms-4` (margin-inline-start)
- `mr-2` → Should be `me-2` (margin-inline-end)
- `pl-6` → Should be `ps-6` (padding-inline-start)
- `pr-6` → Should be `pe-6` (padding-inline-end)
- `rounded-l-lg` → Should be `rounded-s-lg`
- `rounded-r-lg` → Should be `rounded-e-lg`

**Top Affected Files**:
1. `src/components/icons/sprites/HeroiconsSprites.vue` - 17 instances
2. `src/views/account/AccountIndex.vue` - 6 instances
3. `src/views/colonel/SystemSettings.vue` - 7 instances
4. `src/components/account/AccountChangePasswordForm.vue` - 7 instances
5. `src/components/secrets/SecretLinksTableRow.vue` - 7 instances

**Bulk Fix Strategy**:
```bash
# Use find/replace (with manual verification):
ml- → ms-
mr- → me-
pl- → ps-
pr- → pe-
rounded-l- → rounded-s-
rounded-r- → rounded-e-
border-l- → border-s-
border-r- → border-e-
```

**Effort**: 20-30 hours (bulk refactor + testing)

---

### 5. 38 Text Alignment Instances
**Impact**: 🔥 **HIGH** - Text aligned wrong in RTL

**Location**: 20 Vue components (especially tables)

**Examples**:
```vue
<!-- ❌ Current -->
<th class="text-left">{{ $t('web.COMMON.secret') }}</th>
<th class="text-right">{{ $t('web.LABELS.actions') }}</th>

<!-- ✅ Required -->
<th class="text-start">{{ $t('web.COMMON.secret') }}</th>
<th class="text-end">{{ $t('web.LABELS.actions') }}</th>
```

**Top Affected Files**:
1. `src/components/secrets/SecretMetadataTable.vue` - 8 instances
2. `src/components/modals/settings/JurisdictionInfo.vue` - 4 instances
3. `src/components/secrets/SecretLinksTable.vue` - 3 instances
4. `src/components/DomainsTable.vue` - 3 instances

**Effort**: 6-8 hours

---

### 6. 54 Absolute Positioning Utilities
**Impact**: 🟡 **MEDIUM** - Elements positioned on wrong side

**Location**: 35 Vue components

**Examples**:
- `left-0`, `right-0` in fixed/absolute positioned elements
- Toast notifications
- Tooltips
- Dropdown menus

**Critical Files**:
- `src/components/StatusBar.vue` - 4 instances
- `src/components/GlobalBroadcast.vue` - 2 instances
- `src/components/ui/ToastNotification.vue`
- `src/components/MinimalDropdownMenu.vue`

**Effort**: 8-12 hours

---

## 🟡 Priority 3: Visual Elements (Medium Impact)

### 7. Directional Icons Without Mirroring
**Impact**: 🟡 **MEDIUM** - Confusing navigation (arrows point wrong way)

**Location**: 9 components with chevrons/arrows

**Examples**:
```vue
<!-- ❌ Current -->
<OIcon name="chevron-right" />

<!-- ✅ Required -->
<OIcon :name="isRTL ? 'chevron-left' : 'chevron-right'" />

<!-- OR use CSS transform -->
<OIcon
  name="chevron-right"
  class="rtl:scale-x-[-1]"
/>
```

**Affected Files**:
- `src/views/secrets/ShowMetadata.vue`
- `src/components/layout/MastHead.vue`
- `src/components/dashboard/DashboardTabNav.vue`
- `src/components/MoreInfoText.vue`
- `src/components/modals/SettingsModal.vue`

**Effort**: 4-6 hours

---

### 8. Form Input Icon Positioning
**Impact**: 🟡 **MEDIUM** - Icons on wrong side of inputs

**Affected Components**:
- `src/components/CopyButton.vue`
- `src/components/DomainInput.vue`
- `src/components/account/APIKeyForm.vue`

**Example Fix**:
```vue
<!-- Use logical positioning -->
<div class="relative">
  <input class="ps-10" /> <!-- padding-inline-start -->
  <OIcon class="absolute start-3 top-1/2" /> <!-- inset-inline-start -->
</div>
```

**Effort**: 4-6 hours

---

## 🟢 Priority 4: Polish (Can Defer)

### 9. Border Radius Directional Variants
**Impact**: 🟢 **LOW** - Rounded corners on wrong side

**Location**: Button groups, split buttons

**Fix**: Included in bulk refactor (#4)

**Effort**: Minimal (part of bulk changes)

---

### 10. Animation Directions
**Impact**: 🟢 **LOW** - Animations move in wrong direction

**Location**: `tailwind.config.ts`

**Affected Animations**:
```javascript
'kitt-rider': {
  '0%': { transform: 'translateX(-100%)' },   // ← Needs RTL variant
  '100%': { transform: 'translateX(100%)' },  // ← Needs RTL variant
},
'gradient-x': {
  'background-position': 'left center',   // ← Needs logical position
  'background-position': 'right center',  // ← Needs logical position
}
```

**Effort**: 2-3 hours

---

## Summary Table

| # | Pothole | Impact | Effort | Blocking? |
|---|---------|--------|--------|-----------|
| 1 | No `dir` attribute | ⚠️ Critical | 2-4h | ✅ YES |
| 2 | No Tailwind RTL plugin | ⚠️ Critical | 1-2h | ✅ YES |
| 3 | No RTL detection | ⚠️ Critical | 2-3h | ✅ YES |
| 4 | 229 directional utilities | 🔥 High | 20-30h | ⚠️ Partial |
| 5 | 38 text alignments | 🔥 High | 6-8h | ⚠️ Partial |
| 6 | 54 positioning utilities | 🟡 Medium | 8-12h | ❌ No |
| 7 | Directional icons | 🟡 Medium | 4-6h | ❌ No |
| 8 | Form input icons | 🟡 Medium | 4-6h | ❌ No |
| 9 | Border radius | 🟢 Low | Minimal | ❌ No |
| 10 | Animations | 🟢 Low | 2-3h | ❌ No |
| **TOTAL** | | | **50-76 hours** | |

---

## Minimum Viable RTL (Quick Start)

To get **basic RTL working** (not perfect, but functional):

### Week 1: Must Fix (Priority 1 only)
1. ✅ Install Tailwind RTL plugins (1-2h)
2. ✅ Add RTL detection to language store (2-3h)
3. ✅ Add `dir` attribute to HTML (2-4h)

**Result**: RTL languages will render in RTL mode, but spacing/alignment will be off

### Week 2-3: High-Impact Fixes (Priority 2)
4. ✅ Fix table components (6-8h) - Most visible issue
5. ✅ Bulk refactor top 20 components (12-16h)

**Result**: Most common pages will look correct in RTL

### Week 4+: Polish (Priority 3-4)
6. ✅ Fix remaining components incrementally
7. ✅ Add icon mirroring
8. ✅ Final polish and testing

---

## Testing Quick Checklist

After fixing Priority 1 issues, test:

- [ ] Switch to Arabic (`ar`) locale
- [ ] Verify `<html dir="rtl">` in DevTools
- [ ] Check if layout flows right-to-left
- [ ] Verify text alignment (should be right-aligned)
- [ ] Check navigation (should be reversed)

After fixing Priority 2 issues, test:

- [ ] Tables render correctly
- [ ] Forms are usable
- [ ] Buttons and icons are positioned correctly
- [ ] Mobile responsive layout works

---

## Quick Reference

### RTL Language Codes
- `ar` - Arabic (العربية)
- `he` - Hebrew (עברית)
- `fa` - Farsi/Persian (not yet supported)
- `ur` - Urdu (not yet supported)

### Key Files to Monitor
- `templates/web/index.html` - HTML template with dir attribute
- `src/stores/languageStore.ts` - RTL detection logic
- `tailwind.config.ts` - RTL plugin configuration
- `src/App.vue` - Root component dir binding
- `src/layouts/BaseLayout.vue` - Layout dir propagation

### Helpful Commands
```bash
# Find all directional utilities
grep -rn "ml-\|mr-\|pl-\|pr-" src/ --include="*.vue" | wc -l

# Find all text alignments
grep -rn "text-left\|text-right" src/ --include="*.vue"

# Find all directional icons
grep -rn "chevron-left\|chevron-right\|arrow-left\|arrow-right" src/ --include="*.vue"

# Install RTL dependencies
npm install -D tailwindcss-rtl tailwindcss-logical
```

---

**Next Action**: Begin with Priority 1 issues (#1-3) to unblock RTL development.
