# Configuration Guide

Onetime Secret is configured through a primary YAML file, which can be dynamically modified by environment variables. This guide explains the different methods for configuring the application.

## 1. Primary Method: `etc/config.yaml`

The `etc/config.yaml` file is the source of truth for all application settings and is **required** for the application to run. On a fresh installation, you must create this file by copying the provided example:

```bash
cp -p ./etc/examples/config.example.yaml ./etc/config.yaml
```

After creating the file, review and edit `./etc/config.yaml` as needed. At minimum, update the secret key and back it up securely.

This file uses ERB (Embedded Ruby) templating, which allows it to read from environment variables.

### How it Works

A typical entry in `config.yaml` looks like this:

```yaml
---
site:
  host: <%= ENV['HOST'] || 'localhost:3000' %>
domains:
  enabled: <%= ENV['DOMAINS_ENABLED'] || false %>
```

In this format:

- If an environment variable (e.g., `HOST`) is set, its value will be used.
- If the environment variable is not set, the fallback value (e.g., `localhost:3000`) will be used.
- If you remove the ERB syntax and environment variable reference, only the literal value in the config will be used.

### Key Areas to Configure

Key areas to configure in `config.yaml`:

- SMTP or SendGrid for email
- Redis connection details
- Rate limits
- Enabled locales

For a complete reference of all available configuration options, please review the default configuration file at `etc/defaults/config.defaults.yaml`.

## 2. Overriding with Environment Variables

For temporary changes, or in containerized environments like Docker, you can set environment variables to override the values defined in `config.yaml`.

```bash
export HOST=onetimesecret.example.com
export SSL=true
export SECRET='your-long-random-secret-here'
export REDIS_URL='redis://:yourpassword@redis.example.com:6379/0'
export RACK_ENV=production

bundle exec thin -R config.ru -p 3000 start
```

## 3. Using a `.env` File

To make managing environment variables easier, especially for local development or Docker deployments, you can use a `.env` file.

1.  **Create the file:**
    ```bash
    cp .env.example .env
    ```

2.  **Edit the file:** Add your desired key-value pairs to the `.env` file.
    ```
    SECRET="your-long-random-secret-here"
    HOST="localhost:3000"
    REDIS_URL="redis://localhost:6379/0"
    ```

3.  **Usage depends on your setup:**
    - For local development, load the variables before running the application:
      ```bash
      set -a
      source .env
      set +a
      ```
    - For Docker deployments, you can use the `--env-file` option:
      ```bash
      docker run --env-file .env your-image-name
      ```
    - In docker-compose, you can specify the .env file in your docker-compose.yml:
      ```yaml
      services:
        your-service:
          env_file:
            - .env
      ```

The .env file is versatile and can be used in various deployment scenarios, offering flexibility in how you manage your environment variables.

## Important Notes

- The `config.yaml` file is always required, even when using environment variables.
- Choose either direct environment variables or the `.env` file method, but not both, to avoid confusion.
- If you remove environment variable references from `config.yaml`, only the literal values in the config will be used.

> [!IMPORTANT]
> Use a secure value for the `SECRET` key as an environment variable or as `site.secret` in `etc/config.yaml`. Once set, do not change this value. Create and store a backup in a secure offsite location. Changing the secret may prevent decryption of existing secrets.

## Generating a Secure Secret

Your `SECRET` is used for encryption and should be a long, random string. You can generate a cryptographically secure key using `openssl`:

```bash
openssl rand -hex 32
# F42376B...A348C1
```

If OpenSSL is not installed, you can use the `dd` command as a fallback:

```bash
dd if=/dev/urandom bs=32 count=1 2>/dev/null | xxd -p -c 32
```

Note: While the `dd` command provides a reasonable alternative, using OpenSSL is recommended for cryptographic purposes.

Copy the generated value and set it as your `SECRET` in either your `config.yaml` or your environment file.
