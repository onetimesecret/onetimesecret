# Tooling & Reproduction Notes

**Date:** 2026-08-14 · **Host:** Linux 6.18.5 x86_64 (ephemeral container, loopback-only networking)

---

## 1. What was already present

| Tool | Version | Notes |
|---|---|---|
| Ruby | 3.3.6 (`/opt/rbenv/versions/3.3.6`) | see §3 — the repo wants 3.4.10 |
| Bundler | 4.0.9 | |
| RubyGems | 3.5.22 | |
| Node | 22.22.2 | not needed; the SPA was reviewed as source |
| Redis | server + `redis-cli` at `/usr/bin` | used as the local datastore |
| `bundler-audit` | preinstalled at `/opt/rbenv/versions/3.3.6/bin` | outside the bundle — invoke directly, **not** via `bundle exec` |
| Python | 3.x | used only for JSON parsing in the PoC scripts |

**Nothing new was installed.** An attempt to install Ruby 3.4.9 via `rbenv install` failed —
`cache.ruby-lang.org` is not on the egress proxy allowlist (`CONNECT tunnel failed, response 403`).
§3 documents the workaround used instead.

---

## 2. Bringing the application up locally

```bash
cd /home/user/onetimesecret
export PATH="/opt/rbenv/versions/3.3.6/bin:$PATH"
export RUBYOPT="-EUTF-8" LANG=C.UTF-8 LC_ALL=C.UTF-8
export ONETIME_HOME=/home/user/onetimesecret

# 1. Datastore
redis-server --daemonize yes --port 6379 --save '' --appendonly no
redis-cli ping                                   # -> PONG

# 2. Dependencies (the development group needs Ruby >= 3.4 for the `kanayago` gem)
bundle config set --local without 'development'
bundle install --jobs 4

# 3. Configuration (both files are required; neither is tracked)
printf -- "---\n" > etc/config.yaml               # empty: the defaults layer supplies everything
cp etc/defaults/auth.defaults.yaml etc/auth.yaml

# 4. Synthetic environment — ALL SECRETS BELOW ARE THROWAWAY TEST VALUES
cat > /tmp/appsec.env <<'ENVEOF'
RACK_ENV=production
SECRET=<64 random hex bytes, generated locally>
ACCOUNT_ID_SECRET=<32 random hex bytes>
VERIFIABLE_ID_HMAC_SECRET=<32 random hex bytes>
HMAC_SECRET=<32 random hex bytes>
AUTH_SECRET=<32 random hex bytes>
FEDERATION_SECRET=<32 random hex bytes>
REDIS_URL=redis://127.0.0.1:6379/0
HOST=localhost:3000
SSL=false
FROM_EMAIL=test@example.com
AUTHENTICATION_MODE=full
AUTH_DATABASE_URL=sqlite://data/auth.db
AUTH_MFA_ENABLED=true
AUTH_WEBAUTHN_ENABLED=true
AUTH_EMAIL_AUTH_ENABLED=true
ENVEOF
set -a; . /tmp/appsec.env; set +a

# 5. Auth schema (SQLite; requires the UTF-8 RUBYOPT above — migration 003 has non-ASCII content)
mkdir -p data
bundle exec rake auth:migrate                    # -> "Auth database migrated to version 8"

# 6. Serve
bundle exec puma -b tcp://127.0.0.1:3000 -t 2:4 config.ru
curl -sS http://127.0.0.1:3000/api/v2/status     # -> {"success":true,"status":"nominal",...}
```

**Gotchas worth recording.**

- `RACK_ENV=development` refuses to boot without a Vite toolchain (`config.rb:1057`, ADR-025).
  Use `production`.
- `bundle exec rake` / `bundle exec puma` report *"command not found"* unless
  `/opt/rbenv/versions/3.3.6/bin` is on `PATH` — the rbenv shim directory is not exported by default.
- `bundle exec bundle-audit` fails (`bundler-audit` is not in the Gemfile). Call `bundle-audit`
  directly.
- Auth routes 404 until `AUTHENTICATION_MODE=full`; boot then aborts with exit 87 until
  `HMAC_SECRET` is also set.

---

## 3. The Ruby 3.4 problem, and the workaround

`.ruby-version` pins **3.4.10**; the container has at most **3.3.6**, and 3.4.x could not be
downloaded (proxy allowlist). The blocker is a language feature, not a gem: the codebase uses Ruby
3.4's implicit block parameter `it`, which 3.3 parses as a method call:

```
lib/onetime/class_methods.rb:480:in 'block in in_environment?':
  undefined local variable or method 'it' for module Onetime (NameError)
```

**Workaround:** rewrite the 20 `it` block-parameter uses to the semantically identical `_1`, which
both versions accept. Affected: 14 files under `lib/` and `apps/`, plus `Rakefile`. Confirmed
complete with `grep -rn "{ it\b\|{ it\.\|{ it\[" --include=*.rb lib/ apps/`.

**This is an analysis-environment shim, not a proposed change.** It was reverted before committing
(§4). Re-apply with:

```bash
for f in $(grep -rl '{ it\b\|{ it\.\|{ it\[\|== it }' --include=*.rb lib/ apps/) Rakefile; do
  perl -pi -e 's/\{ it \}/{ _1 }/g; s/\{ it\.(\w)/{ _1.$1/g;
               s/\{ it\[/{ _1[/g; s/\{ env == it \}/{ env == _1 }/g;
               s/\.each \{ load it \}/.each { load _1 }/g;' "$f"
done
```

On a host with Ruby 3.4.10 none of this is needed.

---

## 4. Every local change, and how to reset it

| # | Change | Reset |
|---|---|---|
| 1 | `.ruby-version` 3.4.10 → 3.3.6 | `git checkout .ruby-version` |
| 2 | `it` → `_1` in 14 files + `Rakefile` | `git checkout lib/ apps/ Rakefile` |
| 3 | Created `etc/config.yaml` | `rm etc/config.yaml` (untracked) |
| 4 | Created `etc/auth.yaml` | `rm etc/auth.yaml` (untracked) |
| 5 | Created `data/auth.db` (SQLite auth schema) | `rm -rf data/` (untracked) |
| 6 | `bundle config set --local without 'development'` | `bundle config unset --local without` |
| 7 | Installed gems into the rbenv 3.3.6 gem home | `bundle install` on a clean checkout |
| 8 | Redis on 127.0.0.1:6379 populated with test secrets | `redis-cli flushall; redis-cli shutdown nosave` |
| 9 | Puma on 127.0.0.1:3000 | `pkill -f puma` |

**All of items 1, 2 and 6 were reverted before this branch was committed.** `git status` on the
review branch shows only the files under `docs/security/2026-08-14-appsec-review/`.

Nothing outside this container was touched: no external endpoint received traffic, no production
configuration was modified, and no production data or credential was accessed. Every secret used is
a locally-generated throwaway.

---

## 5. Commands used for analysis

**Dependency scanning**

```bash
bundle-audit check --update          # -> 1 advisory: sqlite3 2.9.5 GHSA-mwm8-39rw-8826
```

**Static review** — `rg`/`grep` sweeps over `lib/`, `apps/`, `src/`, `etc/`, `docker/`,
`.github/workflows/`, and the installed gems under
`/opt/rbenv/versions/3.3.6/lib/ruby/gems/3.3.0/gems/`. The high-yield queries:

```bash
grep -rn "valid_email_domain?" --include=*.rb .            # H-3: no production caller
grep -rn "email_verified" --include=*.rb lib/ apps/        # M-1: zero hits
grep -rn "check_active_session" apps lib                   # M-14: zero call sites
grep -rn "Marshal.load\|YAML.load\|YAML.unsafe_load" lib/ apps/   # clean
grep -rn "Access-Control" -i lib/ apps/ etc/ config.ru     # clean — no CORS
grep -rn "\.new(params)\|update(params)\|merge!(params)" lib/ apps/  # clean — no mass assignment
grep -rn "rand(\|Random.rand" lib/ apps/                   # clean — no token uses a non-CSPRNG
```

**Live schema verification** (M-2 — the configured 15-minute magic-link deadline is a no-op):

```bash
python3 -c "import sqlite3;c=sqlite3.connect('data/auth.db');
print([r for r in c.execute(
  \"select sql from sqlite_master where name like '%email_auth%'\")])"
# -> deadline timestamp DEFAULT (datetime(datetime(CURRENT_TIMESTAMP,'localtime'),'1 days'))
```

**Runtime verification** — the five scripts in `poc/`. Run them with the server up:

```bash
cd docs/security/2026-08-14-appsec-review/poc
./01-burn-after-read-race.sh 10      # expect: PASS (1 of 10 gets plaintext)
./03-passphrase-ratelimit.sh         # expect: 422 x5 then 429, identical with XFF rotation
./05-misc-probes.sh                  # headers, CORS, host header, TTL clamping, L-3, M-7
./02-conceal-flood-dos.sh 200        # M-7 — WRITES ~3 MB to Redis; flushall afterwards
bundle exec ruby -Ilib 04-session-options-verification.rb   # refutes the session-entropy claims
```

`poc/02` is the only destructive one; it leaves ~200 keys with 7-day TTLs. Clean up with
`redis-cli flushall`.

---

## 6. Review method

Source review was fanned out across six parallel workstreams — email/token auth, SSO/OIDC,
authorization/IDOR/tenancy, session/CSRF/Redis, SPA/frontend, and supply chain/deployment — each
reading its area in full and reporting file:line evidence. Findings were then **independently
re-verified** by the reviewer against the running application or the live database before being
admitted to `findings.md`.

That verification step mattered: four Critical/High claims about session handling did not survive it
(`findings.md` §5). They arose from reading `lib/onetime/session.rb:63-71` in isolation, where the
`unless defined?(DEFAULT_OPTIONS)` guard looks like constant shadowing but — because Ruby resolves
constants through the ancestor chain — actually means the constant is never defined on the subclass,
so Rack's own defaults apply. Only running the code shows this. Treat any source-only claim in this
class as a hypothesis until executed.
