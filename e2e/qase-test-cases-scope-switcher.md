# Qase Test Cases: Scope Switcher UX

## Suite: Scope Switcher - Organization and Domain Context Switching

### Overview

This test suite covers the Organization and Domain Scope Switcher components that allow users to switch context within the workspace application.

**Visibility Rules Matrix:**

| Page                     | Org Switcher | Domain Switcher |
|--------------------------|--------------|-----------------|
| Dashboard                | show         | show            |
| Secret creation          | show         | show            |
| Org settings /org/:extid | locked       | hide            |
| Domains list /domains    | show         | show            |
| Domain detail            | show         | locked          |
| Billing /billing/*       | locked       | hide            |
| Account /account/*       | hide         | hide            |

**States:**
- `show`: Visible and interactive
- `locked`: Visible but disabled (shows current, cannot switch)
- `hide`: Not rendered

---

## Section 1: Visibility Rules

### TC-SS-001: Dashboard - Organization Switcher Visible

**Priority:** High
**Automation Status:** Automated
**Qase ID:** TC-SS-001

**Preconditions:**
- User is authenticated
- User has at least one organization

**Steps:**
1. Navigate to /dashboard
2. Wait for page to fully load
3. Locate the organization switcher in the header

**Expected Results:**
- Organization switcher is visible
- Current organization name is displayed
- Switcher is interactive (not disabled)
- Dropdown chevron is visible

---

### TC-SS-002: Dashboard - Domain Switcher Visible

**Priority:** High
**Automation Status:** Automated
**Qase ID:** TC-SS-002

**Preconditions:**
- User is authenticated
- User has custom domains enabled (domains_enabled: true)
- User has at least one custom domain

**Steps:**
1. Navigate to /dashboard
2. Wait for page to fully load
3. Locate the domain switcher in the header

**Expected Results:**
- Domain switcher is visible
- Current domain scope is displayed
- Switcher is interactive (not disabled)

**Notes:**
- If user has no custom domains, domain switcher should be hidden (not an error)

---

### TC-SS-003: Secret Creation - Organization Switcher Visible

**Priority:** High
**Automation Status:** Automated
**Qase ID:** TC-SS-003

**Preconditions:**
- User is authenticated

**Steps:**
1. Navigate to / (secret creation page)
2. Wait for page to fully load
3. Locate the organization switcher

**Expected Results:**
- Organization switcher is visible in the header
- Current organization is displayed
- Switcher is interactive

---

### TC-SS-004: Secret Creation - Domain Switcher Visible

**Priority:** High
**Automation Status:** Automated
**Qase ID:** TC-SS-004

**Preconditions:**
- User is authenticated
- User has custom domains

**Steps:**
1. Navigate to / (secret creation page)
2. Wait for page to fully load
3. Locate the domain switcher

**Expected Results:**
- Domain switcher is visible (if user has domains)
- Current scope is displayed
- Secrets created will use the selected domain context

---

### TC-SS-005: Org Settings - Organization Switcher Locked

**Priority:** High
**Automation Status:** Automated
**Qase ID:** TC-SS-005

**Preconditions:**
- User is authenticated
- User has organization with extid

**Steps:**
1. Navigate to /org/:extid (organization settings)
2. Wait for page to fully load
3. Locate the organization switcher
4. Attempt to click the switcher

**Expected Results:**
- Organization switcher is visible
- Current organization name is displayed
- Switcher is disabled/locked (cursor: not-allowed, opacity reduced)
- Clicking does not open dropdown
- Has aria-disabled="true" for accessibility

---

### TC-SS-006: Org Settings - Domain Switcher Hidden

**Priority:** High
**Automation Status:** Automated
**Qase ID:** TC-SS-006

**Preconditions:**
- User is authenticated
- User is on organization settings page

**Steps:**
1. Navigate to /org/:extid
2. Wait for page to fully load
3. Search for domain switcher in the header

**Expected Results:**
- Domain switcher is NOT visible
- No placeholder or disabled version shown

---

### TC-SS-007: Domains List - Organization Switcher Visible

**Priority:** Medium
**Automation Status:** Automated
**Qase ID:** TC-SS-007

**Preconditions:**
- User is authenticated

**Steps:**
1. Navigate to /domains
2. Wait for page to fully load
3. Locate the organization switcher

**Expected Results:**
- Organization switcher is visible
- Switcher is interactive (can switch organizations)
- Switching organizations updates the domains list

---

### TC-SS-008: Domains List - Domain Switcher Visible

**Priority:** Medium
**Automation Status:** Automated
**Qase ID:** TC-SS-008

**Preconditions:**
- User is authenticated
- User has custom domains

**Steps:**
1. Navigate to /domains
2. Wait for page to fully load
3. Locate the domain switcher

**Expected Results:**
- Domain switcher is visible
- Switcher is interactive

---

### TC-SS-009: Domain Detail - Organization Switcher Visible

**Priority:** Medium
**Automation Status:** Automated
**Qase ID:** TC-SS-009

**Preconditions:**
- User is authenticated
- User has at least one custom domain

**Steps:**
1. Navigate to /domains/:extid/brand
2. Wait for page to fully load
3. Locate the organization switcher

**Expected Results:**
- Organization switcher is visible
- Switcher is interactive

---

### TC-SS-010: Domain Detail - Domain Switcher Locked

**Priority:** High
**Automation Status:** Automated
**Qase ID:** TC-SS-010

**Preconditions:**
- User is authenticated
- User is viewing a specific domain's settings

**Steps:**
1. Navigate to /domains/:extid/brand
2. Wait for page to fully load
3. Locate the domain switcher
4. Attempt to click the switcher

**Expected Results:**
- Domain switcher is visible
- Current domain is displayed
- Switcher is disabled/locked
- Clicking does not open dropdown

---

### TC-SS-011: Billing - Organization Switcher Locked

**Priority:** High
**Automation Status:** Automated
**Qase ID:** TC-SS-011

**Preconditions:**
- User is authenticated

**Steps:**
1. Navigate to /billing/overview
2. Wait for page to fully load
3. Locate the organization switcher
4. Attempt to interact with it

**Expected Results:**
- Organization switcher is visible
- Shows current organization
- Switcher is disabled/locked
- Billing context is tied to current organization

---

### TC-SS-012: Billing - Domain Switcher Hidden

**Priority:** High
**Automation Status:** Automated
**Qase ID:** TC-SS-012

**Preconditions:**
- User is authenticated

**Steps:**
1. Navigate to /billing/overview
2. Wait for page to fully load
3. Search for domain switcher

**Expected Results:**
- Domain switcher is NOT visible
- Billing is organization-scoped, not domain-scoped

---

### TC-SS-015: Account Settings - Organization Switcher Hidden

**Priority:** High
**Automation Status:** Automated
**Qase ID:** TC-SS-015

**Preconditions:**
- User is authenticated

**Steps:**
1. Navigate to /account
2. Wait for page to fully load
3. Search for organization switcher

**Expected Results:**
- Organization switcher is NOT visible
- Account settings are user-scoped, not org-scoped

---

### TC-SS-016: Account Settings - Domain Switcher Hidden

**Priority:** High
**Automation Status:** Automated
**Qase ID:** TC-SS-016

**Preconditions:**
- User is authenticated

**Steps:**
1. Navigate to /account
2. Wait for page to fully load
3. Search for domain switcher

**Expected Results:**
- Domain switcher is NOT visible

---

## Section 2: Switching Behavior

### TC-SS-020: Organization Dropdown Opens on Click

**Priority:** High
**Automation Status:** Automated
**Qase ID:** TC-SS-020

**Preconditions:**
- User is authenticated
- Organization switcher is visible and interactive

**Steps:**
1. Navigate to /dashboard
2. Click the organization switcher trigger button

**Expected Results:**
- Dropdown menu opens with animation
- Menu shows "My Organizations" header
- All user's organizations are listed
- Current organization has checkmark indicator
- Menu has role="menu" for accessibility

---

### TC-SS-021: Current Organization Highlighted in Dropdown

**Priority:** High
**Automation Status:** Automated
**Qase ID:** TC-SS-021

**Preconditions:**
- User is authenticated
- User has multiple organizations

**Steps:**
1. Navigate to /dashboard
2. Click the organization switcher
3. Observe the dropdown items

**Expected Results:**
- Current organization has:
  - Checkmark icon on the right
  - Background highlight (brand-50/brand-900 colors)
  - Font weight: semibold
- Other organizations have normal styling

---

### TC-SS-022: Selecting Different Organization Updates Context

**Priority:** Critical
**Automation Status:** Automated
**Qase ID:** TC-SS-022

**Preconditions:**
- User is authenticated
- User has at least 2 organizations

**Steps:**
1. Navigate to /dashboard
2. Note current organization name
3. Click organization switcher
4. Click a different organization
5. Wait for context to update

**Expected Results:**
- Dropdown closes
- Switcher trigger shows new organization name
- Page content updates to reflect new organization context
- Any organization-scoped data is refreshed
- Domain list updates for new organization

---

### TC-SS-023: Gear Icon Navigates to Organization Settings

**Priority:** High
**Automation Status:** Automated
**Qase ID:** TC-SS-023

**Preconditions:**
- User is authenticated
- Organization has extid (non-default organizations)

**Steps:**
1. Navigate to /dashboard
2. Click organization switcher
3. Hover over an organization row
4. Click the gear (cog) icon that appears

**Expected Results:**
- Gear icon appears on hover
- Clicking gear navigates to /org/:extid
- Organization settings page loads
- Dropdown closes

**Notes:**
- Default (personal) organization may not show gear icon

---

### TC-SS-024: Manage Organizations Link Works

**Priority:** Medium
**Automation Status:** Automated
**Qase ID:** TC-SS-024

**Preconditions:**
- User is authenticated

**Steps:**
1. Navigate to /dashboard
2. Click organization switcher
3. Scroll to bottom of dropdown
4. Click "Manage Organizations" link

**Expected Results:**
- Navigates to /org (organizations list page)
- Dropdown closes
- Organizations management page loads

---

### TC-SS-030: Domain Dropdown Opens on Click

**Priority:** High
**Automation Status:** Automated
**Qase ID:** TC-SS-030

**Preconditions:**
- User is authenticated
- User has custom domains enabled
- User has at least one custom domain

**Steps:**
1. Navigate to /dashboard
2. Click the domain switcher trigger button

**Expected Results:**
- Dropdown menu opens with animation
- Menu shows domain header
- All available domains are listed
- Current domain has checkmark indicator

---

### TC-SS-031: Selecting Different Domain Updates Scope

**Priority:** Critical
**Automation Status:** Automated
**Qase ID:** TC-SS-031

**Preconditions:**
- User is authenticated
- User has multiple domains

**Steps:**
1. Navigate to /dashboard
2. Note current domain
3. Click domain switcher
4. Click a different domain
5. Wait for scope to update

**Expected Results:**
- Dropdown closes
- Switcher trigger shows new domain
- Scope indicator updates
- localStorage domainScope key is updated

---

### TC-SS-032: Domain Scope Persists to localStorage

**Priority:** High
**Automation Status:** Automated
**Qase ID:** TC-SS-032

**Preconditions:**
- User is authenticated
- User has custom domains

**Steps:**
1. Navigate to /dashboard
2. Open domain switcher
3. Select a domain
4. Open browser DevTools > Application > Local Storage

**Expected Results:**
- localStorage contains "domainScope" key
- Value matches selected domain hostname

---

### TC-SS-033: Add Domain Link Navigates

**Priority:** Medium
**Automation Status:** Automated
**Qase ID:** TC-SS-033

**Preconditions:**
- User is authenticated
- User has custom domains feature

**Steps:**
1. Navigate to /dashboard
2. Click domain switcher
3. Click "Add Domain" link at bottom

**Expected Results:**
- Navigates to /domains
- Dropdown closes
- Domains management page loads

---

## Section 3: Locked State Behavior

### TC-SS-040: Locked Org Switcher Not Clickable

**Priority:** High
**Automation Status:** Automated
**Qase ID:** TC-SS-040

**Preconditions:**
- User is authenticated
- User is on a page with locked org switcher (e.g., /billing/overview)

**Steps:**
1. Navigate to /billing/overview
2. Locate the organization switcher
3. Attempt to click the switcher

**Expected Results:**
- Switcher displays current organization name
- Cursor shows not-allowed
- Visual opacity is reduced (muted appearance)
- Clicking has no effect
- No dropdown opens

---

### TC-SS-041: Locked Switcher Has ARIA Attributes

**Priority:** Medium
**Automation Status:** Automated
**Qase ID:** TC-SS-041

**Preconditions:**
- User is on a page with locked switcher

**Steps:**
1. Navigate to /billing/overview
2. Inspect the organization switcher element

**Expected Results:**
- Element has aria-disabled="true" OR disabled attribute
- Screen readers announce the element as disabled
- Keyboard focus behavior is appropriate

---

### TC-SS-042: Locked Domain Switcher Shows Current Domain

**Priority:** High
**Automation Status:** Automated
**Qase ID:** TC-SS-042

**Preconditions:**
- User is authenticated
- User has custom domains
- User is on domain detail page

**Steps:**
1. Navigate to /domains/:extid/brand
2. Locate the domain switcher

**Expected Results:**
- Domain switcher is visible
- Shows the current domain being edited
- Switcher is disabled/locked
- User cannot switch domains while editing

---

## Section 4: Edge Cases

### TC-SS-050: Single Organization User

**Priority:** Medium
**Automation Status:** Automated
**Qase ID:** TC-SS-050

**Preconditions:**
- User is authenticated
- User has only one organization (default)

**Steps:**
1. Navigate to /dashboard
2. Click organization switcher

**Expected Results:**
- Switcher is visible
- Dropdown shows one organization (Personal/default)
- Checkmark indicates current selection
- "Manage Organizations" link still available

---

### TC-SS-051: User Without Custom Domains

**Priority:** High
**Automation Status:** Automated
**Qase ID:** TC-SS-051

**Preconditions:**
- User is authenticated
- User has no custom domains OR domains_enabled is false

**Steps:**
1. Navigate to /dashboard
2. Search for domain switcher

**Expected Results:**
- Domain switcher is NOT visible
- No placeholder or disabled state shown
- Page layout adjusts appropriately

---

### TC-SS-052: Canonical Domain Shows Personal Label

**Priority:** Medium
**Automation Status:** Automated
**Qase ID:** TC-SS-052

**Preconditions:**
- User is authenticated
- User has custom domains
- Canonical domain (onetimesecret.com) is in the list

**Steps:**
1. Navigate to /dashboard
2. Click domain switcher
3. Find the canonical domain option

**Expected Results:**
- Canonical domain shows display_domain label
- Has home icon (vs globe for custom domains)
- Can be selected as scope

---

### TC-SS-053: Keyboard Navigation Works

**Priority:** High
**Automation Status:** Automated
**Qase ID:** TC-SS-053

**Preconditions:**
- User is authenticated

**Steps:**
1. Navigate to /dashboard
2. Tab to organization switcher
3. Press Enter to open dropdown
4. Use Arrow Down/Up to navigate
5. Press Enter to select
6. Press Escape to close

**Expected Results:**
- Switcher is focusable via Tab
- Enter opens the dropdown
- Arrow keys navigate menu items
- Enter selects highlighted item
- Escape closes dropdown
- Focus returns to trigger after close

---

### TC-SS-054: Org Switch Resets Unavailable Domain Scope

**Priority:** High
**Automation Status:** Automated
**Qase ID:** TC-SS-054

**Preconditions:**
- User is authenticated
- User has multiple organizations
- Organizations have different domains

**Steps:**
1. Navigate to /dashboard
2. Select a custom domain scope
3. Switch to a different organization
4. Observe domain switcher

**Expected Results:**
- If new org doesn't have the previously selected domain:
  - Domain scope resets to canonical or first available
  - localStorage is updated
- If new org has the same domain:
  - Domain scope is preserved

---

## Section 5: State Persistence

### TC-SS-060: Org Selection Persists Across Navigation

**Priority:** High
**Automation Status:** Automated
**Qase ID:** TC-SS-060

**Preconditions:**
- User is authenticated
- User has multiple organizations

**Steps:**
1. Navigate to /dashboard
2. Note current organization
3. Navigate to /
4. Navigate back to /dashboard
5. Check organization switcher

**Expected Results:**
- Same organization is selected
- No flash of different organization
- State is maintained in store

---

### TC-SS-061: Domain Scope Persists Across Navigation

**Priority:** High
**Automation Status:** Automated
**Qase ID:** TC-SS-061

**Preconditions:**
- User is authenticated
- User has custom domains

**Steps:**
1. Navigate to /dashboard
2. Select a domain scope
3. Navigate to different pages
4. Return to /dashboard

**Expected Results:**
- Same domain scope is selected
- localStorage value is consistent
- Domain scope indicator shows correct domain

---

### TC-SS-062: Domain Scope Persists in localStorage

**Priority:** Medium
**Automation Status:** Automated
**Qase ID:** TC-SS-062

**Preconditions:**
- User is authenticated with domains

**Steps:**
1. Navigate to /dashboard
2. Select a domain
3. Close browser/refresh page
4. Check localStorage and UI

**Expected Results:**
- localStorage contains domainScope key
- On page reload, same domain is selected
- Composable reads from localStorage on init

---

## Section 6: Accessibility

### TC-SS-070: Org Switcher ARIA Labels

**Priority:** Medium
**Automation Status:** Automated
**Qase ID:** TC-SS-070

**Preconditions:**
- User is authenticated

**Steps:**
1. Navigate to /dashboard
2. Inspect organization switcher with screen reader or DevTools

**Expected Results:**
- Trigger has aria-label containing "organization"
- Announces current organization name
- Role and state are properly communicated

---

### TC-SS-071: Domain Switcher ARIA Labels

**Priority:** Medium
**Automation Status:** Automated
**Qase ID:** TC-SS-071

**Preconditions:**
- User is authenticated with domains

**Steps:**
1. Navigate to /dashboard
2. Inspect domain switcher with screen reader

**Expected Results:**
- Trigger has aria-label
- Announces current domain
- Scope concept is communicated

---

### TC-SS-072: Menu Has role="menu"

**Priority:** Medium
**Automation Status:** Automated
**Qase ID:** TC-SS-072

**Preconditions:**
- User is authenticated

**Steps:**
1. Open organization switcher dropdown
2. Inspect the dropdown element

**Expected Results:**
- Dropdown container has role="menu"
- Proper ARIA hierarchy for menus

---

### TC-SS-073: Items Have role="menuitem"

**Priority:** Medium
**Automation Status:** Automated
**Qase ID:** TC-SS-073

**Preconditions:**
- User is authenticated

**Steps:**
1. Open organization switcher dropdown
2. Inspect each menu item

**Expected Results:**
- Each selectable item has role="menuitem"
- Items are focusable
- Selected state is communicated

---

### TC-SS-074: Focus Trapped in Dropdown

**Priority:** Medium
**Automation Status:** Automated
**Qase ID:** TC-SS-074

**Preconditions:**
- User is authenticated

**Steps:**
1. Open organization switcher dropdown
2. Tab repeatedly through items
3. Note focus behavior

**Expected Results:**
- Focus cycles within dropdown (focus trap)
- Cannot Tab out to page elements while open
- Escape key releases focus trap

---

## Data-TestID Recommendations

Add these attributes to components for reliable test automation:

```html
<!-- Organization Scope Switcher -->
<div data-testid="org-scope-switcher">
  <button data-testid="org-scope-switcher-trigger">...</button>
  <div data-testid="org-scope-switcher-dropdown">
    <button data-testid="org-scope-item-{orgId}">
      <button data-testid="org-scope-settings-{orgId}">...</button>
    </button>
    <button data-testid="org-scope-manage-link">...</button>
  </div>
</div>

<!-- Domain Scope Switcher -->
<div data-testid="domain-scope-switcher">
  <button data-testid="domain-scope-switcher-trigger">...</button>
  <div data-testid="domain-scope-switcher-dropdown">
    <button data-testid="domain-scope-item-{domain}">
      <button data-testid="domain-scope-settings-{domain}">...</button>
    </button>
    <button data-testid="domain-scope-add-link">...</button>
  </div>
</div>
```

---

## Test Environment Requirements

### Authentication
- TEST_USER_EMAIL: Valid test user email
- TEST_USER_PASSWORD: Valid test user password

### User Configuration for Full Coverage
- User should have at least 2 organizations
- User should have at least 2 custom domains
- User should have billing access
- Default organization should be present

### API Dependencies
- GET /api/organizations
- GET /api/organizations/:extid
- GET /api/domains (with org filter)
- localStorage access for domain scope

---

## Related Documentation

- `src/apps/workspace/components/navigation/OrganizationScopeSwitcher.vue`
- `src/shared/components/navigation/DomainScopeSwitcher.vue`
- `src/shared/composables/useDomainScope.ts`
- `src/shared/stores/organizationStore.ts`
