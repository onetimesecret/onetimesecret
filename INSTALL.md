# Installation Guide

This guide covers detailed installation methods for Onetime Secret, including manual setup, system requirements, and advanced configuration options.

## System Requirements

### Minimum Specifications
- **CPU**: 2 cores (or equivalent)
- **Memory**: 1GB RAM
- **Storage**: 4GB disk space
- **OS**: Recent Linux distro (Debian recommended), BSD, or macOS

### Required Dependencies
- **Ruby**: 3.4.7+ (required by Gemfile)
- **Redis**: 5.0+ or **Valkey**: 8.0+
- **Node.js**: 22+ (for building frontend assets)
- **pnpm**: 9.0.0+

### System Packages
- build-essential
- libyaml-dev
- libffi-dev
- git
- curl

## Docker Installation (Detailed)

### Available Images

**Pre-built Images:**
```bash
# GitHub Container Registry (recommended)
docker pull ghcr.io/onetimesecret/onetimesecret:latest

# Docker Hub
docker pull onetimesecret/onetimesecret:latest

# Lite version (optimized for smaller deployments)
docker pull ghcr.io/onetimesecret/onetimesecret-lite:latest
```

### Building Images Locally

**Standard Build:**
```bash
git clone https://github.com/onetimesecret/onetimesecret.git
cd onetimesecret
docker build -t onetimesecret .
```

**Lite Build:**
```bash
docker build -f Dockerfile-lite -t onetimesecret:lite .
```

**Multi-platform Build:**
```bash
docker buildx build --platform=linux/amd64,linux/arm64 . -t onetimesecret
```

### Complete Docker Setup

1. **Create network (optional but recommended):**
   ```bash
   docker network create onetime-network
   ```

2. **Start Redis with persistent storage:**
   ```bash
   docker run -d --name redis-onetime \
     --network onetime-network \
     -v redis-data:/data \
     -p 6379:6379 \
     redis:bookworm
   ```

3. **Start Onetime Secret:**
   ```bash
   docker run -d --name onetimesecret \
     --network onetime-network \
     -p 3000:3000 \
     -e REDIS_URL=redis://redis-onetime:6379/0 \
     -e SECRET=$(openssl rand -hex 32) \
     -e HOST=localhost:3000 \
     -e SSL=false \
     -e RACK_ENV=production \
     onetimesecret/onetimesecret:latest
   ```

### Docker Troubleshooting

**Container name conflicts:**
```bash
# Remove existing container
docker rm onetimesecret

# Or restart existing container
docker start onetimesecret
```

**View logs:**
```bash
docker logs onetimesecret
docker logs redis-onetime
```

## Manual Installation

### Fresh System Setup

**For Debian/Ubuntu systems:**

1. **Install sudo (if needed):**
   ```bash
   # Only if starting as root on minimal system
   apt update && apt install -y sudo
   ```

2. **Install system dependencies:**
   ```bash
   sudo apt update
   sudo apt install -y \
     git curl build-essential \
     libyaml-dev libffi-dev \
     redis-server
   ```

3. **Install Ruby 3.4.7+:**

   Debian/Ubuntu system packages typically ship older Ruby versions.
   Use a version manager like [rbenv](https://github.com/rbenv/rbenv) or [mise](https://mise.jdx.dev/):
   ```bash
   # With rbenv:
   rbenv install 3.4.7
   rbenv global 3.4.7

   # Then install Bundler:
   gem install bundler
   ```

4. **Install Node.js 22+ and pnpm:**
   ```bash
   # Install Node.js (via NodeSource or a version manager)
   curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
   sudo apt install -y nodejs

   # Install pnpm
   sudo npm install -g pnpm@latest
   ```

5. **Start Redis:**
   ```bash
   sudo service redis-server start
   ```

### Application Setup

1. **Clone repository:**
   ```bash
   git clone https://github.com/onetimesecret/onetimesecret.git
   cd onetimesecret
   ```

2. **Initialize the application:**
   ```bash
   ./install.sh init
   ```
   This installs Ruby and Node dependencies, generates configuration files, and derives secret keys.

3. **Edit configuration:**
   ```bash
   # Edit config.yaml with your settings
   nano ./etc/config.yaml
   ```

**Updating an existing install:**
```bash
./install.sh reconcile
```
This re-installs dependencies and re-derives child keys from the existing SECRET. Safe to run repeatedly.

> **Migrating from rake?** Previous versions used `rake ots:secrets` for setup. That task has been replaced by `./install.sh init` (first run) and `./install.sh reconcile` (updates).

### Running Modes

#### Production Mode
Best for production deployments:

1. **Build frontend assets:**
   ```bash
   pnpm run build
   ```

2. **Start server:**
   ```bash
   RACK_ENV=production bundle exec puma -C etc/examples/puma.example.rb
   ```

   To customize Puma settings, copy the example config first:
   ```bash
   cp -np etc/examples/puma.example.rb etc/puma.rb
   RACK_ENV=production bundle exec puma -C etc/puma.rb
   ```

#### Development Mode
For backend development without frontend changes:

```bash
RACK_ENV=development bundle exec puma -C etc/examples/puma.example.rb
```

#### Frontend Development Mode
For active frontend development with live reloading:

1. **Enable development mode in config.yaml:**
   ```yaml
   :development:
     :enabled: true
     :frontend_host: 'http://localhost:5173'
   ```

2. **Start main server:**
   ```bash
   RACK_ENV=development bundle exec puma -C etc/examples/puma.example.rb
   ```

3. **Start Vite dev server (separate terminal):**
   ```bash
   pnpm run dev
   ```

### Environment Verification

Check that your environment is correctly set up:

```bash
./install.sh doctor
```

This verifies Ruby and Node versions, Redis connectivity, and environment configuration.

## Advanced Configuration

### Environment File Setup

1. **Create .env file:**
   ```bash
   cp .env.example .env
   ```

2. **Edit .env with your settings:**
   ```bash
   nano .env
   ```

3. **Load environment variables:**
   ```bash
   # For local development
   set -a
   source .env
   set +a
   ```

### Configuration Methods

**Priority order (highest to lowest):**
1. Environment variables
2. .env file
3. config.yaml values

**Using .env with Docker:**
```bash
docker run --env-file .env onetimesecret/onetimesecret:latest
```

### Security Considerations

**Generate secure secret key:**
```bash
# Recommended method
openssl rand -hex 32

# Alternative method
dd if=/dev/urandom bs=32 count=1 2>/dev/null | xxd -p -c 32
```

**Important security notes:**
- Never change the SECRET key after initial setup
- Store the SECRET key backup in a secure location
- Use HTTPS in production (set SSL=true)
- Configure proper firewall rules
- Use strong Redis authentication if exposed

## Development Tools

### Debug Mode
```bash
ONETIME_DEBUG=true RACK_ENV=development bundle exec puma -C etc/examples/puma.example.rb
```

### Pre-commit Hooks
```bash
# Install pre-commit framework
pip install pre-commit

# Install git hooks
pre-commit install
```

### Vite Development Server Security

For custom domains in development:

```bash
# Set allowed hosts
export VITE_ADDITIONAL_SERVER_ALLOWED_HOSTS="dev.onetime.dev"
pnpm run dev
```

**Security Warning**: Never set `allowedHosts: true` as it creates vulnerabilities.

### Docker Development

**View image layers:**
```bash
docker history <image_id>
```

**Interactive debugging:**
```bash
docker run -it --entrypoint /bin/bash onetimesecret/onetimesecret:latest
```

## Production Considerations

### Performance Tuning
- Use a reverse proxy (nginx, Apache)
- Configure Redis persistence
- Set up log rotation
- Monitor resource usage

### High Availability
- Use Redis Sentinel or Cluster
- Load balance multiple app instances
- Set up health checks
- Configure backup strategies

### Monitoring
- Monitor Redis memory usage
- Track application response times
- Set up error logging
- Configure alerting

For production deployment details, see the main [Dockerfile](./Dockerfile) and production deployment documentation.

## Troubleshooting

### Common Issues

**Ruby version conflicts:**
```bash
# Use rbenv or rvm to manage Ruby versions
rbenv install 3.4.7
rbenv global 3.4.7
```

**Permission errors:**
```bash
# Fix gem installation permissions
gem install --user-install bundler
```

**Redis connection issues:**
```bash
# Check Redis status
redis-cli ping

# Check configuration
redis-cli config get "*"
```

**Node.js/pnpm issues:**
```bash
# Clear cache
pnpm store prune
npm cache clean --force

# Reinstall dependencies
rm -rf node_modules
pnpm install
```

### Getting Help

- **Issues**: [GitHub Issues](https://github.com/onetimesecret/onetimesecret/issues)
- **Documentation**: Check `docs/` directory
- **Security**: Review `SECURITY.md`
