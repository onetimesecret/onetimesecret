# Locale Analysis: feature-domains.json

## File Overview

**Path:** `src/locales/en/feature-domains.json`
**Structure:** `web.domains.*` (flat hierarchy, 90 keys)

### Key Categories Identified

1. **Domain Management UI** - Core domain CRUD operations
2. **Privacy/Security Settings** - TTL, passphrase, notification defaults
3. **DNS Verification** - Record types, verification steps, instructions
4. **SSL/Status Monitoring** - SSL status, monitoring, domain status
5. **Success/Error Messages** - Toast notifications, confirmations
6. **Generic UI Labels** - Buttons, toggles, state indicators

---

## Potentially Misplaced Keys

### 1. Generic Labels -> `_common.json`

These keys are too generic and likely duplicated or should be shared:

| Key | Current Location | Recommended | Rationale |
|-----|------------------|-------------|-----------|
| `required` | `web.domains` | `web.COMMON` | Generic term used across forms |
| `optional` | `web.domains` | `web.COMMON` | Generic term used across forms |
| `enabled` | `web.domains` | `web.COMMON` | Generic state indicator |
| `disabled` | `web.domains` | `web.COMMON` | Generic state indicator |
| `custom` | `web.domains` | `web.COMMON` | Generic term |
| `domain` | `web.domains` | `web.COMMON` | Could be used elsewhere |
| `value-0`, `value-1`, `value-2` | `web.domains` | `web.COMMON.value` | Already exists as `web.COMMON.value` |
| `host-0`, `host-1` | `web.domains` | `web.COMMON.host` | Already exists as `web.COMMON.host` |
| `type-0`, `type-1`, `type-2` | `web.domains` | `web.COMMON.type` | Already exists as `web.COMMON.type` |

### 2. Privacy Defaults -> New File or `feature-secrets.json`

Privacy default settings relate more to secret creation than domain management:

| Key | Recommended Destination | Rationale |
|-----|------------------------|-----------|
| `privacy_defaults_title` | `feature-secrets.json` or new `feature-privacy.json` | Secret-centric setting |
| `privacy_defaults_description` | Same | Secret-centric setting |
| `privacy_defaults` | Same | Secret-centric setting |
| `privacy_defaults_icon` | Same | Accessibility for above |
| `default_ttl_label` | Same | TTL is a secret attribute |
| `default_ttl_hint` | Same | TTL is a secret attribute |
| `passphrase_required_label` | Same | Passphrase is a secret attribute |
| `passphrase_required_hint` | Same | Passphrase is a secret attribute |
| `notify_enabled_label` | Same | Notification is a secret attribute |
| `notify_enabled_hint` | Same | Notification is a secret attribute |
| `use_global_default` | `_common.json` | Generic setting pattern |
| `global_default` | `_common.json` | Generic label |
| `ttl_short` | `feature-secrets.json` | TTL abbreviation |
| `passphrase_short` | `feature-secrets.json` | Already has passphrase keys |
| `notify_short` | `feature-secrets.json` or `_common.json` | Generic notification term |

### 3. Status Labels -> `_common.json` under `STATUS`

| Key | Recommended | Rationale |
|-----|-------------|-----------|
| `ssl-status` | `web.STATUS` | Status indicator pattern |
| `domain-status` | `web.STATUS` | Status indicator pattern |
| `active` (if not already shared) | `web.STATUS.active` | Already exists in `_common.json` |

---

## Hierarchy Improvements

### Current (Flat Structure)
```
web.domains.learn-more-dns
web.domains.verify-domain
web.domains.domain-verification-steps
web.domains.1-create-a-txt-record
web.domains.2-create-the-cname-record
...
```

### Recommended (Nested Structure)

```json
{
  "web": {
    "domains": {
      "management": {
        "add_domain": "Add Domain",
        "remove_domain": "Remove Domain",
        "back_to_domains": "Back to Domains",
        "no_domains_found": "No domains found.",
        "loading": "Loading domain information...",
        "custom_domains_count": "Custom domains count"
      },
      "verification": {
        "title": "Domain Verification Steps",
        "description": "Follow these steps to verify domain ownership...",
        "steps": {
          "create_txt_record": "1. Create a TXT record",
          "create_cname_record": "2. Create the CNAME record",
          "create_a_record": "2. Create the A record",
          "wait_propagation": "3. Wait for propagation"
        },
        "initiated_success": "Domain verification initiated successfully.",
        "learn_more_dns": "Learn more about DNS configuration"
      },
      "dns": {
        "record": "DNS Record",
        "target_address": "Target Address",
        "cname_instruction": "In order to connect your domain...",
        "apex_note": "Please note that for apex domains...",
        "propagation_note": "DNS changes can take as little as 60 seconds..."
      },
      "ssl": {
        "status": "SSL Status",
        "renews": "SSL Renews",
        "certificate_note": "It may take a few minutes for your SSL certificate..."
      },
      "scope": {
        "switch_label": "Switch domain scope",
        "list_label": "Available domains",
        "header": "Domain Scope"
      },
      "messages": {
        "success": {
          "added": "Domain added successfully",
          "removed": "Domain removed successfully",
          "claimed": "Domain successfully claimed..."
        },
        "error": {
          "failed_to_add": "Failed to add domain",
          "already_in_org": "This domain is already registered in your organization",
          "in_other_org": "This domain is already registered to another organization..."
        }
      }
    }
  }
}
```

---

## Specific Issues

### 1. Duplicate/Redundant Keys

| Keys | Issue |
|------|-------|
| `value-0`, `value-1`, `value-2` | Should use single `value` key with context |
| `host-0`, `host-1` | Should use single `host` key |
| `type-0`, `type-1`, `type-2` | Should use single `type` key |
| `privacy_defaults_title` vs `privacy_defaults` | Redundant naming |
| `add-domain` vs `add_domain` | Inconsistent casing (kebab vs snake) |

### 2. Inconsistent Naming Conventions

The file mixes:
- kebab-case: `learn-more-dns`, `add-domain`, `ssl-status`
- snake_case: `privacy_defaults_title`, `default_ttl_label`
- camelCase: (none found, which is good)

**Recommendation:** Standardize on snake_case to match `_common.json` patterns.

### 3. Overly Long Key Names

| Current Key | Suggested |
|-------------|-----------|
| `added-formatdistancetonow-domain-created-addsuffix-true` | `added_time_ago` |
| `control-whether-users-can-create-secret-links` | `homepage_access_description` |
| `manage-and-configure-your-verified-custom-domains` | `domains_description` |
| `in-order-to-connect-your-domain-youll-need-to-ha` | `cname_setup_instruction` |
| `if-you-already-have-a-cname-record-for-that-addr` | `cname_existing_instruction` |

---

## New File Suggestions

### 1. `feature-privacy.json` (Optional)

If privacy defaults expand, consider extracting:
- Privacy default settings
- TTL configurations
- Passphrase requirements
- Notification preferences

This would serve both domain-level and account-level privacy settings.

### 2. `feature-dns.json` (Optional)

If DNS verification complexity grows, extract:
- All DNS record type explanations
- Verification step instructions
- Propagation guidance
- SSL certificate notes

---

## Summary of Recommendations

1. **Move 12+ generic keys** to `_common.json`
2. **Move 15 privacy-related keys** to `feature-secrets.json` or new `feature-privacy.json`
3. **Restructure flat hierarchy** into nested categories (management, verification, dns, ssl, scope, messages)
4. **Standardize naming** to snake_case
5. **Simplify verbose key names** for maintainability
6. **Remove duplicate keys** (value-0/1/2, host-0/1, type-0/1/2)

---

## Migration Priority

| Priority | Action | Impact |
|----------|--------|--------|
| High | Move generic keys to `_common.json` | Reduces duplication |
| High | Fix inconsistent naming conventions | Improves maintainability |
| Medium | Restructure into nested hierarchy | Better organization |
| Medium | Move privacy keys to appropriate file | Clearer separation of concerns |
| Low | Create new feature files | Only if categories grow significantly |
