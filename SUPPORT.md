# Support

## Documentation

- [docs.onetimesecret.com](https://docs.onetimesecret.com) — usage guides,
  API reference, and the
  [Self-Hosting Guide](https://docs.onetimesecret.com/en/self-hosting/)
- [docs/](docs/) in this repository — developer-facing documentation

## Bugs and feature requests

Open a [GitHub issue](https://github.com/onetimesecret/onetimesecret/issues).
Include your version (or image tag), how you run it (bare metal, Docker,
compose), and what you expected versus what happened.

Self-hosting from a checkout? Run `bin/setup --doctor --bundle` and attach
the archive it writes to `tmp/` — a sanitized diagnostic snapshot (versions,
file presence, env variable *names* only — never values — and a masked log
excerpt). It answers most back-and-forth questions up front; still, review
it before posting.

## Security vulnerabilities

Never report security issues in a public issue. Follow
[SECURITY.md](SECURITY.md) (email `security@onetimesecret.com`).

## Contributing

Want to fix it yourself? Start with [CONTRIBUTING.md](CONTRIBUTING.md) —
`bin/setup` gets you from clone to running app.

## Hosted service

For questions about the hosted service at
[onetimesecret.com](https://onetimesecret.com), use the feedback form on the
site itself.
