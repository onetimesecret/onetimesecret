# Tooling & Reproduction Notes

## Environment
- Host: Linux 6.18.5 x86_64, root with passwordless sudo.
- Repos under `/home/user/{onetimesecret,otto,familia,rodauth,rodauth-omniauth}`, all on branch `claude/vigilant-goldberg-97ijfl`.
- Outbound: transparent proxy present (`CLAUDE_CODE_PROXY_RESOLVES_HOSTS=true`); rubygems.org reachable (HTTP 200) so gem/Ruby install works. No production systems contacted.

## Pre-installed
- ruby 3.3.6 (rbenv; also 3.1.6, 3.2.6) — **too old**, app needs >= 3.4.7.
- node v22.22.2, pnpm 11.8.0, redis-server 7.0.15 / redis-cli, psql, docker, python3, jq, curl, rg.
- Missing: `sqlite3` CLI, `docker-compose` v1.

## Installed / built during assessment (reversible)
- `rbenv install 3.4.9` — built Ruby 3.4.9 to satisfy Gemfile `ruby '>= 3.4.7'`.

## Redis for analysis
- `redis-server --daemonize yes --save "" --appendonly no --port 6379` (no persistence; ephemeral; flushed after analysis).

## Booting the app for dynamic analysis
- `etc/config.yaml`, `etc/auth.yaml`, `etc/logging.yaml` were created locally by copying the
  matching `etc/defaults/*.defaults.yaml`. These paths are **gitignored** (verified via
  `git check-ignore`), so they are never committed. Remove them to reset.
- Required env to boot: `SECRET` (any 64-hex), `REDIS_URL`, and `IDENTIFIER_SECRET`
  (bridged to Familia's `VERIFIABLE_ID_HMAC_SECRET` so secret ids can be minted). Auth is OFF by
  default, so no Postgres/SQLite is needed.
- **Locale gotcha:** the container's default locale is US-ASCII; Rack's `config.ru` loader chokes on
  the file's em-dash. Set `LC_ALL=C.UTF-8` (and/or force `Encoding.default_external = Encoding::UTF_8`
  in-process). The background-task sandbox resets locale env, so the reliable path used here was the
  in-process boot scripts (which force UTF-8 in Ruby).

## Proof-of-concept artifacts (`../poc/`)
- `race_reveal_model.rb` — in-process model-level race PoC (real `load`/`viewable?`/`decrypted_secret_value`/`revealed!`).
  Deterministic mode: `ruby race_reveal_model.rb 10` → 10/10. Natural mode: `NOBARRIER=1 ruby … 50` → 1/1 (single-process GIL).
- `_setup_secret.rb` + `_reveal_worker.rb` — multi-PROCESS true-parallel race (models clustered Puma):
  setup writes id + a shared `deadline.txt`; launch N `_reveal_worker.rb` in parallel → **12/12 obtained plaintext**.
- `race_reveal_inproc.rb` — full-stack HTTP race via `Rack::MockRequest` (otto→logic→model).
- `headers_check.rb` — dumps live response security headers on default config (CSP/XFO/HSTS ABSENT).
- `race_reveal.sh` / `boot_app.sh` — curl-based + puma boot variants (puma needs `LC_ALL=C.UTF-8`).
- Evidence captured in `../evidence/race_poc_output.md` and `../evidence/headers_output.md`.

Run pattern (Ruby 3.4.9):
```
cd /home/user/onetimesecret
export PATH=/opt/rbenv/versions/3.4.9/bin:$PATH LC_ALL=C.UTF-8 LANG=C.UTF-8
redis-cli -p 6379 flushall
bundle exec ruby /home/user/security-assessment/poc/race_reveal_model.rb 10
```

## Reset / cleanup
- All assessment artifacts live under `/home/user/security-assessment/` only.
- No tracked source files modified/committed. Local analysis-only edits (if any) are reverted before finishing.
- Kill analysis redis: `redis-cli -p 6379 shutdown nosave`.
