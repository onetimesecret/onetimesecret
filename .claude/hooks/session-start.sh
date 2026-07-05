#!/bin/bash
set -euo pipefail

# Only run this hook in Claude Code on the web
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

cd "$CLAUDE_PROJECT_DIR"

# --- rbenv / Ruby -----------------------------------------------------
#
# rbenv may be installed at RBENV_ROOT, $HOME/.rbenv, or /opt/rbenv
# depending on the base image; try each rather than assuming one.
RBENV_BIN="${RBENV_ROOT:-}/bin"
for candidate in "$RBENV_BIN" "$HOME/.rbenv/bin" "/opt/rbenv/bin"; do
  if [ -x "$candidate/rbenv" ]; then
    export PATH="$candidate:$PATH"
    break
  fi
done

if command -v rbenv &> /dev/null; then
  eval "$(rbenv init -)"
else
  echo "SKIP: rbenv not found; skipping Ruby setup for this session."
  exit 0
fi

if [ -f ".ruby-version" ]; then
  RUBY_VERSION=$(cat .ruby-version)
  if ! rbenv prefix "$RUBY_VERSION" &> /dev/null; then
    echo "Installing Ruby $RUBY_VERSION via rbenv (this can take a few minutes to compile)..."
    rbenv install --skip-existing "$RUBY_VERSION"
  fi
  echo "Ruby version: $(ruby -v)"
else
  echo "Warning: .ruby-version file not found. Using rbenv's current default: $(ruby -v)"
fi

# Persist rbenv on PATH for the rest of the session's shells.
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  {
    echo "export PATH=\"$(dirname "$(command -v rbenv)"):\$PATH\""
    echo 'eval "$(rbenv init -)"'
  } >> "$CLAUDE_ENV_FILE"
fi

# --- Ruby gems ----------------------------------------------------------

if [ -f "Gemfile" ]; then
  if command -v bundle &> /dev/null && bundle check &> /dev/null; then
    echo "Ruby gems already installed."
  else
    echo "Installing Ruby gems (bundle install)..."
    bundle install
  fi
else
  echo "Warning: Gemfile not found. Skipping bundle install."
fi

# --- Node / pnpm (frontend + Playwright e2e) -----------------------------

if [ -f "package.json" ]; then
  if command -v pnpm &> /dev/null; then
    if [ -d node_modules ]; then
      echo "node_modules already present."
    else
      echo "Installing Node dependencies (pnpm install)..."
      pnpm install
    fi
  else
    echo "Warning: pnpm not found. Skipping Node dependency install."
  fi
fi

echo "Ruby/Node environment setup complete!"
