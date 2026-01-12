# Locale Analysis: colonel.json

## File Overview

The `colonel.json` file contains locale keys for the admin/colonel interface. It is structured under `web.colonel` with one misplaced sibling namespace `web.feedback`.

### Current Key Categories

| Category | Key Pattern | Count | Description |
|----------|-------------|-------|-------------|
| **Truncated/Generated Keys** | Long hyphenated keys | 6 | Appear auto-generated or truncated |
| **Config Editor** | `configEditor*`, `invalidJson`, `*Error`, `*Saved` | 11 | Configuration editing UI |
| **Navigation** | `dashboard`, `admin`, `activity`, etc. | 9 | Admin panel navigation labels |
| **Welcome/Intro** | `welcome`, `welcomeDesc`, `quickActions` | 5 | Dashboard welcome section |
| **Stats (nested)** | `stats.*` | 8 | Statistics display labels |
| **Actions (nested)** | `actions.*` | 8 | Quick action buttons and descriptions |
| **Background Jobs** | `backgroundJobs`, `queue*`, `worker*` | 10 | Job queue monitoring UI |
| **Test Plan Mode** | `testPlanMode`, `testing*`, `*Plan*` | 11 | Plan testing/override functionality |

---

## Misplaced Keys

### 1. `web.feedback` Section (Lines 87-91)

**Current Location:** `colonel.json` under `web.feedback`

**Recommended Destination:** `feature-feedback.json`

**Keys to Move:**
```json
{
  "web.feedback.when-you-submit-feedback-well-see": "When you submit feedback, we'll see:",
  "web.feedback.send-feedback": "Send feedback",
  "web.feedback.sending-ellipses": "Sending..."
}
```

**Rationale:** The `feature-feedback.json` file already exists and contains the `web.feedback` namespace. These keys should be consolidated there to maintain single-responsibility file organization.

---

## Hierarchy Improvements

### 1. Truncated/Generated Keys Need Cleanup

The following keys appear to be auto-generated or poorly structured:

| Current Key | Suggested Restructure |
|-------------|----------------------|
| `customer-secrets_created-customer-secrets_shared-0` | `stats.customerSecretsFormat` |
| `customer-verified-verified-not-verified-0` | `stats.verificationStatus` |
| `customers-details-counts-recent_customer_count-o-0` | `stats.customerCountFormat` |
| `user-feedback-total-details-counts-feedback_coun-0` | `stats.feedbackCountFormat` |
| `metadata-secrets-details-counts-metadata_count-d-0` | `stats.metadataSecretsFormat` |
| `secrets-details-counts-secret_count-0` | `stats.secretCountFormat` |
| `active-in-the-past-5-minutes-0` | `stats.activeRecently` |

**Rationale:** These keys break naming conventions (hyphenated, truncated, numeric suffixes) and should follow camelCase patterns consistent with the rest of the file.

### 2. Config Editor Keys Should Be Nested

**Current:** Flat keys at root level
```
configEditorTitle
configEditorDescription
invalidJson
validationError
errorFetchingConfig
...
```

**Suggested:** Nested under `configEditor` namespace
```json
{
  "configEditor": {
    "title": "Settings",
    "description": "Edit system configuration settings...",
    "invalidJson": "Invalid JSON in {section} section",
    "validation": {
      "error": "Validation error",
      "schemaError": "Schema validation error: {message} ({path})",
      "unknownError": "Unknown validation error: {error}",
      "mustBeObject": "Configuration must be a JSON object",
      "multipleSectionsInvalid": "Multiple sections have validation errors: {sections}",
      "sectionHasError": "{section} has validation errors: {error}"
    },
    "status": {
      "errorFetching": "Error loading configuration",
      "errorSaving": "Error saving configuration",
      "saved": "Configuration saved successfully",
      "sectionSaved": "{section} saved successfully",
      "sectionEmpty": "{section} section has no configured values"
    },
    "actions": {
      "saveSection": "Save {section}",
      "saveAll": "Save All"
    },
    "unsavedChanges": "Unsaved changes"
  }
}
```

### 3. Background Jobs Should Be Nested

**Current:** Flat keys at root level
**Suggested:** Nested under `jobs` or `backgroundJobs` namespace
```json
{
  "jobs": {
    "title": "Background Jobs",
    "queue": {
      "status": "Queue Status",
      "name": "Queue",
      "pending": "Pending",
      "noData": "No queue data available",
      "loading": "Loading queue data..."
    },
    "workers": {
      "health": "Worker Health",
      "active": "active workers",
      "consumers": "Consumers",
      "processingRate": "Rate/sec"
    },
    "connectionStatus": "Connection Status"
  }
}
```

### 4. Test Plan Mode Should Be Nested

**Current:** Flat keys with `testPlanMode`, `testingAsPlan`, etc.
**Suggested:** Nested under `testMode` namespace
```json
{
  "testMode": {
    "title": "Test Plan Mode",
    "testingAs": "Testing as {planName}",
    "clickToReset": "Click to reset",
    "selectPlan": "Select a plan to test",
    "resetToActual": "Reset to actual plan",
    "currentActualPlan": "Current plan",
    "availablePlans": "Available plans",
    "activate": "Activate test mode",
    "active": "Test mode active",
    "description": "Test your application with different plan entitlements...",
    "warning": "You are testing with {planName} entitlements..."
  }
}
```

---

## New File Suggestions

No new files are recommended. The keys in `colonel.json` are appropriately scoped to admin functionality. However, the following consolidations should occur:

1. **Move `web.feedback` keys to `feature-feedback.json`** - This is a clear case of misplacement.

---

## Summary of Recommended Changes

| Priority | Change | Impact |
|----------|--------|--------|
| High | Move `web.feedback` to `feature-feedback.json` | File organization |
| High | Rename truncated/generated keys to camelCase | Consistency, maintainability |
| Medium | Nest `configEditor*` keys under `configEditor` | Logical grouping |
| Medium | Nest `backgroundJobs`/`queue*`/`worker*` under `jobs` | Logical grouping |
| Medium | Nest `testPlanMode*` keys under `testMode` | Logical grouping |
| Low | Consider moving `stats` and `actions` nested objects out of flat structure (already properly nested) | N/A - already done |

---

## Keys That Are Well-Organized

The following patterns are already good:
- `stats.*` - Properly nested statistics labels
- `actions.*` - Properly nested action descriptions
- Navigation labels (`dashboard`, `admin`, `activity`, etc.) - Simple, clear, flat is appropriate
- Welcome section keys - Simple, flat is appropriate
