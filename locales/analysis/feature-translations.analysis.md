# Analysis: feature-translations.json

## File Overview

This file contains keys under `web.translations` that are specifically about the **translations/localization contribution page**. The content describes how users can contribute translations to Onetime Secret, credits to translation contributors, and instructions for submitting translations.

### Current Key Categories

All 23 keys relate to a single domain: **Translation Contributor Page**

| Category | Key Count | Description |
|----------|-----------|-------------|
| Page content/marketing | 8 | Introductory text, history, mission |
| Contributor acknowledgment | 4 | Thanks to translators, contributor count |
| How-to instructions | 6 | Steps to contribute translations |
| Labels/titles | 3 | Section headers, link text |
| Calls-to-action | 2 | Contact, GitHub references |

## Key Structure Analysis

### Naming Convention Issues

The keys use a slugified-sentence pattern (e.g., `welcomes-contributors-for-both-existing-and-new-`) which is:
1. **Inconsistent** with other locale files that use `camelCase` or `snake_case`
2. **Truncated** - some keys are cut off mid-word (see trailing `-`)
3. **Not semantic** - keys describe content rather than purpose

**Examples of problematic keys:**
- `welcomes-contributors-for-both-existing-and-new-` (truncated)
- `whove-helped-with-translations-as-we-continue-to` (truncated)
- `as-we-add-new-features-our-translations-graduall` (truncated)
- `remember-to-include-your-email-if-youre-not-logg` (truncated)

### Recommended Key Renames

Current keys should follow semantic naming like other files:

| Current Key | Suggested Key |
|-------------|---------------|
| `translations` | `page_title` |
| `help-secure-communication-go-global` | `hero_headline` |
| `since-2012-onetime-secret-has-provided-a-secure-` | `mission_statement` |
| `thanks-to-our-community-we-support-over-20-langu` | `community_impact` |
| `as-we-add-new-features-our-translations-graduall` | `ongoing_need` |
| `ready-to-help-some-ways-to-contribute` | `contribution_intro` |
| `review-existing-translations-using-the-language-` | `step_review` |
| `update-a-language-directly-through-our-github-pr` | `step_update` |
| `start-a-new-translation-from-our` | `step_new_translation` |
| `english-template` | `english_template_label` |
| `send-translations-by-email-to` | `step_email` |
| `have-questions` | `questions_label` |
| `reach-out-to-us` | `contact_link` |
| `remember-to-include-your-email-if-youre-not-logg` | `email_reminder` |
| `the-following-people-have-donated-their-time-to-` | `contributors_intro` |
| `were-grateful-to-the` | `gratitude_intro` |
| `25-contributors` | `contributor_count` |
| `whove-helped-with-translations-as-we-continue-to` | `gratitude_continuation` |
| `if-youre-interested-in-translation` | `interest_intro` |
| `our-github-project` | `github_link_label` |
| `welcomes-contributors-for-both-existing-and-new-` | `contribution_welcome` |
| `your-language-skills-can-help-expand-access-to-s` | `call_to_action` |
| `fork-on-github-and-submit-a-pr` | `github_cta` |

## Potentially Misplaced Keys

**None identified.** All keys in this file are cohesive and specifically relate to the translations/localization contribution page. This is a well-scoped feature file.

## Hierarchy Improvements

### Current Structure
```json
{
  "web": {
    "translations": {
      // flat list of 23 keys
    }
  }
}
```

### Suggested Structure
Organize keys into logical subsections:

```json
{
  "web": {
    "translations": {
      "page": {
        "title": "Translations",
        "hero_headline": "Help Secure Communication Go Global",
        "mission_statement": "Since 2012...",
        "community_impact": "Thanks to our community...",
        "ongoing_need": "As we add new features..."
      },
      "contribute": {
        "intro": "Ready to help? Some ways to contribute:",
        "step_review": "Review existing translations...",
        "step_update": "Update a language directly...",
        "step_new": "Start a new translation from our",
        "step_email": "Send translations by email to",
        "english_template": "English template",
        "github_cta": "Fork on GitHub and Submit a PR"
      },
      "contact": {
        "questions_label": "Have questions?",
        "link_text": "Reach out to us",
        "email_reminder": "- remember to include your email..."
      },
      "contributors": {
        "intro": "The following people have donated...",
        "gratitude": "We're grateful to the",
        "count": "25+ contributors",
        "continuation": "who've helped with translations..."
      },
      "cta": {
        "interest_intro": "If you're interested in translation,",
        "github_link": "our GitHub project",
        "welcome_message": "welcomes contributors...",
        "call_to_action": "Your language skills can help..."
      }
    }
  }
}
```

## New File Suggestions

**No new files needed.** The file is appropriately scoped as a feature file (`feature-translations.json`). The content is cohesive and belongs together.

## Comparison with Other Feature Files

| File | Nesting Depth | Key Style |
|------|---------------|-----------|
| `feature-translations.json` | 1 level | slugified-sentences (inconsistent) |
| `feature-feedback.json` | 1 level | slugified-sentences |
| `feature-domains.json` | varies | mixed |
| `_common.json` | 2-3 levels | snake_case/camelCase |

## Recommendations Summary

1. **High Priority**: Rename truncated keys to semantic names
2. **Medium Priority**: Restructure into logical subsections (page, contribute, contact, contributors, cta)
3. **Low Priority**: Align key naming convention with `_common.json` patterns (snake_case)

## Notes

- The file correctly uses the `web.translations` namespace which is appropriate
- All keys are actively used for the translation contribution page
- No keys appear to be duplicated in other locale files
