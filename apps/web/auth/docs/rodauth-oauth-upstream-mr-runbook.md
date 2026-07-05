# rodauth-oauth `oauth_mount_prefix` — upstream MR plan

Runbook for upstreaming the `Rack::URLMap` mount-prefix fix (issue #3465) from our
fork to the gem maintainer once we're ready to drop the fork.

- **Fork:** `onetimesecret/rodauth-oauth` (GitHub) · branch `claude/rodauth-oauth-urlmap-prefix-gczunl` · PR onetimesecret/rodauth-oauth#13
- **Upstream:** `os85/rodauth-oauth` (GitLab, maintainer: Tiago Cardoso / honeyryderchuck), default branch `master`
- **Status:** not yet submitted upstream. This is a third-party project; submit only with explicit sign-off from the OTS maintainer who owns the `onetimesecret/rodauth-oauth` fork (currently @delano).

## The fix in one paragraph

A new `oauth_mount_prefix` auth value method (default `""`), distinct from Rodauth's
`prefix`, separates the prefix used for **URL generation / `request.path` comparison**
from the prefix used for **`request.is` route matching**. `auth_server_route`
regenerates each OAuth endpoint's `*_path`/`*_url` to prepend it; `authorization_server_url`
honors it (→ discovery `issuer` + `oauth_jwt_issuer`); the hand-rolled helpers
(`registration_client_uri`, and the management `oauth_applications_path` /
`oauth_grants_path`) prepend it explicitly. Route matching (`route_hash[remaining_path]`
+ `request.is` on the bare segment) is untouched. Default `""` is a strict no-op. It can
be derived from the request: `oauth_mount_prefix { request.script_name }`.

A diagram is in the fork at `doc/mount_prefix_fix.svg` / `doc/mount_prefix_fix.png`.

## Include / exclude for the MR

Include the gem change only:

- `lib/rodauth/oauth.rb` — the `auth_server_route` `*_path`/`*_url` regeneration
- `lib/rodauth/features/oauth_base.rb` — `oauth_mount_prefix`, `authorization_server_url`, docs
- `lib/rodauth/features/oauth_dynamic_client_registration.rb`, `oidc_dynamic_client_registration.rb` — `registration_client_uri` prepends the prefix
- `lib/rodauth/features/oauth_application_management.rb`, `oauth_grant_management.rb` — helpers prepend the prefix
- `test/oauth/mount_prefix_test.rb`, plus the `*_with_mount_prefix` cases in `test/oauth/metadata_test.rb` and `test/oidc/metadata_test.rb`
- `doc/release_notes/1_6_5.md` (renumber to upstream's next version), `doc/oauth_base.rdoc`
- `doc/mount_prefix_fix.svg` — optional: the prose description above is self-contained, so include it only if the maintainer finds the diagram useful for review

Exclude / adjust:

- `mount_prefix_poc.rb` and `doc/mount_prefix_fix.png` — developer artifacts, not gem content.
- Reword the OTS-internal reference (`onetimesecret/onetimesecret#3465`) in the release note into a neutral "mounting under a Rack `SCRIPT_NAME`" framing.
- Confirm `auth_server_route` exists upstream with the same name/semantics before relying on the `Feature.prepend` override (it does as of 1.6.4; verify against `master`).

## Suggested MR title

> Add `oauth_mount_prefix` to support mounting under a Rack `SCRIPT_NAME` (Rack::URLMap)

## Suggested MR description

### Problem

When the authorization server is mounted under a sub-path via a Rack `SCRIPT_NAME`
(e.g. `Rack::URLMap.new("/auth" => app)`), the mount point is stripped from `PATH_INFO`.
Route matching keeps working off `remaining_path` with `prefix` left empty, but
`base_url`/`route_path` do not include `SCRIPT_NAME`, so:

- discovery metadata (`oauth_server_metadata_body` / `openid_configuration_body`) emits endpoint URLs without the mount point;
- the `issuer` (and `oauth_jwt_issuer`, via `authorization_server_url`) drop the mount point;
- per-feature `check_csrf?` exemptions compare the full `request.path` (`/auth/token`) against the unprefixed `*_path` (`/token`) and miss, so CSRF is wrongly enforced on `/token`, `/userinfo`, `/revoke`, ...

Setting Rodauth's own `prefix "/auth"` is not viable: it also changes `request.is *_path`
matching while `remaining_path` is already `/token` post-URLMap, breaking every route.

### Solution

A new `oauth_mount_prefix` auth value method (default `""`), intentionally distinct from
`prefix`, separating the prefix used for **URL generation / `request.path` comparison**
from the prefix used for **`request.is` route matching** (details above). Default `""`
is a strict no-op — behavior is identical for root-mounted or `prefix`-based deployments.

### Tests

- `Rack::URLMap`-mounted integration tests: `/token` and `/revoke` CSRF exemptions line up under the mount; every endpoint `*_path` resolves to its `/auth/<segment>` form; the dynamic `request.script_name` form prefixes under the mount and collapses to `""` at the root (and under `internal_request`'s synthetic env).
- Discovery `*_with_mount_prefix` cases for OAuth and OIDC (issuer + all `*_endpoint`/`jwks_uri`).
- No-op default + double-prefix caution.

### Notes

- `oauth_token_revocation` keeps CSRF enforced on form-encoded `/revoke` (`!json_request?`); independent of the mount fix and covered by a regression test.

## Git steps (once approved)

```sh
# from a checkout of the fork, build a clean topic branch off upstream master.
# (idempotent: don't fail if the upstream remote is already configured)
git remote get-url upstream >/dev/null 2>&1 || \
  git remote add upstream git@gitlab.com:os85/rodauth-oauth.git
git fetch upstream
git checkout -b fix/oauth-mount-prefix upstream/master

# identify the commits to bring over (the gem change), then cherry-pick them:
git log --oneline origin/main..origin/claude/rodauth-oauth-urlmap-prefix-gczunl
#   include (subjects): "Add oauth_mount_prefix to decouple mount point ...",
#     "Make registration_client_uri honor oauth_mount_prefix ...",
#     "Honor oauth_mount_prefix in the management-feature path helpers",
#     "Harden oauth_mount_prefix ...", and the two test-coverage commits + the docs.
#   exclude: "Add standalone proof-of-concept ..." (mount_prefix_poc.rb) and
#     "Add rendered PNG ..." (doc/mount_prefix_fix.png) — developer artifacts.
# git cherry-pick <sha> <sha> ...   (or diff the fork branch and re-apply lib/test/doc hunks)

# resolve the release-note renumber + OTS-reference rewording, run the suite, then:
git push <your-gitlab-fork> fix/oauth-mount-prefix
# open the MR against os85/rodauth-oauth:master via the GitLab UI or `glab mr create`
```
