#!/bin/bash
set -euo pipefail

# Only run this hook in Claude Code on the web
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

# Initialize rbenv
export PATH="$HOME/.rbenv/bin:$PATH"
if command -v rbenv &> /dev/null; then
  eval "$(rbenv init -)"
else
  echo "SKIP: rbenv not found; skipping Ruby setup for this session."
  exit 0
fi

# Read the required Ruby version from .ruby-version file
if [ -f "$CLAUDE_PROJECT_DIR/.ruby-version" ]; then
  cd "$CLAUDE_PROJECT_DIR"
  RUBY_VERSION=$(cat .ruby-version)
  echo "Setting up Ruby version $RUBY_VERSION from .ruby-version file..."

  # Check if the specified Ruby version is installed
  if ! rbenv prefix "$RUBY_VERSION" &> /dev/null; then
    echo "Installing Ruby $RUBY_VERSION..."
    rbenv install --skip-existing "$RUBY_VERSION"
    echo "Ruby $RUBY_VERSION installed successfully."
  else
    echo "Ruby $RUBY_VERSION is already installed."
  fi

  # Set the Ruby version as the local version for this project
  rbenv local "$RUBY_VERSION"
else
  echo "Warning: .ruby-version file not found. Skipping Ruby setup."
  exit 1
fi

# Verify Ruby version
echo "Ruby version: $(ruby -v)"

# Export rbenv environment variables for the session
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> "$CLAUDE_ENV_FILE"
  echo 'eval "$(rbenv init -)"' >> "$CLAUDE_ENV_FILE"
fi

# Install bundler if not present
if ! gem list bundler -i &> /dev/null; then
  echo "Installing bundler..."
  gem install bundler --conservative
else
  echo "Bundler is already installed."
fi

# Install project dependencies if Gemfile exists
if [ -f "$CLAUDE_PROJECT_DIR/Gemfile" ]; then
  cd "$CLAUDE_PROJECT_DIR"
  echo "Checking project dependencies..."
  if ! bundle check &> /dev/null; then
    echo "Installing project dependencies..."
    bundle install
    echo "Dependencies installed successfully."
  else
    echo "Dependencies are already satisfied."
  fi
else
  echo "Warning: Gemfile not found. Skipping bundle install."
fi

echo "Ruby environment setup complete!"
