---
name: merge
description: >-
  Merge the current onetimesecret change into its target branch through a
  GitLab merge request on gitlab.com/onetimesecret/onetimesecret using glab.
  Invoke only when the user has explicitly requested merging (Merge Change,
  /merge, or asking to merge this change). Do not invoke merely for review,
  preparation, passing checks, or skill installation.
disable-model-invocation: true
metadata:
  delta-action: land
---

# Merge (GitLab, onetimesecret)

This skill carries out an explicit merge request for the onetimesecret
repository. Being invoked (Merge Change, `/merge`, or an equivalent user
request) is the merge request: proceed through the workflow. Do not reply that
you are waiting for an explicit merge request, and do not ask again whether to
merge. Stop only for the genuine blockers named below. Whenever you stop, state
plainly that the change has **not** been merged and why.

Success means the merge request is merged in GitLab and its merge commit is on
`gitlab/<target>`. Committing, pushing, opening a merge request, or starting a
pipeline is not success.

## Fixed facts

- Forge: GitLab, project `onetimesecret/onetimesecret`. Git remote: `gitlab`.
  Pass `-R onetimesecret/onetimesecret` to every `glab` command. Do not push to
  or open pull requests on `origin` (GitHub) or other remotes.
- Merge method: merge commit (project `merge_method: merge`). Never pass
  `--squash` or `--rebase`.
- Protected/never-commit branches: `main` (GitLab protected), and `develop`,
  `rel/*` (`no-commit-to-branch` in `.pre-commit-config.yaml`).
- Conflict preference: **pause**. Never resolve merge conflicts yourself.
- Git rules (`AGENTS.md`, "Using git"): never amend, restore, rebase, or
  force-push. Prefix editor-capable git commands with `GIT_EDITOR=true`.
- Avoid the terms listed in `AGENTS.md` ("Terms and phrases to avoid") in
  commit messages, merge request text, and changelog fragments.

## 1. Preflight

1. `git --no-optional-locks status --short --branch` and
   `git --no-pager log --oneline -10`.
2. `git fetch gitlab`.
3. Identify the change to merge from the conversation and diff. Unrelated
   uncommitted edits stay untouched: do not stage, stash, reset, or discard
   them. If you cannot tell which edits belong to the change, stop and ask.
4. Determine the target branch, in order:
   - the target branch of an existing open merge request for the current branch
     (`glab mr list -R onetimesecret/onetimesecret --source-branch <branch> -F json`);
   - a branch the user named;
   - otherwise GitLab's default branch
     (`glab api projects/onetimesecret%2Fonetimesecret --jq .default_branch`,
     currently `main`).

## 2. Prepare the branch and commits

1. If you are on `main`, `develop`, or `rel/*`, create a focused, descriptive
   branch for the change (`git switch -c <type>/<short-name>`; include the issue
   number when there is one, e.g. `fix/4734-...`, which the
   `add-msg-issue-prefix` hook in `.pre-commit-config.yaml` reads).
2. Stage only the change's files and commit with a concise, imperative message
   in the repository's `type(scope): subject` style. Let the pre-commit hooks
   run; if one rewrites files, inspect and stage those fixes and commit again
   (a new commit, not an amend). If a hook fails for a real reason, fix it.
3. Changelog (`changelog.d/README.md`, config `changelog.d/scriv.ini`): add a
   fragment with `scriv create`, then edit it, only when the change affects
   behavior, requires migration steps, or would surprise someone upgrading.
   Internal changes (refactoring, CI, dependency bumps) need none. Add a
   separate fragment under the `AI Assistance` category when AI assistance was
   significant. Describe impact, not implementation.
4. If the change alters a documented setup command, update those docs in the
   same change (`CONTRIBUTING.md`, "Pull requests").
5. Generated artifacts under `generated/` are never hand-edited
   (`CONTRIBUTING.md`); regenerate from sources instead.

## 3. Local verification (proportional to the change)

Local runs are a safety net, not a substitute for the required pipeline.

- Ruby: only through the lane runner, never raw `rspec`/`rake`/`try`
  (`AGENTS.md`, "Running tests"; `tests/lanes/run`, `tests/lanes/README.md`).
  Run tests only if `.test-mode` already exists in the checkout.
  - `tests/lanes/run --which <path>` to find a spec's lane.
  - `tests/lanes/run <lane> --only <path>[:LINE]` while iterating.
  - `tests/lanes/run <lane>` once for the full affected lane before pushing
    (`unit` covers most changes).
  If `.test-mode` is absent, skip Ruby tests and say so in the Test Plan.
- Frontend (no services needed; scripts in `package.json`):
  `pnpm test`, `pnpm run lint`, `pnpm run type-check`.
- CI shell scripts under `.github/scripts/`: `bin/testsuite run` and
  `scripts/check-shell-lint.sh` (`AGENTS.md`, "Running tests").

If a check fails, fix the change or stop and report it. Do not bypass hooks
(`--no-verify`) on the branch being merged.

## 4. Publish and open or update the merge request

1. `git push -u gitlab <branch>` (never to a protected branch; never force).
2. Write the description to a temporary file following
   `.github/pull_request_template.md`:
   - `## Summary`: issue link `[#N](https://github.com/onetimesecret/onetimesecret/issues/N)`
     when one exists, plus a brief description of the behavior change;
   - `## Related Issues`: `Fixes #N` / `Closes #N` where applicable;
   - `## Test Plan`: the checks actually run and their results, and any skipped.
3. If no merge request exists:
   `glab mr create -R onetimesecret/onetimesecret --source-branch <branch> --target-branch <target> --title "<title>" --description-file <file> --push=false --yes`.
   If one exists, update its description only if it is materially stale
   (`glab mr update <iid> -R onetimesecret/onetimesecret --description-file <file>`).
4. Record the merge request IID and URL.

## 5. Gate: conflicts, review, and pipeline on the current head

Read the merge request state:
`glab mr view <iid> -R onetimesecret/onetimesecret -F json`. Use `sha`,
`has_conflicts`, `detailed_merge_status`, `head_pipeline`, `state`, and
`target_branch`.

1. **Conflicts (pause).** If `has_conflicts` is true or
   `detailed_merge_status` reports conflicts, stop. Report "not merged", list
   the conflicting files (e.g. from a trial `git merge --no-commit --no-ff
   gitlab/<target>` followed by `git merge --abort`), and wait for the user's
   decision. If the branch is merely behind and the user's decision is to update
   it, merge the target in (`GIT_EDITOR=true git merge gitlab/<target>`), never
   rebase; if that merge conflicts, `git merge --abort` and pause as above.
2. **Discussions and review.** List discussions with
   `glab api projects/onetimesecret%2Fonetimesecret/merge_requests/<iid>/discussions`.
   Every resolvable discussion must be resolved, and every P1 needs a
   disposition: fixed (cite the commit), refuted (one short reply citing the
   relevant invariant), or ticketed (`AGENTS.md`, "Replying to review
   comments"). Enforce this even though GitLab currently does not. Changes that
   widen access require explicit operator approval (`AGENTS.md`,
   "Security-posture decisions"); stop if that approval is absent. Do not
   resolve someone else's discussion without addressing it.
3. **Live settings.** Re-read target protection and merge settings:
   `glab api projects/onetimesecret%2Fonetimesecret/protected_branches` and
   `glab api projects/onetimesecret%2Fonetimesecret --jq '{merge_method,only_allow_merge_if_pipeline_succeeds,only_allow_merge_if_all_discussions_are_resolved,approvals_before_merge}'`.
   Satisfy anything they require (e.g. approvals). If `merge_method` is no
   longer `merge`, stop and report it rather than guessing.
4. **Pipeline (required).** A GitLab pipeline must exist for the merge
   request's current head `sha` and have status `success`. Check `head_pipeline`
   (its `sha` must equal the MR `sha`) or
   `glab api projects/onetimesecret%2Fonetimesecret/merge_requests/<iid>/pipelines`.
   While a pipeline is `created`/`pending`/`running`, wait for it
   (`glab ci status -R onetimesecret/onetimesecret --branch <branch> --wait`)
   and re-check. Pending, failed, canceled, skipped, missing, or unverifiable
   pipelines block the merge. If the repository has no GitLab CI configuration
   (no `.gitlab-ci.yml`) and therefore no pipeline, stop with "not merged: no
   verifiable pipeline". Never merge on a pipeline for an earlier commit, and
   never use admin or bypass merges. On a failure, read the job log
   (`glab ci trace`), reproduce locally (`tests/lanes/run --only <path>:<LINE>`
   for Ruby), fix, push, and restart this gate.

## 6. Merge

1. Re-read `glab mr view <iid> -R onetimesecret/onetimesecret -F json` and
   confirm `sha` equals the commit verified in step 5.
2. Merge with a merge commit, pinned to the verified head:
   `glab mr merge <iid> -R onetimesecret/onetimesecret --sha <verified-sha> --auto-merge=false --yes`.
   Source-branch removal follows the project default (enabled).
3. If GitLab rejects the merge (SHA moved, conflicts, permissions), report
   "not merged" with the exact error; re-enter step 5 only if new commits are
   expected and in scope.

## 7. Confirm the result

1. `glab mr view <iid> -R onetimesecret/onetimesecret -F json`: `state` is
   `merged`; note `merge_commit_sha`.
2. `git fetch gitlab` and
   `git merge-base --is-ancestor <merge_commit_sha> gitlab/<target>`.
3. If the local target branch exists, has no unique commits, and the working
   tree allows it, switch to it and `git merge --ff-only gitlab/<target>`.
   Otherwise leave local branches alone and say why.
4. Report the merge request URL, the merge commit SHA, the target branch, and
   the checks that passed. Do not sync GitHub (`origin`); mirroring between
   GitHub and GitLab is outside this workflow.
