# Tailwind v4 for Custom Branding & Private-Labeling

## Core Concept

Tailwind v4's CSS-first configuration and native CSS variable support make it well-suited for multi-tenant applications where different customers need their own visual identity applied to the same codebase.

## Implementation Model

### Runtime Theme Injection

Instead of baking brand colors and styles into the build, define **semantic design tokens** (like "primary color" or "brand spacing") that act as placeholders. At display-time, these are filled with tenant-specific values.

- Same compiled CSS works for all tenants
- Brand values injected when the page loads
- No rebuild required when onboarding new customers

### Centralized Brand Control

A single source (database, API, or configuration service) stores each tenant's brand values. When a user accesses the application, their tenant's branding is fetched and applied instantly through CSS custom properties.

### Cascade Layer Organization

Tailwind v4's cascade layers provide clear separation between:

- **Base framework styles** (Tailwind defaults)
- **Shared component styles** (your application)
- **Tenant-specific overrides** (brand customizations)

This hierarchy ensures brand customizations take precedence without conflicts.

## Customization Scope

Typical whitelabel scenarios include dynamic control over:

- Color palettes (primary, secondary, accent)
- Typography (font families, sizes, weights)
- Spacing and layout proportions
- Border radii and shadows
- Dark/light mode variants per tenant

The architectural shift: treat visual identity as **data** rather than **code**.

## Tooling

### Design Tokens

Design tokens are named, reusable values representing design decisions. Instead of hardcoding `#1a73e8`, define `color-primary` and update once at the source. Tokens layer from primitive (`gray-200: #e5e5e5`) to semantic (`text-primary: {gray-200}`).

| Tool                 | Use Case                                                                             |
| -------------------- | ------------------------------------------------------------------------------------ |
| **Style Dictionary** | Cross-platform token transformation (CSS, iOS, Android)                              |
| **Penpot**           | Open source design tool with native W3C DTCG tokens; self-hostable Figma alternative |
| **TokiForge**        | Runtime token consumption with theme switching and Tailwind config generation        |

All export directly to CSS custom properties.

### Linting

**Stylelint** handles CSS quality enforcement with 100+ built-in rules and plugin architecture. Extend with custom rules for token naming conventions and variable usage patterns.

### Visual Regression

Essential for multi-tenant themes—catches unintended changes when brand values update:

| Tool           | Approach                                      |
| -------------- | --------------------------------------------- |
| **Playwright** | Screenshot comparison with browser automation |
| **Lost Pixel** | Full-page and component-level testing         |
| **Loki**       | Storybook-specific                            |

### IDE Support

- **CSS Variables Assistant** (JetBrains) – Autocomplete for custom properties
- **Browser DevTools** – Variable value inspection on hover

### CI/CD Pattern

Tailwind v4 itself uses Vitest + Playwright. Recommended pipeline:

1. Lint CSS on commit
2. Visual regression against each brand configuration
3. Validate token export schema
4. Block deployment on failure

---

## References

### Tailwind v4 & Theming

- [Tailwind CSS v4.0](https://tailwindcss.com/blog/tailwindcss-v4)
- [Adding custom styles - Core concepts](https://tailwindcss.com/docs/adding-custom-styles)
- [Dynamic custom color themes - Stack Overflow](https://stackoverflow.com/questions/79620901/dynamic-custom-color-themes)
- [How to use custom color themes in TailwindCSS v4 - Stack Overflow](https://stackoverflow.com/questions/79499818/how-to-use-custom-color-themes-in-tailwindcss-v4)
- [TailwindCSS v4 responsive and custom CSS not applied - Stack Overflow](https://stackoverflow.com/questions/79560404/tailwindcss-v4-responsive-and-custom-css-not-applied)
- [Tailwind CSS v4 Architecture: JIT & Production Patterns](https://learnwebcraft.com/learn/css/tailwind-v4-essential-cheat-sheet)

### Design Tokens

- [What are design tokens? A complete guide - Penpot](https://penpot.app/blog/what-are-design-tokens-a-complete-guide/)
- [Design token system - Contentful](https://www.contentful.com/blog/design-token-system/)
- [Design tokens – Material Design 3](https://m3.material.io/foundations/design-tokens)
- [Overview - Design tokens - Atlassian](https://atlassian.design/tokens/design-tokens)
