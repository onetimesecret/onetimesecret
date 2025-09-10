FROM ruby:3.4-alpine

# Install system dependencies
RUN apk add --no-cache \
    build-base \
    sqlite-dev \
    postgresql-dev \
    tzdata

# Set working directory
WORKDIR /app

# Copy Gemfile and install gems
COPY Gemfile Gemfile.lock ./
RUN bundle config --global frozen 1 && \
    bundle install --without development test

# Copy application code
COPY . .

# Create data directory for SQLite
RUN mkdir -p data

# Create log directory
RUN mkdir -p log

# Set environment
ENV RACK_ENV=production
ENV DATABASE_URL=sqlite:///app/data/auth.db

# Expose port
EXPOSE 9393

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:9393/health || exit 1

# Run database migrations on startup, then start server
CMD ["sh", "-c", "ruby migrate.rb && bundle exec puma -C puma.rb"]
