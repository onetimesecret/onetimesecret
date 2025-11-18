# Tailwind CSS v4 Migration Guide

## Overview

This document provides a complete knowledge transfer for the Tailwind CSS v3 → v4 upgrade completed on 2025-11-18. This major version upgrade fundamentally changes how Tailwind is configured, moving from JavaScript-based configuration to CSS-based configuration using the new `@theme` directive.

## Table of Contents

1. [What Changed](#what-changed)
2. [Package Updates](#package-updates)
3. [Configuration Migration](#configuration-migration)
4. [Breaking Changes](#breaking-changes)
5. [How to Use Custom Theme](#how-to-use-custom-theme)
6. [Troubleshooting](#troubleshooting)
7. [Rolling Back](#rolling-back)

---

## What Changed

### Core Philosophy Shift

**Tailwind v3**: Configuration in JavaScript (`tailwind.config.ts`)
```typescript
export default {
  theme: {
    extend: {
      colors: { brand: { 500: '#dc4a22' } }
    }
  }
}
```

**Tailwind v4**: Configuration in CSS (`src/assets/style.css`)
```css
@theme {
  --color-brand-500: #dc4a22;
}
```

### Why This Matters

- **CSS-First**: Theme values are now CSS custom properties, making them accessible in both Tailwind utilities AND regular CSS
- **Better Performance**: CSS-based config enables faster builds and better tree-shaking
- **Simpler Config**: `tailwind.config.ts` is now minimal (just content paths and plugins)

---

## Package Updates

### Installed Packages

```json
{
  "devDependencies": {
    "tailwindcss": "4.1.17",                      // was 3.4.17
    "@tailwindcss/postcss": "4.1.17",             // NEW - required for v4
    "autoprefixer": "10.4.22",                    // was 10.4.21
    "prettier-plugin-tailwindcss": "0.7.1",       // was 0.6.11
    "eslint-plugin-tailwindcss": "4.0.0-beta.0",  // was 3.18.2
    "@tailwindcss/forms": "0.5.10",               // no change (compatible)
    "@tailwindcss/typography": "0.5.19"           // no change (compatible)
  }
}
```

### Critical New Dependency

**`@tailwindcss/postcss`** - In v4, the PostCSS plugin has been extracted to a separate package. Without this, builds will fail with:

```
Error: It looks like you're trying to use `tailwindcss` directly as a PostCSS plugin
```

---

## Configuration Migration

### 1. PostCSS Configuration (`postcss.config.mjs`)

**Before (v3)**:
```javascript
import tailwindcss from 'tailwindcss';
import autoprefixer from 'autoprefixer';

export default {
  plugins: [tailwindcss, autoprefixer]
};
```

**After (v4)**:
```javascript
import tailwindcss from '@tailwindcss/postcss';  // ← Changed import
import autoprefixer from 'autoprefixer';

export default {
  plugins: [tailwindcss, autoprefixer]
};
```

### 2. Main CSS File (`src/assets/style.css`)

**Before (v3)**:
```css
@tailwind base;
@tailwind components;
@tailwind utilities;

@layer base {
  /* custom styles */
}
```

**After (v4)**:
```css
@import "tailwindcss";  /* ← Replaces @tailwind directives */

@theme {
  /* All custom theme values go here */
  --color-brand-500: #dc4a22;
  --font-family-brand: "Zilla Slab", ui-serif, Georgia;
  --animate-kitt-rider: kitt-rider 3s linear infinite;
}

@layer base {
  /* Custom @font-face, keyframes, and base styles */
  @font-face { /* ... */ }
  @keyframes kitt-rider { /* ... */ }
}
```

### 3. Tailwind Config (`tailwind.config.ts`)

**Before (v3)** - 208 lines with full theme config:
```typescript
export default {
  content: ['./src/**/*.{vue,js,ts}'],
  darkMode: 'class',
  theme: {
    fontFamily: { brand: ['Zilla Slab', ...] },
    extend: {
      colors: { brand: { /* 50-950 shades */ } },
      animation: { 'kitt-rider': '...' },
      keyframes: { 'kitt-rider': { /* ... */ } }
    }
  },
  plugins: [
    forms(),
    typography(),
    function({ addBase }) { /* custom @font-face */ }
  ]
}
```

**After (v4)** - 70 lines, config-only:
```typescript
export default {
  content: ['./src/**/*.{vue,js,ts}'],
  safelist: [/* ... */],
  plugins: [forms(), typography()]
}
```

**What Moved to CSS**:
- ❌ `darkMode: 'class'` - Removed (use `dark:` variant)
- ❌ `theme.fontFamily` → `@theme { --font-family-* }`
- ❌ `theme.extend.colors` → `@theme { --color-* }`
- ❌ `theme.extend.animation` → `@theme { --animate-* }`
- ❌ `theme.extend.keyframes` → `@layer base { @keyframes }`
- ❌ Custom plugin with `addBase()` → `@layer base { @font-face }`

---

## Breaking Changes

### 1. Dark Mode

**v3**: Required `darkMode: 'class'` in config
**v4**: Automatic - just use `dark:` variant

```html
<!-- Works the same in v4 -->
<div class="bg-white dark:bg-gray-800">
```

### 2. Custom Colors

**v3**: Defined in JavaScript
```typescript
theme: {
  extend: {
    colors: { brand: { 500: '#dc4a22' } }
  }
}
```

**v4**: Defined in CSS
```css
@theme {
  --color-brand-500: #dc4a22;
}
```

**Usage**: No change in HTML
```html
<button class="bg-brand-500 hover:bg-brand-600">
```

### 3. Custom Animations

**v3**: Keyframes and animation in JavaScript
```typescript
theme: {
  extend: {
    animation: { 'kitt-rider': 'kitt-rider 3s linear infinite' },
    keyframes: { 'kitt-rider': { '0%': { /* ... */ } } }
  }
}
```

**v4**: Split between `@theme` and `@layer base`
```css
@theme {
  --animate-kitt-rider: kitt-rider 3s linear infinite;
}

@layer base {
  @keyframes kitt-rider {
    0% { transform: translateX(-100%); }
    100% { transform: translateX(100%); }
  }
}
```

### 4. Scoped Vue Styles

**Issue**: Custom utilities in `<style scoped>` blocks fail in v4:
```
Error: Cannot apply unknown utility class `ring-brand-500`
```

**Fix**: Add `@reference` directive at top of scoped styles:
```vue
<style scoped>
  @reference "../../assets/style.css";

  .my-class {
    @apply ring-2 ring-brand-500;
  }
</style>
```

**Example**: See `src/components/modals/SettingsModal.vue:279`

---

## How to Use Custom Theme

### Brand Colors

We have 4 custom color palettes (50-950 shades each):

1. **`brand`** - Primary orange (`#dc4a22` at 500)
2. **`branddim`** - Dimmed orange variant
3. **`brandcomp`** - Complementary blue (`#23b5dd` at 500)
4. **`brandcompdim`** - Dimmed blue variant

**Usage**:
```html
<button class="bg-brand-500 hover:bg-brand-600">
<div class="text-brandcomp-500 dark:text-brandcomp-400">
<input class="ring-brand-500 focus:ring-brand-600">
```

**Accessing in CSS**:
```css
.custom-element {
  background-color: var(--color-brand-500);
  color: var(--color-brandcomp-600);
}
```

### Custom Animations

**`animate-spin-slow`** - Slow 2s spin
```html
<div class="animate-spin-slow">⏳</div>
```

**`animate-kitt-rider`** - Knight Rider scanner effect (3s translateX)
```html
<div class="animate-kitt-rider">→</div>
```

**`animate-gradient-x`** - Horizontal gradient animation (5s)
```html
<div class="bg-gradient-to-r from-brand-500 to-brandcomp-500 animate-gradient-x">
```

### Brand Font (Zilla Slab)

**In Tailwind utilities**:
```html
<h1 class="font-brand"><!-- Uses Zilla Slab --></h1>
```

**In CSS**:
```css
.my-heading {
  font-family: var(--font-family-brand);
}
```

**Loaded weights**: 400, 700 (normal + italic for both)

---

## Troubleshooting

### Build Fails: "Cannot apply unknown utility class"

**Symptom**: Error like `Cannot apply unknown utility class 'ring-brand-500'`

**Cause**: Using custom utilities in Vue `<style scoped>` blocks without `@reference`

**Fix**:
```vue
<style scoped>
  @reference "../../assets/style.css";  /* ← Add this */

  .my-class {
    @apply ring-brand-500;
  }
</style>
```

### Build Fails: "PostCSS plugin moved to separate package"

**Symptom**:
```
Error: It looks like you're trying to use `tailwindcss` directly as a PostCSS plugin
```

**Cause**: Missing `@tailwindcss/postcss` package

**Fix**:
```bash
pnpm add -D @tailwindcss/postcss@4.1.17
```

Update `postcss.config.mjs`:
```javascript
import tailwindcss from '@tailwindcss/postcss';  // Not 'tailwindcss'
```

### Custom Colors Not Working

**Symptom**: `bg-brand-500` doesn't apply color

**Checklist**:
1. ✅ Check `src/assets/style.css` has `@theme { --color-brand-500: #dc4a22; }`
2. ✅ Check CSS file is imported in your entry point
3. ✅ Clear Vite cache: `rm -rf node_modules/.vite && pnpm run build`
4. ✅ Check browser DevTools for CSS custom property value

### ESLint Warnings About Tailwind Classes

**Symptom**: ESLint complains about custom classes

**Cause**: `eslint-plugin-tailwindcss` may need v4 beta

**Fix**: Ensure you have:
```json
"eslint-plugin-tailwindcss": "4.0.0-beta.0"
```

### Dark Mode Not Working

**v4 Note**: Dark mode works automatically with the `dark:` variant. You don't need `darkMode: 'class'` in config anymore.

**Verify**:
1. Toggle dark mode class on `<html>` or `<body>`:
```javascript
document.documentElement.classList.toggle('dark');
```

2. Use utilities:
```html
<div class="bg-white dark:bg-gray-800">
```

---

## Rolling Back

If you need to revert to Tailwind v3:

### 1. Restore Packages

```bash
pnpm add -D \
  tailwindcss@3.4.17 \
  autoprefixer@10.4.21 \
  prettier-plugin-tailwindcss@0.6.11 \
  eslint-plugin-tailwindcss@3.18.2

pnpm remove @tailwindcss/postcss
```

### 2. Restore PostCSS Config

```javascript
import tailwindcss from 'tailwindcss';  // Not '@tailwindcss/postcss'
import autoprefixer from 'autoprefixer';

export default {
  plugins: [tailwindcss, autoprefixer]
};
```

### 3. Restore CSS File

```css
@tailwind base;
@tailwind components;
@tailwind utilities;

@layer base {
  html {
    font-family: theme('fontFamily.serif');
  }
  /* ... rest of base styles ... */
}
```

### 4. Restore Full `tailwind.config.ts`

See git history: `git show HEAD~1:tailwind.config.ts`

### 5. Remove Vue `@reference` Directives

Find and remove:
```bash
grep -r "@reference" src/components --include="*.vue"
```

---

## Testing Checklist

After any Tailwind changes, verify:

- [ ] **Build**: `pnpm run build` completes without errors
- [ ] **Type Check**: `pnpm run type-check` passes
- [ ] **Linting**: `pnpm run lint` passes
- [ ] **Dev Server**: `pnpm run dev` runs without console errors
- [ ] **Brand Colors**: All 4 palettes render correctly (light + dark mode)
- [ ] **Custom Animations**: kitt-rider, gradient-x, spin-slow all work
- [ ] **Typography**: Zilla Slab font loads on headings/buttons
- [ ] **Forms Plugin**: Form inputs styled correctly
- [ ] **Dark Mode**: Toggle between light/dark modes works
- [ ] **CSS Bundle Size**: Check for unexpected size increases

---

## Resources

- **Official Upgrade Guide**: https://tailwindcss.com/docs/upgrade-guide
- **v4 Documentation**: https://tailwindcss.com/docs
- **@theme Directive**: https://tailwindcss.com/docs/theme
- **PostCSS Plugin Docs**: https://github.com/tailwindlabs/tailwindcss/tree/next/packages/@tailwindcss/postcss

---

## Questions?

**Custom Color Values**: See `src/assets/style.css` lines 4-51
**Keyframe Animations**: See `src/assets/style.css` lines 104-122
**Font Loading**: See `src/assets/style.css` lines 67-101
**Config Changes**: Compare `git diff HEAD~1 tailwind.config.ts`

**Migration Commit**: `91c87b1b - Upgrade Tailwind CSS from 3.4.17 to 4.1.17`

---

*Last Updated: 2025-11-18*
*Migrated By: Claude Code Assistant*
*Tailwind Version: 4.1.17*
