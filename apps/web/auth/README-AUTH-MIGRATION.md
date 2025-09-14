# OneTimeSecret Authentication Migration

This document provides quick setup instructions for the authentication migration system. For complete documentation, see the `docs/` directory.

## Quick Start

### Development Setup (Docker)

1. **Start the development environment:**
   ```bash
   ./scripts/start-dev.sh
   ```

2. **Access the services:**
   - OneTimeSecret: http://localhost:4567
   - Auth Service: http://localhost:9393
   - pgAdmin: http://localhost:8080 (optional)

### Manual Setup

1. **Start the authentication service:**
   ```bash
   cd apps/web/auth
   bundle install
   ruby migrate.rb
   bundle exec puma -p 9393
   ```

2. **Configure OneTimeSecret:**
   ```yaml
   # config.yaml
   site:
     authentication:
       external:
         enabled: true
         service_url: "http://localhost:9393"
   ```

3. **Add middleware to your Rack app:**
   ```ruby
   # config.ru
   require_relative 'lib/middleware/identity_resolution'
   use Rack::IdentityResolution
   ```

## Authentication Modes

### Redis Only (Default)
- Current behavior, zero configuration required
- Uses existing Redis-based sessions

### Hybrid Mode (Migration)
```yaml
site:
  authentication:
    external:
      enabled: true
```

### External Only (Post-Migration)
```yaml
site:
  authentication:
    external:
      enabled: true
      features:
        magic_links: true
        two_factor: true
```

## Migration Commands

```bash
# Migrate single user
bin/ots migrate-auth --customer-id user@example.com

# Dry run for all users
bin/ots migrate-auth --dry-run

# Migrate all users
bin/ots migrate-auth --batch-size 100
```

## Testing

### Health Checks
```bash
# Main app identity resolution
curl http://localhost:4567/health/auth

# External auth service
curl http://localhost:9393/health
```

### API Testing
```bash
# Create account
curl -X POST http://localhost:9393/create-account \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"secure123"}'

# Login
curl -X POST http://localhost:9393/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"secure123"}'
```

## Architecture

```
┌─────────────────────────────────────────┐
│         OneTimeSecret App               │
├─────────────────────────────────────────┤
│     Identity Resolution Middleware     │
├─────────────┬───────────┬───────────────┤
│ Redis Auth  │ External  │ Anonymous     │
│ (Current)   │ Auth      │ Users         │
│             │ (New)     │               │
└─────────────┴───────────┴───────────────┘
```

## Key Files

- **`lib/middleware/identity_resolution.rb`** - Core middleware
- **`apps/web/auth/auth.rb`** - Rodauth authentication service
- **`docs/auth-setup-guide.md`** - Complete configuration guide
- **`docs/auth-migration-strategy.md`** - Migration strategy
- **`docs/auth-implementation-plan.md`** - Detailed implementation plan

## Next Steps

1. Test with hybrid mode in development
2. Migrate test users
3. Enable advanced features (2FA, magic links)
4. Plan production rollout

For detailed instructions, see `docs/auth-setup-guide.md`.
