# Manual Installation Guide

This guide covers installing OnetimeSecret manually, whether you're working with an existing development environment or starting from a fresh system. For most use cases, we recommend using our [Docker setup](DOCKER.md) for a simpler and more reliable deployment.

## Prerequisites

Required components:
- [Redis Server](https://redis.io/download) (version 5 or higher)
- [Ruby](https://www.ruby-lang.org/en/downloads/) (version 3.1 or higher, ideally 3.4)
- [Bundler](https://bundler.io/) (version 2.5.x)
- [Node.js](https://nodejs.org/en/download/) (version 20 or higher)
- [pnpm](https://pnpm.io/installation) (version 9.2 or higher)
- Essential build tools and development libraries

## Installation Steps

### 1. Prepare Your Environment

First, verify if you have the required dependencies:

```bash
ruby --version       # Ideally 3.4+
bundler --version    # Ideally 2.6.x
node --version       # Ideally 22+
pnpm --version       # Ideally 10.11+
valkey-server -v     # Ideally 5+, or redis-server
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
sudo apt install -y git curl build-essential libyaml-dev libffi-dev valkey-server ruby3.1 ruby3.1-dev

# Install package managers
sudo gem install bundler
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs
sudo npm install -g pnpm@latest

# Start Redis server
sudo service valkey-server start
```
> [!WARNING]
> Ruby 3.4 is probably not available via the Debian package manager. Keep 3.1 as the system version and use [rbenv](https://github.com/rbenv/rbenv) or [asdf](https://asdf-vm.com/) to install Ruby 3.4.

> [!INFO]
> If you see audit-related errors when installing pnpm with sudo, this is normal in containers or minimal systems where audit capabilities are limited.

### 2. Get the Source Code

```bash
git clone https://github.com/onetimesecret/onetimesecret.git
cd onetimesecret
```

### 3. Install Dependencies

```bash
# Install Ruby dependencies
bundle install

# Install Node.js dependencies
pnpm install
```

### 4. Initialize Configuration

This step creates the commit hash file (used for cache busting) and copies the default configuration file into place.

```bash
git rev-parse --short HEAD > .commit_hash.txt
cp -p ./etc/examples/config.example.yaml ./etc/config.yaml
```

For detailed configuration instructions, see the [Configuration Guide](CONFIGURATION.md).

### 5. Choose Your Running Mode

You can run the application in two ways:

#### Option A: Standard Mode (Static Frontend)

This mode is best for production or backend-only development. It serves pre-compiled frontend assets.

1.  Build frontend assets (optional, as pre-built assets are included in releases):
    ```bash
    pnpm run build:local
    ```

2.  Ensure development mode is disabled in `etc/config.yaml`:
    ```yaml
    development:
      enabled: false
    ```

3.  Start the server (choose the appropriate environment):
    ```bash
    # For production
    RACK_ENV=production bundle exec thin -R config.ru -p 3000 start

    # Or for backend development
    RACK_ENV=development bundle exec thin -R config.ru -p 3000 start
    ```

#### Option B: Frontend Development Mode

This mode is ideal for active frontend development, providing live reloading.

1.  Configure `etc/config.yaml` for frontend development. You have two options:
    *   **Using the built-in proxy (recommended):**
        ```yaml
        development:
          enabled: true
          frontend_host: 'http://localhost:5173' # Proxies /dist/* requests
        ```
    *   **Using an external reverse proxy (e.g., Caddy, nginx):**
        ```yaml
        development:
          enabled: true
          frontend_host: '' # Your reverse proxy must handle /dist/*
        ```

2.  Start the main server in one terminal:
    ```bash
    RACK_ENV=development bundle exec thin -R config.ru -p 3000 start
    ```

3.  Start the Vite dev server in a separate terminal:
    ```bash
    pnpm run dev
    ```

## Technical Details for Frontend Development

When running in development mode (Option B), the application uses Vite's dev server for dynamic asset loading and hot module replacement. Here's how it works:

- In development mode (`development.enabled: true`), the application's templates will request assets from the `/dist/` path:
  ```html
  <script type="module" src="/dist/main.ts"></script>
  <script type="module" src="/dist/@vite/client"></script>
  ```
  These requests are either handled by the built-in proxy or your own reverse proxy, depending on your configuration.

- In production mode (`development.enabled: false`), it uses pre-built static assets referenced through a manifest file.

This setup enables modern frontend development features while ensuring optimal performance in production.
