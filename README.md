# Onetime Secret - Secure One-Time Message Sharing

*Keep passwords and other sensitive information out of your inboxes and chat logs.*

## What is a One-Time Secret?

A onetime secret is a link that can be viewed only once. A single-use URL.

Try it out on [OnetimeSecret.com](https://onetimesecret.com/)

When you send sensitive info like passwords via email or chat, copies persist in many places. Onetime links self-destruct after viewing, ensuring only the intended recipient sees the information.

## Quick Start with Docker

> [!IMPORTANT]
> **Upgrading from v0.22 or v0.23?** See the [v0.23 Upgrade Guide](https://docs.onetimesecret.com/en/self-hosting/upgrading-v0-23/) and [v0.24 Upgrade Guide](https://docs.onetimesecret.com/en/self-hosting/upgrading-v0-24/) for migration steps.

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
  -e REDIS_URL=redis://host.docker.internal:6379/0 \
  -e SECRET="$(cat .ots_secret)" \
  -e HOST=localhost:3000 \
  -e AUTH_REQUIRED=false \
  -e SSL=false \
  onetimesecret/onetimesecret:v0.24.6
```

**3. Access:** http://localhost:3000

## Configuration

### Essential Settings

Create `./etc/config.yaml` from the defaults:
```bash
cp -np ./etc/defaults/config.defaults.yaml ./etc/config.yaml
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

Requires Ruby 3.4+, Redis/Valkey, and Node.js 25+ (for building the frontend).

```bash
git clone https://github.com/onetimesecret/onetimesecret.git && cd onetimesecret
./install.sh init            # Generates .env, secrets, and puma config
source .env.sh               # Export env vars into the shell
bundle exec puma -C etc/puma.rb
```

For long-running deployments, use a Procfile runner or the systemd templates in `etc/examples/systemd/`:
```bash
foreman start -f Procfile.production
```

See the [Self-Hosting Guide](https://docs.onetimesecret.com/en/self-hosting/) for reverse proxy setup, full authentication mode (PostgreSQL + RabbitMQ), and production hardening.

## Development

### Running Locally

There are three ways to run the application for local development:

**Option A: Overmind (recommended)**

[Overmind](https://github.com/DarthSim/overmind) runs backend, frontend, and worker from a single command using `Procfile.dev`:

```bash
brew install overmind          # macOS
./install-dev.sh               # Link config files + install gems and packages (one-time per checkout)
bin/dev                        # Start all processes
```

Control individual processes from a separate terminal:
```bash
overmind connect backend       # Attach for debugger/pry (Ctrl+b,d to detach)
overmind restart frontend      # Restart a single process
```

**Option B: Production-style**

Build the frontend and serve everything from the backend:
```bash
pnpm run build
RACK_ENV=production bundle exec puma -C etc/examples/puma.example.rb
```

### Frontend Development Mode

Enable development mode in `etc/config.yaml` for HMR support:
```yaml
:development:
  :enabled: true
  :frontend_host: 'http://localhost:5173'
```

### Docker Compose

Docker Compose configurations are included in this repository:
```bash
cp --preserve --no-clobber .env.example .env
docker compose up
```

See `docker-compose.yml` for available profiles (simple vs full stack) and `docker/README.md` for details.

## Community & Support

[Latest Release](https://github.com/onetimesecret/onetimesecret/releases/latest) · [Docker Hub](https://hub.docker.com/r/onetimesecret/onetimesecret) · [Build Status](https://github.com/onetimesecret/onetimesecret/actions) · [License](LICENSE.txt)

- [Report an issue](https://github.com/onetimesecret/onetimesecret/issues)
- [Security Statement](./SECURITY.md)
- [Documentation](https://docs.onetimesecret.com) — usage and self-hosting guides; [`docs/`](./docs/) for developer docs
- [Try it live](https://ca.onetimesecret.com/)


## AI Development Assistance

This version of Familia was developed with assistance from AI tools. The following tools provided significant help with architecture design, code generation, and documentation:

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
