# Private-Label Branding & Theming: Landscape Analysis

This document maps how open-source projects approach white-label branding and theming customization. The analysis covers ten projects across identity, collaboration, scheduling, analytics, and documentation spaces.

## Projects Surveyed

| Project | Category | Relevance to OTS |
|---------|----------|------------------|
| GitLab | DevOps platform | Design token architecture reference |
| Mattermost | Team messaging | CSS variable migration patterns |
| Cal.com | Scheduling | Self-hosted white-labeling approach |
| Chatwoot | Customer support | Community Edition limitations |
| Documenso | Document signing | shadcn/Tailwind token patterns |
| Plausible | Analytics | Embedded dashboard white-labeling |
| Outline | Knowledge base | Accent color customization |
| Rallly | Scheduling polls | Recent white-label implementation |
| Zitadel | Identity/auth | Trust-sensitive branding model |
| Keycloak | Identity/auth | Template-based theming system |

---

## 1. Stack Comparison

### CSS Architecture

| Project | Token System | Color Format | Dark Mode Approach |
|---------|--------------|--------------|-------------------|
| GitLab | 3-tier design tokens (constant/semantic/contextual) | Hex | Per-token definitions |
| Cal.com | CSS custom properties | Hex | `.dark` class override |
| Documenso | shadcn conventions | HSL | Class-based toggle |
| Mattermost | CSS variables (post-migration) | RGB with opacity | Theme object |
| Zitadel | Config-driven | Hex | Separate light/dark logos |
| Keycloak | FreeMarker templates + CSS | Arbitrary | Theme inheritance |
| Outline | Accent color only | Hex | System preference |
| Rallly | Environment variables | Hex | Separate light/dark primaries |
| Plausible | Embed parameters | Limited (light/dark/system + bg color) | Theme parameter |
| Chatwoot | Source modification | N/A | N/A |

### Configuration Surface

| Project | Configuration Method | Persistence |
|---------|---------------------|-------------|
| GitLab | API + Admin UI | Database |
| Cal.com | globals.css modification (self-hosted) | Filesystem |
| Documenso | Admin UI upload | Database + asset storage |
| Mattermost | Theme object in settings | Database |
| Zitadel | Admin console (instance + org level) | Database |
| Keycloak | Theme directory structure | Filesystem |
| Outline | Workspace settings | Database |
| Rallly | Environment variables + Control Panel | Config + Database |
| Plausible | Embed code parameters | URL parameters |
| Chatwoot | Database modification or source fork | Varies |

### Build/Runtime Distinction

Projects divide into two patterns:

**Build-time customization** requires deployment changes:
- Cal.com (CSS file modification)
- Keycloak (theme directory packaging)
- Chatwoot Community Edition (source modification)

**Runtime customization** operates through admin interfaces:
- GitLab, Zitadel, Documenso, Outline, Rallly
- Mattermost (theme object)
- Plausible (embed parameters)

---

## 2. Architecture Comparison

### Token Hierarchy Models

**Three-tier (GitLab/Pajamas)**

```
Constant → Semantic → Contextual
color.purple.100 → status.brand.background.color → avatar.fallback.background.purple
```

Estimated 200-400 tokens. Naming convention: `[group].[component].[property].[state]`. Output formats include Figma variables, CSS custom properties (`var(--gl-*)`), and SCSS variables (`$gl-*`).

**Flat namespace (Cal.com)**

```css
:root {
  --cal-bg-emphasis: #e5e7eb;
  --cal-bg: white;
  --cal-bg-subtle: #f3f4f6;
  --cal-bg-error: #f9e3e2;
}
```

Estimated 30-50 tokens. Semantic naming without hierarchy. Dark mode via class override on the same properties.

**shadcn conventions (Documenso)**

```css
:root {
  --background: 0 0% 100%;
  --foreground: 222.2 84% 4.9%;
  --primary: 222.2 47.4% 11.2%;
}
```

Estimated 20-30 core tokens. HSL-based values. Tailwind CSS integration assumed.

### Branding Scope by Project

| Project | Logo | Colors | Fonts | Attribution | Email Branding |
|---------|------|--------|-------|-------------|----------------|
| GitLab | ✓ | Header/footer only | ✗ | N/A | Partial |
| Cal.com | ✓ | Full palette | ✗ | Platform tier | ✓ |
| Documenso | ✓ | N/A | N/A | N/A | ✓ (footer text) |
| Mattermost | ✓ | Full theme | ✗ | N/A | Partial |
| Zitadel | ✓ (light/dark) | 4 colors | ✓ (TTF upload) | Toggle | ✓ |
| Keycloak | ✓ | Full CSS | ✓ | N/A | Separate theme |
| Outline | ✓ | Accent only | ✗ | Toggle (paid add-on) | N/A |
| Rallly | ✓ | Primary (light/dark) | ✗ | Toggle | N/A |
| Plausible | N/A | Background only | N/A | Removed in embed | N/A |
| Chatwoot | Source mod | Source mod | Source mod | Source mod | Source mod |

### Multi-tenant Branding Architecture

**Instance-level only**: GitLab, Cal.com (self-hosted), Mattermost, Outline, Rallly, Plausible

**Organization-level override**: Zitadel (instance defaults, per-org customization), Keycloak (per-realm themes)

Zitadel's two-level model is notable: instance branding serves as the default, individual organizations can override with their own branding, and the system shows a preview before activation.

---

## 3. Feature Ratings

Rating scale:
- **4** = Full programmatic control, documented API
- **3** = Comprehensive UI-based customization
- **2** = Limited customization, workarounds required
- **1** = Source modification or fork required
- **0** = No capability

| Project | Logo Control | Color System | Dark Mode | Email Branding | Attribution Removal | Font Control | API Access |
|---------|-------------|--------------|-----------|----------------|---------------------|--------------|------------|
| GitLab | 4 | 1 | 3 | 2 | N/A | 0 | 4 (limited scope) |
| Cal.com | 3 | 3 | 3 | 3 | 3 (tier-gated) | 0 | 0 |
| Documenso | 3 | 0 | N/A | 3 | N/A | 0 | 0 |
| Mattermost | 3 | 3 | 3 | 2 | N/A | 0 | 3 |
| Zitadel | 4 | 3 | 4 | 3 | 3 | 3 | 3 |
| Keycloak | 3 | 4 | 3 | 3 | N/A | 4 | 0 |
| Outline | 3 | 1 | 2 | 0 | 2 (paid) | 0 | 0 |
| Rallly | 3 | 2 | 3 | 0 | 3 | 0 | 0 |
| Plausible | 0 | 1 | 2 | N/A | 3 | 0 | 4 (build your own) |
| Chatwoot CE | 1 | 1 | 1 | 1 | 1 | 1 | 0 |

### Composite Scores

| Project | Operator Experience (avg) | Technical Depth (max) |
|---------|--------------------------|----------------------|
| Zitadel | 3.3 | 4 |
| Keycloak | 2.9 | 4 |
| Mattermost | 2.6 | 3 |
| Cal.com | 2.5 | 3 |
| GitLab | 2.3 | 4 |
| Documenso | 2.0 | 3 |
| Plausible | 1.7 | 4 |
| Rallly | 1.8 | 3 |
| Outline | 1.3 | 3 |
| Chatwoot CE | 0.9 | 1 |

---

## 4. Positioning Analysis

### Commercial Framing

**Branding as enterprise feature**:
- Cal.com: Platform tier includes custom CSS injection
- Outline: Attribution removal requires paid add-on
- Chatwoot: Enterprise Edition vs Community Edition split

**Branding as core capability**:
- Zitadel: Full branding in open-source, positioned as trust requirement
- Keycloak: Complete theming in community edition
- Rallly: Added white-labeling as enterprise add-on in v4.6.0 (January 2026)

**Branding as DIY**:
- Plausible: Stats API for building custom dashboards, embed for quick wins
- GitLab: Appearance API for basics, design tokens internal only

### Trust-Sensitive Positioning

Zitadel and Keycloak (identity providers) treat branding as essential for user trust during authentication flows. Both emphasize that branded login screens reduce phishing suspicion. Zitadel's documentation explicitly frames branding as a trust mechanism.

Plausible positions its white-label approach around client relationships: analytics providers need to present dashboards without third-party branding to maintain client confidence.

---

## 5. Strengths and Gaps

### Gaps in Current OTS Coverage

**Runtime configuration UI**: Most surveyed projects provide admin interfaces for branding. Source modification (the Chatwoot CE pattern) consistently generates support friction.

**Email branding**: Several projects treat email templates as a separate branding surface. OTS's transactional emails (secret links, notifications) would need to honor the same branding applied to the web UI.

**Dark mode handling**: Projects that handle dark mode well (Zitadel, Mattermost, Rallly) provide separate color values for each mode rather than relying on inversion or filters.

**Preview before activation**: Zitadel's preview window approach reduces branding deployment anxiety. Operators can see changes before they affect users.

### Where OTS Occupies Distinct Space

**OKLCH-based palette generation**: No surveyed project generates full design system palettes from a single hex input using oklch. The closest comparisons are Figma plugins (Paletto, OK Palette) which are design tools, not runtime systems.

**Perceptual uniformity**: GitLab's token system and Cal.com's flat namespace both use hex values without perceptual correction. OKLCH's lightness consistency across hues is not represented in any surveyed project's color system.

**44-shade generation**: The surveyed projects that offer color customization typically expose 4-10 color slots (Zitadel: 4, Rallly: 2 primaries, Mattermost: ~15 theme values). A system that generates 44 shades from a single input occupies different territory.

---

## 6. Opportunities

### Unoccupied Space

**Programmatic palette generation for self-hosted software**: Design tools (Figma plugins) generate palettes. SaaS platforms (Coolify fork, various) add white-labeling. No surveyed project combines runtime palette generation with self-hosted deployment.

**OKLCH in production theming**: OKLCH adoption is concentrated in design tooling and CSS authoring. Runtime theming systems still use hex or HSL.

**Single-input color systems**: Operators currently choose individual colors for each slot. A system that derives a coherent palette from one brand color input reduces configuration burden and ensures color harmony.

### Integration Patterns

**Stats API model (Plausible)**: Exposes data for operators to build their own dashboards. Applicable to OTS's potential B2B reporting features.

**Two-level branding (Zitadel)**: Instance defaults with organization overrides. Directly relevant to OTS's multi-tenant architecture exploration.

**Theme inheritance (Keycloak)**: Base theme provides defaults, custom themes override specific files. Reduces maintenance burden when upstream changes.

---

## 7. Ecosystem Trends

### Design Token Adoption

GitLab's Pajamas system represents the mature end of design token implementation: 200-400 tokens, three-tier hierarchy, multiple output formats, Figma sync exploration. This investment is oriented toward internal consistency across a large application surface, not external customization.

The design token movement has not yet reached the "expose tokens via API for operator customization" stage in any surveyed project. GitLab's Appearance API exposes logos and text, not token overrides. No feature request for this capability was found.

### CSS Variable Migration

Mattermost's `changeCSS()` migration (issue #16028) represents a common pattern: moving from JavaScript-based style manipulation to CSS custom properties. The migration enables theming without JavaScript execution, improves performance, and aligns with browser capabilities.

Projects earlier in this migration (or not undertaking it) face limitations in what theming can achieve without page reload.

### White-Label as Product Tier

Rallly's January 2026 addition of white-labeling as an enterprise add-on follows a pattern: simple open-source tools adding premium branding features. This indicates that white-labeling is becoming an expected capability in the self-hosted space, particularly for tools operators deploy for their own users.

### Trust-Sensitive Applications

Identity providers (Zitadel, Keycloak) and secret-sharing tools occupy similar trust territory. Both require users to enter sensitive information. Both benefit from branded experiences that reduce "is this legitimate?" friction.

Zitadel's approach (comprehensive branding including fonts, preview capability, org-level overrides) may be more directly applicable to OTS than general-purpose application theming patterns.

---

## 8. Strategic Implications

### Parity Baselines

**Runtime configuration**: Operator experience across surveyed projects shows that source modification creates support burden. A configuration surface (environment variables, admin UI, or both) is baseline expectation.

**Light/dark mode**: Projects that don't handle both modes create work for operators or produce inconsistent experiences. Providing separate slots or deriving one from the other both appear in the landscape.

**Email branding**: Transactional email is a branding surface. Projects that handle this well (Documenso, Zitadel) include it in the same configuration flow as web UI branding.

### Distinguishing Characteristics

**Palette generation depth**: 44 shades from single input vs. 4-15 manual color slots represents a different design approach. The question is whether operators want "give me one color and derive everything" or "let me control each slot."

**Color science approach**: OKLCH's perceptual uniformity is a technical distinction with uncertain operator value. Operators may not notice or care about lightness consistency across hues. The value may be more apparent in accessibility contexts (contrast ratios) than general aesthetics.

**Configuration simplicity**: The tradeoff between "simple: one input" and "flexible: many inputs" appears throughout the landscape. OTS occupies the simple end (single brand color) with escape hatches (override specific shades).

### Architecture Considerations

**Multi-tenant branding**: Zitadel's instance-default-plus-org-override pattern aligns with OTS's multi-tenant exploration. The branding system architecture would need to support inheritance and override at the organization level.

**Token output formats**: If OTS generates tokens, the output format matters for integration. CSS custom properties are the baseline. Tailwind v4's `@theme` directive compatibility would be relevant for the OTS codebase specifically.

---

## Appendix: Research Gaps

The following areas require hands-on testing:

1. **Deployment timing**: How long does it take to apply branding changes for each project?
2. **Email client rendering**: Do branded emails render correctly across Outlook, Gmail, Apple Mail?
3. **Mobile breakpoints**: How does each project's branding behave at mobile widths?
4. **Configuration surface counts**: Exact number of configurable parameters for each project
5. **OKLCH-generated color behavior**: Testing whether oklch palettes produce better results than hex-based systems in actual deployments

### Source References

GitLab Appearance API, Pajamas design token documentation, Mattermost issue #16028 and related PRs, Cal.com self-hosting documentation, Chatwoot developer FAQ and community forks, Documenso branding documentation, Plausible embed and Stats API documentation, Outline hosting documentation, Rallly v4.6.0 changelog and white-labeling documentation, Zitadel brand customization guide, Keycloak theme development documentation.
