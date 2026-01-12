# Locale Key Analysis: feature-organizations.json

## File Overview

The `feature-organizations.json` file contains 107 translation keys organized under `web.organizations`. The file covers:

1. **Core Organization Management** - CRUD operations, listing, selection
2. **Form Fields & Validation** - Name, description, email inputs with placeholders
3. **UI Labels & Settings** - Tabs, settings sections, timestamps
4. **Error Messages** - Load, create, update, delete failures
5. **Onboarding/Help Text** - Getting started, about sections
6. **Invitations Subsystem** - Complete invitation workflow (lines 61-107)

---

## Potentially Misplaced Keys

### 1. Generic UI Elements (Move to `_common.json`)

These keys duplicate or closely mirror existing common translations:

| Key | Current Location | Recommended Destination | Rationale |
|-----|------------------|------------------------|-----------|
| `create` | `web.organizations.create` | `web.LABELS.create` | Generic action label |
| `delete` | `web.organizations.delete` | `web.LABELS.delete` | Generic action label |
| `save_changes` | `web.organizations.save_changes` | Already exists: `web.COMMON.save_changes` | Duplicate |
| `danger_zone` | `web.organizations.danger_zone` | Already exists: `web.COMMON.danger_zone` | Duplicate |
| `created` | `web.organizations.created` | `web.STATUS.created` | Already exists in STATUS |
| `last_updated` | `web.organizations.last_updated` | `web.LABELS.last_updated` | Common timestamp label |
| `default` | `web.organizations.default` | `web.COMMON.default` | Generic label |
| `not_found` | `web.organizations.not_found` | Pattern exists: `web.COMMON.not-found` | Generic 404 pattern |

### 2. Billing-Related Keys (Move to `account-billing.json`)

These keys belong with billing/subscription concerns:

| Key | Recommended Destination | Rationale |
|-----|------------------------|-----------|
| `contact_email` | `web.billing.organization.contact_email` | Labeled as "Billing Email" |
| `contact_email_help` | `web.billing.organization.contact_email_help` | Billing/admin context |
| `billing_settings` | `web.billing.navigation.billing_settings` | Billing section |
| `billing_coming_soon` | `web.billing.notices.coming_soon` | Billing feature status |
| `billing_coming_soon_description` | `web.billing.notices.coming_soon_description` | Billing feature status |
| `tabs.billing` | `web.billing.navigation.tab` | Billing tab |

### 3. Branding-Related Keys (Move to `feature-branding.json`)

Company branding belongs with the branding feature:

| Key | Recommended Destination | Rationale |
|-----|------------------------|-----------|
| `tabs.company_branding` | `web.branding.navigation.company_branding_tab` | Branding context |

---

## Suggested Hierarchy Improvements

### Current Structure Issues

1. **Flat namespace at top level** - Most keys are direct children of `web.organizations`, making it hard to find related keys.

2. **Inconsistent nesting** - Only `tabs` and `invitations` use sub-objects while everything else is flat.

3. **Mixed concerns** - Form fields, error messages, and UI labels intermixed.

### Recommended Restructure

```json
{
  "web": {
    "organizations": {
      "entity": {
        "singular": "Organization",
        "plural": "Organizations",
        "description": "Manage your organizations"
      },
      "list": {
        "title": "Organizations",
        "empty": "No organizations yet",
        "empty_description": "Organizations provide unified billing...",
        "select": "Select an organization"
      },
      "create": {
        "title": "New Organization",
        "first": "Create First Organization",
        "button": "Create Organization",
        "description": "Create a new organization"
      },
      "form": {
        "name": {
          "label": "Organization Name",
          "placeholder": "e.g. Acme Corporation"
        },
        "description": {
          "label": "Description",
          "placeholder": "What is this organization for?"
        }
      },
      "settings": {
        "title": "Organization Settings",
        "description": "Update your organization name and description",
        "general": "General Settings",
        "information": "Organization Information"
      },
      "delete": {
        "button": "Delete Organization",
        "warning": "This will permanently delete...",
        "confirm_title": "Delete Organization",
        "confirm_message": "Are you sure you want to delete {name}?"
      },
      "errors": {
        "create": "Failed to create organization",
        "load": "Failed to load organization",
        "load_list": "Failed to load organizations",
        "update": "Failed to update organization",
        "delete": "Failed to delete organization",
        "not_found": "Organization not found"
      },
      "success": {
        "update": "Organization updated successfully"
      },
      "help": {
        "about_title": "About Organizations",
        "about_description": "Organizations provide unified billing...",
        "getting_started_title": "Getting Started with Organizations",
        "getting_started_description": "Create your first organization..."
      },
      "tabs": { ... },
      "invitations": { ... }
    }
  }
}
```

---

## Invitations Subsystem Analysis

The `invitations` sub-object (lines 61-107) is well-structured but could be its own file given its size (47 keys) and distinct functionality.

### Consider: New File `feature-organizations-invitations.json`

**Pros:**
- Clear separation of concerns
- Invitation logic is distinct from org management
- Easier to maintain independently

**Cons:**
- Adds file count
- May be overkill if invitations remain tightly coupled

### If keeping inline, suggested improvements:

```json
"invitations": {
  "entity": {
    "title": "Organization Invitations",
    "pending": "Pending Invitations",
    "empty": "No pending invitations"
  },
  "form": {
    "email_label": "Email Address",
    "email_placeholder": "member@example.com",
    "role_label": "Role"
  },
  "actions": {
    "invite": "Invite Member",
    "invite_new": "Invite New Member",
    "send": "Send Invitation",
    "resend": "Resend",
    "revoke": "Revoke",
    "accept": "Accept Invitation",
    "decline": "Decline Invitation"
  },
  "status": { ... },
  "roles": { ... },
  "success": {
    "sent": "Invitation sent successfully",
    "resent": "Invitation resent successfully",
    "revoked": "Invitation revoked successfully",
    "accepted": "Invitation accepted successfully",
    "declined": "Invitation declined"
  },
  "errors": {
    "send": "Failed to send invitation",
    "resend": "Failed to resend invitation",
    "revoke": "Failed to revoke invitation",
    "accept": "Failed to accept invitation",
    "decline": "Failed to decline invitation",
    "expired": "This invitation has expired",
    "invalid_token": "Invalid or expired invitation"
  },
  "recipient": {
    "details": "Invitation Details",
    "you_are_invited": "You've been invited to join",
    "invited_as": "You've been invited as a",
    "must_sign_in": "Please sign in to accept this invitation",
    "loading": "Loading invitation details"
  },
  "meta": {
    "invited_by": "Invited by",
    "invited_at": "Invited",
    "expires_at": "Expires",
    "resent_count": "Resent {count} time",
    "resent_count_plural": "Resent {count} times"
  }
}
```

---

## Duplicate Keys with `_common.json`

The following keys already exist in `_common.json` and should use references:

| `feature-organizations.json` | `_common.json` Equivalent |
|------------------------------|---------------------------|
| `save_changes` | `web.COMMON.save_changes` |
| `danger_zone` | `web.COMMON.danger_zone` |
| `created` | `web.STATUS.created` |
| `tabs.general` | `web.COMMON.general` |

---

## New File Suggestions

### 1. `feature-members.json` (Future consideration)

If team/member management expands beyond invitations, consider:
- Member listing
- Role management
- Member permissions
- Member removal

Currently these concerns are minimal, so not immediately necessary.

### 2. No immediate new files recommended

The billing keys should move to `account-billing.json` rather than creating a new file. The branding tab reference should move to `feature-branding.json`.

---

## Summary of Recommendations

1. **Remove duplicates** - Use existing `_common.json` keys for generic labels
2. **Move billing keys** - 6 keys should relocate to `account-billing.json`
3. **Move branding tab** - 1 key should relocate to `feature-branding.json`
4. **Restructure hierarchy** - Group by concern (entity, list, create, form, settings, delete, errors, success, help)
5. **Keep invitations inline** - Current nesting is appropriate for the scope
6. **Consider invitation restructure** - Apply similar grouping pattern within invitations subsystem
