# Test Cases: Issue #2114 - Interaction Modes Architecture

**Related Issue:** [#2114](https://github.com/onetimesecret/onetimesecret/issues/2114)
**Feature:** useSecretContext() and useDashboardMode() composables
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

### OTS-2114-SC-003: AUTH_RECIPIENT views someone else's secret

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
| 8 | Observe marketing area | - | NO marketing upsell displayed |
| 9 | Observe header | - | Dashboard link visible (not signup CTA) |

**Post-conditions:**
- Account B can view/reveal the secret normally

**Notes:**
- Tests `actorRole === 'AUTH_RECIPIENT'`
- Maps to `uiConfig.showMarketingUpsell === false`

---

### OTS-2114-SC-004: ANON_RECIPIENT views secret without login

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
| 4 | Observe marketing area | - | Marketing upsell/signup prompt visible |
| 5 | Observe header | - | Signup CTA visible (not dashboard link) |
| 6 | Click "View Secret" | - | Secret content revealed |
| 7 | Observe burn control | - | NO burn button visible |

**Post-conditions:**
- Anonymous user viewed secret successfully
- Marketing messaging was displayed

**Notes:**
- Tests `actorRole === 'ANON_RECIPIENT'`
- Maps to `uiConfig.showMarketingUpsell === true`, `uiConfig.headerAction === 'SIGNUP_CTA'`

---

## Suite: Dashboard Mode - Variant Selection

Tests for `useDashboardMode()` composable that determines which dashboard variant to display.

### OTS-2114-DM-001: Loading state displays basic dashboard

**Priority:** Medium
**Severity:** Minor
**Type:** UI/UX
**Automation Status:** To be automated

**Pre-conditions:**
- User is logged in
- Network is throttled or teams API is slow

**Steps:**
| # | Action | Data | Expected Result |
|---|--------|------|-----------------|
| 1 | Open browser DevTools | - | DevTools panel opens |
| 2 | Go to Network tab | - | Network panel visible |
| 3 | Enable throttling | "Slow 3G" preset | Throttling active |
| 4 | Navigate to /dashboard | - | Page starts loading |
| 5 | Observe initial render | - | DashboardBasic displays while teams load |
| 6 | Wait for load complete | - | Correct variant renders based on team count |

**Post-conditions:**
- No layout flash or jarring transition
- Final variant matches user's team state

**Notes:**
- Tests `variant === 'loading'` state
- Prevents empty/broken UI during data fetch

---

### OTS-2114-DM-002: Basic variant for users without team capability

**Priority:** High
**Severity:** Major
**Type:** Functional
**Automation Status:** To be automated

**Pre-conditions:**
- User account exists without team management capability
- User is on a free/basic plan that doesn't include teams

**Steps:**
| # | Action | Data | Expected Result |
|---|--------|------|-----------------|
| 1 | Log in with basic account | Free tier credentials | Dashboard loads |
| 2 | Navigate to /dashboard | - | DashboardBasic renders |
| 3 | Observe page content | - | Secret creation form visible |
| 4 | Observe teams section | - | NO teams section displayed |
| 5 | Look for upgrade prompt | - | May show upgrade CTA for team features |

**Post-conditions:**
- User can create secrets
- Team features are not shown

**Notes:**
- Tests `variant === 'basic'` when `hasTeamCapability === false`
- Applies to free tier users

---

### OTS-2114-DM-003: Empty variant for users with capability but no teams

**Priority:** High
**Severity:** Major
**Type:** Functional
**Automation Status:** To be automated

**Pre-conditions:**
- User account has team capability (paid plan or standalone mode)
- User has NOT created any teams yet

**Steps:**
| # | Action | Data | Expected Result |
|---|--------|------|-----------------|
| 1 | Log in with capable account | Paid tier credentials | Dashboard loads |
| 2 | Ensure no teams exist | Delete teams if any | Team count is 0 |
| 3 | Navigate to /dashboard | - | DashboardEmpty renders |
| 4 | Observe onboarding content | - | Prompt to create first team visible |
| 5 | Look for "Create Team" CTA | - | Create team button/link present |

**Post-conditions:**
- User is encouraged to create their first team
- Onboarding experience is clear

**Notes:**
- Tests `variant === 'empty'` when `teamCount === 0`
- First-run experience for team-capable users

---

### OTS-2114-DM-004: Single variant for users with exactly one team

**Priority:** High
**Severity:** Major
**Type:** Functional
**Automation Status:** To be automated

**Pre-conditions:**
- User account has team capability
- User has exactly ONE team

**Steps:**
| # | Action | Data | Expected Result |
|---|--------|------|-----------------|
| 1 | Log in with account | Valid credentials | Dashboard loads |
| 2 | Ensure exactly 1 team exists | Create/delete as needed | Team count is 1 |
| 3 | Navigate to /dashboard | - | SingleTeamDashboard renders |
| 4 | Observe team display | - | Single team prominently displayed |
| 5 | Observe quick actions | - | Team-specific actions readily available |

**Post-conditions:**
- Focused UX for single-team workflow
- Quick access to team functions

**Notes:**
- Tests `variant === 'single'` when `teamCount === 1`
- Streamlined experience for solo team users

---

### OTS-2114-DM-005: Multi variant for users with multiple teams

**Priority:** High
**Severity:** Major
**Type:** Functional
**Automation Status:** To be automated

**Pre-conditions:**
- User account has team capability
- User has TWO or more teams

**Steps:**
| # | Action | Data | Expected Result |
|---|--------|------|-----------------|
| 1 | Log in with account | Valid credentials | Dashboard loads |
| 2 | Ensure 2+ teams exist | Create additional if needed | Team count >= 2 |
| 3 | Navigate to /dashboard | - | DashboardIndex renders |
| 4 | Observe team grid | - | Multiple team cards displayed (up to 4) |
| 5 | Look for "View all" link | - | Link to full teams list visible |
| 6 | Click a team card | - | Navigates to team view |

**Post-conditions:**
- User can quickly access any team
- Full team list accessible via "View all"

**Notes:**
- Tests `variant === 'multi'` when `teamCount >= 2`
- Hub experience for power users

---

### OTS-2114-DM-006: Error state with retry functionality

**Priority:** Medium
**Severity:** Major
**Type:** Error Handling
**Automation Status:** To be automated

**Pre-conditions:**
- User is logged in with team capability
- Network or API can be blocked

**Steps:**
| # | Action | Data | Expected Result |
|---|--------|------|-----------------|
| 1 | Open browser DevTools | - | DevTools opens |
| 2 | Go to Network tab | - | Network panel visible |
| 3 | Block teams API request | Block URL pattern: */api/*/teams* | Request will fail |
| 4 | Navigate to /dashboard | - | Teams API call fails |
| 5 | Observe error state | - | Error message: "Unable to load teams" |
| 6 | Observe retry button | - | "Try again" button visible |
| 7 | Unblock API request | Remove block rule | API accessible again |
| 8 | Click "Try again" | - | Teams load successfully |
| 9 | Observe dashboard | - | Correct variant now displays |

**Post-conditions:**
- Error is recoverable without page refresh
- User understands what went wrong

**Notes:**
- Tests error handling and retry mechanism
- Critical for resilient UX

---

## Verification Commands

```bash
# Verify useSecretContext integration
grep -r "useSecretContext" src/apps/secret/
grep -r "actorRole" src/apps/secret/reveal/

# Verify DashboardContainer removal
grep -r "DashboardContainer" src/
# Should return NO results

# Verify useDashboardMode integration
grep -r "useDashboardMode" src/apps/workspace/
grep "DashboardMain" src/apps/workspace/routes/dashboard.ts
```

---

## Playwright Automation Notes

### Suggested Test File Structure

```
tests/e2e/
├── secret-context/
│   ├── creator-role.spec.ts      # OTS-2114-SC-001, OTS-2114-SC-002
│   ├── auth-recipient.spec.ts    # OTS-2114-SC-003
│   └── anon-recipient.spec.ts    # OTS-2114-SC-004
└── dashboard-mode/
    ├── variant-selection.spec.ts # OTS-2114-DM-002 through OTS-2114-DM-005
    ├── loading-state.spec.ts     # OTS-2114-DM-001
    └── error-handling.spec.ts    # OTS-2114-DM-006
```

### Test Data Requirements

| Requirement | Setup Method |
|-------------|--------------|
| Multiple user accounts | Test fixtures or API seeding |
| User with no team capability | Free tier account |
| User with 0 teams | Delete teams via API |
| User with 1 team | Seed exactly 1 team |
| User with 2+ teams | Seed multiple teams |
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
    ├── Suite: Secret Context - Actor Roles
    │   ├── OTS-2114-SC-001
    │   ├── OTS-2114-SC-002
    │   ├── OTS-2114-SC-003
    │   └── OTS-2114-SC-004
    └── Suite: Dashboard Mode - Variant Selection
        ├── OTS-2114-DM-001
        ├── OTS-2114-DM-002
        ├── OTS-2114-DM-003
        ├── OTS-2114-DM-004
        ├── OTS-2114-DM-005
        └── OTS-2114-DM-006
```
