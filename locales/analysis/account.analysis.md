# Locale Key Analysis: account.json

## File Overview

The `account.json` file contains keys under `web.account` and `web.settings` namespaces. It covers:

1. **Account Management** (`web.account`) - Profile info, deletion, API keys, password changes
2. **Settings Pages** (`web.settings`) - Theme, language, profile, sessions, password, security, API, privacy, notifications, caution/danger zone

### Current Key Categories

| Category | Path | Key Count |
|----------|------|-----------|
| Account basics | `web.account.*` | ~35 keys |
| Password change | `web.account.changePassword.*` | 6 keys |
| General settings | `web.settings.*` | 7 keys |
| Theme settings | `web.settings.theme.*` | 3 keys |
| Language settings | `web.settings.language.*` | 3 keys |
| Profile settings | `web.settings.profile.*` | 14 keys |
| Sessions | `web.settings.sessions.*` | 3 keys |
| Password (settings) | `web.settings.password.*` | 3 keys |
| Delete account | `web.settings.delete_account.*` | 3 keys |
| Security | `web.settings.security.*` | 22 keys |
| API & Integrations | `web.settings.api.*` | 18 keys |
| Privacy | `web.settings.privacy.*` | 7 keys |
| Notifications | `web.settings.notifications.*` | 7 keys |
| Caution zone | `web.settings.caution.*` | 13 keys |

---

## Potentially Misplaced Keys

### 1. Billing-Related Keys in `web.account`

These keys belong in `account-billing.json`:

| Current Key | Recommended Location |
|-------------|---------------------|
| `web.account.subscription_title` | `web.billing.subscription.title` (exists) |
| `web.account.manage_subscription` | `web.billing.portal.open_portal` or similar |
| `web.account.customer_information` | `web.billing.customer.information` |
| `web.account.customer_since` | `web.billing.customer.since` |
| `web.account.account_balance` | `web.billing.customer.balance` |
| `web.account.default_payment_method` | `web.billing.overview.payment_method` (exists) |
| `web.account.card_ending` | `web.billing.payment.card_ending` |
| `web.account.subscriptions_title` | `web.billing.subscription.title` (duplicate) |
| `web.account.quantity` | `web.billing.subscription.quantity` |
| `web.account.next_billing_date` | `web.billing.overview.next_billing_date` (exists) |

### 2. Authentication-Related Keys

These keys overlap with `auth.json`:

| Current Key | Recommended Location |
|-------------|---------------------|
| `web.account.changePassword.*` | Already exists at `web.auth.change-password.*` in auth.json |
| `web.account.verify-account` | `web.auth.verify.title` (exists in auth.json) |
| `web.account.close-account` | `web.auth.close-account.title` (exists in auth.json) |
| `web.settings.profile.current-password` | `web.auth.change-password.current-password` |
| `web.settings.profile.new-email` | Could stay or move to auth for consistency |

### 3. API Keys Potentially Warrant Own File

The `web.settings.api.*` section has 18 keys and could be extracted to a dedicated `feature-api.json`:

| Current Path | Suggested New File |
|--------------|-------------------|
| `web.settings.api.*` | `feature-api.json` as `web.api.*` |

---

## Hierarchy Improvements

### 1. Flatten Duplicate Structures

**Problem**: `web.account.changePassword` duplicates `web.auth.change-password` in auth.json.

**Recommendation**: Remove `web.account.changePassword` and use only `web.auth.change-password`.

### 2. Consolidate Account Deletion Keys

**Problem**: Account deletion keys are scattered:
- `web.account.delete-account`
- `web.account.confirm-account-deletion`
- `web.account.deleting-cust-custid`
- `web.account.permanently-delete-account`
- `web.account.permanent-and-non-reversible`
- `web.account.deleting-your-account-is`
- `web.account.account-deleted-successfully`
- `web.account.deactivate`
- `web.account.deactivate-account`
- `web.account.are-you-sure-you-want-to-deactivate-your-account`
- `web.settings.delete_account.*`
- `web.settings.caution.deletion-warning-*`

**Recommendation**: Consolidate under `web.account.deletion.*`:
```
web.account.deletion.title
web.account.deletion.confirm
web.account.deletion.deleting
web.account.deletion.button
web.account.deletion.permanent_notice
web.account.deletion.success
web.account.deletion.warning.secrets
web.account.deletion.warning.metadata
web.account.deletion.warning.api_keys
web.account.deletion.warning.irreversible
```

### 3. Inconsistent Key Naming Conventions

**Problem**: Mix of `kebab-case` and `snake_case`:
- `change-password` vs `changePassword`
- `customer_since` vs `customer-id`
- `delete_account` vs `close-account`

**Recommendation**: Standardize on `snake_case` to match Vue i18n conventions.

### 4. Truncated/Unclear Key Names

These keys have unclear or overly long identifiers:

| Current Key | Suggested Improvement |
|-------------|----------------------|
| `created-windowprops-cust-secrets_created-secrets` | `secrets_created_count` |
| `account-type-windowprops-plan-options-name` | `account_type_display` |
| `keep-this-token-secure-it-provides-full-access-t` | `api_key_security_warning` |
| `are-you-sure-you-want-to-permanently-delete-your` | `deletion_confirmation_message` |
| `click-this-lightning-bolt-to-upgrade-for-custom-domains` | Move to `account-billing.json` |

### 5. Security Settings Could Be Extracted

**Problem**: `web.settings.security.*` has 22 keys covering MFA, sessions, recovery codes, and best practices.

**Recommendation**: Consider creating `account-security.json` if this section grows further, or keep as-is if the current size is manageable.

---

## New File Suggestions

### 1. `feature-api.json` (Recommended)

Extract API-related keys currently in `web.settings.api.*`:
- Documentation links
- Security best practices for API usage
- Key regeneration warnings

### 2. `account-security.json` (Optional)

If security features expand, consider extracting:
- MFA settings
- Session management
- Recovery codes
- Security score/health

---

## Summary of Recommended Actions

| Priority | Action | Impact |
|----------|--------|--------|
| High | Move billing keys to `account-billing.json` | Reduces duplication |
| High | Remove `web.account.changePassword` (use auth.json) | Eliminates duplicate |
| Medium | Consolidate deletion keys under `web.account.deletion.*` | Cleaner hierarchy |
| Medium | Standardize key naming to `snake_case` | Consistency |
| Medium | Rename truncated keys to meaningful names | Maintainability |
| Low | Consider `feature-api.json` extraction | Separation of concerns |
| Low | Consider `account-security.json` extraction | Future scalability |

---

## Cross-File Duplication Detected

| Key in account.json | Duplicate in |
|---------------------|--------------|
| `web.account.changePassword.*` | `web.auth.change-password.*` (auth.json) |
| `web.account.subscription_title` | `web.billing.subscription.title` (account-billing.json) |
| `web.account.next_billing_date` | `web.billing.overview.next_billing_date` (account-billing.json) |
| `web.account.region` | `web.auth.account.region` (auth.json) |
| `web.account.email` | `web.auth.account.email` (auth.json) |
