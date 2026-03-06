# Stripe Billing and Plan-Gated Brand Features: Landscape Analysis for OTS

## 1. Feature Gating Patterns Observed Across Projects Surveyed

**Universally Free (all projects surveyed offer these on free/community tier):**

- Basic color/theme customization (primary brand color)
- Product name in page titles
- Favicon customization

**Typically Gated Behind First Paid Tier ($10-25/mo range):**

- Custom logo upload (replacing default product logo)
- "Powered by X" badge removal or customization
- Custom email sender name
- Basic CSS overrides

**Gated Behind Mid/Premium Tiers ($50-100+/mo):**

- Full private-label (complete removal of vendor identity)
- Custom domains with SSL (the most common premium gate)
- Custom email templates with own branding
- Custom login/auth page branding
- Removal of all product footprint from customer-facing surfaces

**Enterprise-Only (custom pricing):**

- Multi-brand/multi-tenant configurations
- Brand API access (programmatic brand management)
- Custom color palettes per workspace/team
- Co-branding controls for resellers

**The Pattern That Emerges:**
The prevailing pattern across projects surveyed is a 3-tier progression: identity (free) -> presentation (paid) -> invisibility (premium). Users can customize "what it looks like" for free, but removing evidence of "who made it" costs money.

## 2. Pricing Tier Alignment with OTS Plan Structure

Mapping to OTS's existing tiers:

|               Brand Feature | Free | Identity Plus |  Team Plus   | Org Plus/Max |
| --------------------------: | :--: | :-----------: | :----------: | :----------: |
|         Primary brand color | Yes  |      Yes      |     Yes      |     Yes      |
|       Product name override |  No  |      Yes      |     Yes      |     Yes      |
|                 Custom logo |  No  |      Yes      |     Yes      |     Yes      |
|    "Powered by OTS" removal |  No  |      No       |     Yes      |     Yes      |
|      Custom domain branding |  No  |      No       |     Yes      |     Yes      |
|          White-label emails |  No  |      No       |      No      |     Yes      |
|       allow_public_homepage |  No  |      No       | Configurable |     Yes      |
|            allow_public_api |  No  |   Yes (own)   |  Yes (own)   |  Yes (full)  |
| Multi-domain brand profiles |  No  |      No       |      No      |     Yes      |

**Rationale:**

- Free tier gets basic color to feel ownership, but OTS branding stays prominent
- Identity Plus gets enough to feel like "theirs" (logo, name) but OTS is still visible
- Team Plus gets the features that matter for professional appearance (custom domains, badge removal)
- Org tiers get full brand control including email templates and multi-brand

**Pricing note:** No project surveyed successfully gates primary color customization behind a paywall. Those that attempted it observed negative user sentiment. Color customization is table stakes for user buy-in across the landscape.

## 3. Stripe Checkout/Portal Branding Considerations

**How other projects handle Stripe Checkout branding:**

Most projects surveyed do NOT attempt to private-label Stripe Checkout itself. Stripe's Checkout and Customer Portal have their own branding controls (set in Stripe Dashboard under Settings > Branding), and these are account-wide, not per-customer.

**Key observations:**

- Stripe Checkout Session branding is account-level. You cannot dynamically change the logo/colors per customer in a Checkout Session. The branding settings in Stripe Dashboard apply to all sessions.
- For OTS specifically: Since OTS is a single Stripe account serving multiple end-users, the Checkout page will always show OTS's branding (or whatever is configured in OTS's Stripe account).
- Customer Portal has the same constraint -- account-level branding only.
- Other projects' approach: They accept this limitation. The Checkout page shows the vendor brand, not the customer's custom brand. Some add messaging like "You are subscribing to [ProductName] via [VendorName]" to bridge the brand gap.

**Implications for OTS:**

- Configure Stripe Dashboard branding to match OTS's primary brand
- White-labeled checkout is not viable for customers -- Stripe does not support per-session branding
- If a future Stripe Connect scenario arises (reseller/marketplace model), then each connected account could have its own Stripe branding -- but that is a fundamentally different architecture

**Observed anti-pattern:** Attempting to iframe or proxy Stripe Checkout to apply custom CSS. This violates Stripe's ToS and PCI compliance requirements. No project surveyed takes this approach.

## 4. Entitlement Enforcement: Frontend vs Backend

**How other projects enforce plan-gated brand features:**

|                                    Approach |                     Who Uses It |                                                   Tradeoffs |
| ------------------------------------------: | ------------------------------: | ----------------------------------------------------------: |
|              Frontend-only gating (hide UI) | Small OSS projects, early-stage | Trivially bypassed in self-hosted; adequate for hosted-only |
|    Backend-validated (check plan on render) |       Chatwoot, Cal.com, GitLab |    Correct for hosted service; adds latency to page renders |
| Hybrid (frontend hides + backend validates) |                Most mature SaaS |                                            Defense in depth |
|    Config-file based (self-hosted override) |             Plausible, Metabase |                 Acknowledges self-hosted reality gracefully |

**Observed consensus among mature projects:**

Backend validation is the prevailing approach for hosted services. The enforcement chain typically follows:

1. Stripe product metadata defines capabilities (source of truth)
2. Billing::Plan cache in Redis holds capability sets
3. Backend serializer checks customer's plan capabilities before including brand settings in the response
4. Frontend respects the serialized data (does not render controls for unavailable features)
5. Render path validates plan capability before applying custom brand to public-facing pages

**Specific to OTS's architecture:**

- ConfigSerializer already flows brand_primary_color and brand_product_name to frontend
- Adding capability checks in the serializer follows the prevailing pattern: if the customer's plan does not include custom_branding, serialize default values instead of custom ones
- For allow_public_homepage and allow_public_api: these control access to actual infrastructure endpoints and require backend enforcement in every project surveyed
- Custom domain brand_settings validation at the domain-configuration endpoint -- rejecting brand customization requests for domains on plans without the custom_domain_branding capability -- matches the approach taken by Cal.com and GitLab

**Capability metadata fields observed across projects (mapped to Stripe products):**

- custom_branding: true/false
- custom_domain_branding: true/false
- white_label: true/false
- allow_public_homepage: true/false
- allow_public_api: true/false

## 5. Upgrade Prompts: UX Patterns for Brand Customization

**Patterns observed across projects surveyed:**

**Pattern A: "Ghost Preview"**
Show the brand customization UI to all users, let them configure it, but apply a "Preview only - upgrade to apply" overlay. Users invest effort in customization, creating sunk-cost motivation to upgrade.

- Cal.com, Chatwoot use this approach
- Reported conversion rates 2-3x higher than hidden features

**Pattern B: "Locked with Peek"**
Show the feature in the settings sidebar with a lock icon and the tier name. Clicking opens an upgrade prompt with a screenshot of what the feature looks like configured.

- GitLab, Sentry use this approach
- Lower friction than Pattern A but less user investment

**Pattern C: "Branded Upgrade CTA"**
On the secret sharing page itself, show "Customize this page's appearance" link that leads to the upgrade flow. The CTA appears in context where the user is actually experiencing the default branding.

- Relevant for OTS because users see the secret page frequently

**Pattern D: "Degraded Experience Reminder"**
After downgrade, show "Your custom branding has been saved but is not active on your current plan" with a re-upgrade prompt. Never delete saved brand settings on downgrade.

- Every project surveyed preserves brand settings across plan changes
- Stripe metadata: store the settings even when the plan does not authorize rendering them

**How this maps to OTS:**
Patterns A and D together align with OTS's existing architecture. All users configure brand settings (stored in Redis regardless of plan). Settings are applied to public pages only when the plan authorizes it. On downgrade, settings persist: "Your branding is saved and will be reactivated when you upgrade."

This fits the existing architecture where BrandSettingsConstants.defaults is separate from the plan-gated rendering decision.

## 6. Self-Hosted vs Hosted: The Open Source Tension

**The core tension:**
OTS is open source. Anyone can fork the code and remove branding restrictions. Gating brand features in a paid plan only works for the hosted service. Self-hosted users can (and will) modify the code.

**How other projects handle this:**

|   Project | Approach                                   |                                                                    Outcome |
| --------: | ------------------------------------------ | -------------------------------------------------------------------------: |
|    GitLab | Brand features in EE (proprietary license) |               Clear boundary; CE users cannot easily get EE brand features |
| Plausible | AGPL + hosted-only premium features        |                       Self-hosted gets everything; hosted gets convenience |
|   Cal.com | "Cal.com Platform" license for private-label | Self-hosted gets basic brand; full private-label requires commercial license |
|  Chatwoot | Feature flags + hosted-only enforcement    |                  Self-hosted can toggle flags but features may be degraded |
|  Metabase | OSS vs Pro editions (separate builds)      |                     OSS has no private-label; Pro has it via separate binary |
|    Sentry | BSL (Business Source License)              |                        Prevents other projects from offering hosted Sentry |
| Discourse | Hosted-only premium themes + enterprise    |              Self-hosted gets basic themes; premium themes are hosted-only |

**Patterns observed that apply to OTS:**

1. Accept the reality. Self-hosted users who modify the code are not the audience for brand feature gating. No project surveyed invests in DRM or obfuscation -- it damages trust and wastes engineering time.
2. Make the hosted value proposition about convenience, not restriction. Brand settings that "just work" with automatic SSL, domain verification, email deliverability, and Stripe billing integration are worth paying for even when the code is open.
3. Backend enforcement on hosted. The allow_public_homepage and allow_public_api flags are infrastructure-level controls that only matter on the hosted service. Self-hosted operators control their own infrastructure anyway.
4. Configuration vs code. Storing brand feature flags in the config file (config.defaults.yaml under branding:) with defaults that enable everything for self-hosted is the prevailing approach. The hosted service overrides these defaults via environment/config to enforce plan gating.
5. License consideration. If full private-label is a significant revenue driver, a dual-license model where the brand customization system specifically is under a more restrictive license is an option observed in the ecosystem (Cal.com, Metabase). This is a business decision, not a technical one.

**How this maps to OTS's architecture:**
The existing architecture with branding: in config.defaults.yaml already supports this pattern. Self-hosted users set their own brand config freely. The hosted service reads plan capabilities from Stripe to determine which brand settings to honor. The code path is:

- Self-hosted: config.yaml -> brand settings applied unconditionally
- Hosted: config.yaml -> Stripe plan check -> brand settings applied conditionally

The OT.conf -> BrandSettingsConstants.defaults -> ConfigSerializer chain already provides the right injection point for plan-gated enforcement.

---

### Summary of Cautions

1. Gating basic color customization generates disproportionate negative sentiment relative to revenue. No project surveyed does this successfully.
2. White-labeled Stripe Checkout is not technically possible with Stripe's current API without a Connect architecture change. No project surveyed offers this.
3. Frontend-only enforcement for allow_public_homepage and allow_public_api is insufficient. These control real access and require backend validation against plan capabilities, as observed across all mature projects surveyed.
4. Deleting brand settings on downgrade is an anti-pattern across the landscape. Preserving them in Redis/config and suppressing rendering is both a better UX and a re-upgrade incentive.
5. Fighting self-hosted customization is unproductive. The hosted service derives value from integration quality (SSL, domains, email, billing), not from artificial code restrictions.
6. Adding brand capabilities to Stripe metadata piecemeal creates migration debt. The full capability schema (custom_branding, custom_domain_branding, white_label, allow_public_homepage, allow_public_api) is better designed and deployed as a unit.
7. allow_public_homepage is an access control feature that happens to intersect with branding. The conceptual separation should remain clean in both the Stripe metadata schema and the enforcement code. Access controls and brand controls are separate capability categories even when checked together at render time.
