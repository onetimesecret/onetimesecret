# Locale File Analysis: feature-branding.json

## File Overview

**Path:** `src/locales/en/feature-branding.json`
**Structure:** `web.branding.*` (flat hierarchy, 42 keys total)

### Categories of Keys Present

| Category | Count | Examples |
|----------|-------|----------|
| UI Controls | 8 | `color-picker`, `font-family`, `corner-style`, `brand-color` |
| Window/Browser Controls | 8 | `maximize-window`, `minimize-window`, `switch-to-*-browser-view` |
| Instructions (Pre/Post Reveal) | 7 | `pre-reveal-instructions`, `post-reveal-instructions`, `example-*-instructions` |
| Logo Management | 5 | `upload-logo`, `logo-controls`, `heading-logo`, `default-logo-icon` |
| Preview Interface | 5 | `loading-preview`, `preview-and-customize`, `preview-*` |
| Help/Guidance Text | 4 | `this-is-an-interactive-preview-*`, `use-the-controls-*` |
| Status/Notifications | 2 | `you-have-unsaved-changes-*`, `failed-to-load-brand-settings` |
| ARIA/Accessibility | 3 | `eye-icon`, `image-icon`, `customization-icon` |

---

## Potentially Misplaced Keys

### 1. Generic UI Labels (Move to `_common.json`)

These keys represent generic UI patterns that could be reused elsewhere:

| Key | Recommended Location | Rationale |
|-----|---------------------|-----------|
| `color-picker` | `web.LABELS.color_picker` | Generic UI component label |
| `use-setting` | `web.LABELS.use_setting` | Generic action label |
| `loading-preview` | `web.LABELS.loading_preview` or `web.STATUS.loading_preview` | Generic loading state |
| `charactercount-500-characters` | `web.LABELS.character_count` | Reusable character counter pattern |

### 2. Window Controls (Move to `_common.json` or new `ui-components.json`)

These browser/window control labels are not branding-specific:

| Key | Recommended Location | Rationale |
|-----|---------------------|-----------|
| `maximize-window` | `web.LABELS.maximize_window` | Generic window control |
| `minimize-window` | `web.LABELS.minimize_window` | Generic window control |
| `microsoft-edge` | `web.LABELS.browsers.edge` | Browser name reference |
| `edge` | `web.LABELS.browsers.edge` | Duplicate of above |
| `safari` | `web.LABELS.browsers.safari` | Browser name reference |

### 3. ARIA/Icon Labels (Move to `_common.json`)

Accessibility labels that could be shared:

| Key | Recommended Location | Rationale |
|-----|---------------------|-----------|
| `eye-icon` | `web.ARIA.eye_icon` | Generic icon description |
| `image-icon` | `web.ARIA.image_icon` | Generic icon description |
| `customization-icon` | `web.ARIA.customization_icon` | Could be reused |

### 4. Status Messages (Move to `_common.json`)

| Key | Recommended Location | Rationale |
|-----|---------------------|-----------|
| `you-have-unsaved-changes-are-you-sure` | `web.COMMON.unsaved_changes_warning` | Universal UX pattern |
| `failed-to-load-brand-settings` | Keep here | Branding-specific error |

---

## Hierarchy Improvements

### Current Structure (Flat)
```
web.branding.color-picker
web.branding.font-family
web.branding.preview-and-customize
web.branding.pre-reveal-instructions
...
```

### Recommended Structure (Grouped)
```json
{
  "web": {
    "branding": {
      "controls": {
        "color_picker": "...",
        "font_family": "...",
        "corner_style": "...",
        "brand_color": "..."
      },
      "logo": {
        "upload": "...",
        "controls": "...",
        "heading": "...",
        "default_icon": "...",
        "upload_hint": "..."
      },
      "preview": {
        "title": "...",
        "loading": "...",
        "description": "...",
        "recipient_view": "..."
      },
      "instructions": {
        "section_title": "Instructions",
        "pre_reveal": {
          "label": "...",
          "description": "...",
          "example": "..."
        },
        "post_reveal": {
          "label": "...",
          "description": "...",
          "example": "..."
        }
      },
      "browser_preview": {
        "switch_to_safari": "...",
        "switch_to_edge": "..."
      },
      "status": {
        "unsaved_changes": "...",
        "load_failed": "..."
      }
    }
  }
}
```

---

## Duplicate/Redundant Keys

| Keys | Issue | Resolution |
|------|-------|------------|
| `edge` and `microsoft-edge` | Duplicate browser name | Keep one (e.g., `edge`) |
| `switch-to-edge-browser-view` and `switch-to-edge-preview` | Overlapping meaning | Consolidate to one key |
| `switch-to-safari-browser-view` and `switch-to-safari-preview` | Overlapping meaning | Consolidate to one key |
| `this-is-an-interactive-preview-o` and `this-is-an-interactive-preview-of-how-recipients` | Duplicate with truncation | Remove truncated version |

---

## Key Naming Issues

### Inconsistent Naming Conventions

| Current Key | Issue | Suggested Key |
|-------------|-------|---------------|
| `current-label-modelvalue-click-to-cycle-through-options` | Too verbose, implementation details in key | `cycle_option_hint` |
| `click-to-upload-a-logo-with-recommendation` | Too verbose | `logo_upload_hint` |
| `preview-of-the-secret-link-page-for-recipients` | Too verbose | `preview.recipient_description` |
| `use-the-controls-above-to-customize-brand-details` | Includes UI position | `customize_hint` |
| `powered-by-onetime-secret` | Should use `{0}` placeholder | `powered_by` with param |

---

## New File Suggestions

### 1. `ui-preview.json` (Optional)

If the preview/browser frame pattern is used elsewhere (e.g., email previews, other feature previews), consider extracting:

```json
{
  "web": {
    "preview": {
      "browser_frame": {
        "maximize": "Maximize window",
        "minimize": "Minimize window",
        "browsers": {
          "safari": "Safari",
          "edge": "Edge",
          "chrome": "Chrome"
        },
        "switch_to": "Switch to {browser} preview"
      }
    }
  }
}
```

**Recommendation:** Not immediately necessary. Only create if preview patterns are reused.

---

## Summary of Recommended Actions

### Priority 1: Remove Duplicates
- Delete `this-is-an-interactive-preview-o` (truncated duplicate)
- Consolidate `edge` / `microsoft-edge` to single key
- Consolidate `switch-to-*-browser-view` / `switch-to-*-preview` pairs

### Priority 2: Move to `_common.json`
- Generic labels: `color-picker`, `loading-preview`
- ARIA labels: `eye-icon`, `image-icon`, `customization-icon`
- Status pattern: `you-have-unsaved-changes-are-you-sure`

### Priority 3: Restructure Hierarchy
- Group related keys under `controls`, `logo`, `preview`, `instructions` namespaces
- Improves maintainability and discoverability

### Priority 4: Rename Verbose Keys
- Shorten overly descriptive key names
- Remove implementation details from key names (e.g., `modelvalue`, `above`)

---

## Key Count Summary

| Action | Keys Affected |
|--------|---------------|
| Remove (duplicates) | 3 |
| Move to `_common.json` | 8 |
| Rename (simplify) | 5 |
| Keep in place | 26 |
