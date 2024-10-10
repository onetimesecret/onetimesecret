
# Onetime Secret - Secure One-Time Message Sharing

NOTE: The `develop` branch is going through a major refactor. Checkout [`v0.17.3`](https://github.com/onetimesecret/onetimesecret/tree/v0.17.3) for a more stable experience.


*Keep passwords and other sensitive information out of your inboxes and chat logs.*

## Latest releases

* **Ruby 3+ (recommended): [latest](https://github.com/onetimesecret/onetimesecret/releases/latest)**
* Ruby 2.7, 2.6 (legacy environments): [v0.12.1](https://github.com/onetimesecret/onetimesecret/releases/tag/v0.12.1)

---

## What is a Onetime Secret?

A onetime secret is a link that can be viewed only once. A single-use URL.

Try it out on <a class="msg" href="https://onetimesecret.com/">OnetimeSecret.com</a>!


### Why would I want to use it?

When you send people sensitive info like passwords and private links via email or chat, there are copies of that information stored in many places. If you use a Onetime link instead, the information persists for a single viewing which means it can't be read by someone else later. This allows you to send sensitive information in a safe way knowing it's seen by one person only. Think of it like a self-destructing message.


- [Onetime Secret - Secure One-Time Message Sharing](#onetime-secret---secure-one-time-message-sharing)
  - [Latest releases](#latest-releases)
  - [What is a Onetime Secret?](#what-is-a-onetime-secret)
    - [Why would I want to use it?](#why-would-i-want-to-use-it)
  - [Installation](#installation)
    - [System Requirements](#system-requirements)
    - [Docker Installation](#docker-installation)
      - [1. Using Pre-built Images](#1-using-pre-built-images)
      - [2. Building the Image Locally](#2-building-the-image-locally)
      - [3. Multi-platform Builds](#3-multi-platform-builds)
    - [Running the Container](#running-the-container)
  - [Configuration](#configuration)
    - [Basic Setup](#basic-setup)
    - [Configuration Options](#configuration-options)
      - [1. Using config.yaml (Required)](#1-using-configyaml-required)
      - [2. Using Environment Variables (Optional)](#2-using-environment-variables-optional)
      - [3. Using a .env File (Optional)](#3-using-a-env-file-optional)
    - [Important Notes](#important-notes)
    - [Manual Installation](#manual-installation)
      - [1. Get the Code](#1-get-the-code)
      - [2. Install System Dependencies](#2-install-system-dependencies)
      - [3. Set Up the Project](#3-set-up-the-project)
      - [4. Install Ruby Dependencies](#4-install-ruby-dependencies)
      - [5. Install JavaScript Dependencies](#5-install-javascript-dependencies)
      - [6. Run the Web Application](#6-run-the-web-application)
        - [Option A: Without Vite Dev Server (Production-like or Simple Development)](#option-a-without-vite-dev-server-production-like-or-simple-development)
        - [Option B: With Vite Dev Server (Active Frontend Development)](#option-b-with-vite-dev-server-active-frontend-development)
  - [Miscellaneous](#miscellaneous)
    - [Docker-related Tips](#docker-related-tips)
      - [Container Name Already in Use](#container-name-already-in-use)
      - [Docker Compose](#docker-compose)
    - [Security and Configuration](#security-and-configuration)
      - [Generating a Global Secret](#generating-a-global-secret)
      - [Securing Configuration Files](#securing-configuration-files)
    - [Troubleshooting](#troubleshooting)
      - [SSH Issues with GitHub](#ssh-issues-with-github)
    - [Development Tips](#development-tips)
      - [Debugging](#debugging)
      - [Front-end Development](#front-end-development)
      - [Setting up pre-commit hooks](#setting-up-pre-commit-hooks)
        - [Optimizing Docker Builds](#optimizing-docker-builds)
      - [Production Deployment](#production-deployment)
  - [Similar Services](#similar-services)

## Installation

### System Requirements

* Any recent linux distro (we use debian) or *BSD or MacOS
* System dependencies:
  * Ruby 3.3, 3.2, 3.1
  * Redis server 5+
* Minimum specs:
  * 2 core CPU (or equivalent)
  * 1GB memory
  * 4GB disk

For front-end development, you'll also need:
* Node.js 18+
* pnpm 9.0.0+



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



## Configuration

OnetimeSecret offers multiple methods for configuration:

1. **config.yaml file**: The file `./etc/config.yaml` must exist and can be edited for detailed configuration.

2. **Environment Variables**: For quick setup or container deployments, you can configure essential settings using environment variables.

3. **.env file**: For manual installations, you can use a `.env` file to set environment variables.

### Using config.yaml

1. Ensure the configuration file exists:
   ```bash
   cp --preserve --no-clobber ./etc/config.example.yaml ./etc/config.yaml
   ```

2. Edit `./etc/config.yaml` for configurations:
   - Update the secret key (back it up securely)
   - Configure SMTP or SendGrid for email
   - Adjust rate limits
   - Enable/disable locales
   - Set Redis details, for example:
     ```yaml
     redis:
       url: redis://username:password@hostname:6379/0
     ```
     Replace `username`, `password`, `hostname`, and `6379` with your specific Redis configuration details.

3. Optionally customize the language JSON files in `./src/locales`

### Using Environment Variables

You can configure OnetimeSecret quickly by setting essential environment variables directly in your shell:

```bash
export HOST=localhost:3000
export SSL=false
export COLONEL=admin@example.com
export REDIS_URL=redis://username:password@hostname:6379/0
export RACK_ENV=production
```

Replace `username`, `password`, `hostname`, and `6379` in the `REDIS_URL` with your specific Redis configuration details.

### Using .env File (Manual Installation)

For manual installations, you can use a `.env` file to set environment variables:

1. Copy the example .env file:
   ```bash
   cp --preserve --no-clobber .env.example .env
   ```

2. Edit the `.env` file with your desired configuration, including Redis details:
   ```
   REDIS_URL=redis://username:password@hostname:6379/0
   ```

3. Before running the application, load the variables into your shell:
   ```bash
   set -a
   source .env
   set +a
   ```

Note: Choose either direct environment variables or the `.env` file method, but not both, to avoid confusion. Environment variables take precedence over `config.yaml` settings, allowing for easy overrides in container environments or for quick testing.

For a full list of available configuration options, refer to the comments in the `config.example.yaml` file.




### Manual Installation

If you prefer to work with the source code directly, you can install OnetimeSecret manually. Follow these steps:

#### 1. Get the Code

Choose one of these methods:

* Download the [latest release](https://github.com/onetimesecret/onetimesecret/archive/refs/tags/latest.tar.gz)
* Clone the repository:
  ```bash
  git clone https://github.com/onetimesecret/onetimesecret.git
  ```

#### 2. Install System Dependencies

Follow these general steps to install the required system dependencies:

1. Update your system's package list
2. Install git, curl, sudo, and redis-server
3. Install Ruby (version 3.3, 3.2, 3.1)
4. Install Node.js 18+ and pnpm 9.2+

For Debian/Ubuntu systems, you can use the following commands:

```bash
# Update package list and install basic dependencies
sudo apt update
sudo apt install -y git curl sudo redis-server

# Install Ruby (choose one version)
sudo apt install -y ruby3.3  # or ruby3.2, ruby3.1

# Install Node.js and pnpm
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs
sudo npm install -g pnpm@latest
```

Note: After installation, ensure Redis is running with `service redis-server status`. Start it if needed with `service redis-server start`.

For other operating systems, please refer to the official documentation for each dependency to install the correct versions.

#### 3. Set Up the Project

```bash
cd onetimesecret
cp --preserve --no-clobber ./etc/config.example.yaml ./etc/config.yaml
```

#### 4. Install Ruby Dependencies

```bash
sudo gem install bundler
bundle install
```

#### 5. Install JavaScript Dependencies

```bash
pnpm install
pnpm run build
```


#### 6. Run the Web Application

There are two main ways to run the application, depending on your development needs:

##### Option A: Without Vite Dev Server (Production-like or Simple Development)

1. For production or simple development without frontend changes:

   ```bash
   RACK_ENV=production bundle exec thin -R config.ru -p 3000 start
   ```

   Or, for a development-like environment without live reloading:

   ```bash
   RACK_ENV=development bundle exec thin -R config.ru -p 3000 start
   ```

   Ensure `development.enabled` is set to `false` in `etc/config.yaml`:

   ```yaml
   :development:
     :enabled: false
   ```

   This uses pre-built frontend assets in the `dist/assets` directory.

##### Option B: With Vite Dev Server (Active Frontend Development)

1. Set `development.enabled` to `true` in `etc/config.yaml`:

   ```yaml
   :development:
     :enabled: true
   ```

2. Run the Thin server in development mode:

   ```bash
   RACK_ENV=development bundle exec thin -R config.ru -p 3000 start
   ```

3. In a separate terminal, start the Vite dev server:

   ```bash
   pnpm run dev
   ```

   This enables live reloading of frontend assets.

The application determines whether to use development or production assets based on the `RACK_ENV` and `development.enabled` settings. In development mode with the Vite server running, frontend assets are loaded dynamically:

```html
{{#frontend_development}}
<script type="module" src="{{ frontend_host }}/dist/main.ts"></script>
<script type="module" src="{{ frontend_host }}/dist/@vite/client"></script>
{{/frontend_development}}
```

In production mode, it uses the built files in `dist/assets`:

```html
{{^frontend_development}}
{{{vite_assets}}}
{{/frontend_development}}
```

Choose the option that best fits your development workflow and needs.


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

### Security and Configuration

#### Generating a Global Secret

Generate a secure global secret with:

```bash
dd if=/dev/urandom bs=20 count=1 | openssl sha256
```

Include this secret in your encryption key configuration.

#### Securing Configuration Files

If you're using the `etc` directory from the repo, ensure proper permissions:

```bash
chown -R ots ./etc
chmod -R o-rwx ./etc
```

### Troubleshooting

#### SSH Issues with GitHub

If you're having trouble cloning via SSH, verify your SSH config:

With a GitHub account:
```bash
ssh -T git@github.com
# Expected output: Hi username! You've successfully authenticated, but GitHub does not provide shell access.
```

Without a GitHub account:
```bash
ssh -T git@github.com
# Expected output: Warning: Permanently added the RSA host key for IP address '0.0.0.0/0' to the list of known hosts.
# git@github.com: Permission denied (publickey).
```

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

#### Production Deployment

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

| URL | Service | Description | Distinctive Feature |
|-----|---------|-------------|---------------------|
| https://pwpush.com/ | Password Pusher | A tool that uses browser cookies to help you share passwords and other sensitive information. | Temporary, self-destructing links for password sharing |
| https://scrt.link/en | Share a Secret | A service that allows you to share sensitive information anonymously. Crucial for journalists, lawyers, politicians, whistleblowers, and oppressed individuals. | Anonymous, self-destructing message sharing |
| https://cryptgeon.com/ | Cryptgeon | A service for sharing secrets and passwords securely. | Offers a secret generator, password generator, and secret vault |
| https://www.vanish.so/ | Vanish | A service for sharing secrets and passwords securely. | Self-destructing messages with strong encryption |
| https://password.link/en | Password.link | A service for securely sending and receiving sensitive information. | Secure link creation for sensitive information sharing |
| https://sebsauvage.net/ | sebsauvage.net | A website offering various information and services. | Software to recover stolen computers |
| https://www.sharesecret.co/ | ShareSecret | A service for securely sharing passwords in Slack and email. | Secure password sharing with Slack and email integration |
| https://teampassword.com/ | TeamPassword | A password manager for teams. | Fast, easy-to-use, and secure team password management |
| https://secretshare.io/ | Secret Share | A service for sharing passwords securely. | Strong encryption for data in transit and at rest |
| https://retriever.corgea.io/ | Retriever | A service for requesting secrets securely. | Secure secret request and retrieval with encryption |
| https://winden.app/s | Winden | A service for sharing secrets and passwords securely. | Securely transfers files with end-to-end encryption |
| https://www.snote.app/ | SNote | A privacy-focused workspace with end-to-end encryption. | Secure collaboration on projects, to-dos, tasks, and shared files |
| https://www.burnafterreading.me/ | Burn After Reading | A service for sharing various types of sensitive information. | Self-destructing messages with diceware passphrase encryption |
| https://pvtnote.com/en/ | PvtNote | A service for sending private, self-destructing messages. | Clean design with self-destructing messages |
| https://k9crypt.xyz/ | K9Crypt | A secure and anonymous messaging platform. | End-to-end encryption with 2-hour message deletion |

_Summarized, fetched, and collated by [Cohere Command R+](https://cohere.com/blog/command-r-plus-microsoft-azure), formatted by [Claude 3.5 Sonnet](https://www.anthropic.com/news/claude-3-5-sonnet), and proofread by [GitHub Copilot](https://github.com/features/copilot)._

The inclusion of these services in this list does not imply endorsement. Users are encouraged to conduct their own research and due diligence before using any of the listed services, especially when handling sensitive information.
