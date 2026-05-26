#!/usr/bin/env bash

# install-dev.sh
#
# Run this in any checkout/worktree to set up a local dev environment:
#   - Links shared dev resources from OTS_DEV_CONFIG
#   - Installs Ruby gems (bundle install)
#   - Installs Node packages (pnpm install)
#   - Installs the pre-commit/pre-push git hooks and their tool envs
#   - Cleans any pre-existing frontend build output (pnpm run clean)
#   - Points the Caddy webroot symlink at this checkout's public/web
#
# Intentionally does NOT run `pnpm run build`. Production assets in
# public/web cause confusion about which files are actually being served
# during development. `pnpm run clean` removes them so this checkout
# starts in a known, consistent state. The Vite dev server (via bin/dev)
# serves frontend assets directly.
#
# Idempotent: safe to re-run at any time.

set -euo pipefail

# Associative arrays (declare -A) require Bash 4+. macOS ships Bash 3.2,
# so users invoking `bash install-dev.sh` directly need a modern bash.
if (( BASH_VERSINFO[0] < 4 )); then
    echo "Error: This script requires Bash 4+ (found: $BASH_VERSION)"
    echo "  On macOS: brew install bash, then re-run"
    exit 1
fi

OTS_DEV_CONFIG="${OTS_DEV_CONFIG:-$HOME/.config/onetimesecret-dev}"

# Files/dirs to symlink: local_path -> shared_path
declare -A LINKS=(
    ["etc/config.yaml"]="config.yaml"
    ["etc/auth.yaml"]="auth.yaml"
    ["etc/billing.yaml"]="billing.yaml"
    ["etc/logging.yaml"]="logging.yaml"
    ["data"]="data"
    ["Procfile.dev"]="Procfile.dev"
    ["Procfile.volatile"]="Procfile.volatile"
    [".env.test"]=".env.test"
    ["etc/puma.rb"]="puma.rb"
)

# Optional: .env if you have one
if [[ -f "$OTS_DEV_CONFIG/.env" ]]; then
    LINKS[".env"]=".env"
fi

# Repair .env.sh if it's a symlink (historical git issue)
repair_env_sh() {
    if [[ -L ".env.sh" ]]; then
        echo "Repairing .env.sh (removing stale symlink)..."
        rm ".env.sh"
    fi

    if [[ ! -f ".env.sh" ]]; then
        echo "Creating .env.sh wrapper..."
        cat > ".env.sh" << 'EOF'
#!/usr/bin/env bash
# .env.sh

# A convenience wrapper so that .env is just a basic environment file
# that is compatible everywhere while still using the auto-export
# functionality the shell gods left for us.

# set -a enables automatic export mode. All variable assignments between
# here and set +a will be exported to child processes without needing
# 'export' keyword.
set -a

# Load the vars
[ -f .env ] && source .env

# Set +a restores default behavior where variables must be explicitly exported
set +a
EOF
        chmod +x ".env.sh"
        echo "Created and marked executable: .env.sh"
    fi
}

# Replace the Caddy webroot symlink with this checkout's public/web.
# Caddy is configured to serve from /var/www/public/web.
link_caddy_webroot() {
    if [[ ! -d "public/web" ]]; then
        echo "Skip: public/web missing from checkout (unexpected — it is tracked in the repo)"
        return
    fi

    # Canonical absolute path to this checkout's public/web.
    # pwd -P resolves any symlinks in the checkout path.
    local webroot
    webroot="$(cd public/web && pwd -P)"
    local caddy_link="/var/www/public/web"
    local caddy_parent="/var/www/public"

    if [[ ! -d "$caddy_parent" ]]; then
        echo "Skip: $caddy_parent does not exist — caddy webroot symlink not created"
        return
    fi

    # Don't clobber a real directory
    if [[ -e "$caddy_link" && ! -L "$caddy_link" ]]; then
        echo "Skip: $caddy_link exists and is not a symlink — not replacing"
        return
    fi

    # Already correctly linked? Compare resolved targets so we don't
    # relink (and prompt for sudo) when an equivalent relative or
    # non-canonical path is already in place.
    local prev_target=""
    if [[ -L "$caddy_link" ]]; then
        prev_target="$(readlink "$caddy_link")"
        local prev_resolved
        prev_resolved="$(readlink -f "$caddy_link" 2>/dev/null || echo "")"
        if [[ -n "$prev_resolved" && "$prev_resolved" == "$webroot" ]]; then
            echo "OK:   $caddy_link -> $webroot"
            return
        fi
    fi

    local run=""
    if [[ ! -w "$caddy_parent" ]]; then
        run="sudo"
        echo "Note: $caddy_parent requires elevated privileges (sudo)"
    fi

    # Atomic replace: ln -snf swaps the symlink in place without a
    # transient missing-link window between rm and ln.
    $run ln -snf "$webroot" "$caddy_link"

    if [[ -n "$prev_target" ]]; then
        echo "Link: $caddy_link -> $webroot"
        echo "      (was: $prev_target)"
    else
        echo "Link: $caddy_link -> $webroot"
    fi
}

# Install the pre-commit-managed git hooks and pre-build their isolated
# tool environments (rubocop, eslint, etc). Two configs are in play:
#   .pre-commit-config.yaml  -> pre-commit, prepare-commit-msg, post-* hooks
#                               (hook types come from default_install_hook_types)
#   .pre-push-config.yaml    -> pre-push hooks (separate config + hook type)
#
# --install-hooks pre-builds the hook environments so the first commit/push
# is not slowed down by a one-time dependency download. Hooks land in the
# common git dir, so a worktree forest shares one set — re-running here is
# idempotent.
install_git_hooks() {
    if [[ "${has_pre_commit}" != true ]]; then
        echo "Skip: pre-commit not installed — git hooks not configured"
        return
    fi

    # pre-commit refuses to install while core.hooksPath is set, since it
    # cannot guarantee git will invoke the hooks it writes. Surface the
    # one-line fix instead of aborting the whole script.
    local hooks_path
    hooks_path="$(git config --get core.hooksPath || true)"
    if [[ -n "$hooks_path" ]]; then
        echo ""
        echo ">>> WARNING: git hooks NOT installed"
        echo "    pre-commit will not install while core.hooksPath is set."
        echo "    Current value: $hooks_path"

        # If it merely pins git's own default hooks dir, clearing it
        # changes nothing — say so, so the user isn't left guessing.
        local default_hooks resolved_hooks
        default_hooks="$(cd "$(git rev-parse --git-path hooks)" 2>/dev/null && pwd -P || true)"
        resolved_hooks="$(cd "$hooks_path" 2>/dev/null && pwd -P || true)"
        if [[ -n "$default_hooks" && "$resolved_hooks" == "$default_hooks" ]]; then
            echo "    (This is git's default hooks directory. Clearing the setting for this local checkout is safe.)"
        fi

        echo "    To enable git hooks, clear it and re-run this script:"
        echo "      git config --unset-all core.hooksPath"
        echo ""
        return
    fi

    pre-commit install --install-hooks \
        || { echo "Warning: pre-commit hook install failed — git hooks not configured"; return; }
    pre-commit install --hook-type pre-push \
        --config .pre-push-config.yaml --install-hooks \
        || { echo "Warning: pre-push hook install failed"; return; }
}

link_resource() {
    local local_path="$1"
    local shared_name="$2"
    local target="$OTS_DEV_CONFIG/$shared_name"

    if [[ ! -e "$target" ]]; then
        # Clean up a dangling local symlink that pointed at this
        # (now-missing) shared target, so the checkout doesn't rot.
        if [[ -L "$local_path" && "$(readlink "$local_path")" == "$target" ]]; then
            rm "$local_path"
            echo "Removed: $local_path (target $target no longer exists)"
        else
            echo "Skip: $target does not exist"
        fi
        return
    fi

    # Already correctly linked
    if [[ -L "$local_path" && "$(readlink "$local_path")" == "$target" ]]; then
        echo "OK:   $local_path -> $target"
        return
    fi

    # Exists but not a symlink - don't clobber it
    if [[ -e "$local_path" && ! -L "$local_path" ]]; then
        echo "Skip: $local_path already exists (not a symlink)"
        return
    fi

    # Create parent directory if needed
    mkdir -p "$(dirname "$local_path")"

    # Atomic replace handles stale symlinks without a missing-link window.
    ln -snf "$target" "$local_path"
    echo "Link: $local_path -> $target"
}

# Sanity check
if [[ ! -f "Gemfile" ]]; then
    echo "Error: Run this from an OTS checkout root"
    exit 1
fi

# Required tools — fail fast with actionable guidance rather than
# erroring midway through bundle/pnpm install.
missing_required=()
command -v bundle &>/dev/null || missing_required+=("bundle  (Ruby Bundler):  https://bundler.io/")
command -v pnpm   &>/dev/null || missing_required+=("pnpm    (Node package manager):  https://pnpm.io/installation")
if (( ${#missing_required[@]} > 0 )); then
    echo "Error: Required tools missing:"
    for tool in "${missing_required[@]}"; do
        echo "  - $tool"
    done
    exit 1
fi

# Check for overmind (needed by bin/dev) — cache result for reuse below
has_overmind=true
if ! command -v overmind &>/dev/null; then
    has_overmind=false
    echo "Warning: Overmind not found — required by bin/dev"
    echo "  Install: https://github.com/DarthSim/overmind#installation"
    echo ""
fi

# Check for pre-commit (manages the git pre-commit/pre-push hooks) — cache
# result for reuse below. Not required to run the app, so warn and continue.
has_pre_commit=true
if ! command -v pre-commit &>/dev/null; then
    has_pre_commit=false
    echo "Warning: pre-commit not found — git pre-commit/pre-push hooks will not be installed"
    echo "  Install one of:"
    echo "    pipx install pre-commit        (recommended — isolated)"
    echo "    brew install pre-commit        (macOS)"
    echo "    pip install --user pre-commit"
    echo "  Docs: https://pre-commit.com"
    echo ""
fi

# Warn if shared config directory is absent
if [[ ! -d "$OTS_DEV_CONFIG" ]]; then
    echo "Warning: $OTS_DEV_CONFIG does not exist — config symlinks will be skipped"
    echo "  To enable shared dev config, create the directory and populate with:"
    for shared_name in "${LINKS[@]}"; do
        echo "    - $shared_name"
    done
    echo "    - .env  (optional)"
    echo "  Or point OTS_DEV_CONFIG at an existing directory."
    echo ""
fi

# Repair .env.sh before proceeding with other links
repair_env_sh

if [[ -d "$OTS_DEV_CONFIG" ]]; then
    echo "Linking dev resources from $OTS_DEV_CONFIG"
    echo "---"
    for local_path in "${!LINKS[@]}"; do
        link_resource "$local_path" "${LINKS[$local_path]}"
    done
fi

# Fall back to local copies when symlink sources are absent.
# Remove dangling symlinks first — [[ ! -e ]] is true for broken symlinks
# but cp will fail because the link path still exists in the directory.
if [[ ! -e "Procfile.dev" && -f "Procfile.dev.example" ]]; then
    [[ -L "Procfile.dev" ]] && rm "Procfile.dev"
    cp Procfile.dev.example Procfile.dev
    echo "Copy: Procfile.dev.example -> Procfile.dev (no symlink source)"
fi

if [[ ! -e "etc/puma.rb" && -f "etc/examples/puma.example.rb" ]]; then
    [[ -L "etc/puma.rb" ]] && rm "etc/puma.rb"
    cp etc/examples/puma.example.rb etc/puma.rb
    echo "Copy: etc/examples/puma.example.rb -> etc/puma.rb (no symlink source)"
fi

echo "---"
echo "Installing Ruby gems..."
bundle install

echo "---"
echo "Installing Node packages..."
pnpm install

echo "---"
echo "Installing git hooks (pre-commit, pre-push)..."
install_git_hooks

echo "---"
echo "Removing frontend build output (public/web/dist)..."
pnpm run clean

echo "---"
echo "Configuring Caddy webroot..."
link_caddy_webroot

echo "---"
echo "Setup complete."
echo ""
echo "  Note: pnpm run build was NOT run (intentional)."
echo "  Prior build output was removed; the Vite dev server serves assets directly."
echo ""
if [[ "${has_overmind}" = true ]]; then
    echo "To start:"
    echo "  bin/dev                  # standard"
    echo "  bin/dev --volatile       # ephemeral, no persistent data (useful in alternate checkouts)"
else
    echo "Install overmind to use bin/dev, or start services manually:"
    echo "  source .env.sh && bundle exec puma -C etc/puma.rb"
fi
