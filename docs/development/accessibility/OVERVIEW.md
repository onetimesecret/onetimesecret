# Accessibility Overview

## Introduction

Onetime Secret is a privacy tool that helps you securely share sensitive information like passwords or private messages. The key principle is simple: when someone shares a secret, it can be viewed exactly once before being instantly and permanently deleted. This prevents sensitive data from lingering in email, chat logs, or other communication systems.

The service is available in two forms. First, there's the free and open-source project that anyone can use at onetimesecret.com or install on their own servers. The project follows an open-source first development model, meaning new features are built for and tested in the open-source version before being added to paid services. This ensures that core privacy functionality remains accessible to everyone.

Some organizations choose to use the paid service, which allows them to add their own branding and custom web addresses for sharing secrets. For example, a company's IT help desk might send password reset links that come from secretlink.company.com instead of onetimesecret.com. This helps recipients trust that the links are legitimate since they come from their organization's own domain.

Whether you're using the open-source version or a branded instance, the core experience remains straightforward:
- Click the secret link to view the content
- Enter the passphrase if one was set by the sender
- View the secret, which is then permanently deleted

For those who want to create and share secrets, the interface is designed to be simple and usable without requiring an account. You can enter your secret text, optionally set a passphrase and expiration time, and then share the generated link with your recipient. The service also provides features for more advanced users, like an API for automation, while maintaining its focus on being accessible to everyone who needs to share sensitive information securely.

## Accessibility Features

Onetime Secret focuses on two primary workflows: creating/sharing secrets and receiving secrets. Our accessibility work ensures these core functions are usable by everyone, regardless of how they interact with the platform.

### Recipient Experience

We'll start with the recipient experience. All users benefit from a positive experience when receiving and viewing secrets.

The secret viewing interface incorporates accessibility features to ensure that receiving and viewing secrets is straightforward for all users. Here's how we've enhanced the experience:

#### Semantic HTML Structure
- **Landmarks:** Added `main`, `nav`, and `footer` landmarks to define the structure of the page
- **Heading Levels:** Utilized appropriate heading hierarchies (H1-H6) for clear content organization
- **Role Attributes:** Incorporated necessary `role` attributes to improve document semantics and assistive technology navigation

#### Focus and Keyboard Navigation
- **Descriptive Labels:** Implemented descriptive `aria-label` attributes for interactive elements to provide clear context
- **Live Regions:** Employed `aria-live` regions to announce dynamic content updates to screen readers
- **Toggle States:** Added `aria-pressed` states for toggle buttons to indicate their current status
- **Decorative Elements:** Applied `aria-hidden="true"` to non-essential decorative elements to streamline screen reader output
- **Enhanced Focus Styles:** Improved focus indicators for all interactive elements to ensure visibility
- **Contrast:** Ensured focus indicators maintain sufficient contrast across all color schemes
- **Focus Rings:** Added focus rings with adequate contrast to assist keyboard navigation

#### Screen Reader Support
- **Form Field Labeling and Descriptive Text:** Improved labeling and descriptions for all interactive elements
- **Status Announcements and Dynamic Updates:** Implemented `aria-live` regions to keep users informed of changes and actions

#### Visual Accessibility
- **Dark Mode:** Enhanced text contrast in dark mode to improve readability
- **Alert Messages:** Increased contrast for alert messages to ensure they stand out
- **Brand Colors:** Adjusted brand colors to achieve better visibility and accessibility
- **Disabled States:** Increased opacity of disabled states to clearly distinguish non-interactive elements

### Secret Creation and Management Experience

We've implemented fundamental accessibility features and continue to improve the experience:
- Basic keyboard navigation through all form controls
- Clear error messages that work with screen readers
- Light and dark mode support
- Simple, linear workflow that's easy to follow

### Automated Testing & Enforcement Policy

Accessibility is checked automatically in CI (engine:
[axe-core](https://github.com/dequelabs/axe-core), Deque). Three scans run on
every pull request, with two enforcement tiers:

- **Page-level, public (blocking)** — `e2e/all/accessibility.spec.ts` scans the
  public surfaces in **both light and dark** themes via `@axe-core/playwright`,
  as part of the blocking `e2e/all/` CI gate. Run locally, credential-free,
  with `pnpm test:a11y`.
- **Page-level, authenticated (informational, not yet blocking)** —
  `e2e/full/accessibility.spec.ts` scans the signed-in surfaces the same way,
  in the `full/` CI suite. That suite is mid-remediation and currently runs
  `continue-on-error` (see `.github/workflows/e2e.yml` and
  `e2e/docs/e2e-remediation-plan.md`), so it reports but does not yet gate a
  merge. It needs a signed-in session, so run it locally with test credentials:
  `TEST_USER_EMAIL=… TEST_USER_PASSWORD=… pnpm test:a11y:full`.
- **Component-level (shift-left, blocking)** — `src/tests/shared/a11y/*.a11y.spec.ts`
  run axe in jsdom (via `vitest-axe`) against shared UI primitives on every
  `pnpm test`. (Color-contrast is excluded here — jsdom has no layout — and is
  covered by the page-level layer.)

The policy the layers enforce:

- **Target: WCAG 2.1 Level AA.** Rulesets: `wcag2a wcag2aa wcag21a wcag21aa`
  plus axe `best-practice`.
- **Ratcheting baselines** (`e2e/accessibility-baseline*.json`) hold known,
  tracked debt. A scan fails on any violation **not** in the baseline (a
  regression), and **hard-fails on any new `serious`/`critical`** regardless of
  baseline. Baselines may only **shrink**: fix a violation, then regenerate the
  baseline for the surface you changed — `pnpm test:a11y:update` for the public
  baseline (`e2e/accessibility-baseline.json`), or
  `pnpm test:a11y:full:update` (with test credentials, as above) for the
  authenticated baseline (`e2e/accessibility-baseline.full.json`). Each script
  regenerates only its own baseline. This mirrors the `e2e/QUARANTINE.md`
  convention — tracked, visible, and always shrinking.
- **Ownership** sits with the author of the changed component: a red a11y check
  is a blocking defect, not a follow-up.
- **Brand safety.** Operator brand colors are applied by remapping the brand
  scale (`src/utils/brand-palette.ts`); that generator computes an accessible
  text color per primary (`checkBrandContrast`), unit-tested in
  `src/tests/utils/brand-palette.spec.ts`, so custom-branded instances stay AA.

**Still manual (automation covers ~30–40% of WCAG):** screen-reader passes
(NVDA, VoiceOver, JAWS), keyboard-only navigation, and focus-visibility. We
welcome community contributions on these through discussions and pull requests.
The point-in-time findings and remediation are recorded in
[`architecture/public-surfaces-accessibility-audit.md`](../../architecture/public-surfaces-accessibility-audit.md).

#### Reporting Accessibility Issues
To report accessibility issues or suggest improvements, you can:

1. Open an issue on our GitHub repository
2. Use the feedback form in the application footer
3. Contact our support team through the website

## Final Thoughts

Secure communication should be accessible to everyone. Onetime Secret implements accessibility features following established standards and best practices, focusing on core functionality that lets all users share and receive secrets effectively. We welcome feedback from users to help identify areas where we can improve the platform's accessibility.

Best regards,
Delano
