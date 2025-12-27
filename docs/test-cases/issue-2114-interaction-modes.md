# Test Cases: Issue #2114 - Interaction Modes Architecture

**Related Issue:** [#2114](https://github.com/onetimesecret/onetimesecret/issues/2114)
**Feature:** useSecretContext() composable
**Created:** 2024-12-11
**Automation Status:** To be automated (Playwright)

---

## Suite: Secret Context - Actor Roles

Tests for `useSecretContext()` composable that determines UI configuration based on viewer identity.

### OTS-2114-SC-001: CREATOR views own secret (pre-reveal)

**Priority:** High
**Severity:** Major
**Type:** Functional
**Automation Status:** To be automated

**Pre-conditions:**
- User is logged into their account
- User has created at least one secret

**Steps:**
| # | Action | Data | Expected Result |
|---|--------|------|-----------------|
| 1 | Log in to account | Valid credentials | Dashboard loads |
| 2 | Create a new secret | Any content, no passphrase | Secret created, link displayed |
| 3 | Copy secret link | - | Link copied to clipboard |
| 4 | Open secret link in same browser | Same session | Secret confirmation page loads |
| 5 | Observe page alerts | - | Yellow warning banner displays: "You created this secret" |
| 6 | Observe header area | - | Dashboard link visible (not signup CTA) |

**Post-conditions:**
- Secret remains unviewed (still requires confirmation)
- Warning banner can be dismissed

**Notes:**
- Tests `actorRole === 'CREATOR'` before reveal
- Maps to `uiConfig.headerAction === 'DASHBOARD_LINK'`

---

### OTS-2114-SC-002: CREATOR views own secret (post-reveal)

**Priority:** High
**Severity:** Major
**Type:** Functional
**Automation Status:** To be automated

**Pre-conditions:**
- User is logged into their account
- User has secret link they created

**Steps:**
| # | Action | Data | Expected Result |
|---|--------|------|-----------------|
| 1 | Navigate to own secret link | Secret URL | Confirmation page loads |
| 2 | Click "View Secret" button | - | Secret content revealed |
| 3 | Observe page alerts | - | Brand-colored notice: "You viewed your own secret" |
| 4 | Observe burn control | - | Burn button is visible and functional |

**Post-conditions:**
- Secret is now burned (one-time view consumed)
- User can dismiss the notification

**Notes:**
- Tests `actorRole === 'CREATOR'` after reveal
- Maps to `uiConfig.showBurnControl === true`

---

### OTS-2114-SC-003: RECIPIENT_AUTH views someone else's secret

**Priority:** High
**Severity:** Major
**Type:** Functional
**Automation Status:** To be automated

**Pre-conditions:**
- Two user accounts exist (Account A, Account B)
- Account A has created a secret

**Steps:**
| # | Action | Data | Expected Result |
|---|--------|------|-----------------|
| 1 | Log in as Account A | Valid credentials | Dashboard loads |
| 2 | Create a new secret | Any content | Secret link displayed |
| 3 | Copy secret link | - | Link copied |
| 4 | Log out | - | Logged out successfully |
| 5 | Log in as Account B | Different account | Dashboard loads |
| 6 | Navigate to secret link | Copied URL | Secret confirmation page loads |
| 7 | Observe page alerts | - | NO owner warning banner displayed |
| 8 | Observe marketing area | - | NO capabilities upgrade displayed |
| 9 | Observe header | - | Dashboard link visible (not signup CTA) |

**Post-conditions:**
- Account B can view/reveal the secret normally

**Notes:**
- Tests `actorRole === 'RECIPIENT_AUTH'`
- Maps to `uiConfig.showCapabilitiesUpgrade === false`

---

### OTS-2114-SC-004: RECIPIENT_ANON views secret without login

**Priority:** High
**Severity:** Major
**Type:** Functional
**Automation Status:** To be automated

**Pre-conditions:**
- A secret has been created (by any user)
- Secret link is available

**Steps:**
| # | Action | Data | Expected Result |
|---|--------|------|-----------------|
| 1 | Open incognito/private browser window | - | Clean session, not logged in |
| 2 | Navigate to secret link | Secret URL | Secret confirmation page loads |
| 3 | Observe page alerts | - | NO owner warning banner displayed |
| 4 | Observe marketing area | - | Capabilities upgrade/signup prompt visible |
| 5 | Observe header | - | Signup CTA visible (not dashboard link) |
| 6 | Click "View Secret" | - | Secret content revealed |
| 7 | Observe burn control | - | NO burn button visible |

**Post-conditions:**
- Anonymous user viewed secret successfully
- Marketing messaging was displayed

**Notes:**
- Tests `actorRole === 'RECIPIENT_ANON'`
- Maps to `uiConfig.showCapabilitiesUpgrade === true`, `uiConfig.headerAction === 'SIGNUP_CTA'`

---

## Verification Commands

```bash
# Verify useSecretContext integration
grep -r "useSecretContext" src/apps/secret/
grep -r "actorRole" src/apps/secret/reveal/
```

---

## Playwright Automation Notes

### Suggested Test File Structure

```
tests/e2e/
└── secret-context/
    ├── creator-role.spec.ts      # OTS-2114-SC-001, OTS-2114-SC-002
    ├── auth-recipient.spec.ts    # OTS-2114-SC-003
    └── anon-recipient.spec.ts    # OTS-2114-SC-004
```

### Test Data Requirements

| Requirement | Setup Method |
|-------------|--------------|
| Multiple user accounts | Test fixtures or API seeding |
| Network blocking | Playwright route interception |

### Qase Integration

When automating these tests, link to Qase cases:

```typescript
import { test } from '@playwright/test';
import { qase } from 'playwright-qase-reporter';

test(qase('OTS-2114-SC-001', 'CREATOR views own secret (pre-reveal)'), async ({ page }) => {
  // Implementation
});
```

---

## Import to Qase

These test cases can be imported to Qase via:

1. **Manual entry:** Copy each test case into Qase UI
2. **CSV import:** Convert this markdown to CSV format
3. **API import:** Use Qase API to bulk create cases

### Suggested Qase Suite Structure

```
Project: OTS (OneTime Secret)
└── Feature: Interaction Modes (#2114)
    └── Suite: Secret Context - Actor Roles
        ├── OTS-2114-SC-001
        ├── OTS-2114-SC-002
        ├── OTS-2114-SC-003
        └── OTS-2114-SC-004
```
