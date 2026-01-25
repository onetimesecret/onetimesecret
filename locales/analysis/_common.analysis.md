# Analysis: _common.json Key Structure

This document analyzes the key structure of `/src/locales/en/_common.json` and identifies keys that may belong in more appropriate locale files.

## File Overview

The `_common.json` file contains keys organized under `web.COMMON`, `web.LABELS`, `web.STATUS`, `web.FEATURES`, `web.UNITS`, `web.TITLES`, `web.ARIA`, and `web.INSTRUCTION` namespaces.

### Current Categories

| Namespace | Key Count | Purpose |
|-----------|-----------|---------|
| `web.COMMON` | ~163 keys | Mixed bag of UI text, form fields, auth messages, secret-related text |
| `web.LABELS` | ~35 keys | UI labels for various features |
| `web.STATUS` | ~25 keys | Status indicators and descriptions |
| `web.FEATURES` | 3 keys | Feature descriptions |
| `web.UNITS` | ~12 keys | Time duration units and remaining counts |
| `web.TITLES` | ~34 keys | Page/section titles |
| `web.ARIA` | 1 key | Accessibility labels |
| `web.INSTRUCTION` | 5 keys | User instructions for sharing |

---

## Potentially Misplaced Keys

### 1. Authentication-Related Keys -> `auth.json`

These keys belong in `auth.json` under appropriate namespaces:

| Current Key | Recommended Location |
|-------------|---------------------|
| `web.COMMON.header_create_account` | `web.auth.signup.header` or `web.signup` |
| `web.COMMON.header_sign_in` | `web.auth.login.header` or `web.login` |
| `web.COMMON.header_logout` | `web.auth.logout.header` |
| `web.COMMON.login_to_your_account` | `web.login.prompt` |
| `web.COMMON.button_create_account` | `web.signup.button` |
| `web.COMMON.field_email` | `web.auth.fields.email` |
| `web.COMMON.field_password` | `web.auth.fields.password` |
| `web.COMMON.field_password2` | `web.auth.fields.confirm_password` |
| `web.COMMON.email_placeholder` | `web.auth.placeholders.email` |
| `web.COMMON.password_placeholder` | `web.auth.placeholders.password` |
| `web.COMMON.confirm_password_placeholder` | `web.auth.placeholders.confirm_password` |
| `web.COMMON.show-password` | `web.auth.password.show` |
| `web.COMMON.hide-password` | `web.auth.password.hide` |
| `web.COMMON.minimum_8_characters` | `web.auth.password.min_length` |
| `web.COMMON.password-requirements` | `web.auth.password.requirements` |
| `web.COMMON.passwords_do_not_match` | `web.auth.password.mismatch` |
| `web.COMMON.passwords-do-not-match` | `web.auth.password.mismatch` (duplicate) |
| `web.COMMON.password-strength` | `web.auth.password.strength` |
| `web.COMMON.remember-me-description` | `web.login.remember_me` |
| `web.COMMON.new-password` | `web.auth.change-password.new` |
| `web.COMMON.confirm-password` | `web.auth.change-password.confirm` |
| `web.COMMON.email-address` | `web.auth.fields.email_label` |
| `web.COMMON.verification_sent_to` | `web.auth.verify.sent_to` |
| `web.COMMON.autoverified_success` | `web.auth.verify.auto_success` |
| `web.COMMON.signup_success_generic` | `web.signup.success` |
| `web.COMMON.verification_not_valid` | `web.auth.verify.invalid` |
| `web.COMMON.verification_already_logged_in` | `web.auth.verify.already_logged_in` |
| `web.COMMON.click_to_verify` | `web.auth.verify.click_to_continue` |
| `web.COMMON.msg_check_email` | `web.auth.check_email` |

**Note:** Several password-related keys are duplicated with different naming conventions (snake_case vs kebab-case).

### 2. Secret-Specific Keys -> `feature-secrets.json`

| Current Key | Recommended Location |
|-------------|---------------------|
| `web.COMMON.secret_privacy_options` | `web.secrets.privacyOptions` (exists) |
| `web.COMMON.secret_passphrase` | `web.secrets.passphrase` |
| `web.COMMON.secret_passphrase_hint` | `web.secrets.passphrase_hint` |
| `web.COMMON.secret_recipient_address` | `web.secrets.recipient_address` |
| `web.COMMON.secret_placeholder` | `web.secrets.placeholder` |
| `web.COMMON.button_create_secret` | `web.secrets.button_create` |
| `web.COMMON.button_generate_secret` | `web.secrets.button_generate` |
| `web.COMMON.button_generate_secret_short` | `web.secrets.button_generate_short` |
| `web.COMMON.generate_password_disabled` | `web.secrets.generate_disabled` |
| `web.COMMON.error_secret` | `web.secrets.error_empty` |
| `web.COMMON.error_passphrase` | `web.secrets.error_passphrase` |
| `web.COMMON.enter_passphrase_here` | `web.secrets.enter_passphrase` |
| `web.COMMON.incorrect_passphrase` | `web.secrets.incorrect_passphrase` |
| `web.COMMON.view_secret` | `web.secrets.view` |
| `web.COMMON.careful_only_see_once` | `web.secrets.warning_once` |
| `web.COMMON.secret_was_truncated` | `web.secrets.truncated` |
| `web.COMMON.share_a_secret` | `web.secrets.share` |
| `web.COMMON.share_link_securely` | `web.secrets.share_securely` |
| `web.COMMON.click_to_continue` | `web.secrets.reveal_button` |
| `web.COMMON.copy-secret-to-clipboard` | `web.secrets.copy_to_clipboard` |
| `web.COMMON.secret-copied-to-clipboard` | `web.secrets.copied_success` |
| `web.COMMON.press_copy_button_below` | `web.secrets.press_copy` |
| `web.COMMON.Double check that passphrase` | `web.secrets.passphrase_error` (duplicate, remove) |
| `web.LABELS.secret_status` | `web.secrets.status.label` |
| `web.LABELS.secret_link` | `web.secrets.link.label` |
| `web.LABELS.create_new_secret` | `web.secrets.create_new` |
| `web.LABELS.security_details` | `web.secrets.security_details` |
| `web.LABELS.passphrase_protected` | `web.secrets.passphrase_protected` |
| `web.LABELS.no_passphrase` | `web.secrets.no_passphrase` |
| `web.LABELS.title_recent_secrets` | `web.secrets.recent.title` |
| `web.LABELS.caption_recent_secrets` | `web.secrets.recent.caption` |
| `web.LABELS.create-link-short` | `web.secrets.create_link_short` |
| `web.LABELS.create-link` | `web.secrets.create_link` |
| `web.LABELS.create-request-short` | `web.secrets.create_request_short` |
| `web.LABELS.create-request` | `web.secrets.create_request` |
| `web.INSTRUCTION.*` | `web.secrets.instructions.*` |

### 3. Burn-Related Keys -> `feature-secrets.json` (burn namespace)

| Current Key | Recommended Location |
|-------------|---------------------|
| `web.COMMON.burn` | `web.secrets.burn.action` |
| `web.COMMON.burned` | `web.secrets.burn.burned` |
| `web.COMMON.burn_this_secret` | `web.secrets.burn.this_secret` |
| `web.COMMON.burn_this_secret_hint` | `web.secrets.burn.hint` |
| `web.COMMON.burn_this_secret_confirm_hint` | `web.secrets.burn.confirm_hint` |
| `web.COMMON.burn_this_secret_aria` | `web.secrets.burn.aria` |
| `web.COMMON.burn_confirmation_title` | `web.secrets.burn.confirm_title` |
| `web.COMMON.burn_confirmation_message` | `web.secrets.burn.confirm_message` |
| `web.COMMON.confirm_burn` | `web.secrets.burn.confirm_button` |
| `web.COMMON.burn_security_notice` | `web.secrets.burn.security_notice` |
| `web.STATUS.burned` | `web.secrets.status.burned` |
| `web.STATUS.burned_description` | `web.secrets.status.burned_description` |

### 4. Domain-Related Keys -> `feature-domains.json`

| Current Key | Recommended Location |
|-------------|---------------------|
| `web.COMMON.custom_domains_title` | `web.domains.title` |
| `web.COMMON.custom_domains_description` | `web.domains.description` |
| `web.LABELS.creating_links_for` | `web.domains.creating_links_for` |
| `web.LABELS.scope_indicator` | `web.domains.scope_indicator` |
| `web.TITLES.domains` | `web.domains.page_title` |
| `web.TITLES.domain_add` | `web.domains.add.title` |
| `web.TITLES.domain_verify` | `web.domains.verify.title` |
| `web.TITLES.domain_brand` | `web.domains.brand.title` |

### 5. Feedback-Related Keys -> `feature-feedback.json`

| Current Key | Recommended Location |
|-------------|---------------------|
| `web.COMMON.feedback_text` | `web.feedback.placeholder` |
| `web.COMMON.button_send_feedback` | `web.feedback.button_send` |
| `web.LABELS.feedback-received` | `web.feedback.received` |
| `web.TITLES.feedback` | `web.feedback.title` |

### 6. Colonel/Admin Keys -> `colonel.json`

| Current Key | Recommended Location |
|-------------|---------------------|
| `web.TITLES.colonel` | `web.colonel.title` |
| `web.TITLES.colonel_users` | `web.colonel.users.title` |
| `web.TITLES.colonel_secrets` | `web.colonel.secrets.title` |
| `web.TITLES.colonel_domains` | `web.colonel.domains.title` |
| `web.TITLES.colonel_system` | `web.colonel.system.title` |
| `web.TITLES.colonel_maindb` | `web.colonel.maindb.title` |
| `web.TITLES.colonel_authdb` | `web.colonel.authdb.title` |
| `web.TITLES.colonel_banned_ips` | `web.colonel.banned_ips.title` |
| `web.TITLES.colonel_usage` | `web.colonel.usage.title` |
| `web.TITLES.colonel_info` | `web.colonel.info.title` |
| `web.TITLES.system_settings` | `web.colonel.settings.title` |

### 7. Dashboard-Related Keys -> `dashboard.json`

| Current Key | Recommended Location |
|-------------|---------------------|
| `web.COMMON.header_dashboard` | `web.dashboard.header` |
| `web.COMMON.recent` | `web.dashboard.recent` |
| `web.COMMON.received` | `web.dashboard.received` |
| `web.TITLES.dashboard` | `web.dashboard.title` |
| `web.TITLES.recent` | `web.dashboard.recent_title` |

### 8. Account-Related Keys -> `account.json`

| Current Key | Recommended Location |
|-------------|---------------------|
| `web.COMMON.header_settings` | `web.account.settings.header` |
| `web.TITLES.account` | `web.account.title` |
| `web.TITLES.profile_settings` | `web.account.profile.title` |
| `web.TITLES.preferences_settings` | `web.account.preferences.title` |
| `web.TITLES.privacy_settings` | `web.account.privacy.title` |
| `web.TITLES.notification_settings` | `web.account.notifications.title` |
| `web.TITLES.change_email` | `web.account.email.title` |
| `web.TITLES.security_overview` | `web.account.security.title` |
| `web.TITLES.change_password` | `web.account.password.title` |
| `web.TITLES.mfa_settings` | `web.account.mfa.title` |
| `web.TITLES.active_sessions` | `web.account.sessions.title` |
| `web.TITLES.recovery_codes` | `web.account.recovery.title` |
| `web.TITLES.api_settings` | `web.account.api.title` |
| `web.TITLES.advanced_settings` | `web.account.advanced.title` |
| `web.TITLES.organizations_settings` | `web.account.organizations.title` |
| `web.TITLES.organization_settings` | `web.account.organization.title` |

### 9. Data Region Keys -> `feature-regions.json`

| Current Key | Recommended Location |
|-------------|---------------------|
| `web.TITLES.data_region` | `web.regions.title` |
| `web.TITLES.current_region` | `web.regions.current.title` |
| `web.TITLES.available_regions` | `web.regions.available.title` |
| `web.TITLES.why_data_sovereignty` | `web.regions.sovereignty.title` |

### 10. Incoming Secrets Keys -> `feature-incoming.json`

| Current Key | Recommended Location |
|-------------|---------------------|
| `web.COMMON.button_create_incoming` | `web.incoming.button_create` |
| `web.TITLES.incoming` | `web.incoming.title` |

---

## Hierarchy Improvements

### Current Issues

1. **Flat structure in COMMON**: The `web.COMMON` namespace is a catch-all with 160+ keys at the same level, making it difficult to find related keys.

2. **Inconsistent naming conventions**: Mix of snake_case (`button_create_secret`) and kebab-case (`form-field-required`).

3. **Duplicate keys**:
   - `passwords_do_not_match` and `passwords-do-not-match`
   - `Double check that passphrase` (literal string as key) and `error_passphrase`

4. **Generic keys mixed with specific**: UI primitives (`word_confirm`, `word_cancel`) mixed with feature-specific text.

### Recommended Hierarchy for Remaining Common Keys

After moving domain-specific keys, restructure what remains in `_common.json`:

```json
{
  "web": {
    "common": {
      "actions": {
        "submit": "Submit",
        "submitting": "Submitting...",
        "processing": "Processing...",
        "save": "Save Changes",
        "saving": "Saving...",
        "cancel": "Cancel",
        "confirm": "Confirm",
        "continue": "Continue",
        "done": "Done",
        "back": "Back",
        "remove": "Remove",
        "refresh": "Refresh",
        "reload": "Reload",
        "get_started": "Get Started"
      },
      "status": {
        "loading": "Loading...",
        "active": "Active",
        "inactive": "Inactive",
        "success": "Success",
        "error": "Error"
      },
      "validation": {
        "required": "This field is required",
        "unexpected_error": "An unexpected error occurred. Please try again."
      },
      "ui": {
        "warning": "Warning",
        "oops": "Oops!",
        "important": "Important",
        "note": "Note",
        "danger_zone": "Danger Zone",
        "caution_zone": "Careful Consideration Zone",
        "are_you_sure": "Are you sure?",
        "preview": "Preview",
        "escape": "Escape",
        "press_esc_to_close": "Press ESC to close"
      },
      "navigation": {
        "previous": "Previous",
        "next": "Next",
        "home": "Home"
      },
      "clipboard": {
        "copied": "Copied to clipboard"
      },
      "preferences": {
        "language": "Language",
        "theme": "Theme",
        "appearance": "Appearance"
      },
      "time": {
        "monthly": "Monthly",
        "yearly": "Yearly",
        "expires_in": "Expires in"
      }
    },
    "labels": {
      "view_toggle": { "show": "Show", "hide": "Hide" },
      "timeline": "Timeline",
      "lifespan": "Lifespan",
      "details": "Details",
      "actions": "Actions",
      "share": "Share",
      "dismiss": "Dismiss",
      "close": "Close"
    },
    "status": {
      "new": "New",
      "active": "Active",
      "inactive": "Inactive",
      "success": "Success",
      "delivered": "Delivered"
    },
    "units": {
      "ttl": { "..." },
      "ttl_remaining": { "..." }
    }
  }
}
```

---

## New File Suggestions

### 1. `ui-primitives.json` (New)

For truly generic UI elements that are used across the entire application:

- Action words: confirm, cancel, continue, done, back, remove
- Status words: loading, active, inactive
- UI text: warning, error, oops, important, note
- Clipboard: copied messages
- Navigation: previous, next

### 2. `form-validation.json` (New)

For form-related messages that span multiple features:

- Required field messages
- Password strength indicators
- Generic validation errors

---

## Duplicate Keys to Consolidate

| Duplicates | Keep |
|------------|------|
| `passwords_do_not_match` / `passwords-do-not-match` | `passwords_do_not_match` |
| `Double check that passphrase` / `error_passphrase` | `error_passphrase` |
| `loading` / `loading_ellipses` | `loading` |
| `done` (COMMON) / `done` (LABELS.saved variant) | Keep both with context |
| `sending-ellipses` (LABELS) / exists in colonel | Consolidate to common |

---

## Summary

The `_common.json` file has grown into a catch-all that contains:
- **163 keys in COMMON** that should be distributed to 10+ feature files
- **35 keys in LABELS** mostly specific to secrets/domains
- **34 keys in TITLES** that are page titles belonging to their respective feature files
- **25 keys in STATUS** primarily for secret states

### Recommended Actions

1. **Move ~80+ keys** to their appropriate feature files (auth, secrets, domains, feedback, colonel, dashboard, account, regions, incoming)
2. **Consolidate duplicates** (at least 3 pairs identified)
3. **Standardize naming** to snake_case throughout
4. **Create hierarchical structure** within remaining common keys
5. **Consider new files** for ui-primitives and form-validation if the project scales

After cleanup, `_common.json` should contain only:
- Generic action verbs (submit, cancel, confirm, etc.)
- Universal status indicators
- Time/date units
- Accessibility labels
- True cross-cutting concerns
