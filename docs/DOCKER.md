# Onetime Secret - Docker Deployment Guide

Onetime Secret is a service that allows you to share sensitive information securely using single-use URLs. This guide provides instructions for deploying Onetime Secret using Docker.

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

After building the image, you can run Onetime Secret with a few simple commands.

1.  **Start a Valkey/Redis container.** Onetime Secret requires a Valkey or Redis server (v5+).

    ```bash
    docker run -d --name valkey -p 6379:6379 valkey/valkey
    ```

2.  **Configure and run the application container.** Create and edit a `.env` file as described in the Configuration section, ensuring `REDIS_URL` is set to `redis://host.docker.internal:6379/0`. Then, run the container:

    ```bash
    docker run -p 3000:3000 -d --name onetimesecret \
        --env-file .env \
        onetimesecret
    ```

    > [!NOTE]
    > `host.docker.internal` is supported in Docker 20.10+ on all platforms (Mac, Windows, Linux). For older versions on Linux, you may need to use `--add-host=host.docker.internal:host-gateway` or the host's IP address.

Onetime Secret will be accessible at `http://localhost:3000`.

## Docker Compose

For users who prefer using Docker Compose, we maintain a separate repository with Docker Compose configurations. This setup allows for easier management of multi-container deployments, including Onetime Secret and its Redis dependency.

Visit our [Docker Compose repository](https://github.com/onetimesecret/docker-compose/) for more information and usage instructions.

## Configuration

Onetime Secret is configured using environment variables. The recommended approach is to use an environment file (`.env`), which keeps your configuration organized and separate from your run commands.

1.  **Create a `.env` file.** Copy the provided example file:

    ```bash
    cp --preserve --no-clobber .env.example .env
    ```

2.  **Edit `.env`.** Open the `.env` file and customize the variables. At a minimum, set a unique `SECRET`. You can generate one with `openssl rand -hex 24`.

3.  **Run the container with the `.env` file.** Use the `--env-file` flag to pass your configuration to Docker. This prevents exposing secrets in your shell history or process list.

### Key Environment Variables

Key variables (all of which are in `.env.example`):

- `SECRET`: A long, random, and unique string for encryption. **Required.**
- `REDIS_URL`: URL for your Valkey/Redis instance.
- `HOST`: The hostname where the service will be accessible.
- `SSL`: Whether to use SSL (`true`/`false`).
- `COLONEL`: Admin account email.
- `RACK_ENV`: Application environment (`production`/`development`).

For more detailed configuration options, refer to the [GitHub README](https://github.com/onetimesecret/onetimesecret#configuration).

## System Requirements

- Any recent Linux distro or *BSD
- Redis server 5+
- Minimum specs: 2 core CPU, 1GB memory, 4GB disk

## Production Deployment

When deploying to production, ensure you:

1. Protect your Redis instance with authentication or Redis networks
2. Enable Redis persistence
3. Use a strong, unique secret
4. Specify the correct domain for deployment

Example:

Update your `.env` file with your production settings (e.g., `HOST`, `REDIS_URL`, `SSL=true`). Then, run the container:

```bash
docker run -p 3000:3000 -d --name onetimesecret \
  --env-file .env \
  onetimesecret/onetimesecret:latest
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

## Lite Docker Image

We also offer a "lite" version of the Onetime Secret Docker image, which embraces the philosophy of "leave no trace" by default. This version ensures that all secrets vanish once the container stops, providing enhanced privacy and simplified cleanup.

To use the lite version, replace the image tag in your Docker commands with `latest-lite`:

```bash
docker run -p 3000:3000 -d --name onetimesecret \
  -e SECRET=$SECRET \
  -e REDIS_URL=$REDIS_URL \
  -e COLONEL=$COLONEL \
  -e HOST=$HOST \
  -e SSL=$SSL \
  -e RACK_ENV=$RACK_ENV \
  onetimesecret/onetimesecret-lite:latest
```

> [!TIP]
> The ephemeral nature of the lite version is a feature, not a bug. It provides an extra layer of security and simplifies management.

For more detailed information about the lite Docker image, please refer to the [DOCKER-lite.md](DOCKER-lite.md) file in the docs directory.

## More Information

For more detailed information, including development setup and troubleshooting, please visit our [GitHub repository](https://github.com/onetimesecret/onetimesecret).
