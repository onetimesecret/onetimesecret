# Installation Guide

This guide covers detailed installation methods for Onetime Secret, including manual setup, system requirements, and advanced configuration options.

## System Requirements

### Minimum Specifications
- **CPU**: 2 cores (or equivalent)
- **Memory**: 1GB RAM
- **Storage**: 4GB disk space
- **OS**: Recent Linux distro (Debian recommended), BSD, or macOS

### Required Dependencies
- **Ruby**: 3.4+ (3.0 may work but unsupported)
- **Redis**: 5.0+
- **Node.js**: 22+ (for frontend development)
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
     redis-server \
     ruby3.1 ruby3.1-dev
   ```

3. **Install package managers:**
   ```bash
   # Install Bundler
   sudo gem install bundler

   # Install Node.js
   curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
   sudo apt install -y nodejs

   # Install pnpm
   sudo npm install -g pnpm@latest
   ```

4. **Start Redis:**
   ```bash
   sudo service redis-server start
   ```

### Application Setup

1. **Clone repository:**
   ```bash
   git clone https://github.com/onetimesecret/onetimesecret.git
   cd onetimesecret
   ```

2. **Install dependencies:**
   ```bash
   # Ruby dependencies
   bundle install

   # Node.js dependencies (for development)
   pnpm install
   ```

3. **Initialize configuration:**
   ```bash
   git rev-parse --short HEAD > .commit_hash.txt
   cp ./etc/config.example.yaml ./etc/config.yaml
   ```

4. **Edit configuration:**
   ```bash
   # Edit config.yaml with your settings
   nano ./etc/config.yaml
   ```

### Running Modes

#### Production Mode
Best for production deployments:

1. **Build frontend assets:**
   ```bash
   pnpm run build:local
   ```

2. **Set development mode to false in config.yaml:**
   ```yaml
   :development:
     :enabled: false
   ```

3. **Start server:**
   ```bash
   RACK_ENV=production bundle exec thin -R config.ru -p 3000 start
   ```

#### Development Mode
For backend development without frontend changes:

```bash
RACK_ENV=development bundle exec thin -R config.ru -p 3000 start
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
   RACK_ENV=development bundle exec thin -R config.ru -p 3000 start
   ```

3. **Start Vite dev server (separate terminal):**
   ```bash
   pnpm run dev
   ```

### Dependency Verification

Verify required versions are installed:

```bash
ruby --version       # Should be 3.1+
bundler --version    # Should be 2.5.x
node --version       # Should be 22+
pnpm --version       # Should be 9.0+
redis-server -v      # Should be 5+
```

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
ONETIME_DEBUG=true bundle exec thin -e dev start
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
rbenv install 3.1.0
rbenv global 3.1.0
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
