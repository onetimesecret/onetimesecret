#
# ONETIME SECRET - LITE IMAGE
#
# This Dockerfile creates a self-contained, all-in-one container with both
# the Onetime Secret application and a Redis server.
#
# It is ephemeral by design: all data is lost when the container stops.
# This is a security feature, not a bug.
#
# For more detailed documentation, see docker/variants/README.md.
#
# BUILDING (via Bake — resolves the main image dependency automatically):
#
#     $ docker buildx bake -f docker/bake.hcl lite
#
# RUNNING:
#
#     $ docker run --rm -p 7143:3000 --name onetimesecret-lite onetimesecret-lite
#
# The application will be available at http://localhost:7143.
#

# The "main" context is provided by docker/bake.hcl via:
#   contexts = { main = "target:main" }
FROM main
ARG VERSION=0.0.0

LABEL Name=onetimesecret-lite Version=$VERSION
LABEL maintainer="Onetime Secret <docker-maint@onetimesecret.com>"
LABEL org.opencontainers.image.description="Onetime Secret (Lite) is a web application for sharing sensitive information via one-time use links. This image contains both the Onetime Secret application and Redis, making it a self-contained solution for quick deployment and testing. Warning: Not recommended for production use."

# The main image sets USER appuser — switch to root for package installation
USER root

# Install Redis and other dependencies
RUN apt-get update && apt-get install -y \
    redis-server \
    redis-tools \
    && rm -rf /var/lib/apt/lists/*

# Write Redis configuration
RUN <<-EOF cat > /etc/redis/redis.conf
    bind 0.0.0.0
    port 6379
    daemonize no
EOF

# Write the startup script
# Note: We use quoted EOF ('EOF') to prevent variable expansion in the heredoc.
# This preserves potential variables (like $PATH) as literal text, to be evaluated when the script runs.
RUN <<-'EOF' cat > /onetime.sh
#!/bin/bash
set -e
# Print welcome message
echo "
🔒  Welcome to Onetime Secret Lite - The All-in-One, Onetime-use Secret Sharing Container for Humans!  🔒
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🕵️  Your secrets are about to get a whole lot stealthier!

🖥️  ACCESS THE APP HERE: http://localhost:$PORT

💭  Pro tip: Secrets are like memes - hilarious, but only when shared with the right people!

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🎭  Happy secret sharing, you magnificent nerdlinger! 🎭
"

# Generate a unique secret for this container session.
# This overrides the ENV SECRET placeholder from the Dockerfile so the app
# never runs with a static, well-known value.
echo "Generating a unique secret..."
export SECRET=$(openssl rand -hex 32)

# Start Redis server
echo "Starting Redis..."
redis-server /etc/redis/redis.conf &

# Wait for Redis to be ready
until redis-cli ping; do
  echo "⚙️  Waiting for Redis to be ready..."
  sleep 1
done
echo "Redis is ready!"

# Start Onetime Secret
echo "Starting Onetime Secret..."
exec /app/bin/entrypoint.sh
EOF

# Ensure the script has the correct line endings and is executable
RUN chmod +x /onetime.sh

# Set environment variables
ENV HOST=127.0.0.1:3000
ENV PORT=3000
ENV STDOUT_SYNC=true
ENV SSL=false
# SECRET is generated at runtime by /onetime.sh (openssl rand -hex 32).
# This placeholder ensures the variable exists if the script is bypassed,
# but it must never be used as an actual secret. The value "CHANGEME" is
# specifically handled by OT::Config.raise_concerns to trigger a fast fail.
ENV SECRET=CHANGEME
ENV REDIS_URL=redis://localhost:6379/0
ENV RACK_ENV=production
ENV AUTH_ENABLED=false

EXPOSE 3000

# Lite stays as root: redis-server needs write access to /var/lib/redis
# and this variant is ephemeral/dev-only (not for production)
CMD ["/onetime.sh"]
