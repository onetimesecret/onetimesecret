# Isolated Development Environments

Test OTS across authentication modes using DevBox or Flox configurations in `path/2/run/`.

## Why

- Compare behavior across auth modes without editing `.env`
- Run multiple configurations simultaneously on different ports
- Ephemeral services (valkey, postgres) per configuration
- Reproducible environments via Nix

## Configurations

| Name | Auth Mode | Port | Services |
|------|-----------|------|----------|
| `ots-noauth` | Disabled | 7201 | Valkey |
| `ots-simple` | Simple | 7202 | Valkey |
| `ots-full` | Full (Rodauth) | 7203 | Valkey, Postgres |
| `ots-full-sso` | Full + SSO | 7204 | Valkey, Postgres |

## Setup

```bash
# Create shared secrets (once)
cd path/2/run/devbox   # or flox
cp secrets.env.example secrets.env
echo "SECRET=$(openssl rand -hex 32)" >> secrets.env
```

## DevBox

Auto-activates on `cd` via direnv.

```bash
cd path/2/run/devbox/ots-simple
direnv allow              # first time
devbox services up
```

## Flox

Explicit activation with `flox activate`.

```bash
cd path/2/run/flox/ots-simple
flox activate -s          # activate + start services

# Or:
flox activate
flox services start
```

## Full Auth Modes

Require database setup after first start:

```bash
# DevBox
devbox run db:setup

# Flox
db-setup   # shell function
```

## Comparison

| | DevBox | Flox |
|-|--------|------|
| Activation | `cd` (direnv) | `flox activate` |
| Start services | `devbox services up` | `flox services start` |
| Logs | process-compose TUI | `flox services logs` |
