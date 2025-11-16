# i18n Reorganization Implementation Plan

## Overview

This document provides a concrete, actionable plan for reorganizing the Onetime Secret i18n structure to clearly separate:
- **Recipients** (anonymous users viewing secrets)
- **Creators** (authenticated users creating/managing secrets)
- **Shared** (common UI elements)

---

## Recommended Reorganization Structure

### New Locale File Structure

```json
{
  "recipient": {
    "secret": {
      "title": "You have a message",
      "warning_view_once": "Careful: we will only show it once.",
      "click_to_reveal": "Click to reveal →",
      "enter_passphrase": "Enter the passphrase here",
      "passphrase_required": "This secret requires a passphrase",
      "copy_to_clipboard": "Copy to Clipboard",
      "copied": "Copied!",
      "safely_close_tab": "You can safely close this tab",
      "view_once_warning": "Once you leave or refresh this page, this secret will be permanently deleted"
    },
    "burn": {
      "title": "Burn this secret",
      "description": "Burning a secret will delete it before it has been viewed",
      "confirmation_title": "Please Confirm",
      "confirmation_message": "Are you sure you want to burn this secret? This action cannot be undone.",
      "confirm_button": "Yes, burn this secret",
      "cancel_button": "Cancel"
    },
    "errors": {
      "not_found": "That information is no longer available",
      "already_viewed": "Information shared through this service can only be viewed once",
      "permanently_deleted": "This secret has been permanently deleted",
      "incorrect_passphrase": "Incorrect passphrase"
    },
    "help": {
      "title": "Need help?",
      "contact_sender": "Contact the person who sent you this link",
      "faq": {
        "what_am_i_looking_at": {
          "title": "What am I looking at?",
          "description": "You're viewing a secure message that was shared with you through Onetime Secret."
        },
        "can_view_again": {
          "title": "Can I view this secret again later?",
          "description": "No. For security reasons, this secret is only viewable once."
        },
        "how_to_copy": {
          "title": "How do I save this information?",
          "description": "Use the 'Copy to Clipboard' button to copy the entire secret."
        }
      }
    },
    "footer": {
      "powered_by": "Powered by",
      "attribution": "Onetime Secret"
    }
  },

  "creator": {
    "dashboard": {
      "title": "Dashboard",
      "tab_home": "Home",
      "tab_recent": "Recent",
      "tab_domains": "Domains",
      "no_secrets_yet": "You haven't created any secrets yet",
      "get_started": "Get started by creating your first secret",
      "create_another": "Create another secret"
    },
    "metadata": {
      "title": "Your Secret Details",
      "created": "Created",
      "expires": "Expires",
      "status": "Status",
      "status_not_received": "Not Received",
      "status_received": "Received",
      "status_burned": "Burned",
      "recipient": "Recipient",
      "passphrase_protected": "Passphrase Protected",
      "view_secret": "View Secret",
      "burn_secret": "Burn Secret",
      "copy_link": "Copy Link",
      "viewed_ago": "Viewed {time} ago",
      "created_ago": "Created {time} ago",
      "expires_in": "Expires in {time}",
      "only_view_once": "You can only view this secret value once",
      "timeline": "Timeline",
      "encrypted": "Encrypted",
      "you_created_this": "You created this secret"
    },
    "secrets": {
      "create_title": "Create a Secret",
      "recent_title": "Recent Secrets",
      "not_received": "Not Received",
      "received": "Received",
      "burned": "Burned"
    },
    "domains": {
      "title": "Custom Domains",
      "add_domain": "Add Domain",
      "add_your_domain": "Add your domain",
      "verify_domain": "Verify your domain",
      "manage_brand": "Manage Brand",
      "domain_name": "Domain Name",
      "status": "Status",
      "actions": "Actions",
      "no_domains": "No domains found",
      "get_started": "Get started by adding a custom domain",
      "verification": {
        "title": "Domain Verification Steps",
        "step1_title": "Create a TXT record",
        "step1_description": "Add this hostname to your DNS configuration",
        "step2_title": "Create the A or CNAME record",
        "step2_cname_warning": "A CNAME record is not allowed. Instead, you'll need an A record.",
        "step2_apex_note": "Please note that for apex domains (e.g., example.com), you'll need to create an A record.",
        "step3_title": "Wait for propagation",
        "step3_description": "DNS changes can take as little as 60 seconds or as long as 48 hours",
        "dns_instructions": "Follow these steps to verify domain ownership",
        "target_address": "Target address",
        "host": "Host",
        "value": "Value",
        "type": "Type"
      },
      "branding": {
        "title": "Customize your domain branding",
        "brand_color": "Brand Color",
        "brand_logo": "Brand Logo",
        "corner_style": "Corner Style",
        "upload_logo": "Upload Logo",
        "preview": "Preview",
        "loading_preview": "Loading preview..."
      }
    },
    "account": {
      "title": "Account Settings",
      "your_account": "Your Account",
      "email": "Email",
      "account_id": "Account ID",
      "change_password": {
        "title": "Change Password",
        "current_password": "Current Password",
        "new_password": "New Password",
        "confirm_password": "Confirm Password",
        "update_button": "Update Password",
        "success": "Password updated successfully"
      },
      "api_keys": {
        "title": "API Keys",
        "create_new": "Create New API Key",
        "token": "Token",
        "created": "Created",
        "keep_secure": "Keep this token secure - it provides full access to your account"
      },
      "billing": {
        "title": "Billing",
        "plan": "Plan",
        "status": "Status",
        "customer_id": "Customer ID"
      },
      "delete": {
        "title": "Delete Account",
        "description": "Deleting your account is permanent and non-reversible",
        "confirmation_title": "Confirm Account Deletion",
        "confirmation_message": "Are you sure you want to permanently delete your account?",
        "confirm_with_password": "Confirm with your password",
        "deactivate_button": "Deactivate",
        "permanently_delete_button": "Permanently Delete Account",
        "success": "Account deleted successfully"
      }
    }
  },

  "shared": {
    "common": {
      "loading": "Loading...",
      "processing": "Processing...",
      "submitting": "Submitting...",
      "submit": "Submit",
      "cancel": "Cancel",
      "confirm": "Confirm",
      "close": "Close",
      "back": "Back",
      "next": "Next",
      "previous": "Previous",
      "done": "Done",
      "continue": "Continue",
      "error": "Error",
      "warning": "Warning",
      "success": "Success",
      "oops": "Oops!",
      "unexpected_error": "An unexpected error occurred. Please try again."
    },
    "auth": {
      "sign_in": "Sign In",
      "sign_up": "Sign Up",
      "sign_out": "Sign Out",
      "email": "Email",
      "email_placeholder": "e.g. tom@myspace.com",
      "password": "Password",
      "password_placeholder": "Enter your password",
      "confirm_password": "Confirm Password",
      "confirm_password_placeholder": "Confirm your password",
      "forgot_password": "Forgot your password?",
      "need_account": "Need an account?",
      "have_account": "Already have an account?",
      "create_account": "Create Account",
      "sign_in_to_account": "Sign in to your account",
      "create_your_account": "Create your account",
      "remember_me": "Remember me",
      "reset_password": {
        "title": "Reset Password",
        "request_title": "Request Password Reset",
        "instructions": "Enter your email address below and we'll send you a link to reset your password",
        "choose_new": "Choose a new password",
        "enter_new": "Please enter your new password below",
        "request_button": "Request Reset",
        "back_to_signin": "Back to Sign In"
      }
    },
    "secret_form": {
      "title": "Share a secret",
      "secret_placeholder": "Secret content goes here...",
      "passphrase": "Passphrase",
      "passphrase_hint": "A word or phrase that's difficult to guess",
      "passphrase_required": "Passphrase (required)",
      "passphrase_min_length": "Minimum {length} characters",
      "recipient_address": "Recipient Address",
      "recipient_optional": "Recipient delivery is optional",
      "expiration_time": "Expiration time",
      "privacy_options": "Privacy Options",
      "create_button": "Create a secret link",
      "generate_password": "Or generate a random password",
      "generate_password_short": "Generate Password",
      "custom_domain": "Custom Domain",
      "instructions": {
        "pre_reveal": "Pre-reveal instructions",
        "pre_reveal_description": "These instructions will be shown to recipients before they view the secret",
        "post_reveal": "Post-reveal instructions",
        "post_reveal_description": "These instructions will be shown to recipients after they view the secret"
      }
    },
    "labels": {
      "actions": "Actions",
      "status": "Status",
      "created": "Created",
      "expires": "Expires",
      "expired": "Expired",
      "received": "Received",
      "burned": "Burned",
      "secret": "Secret",
      "secrets": "Secrets",
      "metadata": "Metadata",
      "timeline": "Timeline",
      "encrypted": "Encrypted",
      "copy_to_clipboard": "Copy to Clipboard",
      "copied": "Copied!",
      "refresh": "Refresh"
    },
    "time": {
      "seconds": "seconds",
      "minutes": "minutes",
      "hours": "hours",
      "days": "days",
      "weeks": "weeks",
      "expires_in": "Expires in",
      "no_options_available": "No options available"
    },
    "errors": {
      "validation": {
        "required": "This field is required",
        "email_invalid": "Please enter a valid email address",
        "passwords_dont_match": "Passwords do not match",
        "passphrase_too_short": "Passphrase must be at least {length} characters",
        "secret_empty": "You did not provide anything to share"
      }
    }
  },

  "public": {
    "homepage": {
      "tagline": "Secure links that only work once",
      "description": "Keep sensitive information out of your chat logs and email. Share a secret link that is available only one time.",
      "cta": {
        "title": "Elevate your secure sharing with custom domains",
        "subtitle": "Strengthen connections and build trust with your own branded secret links",
        "get_started": "Get Started",
        "feature1": "Privacy-first design",
        "feature2": "Secure encrypted storage",
        "feature3": "One-time access"
      },
      "protip1": "Pro tip: You can also create a secret by pasting it on the homepage",
      "password_generation": {
        "title": "Need a strong password?",
        "description": "Click the button below to generate a random password"
      },
      "sign_up_free": "Sign up free",
      "explore_plans": "Explore premium plans"
    },
    "footer": {
      "about": "About",
      "privacy_policy": "Privacy Policy",
      "terms_of_service": "Terms of Service",
      "contact": "Contact",
      "github": "View source on GitHub",
      "feedback": "Provide feedback",
      "powered_by": "Powered by Onetime Secret",
      "version": "Version {version}",
      "navigation": {
        "about": "About Onetime Secret",
        "help": "Help & Documentation",
        "api": "API Documentation",
        "pricing": "Pricing",
        "blog": "Blog"
      }
    },
    "feedback": {
      "title": "Share your feedback",
      "subtitle": "Help us improve",
      "description": "Hey there! Thanks for stopping by our feedback page. We value your input and use it to make Onetime Secret better.",
      "placeholder": "Share your thoughts, ideas, or experiences...",
      "send_button": "Send Feedback",
      "all_welcome": "All feedback welcome",
      "remember_email": "Remember to include your email if you're not logged in and want a response",
      "thanks": "Thanks for helping Onetime Secret improve!"
    },
    "errors": {
      "404": {
        "title": "404 - Page Not Found",
        "description": "Oops! The page you are looking for doesn't exist or has been moved.",
        "return_home": "Return Home",
        "go_back": "Go back to previous page"
      },
      "500": {
        "title": "Oops! Something went wrong",
        "description": "We're sorry, but an unexpected error occurred while processing your request.",
        "try_again": "Please try again later"
      }
    }
  },

  "settings": {
    "title": "Settings",
    "sections": {
      "general": "General",
      "appearance": "Appearance",
      "jurisdiction": "Data Region",
      "language": "Language"
    },
    "general": {
      "title": "General Settings",
      "customize": "Customize your app preferences and settings"
    },
    "appearance": {
      "theme": "Theme",
      "toggle_dark_mode": "Toggle dark mode",
      "icon_library": "Icon Library",
      "font_family": "Font Family"
    },
    "jurisdiction": {
      "title": "Data Region",
      "current": "Current jurisdiction",
      "description": "Data center location for your account",
      "available_regions": "Available regions",
      "switch_region": "Switch region"
    },
    "language": {
      "title": "Language",
      "current": "Current language is {locale}",
      "changed": "Language changed to {locale}",
      "help": {
        "title": "Help us improve translations",
        "description": "Your language skills can help expand access to secure sharing globally",
        "start_new": "Start a new translation from our English template",
        "update_existing": "Update a language directly through our GitHub project",
        "send_email": "Send translations by email to {email}",
        "fork_github": "Fork on GitHub and submit a PR",
        "thanks": "Thanks to our community, we support over 20 languages"
      }
    }
  }
}
```

---

## Migration Mapping

### Key Migration Examples

#### Recipient Keys

| Current Key | New Key | Component |
|-------------|---------|-----------|
| `web.COMMON.click_to_continue` | `recipient.secret.click_to_reveal` | SecretConfirmationForm |
| `web.COMMON.enter_passphrase_here` | `recipient.secret.enter_passphrase` | SecretConfirmationForm |
| `web.COMMON.burn_this_secret` | `recipient.burn.title` | BurnSecret |
| `web.COMMON.burn_confirmation_message` | `recipient.burn.confirmation_message` | BurnSecret |
| `information-no-longer-available` | `recipient.errors.not_found` | UnknownSecret |
| `you-can-safely-close-this-tab` | `recipient.secret.safely_close_tab` | SecretDisplayCase |
| `web.private.only_see_once` | `recipient.secret.warning_view_once` | SecretDisplayCase |

#### Creator Keys

| Current Key | New Key | Component |
|-------------|---------|-----------|
| `web.dashboard.title_no_recent_secrets` | `creator.dashboard.no_secrets_yet` | DashboardRecent |
| `web.dashboard.get-started-by-creating-your-first-secret` | `creator.dashboard.get_started` | DashboardRecent |
| `web.private.viewed_ago` | `creator.metadata.viewed_ago` | SecretMetadataTable |
| `web.private.created_success` | `creator.metadata.created_ago` | ShowMetadata |
| `web.account.changePassword.updatePassword` | `creator.account.change_password.update_button` | AccountChangePasswordForm |
| `add-your-domain` | `creator.domains.add_your_domain` | DashboardDomainAdd |
| `verify-your-domain` | `creator.domains.verify_domain` | DashboardDomainVerify |

#### Shared Keys

| Current Key | New Key | Component |
|-------------|---------|-----------|
| `web.COMMON.loading` | `shared.common.loading` | Many |
| `web.COMMON.word_cancel` | `shared.common.cancel` | Many |
| `web.COMMON.word_confirm` | `shared.common.confirm` | Many |
| `web.COMMON.email_placeholder` | `shared.auth.email_placeholder` | Auth forms |
| `web.COMMON.secret_passphrase` | `shared.secret_form.passphrase` | SecretForm |
| `web.login.forgot_your_password` | `shared.auth.forgot_password` | SignInForm |
| `web.signup.create-your-account` | `shared.auth.create_your_account` | SignUpForm |

#### Public Keys

| Current Key | New Key | Component |
|-------------|---------|-----------|
| `web.COMMON.tagline` | `public.homepage.tagline` | Homepage |
| `web.COMMON.description` | `public.homepage.description` | Homepage |
| `web.homepage.protip1` | `public.homepage.protip1` | Homepage |
| `404-page-not-found` | `public.errors.404.title` | ErrorNotFound |
| `return-home` | `public.errors.404.return_home` | ErrorNotFound |

---

## Implementation Steps

### Step 1: Create New Locale Structure (1-2 days)

1. **Create new en.json with new structure**
   ```bash
   cp src/locales/en.json src/locales/en.json.backup
   # Create new structure based on template above
   ```

2. **Preserve all existing keys with migration mapping**
   - Keep old keys temporarily for backwards compatibility
   - Add new keys alongside old ones
   - Example:
   ```json
   {
     "recipient": {
       "secret": {
         "click_to_reveal": "Click to reveal →"
       }
     },
     "web": {
       "COMMON": {
         "click_to_continue": "Click to reveal →"  // DEPRECATED: Use recipient.secret.click_to_reveal
       }
     }
   }
   ```

### Step 2: Update Components (3-5 days)

#### Recipient Components

**Before:**
```vue
<template>
  <button @click="reveal">
    {{ $t('web.COMMON.click_to_continue') }}
  </button>
</template>
```

**After:**
```vue
<template>
  <button @click="reveal">
    {{ $t('recipient.secret.click_to_reveal') }}
  </button>
</template>
```

#### Creator Components

**Before:**
```vue
<template>
  <div v-if="hasNoSecrets">
    <h2>{{ $t('web.dashboard.title_no_recent_secrets') }}</h2>
    <p>{{ $t('web.dashboard.get-started-by-creating-your-first-secret') }}</p>
  </div>
</template>
```

**After:**
```vue
<template>
  <div v-if="hasNoSecrets">
    <h2>{{ $t('creator.dashboard.no_secrets_yet') }}</h2>
    <p>{{ $t('creator.dashboard.get_started') }}</p>
  </div>
</template>
```

#### Shared Components

**Before:**
```vue
<template>
  <input
    :placeholder="$t('web.COMMON.email_placeholder')"
    type="email"
  />
</template>
```

**After:**
```vue
<template>
  <input
    :placeholder="$t('shared.auth.email_placeholder')"
    type="email"
  />
</template>
```

### Step 3: Migrate Flat Keys (2-3 days)

Create a script to identify and move flat keys:

```javascript
// scripts/migrate-flat-keys.js
const fs = require('fs');
const path = require('path');

const LOCALE_PATH = path.join(__dirname, '../src/locales/en.json');
const locale = JSON.parse(fs.readFileSync(LOCALE_PATH, 'utf-8'));

const flatKeys = Object.keys(locale).filter(key => key !== 'web' && key !== 'recipient' && key !== 'creator' && key !== 'shared' && key !== 'public' && key !== 'settings');

console.log(`Found ${flatKeys.length} flat keys to migrate:`);
console.log(flatKeys.join('\n'));

// Generate migration suggestions based on key name patterns
const suggestions = flatKeys.map(key => {
  if (key.includes('domain') || key.includes('dns')) {
    return { old: key, new: `creator.domains.${key.replace(/-/g, '_')}` };
  } else if (key.includes('404') || key.includes('not-found')) {
    return { old: key, new: `public.errors.404.${key.replace(/-/g, '_')}` };
  } else if (key.includes('account') || key.includes('delete')) {
    return { old: key, new: `creator.account.${key.replace(/-/g, '_')}` };
  } else if (key.includes('sign-in') || key.includes('password')) {
    return { old: key, new: `shared.auth.${key.replace(/-/g, '_')}` };
  } else {
    return { old: key, new: `public.misc.${key.replace(/-/g, '_')}` };
  }
});

console.log('\nMigration suggestions:');
console.log(JSON.stringify(suggestions, null, 2));
```

### Step 4: Update All Locale Files (1-2 weeks)

For each of the 30 language files:

1. **Automated first pass** - Use script to restructure:
   ```bash
   node scripts/restructure-locale.js src/locales/es.json
   ```

2. **Manual review** - Have native speaker verify context
3. **Test** - Ensure UI displays correctly

### Step 5: Remove Deprecated Keys (After 1-2 releases)

1. Add deprecation warnings to console:
   ```javascript
   // src/plugins/i18n.js
   const originalT = i18n.global.t;
   i18n.global.t = (key, ...args) => {
     const deprecatedKeys = {
       'web.COMMON.click_to_continue': 'recipient.secret.click_to_reveal',
       // ... more mappings
     };

     if (deprecatedKeys[key]) {
       console.warn(`[i18n] Key "${key}" is deprecated. Use "${deprecatedKeys[key]}" instead.`);
     }

     return originalT(key, ...args);
   };
   ```

2. After 1-2 releases, remove old keys from locale files

---

## Translation Priority Strategy

### Tier 1: Recipient Experience (High Priority)
**~100 keys** - Translate first for all languages

Namespaces:
- `recipient.*` (all keys)
- `shared.common.*` (basic UI)
- `shared.errors.validation.*`
- `public.errors.*` (error pages)

**Cost estimate**: $100-200 per language

### Tier 2: Creator Features (Medium Priority)
**~150 keys** - Translate after Tier 1

Namespaces:
- `creator.dashboard.*`
- `creator.metadata.*`
- `creator.secrets.*`
- `shared.auth.*`
- `shared.secret_form.*`

**Cost estimate**: $150-300 per language (additional)

### Tier 3: Advanced Features (Lower Priority)
**~200 keys** - Optional, community contributions

Namespaces:
- `creator.domains.*`
- `creator.account.*`
- `settings.*`

**Cost estimate**: $200-400 per language (additional)

### Tier 4: Marketing & Optional (Lowest Priority)
**~400 keys** - Community/AI assisted

Namespaces:
- `public.homepage.*`
- `public.footer.*`
- `public.feedback.*`

---

## Testing Strategy

### 1. Automated Tests

```javascript
// tests/i18n/key-coverage.spec.js
import { describe, it, expect } from 'vitest';
import en from '@/locales/en.json';

describe('i18n structure', () => {
  it('should have recipient namespace', () => {
    expect(en.recipient).toBeDefined();
    expect(en.recipient.secret).toBeDefined();
    expect(en.recipient.burn).toBeDefined();
    expect(en.recipient.errors).toBeDefined();
  });

  it('should have creator namespace', () => {
    expect(en.creator).toBeDefined();
    expect(en.creator.dashboard).toBeDefined();
    expect(en.creator.metadata).toBeDefined();
  });

  it('should have shared namespace', () => {
    expect(en.shared).toBeDefined();
    expect(en.shared.common).toBeDefined();
    expect(en.shared.auth).toBeDefined();
  });

  it('should have public namespace', () => {
    expect(en.public).toBeDefined();
    expect(en.public.homepage).toBeDefined();
    expect(en.public.footer).toBeDefined();
  });

  it('should not have flat keys (except web for backwards compat)', () => {
    const topLevelKeys = Object.keys(en);
    const allowedKeys = ['recipient', 'creator', 'shared', 'public', 'settings', 'web'];
    const unexpectedKeys = topLevelKeys.filter(k => !allowedKeys.includes(k));
    expect(unexpectedKeys).toEqual([]);
  });
});
```

### 2. Component Tests

```javascript
// tests/components/SecretDisplayCase.spec.js
import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import SecretDisplayCase from '@/components/secrets/canonical/SecretDisplayCase.vue';

describe('SecretDisplayCase i18n', () => {
  it('uses recipient namespace keys', () => {
    const i18n = createI18n({
      legacy: false,
      locale: 'en',
      messages: {
        en: {
          recipient: {
            secret: {
              copy_to_clipboard: 'Copy to Clipboard',
              safely_close_tab: 'You can safely close this tab'
            }
          }
        }
      }
    });

    const wrapper = mount(SecretDisplayCase, {
      global: {
        plugins: [i18n]
      },
      props: {
        secret: 'test-secret-value'
      }
    });

    expect(wrapper.text()).toContain('Copy to Clipboard');
    expect(wrapper.text()).toContain('You can safely close this tab');
  });
});
```

### 3. Visual Regression Tests

Use Playwright to capture screenshots of key pages in each language:

```javascript
// e2e/i18n-visual.spec.js
import { test, expect } from '@playwright/test';

const languages = ['en', 'es', 'fr', 'de', 'ja'];

languages.forEach(lang => {
  test.describe(`Visual tests for ${lang}`, () => {
    test('recipient secret view', async ({ page }) => {
      await page.goto(`/secret/test-key?lang=${lang}`);
      await expect(page).toHaveScreenshot(`recipient-${lang}.png`);
    });

    test('creator dashboard', async ({ page }) => {
      await page.goto(`/dashboard?lang=${lang}`);
      await expect(page).toHaveScreenshot(`dashboard-${lang}.png`);
    });
  });
});
```

---

## Rollout Plan

### Phase 1: Preparation (Week 1)
- [ ] Create new locale structure in en.json
- [ ] Set up migration mapping document
- [ ] Create automated migration scripts
- [ ] Add deprecation warning system

### Phase 2: Implementation (Weeks 2-3)
- [ ] Update all recipient-facing components
- [ ] Update all creator-facing components
- [ ] Update all shared components
- [ ] Migrate flat keys to new namespaces

### Phase 3: Testing (Week 4)
- [ ] Run automated tests
- [ ] Manual QA in multiple languages
- [ ] Fix any missing translations
- [ ] Performance testing

### Phase 4: Translation (Weeks 5-8)
- [ ] Tier 1: Translate recipient keys for all 30 languages
- [ ] Tier 2: Translate creator keys for top 10 languages
- [ ] Tier 3: Community contributions for remaining

### Phase 5: Cleanup (Week 9)
- [ ] Remove deprecated keys
- [ ] Update documentation
- [ ] Add contribution guidelines for translations

---

## Success Metrics

### Code Quality
- [ ] Zero flat keys (except backwards compat in web.*)
- [ ] All components use new namespace structure
- [ ] 100% test coverage for i18n usage
- [ ] Zero console deprecation warnings

### Translation Coverage
- [ ] Tier 1: 100% translated for all 30 languages
- [ ] Tier 2: 100% for top 10 languages, 50%+ for others
- [ ] Tier 3: 50%+ coverage overall

### Cost Reduction
- [ ] 50-70% reduction in initial translation costs for new languages
- [ ] Clear documentation enables community contributions

---

## Maintenance Guidelines

### For Developers

**When adding new components:**
1. Determine user type: Recipient, Creator, or Shared
2. Add keys to appropriate namespace
3. Never add flat keys
4. Document which tier the keys belong to

**Example:**
```vue
<!-- ✅ GOOD -->
<template>
  <button>{{ $t('recipient.secret.click_to_reveal') }}</button>
</template>

<!-- ❌ BAD -->
<template>
  <button>{{ $t('click-here') }}</button>
</template>
```

### For Translators

**Priority order:**
1. Start with `recipient.*` (most important)
2. Then `shared.common.*` and `shared.auth.*`
3. Then `creator.dashboard.*` and `creator.metadata.*`
4. Finally `public.*` and `settings.*`

**Context guide:**
- `recipient.*` - Anonymous users viewing secrets
- `creator.*` - Authenticated users managing secrets
- `shared.*` - Used by both types
- `public.*` - Marketing/info pages

---

## Tools & Scripts

### 1. Key Usage Analyzer

```bash
# Find all components using a specific key
./scripts/find-key-usage.sh "web.COMMON.loading"

# List all keys used by recipient components
./scripts/analyze-recipient-keys.sh

# List all keys used by creator components
./scripts/analyze-creator-keys.sh
```

### 2. Translation Coverage Report

```bash
# Generate coverage report for all languages
npm run i18n:coverage

# Output:
# Language: es
# Tier 1 (Recipient): 100% (100/100)
# Tier 2 (Creator): 75% (112/150)
# Tier 3 (Advanced): 30% (60/200)
# Tier 4 (Marketing): 10% (40/400)
```

### 3. Migration Helper

```bash
# Automatically update component i18n keys
npm run i18n:migrate src/components/secrets/canonical/SecretDisplayCase.vue

# Output:
# Updated: web.COMMON.click_to_continue → recipient.secret.click_to_reveal
# Updated: web.private.only_see_once → recipient.secret.warning_view_once
```

---

## Conclusion

This reorganization will:

1. **Reduce translation costs by 50-70%** for new languages
2. **Improve code maintainability** with clear namespace structure
3. **Enable targeted translation** efforts (recipient experience first)
4. **Provide better developer experience** with clear conventions
5. **Support gradual rollout** without breaking existing functionality

The key is to separate recipient-facing keys (high priority, ~100 keys) from creator-facing keys (~350 keys) and marketing content (~400 keys), allowing strategic investment in translations based on user impact.
