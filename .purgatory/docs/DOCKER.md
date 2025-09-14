# Onetime Secret - Docker Deployment Guide

Onetime Secret is a service that allows you to share sensitive information securely using single-use URLs. This guide provides instructions for deploying Onetime Secret using Docker.

> [!NOTE]
> Pre-built images are available from [GitHub Container Registry](https://github.com/onetimesecret/onetimesecret/pkgs/container/onetimesecret) and [Docker Hub](https://hub.docker.com/r/onetimesecret/onetimesecret). Most users can skip the "Building the Image" section.

> [!NOTE]
> For information on our "lite" Docker image, which offers an ephemeral "leave no trace" option, see [DOCKER-lite.md](DOCKER-lite.md).

## Building the Image

First, build the Docker image from the source repository:

```bash
docker build -t onetimesecret .
```

For multi-platform builds (e.g., for `linux/amd64` and `linux/arm64`), you can use `buildx`:

```bash
docker buildx build --platform=linux/amd64,linux/arm64 . -t onetimesecret
```

## Quick Start

After building the image, you can run Onetime Secret with a few commands. This method is ideal for a quick test. For a more robust setup, see the `Running with a Configuration File` section below.

1.  **Start a Valkey/Redis container:**

    ```bash
    docker run -d --name valkey -p 6379:6379 valkey/valkey
    ```

2.  **Set a unique secret:**

    ```bash
    openssl rand -hex 24
    ```

    Copy the output from above command and save it somewhere safe.

    ```bash
    echo -n "Enter a secret and press [ENTER]: "; read -s SECRET
    ```

    Paste the secret you copied from the openssl command above.

3.  **Run the application:**

    ```bash
    docker run -p 3000:3000 -d --name onetimesecret \
        -e SECRET=$SECRET \
        -e VALKEY_URL=redis://host.docker.internal:6379/0 \
        onetimesecret
    ```

    > [!NOTE]
    > `host.docker.internal` is supported in Docker 20.10+ on all platforms. For older versions on Linux, you may need to use `--add-host=host.docker.internal:host-gateway` or the host's IP address.

Onetime Secret will be accessible at `http://localhost:3000`.

## Running with a Configuration File

For a more permanent and secure setup, it's best to use a configuration file. This method avoids exposing secrets in your shell history and makes your configuration reusable.

1.  **Create a `.env` file** from the example:

    ```bash
    cp --preserve --no-clobber .env.example .env
    ```

2.  **Edit your `.env` file.** Open `.env` and set a unique `SECRET`. You can generate one with `openssl rand -hex 24`. Also, ensure `VALKEY_URL` points to your Valkey/Redis instance.

3.  **Run the container** using the `--env-file` flag:

    ```bash
    docker run -p 3000:3000 -d --name onetimesecret \
        --env-file .env \
        onetimesecret
    ```

## Docker Compose

For users who prefer using Docker Compose, we maintain a separate repository with Docker Compose configurations. This setup allows for easier management of multi-container deployments, including Onetime Secret and its Redis dependency.

Visit our [Docker Compose repository](https://github.com/onetimesecret/docker-compose/) for more information and usage instructions.

## Configuration

Onetime Secret's behavior is defined by the `etc/config.yaml` file. On a fresh start, the image copies `etc/defaults/config.defaults.yaml` to `etc/config.yaml`. This YAML file uses ERB templating to incorporate environment variables, allowing for dynamic configuration.

While environment variables are convenient for Docker, the YAML file is the source of truth for all settings.

### Configuration Methods

There are two primary ways to configure the application in Docker:

1.  **Environment Variables (Recommended for most use cases):** Set environment variables, typically via an `.env` file and the `--env-file` flag, to override the defaults in `etc/config.yaml`. This is the simplest method for common adjustments.

2.  **Mounting a Custom `config.yaml` (Advanced):** For complete control, you can mount your own `config.yaml` file from the host machine into the container. This bypasses the default configuration entirely and is useful for complex setups or when you need to configure settings not exposed via environment variables.

    ```bash
    docker run -p 3000:3000 -d --name onetimesecret \
        -v /path/to/your/custom-config.yaml:/app/etc/config.yaml \
        onetimesecret
    ```

    > [!WARNING]
    > When you mount a custom config file, you are responsible for maintaining it. Ensure it includes all necessary settings for your deployment, including a strong `SECRET` and correct `VALKEY_URL`.

### Key Environment Variables

Below are the most common environment variables used to configure the application. For a complete list of all available settings, refer to the `etc/defaults/config.defaults.yaml` file.

- `SECRET`: A long, random, and unique string for encryption. **Required.**
- `VALKEY_URL`: URL for your Valkey/Redis instance.
- `HOST`: The hostname where the service will be accessible.
- `SSL`: Whether to generate links with https:// (`true`/`false`).
- `COLONEL`: Admin account email for application ownership.

## System Requirements

- Any recent Linux distro or *BSD
- Valkey/database server 5+ (or compatible)
- Minimum specs: 2 core CPU, 1GB memory, 4GB disk

## Production Checklist

When deploying to production, it's crucial to ensure your setup is secure and robust. Use this checklist as a guide:

- **[ ] Use a Strong, Unique Secret:** Your `SECRET` should be a long, randomly generated string. Do not use default or easily guessable secrets.
- **[ ] Secure Your Database:** Protect your Valkey/Redis instance with a strong password and, if possible, network policies that restrict access to only the application container.
- **[ ] Enable Database Persistence:** Configure your Valkey/Redis instance to persist data to disk (e.g., using AOF or RDB snapshots). This prevents data loss if the database container restarts.
- **[ ] Specify the Correct Domain:** Ensure the `HOST` variable is set to your public-facing domain name and `SSL` is set to `true`.
- **[ ] Use a Specific Docker Image Tag:** Instead of `latest`, pin your deployment to a specific version tag (e.g., `v0.23.0`). This ensures your deployments are predictable and repeatable.
- **[ ] Manage Configuration Securely:** Use a dedicated `.env` file for production with the `--env-file` flag, or mount a production-ready `config.yaml`. Avoid passing secrets directly on the command line.

A production run command using an environment file might look like this:

```bash
docker run -p 3000:3000 -d --name onetimesecret \
  --env-file .production.env \
  -v /var/onetimesecret/custom-config.yaml:/app/etc/config.yaml \
  onetimesecret:v0.23.0
```

## Updating the Docker Image

To update your Onetime Secret Docker deployment to the latest version:

1. Pull the latest image:

   ```bash
   docker pull onetimesecret/onetimesecret:latest
   ```

2. Stop and remove the existing container:

   ```bash
   docker stop onetimesecret
   docker rm onetimesecret
   ```

3. Run a new container with the updated image using the same command as in the Quick Start or Production Deployment section.

## Docker Image Tags

Onetime Secret Docker images are tagged for different versions:

- `v0.23.0` (and similar version numbers): A specific stable release. (Recommended)
- `latest`: The most recent stable release
- `next`: The most recent release candidate. These are updated during development and are generally not recommended unless there is a specific feature or bug fix that you need. In some cases `latest` will be newer than `next` if there has been a stable release but a new release candidate has not been tagged yet.

These version numbers (e.g., v0.23.0) correspond to the releases and tags available on our GitHub repository. You can find the full list of releases and their details at <https://github.com/onetimesecret/onetimesecret/releases>.

To use a specific version, replace `onetimesecret/onetimesecret:latest` with the desired tag, for example:

```bash
docker run ... onetimesecret/onetimesecret:v0.23.0
```
Using a specific version tag allows you to maintain consistency across deployments and easily roll back if needed.

## More Information

For more detailed information, including development setup and troubleshooting, please visit our [GitHub repository](https://github.com/onetimesecret/onetimesecret).
