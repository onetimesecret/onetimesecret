# PR #4256 — text capitalization and security policy restart brief

**Recorded:** 2026-09-16
**Source:** [Draft PR #4256](https://github.com/onetimesecret/onetimesecret/pull/4256)
**Branch:** `claude/english-content-quality-spccv4`
**Disposition:** Do not revive or merge this branch. Reassess each workstream against the current
tree and implement accepted changes from scratch.

## Purpose

This document preserves what PR #4256 attempted, the useful discoveries it made, and the checks
needed before any part is reimplemented. It is an inventory and restart aid, not an accepted
specification. The PR description, commits, and comments are historical evidence of the attempted
change; they are not authority for product entitlements or security commitments.

## Historical change set

The PR contains three substantive commits and two merges from `main`:

| Commit | Workstream |
| --- | --- |
| `f9248e92f1` | Restructured `SECURITY.md` |
| `066d1e7760` | Changed English UI copy to sentence case, removed unused 404 keys, and regenerated content hashes |
| `470c4b12f3` | Updated hardcoded English UI strings, test assertions/selectors, and a billing example |

At its last update, the PR changed 57 files with 266 insertions and 606 deletions. Most deletions
were the same three unused 404 entries removed from every locale. The branch is now reported by
GitHub as conflicting with `main`.

## 1. English copy normalization

### Attempted scope

The PR converted many buttons, actions, form labels, navigation labels, and calls to action from
title case to sentence case. Representative changes included:

- `Generate Password` → `Generate password`
- `Create Account` → `Create account`
- `Sign In` → `Sign in`
- `Save Changes` → `Save changes`
- `Show More` / `Show Less` → `Show more` / `Show less`
- `Create Secret Link` → `Create secret link`

The pass touched 16 English locale files. It deliberately excluded `web.TITLES.*`, email subject
lines, and proper-noun feature names. Some nearby navigation labels were included so one screen
did not mix capitalization styles.

### Other copy cleanup

The same commit also:

- removed a leading space from the password-generator description;
- removed the trailing space from `web.COMMON.sent_to` after checking that the rendering component
  supplies spacing with CSS;
- normalized some ellipses;
- rewrote a repetitive homepage call-to-action subtitle; and
- regenerated English `content_hash` values.

### Restart constraints

- Locate the current, authoritative voice-and-tone guide before deciding the rule. The guide cited
  by the PR (`translations/universal/voice-and-tone.md`) is not present in this repository or in
  the archived branch, so its quoted sentence-case prescription cannot be validated here.
- Define categories before editing: page title, section heading, navigation label, field label,
  button/action, status, feature name, and email subject. The original pass mixed several of these
  categories in one bulk edit.
- Inventory rendered usage before changing shared keys. A locale key used as both a page title and
  a button label may need to be split rather than globally recased.
- Treat hardcoded component strings as i18n debt. Re-casing them preserves the existing behavior
  of rendering English in every locale; moving them into locale files is a separate decision.
- Regenerate content hashes only after the copy set is final, using the current locale tooling and
  its current rewrite guard.

## 2. Product-entitlement corrections

The capitalization pass also changed four billing messages and one example comment:

| Prior text | Proposed text in PR #4256 |
| --- | --- |
| Team management requires Identity Plus or higher | Team management requires Team Plus or higher |
| Custom domains require Identity Plus or higher | Additional custom domains require Identity Plus or higher |
| API access requires Identity Plus or higher | Full API access requires a signed-in account |
| Audit logs require Multi-Team plan or higher | Audit logs require Team Plus or higher |
| Team Plan | Team Plus |

These are functional product claims, not capitalization edits. The PR description says they were
checked against `pricing/compare-plans.md` in a separate documentation repository, but that source
is not available in this checkout. The proposed wording is therefore unverified here.

### Restart constraints

- Revalidate every entitlement against the current canonical plan catalog and billing enforcement
  code before changing user-visible text.
- Confirm whether “full API access” is a defined product concept and what access remains available
  without a signed-in account.
- Confirm the included custom-domain count for every tier rather than encoding only the upgrade
  threshold.
- Keep entitlement corrections in a separate commit and review from purely editorial changes.

## 3. Unused 404 locale keys

The PR removed these three entries from all locale `error-pages.json` files:

- `web.errors.oops_the_page_you_are_looking_for_doesnt_exist_o`
- `web.errors.404_page_not_found_0`
- `web.errors.404_page_not_found`

The retained 404 copy was the entry used by `ErrorNotFound.vue` at the time. This produced most of
the PR's deletion count while preserving locale key-set alignment.

### Restart constraints

- Search the current application, tests, generated declarations, and translation tooling for each
  key before deletion.
- Confirm the current locale validation policy for synchronized key removal.
- Make dead-key removal its own commit so it can be reviewed and reverted independently.

## 4. Hardcoded UI copy and tests

The PR recased hardcoded English in:

- `src/apps/secret/components/form/SecretForm.vue` (ARIA label);
- `src/apps/workspace/layouts/WorkspaceLayout.vue`; and
- `src/shared/layouts/ManagementLayout.vue`.

It updated three Playwright files and four unit/a11y spec files whose selectors or fixtures named
the changed visible text. The PR noted that the affected Playwright `:has-text()` selectors were
case-insensitive, so those selector edits were synchronization rather than behavioral fixes.

The layout literals were already outside the locale system. That pre-existing gap should be
re-evaluated instead of copied automatically into a new capitalization pass.

## 5. Security policy rewrite

The proposed `SECURITY.md` rewrite:

- put the reporting address and “do not open a public issue” instruction first;
- represented supported release lines in a table;
- included a time-specific example naming 0.26.x, 0.25.x, and older versions;
- removed the request that first-time reporters attest that they read the policy;
- encouraged early, incomplete reports;
- retained the reporting address and subject-line format;
- expressed acknowledgement, assessment, and update windows more plainly;
- retained confidentiality, encrypted-email, resolution, and no-paid-bounty language; and
- removed the closing emoji.

This section contains normative security, privacy, support, and response-time claims. The prior
`SECURITY.md` is evidence of what the repository said at the branch point, but the PR does not cite
an accepted security specification or operator-approved policy. None of the proposed promises
should be reintroduced without explicit owner approval.

### Commitments requiring fresh approval

- Which release lines receive features, bug fixes, and security updates.
- Whether a moving release-line table or explicit version numbers is preferred.
- Acknowledgement within 5 business days.
- Initial assessment within 14 business days.
- Updates at least once every 5 business days and never more than 7 calendar days apart.
- Confidentiality until a fix is in place.
- Whether ProtonMail should still be named as the encrypted-email provider.
- The no-paid-bounty position and case-by-case reward language.
- Whether the latest GitHub release is authoritative for the supported minor line.

Avoid a time-stamped version example unless there is a reliable maintenance mechanism; the
example in the archived branch is already historical context rather than a safe current claim.

## Validation recorded on the abandoned PR

The last recorded CI run showed:

- i18n validation passed;
- TypeScript lint, build, and unit tests passed;
- container validation and container E2E tests passed;
- CodeQL checks passed; and
- visual regression failed because 12 committed image baselines changed.

The 12 visual changes covered homepage, incoming-secret, and receipt states whose rendered strings
changed. The PR author classified them as expected copy diffs, but the required baselines were not
regenerated. That classification is historical and should be rechecked visually in a fresh pass.

No review approval was recorded. Passing historical checks does not validate the changes against
the present codebase.

## Recommended restart shape

Use small, independently reviewable changes rather than recreating the original mixed PR:

1. Establish and cite the authoritative English capitalization rules.
2. Inventory copy by UI role and approve an exact list of changes.
3. Apply locale-backed editorial changes and regenerate hashes.
4. Handle hardcoded strings and any i18n extraction separately.
5. Revalidate and correct product entitlements in a dedicated change.
6. Remove confirmed dead locale keys in a dedicated cleanup.
7. Rewrite `SECURITY.md` only from operator-approved commitments.
8. Update affected test assertions and regenerate visual baselines in the pinned environment.

Each new change should be based on current `main`; none should be cherry-picked wholesale from the
archived commits.

## Historical references

- PR: <https://github.com/onetimesecret/onetimesecret/pull/4256>
- Security rewrite: `f9248e92f100aabbd9d26d0d3dc4800dd8ea4b41`
- Locale normalization and dead-key removal: `066d1e77603e8d048cc2655ad81290075cfd12ee`
- Hardcoded copy and test synchronization: `470c4b12f3e26104e742c1399364558cf3558a19`
- Last branch commit: `ceae61548602fdb45ddff20bcb246d4183b56d12`
