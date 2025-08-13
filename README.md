# Onetime Secret - Secure One-Time Message Sharing

*Keep passwords and other sensitive information out of your inboxes and chat logs.*

## What is a Onetime Secret?

A onetime secret is a link that can be viewed only once. A single-use URL.

Try it out on [OnetimeSecret.com](https://onetimesecret.com/)

When you send people sensitive info like passwords and private links via email or chat, there are copies of that information stored in many places. If you use a Onetime link instead, the information persists for a single viewing which means it can't be read by someone else later. This allows you to send sensitive information in a safe way knowing it's seen by one person only. Think of it like a self-destructing message.

## Quick Start

Get up and running in 30 seconds:

```bash
# 1. Start Redis
docker run -d --name valkey -p 6379:6379 valkey/valkey

# 2. Generate and save a secure secret
openssl rand -hex 32

# 3. Set the secret securely (paste the secret from step 2)
echo -n "Enter secret: "; read -s SECRET

# 4. Start Onetime Secret
docker run -p 3000:3000 \
  -e SECRET=$SECRET \
  -e REDIS_URL=redis://host.docker.internal:6379/0 \
  ghcr.io/onetimesecret/onetimesecret:latest
```

Open `http://localhost:3000` in your browser.

---

## Installation

### Docker Installation (Recommended)

```bash
# Using pre-built image
docker pull ghcr.io/onetimesecret/onetimesecret:latest

# Or build from source
docker build -t onetimesecret .
```

For detailed setup instructions, see our [Docker Guide](docs/DOCKER.md).

For our self-contained, ephemeral "lite" image, see [Docker Lite Guide](docs/DOCKER-lite.md).

### Manual Installation

While we recommend Docker for most users, a manual installation is possible. For detailed steps, see our [Manual Installation Guide](docs/MANUAL_INSTALL.md).

### System Requirements

* Any recent Linux distro (we use Debian) or *BSD or macOS
* Ruby 3.4+ (3.1-3.3 may work but not officially supported)
* Valkey/Redis server 5+
* Node.js 22+ (for frontend development)
* Minimum specs: 2 core CPU, 1GB memory, 4GB disk

## Configuration

Onetime Secret requires a `config.yaml` file for all installations. The configuration file uses ERB templating to incorporate environment variables, allowing for flexible deployment scenarios.

For detailed configuration instructions, including how to use environment variables, `.env` files, and advanced settings, see our [Configuration Guide](docs/CONFIGURATION.md).

> [!IMPORTANT]
> Generate a secure `SECRET` key using `openssl rand -hex 32` and store it safely. Never change this value once set, as it prevents decryption of existing secrets.

## Development

For tips on debugging, frontend development, setting up pre-commit hooks, and other development-related topics, see our [Development Guide](docs/DEVELOPMENT.md).

## Releases

### **Get the [Latest Release](https://github.com/onetimesecret/onetimesecret/releases/latest)** (Recommended)

This is the actively developed and maintained version with the most recent features and security updates.

### Version Notes

**Pre-1.0 Status:** Onetime Secret is currently in active development with pre-1.0 version numbers (e.g., v0.23.0). While we recommend using the `latest` tag for the newest features, **production deployments should pin to a specific version tag** (e.g., `v0.23.0`) for stability.

⚠️ **Breaking Changes:** Expect potential breaking changes between "major-minor" releases (e.g., v0.22.x → v0.23.0). We follow semantic versioning principles but treat pre-1.0 minor version bumps as potentially breaking changes.

### Development Branch Notice

> [!WARNING]
> **Custom Domain Support Temporarily Unavailable:** This development branch has intentionally broken custom domain functionality as part of ongoing architectural improvements. If you need custom domain support, please use one of these stable alternatives:
>
> - **Latest stable release:** [v0.22.3](https://github.com/onetimesecret/onetimesecret/releases/tag/v0.22.3)
> - **Docker images:** `ghcr.io/onetimesecret/onetimesecret:v0.22.3` or `onetimesecret/onetimesecret:v0.22.3`
> - **Source installation:** `git checkout v0.22.3` after cloning
>
> Custom domain functionality will be restored in future releases.

## Similar Services

This section provides an overview of services similar to our project, highlighting their unique features and how they compare. These alternatives may be useful for users looking for specific functionalities or wanting to explore different options in the same domain. By presenting this information, we aim to give our users a comprehensive view of the available options in the secure information sharing space.

**Note:** Our in-house legal counsel ([codium-pr-agent-pro bot](https://github.com/onetimesecret/onetimesecret/pull/610#issuecomment-2333317937)) suggested adding this introduction and the disclaimer at the end.

| URL                                | Service            | Description                                                                                                                                                     | Distinctive Feature                                               |
| ---------------------------------- | ------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------- |
| <https://protonurl.ch/>             | protonURL          | A simple and secure tool to share secret, confidential, or non-confidential content via a self-destructing link.                                                | Temporary, self-destructing links for sensitive content with strong encryption and available in 15 languages.            |
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
