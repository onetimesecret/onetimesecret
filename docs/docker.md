# Onetime Secret - Docker Deployment Guide

Onetime Secret is a service that allows you to share sensitive information securely using single-use URLs. This guide provides instructions for deploying Onetime Secret using Docker.

> [!NOTE]
> For information on our "lite" Docker image, which offers an ephemeral "leave no trace" option, see [DOCKER-lite.md](DOCKER-lite.md).

## Quick Start

To run Onetime Secret using Docker:

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

   Note: `host.docker.internal` is specific to Docker Desktop for Mac and Windows. For Linux, use the host's IP address or `172.17.0.1` instead.

3. Run the Onetime Secret container:

   ```bash
   docker run -p 3000:3000 -d --name onetimesecret \
     -e REDIS_URL=$REDIS_URL \
     -e COLONEL=$COLONEL \
     -e HOST=$HOST \
     -e SSL=$SSL \
     -e RACK_ENV=$RACK_ENV \
     onetimesecret/onetimesecret:latest
   ```

Onetime Secret should now be accessible at `http://localhost:3000`.

## Docker Compose

For users who prefer using Docker Compose, we maintain a separate repository with Docker Compose configurations. This setup allows for easier management of multi-container deployments, including Onetime Secret and its Redis dependency.

Visit our [Docker Compose repository](https://github.com/onetimesecret/docker-compose/) for more information and usage instructions.

## Configuration

Onetime Secret can be configured using environment variables. Key variables include:

- `HOST`: The hostname where the service will be accessible
- `SSL`: Whether to use SSL (true/false)
- `COLONEL`: Admin account email
- `REDIS_URL`: URL for Redis connection
- `RACK_ENV`: Application environment (production/development)

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

- `latest`: The most recent stable release
- `v0.18.3` (and similar version numbers): Specific release versions

These version numbers (e.g., v0.18.3) correspond to the releases on our GitHub repository. You can find the full list of releases and their details at <https://github.com/onetimesecret/onetimesecret/releases>.

To use a specific version, replace `onetimesecret/onetimesecret:latest` with the desired tag, for example:

```bash
docker run ... onetimesecret/onetimesecret:v0.18.3
```

Using a specific version tag allows you to maintain consistency across deployments and easily roll back if needed.

## Lite Docker Image

We also offer a "lite" version of the Onetime Secret Docker image, which embraces the philosophy of "leave no trace" by default. This version ensures that all secrets vanish once the container stops, providing enhanced privacy and simplified cleanup.

To use the lite version, replace the image tag in your Docker commands with `latest-lite`:

```bash
docker run -p 3000:3000 -d --name onetimesecret \
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
