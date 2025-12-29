# Email Locale File Analysis

**File:** `/Users/d/Projects/opensource/onetime/onetimesecret/src/locales/en/email.json`
**Analyzed:** 2025-12-27

## File Overview

The `email.json` file contains 40 lines with a single top-level `email` namespace containing 5 categories:

| Category | Keys | Purpose |
|----------|------|---------|
| `incomingsupport` | 2 | Support ticket email templates |
| `secretlink` | 3 | Secret sharing notification emails |
| `welcome` | 5 | Account verification/welcome emails |
| `organization_invitation` | 10 | Organization invitation emails (including nested `roles`) |
| `common` | 4 | Shared email UI elements |

**Total key count:** ~24 leaf keys

---

## Potentially Misplaced Keys

### 1. `email.organization_invitation.roles`

```json
"roles": {
  "member": "a member",
  "admin": "an administrator"
}
```

**Issue:** Role labels are duplicated. The `feature-organizations.json` file already defines:
```json
"invitations.roles.member": "Member"
"invitations.roles.admin": "Admin"
```

**Recommendation:**
- Remove `email.organization_invitation.roles` from `email.json`
- Reference the existing roles from `feature-organizations.json` or create email-specific variants in the organization file under a namespace like `invitations.email_roles`

**Destination:** `feature-organizations.json` under `web.organizations.invitations.email_roles`

---

### 2. `email.incomingsupport`

```json
"incomingsupport": {
  "subject": "[Ticket: %s]",
  "body1": "A customer has sent the following info"
}
```

**Issue:** The "incoming" feature already has its own file (`feature-incoming.json`) which handles incoming secret functionality. Support-related email templates for incoming secrets should be co-located with that feature.

**Recommendation:** Move to `feature-incoming.json` under a new namespace `incoming.email` or create consistency by keeping email templates together but renaming for clarity.

**Option A (preferred):** Keep in `email.json` but rename to `email.support_ticket` for clarity
**Option B:** Move to `feature-incoming.json` as `incoming.email.support_notification`

---

## Hierarchy Improvement Suggestions

### Current Structure Issues

1. **Inconsistent nesting depth:** `organization_invitation` has nested `roles` while other categories are flat
2. **Inconsistent naming:** Mix of snake_case (`organization_invitation`) and single words (`welcome`, `common`)
3. **Missing structure:** No separation between transactional emails vs. system emails

### Proposed Hierarchy

```json
{
  "email": {
    "transactional": {
      "secret_shared": {
        "subject": "...",
        "body": "...",
        "tagline": "..."
      },
      "welcome": {
        "subject": "...",
        "body": "...",
        "verify_cta": "...",
        "postscript": "..."
      },
      "organization_invitation": {
        "subject": "...",
        "body": "...",
        "accept_cta": "...",
        "decline_instruction": "...",
        "expiry_notice": "..."
      }
    },
    "system": {
      "support_ticket": {
        "subject": "...",
        "body": "..."
      }
    },
    "common": {
      "greeting": "...",
      "thanks": "...",
      "unsubscribe": "...",
      "view_in_browser": "..."
    }
  }
}
```

### Benefits
- Clear separation between user-facing transactional emails and internal system emails
- Consistent nesting depth
- Easier to locate email types
- Scales better as new email types are added

---

## New File Suggestions

The current `email.json` is appropriately sized (~40 lines) and does not warrant splitting. However, if the email system grows significantly, consider:

### Future Consideration: `email-templates.json`

If the project adds HTML email templates with extensive copy blocks, a separate file may be warranted for:
- Full HTML email body content
- Rich text formatting strings
- Footer/header content blocks

**Current recommendation:** Keep as single `email.json` file.

---

## Consistency Observations

### Positive Patterns
- Uses `email` as top-level namespace (matches other files using `web`, `incoming`, etc.)
- Keeps email-specific content isolated from UI strings
- `common` section for reusable elements

### Areas for Alignment

1. **Namespace consistency:** Other files use `web` as top-level namespace. Consider whether `email` should be nested under `web` for consistency:
   ```json
   { "web": { "email": { ... } } }
   ```

2. **Placeholder format inconsistency:**
   - Uses `%s` (C-style): `"subject": "[Ticket: %s]"`
   - Uses `%{var}` (Ruby-style): `"subject": "You've been invited to join %{organization_name}"`

   **Recommendation:** Standardize on `%{named}` placeholders for clarity and maintainability.

---

## Summary of Recommended Actions

| Priority | Action | Effort |
|----------|--------|--------|
| Low | Remove duplicate `roles` from `email.organization_invitation` | Minimal |
| Low | Standardize placeholder format to `%{named}` style | Low |
| Medium | Rename `secretlink` to `secret_shared` for clarity | Low |
| Medium | Rename `incomingsupport` to `support_ticket` for clarity | Low |
| Low | Consider nesting under `web` namespace for consistency | Medium |

---

## File Statistics

- **Lines:** 41
- **Top-level namespaces:** 1 (`email`)
- **Second-level categories:** 5
- **Leaf keys:** ~24
- **Nested objects:** 1 (`roles` under `organization_invitation`)
