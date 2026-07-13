# locales/BATCH_OPERATIONS.md
---

## Local i18n branch processing

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

One integration PR, not 29 (or however many branches you have).

```bash
# 1. preflight — local must match origin; base must be locale-only (octopus aborts on any conflict)
git fetch origin
base=$(git rev-parse origin/main)
for b in $(git branch --list 'i18n/update-*' --format='%(refname:short)'); do
  [ "$(git rev-parse "$b")" = "$(git rev-parse "origin/$b")" ] || echo "DRIFT: $b"
  git diff --name-only "$(git merge-base "$b" "$base")".."$b" | grep -qv '^locales/content/' && echo "NON-LOCALE: $b"
done

# 2. octopus merge → push → PR
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
