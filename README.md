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
> ```bash
> # Only if starting as root on a minimal system
> apt update && apt install -y sudo
> ```

Install system dependencies:

```bash
# For Debian/Ubuntu systems:
sudo apt update
sudo apt install -y git curl build-essential libyaml-dev libffi-dev redis-server ruby3.1 ruby3.1-dev

# Install package managers
sudo gem install bundler
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs
sudo npm install -g pnpm@latest

# Start Redis server
sudo service redis-server start
```

> **Note:** If you see audit-related errors when installing pnpm with sudo, this is normal in containers or minimal systems where audit capabilities are limited.

##### 2. Get the Source Code

```bash
git clone https://github.com/onetimesecret/onetimesecret.git
cd onetimesecret
```

##### 3. Install Dependencies

```bash
# Install Ruby dependencies
bundle install

# Install Node.js dependencies
pnpm install
```

##### 4. Initialize Configuration

```bash
git rev-parse --short HEAD > .commit_hash.txt
cp -p ./etc/config.example.yaml ./etc/config.yaml
```

##### 5. Choose Your Running Mode

You can run the application in two ways:

###### Option A: Standard Mode (Static Frontend, Choose RACK_ENV)

Best for production or development without frontend changes:

1. Build frontend assets (optional, pre-built assets included):

```bash
pnpm run build:local
```

2. Set development mode to false in `etc/config.yaml`:

```yaml
:development:
  :enabled: false
```

3. Start the server (choose environment as needed):

```bash
# For production
RACK_ENV=production bundle exec thin -R config.ru -p 3000 start

# Or for backend development
RACK_ENV=development bundle exec thin -R config.ru -p 3000 start
```

###### Option B: Frontend Development Mode

Best for active frontend development with live reloading. You have two options:


1. Using the built-in proxy (easier):
```yaml
  :development:
    :enabled: true
    :frontend_host: 'http://localhost:5173'  # Built-in proxy handles /dist/* requests
```

2. Using a reverse proxy (like Caddy, nginx):
```yaml
  # etc/config.yaml
  :development:
    :enabled: true
    :frontend_host: ''  # Let your reverse proxy handle /dist/* requests
```

Then:

1. Start the main server:
   ```bash
   RACK_ENV=development bundle exec thin -R config.ru -p 3000 start
   ```

2. Start the Vite dev server (in a separate terminal):
   ```bash
   pnpm run dev
   ```

#### Technical Details for Frontend Development

When running in development mode (Option B), the application uses Vite's dev server for dynamic asset loading and hot module replacement. Here's how it works:

- In development mode (development.enabled: true), the application loads assets from /dist/*:
  ```html
  {{#frontend_development}}
  <script type="module" src="/dist/main.ts"></script>
  <script type="module" src="/dist/@vite/client"></script>
  {{/frontend_development}}
  ```
These requests are either:

* Handled by the built-in proxy (when `frontend_host` is set)
* Handled by your reverse proxy (when it's empty or not set)

- In production mode (`development.enabled: false`), it uses pre-built static assets:
  ```html
  {{^frontend_development}}
  {{{vite_assets}}}
  {{/frontend_development}}
  ```

This setup enables features like hot module replacement and instant updates during frontend development, while ensuring optimal performance in production.

## Configuration

OnetimeSecret requires a `config.yaml` file for all installations. Environment variables can be used to override specific settings, but the `config.yaml` file must always be present.

### Basic Setup

1. Create the configuration file:

   ```bash
   cp -p ./etc/config.example.yaml ./etc/config.yaml
   ```

2. Review and edit `./etc/config.yaml` as needed. At minimum, update the secret key and back it up securely.

### Configuration Options

#### 1. Using config.yaml (Required)

The `./etc/config.yaml` file is the primary configuration method. It uses ERB syntax to incorporate environment variables, allowing for flexible configuration:

```yaml
---
:site:
  :host: <%= ENV['HOST'] || 'localhost:7143' %>
:domains:
  :enabled: <%= ENV['DOMAINS_ENABLED'] || false %>
```

In this format:

* If an environment variable (e.g., `HOST`) is set, its value will be used.
* If the environment variable is not set, the fallback value (e.g., 'localhost:7143') will be used.
* If you remove the ERB syntax and environment variable reference, only the literal value in the config will be used.

Key areas to configure in `config.yaml`:

* SMTP or SendGrid for email
* Redis connection details
* Rate limits
* Enabled locales
* UI and authentication settings

#### 2. Using Environment Variables (Optional)

For quick setups or container deployments, you can use environment variables to override `config.yaml` settings:

```bash
export HOST=localhost:3000
export SSL=false
export SECRET=A_UNIQUE_VALUE
export REDIS_URL=redis://username:password@hostname:6379/0
export RACK_ENV=production
```

#### 3. Using a .env File (Optional)

For various deployment scenarios, including Docker setups and local development, you can use a `.env` file to set environment variables:

1. Create the .env file:

   ```bash
   cp -p .env.example .env
   ```

2. Edit the `.env` file with your desired configuration.

3. Usage depends on your setup:
   * For local development, load the variables before running the application:

     ```bash
     set -a
     source .env
     set +a
     ```

   * For Docker deployments, you can use the `--env-file` option:

     ```bash
     docker run --env-file .env your-image-name
     ```

   * In docker-compose, you can specify the .env file in your docker-compose.yml:

     ```yaml
     services:
       your-service:
         env_file:
           - .env
     ```

The .env file is versatile and can be used in various deployment scenarios, offering flexibility in how you manage your environment variables.

### Important Notes

* The `config.yaml` file is always required, even when using environment variables.
* Choose either direct environment variables or the `.env` file method, but not both, to avoid confusion.
* If you remove environment variable references from `config.yaml`, only the literal values in the config will be used.

> [!IMPORTANT]
> Use a secure value for the `SECRET` key as an environment variable or as `site.secret` in `etc/config.yaml`. Once set, do not change this value. Create and store a backup in a secure offsite location. Changing the secret may prevent decryption of existing secrets.

#### UI and Authentication Configuration

OnetimeSecret provides flexible UI and authentication controls that allow you to customize the user experience:

##### UI Controls

**Disabling the Web Interface (`UI_ENABLED=false`)**

When the web interface is disabled, OnetimeSecret shows only a minimal explanation page instead of the full application interface:

```bash
# Environment variable
export UI_ENABLED=false

# Or in config.yaml
:site:
  :interface:
    :ui:
      :enabled: false
```

This mode is useful for:
- Maintenance periods
- API-only deployments
- Controlled access scenarios

##### Authentication Controls

**Requiring Authentication (`AUTH_REQUIRED=true`)**

When authentication is required, the homepage secret creation form is only available to logged-in users:

```bash
# Environment variable
export AUTH_REQUIRED=true

# Or in config.yaml
:site:
  :authentication:
    :required: true
```

In this mode:
- Unauthenticated users see a dedicated login-required homepage
- Site header with logo and navigation links remain visible
- Only authenticated users can create secrets
- More restrictive than disabled UI while maintaining site navigation and branding

For a full list of available configuration options, refer to the comments in the `config.example.yaml` file.

### Generating a Secure Random Key

To generate a secure, random 256-bit (32-byte) secret key, you can use the following command with OpenSSL:

```bash
openssl rand -hex 32
```

If OpenSSL is not installed, you can use the `dd` command as a fallback:

```bash
dd if=/dev/urandom bs=32 count=1 2>/dev/null | xxd -p -c 32
```

Note: While the `dd` command provides a reasonable alternative, using OpenSSL is recommended for cryptographic purposes.

## Miscellaneous

### Docker-related Tips

#### Container Name Already in Use

If you encounter the error "The container name '/onetimesecret' is already in use":

```bash
# If the container already exists, you can simply start it again:
docker start onetimesecret

# OR, remove the existing container
docker rm onetimesecret
```

After removing the container, you can run the regular `docker run` command again.

#### Docker Compose

For Docker Compose setup, see the dedicated [Docker Compose repo](https://github.com/onetimesecret/docker-compose/).

### Development Tips

#### Debugging

To run in debug mode:

```bash
ONETIME_DEBUG=true bundle exec thin -e dev start
```

#### Front-end Development

When running the Vite server in development mode, it will automatically reload when files change. Ensure that `RACK_ENV` is set to `development` or `development.enabled` in `etc/config` is set to `false`.

#### Vite Development Server Security

Starting with Vite 5.4.12, additional security measures were implemented to prevent unauthorized access to development servers. When using custom domains for development, you must explicitly configure allowed hosts.

##### Configuring Allowed Hosts

By default, only `localhost` and `127.0.0.1` are allowed to access the development server. To use custom domains:

1. **Using environment variables** (recommended for local development):

   ```bash
   # Option 1: Using export
   export VITE_ADDITIONAL_SERVER_ALLOWED_HOSTS="dev.onetime.dev"
   pnpm run dev

   # Option 2: Set inline
   VITE_ADDITIONAL_SERVER_ALLOWED_HOSTS="dev.onetime.dev" pnpm run dev
   ```

2. **Using .env file**:

   Add to your `.env` file:
   ```
   VITE_ADDITIONAL_SERVER_ALLOWED_HOSTS=dev.onetime.dev
   ```

3. **Using Docker**:

   ```bash
   docker run -p 3000:3000 -d \
     -e VITE_ADDITIONAL_SERVER_ALLOWED_HOSTS="dev.onetime.dev" \
     # other env vars...
     onetimesecret/onetimesecret:latest
   ```

> **Security Warning:** Never set `allowedHosts: true` in your configuration as this creates a security vulnerability allowing any website to access your development server.

See [GHSA-vg6x-rcgg-rjx6](https://github.com/vitejs/vite/security/advisories/GHSA-vg6x-rcgg-rjx6) for details on the vulnerability this configuration prevents.

#### Setting up pre-commit hooks

We use the `pre-commit` framework to maintain code quality. To set it up:

1. Install pre-commit:

   ```bash
   pip install pre-commit
   ```

2. Install the git hooks:

   ```bash
   pre-commit install
   ```

This will ensure that the pre-commit hooks run before each commit, helping to maintain code quality and consistency.

##### Optimizing Docker Builds

To see the layers of an image and optimize your builds, use:

```bash
docker history <image_id>
```

### Production Deployment

See [Dockerfile](./Dockerfile)


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
