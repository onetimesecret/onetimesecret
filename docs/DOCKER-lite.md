# Onetime Secret Lite: The All-in-One Container

The "lite" image is a self-contained container with both the Onetime Secret application and a Valkey server. It is ephemeral by design, meaning all data is lost when the container stops. This is a security feature, not a bug.

> [!NOTE]
> A pre-built image is available from [GitHub Container Registry](https://github.com/onetimesecret/onetimesecret/pkgs/container/onetimesecret-lite). Most users can skip the "Building the Image" section.

## Building the Image

To build the lite image from the source repository, use the `Dockerfile-lite` file:

```bash
docker build -t onetimesecret-lite -f Dockerfile-lite .
```

## Quick Start

Run the container using the `--rm` flag to ensure it is automatically removed on exit, fulfilling its ephemeral purpose.

```bash
docker run --rm -p 7143:3000 --name onetimesecret-lite onetimesecret-lite:latest
```

The application will be available at `http://localhost:7143`.

> [!WARNING]
> This image is not designed for data persistence. When the container stops, all data, including any secrets you have created, will be permanently deleted.

## Advanced Setups

The lite image is intentionally simple. For more advanced use cases, such as data persistence, custom configuration, or production deployments, please use the main Docker image or the Docker Compose setup.

- **Main Docker Image:** For separate app and database containers, see [DOCKER.md](DOCKER.md).
- **Docker Compose:** For flexible, multi-container setups, visit our [Docker Compose repository](https://github.com/onetimesecret/docker-compose).
