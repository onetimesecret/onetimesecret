# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Branch Context

This is the `main` branch (stable production release). Active development happens on `develop` branch which is ~2500 commits ahead. The architecture is similar but `develop` has significant new features.

## Common Commands

### Git Commands

Always use `--no-pager` for git commands in non-interactive shells:
```bash
git --no-pager diff
git --no-pager log --oneline -20
git --no-pager show HEAD
```

### Backend

```bash
# Start development server
RACK_ENV=development bundle exec thin -R config.ru -p 3000 start

# Console access
bin/ots console

# Run Ruby tests (Tryouts framework)
REDIS_URL='redis://127.0.0.1:2121/0' bundle exec try --agent
bundle exec try --verbose --fails try/path/file_try.rb
bundle exec try --stack  # full stack traces

# RSpec tests
bundle exec rspec spec/
```

### Frontend

```bash
# Development with HMR
pnpm run dev

# Build for production
pnpm run build

# Type checking
pnpm run type-check

# Linting
pnpm run lint
pnpm run lint:fix

# Tests
pnpm test                  # Vitest unit tests
pnpm run playwright        # E2E tests
```

### Test Database

```bash
# Start Redis on port 2121 for tests
pnpm run redis:start
pnpm run redis:stop
```

## High-Level Architecture

### Stack

- **Backend**: Ruby 3.1+, Rack 2.x, Otto router, Thin server
- **Data**: Redis via Familia ORM
- **Frontend**: Vue 3, TypeScript, Vite, Tailwind CSS, Pinia
- **Package management**: Bundler (Ruby), pnpm (Node.js)

### Directory Structure

```
apps/                   # Modular Rack applications
  ├── api/              # REST APIs (v1, v2)
  └── web/              # Main web application

lib/
  ├── onetime.rb        # Core library entry point
  └── onetime/          # Business logic, models, utilities

src/                    # Vue 3 SPA
  ├── components/       # Vue components
  ├── views/            # Page views
  ├── stores/           # Pinia state management
  └── locales/          # i18n translations

try/                    # Tryouts integration tests (primary)
spec/                   # RSpec tests
tests/                  # Vitest/Playwright tests
etc/                    # Configuration files
```

### Application Entry Points

- `config.ru` - Main Rack configuration, loads apps from `apps/` directory
- `bin/ots` - CLI tool for administration commands
- Apps are mounted via Otto router, each with its own `application.rb`

### Configuration

- Copy `etc/defaults/config.defaults.yaml` to `etc/config.yaml`
- Environment variables override config (see `.env.example`)
- Key vars: `HOST`, `SSL`, `SECRET`, `REDIS_URL`, `RACK_ENV`

### Familia ORM

Redis-backed models in `lib/onetime/models/`. Key pattern:
- Models inherit from Familia::Horreum
- Define fields, TTLs, and relationships
- Use `prefix` for Redis key namespace
