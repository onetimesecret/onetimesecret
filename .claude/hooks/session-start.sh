#!/bin/bash
set -euo pipefail

# Only run this hook in Claude Code on the web
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

echo "Setting up Ruby 3.4.7 environment..."

# Initialize rbenv
export PATH="$HOME/.rbenv/bin:$PATH"
if command -v rbenv &> /dev/null; then
  eval "$(rbenv init -)"
else
  echo "Warning: rbenv not found. Skipping Ruby setup."
  exit 1
fi

# Check if Ruby 3.4.7 is installed
if ! rbenv versions | grep -q "3.4.7"; then
  echo "Installing Ruby 3.4.7..."
  rbenv install 3.4.7
  echo "Ruby 3.4.7 installed successfully."
else
  echo "Ruby 3.4.7 is already installed."
fi

# Set Ruby 3.4.7 as the local version for this project
rbenv local 3.4.7

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
  echo "Installing project dependencies..."
  cd "$CLAUDE_PROJECT_DIR"
  bundle install
  echo "Dependencies installed successfully."
else
  echo "Warning: Gemfile not found. Skipping bundle install."
fi

echo "Ruby environment setup complete!"
