#!/usr/bin/env bash

# install-dev.sh
#
# Run this in any checkout/worktree to set up a local dev environment:
#   - Links shared dev resources from OTS_DEV_CONFIG
#   - Installs Ruby gems (bundle install)
#   - Installs Node packages (pnpm install)
#
# Idempotent: safe to re-run at any time.

set -euo pipefail

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
# here and and set +a will be exported to child processes without needing
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

link_resource() {
    local local_path="$1"
    local shared_name="$2"
    local target="$OTS_DEV_CONFIG/$shared_name"

    # Validate target is within expected config directory (prevent path traversal)
    case "$target" in
        "$OTS_DEV_CONFIG"/*) ;;
        *) echo "Error: Invalid target path: $target"; return 1 ;;
    esac

    if [[ ! -e "$target" ]]; then
        echo "Skip: $target does not exist"
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

    # Remove stale symlink
    if [[ -L "$local_path" ]]; then
        rm "$local_path"
    fi

    # Create parent directory if needed
    mkdir -p "$(dirname "$local_path")"

    ln -s "$target" "$local_path"
    echo "Link: $local_path -> $target"
}

# Sanity check
if [[ ! -f "Gemfile" ]]; then
    echo "Error: Run this from an OTS checkout root"
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

# Warn if shared config directory is absent
if [[ ! -d "$OTS_DEV_CONFIG" ]]; then
    echo "Warning: $OTS_DEV_CONFIG does not exist — symlinks will be skipped"
    echo "  Create it and populate with config files, or set OTS_DEV_CONFIG to an existing directory"
    echo ""
fi

# Repair .env.sh before proceeding with other links
repair_env_sh

echo "Linking dev resources from $OTS_DEV_CONFIG"
echo "---"

for local_path in "${!LINKS[@]}"; do
    link_resource "$local_path" "${LINKS[$local_path]}"
done

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
if [[ "${has_overmind}" = true ]]; then
    echo "Done. Run 'bin/dev' to start."
else
    echo "Done. Install overmind to use 'bin/dev', or start services manually:"
    echo "  source .env.sh && bundle exec puma -C etc/puma.rb"
fi
