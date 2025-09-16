# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Essential Commands

### Development Environment Setup

```bash
# Install dependencies
bundle install
pnpm install

# Start Redis for development (uses port 2121)
pnpm run redis:start

# Start development server with live reloading
RACK_ENV=development bundle exec thin -R config.ru -p 3000 start

# In separate terminal for frontend dev mode
pnpm run dev
```

### Testing Commands

```bash
# Tryouts framework (Ruby testing) - preferred for Ruby tests
FAMILIA_DEBUG=0 bundle exec try --agent                          # Run all tryouts with agent output
bundle exec try --verbose --fails try/specific_file_try.rb       # Debug specific test file
bundle exec try --agent try/features/relationships_edge_cases_try.rb:101  # Run specific test case

# RSpec (Ruby testing)
bundle exec rspec tests/unit/ruby/rspec/**/*_spec.rb
COVERAGE=1 bundle exec rspec tests/unit/ruby/rspec/**/*_spec.rb   # With coverage

# Frontend testing
pnpm test                    # Vitest unit tests
pnpm test:coverage          # With coverage
pnpm playwright             # End-to-end tests

# Linting and type checking
pnpm lint                   # ESLint
pnpm type-check            # TypeScript checking
bundle exec rubocop        # Ruby linting
```

### Build and Development

```bash
# Build frontend assets
pnpm run build:local        # For local development
pnpm run build              # For production

# Redis utilities
pnpm redis:clean            # Clear Redis data
pnpm redis:status           # Check Redis connection

# CLI tool usage
bin/ots console             # Ruby console with Onetime preloaded
bin/ots version             # Show version
bin/ots migrate SCRIPT --run   # Run migration scripts
```

## Architecture Overview

### Application Structure

Onetime Secret is a Ruby web application with a modern Vue.js frontend, organized in a modular architecture:

- **`apps/`** - Main application modules:
  - `apps/web/core/` - Web interface controllers, views, and helpers
  - `apps/api/v1/` - Legacy API (models, controllers, logic)
  - `apps/api/v2/` - Current API (models, controllers, logic with domain separation)

- **`lib/onetime/`** - Core business logic and utilities
- **`src/`** - Vue.js frontend application
- **`tests/`** - Comprehensive test suite (tryouts, RSpec, Vitest, Playwright)

### Key Architectural Patterns

**Domain-Driven Design**: V2 API uses domain separation (`/logic/domains/`, `/logic/authentication/`, `/logic/secrets/`) where business logic is organized by functional domains rather than technical layers.

**Logic Layer Pattern**: Business operations are encapsulated in dedicated logic classes (e.g., `GenerateSecret`, `AuthenticateSession`) that handle validation, business rules, and coordination between models.

**Familia ORM**: Uses Redis as primary datastore via the Familia ORM, providing ActiveRecord-like interface for Redis operations.

**Frontend-Backend Separation**: Vue.js SPA communicates with Ruby backend via REST API, with Vite handling modern frontend build pipeline.

### Configuration System

- **`etc/config.yaml`** - Main configuration (copy from `config.example.yaml`)
- **Environment variables** override config values
- **Development mode** can proxy frontend to Vite dev server
- **Redis configuration** via `REDIS_URL` environment variable

### Testing Philosophy

- **Tryouts** (`.try.rb` files) - Primary Ruby testing framework, plain Ruby with realistic scenarios
- **RSpec** - Traditional Ruby testing for specific components
- **Vitest** - Vue/TypeScript unit testing
- **Playwright** - End-to-end integration testing

Use `--agent` mode with tryouts for token-efficient LLM analysis, `--verbose --fails` for debugging specific issues.

### Key Dependencies

- **Ruby 3.1+** with Rack-based web server (Thin/Puma)
- **Redis 5+** as primary datastore
- **Vue 3.5+** with Composition API and TypeScript
- **Vite** for frontend build tooling
- **pnpm** for package management

### Development Modes

**Production Mode**: Built frontend assets, single server process
**Development Mode**: Enables Vite proxy for live reloading
**Frontend Dev Mode**: Separate Vite dev server on port 5173

See `development.enabled` and `development.frontend_host` in config.yaml for frontend development setup.
