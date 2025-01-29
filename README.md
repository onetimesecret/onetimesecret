# Onetime Secret - Secure One-Time Message Sharing

*Keep passwords and other sensitive information out of your inboxes and chat logs.*

> [!NOTE]
> Skip to [Installation instructions](#installation).

---

## What is a Onetime Secret?

A onetime secret is a link that can be viewed only once. A single-use URL.

Try it out on [OnetimeSecret.com](https://onetimesecret.com/)!

### Why would I want to use it?

When you send people sensitive info like passwords and private links via email or chat, there are copies of that information stored in many places. If you use a Onetime link instead, the information persists for a single viewing which means it can't be read by someone else later. This allows you to send sensitive information in a safe way knowing it's seen by one person only. Think of it like a self-destructing message.

* [What is a Onetime Secret?](#what-is-a-onetime-secret)
  * [Why would I want to use it?](#why-would-i-want-to-use-it)
* [Latest releases](#latest-releases)
  * [**Get the Latest Release** (Recommended)](#get-the-latest-release-recommended)
  * [Older releases](#older-releases)
* [Installation](#installation)
  * [System Requirements](#system-requirements)
  * [Docker Installation](#docker-installation)
  * [Running the Container](#running-the-container)
  * [Manual Installation](#manual-installation)
* [Configuration](#configuration)
  * [Basic Setup](#basic-setup)
  * [Configuration Options](#configuration-options)
  * [Important Notes](#important-notes)
  * [Generating a Secure Random Key](#generating-a-secure-random-key)
* [Miscellaneous](#miscellaneous)
  * [Docker-related Tips](#docker-related-tips)
  * [Development Tips](#development-tips)
  * [Production Deployment](#production-deployment)
* [Similar Services](#similar-services)


## Latest releases

### **Get the [Latest Release](https://github.com/onetimesecret/onetimesecret/releases/latest)** (Recommended)

This is the actively developed and maintained version with the most recent features and security updates.

### Older releases

**Ruby 3 without Node.js: [v0.15.0](https://github.com/onetimesecret/onetimesecret/releases/tag/v0.15.0)**

* If you prefer a simpler setup with just Ruby dependencies (i.e. without Node.js dependencies) this is the most recent version.
* No security updates or bug fixes will be provided for this version.

**Ruby 2.7, 2.6 (Legacy - Not Supported): [v0.12.1](https://github.com/onetimesecret/onetimesecret/releases/tag/v0.12.1)**

* ⚠️ **Warning**: This version is no longer maintained or supported.
* Only use if you absolutely cannot run Ruby 3+.
* No security updates or bug fixes will be provided for this version.

We strongly recommend using the latest release with Ruby 3+ for the best performance, security, and feature set. Legacy Ruby 2.x versions are provided for reference only and should be avoided in production environments.

## Installation

### System Requirements

* Any recent linux distro (we use debian) or *BSD or MacOS
* System dependencies:
  * Ruby 3.1+ (3.0 may work but is not officially supported)
  * Redis server 5+
  * Node.js 22+ (for front-end development)
  * pnpm 9.0.0+
* Additional packages:
  * build-essential
  * libyaml-dev
  * libffi-dev
* Minimum specs:
  * 2 core CPU (or equivalent)
  * 1GB memory
  * 4GB disk

### Docker Installation

There are multiple ways to run OnetimeSecret using Docker. Choose the method that best suits your needs:

#### 1. Using Pre-built Images

We offer pre-built images on both GitHub Container Registry and Docker Hub.

```bash
# Pull from GitHub Container Registry
docker pull ghcr.io/onetimesecret/onetimesecret:latest

# OR, pull from Docker Hub
docker pull onetimesecret/onetimesecret:latest
```

#### 2. Building the Image Locally

If you prefer to build the image yourself:

```bash
git clone https://github.com/onetimesecret/onetimesecret.git
cd onetimesecret
docker build -t onetimesecret .
```

#### 3. Multi-platform Builds

For environments requiring multi-architecture support:

```bash
git clone https://github.com/onetimesecret/onetimesecret.git
cd onetimesecret
docker buildx build --platform=linux/amd64,linux/arm64 . -t onetimesecret
```

#### 4. Lite Docker Image

We also offer a "lite" version of the Docker image, which is optimized for quicker deployment and reduced resource usage. To use the lite version:

```bash
# Pull the lite image
docker pull ghcr.io/onetimesecret/onetimesecret-lite:latest

# OR, build it locally
docker build -f Dockerfile-lite -t onetimesecret:lite .
```

For more information on the lite Docker image, refer to the [DOCKER-lite.md](docs/DOCKER-lite.md) documentation.

### Running the Container

Regardless of how you obtained or built the image, follow these steps to run OnetimeSecret:

1. Start a Redis container:

   ```bash
   docker run -p 6379:6379 -d redis:bookworm
   ```

2. Set essential environment variables:

   ```bash
   export HOST=localhost:3000
   export SSL=false
   export COLONEL=admin@example.com
   export REDIS_URL=redis://host.docker.internal:6379/0
   export RACK_ENV=production
   ```

   Note: The `COLONEL` variable sets the admin account email. It's a playful combination of "colonel" (someone in charge) and "kernel" (as in Linux), representing the system administrator.

3. Run the OnetimeSecret container:

   ```bash
   docker run -p 3000:3000 -d --name onetimesecret \
     -e REDIS_URL=$REDIS_URL \
     -e COLONEL=$COLONEL \
     -e HOST=$HOST \
     -e SSL=$SSL \
     -e RACK_ENV=$RACK_ENV \
     onetimesecret/onetimesecret:latest
   ```

   Note: Replace `onetimesecret/onetimesecret:latest` with your image name if you built it locally.

OnetimeSecret should now be running and accessible at `http://localhost:3000`.

### Manual Installation

This guide covers installing OnetimeSecret manually, whether you're working with an existing development environment or starting from a fresh system.

#### Prerequisites

Required components:
- [Redis Server](https://redis.io/download) (version 5 or higher)
- [Ruby](https://www.ruby-lang.org/en/downloads/) (version 3.1 or higher)
- [Bundler](https://bundler.io/) (version 2.5.x)
- [Node.js](https://nodejs.org/en/download/) (version 20 or higher)
- [pnpm](https://pnpm.io/installation) (version 9.2 or higher)
- Essential build tools and development libraries

#### Installation Steps

##### 1. Prepare Your Environment

First, verify if you have the required dependencies:

```bash
ruby --version       # Should be 3.1+
bundler --version    # Should be 2.5.x
node --version       # Should be 20+
pnpm --version       # Should be 9.2+
redis-server -v      # Should be 5+
```

For a fresh system installation, follow these steps:

> [!Important]
> If starting with a minimal system (like a fresh Debian container), install `sudo` first:
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

#### 2. Using Environment Variables (Optional)

For quick setups or container deployments, you can use environment variables to override `config.yaml` settings:

```bash
export HOST=localhost:3000
export SSL=false
export COLONEL=admin@example.com
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

When deploying to production, ensure you:

1. Protect your Redis instance with authentication or Redis networks.
2. Enable Redis persistence and save the data securely.
3. Change the secret to a strong, unique value.
4. Specify the correct domain it will be deployed on.

Example production deployment:

```bash
export HOST=example.com
export SSL=true
export COLONEL=admin@example.com
export REDIS_URL=redis://username:password@hostname:6379/0
export RACK_ENV=production

docker run -p 3000:3000 -d --name onetimesecret \
  -e REDIS_URL=$REDIS_URL \
  -e COLONEL=$COLONEL \
  -e HOST=$HOST \
  -e SSL=$SSL \
  -e RACK_ENV=$RACK_ENV \
  onetimesecret
```

Ensure all sensitive information is properly secured and not exposed in your deployment scripts or environment.

## Similar Services

This section provides an overview of services similar to our project, highlighting their unique features and how they compare. These alternatives may be useful for users looking for specific functionalities or wanting to explore different options in the same domain. By presenting this information, we aim to give our users a comprehensive view of the available options in the secure information sharing space.

**Note:** Our in-house legal counsel ([codium-pr-agent-pro bot](https://github.com/onetimesecret/onetimesecret/pull/610#issuecomment-2333317937)) suggested adding this introduction and the disclaimer at the end.

| URL                                | Service            | Description                                                                                                                                                     | Distinctive Feature                                               |
| ---------------------------------- | ------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------- |
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

The inclusion of these services in this list does not imply endorsement. Users are encouraged to conduct their own research and due diligence before using any of the listed services, especially when handling sensitive information.
