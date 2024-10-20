# Onetime Secret Lite: All-in-One Container

## Quick Start

```bash
docker run -d -p 7143:3000 --name onetimesecret-lite ghcr.io/onetimesecret/onetimesecret-lite:latest
```

> [!WARNING]
> Data is not saved by default. Stopping and/or removing the running container will remove all information entered.

## Ephemeral by Design

Onetime Secret Lite embraces the philosophy of "leave no trace" by default. This design choice offers several benefits:

1. **Enhanced Privacy**: Once the container stops, all secrets vanish, ensuring no lingering sensitive data.
2. **Simplified Cleanup**: No need for manual data purging; just stop the container.
3. **True "One-Time" Nature**: Aligns perfectly with the concept of single-use secrets.

> [!TIP]
> This ephemeral nature is a feature, not a bug. It provides an extra layer of security and simplifies management.

## Best Practices to Prevent Accidental Data Loss

While the ephemeral nature is a key feature, we understand the importance of preventing accidental data loss. Here are some best practices:

1. **Set Clear Expiration Times**: Always set short, appropriate expiration times for your secrets.
2. **Communicate Clearly**: Inform recipients about the urgency of accessing shared secrets.
3. **Use Burn-After-Reading**: Enable this option for critical secrets to ensure they're deleted after first view.
4. **Monitor Container Health**: Regularly check the container's status to prevent unexpected stops.
5. **Consider Persistence for Critical Use**: If you need longer-term storage, use the persistence option (see below).

> [!IMPORTANT]
> Never use Onetime Secret Lite as the sole storage for critical, irreplaceable information. Always have a secure backup for truly vital data.

## Data Persistence (Optional)

For scenarios requiring data retention across container restarts:

```bash
docker run -d -p 7143:3000 -v ots-data:/var/lib/redis --name onetimesecret-lite onetimesecret-lite
```

This command creates a Docker volume, allowing data to persist even if the container is stopped or removed.

> [!NOTE]
> While persistence is available, it deviates from the "lite" and ephemeral nature of this setup. Use judiciously and only when necessary.

## Usage Notes

- **Ideal for**: Quick or temporary deployments, demos or advanced/technical teams that are comfortable with the ephemeral design.
- **Production use**: Consider separate app/DB containers for enhanced security and scalability.
- **Security**: Secure port 7143 with an HTTPS reverse proxy in exposed environments.

## Advanced Setups and Configuration

Need more control or advanced features? Consider:

* Main readme for ghcr.io/onetimesecret/onetimesecret Docker image (github.com/onetimesecret/onetimesecret/docs/DOCKER.md)
* Docker compose: [github.com/onetimesecret/docker-compose](https://github.com/onetimesecret/docker-compose)

This repository provides a Docker Compose configuration for more complex deployments, offering greater flexibility and customization options.


Based on the context provided and the request to revise the end of the readme, here's an updated version that aligns better with the "lite" and ephemeral nature of the setup:

```markdown
## Data Persistence

By default, this container is designed to be ephemeral, aligning with the temporary nature of one-time secrets. When the container is stopped or removed, all data is automatically deleted, which can be seen as a security feature.

## Usage Notes

- **Ideal for**:
  - Quick deployments
  - Development and testing environments
  - Temporary setups
  - Demonstrations
  - Advanced users comfortable with ephemeral data

- **Starting the container**:
  ```bash
  docker run -d -p 7143:3000 --name onetimesecret-lite onetimesecret-lite
  ```

- **Security considerations**:
  - For internet-facing deployments, place the container behind a reverse proxy with HTTPS.
  - The ephemeral nature of this setup provides automatic data cleanup on container shutdown.
  - For enhanced security, consider implementing regular container recreation as part of your operational practices.

> [!IMPORTANT]
> This "lite" version is designed for simplicity and ephemerality. It's not recommended for long-term production use or scenarios requiring data retention.

## Advanced Setups and Configuration

For more complex requirements or production environments, consider these alternatives:

1. **Separate App/DB Containers**:
   - Offers enhanced security and scalability
   - See the main Docker readme: [github.com/onetimesecret/onetimesecret/docs/DOCKER.md](https://github.com/onetimesecret/onetimesecret/docs/DOCKER.md)

2. **Docker Compose Setup**:
   - Provides greater flexibility and customization
   - Available at: [github.com/onetimesecret/docker-compose](https://github.com/onetimesecret/docker-compose)

These options are better suited for production environments or scenarios requiring specific security, scalability, or data retention needs.
