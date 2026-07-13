# locales/BATCH_OPERATIONS.md

---

## Local i18n branch processing

Pipeline order (each step assumes the previous one ran):

1. **Export** — drained DB -> `locales/content/` + shared tables via `export-all.sh`
   (dry-run by default). Exports every locale with `pending: 0`, skips the rest, then
   runs `i18n db export` once. Leaves uncommitted changes in the working tree;
   everything below operates on those. See [README.md](README.md) step 4.
2. **Create branches** — one `i18n/update-<locale>` branch per changed locale (below).
3. **Open PRs** — one PR per branch (below).
4. **Rebase / respond to feedback / merge back** — the original sections that follow.

### Exporting drained locales

`export-all.sh` writes each fully drained locale's DB translations into `locales/content/`, then
runs `i18n db export` once. Skips any locale with `pending > 0`. Dry-run is the default — pass
`--execute` to act.

```bash
# preview: which locales are drained, what it would export
locales/scripts/export-all.sh

# do it: export every drained locale + shared db tables (once)
locales/scripts/export-all.sh --execute

# or a specific subset
locales/scripts/export-all.sh --execute de es fr_FR
```

Leaves uncommitted changes in the working tree for **Creating the branches** below.

### Exporting the DB (glossary + shared tables)

`export-all.sh` already runs this as its last step. Run it standalone only when re-exporting
shared tables without re-running the locale exports. Writes `glossary.sql` and the other shared
db tables **once**, after every locale is drained. `i18n tasks export <locale>` does _not_ touch
these.

```bash
python3 locales/scripts/i18n db export
```

Also record the round in `session_log` — nothing else writes that table, and `db export`
skips it when empty (so a round leaves no trace unless you add a row):

```bash
python3 locales/scripts/i18n db session add \
  --date <YYYY-MM-DD> --tasks <total> \
  --notes 'N-locale drain; <recoveries, glossary rows, audit result — verbatim>'
python3 locales/scripts/i18n db export session_log   # persist the row
python3 locales/scripts/i18n db session list         # verify
```

### Creating the branches

`branch-per-locale.sh` slices the uncommitted `locales/content/` changes into one branch per
locale. Bases on **`main`** (line 21). Dry-run is the default — pass `--execute` to act.

```bash
# preview: which locales, which base, what it would run
locales/scripts/branch-per-locale.sh --changed

# do it: for each changed locale, checkout main -> branch i18n/update-<locale> ->
#        add locales/content/<locale>/ -> commit -> push -u origin
locales/scripts/branch-per-locale.sh --changed --execute

# or a specific subset
locales/scripts/branch-per-locale.sh --execute de es fr_FR
```

Safe to re-run: skips locales with no changes and any branch that already exists. Requires a
clean tree **outside** `locales/`. The commit-msg hook prepends the `[#XXXX]` prefix — don't
hand-add it.

### Opening the PRs

`pr-per-locale.sh` opens one PR per `i18n/update-<locale>` branch, running a fresh local `claude`
translation-quality review per locale and baking its summary into the PR body. The review time is
the natural throttle (no burst of API calls). Bases on **`main`** by default. Dry-run unless
`--execute`.

```bash
# preview: prints each review + the exact gh command, creates nothing
locales/scripts/pr-per-locale.sh

# create all PRs (authenticated gh required)
locales/scripts/pr-per-locale.sh --execute

# deeper review model, or skip the review for a stats-only body
locales/scripts/pr-per-locale.sh --execute --model claude-opus-4-8
locales/scripts/pr-per-locale.sh --execute --no-review

# refresh the body of an already-open PR instead of skipping it
locales/scripts/pr-per-locale.sh --execute --update de
```

Each run writes its per-locale artifacts to `locales/reviews/<timestamp>/` (the `<locale>.md`
quality reviews plus `.raw.txt`/`.stderr`/`i18n-validate-*.json` diagnostics). **This directory is
gitignored — we do not commit reviews to this repo.** The `.md` reviews are already baked into the
PR bodies on GitHub; the local copies are bespoke, per-diff quality records we may relocate to the
**translation-rules** repo as an audit trail. Until that lands, treat `locales/reviews/` as local
scratch and keep the runs you care about out-of-tree.

Capture the resulting PR numbers to rebuild the arrays below — they are per-round and the ones
listed are stale (a prior batch). Note `--head` is exact-match, not a prefix, so filter with jq
(the freshly-opened PRs are in the default open state):

```bash
gh pr list --limit 100 --json number,headRefName \
  --jq '.[] | select(.headRefName | startswith("i18n/update-")) | "\(.number) \(.headRefName)"'
```

### Rebasing on main

Make sure we have the latest everything (including any changes to locale scripts, translation
workflow checks etc, and to avoid any conflicts merging back into main)

```bash
git fetch origin
start=$(git branch --show-current)
failed=()
for b in $(git branch --list 'i18n/update-*' --format='%(refname:short)'); do
  echo "=== $b ==="
  if ! git rebase origin/main "$b"; then
    git rebase --abort
    failed+=("$b")
    echo ">>> conflict, left $b untouched"
  fi
done
git switch "$start"   # rebases pollute @{-1}, so `git switch -` lands wrong
echo "Rebased cleanly; needs manual attention: ${failed[*]:-none}"
```

### Responding to PR feedback

> The `pairs=(…)` numbers below are from a **prior batch** — regenerate them for the current
> round with the `gh pr list … startswith` command above before running this.

```bash
pairs=(
  "3574 i18n/update-ar"   "3575 i18n/update-bg"   "3576 i18n/update-ca_ES"
  "3577 i18n/update-cs"   "3578 i18n/update-da_DK" "3579 i18n/update-de"
  "3580 i18n/update-de_AT" "3581 i18n/update-el_GR" "3582 i18n/update-eo"
  "3583 i18n/update-es"   "3584 i18n/update-fr_CA" "3585 i18n/update-fr_FR"
  "3586 i18n/update-he"   "3587 i18n/update-hu"   "3588 i18n/update-it_IT"
  "3589 i18n/update-ja"   "3590 i18n/update-ko"   "3591 i18n/update-mi_NZ"
  "3592 i18n/update-nl"   "3593 i18n/update-pl"   "3594 i18n/update-pt_BR"
  "3595 i18n/update-pt_PT" "3596 i18n/update-ru"  "3597 i18n/update-sl_SI"
  "3598 i18n/update-sv_SE" "3599 i18n/update-tr"  "3600 i18n/update-uk"
  "3601 i18n/update-vi"   "3602 i18n/update-zh"
)
for pair in "${pairs[@]}"; do
  pr="${pair%% *}"; b="${pair#* }"
  echo "=== PR #$pr ($b) ==="
  git switch "$b" || { echo "skip $b"; continue; }
  claude -p --model claude-sonnet-5 --permission-mode acceptEdits "$(cat <<EOF
You are on branch $b, which is the head of PR #$pr in onetimesecret/onetimesecret.
Read that PR's review feedback: gh pr view $pr --comments; gh api repos/onetimesecret/onetimesecret/pulls/$pr/comments.
For each actionable comment, update this locale's files under locales/content/. Validate JSON.
Commit each logical change (commit-msg hook adds the prefix; don't hand-add it) and push with git push.
Do not force-push, rebase, amend, or switch branches. If a comment is ambiguous or you disagree, leave it and note why.
EOF
)"
done
git switch main
```

### Merging back into main

One integration PR, not 29 (or however many branches you have). The `#3574–3602` / `seq 3574 3602`
references are from a prior batch — swap in the current round's numbers.

```bash
# 1. preflight — local must match origin; base must be locale-only (octopus aborts on any conflict)
git fetch origin
base=$(git rev-parse origin/main)
for b in $(git branch --list 'i18n/update-*' --format='%(refname:short)'); do
  [ "$(git rev-parse "$b")" = "$(git rev-parse "origin/$b")" ] || echo "DRIFT: $b"
  git diff --name-only "$(git merge-base "$b" "$base")".."$b" | grep -qv '^locales/content/' && echo "NON-LOCALE: $b"
done

# 2. octopus merge -> push -> PR
git switch -c i18n/integration-batch origin/main
git merge --no-ff $(git branch --list 'i18n/update-*' --format='%(refname:short)')
git push -u origin i18n/integration-batch
gh pr create --base main \
  --title "i18n: batch locale updates (supersedes #3574–#3602)" \
  --body "Octopus merge of 29 i18n/update-* branches. Locale-only, conflict-free."

# 3. after the PR merges, the 29 auto-close as Merged (tips reachable from main). verify:
for pr in $(seq 3574 3602); do gh pr view "$pr" --json number,state --jq '"\(.number) \(.state)"'; done
```

Octopus aborts on conflict — run sequentially to find the offender:

```bash
for b in $(git branch --list 'i18n/update-*' --format='%(refname:short)'); do
  git merge --no-ff --no-edit "$b" || { echo ">>> conflict on $b"; break; }
done
```

Notes:

- `--no-ff` is redundant for an octopus (multi-head merges never fast-forward) —
  harmless, leave or drop.
- Reverting a 29-parent octopus is awkward (`git revert -m <n>`); acceptable for
  a locale batch you'll never roll back. Use sequential 2-parent merges if you
  need easy rollback.
