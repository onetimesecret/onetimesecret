<!-- .github/pull_request_template.md -->

Why are these changes the way that they are?

```
# Did you discover an incidental fix while working on this? Time to stop,
# drop, and branch.
#
# Create fix branch from base (main/develop), cherry-pick the commit(s),
# and create a PR (quickest: gh pr create --fill); merge and then rebase
# back into the feature branch; continue on your way.
#
#     $ git checkout main && git pull origin main
#     $ git checkout -b fix/static-file-loading
#     $ git cherry-pick <fix-commit>
#     $ git push origin fix/static-file-loading
#
# Clean history, reviewable, and properly documented in releases.
```
