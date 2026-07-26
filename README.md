# Onetime Secret — Secure One-Time Message Sharing

_Keep passwords and other sensitive information out of your inboxes and chat logs._

A **onetime secret** is a link that can be viewed only once — a single-use URL.
When you share sensitive info like a password over email or chat, copies linger
in many places. Onetime links self-destruct after viewing, so only the intended
recipient ever sees the contents.

**[Try it live at OnetimeSecret.com →](https://onetimesecret.com/)**

## Quick Start (Docker)

```bash
# 1. Start Redis
docker run -p 6379:6379 -d redis:bookworm

# 2. Generate and store a persistent secret key — back this up safely
openssl rand -hex 32 > .ots_secret && chmod 600 .ots_secret

# 3. Run Onetime Secret (set SSL=true for production)
docker run -p 3000:3000 -d \
  --name onetimesecret \
  --add-host=host.docker.internal:host-gateway \
  -e REDIS_URL=redis://host.docker.internal:6379/0 \
  -e SECRET="$(cat .ots_secret)" \
  -e HOST=localhost:3000 \
  -e SSL=false \
  onetimesecret/onetimesecret:v0.26.1
```

Open <http://localhost:3000>, then create an admin ("colonel") account — it
prints a generated password and is verified immediately:

```bash
docker exec onetimesecret bin/ots customers create me@example.com --role colonel
```

> [!IMPORTANT]
> **Losing your `SECRET` key is not recoverable**. It makes existing
> secrets unreadable among other things, so back it up.

## Going further

- **Self-hosting** — reverse proxy, full authentication (PostgreSQL + RabbitMQ, MFA, WebAuthn), and production hardening: [Self-Hosting Guide](https://docs.onetimesecret.com/en/self-hosting/)
- **Docker Compose** — simple and full stacks: [docker/README.md](./docker/README.md)
- **Configuration** — [.env.reference](./.env.reference) and [config defaults](./etc/defaults/config.defaults.yaml)
- **Contributing** — from clone to a green test suite in two commands, plus [test accounts & API tokens](./docs/development/test-accounts.md): [CONTRIBUTING.md](./CONTRIBUTING.md)

## Community & Support

- **Get help** — [Documentation](https://docs.onetimesecret.com) · [Report an issue](https://github.com/onetimesecret/onetimesecret/issues) · [Support](./SUPPORT.md)
- **Project** — [Latest Release](https://github.com/onetimesecret/onetimesecret/releases/latest) · [Docker Hub](https://hub.docker.com/r/onetimesecret/onetimesecret) · [Build Status](https://github.com/onetimesecret/onetimesecret/actions)
- **Policies** — [Security](./SECURITY.md) · [Code of Conduct](./CODE_OF_CONDUCT.md)
- **See also** — [Similar services & alternatives](./docs/similar-services.md)

## AI Development Assistance

Onetime Secret was developed with help from AI tools for architecture design,
code generation, and documentation. As project maintainers, we remain responsible
for all design decisions and the final code, and believe in being transparent
about the tools involved.

## License

MIT — see [LICENSE.txt](./LICENSE.txt).
