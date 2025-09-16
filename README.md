# Onetime Secret - Secure One-Time Message Sharing

*Keep passwords and other sensitive information out of your inboxes and chat logs.*

## What is a Onetime Secret?

A onetime secret is a link that can be viewed only once. A single-use URL.

Try it out on [OnetimeSecret.com](https://onetimesecret.com/)

When you send sensitive info like passwords via email or chat, copies persist in many places. Onetime links self-destruct after viewing, ensuring only the intended recipient sees the information.

## Quick Start with Docker

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
docker run -p 3000:3000 -d \
  -e REDIS_URL=redis://host.docker.internal:6379/0 \
  -e SECRET="$(cat .ots_secret)" \
  -e HOST=localhost:3000 \
  -e SSL=false \ # ⚠️ WARNING: Set SSL=true for production deployments
  onetimesecret/onetimesecret:latest
```

**3. Access:** http://localhost:3000

## Configuration

### UI Controls

**Disable Web Interface** (`UI_ENABLED=false`):
- Shows minimal explanation page instead of full interface
- Useful for maintenance or API-only deployments

**Require Authentication** (`AUTH_REQUIRED=true`):
- Homepage secret creation requires login
- Maintains site navigation while restricting access

### Essential Settings

Create `./etc/config.yaml` from the example:
```bash
cp ./etc/config.example.yaml ./etc/config.yaml
```

Key configuration areas:
- **Email**: SMTP or SendGrid setup
- **Authentication**: Enable/disable login requirements
- **Rate limits**: Control usage patterns
- **UI settings**: Customize user experience

### Environment Variables

Common overrides:
```bash
HOST=your-domain.com
SSL=true
SECRET=your-secure-random-key
REDIS_URL=redis://host:6379/0
AUTH_REQUIRED=true
TTL_OPTIONS='1800 43200 86400 259200'  # 30m, 12h, 24h, 3d
```

> **Important**: Generate a secure SECRET key and back it up safely:
> ```bash
> openssl rand -hex 32
> ```

## Installation Options

### Docker Images

**Pre-built images:**
```bash
# GitHub Container Registry
docker pull ghcr.io/onetimesecret/onetimesecret:latest

# Docker Hub
docker pull onetimesecret/onetimesecret:latest

# Lite version (smaller, optimized)
docker pull ghcr.io/onetimesecret/onetimesecret-lite:latest
```

**Build locally:**
```bash
git clone https://github.com/onetimesecret/onetimesecret.git
cd onetimesecret
docker build -t onetimesecret .
```

### Manual Installation

**System Requirements:**
- Ruby 3.4+
- Redis 5+
- Node.js 22+ (for development)
- 1GB RAM, 2 CPU cores minimum

**Quick setup:**
```bash
git clone https://github.com/onetimesecret/onetimesecret.git
cd onetimesecret
bundle install
cp ./etc/config.example.yaml ./etc/config.yaml
# Edit config.yaml as needed
RACK_ENV=production bundle exec thin -R config.ru -p 3000 start
```

> **For detailed installation instructions**, including system setup, troubleshooting, and advanced configuration, see [INSTALL.md](./INSTALL.md).

## Development

### Frontend Development Mode

For active development with live reloading:

1. Enable development mode in `etc/config.yaml`:
```yaml
:development:
  :enabled: true
  :frontend_host: 'http://localhost:5173'
```

2. Start servers:
```bash
# Terminal 1: Main server
RACK_ENV=development bundle exec thin -R config.ru -p 3000 start

# Terminal 2: Vite dev server
pnpm run dev
```

### Docker Compose

For complete setup with dependencies:
[Docker Compose repo](https://github.com/onetimesecret/docker-compose/)

## Support

- **Issues**: [GitHub Issues](https://github.com/onetimesecret/onetimesecret/issues)
- **Documentation**: Check `docs/` directory for detailed guides
- **Security**: Review `SECURITY.md` for security considerations

### Production Deployments

See [Dockerfile](./Dockerfile)

## AI Development Assistance

This version of Familia was developed with assistance from AI tools. The following tools provided significant help with architecture design, code generation, and documentation:

- **Claude (Desktop, Code Max plan, Sonnet 4, Opus 4.1)** - Interactive development sessions, debugging, architecture design, code generation, and documentation
- **Google Gemini** - Refactoring suggestions, code generation, and documentation.
- **GitHub Copilot** - Code completion and refactoring assistance
- **Qodo Merge Pro** - Code review and QA improvements

I remain responsible for all design decisions and the final code. I believe in being transparent about development tools, especially as AI becomes more integrated into our workflows as developers.


## Similar Services

This section provides an overview of services similar to our project, highlighting their unique features and how they compare. These alternatives may be useful for users looking for specific functionalities or wanting to explore different options in the same domain. By presenting this information, we aim to give our users a comprehensive view of the available options in the secure information sharing space.

**Note:** Our in-house legal counsel ([codium-pr-agent-pro bot](https://github.com/onetimesecret/onetimesecret/pull/610#issuecomment-2333317937)) suggested adding this introduction and the disclaimer at the end.

| URL                                | Service            | Description                                                                                                                                                     | Distinctive Feature                                               |
| ---------------------------------- | ------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------- |
| <https://protonurl.ch/>             | protonURL          | A simple and secure tool to share secret, confidential, or non-confidential content via a self-destructing link.                                                | Temporary, self-destructing links for sensitive content with strong encryption and available in 15 languages |
| <https://pwpush.com/>              | Password Pusher    | A tool that uses browser cookies to help you share passwords and other sensitive information.                                                                   | Temporary, self-destructing links for password sharing            |
| <https://scrt.link/en>             | Share a Secret     | A service that allows you to share sensitive information anonymously. Crucial for journalists, lawyers, politicians, whistleblowers, and oppressed individuals. | Anonymous, self-destructing message sharing                       |
| <https://cryptgeon.com/>           | Cryptgeon          | A service for sharing secrets and passwords securely.                                                                                                           | Offers a secret generator, password generator, and secret vault   |
| <https://www.vanish.so/>           | Vanish             | A service for sharing secrets and passwords securely.
                                                                                                           | Self-destructing messages with strong encryption                  |
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

*Summarized, fetched, and collated by [Cohere Command R+](https://cohere.com/blog/command-r-plus-microsoft-azure), formatted by [Claude 3.5 Sonnet](https://www.anthropic.com/news/claude-3-5-sonnet), and proofread by [GitHub Copilot](https://github.com/features/copilot).*


## Badges
[![Latest Release](https://img.shields.io/github/v/release/onetimesecret/onetimesecret)](https://github.com/onetimesecret/onetimesecret/releases/latest)
[![Docker Pulls](https://img.shields.io/docker/pulls/onetimesecret/onetimesecret)](https://hub.docker.com/r/onetimesecret/onetimesecret)
[![Build Status](https://img.shields.io/github/actions/workflow/status/onetimesecret/onetimesecret/ci.yml)](https://github.com/onetimesecret/onetimesecret/actions)
[![License](https://img.shields.io/github/license/onetimesecret/onetimesecret)](LICENSE)

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE.txt) file for details.

## Community & Support

- 🐛 [Report Issues](https://github.com/onetimesecret/onetimesecret/issues)
- 📧 [Security Issues](mailto:security@onetimesecret.com) (email)
- 🌐 [Try it Live](https://ca.onetimesecret.com/)
