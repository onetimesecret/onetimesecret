# Onetime Secret - Secure One-Time Message Sharing

*Keep passwords and other sensitive information out of your inboxes and chat logs.*

## What is a One-Time Secret?

A onetime secret is a link that can be viewed only once. A single-use URL.

Try it out on [OnetimeSecret.com](https://onetimesecret.com/)

When you send sensitive info like passwords via email or chat, copies persist in many places. Onetime links self-destruct after viewing, ensuring only the intended recipient sees the information.

## Quick Start with Docker

> [!IMPORTANT]
> **Upgrading from v0.22, v0.23, or v0.24?** See the [v0.23 Upgrade Guide](https://docs.onetimesecret.com/en/self-hosting/upgrading-v0-23/), [v0.24 Upgrade Guide](https://docs.onetimesecret.com/en/self-hosting/upgrading-v0-24/), and [v0.25 Upgrade Guide](https://docs.onetimesecret.com/en/self-hosting/upgrading-v0-25/) for migration steps.

**1. Start Redis:**
```bash
docker run -p 6379:6379 -d redis:bookworm
```

**2. Generate and store a persistent secret key:**
```bash
# First, generate a persistent secret key and store it
openssl rand -hex 32 > .ots_secret
chmod 600 .ots_secret
echo "Secret key saved to .ots_secret (keep this file secure!)"

# Now run the container using the key
# ⚠️ WARNING: Set SSL=true for production deployments
docker run -p 3000:3000 -d \
  --name onetimesecret \
  --add-host=host.docker.internal:host-gateway \
  -e REDIS_URL=redis://host.docker.internal:6379/0 \
  -e SECRET="$(cat .ots_secret)" \
  -e HOST=localhost:3000 \
  -e AUTH_REQUIRED=false \
  -e SSL=false \
  onetimesecret/onetimesecret:v0.25.11
```

**3. Access:** http://localhost:3000

**4. Create your first account** — see [Create your first account](#create-your-first-account) below.

## Create your first account

Create an admin ("colonel") account from the CLI — it prints a generated password, and CLI-created accounts are verified immediately (no email required).

Docker (container started with `--name onetimesecret` as above):
```bash
docker exec onetimesecret bin/ots customers create me@example.com --role colonel
```

Docker Compose (the app service is named `app`):
```bash
docker compose exec app bin/ots customers create me@example.com --role colonel
```

Bare-metal (Valkey/Redis running and `.env` sourced: `set -a; source .env; set +a`):
```bash
bundle exec bin/ots customers create me@example.com --role colonel
```

For an API token, use `bin/ots apitoken me@example.com` (or `bin/ots apitoken me@example.com --create --role colonel` to create the account and token in one step). See [docs/development/test-accounts.md](./docs/development/test-accounts.md) for more.

> **Self-hosting note:** By default (`AUTH_AUTOVERIFY=false`) new web signups must click a link in a verification email before they can sign in, which requires a working mailer (`EMAILER_MODE`, `SMTP_HOST`/`SMTP_USERNAME`/`SMTP_PASSWORD`, `FROM_EMAIL`). On a fresh install the SMTP host is a placeholder, so the email never arrives and the signup is stranded as pending. For private or team instances, either set `AUTH_AUTOVERIFY=true` (accounts are active immediately at signup) or create accounts from the CLI as above. (Full auth mode, `AUTHENTICATION_MODE=full`, uses Rodauth's verify-account flow via `AUTH_VERIFY_ACCOUNT_ENABLED` instead.)

## Configuration

### Essential Settings

Create `./etc/config.yaml` from the defaults:
```bash
[ -f ./etc/config.yaml ] || cp -p ./etc/defaults/config.defaults.yaml ./etc/config.yaml
```

Key configuration areas:
- **Authentication**: Two modes available - Simple (Redis-only, default) or Full (SQL database with MFA, WebAuthn, etc.)
- **Email**: SMTP, SES or SendGrid setup
- **UI settings**: Customize user experience

> See [docs/authentication/switching-to-full-mode.md](./docs/authentication/switching-to-full-mode.md) for advanced authentication features

### Environment Variables

See [.env.reference](./.env.reference)

> **Important**: Generate a secure SECRET key and back it up safely:
> ```bash
> openssl rand -hex 32
> ```

## Installation

### Bare-Metal / Manual

Requires Ruby 3.4.9 (pinned via `.ruby-version`), Redis/Valkey, Node.js 22, pnpm 11.10.0, and Python 3 (required by the frontend build).

> **Note:** A UTF-8 locale (e.g. `export LANG=C.UTF-8`) is recommended. The `.env` reader now forces UTF-8, so a POSIX/`C` locale no longer breaks boot, but a UTF-8 locale is still best for correct handling of non-ASCII data.

```bash
git clone https://github.com/onetimesecret/onetimesecret.git && cd onetimesecret
bin/setup --init             # Generates .env, secrets, and puma config
set -a; source .env; set +a  # Export env vars into the shell
pnpm run build               # Build the frontend assets (required, or the UI is blank)
bundle exec puma -C etc/puma.rb
```

Then, in another terminal (with the env sourced the same way), [create your first account](#create-your-first-account):
```bash
bundle exec bin/ots customers create me@example.com --role colonel
```

For long-running deployments, use a Procfile runner or the systemd templates in `etc/examples/systemd/`:
```bash
foreman start -f Procfile.production
```

See the [Self-Hosting Guide](https://docs.onetimesecret.com/en/self-hosting/) for reverse proxy setup, full authentication mode (PostgreSQL + RabbitMQ), and production hardening.

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md) for the full contributor guide. The
short version — one command sets up the checkout, one command runs it:

```bash
bin/setup                      # Deps, config, secrets, generated artifacts, git hooks (idempotent)
bin/dev                        # Start backend + frontend + worker (needs overmind)
```

> [Overmind](https://github.com/DarthSim/overmind) runs the processes from
> `Procfile.dev`; [direnv](https://direnv.net/) (with its
> [shell hook](https://direnv.net/docs/hook.html)) auto-loads the environment
> per checkout. Both are recommended — `bin/setup` tells you what's missing
> and how to proceed without them.

Control individual processes from a separate terminal:
```bash
overmind connect backend       # Attach for debugger/pry (Ctrl+b,d to detach)
overmind restart frontend      # Restart a single process
```

To run the test suites, switch the checkout to the test lane first:
```bash
bin/setup --test               # Throwaway test datastore on :2121 + test mode
pnpm run test:rspec:fast       # RSpec
pnpm test                      # Vitest
```

**Production-style local run**

Build the frontend and serve everything from the backend:
```bash
pnpm run build
RACK_ENV=production bundle exec puma -C etc/examples/puma.example.rb
```

### Frontend Hot Module Replacement

Enable development mode in `etc/config.yaml` for HMR support:
```yaml
development:
  enabled: true
  frontend_host: 'http://localhost:5173'
```

The browser swaps changed modules in place without a full page reload, preserving application state.

## Docker Compose

Docker Compose configurations are included in this repository:
```bash
[ -f .env ] || cp .env.example .env
echo "SECRET=$(openssl rand -hex 32)" >> .env
docker compose up
```

Then, in another terminal, [create your first account](#create-your-first-account):
```bash
docker compose exec app bin/ots customers create me@example.com --role colonel
```

See `docker-compose.yml` to switch between the simple and full stacks (edit the `include`), and [docker/README.md](./docker/README.md) for details. The compose stacks default to the same pinned image tag as the quick start above; override it with `OTS_IMAGE_TAG` in `.env`.

## Community & Support

[Latest Release](https://github.com/onetimesecret/onetimesecret/releases/latest) · [Docker Hub](https://hub.docker.com/r/onetimesecret/onetimesecret) · [Build Status](https://github.com/onetimesecret/onetimesecret/actions) · [License](LICENSE.txt)

- [Contributing Guide](./CONTRIBUTING.md) — from clone to green test suite with `bin/setup`
- [Support](./SUPPORT.md) · [Code of Conduct](./CODE_OF_CONDUCT.md)
- [Report an issue](https://github.com/onetimesecret/onetimesecret/issues)
- [Security Statement](./SECURITY.md)
- [Documentation](https://docs.onetimesecret.com) — usage and self-hosting guides; [`docs/`](./docs/) for developer docs
- [Try it live](https://ca.onetimesecret.com/)


## AI Development Assistance

This version of One-Time Secret was developed with assistance from AI tools. The following tools provided significant help with architecture design, code generation, and documentation:

- **Claude (Desktop, Code Max plan, Sonnet 4, Opus 4.6)** - Interactive development sessions, debugging, architecture design, code generation, and documentation
- **Google Gemini** - Refactoring suggestions, code generation, and documentation.
- **GitHub Copilot** - Code completion and refactoring assistance
- **Qodo Merge Pro** - Code review and QA improvements

I remain responsible for all design decisions and the final code. I believe in being transparent about development tools, especially as AI becomes more integrated into our workflows as developers.


## Similar Services

This section provides an overview of services similar to our project, highlighting their unique features and how they compare. These alternatives may be useful for users looking for specific functionalities or wanting to explore different options in the same domain. By presenting this information, we aim to give our users a comprehensive view of the available options in the secure information sharing space.

**Note:** Our in-house legal counsel ([codium-pr-agent-pro bot](https://github.com/onetimesecret/onetimesecret/pull/610#issuecomment-2333317937)) suggested adding this introduction and the disclaimer at the end.

| URL                                | Service            | Description                                                                                                                                                     | Distinctive Feature                                               |
| ---------------------------------- | ------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------- |
| <https://protonurl.ch/>            | protonURL          | A simple and secure tool to share secret, confidential, or non-confidential content via a self-destructing link.                                                | Temporary, self-destructing links for sensitive content with strong encryption and available in 15 languages |
| <https://pwpush.com/>              | Password Pusher    | A tool that uses browser cookies to help you share passwords and other sensitive information.                                                                   | Temporary, self-destructing links for password sharing            |
| <https://scrt.link/en>             | Share a Secret     | A service that allows you to share sensitive information anonymously. Crucial for journalists, lawyers, politicians, whistleblowers, and oppressed individuals. | Anonymous, self-destructing message sharing                       |
| <https://cryptgeon.com/>           | Cryptgeon          | A service for sharing secrets and passwords securely.                                                                                                           | Offers a secret generator, password generator, and secret vault   |
| <https://www.vanish.so/>           | Vanish             | A service for sharing secrets and passwords securely.                                                                                                           | Self-destructing messages with strong encryption                  |
| <https://password.link/en>         | Password.link      | A service for securely sending and receiving sensitive information.                                                                                             | Secure link creation for sensitive information sharing            |
| <https://www.sharesecret.co/>      | ShareSecret        | A service for securely sharing passwords in Slack and email.                                                                                                    | Secure password sharing with Slack and email integration          |
| <https://teampassword.com/>        | TeamPassword       | A password manager for teams.                                                                                                                                   | Fast, easy-to-use, and secure team password management            |
| <https://secretshare.io/>          | Secret Share       | A service for sharing passwords securely.                                                                                                                       | Strong encryption for data in transit and at rest                 |
| <https://retriever.corgea.io/>     | Retriever          | A service for requesting secrets securely.                                                                                                                      | Secure secret request and retrieval with encryption               |
| <https://winden.app/s>             | Winden             | A service for sharing secrets and passwords securely.                                                                                                           | Securely transfers files with end-to-end encryption               |
| <https://www.snote.app/>           | SNote              | A privacy-focused workspace with end-to-end encryption.                                                                                                         | Secure collaboration on projects, to-dos, tasks, and shared files |
| <https://www.burnafterreading.me/> | Burn After Reading | A service for sharing various types of sensitive information.                                                                                                   | Self-destructing messages with diceware passphrase encryption     |
| <https://pvtnote.com/en/>          | PvtNote            | A service for sending private, self-destructing messages.                                                                                                       | Clean design with self-destructing messages                       |
| <https://k9crypt.xyz/>             | K9Crypt            | A secure and anonymous messaging platform.                                                                                                                      | End-to-end encryption with 2-hour message deletion                |

_Summarized, fetched, and collated by [Cohere Command R+](https://cohere.com/blog/command-r-plus-microsoft-azure), formatted by [Claude 3.5 Sonnet](https://www.anthropic.com/news/claude-3-5-sonnet), and proofread by [GitHub Copilot](https://github.com/features/copilot)._


## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE.txt) file for details.
