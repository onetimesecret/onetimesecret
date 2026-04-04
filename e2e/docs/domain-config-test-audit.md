# Domain Configuration Screens - Test Coverage Audit

**Date:** 2026-04-04
**Context:** UI consistency fixes across three domain configuration screens
**Screens:** Email Sending, SSO Configuration, Incoming Secrets

---

## Executive Summary

This audit identifies existing test coverage and gaps for the domain configuration screens being modified for UI consistency. The changes involve:
- Moving toggle from top to bottom of form
- Changing toggle label from feature name to "Enabled"
- Disabling form fields when toggle is OFF
- Info banner visibility based on enabled/disabled state
- Recipient display format changes (showing email addresses)
- Potential relocation/removal of "Delete All Recipients" button

---

## Current Test Coverage

### 1. Incoming Secrets Configuration

#### E2E Tests (Playwright)
**File:** `e2e/all/incoming-secrets.spec.ts`

| Test | Status | Notes |
|------|--------|-------|
| Form loading when feature enabled | Covered | Tests form visibility and recipient dropdown |
| Feature disabled state | Covered | Verifies form NOT visible when disabled |
| Recipients dropdown population | Covered | Tests dropdown opens, recipients visible |
| Recipient selection | Covered | Tests selecting and verifying selection |
| Form validation (incomplete form) | Covered | Submit button disabled when incomplete |
| Submit enabled when fields filled | Covered | Button becomes enabled with valid data |
| Memo character counter | Covered | Counter visibility and limit behavior |
| Happy path flow (full submission) | Covered | End-to-end create and success page |
| API error handling | Covered | Form remains visible on error |
| Accessibility (ARIA attributes) | Covered | Tests aria-label, aria-expanded |
| Mobile responsiveness | Covered | Tests viewport adaptation |

**Gap Analysis:**
- No tests for toggle position (UI layout)
- No tests for form fields becoming disabled when toggle OFF
- No tests for info banner visibility conditions
- No tests for recipient email display format

#### Backend Tests (Tryouts)
**Files:**
- `try/features/incoming/incoming_enabled_toggle_try.rb` - Comprehensive
- `try/features/incoming/incoming_config_try.rb` - Configuration
- `try/features/incoming/incoming_config_schema_separation_try.rb`
- `try/features/incoming/recipient_resolver_try.rb`

| Test | Status | Notes |
|------|--------|-------|
| IncomingConfig.enabled? defaults | Covered | false by default |
| enable!/disable! transitions | Covered | State changes correctly |
| Recipients preserved when disabled | Covered | Round-trip preservation |
| RecipientResolver uses IncomingConfig | Covered | Integration tests |
| API rejects when disabled | Covered | ValidateRecipient, CreateIncomingSecret |
| GetConfig returns enabled state | Covered | API returns correct enabled value |

---

### 2. SSO Configuration

#### E2E Tests (Playwright)
**File:** `e2e/full/domain-sso-config.spec.ts`

| Test ID | Test | Status | Notes |
|---------|------|--------|-------|
| TC-DSSO-001 | Navigation from org SSO tab | Covered | |
| TC-DSSO-002 | Back button navigation | Covered | |
| TC-DSSO-003 | Direct URL navigation | Covered | |
| TC-DSSO-004 | Domain list with SSO badges | Covered | |
| TC-DSSO-005 | "Not Configured" badge | Covered | |
| TC-DSSO-006 | Configure link navigation | Covered | |
| TC-DSSO-007 | Empty domains state | Covered | |
| TC-DSSO-008 | Empty form for unconfigured domain | Covered | |
| TC-DSSO-009 | Provider type selector (4 options) | Covered | |
| TC-DSSO-010 | Entra ID shows tenant_id field | Covered | |
| TC-DSSO-011 | OIDC shows issuer field | Covered | |
| TC-DSSO-012 | Form validation (required fields) | Covered | Save button disabled/enabled |
| TC-DSSO-013 | Test connection button | Covered | |
| TC-DSSO-014 | Test connection success | Covered | |
| TC-DSSO-015 | Test connection error | Covered | |
| TC-DSSO-016 | Save creates config | Covered | |
| TC-DSSO-017 | Delete with confirmation | Covered | |
| TC-DSSO-018 | Multi-domain different providers | Covered | |
| TC-DSSO-019 | Access denied without entitlement | Covered | |
| TC-DSSO-020 | Direct access without entitlement | Covered | |

**Gap Analysis:**
- No tests for enabled toggle behavior (currently no enabled toggle in SSO form based on code review)
- No tests for form fields disabled state
- No tests for info banner visibility

#### Backend Tests (Tryouts)
**File:** `try/integration/api/domains/list_domains_sso_fields_try.rb`

| Test | Status | Notes |
|------|--------|-------|
| sso_configured/sso_enabled fields | Covered | API response includes correct booleans |
| Domain without SSO config | Covered | sso_configured=false, sso_enabled=false |
| Domain with disabled SSO | Covered | sso_configured=true, sso_enabled=false |
| Domain with enabled SSO | Covered | sso_configured=true, sso_enabled=true |

---

### 3. Email Sending Configuration

#### E2E Tests (Playwright)
**Status:** NO DEDICATED E2E TESTS

**Gap Analysis:**
- No Playwright tests for email configuration screen
- No tests for form field validation
- No tests for enabled toggle behavior
- No tests for info banner visibility
- No tests for save/delete operations

#### Backend Tests (Tryouts)
**File:** `try/integration/api/domains/list_domains_mail_fields_try.rb`

| Test | Status | Notes |
|------|--------|-------|
| Domain list mail fields | Covered | API response includes mail config |

---

## Tests That May Break From UI Changes

### High Risk (Likely to fail)

1. **Toggle position selectors**
   - Tests using CSS selectors that assume toggle at top of form
   - Need to update if position changes

2. **Toggle label text matching**
   - Tests using `hasText: 'Incoming Secrets'` or similar feature names
   - Will break if label changes to "Enabled"

3. **Form field enabled state assertions**
   - Any test that fills form fields without first enabling toggle
   - Will fail if fields become disabled by default

### Medium Risk (May need updates)

4. **Form validation flow tests**
   - `e2e/all/incoming-secrets.spec.ts` - Tests form submission
   - May need to ensure toggle is ON before testing

5. **SSO form tests**
   - `e2e/full/domain-sso-config.spec.ts` - Multiple form interaction tests
   - TC-DSSO-008, TC-DSSO-012 may need toggle handling

### Low Risk (Likely stable)

6. **API-level tests**
   - Tryouts tests that don't interact with UI
   - Should remain stable

---

## Missing Test Coverage (Priority Order)

### Critical - Must Add

1. **Toggle-Form State Coupling**
   ```typescript
   test('form fields are disabled when toggle is OFF', async ({ page }) => {
     // Navigate to config page
     // Verify toggle is OFF by default (or set to OFF)
     // Assert all form inputs have disabled attribute or aria-disabled
   });

   test('form fields become enabled when toggle is switched ON', async ({ page }) => {
     // Toggle ON
     // Assert form inputs are now enabled
   });
   ```

2. **Info Banner Visibility**
   ```typescript
   test('shows disabled info banner when toggle is OFF', async ({ page }) => {
     // With toggle OFF
     // Expect info banner with "feature disabled" message
   });

   test('hides disabled info banner when toggle is ON', async ({ page }) => {
     // With toggle ON
     // Info banner should not be visible OR show different content
   });
   ```

### High Priority

3. **Cross-Screen Consistency Tests**
   ```typescript
   test.describe('Domain Config Screen Consistency', () => {
     const configScreens = [
       { name: 'Email', path: '/org/{orgId}/domains/{domainId}/email' },
       { name: 'SSO', path: '/org/{orgId}/domains/{domainId}/sso' },
       { name: 'Incoming', path: '/org/{orgId}/domains/{domainId}/incoming' },
     ];

     for (const screen of configScreens) {
       test(`${screen.name} has toggle at bottom of form`, async ({ page }) => {
         // Navigate to screen
         // Find toggle element
         // Assert toggle is positioned after form fields (Y coordinate comparison)
       });

       test(`${screen.name} toggle label is "Enabled"`, async ({ page }) => {
         // Navigate to screen
         // Find toggle label
         // Assert text is "Enabled"
       });
     }
   });
   ```

4. **Email Config Screen E2E Tests**
   - Form field validation
   - Save/delete operations
   - Enabled toggle behavior
   - Error handling

### Medium Priority

5. **Recipient Display Format Tests**
   ```typescript
   test('recipient list shows email addresses', async ({ page }) => {
     // Navigate to incoming config with recipients
     // Assert email addresses are visible in list
   });
   ```

6. **Delete All Recipients Button**
   ```typescript
   test('delete all recipients button clears list with confirmation', async ({ page }) => {
     // With existing recipients
     // Click delete all
     // Confirm dialog
     // Assert list is empty
   });
   ```

### Low Priority

7. **Accessibility for Disabled States**
   ```typescript
   test('disabled form fields have proper aria attributes', async ({ page }) => {
     // With toggle OFF
     // Assert inputs have aria-disabled="true" or disabled attribute
     // Assert proper focus management (skip disabled fields)
   });
   ```

---

## Recommended Test Update Workflow

### Phase 1: Pre-Change Baseline
1. Run existing e2e tests, record current pass/fail status
2. Identify any tests that make assumptions about toggle position

### Phase 2: Update Existing Tests
1. Update `e2e/all/incoming-secrets.spec.ts`:
   - Add toggle enable step before form interaction tests
   - Update toggle label assertions if present

2. Update `e2e/full/domain-sso-config.spec.ts`:
   - Add toggle handling if SSO form gets enabled toggle
   - Update form validation tests to account for disabled state

### Phase 3: Add New Coverage
1. Create `e2e/full/domain-config-consistency.spec.ts`:
   - Cross-screen consistency tests
   - Toggle-form state coupling tests
   - Info banner visibility tests

2. Create `e2e/full/domain-email-config.spec.ts`:
   - Full coverage for email configuration screen

### Phase 4: Backend Validation
1. Run Tryouts to ensure backend behavior unchanged:
   ```bash
   bundle exec try --agent try/features/incoming/
   bundle exec try --agent try/integration/api/domains/
   ```

---

## Test Data-TestId Requirements

Based on the UI changes, these `data-testid` attributes should be added to components:

```vue
<!-- Toggle -->
<button data-testid="config-enabled-toggle" role="switch" />

<!-- Form container -->
<div data-testid="config-form-fields" />

<!-- Info banner -->
<div data-testid="config-disabled-banner" />

<!-- Recipient list -->
<ul data-testid="recipient-list" />

<!-- Delete all button -->
<button data-testid="delete-all-recipients" />
```

---

## Files to Monitor

| File | Reason |
|------|--------|
| `e2e/all/incoming-secrets.spec.ts` | Main incoming secrets tests |
| `e2e/full/domain-sso-config.spec.ts` | SSO configuration tests |
| `src/apps/workspace/components/domains/DomainIncomingConfigForm.vue` | Being modified |
| `src/apps/workspace/components/domains/DomainEmailConfigForm.vue` | Being modified |
| `src/apps/workspace/components/domains/DomainSsoConfigForm.vue` | Being modified |
| `try/features/incoming/*.rb` | Backend incoming tests |

---

## Appendix: Test Run Commands

```bash
# E2E Tests (with dev server running)
PLAYWRIGHT_BASE_URL=http://localhost:5173 pnpm test:playwright e2e/all/incoming-secrets.spec.ts
PLAYWRIGHT_BASE_URL=http://localhost:5173 pnpm test:playwright e2e/full/domain-sso-config.spec.ts

# Tryouts (backend)
bundle exec try --agent try/features/incoming/
bundle exec try --agent try/integration/api/domains/

# Full e2e suite
PLAYWRIGHT_BASE_URL=http://localhost:5173 pnpm test:playwright e2e/

# With headed browser for debugging
pnpm test:playwright e2e/all/incoming-secrets.spec.ts --headed --project=chromium
```
