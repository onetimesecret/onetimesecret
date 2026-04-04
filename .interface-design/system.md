# Onetime Secret Design System

## Intent

**Who**: Users sharing sensitive information — passwords, credentials, private messages. Often technical (developers, IT admins) but increasingly non-technical users sharing passwords with family or colleagues.

**Task**: Create a secret link quickly, track its status, share it securely.

**Feel**: Trustworthy and precise. Not cold, but not playful either. The warmth comes from the brand color (flame orange) against neutral surfaces — like a wax seal on a letter.

---

## Palette

### Brand Colors
- **Primary (flame)**: `brand-500` (#dc4a22) — warm orange, used sparingly for actions and active states
- **Complement (sky)**: `brandcomp-500` (#23b5dd) — cool blue, reserved for special cases

### Surface Colors
- **Light mode**: White with gray-50 undertones, semi-transparent (`bg-white/60`, `bg-white/80`)
- **Dark mode**: Slate-800/900 with transparency (`bg-gray-800/60`, `bg-gray-800/80`)

### Text Hierarchy
- **Primary**: `text-gray-900` / `dark:text-white`
- **Secondary**: `text-gray-600` / `dark:text-gray-300`
- **Tertiary**: `text-gray-500` / `dark:text-gray-400`
- **Muted**: `text-gray-400` / `dark:text-gray-500`

---

## Surfaces

### Card Treatment
Standard card surface for content containers:

```
border border-gray-200/60 bg-white/60 shadow-sm backdrop-blur-sm
dark:border-gray-700/60 dark:bg-gray-800/60
```

### Elevated Card (primary actions)
For the main interaction area (e.g., secret form):

```
border border-gray-200/60
bg-gradient-to-br from-white to-gray-50/30
shadow-[0_4px_16px_rgb(0,0,0,0.08),0_1px_4px_rgb(0,0,0,0.06)]
backdrop-blur-sm
dark:border-gray-700/60 dark:from-slate-900 dark:to-slate-800/30
dark:shadow-[0_4px_16px_rgb(0,0,0,0.3),0_1px_4px_rgb(0,0,0,0.2)]
```

### Empty State
For "no content" areas:

```
rounded-xl border border-gray-200 bg-gray-50/50
dark:border-gray-700/50 dark:bg-slate-800/20
```

---

## Depth Scale

| Level | Use | Shadow |
|-------|-----|--------|
| 0 | Flat elements | none |
| 1 | Cards, containers | `shadow-sm` |
| 2 | Primary action areas | `shadow-[0_4px_16px_...]` |
| 3 | Modals, dropdowns | `shadow-lg` |

All surfaces use `backdrop-blur-sm` for the frosted glass effect.

---

## Typography

### Fonts
- **Brand**: Zilla Slab (serif) — used for headings and brand moments
- **Body**: System sans-serif stack
- **Code**: System monospace — used in the console-style row variant

### Scale
- **Page title**: `text-xl font-medium` (rarely used in workspace)
- **Section heading**: `text-lg font-medium text-gray-600 dark:text-gray-300`
- **Card heading**: `text-base font-medium`
- **Body**: `text-sm`
- **Caption**: `text-xs`

---

## Spacing

### Base Unit
4px (`1` in Tailwind)

### Section Rhythm
- **Between related elements**: `mb-3` or `mb-4` (12-16px)
- **Between sections**: `mb-10` (40px)
- **Bottom padding for scroll room**: `pb-16` (64px)

### Card Padding
- **Standard**: `p-4 sm:p-6`
- **Dense**: `p-3`

---

## Interactive Elements

### Chips/Tags
Active state:
```
bg-brand-50 text-brand-700 ring-1 ring-inset ring-brand-600/20
hover:bg-brand-100
dark:bg-brand-900/30 dark:text-brand-300 dark:ring-brand-400/30
```

Inactive state:
```
bg-gray-50 text-gray-600 ring-1 ring-inset ring-gray-500/20
hover:bg-gray-100
dark:bg-gray-700 dark:text-gray-300 dark:ring-gray-500/30
```

### Buttons
Primary uses brand color with `cornerClass` prop for consistent rounding.

---

## Component Patterns

### Dashboard Layout
Three stacked sections with consistent card treatment:
1. **Options bar** — compact, controls for the form below
2. **Primary action card** — elevated, largest visual weight
3. **Secondary content** — standard card, quieter heading

### Row Variants (A/B test system)
The `SecretLinksTableRow` component supports multiple visual variants:
- `timeline` — vertical connector, badge status
- `console` — monospace, tree-style metadata (current default)
- `ledger` — medallion index
- `slotmachine` — full-row state coloring

---

## Decisions Log

### 2026-01-19: Dashboard cohesion refinement
- Reduced form card shadow from `8px/30px` to `4px/16px`
- Added card surface to SecretLinksTable list container
- Unified border opacity at `/60` across all cards
- Reduced section heading from `text-xl` to `text-lg` with lighter color
- Tightened spacing rhythm (`mb-6` → `mb-4`, `mb-12` → `mb-10`, `pb-24` → `pb-16`)

### 2026-02-03: Early Supporter status color
- Added amber palette for grandfathered/legacy plan badges
- `amber-100/700/800` (light) and `amber-900/30, amber-400` (dark)
- Chose amber over green (success) or purple (premium) to convey warmth and appreciation for early adopters
- Complements brand orange without competing for attention
